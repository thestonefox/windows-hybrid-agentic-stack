#Requires -Version 5.1
# Loaded by tts.ps1. Engine packages are trusted application code, not plugins
# fetched from arbitrary URLs. Installed ownership hashes gate script execution.
if (-not (Get-Command Get-StackSetupScript -ErrorAction Ignore)) {
    . (Join-Path $script:TtsRoot 'scripts/script-invocation.ps1')
}
. (Get-StackSetupScript (Join-Path $script:TtsRoot 'scripts/installation-state.ps1'))
. (Get-StackSetupScript (Join-Path $script:TtsRoot 'scripts/uninstall.ps1'))

function Get-TtsEngineState {
    $state = Read-StackInstallationState $script:TtsRoot
    if ($null -eq $state -or $state.Status -eq 'Uninstalled') { throw 'No active tracked speech installation. Run setup first.' }
    return $state
}

function Get-TtsDefaultEngine {
    $path = Join-Path $script:TtsServiceDir 'engines.json'
    if (Test-Path -LiteralPath $path) {
        $registry = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($registry.schemaVersion -ne 1) { throw 'Unsupported engine registry.' }
        return $registry.defaultEngine
    }
    return $script:TtsSettings.Engine
}

function Get-TtsInstalledRuntime {
    param([string]$Engine, $State)
    if (-not $Engine) { throw 'No default engine is configured. Use tts-engine-default ENGINE.' }
    $package = Get-TtsStrategy -Root $script:TtsRoot -Id $Engine
    $state = if ($State) { $State } else { Get-TtsEngineState }
    $record = @($state.TtsStrategies | Where-Object { $_.Id -ceq $Engine -and $_.Status -eq 'Installed' })
    if ($record.Count -ne 1) { throw "Engine '$Engine' is available but not installed. Use tts-engine-install $Engine." }
    $runtimePath = Resolve-TtsPackagePath $script:TtsRoot "tts/engines/$Engine/runtime.json"
    if (-not (Test-Path -LiteralPath $runtimePath)) {
        # Read schema-2 single-engine installations without moving their data.
        $runtimePath = Join-Path $script:TtsServiceDir 'runtime.json'
    }
    $runtime = Get-Content -LiteralPath $runtimePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($runtime.schemaVersion -ne 1 -or $runtime.engine -cne $Engine) { throw 'Engine runtime identity mismatch.' }
    foreach ($pair in @(@('environmentPath','EnvironmentPath'),@('modelsPath','ModelsPath'),@('voicesPath','VoicesPath'),@('device','Device'))) {
        if ($runtime.($pair[0]) -cne $record[0].Context.($pair[1])) { throw 'Engine runtime differs from its ownership record.' }
    }
    if ($runtime.backendPath -cne "tts/strategies/$Engine/$($package.Manifest.entrypoints.backend)" -or
        ($runtime.capabilities | ConvertTo-Json -Compress) -cne ($package.Manifest.capabilities | ConvertTo-Json -Compress)) { throw 'Engine runtime differs from its package.' }
    return [pscustomobject]@{Runtime=$runtime;Package=$package;Record=$record[0]}
}

function Get-TtsActiveEngine {
    $status = Get-TtsStatusResponse -AnyEngine
    if ($status) { return $status.engine }
    if (Test-Path -LiteralPath $script:TtsPidFile) {
        $saved = [IO.File]::ReadAllText($script:TtsPidFile).Trim()
        if ($saved -notmatch '^\d+$') { throw 'Invalid speech PID record.' }
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$saved" -ErrorAction Stop
        if ($process) {
            foreach ($record in @((Get-TtsEngineState).TtsStrategies)) {
                $python = Join-Path (Resolve-TtsPackagePath $script:TtsRoot $record.Context.EnvironmentPath) 'Scripts/python.exe'
                if ($process.ExecutablePath -ieq $python -and $process.CommandLine -and
                    $process.CommandLine.Contains(('"' + $script:TtsServiceFile + '"'))) { return $record.Id }
            }
            throw 'Saved speech PID belongs to an unverified process. No process was stopped.'
        }
    }
    return $null
}

function Set-TtsRuntimeSelection {
    param($Selection)
    $script:TtsRuntime = $Selection.Runtime
    $script:TtsPython = Join-Path (Resolve-TtsPackagePath $script:TtsRoot $Selection.Runtime.environmentPath) 'Scripts/python.exe'
    $script:TtsVoiceDirectory = Resolve-TtsPackagePath $script:TtsRoot $Selection.Runtime.voicesPath
    $script:TtsDevice = $Selection.Runtime.device
}

function Invoke-TtsEngineCommand {
    param([string]$Engine,[string]$Command,[hashtable]$Parameters=@{})
    $lock = Enter-StackOperationLock $script:TtsRoot
    try {
        # Legacy layouts keep their old interface until migrated by setup.
        if (-not $script:TtsRuntime -and -not $Engine -and -not (Test-Path -LiteralPath (Join-Path $script:TtsServiceDir 'engines.json'))) { & $Command @Parameters; return }
        $active = Get-TtsActiveEngine
        if ($Command -eq 'Invoke-TtsStopCore') {
            if ($Engine) { $null = Get-TtsInstalledRuntime $Engine }
            if ($Engine -and $active -and $Engine -cne $active) { throw "Engine '$Engine' is not the active engine ($active)." }
            Stop-StackOwnedSpeech $script:TtsRoot
            if (Test-Path -LiteralPath $script:TtsPidFile) { Remove-Item -LiteralPath $script:TtsPidFile -Force }
            Write-Host 'TTS stopped.'
            return
        }
        if (-not $Engine) { $Engine = if ($active) { $active } else { Get-TtsDefaultEngine } }
        $selection = Get-TtsInstalledRuntime $Engine
        if ($Command -in @('Invoke-TtsVoiceAddCore','Invoke-TtsVoiceRemoveCore','Invoke-TtsVoiceTestCore')) {
            if ($Parameters.Name -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$') { throw 'Invalid voice name.' }
        }
        if ($Command -in @('Invoke-TtsVoiceAddCore','Invoke-TtsVoiceRemoveCore')) {
            if (-not $selection.Runtime.capabilities.voiceCloning) { throw "$($selection.Package.Manifest.name) does not support reference-recording voice profiles." }
            if ($Parameters.Name -eq 'default') { throw 'default is the reserved built-in voice.' }
        }
        if ($Command -eq 'Invoke-TtsVoiceRemoveCore') {
            if ((Read-Host "Delete voice '$($Parameters.Name)' and its reference files? Type YES") -cne 'YES') { Write-Host 'Cancelled.'; return }
            $Parameters.Confirmed = $true
        }
        if ($Command -eq 'Invoke-TtsVoiceAddCore' -and $selection.Package.Manifest.voiceReference.transcriptRequired) {
            $transcript = [IO.Path]::ChangeExtension($Parameters.Path, '.txt')
            if (-not (Test-Path -LiteralPath $transcript -PathType Leaf)) { throw "$($selection.Package.Manifest.name) requires a matching UTF-8 transcript. Expected: $transcript" }
            $info = Get-Item -LiteralPath $transcript
            if ($info.Length -gt 16000) { throw 'Reference transcript exceeds 16,000 bytes.' }
            $text = [IO.File]::ReadAllText($transcript, (New-Object Text.UTF8Encoding($false,$true))).Trim()
            if (-not $text -or $text.Length -gt 4000) { throw 'Reference transcript must contain 1-4000 characters.' }
        }
        if ($Command -eq 'Invoke-TtsVoiceAddCore') {
            if ([IO.Path]::GetExtension($Parameters.Path) -ine '.wav' -or -not (Test-Path -LiteralPath $Parameters.Path -PathType Leaf)) { throw "Reference WAV not found: $($Parameters.Path)" }
        }
        if ($active -and $active -cne $Engine) {
            Write-Host "Switching speech engine: $active -> $Engine"
            Stop-StackOwnedSpeech -Root $script:TtsRoot
            if (Test-Path -LiteralPath $script:TtsPidFile) { Remove-Item -LiteralPath $script:TtsPidFile -Force }
        }
        Set-TtsRuntimeSelection $selection
        & $Command @Parameters
    }
    finally { $lock.ReleaseMutex(); $lock.Dispose() }
}

function Write-TtsOwnedData {
    param([string]$Relative,[string]$Text,$State)
    $path = Resolve-TtsPackagePath $script:TtsRoot $Relative
    $owned = @($State.Files | Where-Object Path -ceq $Relative)
    if (Test-Path -LiteralPath $path) {
        if ($owned.Count -ne 1 -or (Get-StackFileSHA256 $path) -cne $owned[0].SHA256) { throw "Engine settings are unowned or edited; preserved: $Relative" }
    }
    $temporary = $path + '.tmp.' + [guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($temporary,$Text,(New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $path -Force
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
    $State.Files = @($State.Files | Where-Object Path -cne $Relative) + @([pscustomobject]@{Path=$Relative;SHA256=(Get-StackFileSHA256 $path)})
}

function Set-TtsDefaultEngine {
    param([AllowNull()][string]$Engine,$State)
    if ($Engine) {
        $selection = Get-TtsInstalledRuntime $Engine
        Write-TtsOwnedData 'tts/runtime.json' ($selection.Runtime | ConvertTo-Json -Depth 8) $State
        Write-StackInstallationState $script:TtsRoot $State
    }
    $json = [pscustomobject]@{schemaVersion=1;defaultEngine=$(if ($Engine) { $Engine } else { $null })} | ConvertTo-Json
    Write-TtsOwnedData 'tts/engines.json' $json $State
    Write-StackInstallationState $script:TtsRoot $State
}

function tts-engine-list {
    $state = Get-TtsEngineState
    $default = Get-TtsDefaultEngine
    $active = Get-TtsActiveEngine
    $rows = foreach ($package in @(Get-TtsStrategies $script:TtsRoot)) {
        $record = @($state.TtsStrategies | Where-Object Id -ceq $package.Manifest.id)
        [pscustomobject]@{Engine=$package.Manifest.id;Status=$(if ($record.Count) { $record[0].Status } else { 'Available' });Default=($default -ceq $package.Manifest.id);Active=($active -ceq $package.Manifest.id)}
    }
    $rows | Format-Table -AutoSize | Out-String -Stream | ForEach-Object { Write-Host $_ }
}

function tts-engine-default {
    param([Parameter(Position=0)][string]$Engine)
    if (-not $Engine) { Write-Output (Get-TtsDefaultEngine); return }
    $lock = Enter-StackOperationLock $script:TtsRoot
    try {
        $state = Get-TtsEngineState
        Set-TtsDefaultEngine $Engine $state
        Write-Host "Default speech engine: $Engine (the running engine is unchanged)."
    }
    finally { $lock.ReleaseMutex(); $lock.Dispose() }
}

function tts-engine-install {
    param([Parameter(Position=0,Mandatory=$true)][string]$Engine,[ValidateSet('auto','cpu','cuda')][string]$Device='auto',[switch]$Yes)
    $lock = Enter-StackOperationLock $script:TtsRoot
    $session = $null
    $succeeded = $false
    try {
        $package = Get-TtsStrategy $script:TtsRoot $Engine
        $state = Get-TtsEngineState
        if (Get-TtsActiveEngine) { throw 'Stop speech with tts-stop before installing or repairing an engine.' }
        Write-Host "Engine: $($package.Manifest.name); licence: $($package.Manifest.license)"
        foreach ($model in $package.Manifest.models) { Write-Host "Model download: $($model.source); licence: $($model.license)" }
        if (-not $Yes -and (Read-Host "Install $($package.Manifest.name)? Type YES") -cne 'YES') { Write-Host 'Cancelled.'; return }
        Invoke-StackSetupScript -Path (Join-Path $script:TtsRoot 'scripts/check-prerequisites.ps1') -Arguments @{Voice=$true;StrategyManifestJson=($package.Manifest | ConvertTo-Json -Depth 12 -Compress)}
        if ($LASTEXITCODE -ne 0) { throw 'Speech prerequisites are missing.' }
        $default = Get-TtsDefaultEngine
        $session = Start-StackInstallationTracking $script:TtsRoot
        Invoke-StackSetupScript -Path (Join-Path $script:TtsServiceDir 'install-tts.ps1') -Arguments @{InstallPath=$script:TtsRoot;Device=$Device;TtsEngine=$Engine}
        if ($LASTEXITCODE -ne 0) { throw 'Engine installation failed. Partial files remain tracked for retry or uninstall.' }
        $succeeded = $true
    }
    finally {
        try {
            if ($session) {
                Complete-StackInstallationTracking $session $succeeded
                if ($succeeded -and -not $default) { Set-TtsDefaultEngine $Engine (Get-TtsEngineState) }
            }
        }
        finally { $lock.ReleaseMutex(); $lock.Dispose() }
    }
}

function tts-engine-uninstall {
    param([Parameter(Position=0,Mandatory=$true)][string]$Engine,[string]$DefaultEngine,[switch]$Apply,[switch]$Yes)
    $lock = Enter-StackOperationLock $script:TtsRoot
    try {
        $state = Get-TtsEngineState
        $records = @($state.TtsStrategies | Where-Object Id -ceq $Engine)
        if ($records.Count -ne 1) { throw "Engine '$Engine' is not installed." }
        $default = Get-TtsDefaultEngine
        $others = @($state.TtsStrategies | Where-Object { $_.Id -cne $Engine -and $_.Status -eq 'Installed' })
        if ($DefaultEngine) {
            if ($default -cne $Engine) { throw '--default-engine is only needed when removing the default engine.' }
            if ($DefaultEngine -ceq $Engine) { throw 'The replacement default cannot be the engine being removed.' }
            $null = Get-TtsInstalledRuntime $DefaultEngine
        }
        if ($default -ceq $Engine -and $others.Count -and -not $DefaultEngine) { throw 'Choose a replacement with --default-engine ENGINE before removing the default.' }
        $prefixes = @(($records[0].Context.EnvironmentPath.TrimEnd('/')+'/'), ($records[0].Context.ModelsPath.TrimEnd('/')+'/'), "tts/engines/$Engine/")
        $plan = Get-StackUninstallPlan $script:TtsRoot -ShowProgress
        $selectedFiles = @($plan.DeleteFiles | Where-Object { $path=$_.Path; @($prefixes | Where-Object { $path.StartsWith($_,[StringComparison]::Ordinal) }).Count -gt 0 })
        Write-Host "Engine: $Engine; remove unchanged files: $($selectedFiles.Count). Personal voices and the strategy catalog remain."
        if (-not $Apply) { Write-Host 'Preview only. Use --apply to remove this engine.'; return }
        if (-not $Yes -and (Read-Host "Remove $Engine? Type YES") -cne 'YES') { Write-Host 'Cancelled.'; return }
        if ((Get-TtsActiveEngine) -ceq $Engine) { Stop-StackOwnedSpeech $script:TtsRoot }
        $hook = @(Get-TtsInstalledHooks $script:TtsRoot ([pscustomobject]@{TtsStrategies=$records}))[0]
        Invoke-TtsVerifiedHook $hook.Path $hook.SHA256 @{Context=$hook.Context}
        # Recompute after the hook and recheck every file immediately before removal.
        $plan = Get-StackUninstallPlan $script:TtsRoot -ShowProgress
        $selectedFiles = @($plan.DeleteFiles | Where-Object { $path=$_.Path; @($prefixes | Where-Object { $path.StartsWith($_,[StringComparison]::Ordinal) }).Count -gt 0 })
        $progress = New-StackOperationProgress "Removing engine $Engine" -Enabled
        $processed = 0
        foreach ($file in $selectedFiles) {
            $path = Resolve-TtsPackagePath $script:TtsRoot $file.Path
            if ((Get-StackFileSHA256 $path -Progress $progress) -cne $file.SHA256) { throw "Engine file changed during removal: $($file.Path)" }
            Remove-Item -LiteralPath $path -Force
            $processed++
            Write-StackOperationProgress $progress -Completed $processed -Total $selectedFiles.Count
        }
        Write-StackOperationProgress $progress -Completed $processed -Total $selectedFiles.Count -Force
        $removed = @($selectedFiles.Path)
        $state.Files = @($state.Files | Where-Object { $removed -cnotcontains $_.Path })
        $state.TtsStrategies = @($state.TtsStrategies | Where-Object Id -cne $Engine)
        Write-StackInstallationState $script:TtsRoot $state
        if ($default -ceq $Engine) { Set-TtsDefaultEngine $DefaultEngine $state }
        foreach ($relative in @($state.Directories | Sort-Object Length -Descending)) {
            if (@($prefixes | Where-Object { ($relative+'/').StartsWith($_,[StringComparison]::Ordinal) }).Count) {
                $path = Resolve-TtsPackagePath $script:TtsRoot $relative
                if ((Test-Path -LiteralPath $path) -and -not @(Get-ChildItem -LiteralPath $path -Force).Count) { Remove-Item -LiteralPath $path }
            }
        }
        Write-Host "Engine removed: $Engine. Modified/unknown files and personal voices are preserved."
    }
    finally { $lock.ReleaseMutex(); $lock.Dispose() }
}

function tts-start { param([string]$Engine) Invoke-TtsEngineCommand $Engine 'Invoke-TtsStartCore' }
function tts-stop { param([string]$Engine) Invoke-TtsEngineCommand $Engine 'Invoke-TtsStopCore' }
function tts-status {
    param([string]$Engine)
    Write-Host "Default engine: $(Get-TtsDefaultEngine)"
    $status = Get-TtsStatusResponse -AnyEngine
    $active = if ($status) { $status.engine } else { $null }
    Write-Host "Active engine:  $active"
    $state = $null
    if ($Engine -or $active) { $state = Read-StackInstallationState $script:TtsRoot -ReadOnly }
    if ($Engine) { $null = Get-TtsInstalledRuntime $Engine -State $state }
    if ($Engine -and $Engine -cne $active) { Write-Host "Requested engine: $Engine (stopped)"; return }
    if ($active) { Set-TtsRuntimeSelection (Get-TtsInstalledRuntime $active -State $state) }
    Invoke-TtsStatusCore -Status $status -AlreadyChecked
}
function tts-say { param([Parameter(Position=0,Mandatory=$true)][string]$Text,[string]$Voice=$script:TtsDefaultVoice,[string]$Engine) Invoke-TtsEngineCommand $Engine 'Invoke-TtsSayCore' @{Text=$Text;Voice=$Voice} }
function tts-voice-list { param([string]$Engine) Invoke-TtsEngineCommand $Engine 'Invoke-TtsVoiceListCore' }
function tts-voice-add { param([Parameter(Position=0,Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Name,[string]$Engine) Invoke-TtsEngineCommand $Engine 'Invoke-TtsVoiceAddCore' @{Path=$Path;Name=$Name} }
function tts-voice-remove { param([Parameter(Position=0,Mandatory=$true)][string]$Name,[string]$Engine) Invoke-TtsEngineCommand $Engine 'Invoke-TtsVoiceRemoveCore' @{Name=$Name} }
function tts-voice-test { param([Parameter(Position=0,Mandatory=$true)][string]$Name,[string]$Engine) Invoke-TtsEngineCommand $Engine 'Invoke-TtsVoiceTestCore' @{Name=$Name} }
