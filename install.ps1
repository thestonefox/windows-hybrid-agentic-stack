#Requires -Version 5.1

<#
.SYNOPSIS
    Windows Hybrid Agentic Stack installer.

.DESCRIPTION
    Loads configuration, selects components, checks prerequisites
    and installs cloud agents, local agents and selected speech engines.

    Chatterbox automatically selects CPU or CUDA PyTorch.
    External prerequisites must already be installed.

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -Cloud

.EXAMPLE
    .\install.ps1 -Local

.EXAMPLE
    .\install.ps1 -Voice

.EXAMPLE
    .\install.ps1 -Cloud -Local -Voice

.EXAMPLE
    .\install.ps1 -Check

.EXAMPLE
    .\install.ps1 -Check -Voice -TtsEngine piper-tts
#>

[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Core,
    [switch]$Cloud,
    [switch]$Local,
    [switch]$Voice,
    [string]$TtsEngine,
    [string]$LocalModels,
    [string]$DefaultLocalModel,
    [ValidateSet('cloud','local')][string]$DefaultLocation,
    [switch]$Yes,
    [string]$InstallPath,
    [bool]$PersistCommandPath = $true
)

$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
if (-not ($null -ne ('WindowsHybridAgenticStack.SetupRuntime' -as [type]) -and [WindowsHybridAgenticStack.SetupRuntime]::IsHosting)) {
    . (Join-Path $repoRoot 'scripts\script-invocation.ps1')
}

$configScript = Join-Path $repoRoot 'scripts\config.ps1'
$prerequisiteScript = Join-Path $repoRoot 'scripts\check-prerequisites.ps1'
$agentSetupScript = Join-Path $repoRoot 'scripts\setup-agents.ps1'
$commandInstallScript = Join-Path $repoRoot 'scripts\install-agent-commands.ps1'
$ttsInstallScript = Join-Path $repoRoot 'tts\install-tts.ps1'
$registrationHelper = Join-Path $repoRoot 'scripts\command-registration.ps1'
$trackingSession = $null
$installationSucceeded = $false
$operationLock = $null

function Read-YesNo {
    param(
        [string]$Question,
        [bool]$Default = $true
    )

    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }

    while ($true) {
        $answer = Read-Host "$Question $suffix"

        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $Default
        }

        switch ($answer.Trim().ToLowerInvariant()) {
            'y'   { return $true }
            'yes' { return $true }
            'n'   { return $false }
            'no'  { return $false }
            default {
                Write-Host 'Please enter Y or N.' `
                    -ForegroundColor Yellow
            }
        }
    }
}

function Copy-StackFile {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        return
    }

    $directory = Split-Path -Parent $Destination

    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force |
            Out-Null
    }

    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        $sourceHash = (
            Get-FileHash -LiteralPath $Source -Algorithm SHA256
        ).Hash

        $destinationHash = (
            Get-FileHash -LiteralPath $Destination -Algorithm SHA256
        ).Hash

        if ($sourceHash -eq $destinationHash) {
            Write-Host "Unchanged: $Destination"
            return
        }

        $backup = "$Destination.bak.$(
            [guid]::NewGuid().ToString('N')
        )"

        Copy-Item -LiteralPath $Destination -Destination $backup
        Write-Host "Backup: $backup"
    }
    elseif (Test-Path -LiteralPath $Destination) {
        throw "Destination is not a file: $Destination"
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    Write-Host "Installed: $Destination"
}

try {
    Write-Host ''
    Write-Host 'Windows Hybrid Agentic Stack'
    Write-Host '============================'
    Write-Host ''

    foreach ($file in @($configScript, $prerequisiteScript, $registrationHelper,
        (Join-Path $repoRoot 'scripts\command-host.cs'),
        (Join-Path $repoRoot 'scripts\configuration.ps1'),
        (Join-Path $repoRoot 'scripts\installation-state.ps1'),
        (Join-Path $repoRoot 'scripts\uninstall.ps1'),
        (Join-Path $repoRoot 'uninstall.ps1'),
        (Join-Path $repoRoot 'scripts\profile-loader.ps1'))) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Required project script missing: $file"
        }
    }

    Invoke-StackSetupScript -Path $configScript -Arguments @{Validate=$true}

    if ($LASTEXITCODE -ne 0) {
        throw 'Configuration validation failed.'
    }

    $configJson = Invoke-StackSetupScript -Path $configScript -Arguments @{Show=$true}

    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to load configuration.'
    }

    $config = ($configJson | Out-String) | ConvertFrom-Json

    if ($null -eq $config) {
        throw 'Configuration could not be parsed.'
    }

    . (Get-StackSetupScript (Join-Path $repoRoot 'tts\strategy-management.ps1'))
    if ($Check -and -not $Core -and -not ($Cloud -or $Local -or $Voice)) {
        $Cloud = $true
        $Local = $true
        $Voice = $true
    }
    if ($TtsEngine -and -not $Voice) { throw '-TtsEngine requires -Voice.' }
    $requestedEngines = @()
    if ($TtsEngine) { $requestedEngines = @($TtsEngine.Split(',') | ForEach-Object { $_.Trim() }); $config.tts.engine = $requestedEngines[0] }
    $explicitSelection = $Core -or $Cloud -or $Local -or $Voice

    if (-not $explicitSelection) {
        Write-Host ''
        Write-Host 'Select components to install:'
        Write-Host ''

        $Cloud = Read-YesNo `
            -Question 'Cloud agents (OpenCode provider of your choice)?' `
            -Default ([bool]$config.agents.cloud.enabled)

        $Local = Read-YesNo `
            -Question 'Local agents (OpenCode + Ollama)?' `
            -Default ([bool]$config.agents.local.enabled)

        $Voice = Read-YesNo `
            -Question 'Voice output?' `
            -Default ([bool]$config.tts.enabled)
    }

    if (-not ($Core -or $Cloud -or $Local -or $Voice)) {
        throw 'No components selected.'
    }
    if (($LocalModels -or $DefaultLocalModel) -and -not $Local) { throw 'Local model selection requires -Local.' }
    if ($DefaultLocalModel) { $config.agents.local.model = $DefaultLocalModel }
    $localModelSelection = if ($LocalModels) { @($LocalModels.Split(',') | ForEach-Object { $_.Trim() }) } else { @([string]$config.agents.local.model) }
    if ($Local) {
        if ($localModelSelection -notcontains $config.agents.local.model) { throw 'The default local model must be in -LocalModels.' }
        if (@($localModelSelection | Select-Object -Unique).Count -ne $localModelSelection.Count) { throw 'Duplicate local model selection.' }
        foreach ($modelId in $localModelSelection) {
            if ($modelId -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9._/-]*(?::[a-zA-Z0-9._-]+)?$' -or $modelId -match '(^|/)\.\.?(/|$)') { throw "Invalid Ollama model: $modelId" }
        }
    }

    if ($Cloud -or $Local) {
        foreach ($file in @($agentSetupScript, $commandInstallScript)) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                throw "Required project script missing: $file"
            }
        }
    }

    if ($Voice) {
        if (-not (Test-Path -LiteralPath $ttsInstallScript -PathType Leaf)) {
            throw "Required TTS installer missing: $ttsInstallScript"
        }

        $available = @(Get-TtsStrategies -Root $repoRoot)
        if (-not $Check -and -not $Yes -and -not $TtsEngine -and
            -not (Test-Path -LiteralPath (Join-Path $repoRoot 'config/config.json'))) {
            $requestedEngines = @((Select-TtsEngine -Manifests @($available | ForEach-Object { $_.Manifest }) -Default $config.tts.engine).Split(','))
            $config.tts.engine = $requestedEngines[0]
        }
        if (-not $requestedEngines.Count) { $requestedEngines = @($config.tts.engine) }
        if (@($requestedEngines | Select-Object -Unique).Count -ne $requestedEngines.Count) { throw 'Duplicate engine selection.' }
        $selectedPackages = @()
        foreach ($engineId in $requestedEngines) {
            $ttsPackage = Get-TtsStrategy -Root $repoRoot -Id $engineId
            if ($config.tts.device -ne 'auto' -and $config.tts.device -notin $ttsPackage.Manifest.devices) { throw 'Selected strategy does not support this device.' }
            Write-Host "TTS package: $($ttsPackage.Manifest.name) $($ttsPackage.Manifest.version); licence: $($ttsPackage.Manifest.license)"
            foreach ($model in $ttsPackage.Manifest.models) {
                $pin = if ($model.revision) { "revision $($model.revision)" } else { "SHA256 $($model.sha256)" }
                Write-Host "Model download: $($model.source), $pin; licence: $($model.license)"
            }
            $selectedPackages += $ttsPackage
        }
        $ttsPackage = $selectedPackages[0]
    }

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $InstallPath = [string]$config.installation.directory
    }

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $InstallPath = Join-Path $HOME 'AI\WindowsHybridAgenticStack'
    }

    $InstallPath = [Environment]::ExpandEnvironmentVariables(
        $InstallPath
    )

    if ($InstallPath -match '^\$HOME(?=[\\/]|$)') {
        $InstallPath = $HOME + $InstallPath.Substring(5)
    }

    $InstallPath = $ExecutionContext.SessionState.Path.
        GetUnresolvedProviderPathFromPSPath($InstallPath)

    Write-Host ''
    Write-Host $(if ($Check) { 'Prerequisite check selection' } else { 'Installation plan' })
    Write-Host '-----------------'
    Write-Host "Directory:    $InstallPath"
    Write-Host "Cloud agents: $Cloud"
    Write-Host "Local agents: $Local"
    Write-Host "Voice output: $Voice"

    if ($Cloud) {
        Write-Host ('Cloud model:  ' + $(if ($config.agents.cloud.model) { $config.agents.cloud.model } else { 'OpenCode default' }))
    }

    if ($Local) {
        Write-Host "Local model:  $($config.agents.local.model)"
        Write-Host "Context:      $($config.agents.local.contextSize) tokens"
    }

    if ($Voice) {
        Write-Host "TTS engine:   $($config.tts.engine)"
        Write-Host "TTS device:   $($config.tts.device)"
    }

    Write-Host ''

    if (-not $Check -and -not $Yes -and -not (Read-YesNo -Question 'Continue with installation?')) {
        Write-Host 'Installation cancelled. No changes made.'
        exit 0
    }

    Write-Host ''
    Write-Host 'Checking prerequisites...'
    Write-Host ''

    $checkArguments = @{
        Core = [bool]$Core
        Cloud = [bool]$Cloud
        Local = [bool]$Local
        Voice = [bool]$Voice
    }

    if ($Voice) { $checkArguments.StrategyManifestJson = ($ttsPackage.Manifest | ConvertTo-Json -Depth 12 -Compress) }
    Invoke-StackSetupScript -Path $prerequisiteScript -Arguments $checkArguments
    if ($LASTEXITCODE -eq 0 -and $Voice) {
        foreach ($additional in @($selectedPackages | Select-Object -Skip 1)) {
            Invoke-StackSetupScript -Path $prerequisiteScript -Arguments @{Voice=$true;StrategyManifestJson=($additional.Manifest | ConvertTo-Json -Depth 12 -Compress)}
            if ($LASTEXITCODE -ne 0) { break }
        }
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Host 'Required prerequisites are missing.' `
            -ForegroundColor Red
        Write-Host 'Follow the installation guide in docs/installation.md.'
        Write-Host 'Then rerun this installer.'
        exit 1
    }

    Write-Host ''
    Write-Host 'Prerequisite checks completed.' `
        -ForegroundColor Green

    if ($Check) {
        Write-Host 'Check only. No changes made.'
        exit 0
    }

    . (Get-StackSetupScript (Join-Path $repoRoot 'scripts\installation-state.ps1'))
    $trackingArguments = @{ InstallPath = $InstallPath }
    if ($Local) {
        $safeModel = ([string]$config.agents.local.model).ToLowerInvariant() -replace '[^a-z0-9-]', '-'
        $trackingArguments.ManagedModelName = 'whas-' + $safeModel.Trim('-') + '-ctx' + $config.agents.local.contextSize
        $trackingArguments.ManagedModelNames = @($localModelSelection) + @($localModelSelection | ForEach-Object { 'whas-' + (($_.ToLowerInvariant() -replace '[^a-z0-9-]', '-').Trim('-')) + '-ctx' + $config.agents.local.contextSize })
    }
    $operationLock = Enter-StackOperationLock $InstallPath
    $trackingSession = Start-StackInstallationTracking @trackingArguments
    foreach ($relative in @('uninstall.ps1','scripts\uninstall.ps1','scripts\installation-state.ps1','scripts\command-registration.ps1','scripts\script-invocation.ps1','scripts\configuration.ps1','scripts\agent-strategies.ps1','scripts\whas.ps1','tts\strategy-management.ps1','scripts\check-prerequisites.ps1')) {
        Copy-StackFile -Source (Join-Path $repoRoot $relative) -Destination (Join-Path $InstallPath $relative)
    }
    foreach($relative in @('config/defaults.json','scripts/agent-commands.ps1','tts/tts.ps1','tts/install-tts.ps1','tts/tts_service.py','tts/engine-management.ps1','tts/strategy.schema.json')) {
        Copy-StackFile -Source (Join-Path $repoRoot $relative) -Destination (Join-Path $InstallPath $relative)
    }
    foreach($package in @(Get-TtsStrategies $repoRoot)) {
        foreach($asset in $package.Files) {
            $relative="tts/strategies/$($package.Manifest.id)/$asset"
            Copy-StackFile -Source (Join-Path $repoRoot $relative) -Destination (Join-Path $InstallPath $relative)
        }
    }
    $engineRegistryPath=Join-Path $InstallPath 'tts/engines.json'
    if(-not $Voice -and -not (Test-Path -LiteralPath $engineRegistryPath)) {
        [IO.File]::WriteAllText($engineRegistryPath,'{"schemaVersion":1,"defaultEngine":null}',(New-Object Text.UTF8Encoding($false)))
    }
    . (Get-StackSetupScript (Join-Path $repoRoot 'scripts/agent-strategies.ps1')) -InstallPath $repoRoot
    foreach ($strategy in Get-WhasAgentStrategies) {
        foreach ($asset in $strategy.Manifest.files) {
            $relative = "agents/strategies/$($strategy.Manifest.id)/$asset"
            Copy-StackFile -Source (Join-Path $repoRoot $relative) -Destination (Join-Path $InstallPath $relative)
        }
    }

    if ($Cloud -or $Local) {
        Write-Host ''
        Write-Host 'Configuring OpenCode agents...'
        Write-Host ''

        $setupCloudModel = [string]$config.agents.cloud.model
        if ($setupCloudModel -and $setupCloudModel -notmatch '/') {
            $setupCloudModel = "$($config.agents.cloud.provider)/$setupCloudModel"
        }
        $setupArguments = @{
            Yes = [bool]$Yes
            Cloud = [bool]$Cloud
            Local = [bool]$Local
            InstallPath = $InstallPath
            CloudModel = $setupCloudModel
            LocalModel = [string]$config.agents.local.model
            LocalContextSize = [int]$config.agents.local.contextSize
        }

        Invoke-StackSetupScript -Path $agentSetupScript -Arguments $setupArguments

        if ($LASTEXITCODE -ne 0) {
            throw 'OpenCode agent setup failed.'
        }
        foreach ($additionalModel in @($localModelSelection | Where-Object { $_ -cne $config.agents.local.model })) {
            $extra = $setupArguments.Clone()
            $extra.Cloud = $false
            $extra.LocalModel = $additionalModel
            Invoke-StackSetupScript -Path $agentSetupScript -Arguments $extra
            if ($LASTEXITCODE -ne 0) { throw "Additional local model setup failed: $additionalModel" }
        }

        Write-Host ''
        Write-Host 'Installing PowerShell agent commands...'
        Write-Host ''

        Invoke-StackSetupScript -Path $commandInstallScript -Arguments @{InstallPath=$InstallPath;PersistPath=$PersistCommandPath}

        if ($LASTEXITCODE -ne 0) {
            throw 'PowerShell agent command installation failed.'
        }

    }

    if ($Voice) {
        Write-Host ''
        Write-Host "Installing TTS strategy: $($config.tts.engine)"
        Write-Host ''

        foreach ($engineId in $requestedEngines) {
            Invoke-StackSetupScript -Path $ttsInstallScript -Arguments @{InstallPath=$InstallPath;Device=[string]$config.tts.device;TtsEngine=$engineId}
            if ($LASTEXITCODE -ne 0) { throw "TTS strategy installation failed: $engineId." }
        }
        $selectedRuntime = Join-Path $InstallPath "tts/engines/$($config.tts.engine)/runtime.json"
        if (Test-Path -LiteralPath $selectedRuntime) {
            Copy-Item -LiteralPath $selectedRuntime -Destination (Join-Path $InstallPath 'tts/runtime.json') -Force
            $engineRegistry = [pscustomobject]@{schemaVersion=1;defaultEngine=$config.tts.engine}
            [IO.File]::WriteAllText((Join-Path $InstallPath 'tts/engines.json'), ($engineRegistry | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
        }

        # Keep the installed runtime configuration alongside TTS.
        # Existing files are preserved with a backup on changes.
        Copy-StackFile `
            -Source (Join-Path $repoRoot 'config\defaults.json') `
            -Destination (Join-Path $InstallPath 'config\defaults.json')

        Copy-StackFile `
            -Source (Join-Path $repoRoot 'config\config.json') `
            -Destination (Join-Path $InstallPath 'config\config.json')

        . (Get-StackSetupScript $registrationHelper)
        Install-StackCommandRegistration -InstallPath $InstallPath -PersistPath $PersistCommandPath
        . (Get-StackSetupScript (Join-Path $repoRoot 'scripts\profile-loader.ps1'))
        Remove-StackLegacyProfileLoader
    }

        # Runtime agent commands read the installed configuration.
        # Keep the source model in the repository configuration but
        # select the generated context-enabled model at runtime.
        if ($Local) {
            $modelName = [string]$config.agents.local.model
            $contextSize = [int]$config.agents.local.contextSize
            $safeModelName = ($modelName.ToLowerInvariant() -replace '[^a-z0-9-]', '-').Trim('-')
            $runtimeModel = "whas-$safeModelName-ctx$contextSize"
            $runtimeConfigPath = Join-Path $InstallPath 'config\config.json'
            $runtimeConfigDirectory = Split-Path -Parent $runtimeConfigPath
            if (-not (Test-Path -LiteralPath $runtimeConfigDirectory)) {
                New-Item -ItemType Directory -Path $runtimeConfigDirectory -Force | Out-Null
            }
            $runtimeConfig = if (Test-Path -LiteralPath $runtimeConfigPath -PathType Leaf) {
                Get-Content -LiteralPath $runtimeConfigPath -Raw | ConvertFrom-Json
            }
            else { [pscustomobject]@{} }
            if ($runtimeConfig -isnot [pscustomobject]) {
                throw 'Installed runtime configuration is not a JSON object.'
            }
            if ($null -eq $runtimeConfig.PSObject.Properties['agents']) {
                $runtimeConfig | Add-Member -NotePropertyName agents -NotePropertyValue ([pscustomobject]@{})
            }
            if ($null -eq $runtimeConfig.agents.PSObject.Properties['local']) {
                $runtimeConfig.agents | Add-Member -NotePropertyName local -NotePropertyValue ([pscustomobject]@{})
            }
            if ($null -eq $runtimeConfig.agents.local.PSObject.Properties['model']) {
                $runtimeConfig.agents.local | Add-Member -NotePropertyName model -NotePropertyValue $runtimeModel
            }
            else { $runtimeConfig.agents.local.model = $runtimeModel }
            $runtimeJson = $runtimeConfig | ConvertTo-Json -Depth 50
            $runtimeOriginal = if (Test-Path -LiteralPath $runtimeConfigPath -PathType Leaf) {
                Get-Content -LiteralPath $runtimeConfigPath -Raw
            }
            else { '' }
            if ($runtimeOriginal.Trim() -cne $runtimeJson.Trim()) {
                if (Test-Path -LiteralPath $runtimeConfigPath -PathType Leaf) {
                    $runtimeBackup = "$runtimeConfigPath.bak.$([guid]::NewGuid().ToString('N'))"
                    Copy-Item -LiteralPath $runtimeConfigPath -Destination $runtimeBackup
                }
                [System.IO.File]::WriteAllText(
                    $runtimeConfigPath, $runtimeJson,
                    (New-Object System.Text.UTF8Encoding($false))
                )
            }
            Write-Host "Runtime local model: $runtimeModel"
        }
    Write-Host ''
    if ($Core -or $Voice -or $Cloud -or $Local) {
        $runtimeConfigPath = Join-Path $InstallPath 'config/config.json'
        $runtimeConfig = if (Test-Path -LiteralPath $runtimeConfigPath) { Get-Content -LiteralPath $runtimeConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { [pscustomobject]@{} }
        if ($Voice) {
            if ($null -eq $runtimeConfig.tts) { $runtimeConfig | Add-Member -NotePropertyName tts -NotePropertyValue ([pscustomobject]@{}) }
            $runtimeConfig.tts | Add-Member -NotePropertyName engine -NotePropertyValue $config.tts.engine -Force
        }
        if (-not $runtimeConfig.interaction) {
            $runtimeConfig | Add-Member -NotePropertyName interaction -NotePropertyValue ([pscustomobject]@{location=$(if ($Local -and -not $Cloud) {'local'} else {$config.interaction.location});runtime=$(if($Cloud -or $Local){$config.interaction.runtime}else{$null});speech=$config.interaction.speech})
        }
        if($DefaultLocation) { $runtimeConfig.interaction.location=$DefaultLocation }
        [IO.File]::WriteAllText($runtimeConfigPath, ($runtimeConfig | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
    }
    Write-Host 'Building graphical usage and maintenance applications...'
    . (Get-StackSetupScript $registrationHelper)
    Install-StackCommandRegistration -InstallPath $InstallPath -PersistPath $PersistCommandPath
    $fingerprint=(Invoke-StackSetupScript -Path (Join-Path $repoRoot 'scripts/build-setup.ps1') -Arguments @{Fingerprint=$true} | Out-String).Trim()
    $stampPath=Join-Path $InstallPath '.whas-app-build.json'
    $reuseApps=$false
    if(Test-Path -LiteralPath $stampPath) {
        $valid=$true
        foreach($name in @('.whas-app-build.json','whas-gui.exe','whas-setup.exe')) {
            $entry=@($trackingSession.State.Files | Where-Object { $_.Path -ceq $name })
            $file=Join-Path $InstallPath $name
            if($entry.Count -ne 1 -or -not (Test-Path -LiteralPath $file) -or (Get-StackFileSHA256 $file) -cne $entry[0].SHA256) { $valid=$false; break }
        }
        if($valid) { $stamp=[IO.File]::ReadAllText($stampPath)|ConvertFrom-Json; $reuseApps=$stamp.sourceSHA256 -ceq $fingerprint }
    }
    if(-not $reuseApps) {
    $buildDirectory=Join-Path ([IO.Path]::GetTempPath()) ('whas-app-build-'+[guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($buildDirectory)|Out-Null
    try {
        Invoke-StackSetupScript -Path (Join-Path $repoRoot 'scripts/build-gui.ps1') -Arguments @{OutputPath=(Join-Path $buildDirectory 'whas-gui.exe')}
        if($LASTEXITCODE -ne 0) { throw 'Graphical client build failed.' }
        Invoke-StackSetupScript -Path (Join-Path $repoRoot 'scripts/build-setup.ps1') -Arguments @{OutputPath=(Join-Path $buildDirectory 'whas-setup.exe')}
        if($LASTEXITCODE -ne 0) { throw 'Graphical maintenance build failed.' }
        foreach($name in @('whas-gui.exe','whas-setup.exe')) { Copy-StackFile -Source (Join-Path $buildDirectory $name) -Destination (Join-Path $InstallPath $name) }
        [IO.File]::WriteAllText($stampPath,(@{sourceSHA256=$fingerprint}|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
    } finally {
        foreach($name in @('whas-gui.exe','whas-setup.exe')) { $file=Join-Path $buildDirectory $name; if(Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force } }
        if(-not @(Get-ChildItem -LiteralPath $buildDirectory -Force).Count) { Remove-Item -LiteralPath $buildDirectory }
    }
    } else { Write-Host 'Graphical applications unchanged; reusing verified builds.' }
    Complete-StackInstallationTracking -Session $trackingSession -Succeeded $true
    $trackingSession = $null
    $installationSucceeded = $true
    Write-Host 'Installation completed.' -ForegroundColor Green

    if ($Cloud -or $Local) {
        $openCodeConfig = Join-Path $InstallPath 'opencode.json'

        Write-Host ''
        Write-Host "OpenCode configuration: $openCodeConfig"
        Write-Host ''
        Write-Host 'After refreshing PATH or reopening the terminal, use:'
        Write-Host '  agent'
        Write-Host '  agentdo'
        Write-Host '  localagent'
        Write-Host '  localagentdo'
    }

    if ($Voice) {
        Write-Host ''
        Write-Host 'After refreshing PATH or reopening the terminal, use:'
        Write-Host '  tts-start'
        Write-Host '  tts-stop'
        Write-Host '  tts-status'
        Write-Host '  tts-say'
        Write-Host '  tts-voice-list'
        Write-Host '  tts-voice-add'
        Write-Host '  tts-voice-remove'
        Write-Host '  tts-voice-test'
    }

    exit 0
}
catch {
    Write-Host ''
    Write-Host "Installer error: $($_.Exception.Message)" `
        -ForegroundColor Red

    exit 1
}
finally {
    if ($null -ne $trackingSession) {
        try { Complete-StackInstallationTracking -Session $trackingSession -Succeeded $installationSucceeded }
        catch { Write-Warning "Ownership tracking is incomplete; uninstaller will retain unverified files: $($_.Exception.Message)" }
    }
    if ($operationLock) { $operationLock.ReleaseMutex(); $operationLock.Dispose() }
}
