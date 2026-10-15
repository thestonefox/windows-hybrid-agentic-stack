#Requires -Version 5.1

<#
.SYNOPSIS
    Save a baseline for a controlled fresh-install test.
.DESCRIPTION
    Reads current configuration, profiles, execution policies and Ollama
    model inventory. Writes only a new snapshot directory. Refuses to
    proceed if the proposed installation directory already exists.
    Run from the normal Windows account, not a sandbox account.
    This script does not install, uninstall or restore anything.
#>
[CmdletBinding()]
param(
    [string]$InstallPath,
    [string]$SnapshotDirectory = (Join-Path (Join-Path $env:USERPROFILE 'WHAS-TestEvidence') (
        'whas-install-baseline-' + [guid]::NewGuid().ToString('N')))
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$configScript = Join-Path $repositoryRoot 'scripts\config.ps1'
$configOutput = & $configScript -Show
if ($LASTEXITCODE -ne 0) { throw 'Unable to read effective stack configuration.' }
$config = ($configOutput | Out-String) | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = [string]$config.installation.directory
}
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = Join-Path $HOME 'AI\WindowsHybridAgenticStack'
}
$InstallPath = [Environment]::ExpandEnvironmentVariables($InstallPath)
if ($InstallPath -match '^\$HOME(?=[\\/]|$)') {
    $InstallPath = $HOME + $InstallPath.Substring(5)
}
$InstallPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallPath)
if (Test-Path -LiteralPath $InstallPath) {
    throw "Fresh-install baseline requires an absent target. Existing directory left untouched: $InstallPath"
}
if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    throw 'LOCALAPPDATA is unavailable.'
}
$commandDirectory = Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack\bin'
$commandState = Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack\commands.json'
if ((Test-Path -LiteralPath $commandDirectory) -or (Test-Path -LiteralPath $commandState)) {
    throw 'Fresh-install baseline requires absent local executable registration. Existing registration left untouched.'
}
$environmentKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
try {
    $userPathExisted = $null -ne $environmentKey -and $environmentKey.GetValueNames() -icontains 'Path'
    $userPathValue = if ($userPathExisted) {
        [string]$environmentKey.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    } else { $null }
    $userPathKind = if ($userPathExisted) { [string]$environmentKey.GetValueKind('Path') } else { $null }
}
finally { if ($null -ne $environmentKey) { $environmentKey.Dispose() } }
$SnapshotDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SnapshotDirectory)
if (Test-Path -LiteralPath $SnapshotDirectory) {
    throw "Snapshot destination already exists: $SnapshotDirectory"
}
$comparisonRoot = [System.IO.Path]::GetFullPath($InstallPath).TrimEnd('\')
$comparisonSnapshot = [System.IO.Path]::GetFullPath($SnapshotDirectory).TrimEnd('\')
if ($comparisonSnapshot.Equals($comparisonRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $comparisonSnapshot.StartsWith($comparisonRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
    $comparisonRoot.StartsWith($comparisonSnapshot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Keep the baseline outside the proposed installation directory and its ancestors.'
}

# Inventory must succeed before creating a baseline. An unknown inventory
# cannot safely distinguish pre-existing models from test-created models.
$inventory = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 10
if ($null -eq $inventory.PSObject.Properties['models']) {
    throw 'Ollama did not return a model inventory.'
}
$sourceModel = [string]$config.agents.local.model
$sourceTag = if ($sourceModel.Contains(':')) { $sourceModel } else { "${sourceModel}:latest" }
$safeName = ($sourceModel.ToLowerInvariant() -replace '[^a-z0-9-]', '-').Trim('-')
$managedModel = "whas-$safeName-ctx$($config.agents.local.contextSize)"

New-Item -ItemType Directory -Path $SnapshotDirectory -ErrorAction Stop | Out-Null
$profilePath = $PROFILE.CurrentUserCurrentHost
$localLoaderPath = Join-Path $env:LOCALAPPDATA 'WindowsHybridAgenticStack\profile.ps1'
$files = @()
foreach ($entry in @(
    @{ Path = $profilePath; Backup = 'powershell-profile.original' },
    @{ Path = $localLoaderPath; Backup = 'local-loader.original' }
)) {
    $exists = Test-Path -LiteralPath $entry.Path
    $hash = $null
    if ($exists) {
        if (-not (Test-Path -LiteralPath $entry.Path -PathType Leaf)) {
            throw "Expected a file: $($entry.Path)"
        }
        $backupPath = Join-Path $SnapshotDirectory $entry.Backup
        Copy-Item -LiteralPath $entry.Path -Destination $backupPath -ErrorAction Stop
        $hash = (Get-FileHash -LiteralPath $entry.Path -Algorithm SHA256).Hash
        if ((Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash -cne $hash) {
            throw "Backup verification failed: $($entry.Path)"
        }
    }
    $parent = Split-Path -Parent $entry.Path
    $priorBackups = @()
    if (Test-Path -LiteralPath $parent -PathType Container) {
        $priorBackups = @(Get-ChildItem -LiteralPath $parent -File |
            Where-Object { $_.Name.StartsWith((Split-Path -Leaf $entry.Path) + '.bak.', [StringComparison]::OrdinalIgnoreCase) } |
            Select-Object -ExpandProperty FullName)
    }
    $files += [pscustomobject]@{
        Path = $entry.Path
        Existed = $exists
        OriginalSHA256 = $hash
        BackupFile = $(if ($exists) { $entry.Backup } else { $null })
        ParentExisted = Test-Path -LiteralPath $parent -PathType Container
        ExistingBackups = $priorBackups
    }
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$baseline = [ordered]@{
    SchemaVersion = 2
    CapturedAtUtc = [DateTime]::UtcNow.ToString('o')
    ComputerName = $env:COMPUTERNAME
    UserName = $identity.Name
    UserSid = $identity.User.Value
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    RepositoryRoot = $repositoryRoot
    InstallPath = $InstallPath
    InstallPathExisted = $false
    InstallParentExisted = Test-Path -LiteralPath (Split-Path -Parent $InstallPath) -PathType Container
    ProfileFiles = $files
    CommandDirectory = $commandDirectory
    CommandDirectoryExisted = $false
    CommandStatePath = $commandState
    UserPath = @{ Existed = $userPathExisted; RawValue = $userPathValue; RegistryKind = $userPathKind }
    ExecutionPolicies = @(Get-ExecutionPolicy -List | ForEach-Object {
        [pscustomobject]@{ Scope = [string]$_.Scope; Policy = [string]$_.ExecutionPolicy }
    })
    OllamaModels = @($inventory.models)
    SourceModel = $sourceTag
    SourceModelExisted = @($inventory.models | Where-Object name -eq $sourceTag).Count -gt 0
    ManagedModel = $managedModel
    ManagedModelExisted = @($inventory.models | Where-Object name -eq "${managedModel}:latest").Count -gt 0
    Limitations = @(
        'Filesystem/model baseline, not a whole-machine snapshot.',
        'Caches, logs, provider token refreshes and unrelated concurrent changes are outside automatic rollback.',
        'Review post-install changes before restoring any synced profile.'
    )
}
$manifestPath = Join-Path $SnapshotDirectory 'baseline.json'
[System.IO.File]::WriteAllText($manifestPath, ($baseline | ConvertTo-Json -Depth 12),
    (New-Object System.Text.UTF8Encoding($true)))
Write-Host "Baseline saved: $manifestPath"
Write-Host "Account: $($identity.Name)"
Write-Host "Profile: $profilePath"
Write-Host "Installation target (absent): $InstallPath"
Write-Host "Source model already present: $($baseline.SourceModelExisted)"
Write-Host "Managed model already present: $($baseline.ManagedModelExisted)"
