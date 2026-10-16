#Requires -Version 5.1

# Loading this helper has no side effects. Production registration changes
# only the local app directory and the current user's PATH, never a profile.
# Keep default registration outside AppData: packaged installer hosts may
# redirect AppData writes into a private cache invisible to ordinary shells.
$script:StackRegistrationSources = $PSScriptRoot

if (-not (Get-Command Test-StackCommandNames -ErrorAction Ignore)) {
    $stateHelper = Join-Path $PSScriptRoot 'installation-state.ps1'
    if (Get-Command Get-StackSetupScript -ErrorAction Ignore) { . (Get-StackSetupScript $stateHelper) }
    else { . $stateHelper }
}

function Set-StackUserCommandPath {
    param([string]$Directory, [switch]$Remove)
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
    try {
        $before = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind = if ($key.GetValueNames() -icontains 'Path') {
            $key.GetValueKind('Path')
        } else { [Microsoft.Win32.RegistryValueKind]::ExpandString }
        $parts = @($before -split ';')
        $matches = @($parts | Where-Object {
            [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ieq $Directory.TrimEnd('\')
        })
        $changed = $false
        if ($Remove -and $matches.Count -gt 0) {
            $after = @($parts | Where-Object { $matches -notcontains $_ }) -join ';'
            if ($after.Length -eq 0) { $key.DeleteValue('Path', $false) }
            else { $key.SetValue('Path', $after, $kind) }
            $changed = $true
        }
        elseif (-not $Remove -and $matches.Count -eq 0) {
            $after = if ($before.Length -eq 0) { $Directory } else { $before + ';' + $Directory }
            $key.SetValue('Path', $after, $kind)
            $changed = $true
        }
    }
    finally { $key.Dispose() }
    if ($changed) {
        if ($null -eq ('WhasEnvironmentNotification' -as [type])) {
            Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WhasEnvironmentNotification {
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam,
        string lParam, uint flags, uint timeout, out UIntPtr result);
}
'@
        }
        $result = [UIntPtr]::Zero
        $null = [WhasEnvironmentNotification]::SendMessageTimeout([IntPtr]0xffff, 0x1a,
            [UIntPtr]::Zero, 'Environment', 2, 2000, [ref]$result)
    }
    return $changed
}

function Install-StackCommandRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallPath,
        [string]$RegistrationDirectory = (Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack'),
        [bool]$PersistPath = $true
    )
    if ($PSVersionTable.PSVersion.Major -ne 5) {
        throw 'Build command launchers using Windows PowerShell 5.1.'
    }
    if ([string]::IsNullOrWhiteSpace($InstallPath) -or [string]::IsNullOrWhiteSpace($RegistrationDirectory)) {
        throw 'Installation and registration paths must not be empty.'
    }
    $root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallPath)
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Installation missing: $root" }
    $directory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RegistrationDirectory)
    $bin = Join-Path $directory 'bin'
    $statePath = Join-Path $directory 'commands.json'
    $source = Join-Path $script:StackRegistrationSources 'command-host.cs'
    $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $names = @(Get-StackCommandNames)
    $previous = $null
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $previous = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($previous.SchemaVersion -ne 1) { throw 'Unknown command registration format; left untouched.' }
    }
    # An unknown executable in our destination must never be overwritten.
    foreach ($name in $names) {
        $destination = Join-Path $bin ($name + '.exe')
        if (Test-Path -LiteralPath $destination) {
            if ($null -eq $previous -or
                (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -cne $previous.ExecutableSHA256) {
                throw "Unrecognized command executable; left untouched: $destination"
            }
        }
    }
    $reuse = $null -ne $previous -and $previous.SourceSHA256 -ceq $sourceHash -and
        (Test-Path -LiteralPath (Join-Path $bin 'agent.exe') -PathType Leaf)
    $buildDirectory = $null
    try {
        if ($reuse) { $built = Join-Path $bin 'agent.exe' }
        else {
            $buildDirectory = Join-Path ([IO.Path]::GetTempPath()) ('whas-command-build-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $buildDirectory -ErrorAction Stop | Out-Null
            $built = Join-Path $buildDirectory 'command-host.exe'
            Add-Type -Path $source -OutputAssembly $built -OutputType ConsoleApplication `
                -ReferencedAssemblies ([System.Management.Automation.PSObject].Assembly.Location) -ErrorAction Stop
        }
        New-Item -ItemType Directory -Path $bin -Force -ErrorAction Stop | Out-Null
        $executableHash = (Get-FileHash -LiteralPath $built -Algorithm SHA256).Hash
        foreach ($name in $names) {
            $destination = Join-Path $bin ($name + '.exe')
            if (Test-Path -LiteralPath $destination -PathType Leaf) {
                if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ceq $executableHash) { continue }
                Copy-Item -LiteralPath $destination -Destination ($destination + '.bak.' + [guid]::NewGuid().ToString('N'))
            }
            Copy-Item -LiteralPath $built -Destination $destination -Force -ErrorAction Stop
        }
        $rootFile = Join-Path $bin 'install-root.txt'
        if (-not (Test-Path -LiteralPath $rootFile -PathType Leaf) -or [IO.File]::ReadAllText($rootFile) -cne $root) {
            if (Test-Path -LiteralPath $rootFile) {
                Copy-Item -LiteralPath $rootFile -Destination ($rootFile + '.bak.' + [guid]::NewGuid().ToString('N'))
            }
            [IO.File]::WriteAllText($rootFile, $root, (New-Object System.Text.UTF8Encoding($true)))
        }
        $pathAdded = $false
        if ($PersistPath) { $pathAdded = Set-StackUserCommandPath -Directory $bin }
        $state = [ordered]@{
            SchemaVersion = 1
            InstallPath = $root
            SourceSHA256 = $sourceHash
            ExecutableSHA256 = $executableHash
            PathEntryAdded = $pathAdded -or ($null -ne $previous -and $previous.PathEntryAdded)
            Commands = $names
        }
        $stateJson = $state | ConvertTo-Json -Depth 4
        if (-not (Test-Path -LiteralPath $statePath -PathType Leaf) -or [IO.File]::ReadAllText($statePath) -cne $stateJson) {
            [IO.File]::WriteAllText($statePath, $stateJson, (New-Object System.Text.UTF8Encoding($true)))
        }
        if (@($env:Path -split ';' | Where-Object { $_.TrimEnd('\') -ieq $bin.TrimEnd('\') }).Count -eq 0) {
            $env:Path = $bin + ';' + $env:Path
        }
        Write-Host "Stack executable commands registered: $bin"
        Write-Host 'Refresh PATH in your original terminal, or close and reopen the terminal application.'
    }
    finally {
        if ($buildDirectory) {
            $buildFull = [IO.Path]::GetFullPath($buildDirectory)
            $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
            if (-not $buildFull.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
                (Split-Path -Leaf $buildFull) -notmatch '^whas-command-build-[a-f0-9]{32}$') { throw 'Unexpected command build cleanup path.' }
            $compiledFile = Join-Path $buildFull 'command-host.exe'
            if (Test-Path -LiteralPath $compiledFile) { Remove-Item -LiteralPath $compiledFile -Force }
            if ((Test-Path -LiteralPath $buildFull) -and @(Get-ChildItem -LiteralPath $buildFull -Force).Count -eq 0) { Remove-Item -LiteralPath $buildFull }
        }
    }
}

function Unregister-StackCommands {
    [CmdletBinding()]
    param([string]$RegistrationDirectory = (Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack'), [bool]$PersistPath = $true)

    if ([string]::IsNullOrWhiteSpace($RegistrationDirectory)) { throw 'Registration directory must not be empty.' }
    $directory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RegistrationDirectory)
    $statePath = Join-Path $directory 'commands.json'
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return }
    $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.SchemaVersion -ne 1) { throw 'Unknown command registration format; left untouched.' }
    $bin = Join-Path $directory 'bin'
    if (-not (Test-StackCommandNames @($state.Commands))) { throw 'Unexpected registered command names; left untouched.' }
    $allowedNames = @($state.Commands)
    $ownedFiles = @()
    foreach ($name in $allowedNames) {
        $file = Join-Path $bin ($name + '.exe')
        if (Test-Path -LiteralPath $file) {
            if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -cne $state.ExecutableSHA256) {
                throw "Changed command executable; left untouched: $file"
            }
            $ownedFiles += $file
        }
    }
    if ($PersistPath -and $state.PathEntryAdded) { $null = Set-StackUserCommandPath -Directory $bin -Remove }
    $env:Path = @($env:Path -split ';' | Where-Object { $_.TrimEnd('\') -ine $bin.TrimEnd('\') }) -join ';'
    foreach ($file in $ownedFiles) { Remove-Item -LiteralPath $file -Force -ErrorAction Stop }
    # Leave backups and installation files for explicit review/cleanup.
    foreach ($file in @((Join-Path $bin 'install-root.txt'), $statePath)) {
        if (Test-Path -LiteralPath $file -PathType Leaf) { Remove-Item -LiteralPath $file -Force -ErrorAction Stop }
    }
    if ((Test-Path -LiteralPath $bin -PathType Container) -and
        @(Get-ChildItem -LiteralPath $bin -Force).Count -eq 0) { Remove-Item -LiteralPath $bin }
    Write-Host 'Local command registration removed. Profiles and execution policies were not changed.'
}
