#Requires -Version 5.1
# Shared ownership tracking. Loading this file performs no installation or cleanup.

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
    param([string]$Root)
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
    param([string]$Path, [switch]$AllowConcurrentWrite)
    # Stream bytes directly: repeated Get-FileHash/provider setup dominates
    # small Python files. Ordinary owned files still exclude concurrent writers.
    if (-not [IO.Path]::IsPathRooted($Path)) {
        $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    }
    $sharing = if ($AllowConcurrentWrite) { [IO.FileShare]::ReadWrite } else { [IO.FileShare]::Read }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, $sharing)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
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
    param([string]$Root)
    $path = Join-Path $Root '.whas-installation.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $state = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.SchemaVersion -ne 1 -or $state.InstallPath -ine $Root -or
        $state.OwnerSid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or
        $state.InstallationId -notmatch '^[a-f0-9]{32}$') { throw 'Invalid or foreign installation ownership record.' }
    foreach ($entry in @($state.Files) + @($state.OriginalFiles)) {
        $null = Resolve-StackOwnedPath -Root $Root -Relative $entry.Path
    }
    return $state
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
    return (-not $State.PreexistingVenv -and $Path -match '^\.venv/(.+/)?__pycache__/[^/]+\.(pyc|nbc|nbi)$')
}

function Start-StackInstallationTracking {
    [CmdletBinding()]
    param([string]$InstallPath, [string]$ManagedModelName)
    $root = Assert-StackInstallationRoot -Root $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallPath)
    $registration = Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack'
    if ($registration -ieq $root -or $registration.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $root.StartsWith($registration + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Installation and command registration must be separate directories.' }
    $tree = Get-StackInstallationTree -Root $root
    $state = Read-StackInstallationState -Root $root
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
            $allowed = @('agent','agentdo','localagent','localagentdo','tts-start','tts-stop','tts-status','tts-say','tts-voice-list','tts-voice-add','tts-voice-remove','tts-voice-test')
            if ($commands.SchemaVersion -ne 1 -or @(Compare-Object $allowed @($commands.Commands)).Count -gt 0) { throw 'Existing command registration is not recognised.' }
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
        if (@($state.Directories) -notcontains $directory -and @($state.PreexistingDirectories) -notcontains $directory) { $state.PreexistingDirectories += $directory }
    }
    foreach ($entry in $state.Files) { $known[$entry.Path] = $entry }
    $originals = @{}
    foreach ($entry in $state.OriginalFiles) { $originals[$entry.Path] = $entry }
    $managedFiles = @('opencode.json','AGENTS.md','config/defaults.json','config/config.json',
        'scripts/agent-commands.ps1','scripts/config.ps1','scripts/configuration.ps1',
        'scripts/command-registration.ps1','scripts/installation-state.ps1','scripts/uninstall.ps1',
        'tts/tts.ps1','tts/tts_service.py','uninstall.ps1')
    foreach ($relative in $tree.Files | Where-Object { $_ -ne '.whas-installation.json' }) {
        if (Test-StackGeneratedFile $relative $state) { continue }
        $owned = $known.ContainsKey($relative)
        $changed = $owned -and -not (Test-StackGeneratedFile $relative $state) -and
            (Get-StackFileSHA256 (Join-Path $root $relative)) -cne $known[$relative].SHA256
        if (-not $owned -or $changed) {
            if (@($state.PreexistingPaths) -notcontains $relative) { $state.PreexistingPaths += $relative }
            if ($relative -in $managedFiles -and (-not $originals.ContainsKey($relative) -or $changed)) {
                $bytes = [IO.File]::ReadAllBytes((Join-Path $root $relative))
                if ($bytes.Length -gt 4MB) { throw "Managed configuration too large to preserve: $relative" }
                $originals[$relative] = [pscustomobject]@{ Path = $relative; Base64 = [Convert]::ToBase64String($bytes); SHA256 = Get-StackFileSHA256 (Join-Path $root $relative) }
            }
        }
    }
    $state.OriginalFiles = @($originals.Values)
    $modelBefore = @()
    if ($ManagedModelName) { $modelBefore = @(Get-StackOllamaModels) }
    $regBefore = @{}
    $regBin = Join-Path $registration 'bin'
    if (Test-Path -LiteralPath $regBin) {
        foreach ($file in Get-ChildItem -LiteralPath $regBin -File) { $regBefore[$file.Name] = Get-StackFileSHA256 $file.FullName }
    }
    if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
    $state.Status = 'Installing'
    Write-StackInstallationState -Root $root -State $state
    [pscustomobject]@{ Root = $root; State = $state; BeforePaths = @($tree.Files); RegBefore = $regBefore; ModelBefore = $modelBefore; ModelName = $ManagedModelName }
}

function Complete-StackInstallationTracking {
    [CmdletBinding()]
    param($Session, [bool]$Succeeded)
    $state = $Session.State
    $root = Assert-StackInstallationRoot -Root $Session.Root
    $tree = Get-StackInstallationTree -Root $root
    $originals = @($state.OriginalFiles.Path)
    $files = New-Object 'System.Collections.Generic.List[object]'
    foreach ($relative in $tree.Files) {
        if ($relative -eq '.whas-installation.json' -or $relative -like 'voices/*' -or
            ($state.PreexistingVenv -and $relative -like '.venv/*')) { continue }
        if ($relative -in $originals -or @($state.PreexistingPaths) -notcontains $relative) {
            $files.Add([pscustomobject]@{ Path = $relative; SHA256 = Get-StackFileSHA256 ([IO.Path]::Combine($root, $relative)) -AllowConcurrentWrite:(Test-StackGeneratedFile $relative $state) })
        }
    }
    $state.Files = $files.ToArray()
    $state.Directories = @($tree.Directories | Where-Object { @($state.PreexistingDirectories) -notcontains $_ })
    if ($Session.ModelName) {
        try {
            $tag = $Session.ModelName + ':latest'
            $current = @(Get-StackOllamaModels | Where-Object name -eq $tag)
            $before = @($Session.ModelBefore | Where-Object name -eq $tag)
            $previousModel = @($state.Models | Where-Object Name -eq $tag)
            if ($current.Count -eq 1) {
                $owned = $before.Count -eq 0 -or ($previousModel.Count -eq 1 -and $previousModel[0].Created -and $previousModel[0].Digest -ceq $current[0].digest)
                $state.Models = @($state.Models | Where-Object Name -ne $tag) + @([pscustomobject]@{ Name = $tag; Digest = $current[0].digest; Created = $owned })
            }
        } catch { Write-Warning "Model ownership could not be verified; unverified models will be retained: $_" }
    }
    $backups = @{}
    foreach ($entry in $state.RegistrationBackups) { $backups[$entry.Name] = $entry }
    $regBin = Join-Path $state.RegistrationDirectory 'bin'
    if (Test-Path -LiteralPath $regBin) {
        foreach ($file in Get-ChildItem -LiteralPath $regBin -File | Where-Object { $_.Name -match '^(agent|agentdo|localagent|localagentdo|tts-(start|stop|status|say|voice-(list|add|remove|test)))\.exe\.bak\.[a-f0-9]{32}$|^install-root\.txt\.bak\.[a-f0-9]{32}$' }) {
            if (-not $Session.RegBefore.ContainsKey($file.Name)) { $backups[$file.Name] = [pscustomobject]@{ Name = $file.Name; SHA256 = Get-StackFileSHA256 $file.FullName } }
        }
    }
    $state.RegistrationBackups = @($backups.Values)
    $state.Status = if ($Succeeded) { 'Installed' } else { 'Interrupted' }
    Write-StackInstallationState -Root $root -State $state
}
