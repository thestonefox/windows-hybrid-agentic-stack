#Requires -Version 5.1
# Shared ownership tracking. Loading this file performs no installation or cleanup.

function Get-StackCommandNames {
    param([switch]$Legacy)
    $names = @('agent','agentdo','localagent','localagentdo','tts-start','tts-stop','tts-status',
        'tts-say','tts-voice-list','tts-voice-add','tts-voice-remove','tts-voice-test')
    if (-not $Legacy) { $names += @('tts-engine-list','tts-engine-install','tts-engine-uninstall','tts-engine-default','whas') }
    return $names
}
function Test-StackCommandNames {
    param([string[]]$Names)
    return (@(Compare-Object @(Get-StackCommandNames) $Names).Count -eq 0 -or
        @(Compare-Object @(Get-StackCommandNames | Where-Object { $_ -ne 'whas' }) $Names).Count -eq 0 -or
        @(Compare-Object @(Get-StackCommandNames -Legacy) $Names).Count -eq 0)
}

function Enter-StackOperationLock {
    param([string]$Root)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $key = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Root).TrimEnd('\').ToLowerInvariant())))).Replace('-','') }
    finally { $sha.Dispose() }
    $mutex = New-Object Threading.Mutex($false, ('Local\WHAS-' + $key))
    try {
        try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { throw 'Another stack operation is running. Wait for it to finish and retry.' }
        return $mutex
    }
    catch { $mutex.Dispose(); throw }
}

function New-StackOperationProgress {
    param([string]$Activity, [switch]$Enabled, [string]$Unit = 'files')
    if (-not $Enabled) { return $null }
    $progress = [pscustomobject]@{
        Activity = $Activity; Timer = [Diagnostics.Stopwatch]::StartNew()
        LastUpdate = -2000L; Completed = 0L; Total = -1L; Unit = $Unit
    }
    Write-StackOperationProgress $progress -Force
    return $progress
}

function Write-StackOperationProgress {
    param($Progress, [long]$Completed = -1, [long]$Total = -1,
        [string]$Detail, [switch]$Force)
    if ($null -eq $Progress) { return }
    if ($Completed -ge 0) { $Progress.Completed = $Completed }
    if ($Total -ge 0) { $Progress.Total = $Total }
    $elapsed = $Progress.Timer.ElapsedMilliseconds
    if (-not $Force -and $elapsed - $Progress.LastUpdate -lt 2000) { return }
    $Progress.LastUpdate = $elapsed
    $count = if ($Progress.Total -ge 0) { "$($Progress.Completed)/$($Progress.Total) $($Progress.Unit)" } else { "$($Progress.Completed) $($Progress.Unit) inspected" }
    Write-Host ("{0}: {1}; {2:N0}s elapsed. {3}" -f $Progress.Activity, $count, ($elapsed / 1000), $Detail).TrimEnd()
}

function Resolve-StackOwnedPath {
    param([string]$Root, [string]$Relative)
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or
        $Relative -match '(^|[\\/])\.\.?([\\/]|$)|:') { throw "Invalid ownership path: $Relative" }
    $full = [IO.Path]::GetFullPath([IO.Path]::Combine($Root, $Relative))
    if (-not $full.StartsWith($Root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Ownership path escapes the installation.'
    }
    return $full
}

function Assert-StackInstallationRoot {
    param([string]$Root)
    $full = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    if (Test-Path -LiteralPath (Join-Path $full '.git')) { throw "Refusing to manage a Git checkout: $full" }
    $repository = Split-Path -Parent $PSScriptRoot
    if (-not (Test-Path -LiteralPath (Join-Path $repository '.git'))) { $repository = $null }
    foreach ($protected in @([IO.Path]::GetPathRoot($full).TrimEnd('\'), $env:USERPROFILE,
        $env:WINDIR, $env:ProgramFiles, $repository)) {
        if ($protected -and ($full -ieq $protected.TrimEnd('\') -or
            $protected.StartsWith($full + '\', [StringComparison]::OrdinalIgnoreCase))) {
            throw "Refusing to manage a protected directory: $full"
        }
    }
    $ancestor = $full
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor) {
            $item = Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse point requires manual review: $ancestor" }
        }
        $parent = Split-Path -Parent $ancestor
        if ($parent -eq $ancestor) { break }
        $ancestor = $parent
    }
    return $full
}

function Get-StackInstallationTree {
    param([string]$Root, $Progress)
    $files = New-Object 'System.Collections.Generic.List[string]'
    $directories = New-Object 'System.Collections.Generic.List[string]'
    if (Test-Path -LiteralPath $Root) {
        if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "Installation is not a directory: $Root" }
        $pending = New-Object 'System.Collections.Generic.Stack[string]'
        $pending.Push($Root)
        while ($pending.Count -gt 0) {
            $directory = $pending.Pop()
            foreach ($item in Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop) {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse point requires manual review: $($item.FullName)" }
                $relative = $item.FullName.Substring($Root.Length + 1).Replace('\','/')
                if ($item.PSIsContainer) { $directories.Add($relative); $pending.Push($item.FullName) }
                else { $files.Add($relative) }
                if ($Progress -and $Progress.Timer.ElapsedMilliseconds - $Progress.LastUpdate -ge 2000) {
                    Write-StackOperationProgress $Progress -Completed $files.Count
                }
            }
        }
    }
    [pscustomobject]@{ Files = $files.ToArray(); Directories = $directories.ToArray() }
}

function Get-StackRawUserPath {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    try {
        $exists = $null -ne $key -and $key.GetValueNames() -icontains 'Path'
        [pscustomobject]@{
            Existed = $exists
            Value = $(if ($exists) { [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } else { '' })
            Kind = $(if ($exists) { [string]$key.GetValueKind('Path') } else { 'ExpandString' })
        }
    } finally { if ($null -ne $key) { $key.Dispose() } }
}

function Set-StackRawUserPath {
    param($PathState, [AllowEmptyString()][string]$ExpectedValue)
    if ((Get-StackRawUserPath).Value -cne $ExpectedValue) { throw 'User PATH changed during uninstall; the new value was preserved.' }
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
    try {
        if ($PathState.Existed) { $key.SetValue('Path', [string]$PathState.Value, [Microsoft.Win32.RegistryValueKind]([Enum]::Parse([Microsoft.Win32.RegistryValueKind], $PathState.Kind))) }
        else { $key.DeleteValue('Path', $false) }
    } finally { $key.Dispose() }
}

function Get-StackFileSHA256 {
    param([string]$Path, [switch]$AllowConcurrentWrite, $Progress)
    # Stream bytes directly: repeated Get-FileHash/provider setup dominates
    # small Python files. Ordinary owned files still exclude concurrent writers.
    if (-not [IO.Path]::IsPathRooted($Path)) {
        $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    }
    $sharing = if ($AllowConcurrentWrite) { [IO.FileShare]::ReadWrite } else { [IO.FileShare]::Read }
    # Private model copies can be several GB. Buffer sequential reads while
    # retaining the same sharing restrictions and SHA-256 verification.
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read,
        $sharing, 1MB, [IO.FileOptions]::SequentialScan)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            if ($null -eq $Progress -or $stream.Length -lt 16MB) {
                return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','')
            }
            # Large model files need feedback within a hash, not just between files.
            $buffer = New-Object byte[] 8MB
            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $null = $sha.TransformBlock($buffer, 0, $read, $buffer, 0)
                $detail = 'Reading {0}: {1:N0}/{2:N0} MiB' -f [IO.Path]::GetFileName($Path), ($stream.Position / 1MB), ($stream.Length / 1MB)
                Write-StackOperationProgress $Progress -Detail $detail
            }
            $null = $sha.TransformFinalBlock((New-Object byte[] 0), 0, 0)
            return ([BitConverter]::ToString($sha.Hash)).Replace('-','')
        }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Write-StackInstallationState {
    param([string]$Root, $State)
    $path = Join-Path $Root '.whas-installation.json'
    $temporary = $path + '.tmp.' + [guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($temporary, ($State | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($true)))
        Move-Item -LiteralPath $temporary -Destination $path -Force -ErrorAction Stop
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}

function Read-StackInstallationState {
    param([string]$Root, [switch]$ReadOnly)
    $path = Join-Path $Root '.whas-installation.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $json = [IO.File]::ReadAllText($path)
    # Reuse validated snapshots only for readers. Mutating callers always get
    # their own object, and changed bytes invalidate the read-only snapshot.
    if ($ReadOnly -and $script:StackReadSnapshot -and $script:StackReadSnapshot.Root -ceq $Root -and
        $script:StackReadSnapshot.Json -ceq $json) { return $script:StackReadSnapshot.State }
    $state = $json | ConvertFrom-Json
    if ($state.SchemaVersion -notin @(1,2) -or $state.InstallPath -ine $Root -or
        $state.OwnerSid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or
        $state.InstallationId -notmatch '^[a-f0-9]{32}$') { throw 'Invalid or foreign installation ownership record.' }
    if ($state.SchemaVersion -eq 2) {
        if ($state.TtsStrategies -isnot [array]) { throw 'Invalid strategy installation record.' }
        $strategyIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($strategy in $state.TtsStrategies) {
            if ($strategy.Id -notmatch '^[a-z][a-z0-9-]{0,47}$' -or -not $strategyIds.Add($strategy.Id) -or
                $strategy.Context.InstallPath -ine $Root -or $strategy.Context.Engine -cne $strategy.Id -or
                $strategy.ApiVersion -ne 1 -or $strategy.Status -notin @('Installing','Prepared','Installed')) { throw 'Invalid strategy context.' }
            $environment = "tts/engines/$($strategy.Id)/.venv"
            if ($strategy.Context.EnvironmentPath -cne $environment -and
                -not ($strategy.Id -ceq 'chatterbox-turbo' -and $strategy.Context.EnvironmentPath -ceq '.venv' -and -not $state.PreexistingVenv)) { throw 'Invalid strategy environment path.' }
            if ($strategy.Context.ModelsPath -cne "tts/engines/$($strategy.Id)/models" -or
                $strategy.Context.VoicesPath -notin @('voices',"voices/$($strategy.Id)")) { throw 'Invalid strategy resource paths.' }
        }
    }
    $entries=@($state.Files) + @($state.OriginalFiles)
    if ($null -ne ('WindowsHybridAgenticStack.CommandHost' -as [type])) {
        [WindowsHybridAgenticStack.CommandHost]::ValidateOwnershipPaths($Root, [Management.Automation.PSObject[]]$entries)
    } else {
        foreach ($entry in $entries) { $null = Resolve-StackOwnedPath -Root $Root -Relative $entry.Path }
    }
    if ($ReadOnly) { $script:StackReadSnapshot = [pscustomobject]@{Root=$Root;Json=$json;State=$state} }
    return $state
}

function Get-StackAgentHooks {
    param([string]$Root,$State)
    $assets=@{}
    foreach($entry in $State.Files) { $assets[$entry.Path]=$entry.SHA256 }
    foreach($relative in @($assets.Keys | Where-Object { $_ -cmatch '^agents/strategies/[a-z][a-z0-9-]{0,47}/manifest\.json$' })) {
        $id=$relative.Split('/')[2]
        $prefix="agents/runtime/$id/"
        if(-not @($State.Files | Where-Object { $_.Path.StartsWith($prefix,[StringComparison]::Ordinal) }).Count) { continue }
        $manifestPath=Resolve-StackOwnedPath $Root $relative
        if(-not (Test-Path -LiteralPath $manifestPath)) { continue }
        if((Get-StackFileSHA256 $manifestPath) -cne $assets[$relative]) { throw 'Agent manifest changed; cleanup hook execution requires repair.' }
        $manifest=[IO.File]::ReadAllText($manifestPath)|ConvertFrom-Json
        if($manifest.schemaVersion -ne 1 -or $manifest.id -cne $id) { throw 'Invalid agent strategy identity.' }
        if(-not $manifest.capabilities.managedInstall) { continue }
        if(-not $manifest.entrypoints.uninstall -or $manifest.files -cnotcontains $manifest.entrypoints.uninstall) { throw 'Agent strategy requires a declared uninstall hook.' }
        $package="agents/strategies/$id/"
        foreach($file in $manifest.files) {
            $path=Resolve-StackOwnedPath $Root ($package+$file)
            if(-not $assets.ContainsKey($package+$file) -or -not (Test-Path -LiteralPath $path) -or (Get-StackFileSHA256 $path) -cne $assets[$package+$file]) { throw 'Agent strategy is unowned or modified; cleanup hook execution requires repair.' }
        }
        $hook=$package+$manifest.entrypoints.uninstall
        [pscustomobject]@{Id=$id;Path=(Resolve-StackOwnedPath $Root $hook);SHA256=$assets[$hook];Context=[pscustomobject]@{InstallPath=$Root;RuntimeId=$id}}
    }
}

function Get-StackOllamaModels {
    $response = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 10 -ErrorAction Stop
    if ($null -eq $response.PSObject.Properties['models']) { throw 'Ollama returned no model inventory.' }
    return $response.models
}

function Test-StackGeneratedFile {
    param([string]$Path, $State)
    if (@($State.PreexistingPaths) -contains $Path) { return $false }
    if ($Path -in @('tts/service.log','tts/service-errors.log','tts/service.pid','tts/last-spoken.wav')) { return $true }
    # Numba writes compiled-code (.nbc) and index (.nbi) caches beside Python bytecode.
    if (-not $State.PreexistingVenv -and $Path -match '^\.venv/(.+/)?__pycache__/[^/]+\.(pyc|nbc|nbi)$') { return $true }
    foreach ($strategy in @($State.TtsStrategies)) {
        if ($null -eq $strategy) { continue }
        $prefix = [regex]::Escape([string]$strategy.Context.EnvironmentPath)
        if ($Path -match ('^' + $prefix + '/(.+/)?__pycache__/[^/]+\.(pyc|nbc|nbi)$')) { return $true }
        # Hugging Face local_dir metadata is disposable only within this owned model root.
        $models = [regex]::Escape([string]$strategy.Context.ModelsPath)
        if ($Path -match ('^' + $models + '/\.cache/huggingface/(.+/)?[^/]+\.(lock|metadata)$')) { return $true }
        $package = [regex]::Escape('tts/strategies/' + $strategy.Id)
        if ($Path -match ('^' + $package + '/(.+/)?__pycache__/[^/]+\.pyc$')) { return $true }
    }
    return $false
}

function Start-StackInstallationTracking {
    [CmdletBinding()]
    param([string]$InstallPath, [string]$ManagedModelName, [string[]]$ManagedModelNames)
    $root = Assert-StackInstallationRoot -Root $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallPath)
    $registration = Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack'
    if ($registration -ieq $root -or $registration.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $root.StartsWith($registration + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Installation and command registration must be separate directories.' }
    $scan = New-StackOperationProgress 'Inspecting existing installation' -Enabled
    $tree = Get-StackInstallationTree -Root $root -Progress $scan
    Write-StackOperationProgress $scan -Completed $tree.Files.Count -Total $tree.Files.Count -Force
    $state = Read-StackInstallationState -Root $root
    # A completed uninstall ends the previous ownership session. Retained user
    # files become the baseline for a new install, including a different engine.
    if ($state -and $state.Status -eq 'Uninstalled') { $state = $null }
    if ($null -eq $state) {
        $state = [pscustomobject]@{
            SchemaVersion = 1; InstallationId = [guid]::NewGuid().ToString('N')
            OwnerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            InstallPath = $root; RegistrationDirectory = $registration
            RootExisted = Test-Path -LiteralPath $root
            PreexistingPaths = @($tree.Files)
            PreexistingDirectories = @($tree.Directories); Directories = @()
            PreexistingVenv = Test-Path -LiteralPath (Join-Path $root '.venv')
            RegistrationRootExisted = Test-Path -LiteralPath $registration
            RegistrationBinExisted = Test-Path -LiteralPath (Join-Path $registration 'bin')
            OriginalUserPath = Get-StackRawUserPath
            PreviousRegistration = $null
            OriginalFiles = @(); Files = @(); Models = @(); RegistrationBackups = @(); Status = 'Installing'
        }
        $commandsPath = Join-Path $registration 'commands.json'
        if (Test-Path -LiteralPath $commandsPath) {
            $commands = Get-Content -LiteralPath $commandsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($commands.SchemaVersion -ne 1 -or -not (Test-StackCommandNames @($commands.Commands))) { throw 'Existing command registration is not recognised.' }
            $allowed = @($commands.Commands)
            $previousFiles = @()
            $bin = Join-Path $registration 'bin'
            $null = Get-StackInstallationTree -Root $registration
            foreach ($relative in @('commands.json','bin/install-root.txt') + @($allowed | ForEach-Object { 'bin/' + $_ + '.exe' })) {
                $path = Resolve-StackOwnedPath $registration $relative
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Existing registration is incomplete; repair it before installation.' }
                if ($relative -like '*.exe' -and (Get-StackFileSHA256 $path) -cne $commands.ExecutableSHA256) { throw 'Existing executable changed; installation stopped before tracking writes.' }
                $previousFiles += [pscustomobject]@{ Path=$relative; Base64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($path)); SHA256=Get-StackFileSHA256 $path }
            }
            $state.PreviousRegistration = [pscustomobject]@{
                InstallPath = $commands.InstallPath; Files = $previousFiles
                HadPathEntry = @($state.OriginalUserPath.Value -split ';' | Where-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ieq $bin }).Count -gt 0
            }
        }
    }
    $known = @{}
    foreach ($directory in $tree.Directories) {
        if (-not $state.PreexistingVenv -and $directory -match '^\.venv/(.+/)?__pycache__$') { continue }
        if ((Test-StackGeneratedFile ($directory + '/placeholder.pyc') $state) -or
            (Test-StackGeneratedFile ($directory + '/placeholder.metadata') $state)) { continue }
        if (@($state.Directories) -notcontains $directory -and @($state.PreexistingDirectories) -notcontains $directory) { $state.PreexistingDirectories += $directory }
    }
    foreach ($entry in $state.Files) { $known[$entry.Path] = $entry }
    $originals = @{}
    foreach ($entry in $state.OriginalFiles) { $originals[$entry.Path] = $entry }
    $managedFiles = @('opencode.json','AGENTS.md','config/defaults.json','config/config.json','whas-gui.exe','whas-setup.exe','.whas-app-build.json',
        'scripts/whas.ps1','scripts/agent-strategies.ps1',
        'scripts/agent-commands.ps1','scripts/config.ps1','scripts/configuration.ps1',
        'scripts/command-registration.ps1','scripts/installation-state.ps1','scripts/uninstall.ps1','scripts/script-invocation.ps1','scripts/check-prerequisites.ps1',
        'tts/tts.ps1','tts/tts_service.py','tts/strategy-management.ps1','tts/engine-management.ps1','tts/install-tts.ps1','tts/strategy.schema.json','tts/runtime.json','tts/engines.json','uninstall.ps1')
    foreach ($relative in $tree.Files | Where-Object { $_ -ne '.whas-installation.json' }) {
        if (Test-StackGeneratedFile $relative $state) { continue }
        $owned = $known.ContainsKey($relative)
        $changed = $owned -and -not (Test-StackGeneratedFile $relative $state) -and
            (Get-StackFileSHA256 (Join-Path $root $relative)) -cne $known[$relative].SHA256
        if (-not $owned -or $changed) {
            if (@($state.PreexistingPaths) -notcontains $relative) { $state.PreexistingPaths += $relative }
            $managedRuntime = $relative -cmatch '^tts/engines/[a-z][a-z0-9-]{0,47}/runtime\.json$'
            if (($relative -in $managedFiles -or $managedRuntime) -and (-not $originals.ContainsKey($relative) -or $changed)) {
                $bytes = [IO.File]::ReadAllBytes((Join-Path $root $relative))
                if ($bytes.Length -gt 4MB) { throw "Managed configuration too large to preserve: $relative" }
                $originals[$relative] = [pscustomobject]@{ Path = $relative; Base64 = [Convert]::ToBase64String($bytes); SHA256 = Get-StackFileSHA256 (Join-Path $root $relative) }
            }
        }
    }
    $state.OriginalFiles = @($originals.Values)
    $modelBefore = @()
    if ($ManagedModelName -or $ManagedModelNames.Count) { $modelBefore = @(Get-StackOllamaModels) }
    $regBefore = @{}
    $regBin = Join-Path $registration 'bin'
    if (Test-Path -LiteralPath $regBin) {
        foreach ($file in Get-ChildItem -LiteralPath $regBin -File) { $regBefore[$file.Name] = Get-StackFileSHA256 $file.FullName }
    }
    if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
    $state.Status = 'Installing'
    Write-StackInstallationState -Root $root -State $state
    [pscustomobject]@{ Root = $root; State = $state; BeforePaths = @($tree.Files); RegBefore = $regBefore; ModelBefore = $modelBefore; ModelName = $ManagedModelName; ModelNames = $ManagedModelNames }
}

function Complete-StackInstallationTracking {
    [CmdletBinding()]
    param($Session, [bool]$Succeeded)
    $state = $Session.State
    $latest = Read-StackInstallationState $Session.Root
    if ($latest -and $latest.SchemaVersion -eq 2) {
        $state.SchemaVersion = 2
        $state | Add-Member -NotePropertyName TtsStrategies -NotePropertyValue @($latest.TtsStrategies) -Force
    }
    $root = Assert-StackInstallationRoot -Root $Session.Root
    Write-Host 'Finalising installation: recording files for safe uninstallation...'
    $scan = New-StackOperationProgress 'Scanning installed files' -Enabled
    $tree = Get-StackInstallationTree -Root $root -Progress $scan
    Write-StackOperationProgress $scan -Completed $tree.Files.Count -Total $tree.Files.Count -Force
    $originals = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($state.OriginalFiles)) { $null = $originals.Add($item.Path) }
    $preexisting = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($state.PreexistingPaths)) { $null = $preexisting.Add($item) }
    $progress = New-StackOperationProgress 'Recording installed file hashes' -Enabled
    $progress.Total = $tree.Files.Count
    $inspected = 0
    $files = New-Object 'System.Collections.Generic.List[object]'
    foreach ($relative in $tree.Files) {
        $progress.Completed = ++$inspected
        if ($progress.Timer.ElapsedMilliseconds - $progress.LastUpdate -ge 2000) { Write-StackOperationProgress $progress }
        if ($relative -eq '.whas-installation.json' -or $relative -like 'voices/*' -or $relative -like 'agents/data/*' -or $relative -like 'agents/runtime/*/home/profiles/*' -or
            ($state.PreexistingVenv -and $relative -like '.venv/*')) { continue }
        if ($originals.Contains($relative) -or -not $preexisting.Contains($relative)) {
            $files.Add([pscustomobject]@{ Path = $relative; SHA256 = Get-StackFileSHA256 ([IO.Path]::Combine($root, $relative)) -AllowConcurrentWrite:(Test-StackGeneratedFile $relative $state) -Progress $progress })
        }
    }
    $state.Files = $files.ToArray()
    Write-StackOperationProgress $progress -Completed $inspected -Total $tree.Files.Count -Force
    $state.Directories = @($tree.Directories | Where-Object { @($state.PreexistingDirectories) -notcontains $_ })
    $modelNames = if ($Session.ModelNames.Count) { $Session.ModelNames } elseif ($Session.ModelName) { @($Session.ModelName) } else { @() }
    foreach ($modelName in $modelNames) {
        try {
            $tag = if ($modelName -match ':[^/]+$') { $modelName } else { $modelName + ':latest' }
            $current = @(Get-StackOllamaModels | Where-Object name -eq $tag)
            $before = @($Session.ModelBefore | Where-Object name -eq $tag)
            $previousModel = @($state.Models | Where-Object Name -eq $tag)
            if ($current.Count -eq 1) {
                $owned = $before.Count -eq 0 -or ($previousModel.Count -eq 1 -and $previousModel[0].Created -and $previousModel[0].Digest -ceq $current[0].digest)
                $kind=if ($modelName -match '^whas-[a-z0-9-]+-ctx[0-9]+$' -or -not $Session.ModelNames.Count) { 'Configured' } else { 'Source' }
                $state.Models = @($state.Models | Where-Object Name -ne $tag) + @([pscustomobject]@{ Name = $tag; Digest = $current[0].digest; Created = $owned; Kind=$kind })
            }
        } catch { Write-Warning "Model ownership could not be verified; unverified models will be retained: $_" }
    }
    $backups = @{}
    foreach ($entry in $state.RegistrationBackups) { $backups[$entry.Name] = $entry }
    $regBin = Join-Path $state.RegistrationDirectory 'bin'
    if (Test-Path -LiteralPath $regBin) {
        foreach ($file in Get-ChildItem -LiteralPath $regBin -File | Where-Object { $_.Name -match '^(whas|agent|agentdo|localagent|localagentdo|tts-(start|stop|status|say|voice-(list|add|remove|test)|engine-(list|install|uninstall|default)))\.exe\.bak\.[a-f0-9]{32}$|^install-root\.txt\.bak\.[a-f0-9]{32}$' }) {
            if (-not $Session.RegBefore.ContainsKey($file.Name)) { $backups[$file.Name] = [pscustomobject]@{ Name = $file.Name; SHA256 = Get-StackFileSHA256 $file.FullName } }
        }
    }
    $state.RegistrationBackups = @($backups.Values)
    $state.Status = if ($Succeeded) { 'Installed' } else { 'Interrupted' }
    Write-Host 'Saving installation ownership record...'
    Write-StackInstallationState -Root $root -State $state
}
