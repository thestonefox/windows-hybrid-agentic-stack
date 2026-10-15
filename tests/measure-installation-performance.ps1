#Requires -Version 5.1
<#
.SYNOPSIS
    Measure ownership tracking and cleanup with an isolated Python-like tree.
.DESCRIPTION
    No registration, downloads, services, models or persistent PATH edits.
    Retains timings and receipts in a new temporary directory. This measures
    file-count overhead, not the disk throughput of a complete CUDA environment.
#>
[CmdletBinding()]
param(
    [ValidateRange(100,100000)][int]$FileCount = 2000,
    [string]$SourceRoot,
    [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
if (-not $SourceRoot) { $SourceRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $SourceRoot 'scripts\installation-state.ps1')
. (Join-Path $SourceRoot 'scripts\command-registration.ps1')
. (Join-Path $SourceRoot 'scripts\uninstall.ps1')
$originalProfile = $env:USERPROFILE
$originalPath = $env:Path
$pathBefore = Get-StackRawUserPath | ConvertTo-Json -Compress
$policiesBefore = Get-ExecutionPolicy -List | ConvertTo-Json -Compress
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('whas-performance-' + [guid]::NewGuid().ToString('N'))
$root = Join-Path $fixture 'installation'
$env:USERPROFILE = Join-Path $fixture 'user'
$times = [ordered]@{}
$watch = New-Object Diagnostics.Stopwatch
try {
    [IO.Directory]::CreateDirectory($env:USERPROFILE) | Out-Null
    $session = Start-StackInstallationTracking -InstallPath $root
    $bytes = New-Object byte[] 4096
    for ($index = 0; $index -lt $FileCount; $index++) {
        $package = Join-Path $root ('.venv\Lib\site-packages\package' + [int][math]::Floor($index / 40))
        if ($index % 4 -eq 0) { $package = Join-Path $package '__pycache__' }
        [IO.Directory]::CreateDirectory($package) | Out-Null
        $extension = if ($index % 4 -eq 0) { '.pyc' } else { '.py' }
        [IO.File]::WriteAllBytes((Join-Path $package ('module' + $index + $extension)), $bytes)
    }
    # Include binary bytes without creating a full multi-gigabyte CUDA install.
    [IO.File]::WriteAllBytes((Join-Path $root '.venv\runtime.dll'), (New-Object byte[] (64MB)))
    Write-Host "Fixture: $FileCount small files plus a 64 MiB binary"
    $watch.Restart(); $tree = Get-StackInstallationTree -Root $root
    $times.TreeSeconds = $watch.Elapsed.TotalSeconds
    Write-Host ('Tree enumeration: {0:N2}s' -f $times.TreeSeconds)
    $watch.Restart()
    foreach ($relative in $tree.Files) { $null = Resolve-StackOwnedPath $root $relative }
    $times.ResolvePathsSeconds = $watch.Elapsed.TotalSeconds
    Write-Host ('Path validation: {0:N2}s' -f $times.ResolvePathsSeconds)
    $watch.Restart()
    foreach ($relative in $tree.Files) { $null = Get-StackFileSHA256 ([IO.Path]::Combine($root, $relative)) }
    $times.HashFilesSeconds = $watch.Elapsed.TotalSeconds
    Write-Host ('File hashing: {0:N2}s' -f $times.HashFilesSeconds)
    $watch.Restart(); Complete-StackInstallationTracking $session $true
    $times.CompleteTrackingSeconds = $watch.Elapsed.TotalSeconds
    Write-Host ('Complete ownership tracking: {0:N2}s' -f $times.CompleteTrackingSeconds)
    $watch.Restart(); $state = Read-StackInstallationState -Root $root
    $times.ReadOwnershipSeconds = $watch.Elapsed.TotalSeconds
    Write-Host ('Read and validate ownership: {0:N2}s' -f $times.ReadOwnershipSeconds)
    if (@($state.Files).Count -ne ($FileCount + 1)) { throw 'Fixture ownership count mismatch' }
    $watch.Restart(); $plan = Get-StackUninstallPlan -InstallPath $root
    $times.PreviewSeconds = $watch.Elapsed.TotalSeconds
    Write-Host ('Uninstall preview: {0:N2}s' -f $times.PreviewSeconds)
    if ($plan.DeleteFiles.Count -ne ($FileCount + 1) -or $plan.KeepFiles.Count -ne 0) { throw 'Fixture preview mismatch' }
    $watch.Restart()
    Invoke-StackUninstall -Plan $plan -PersistPath $false -ReceiptDirectory (Join-Path $fixture 'receipts') -Confirm:$false
    $times.ApplySeconds = $watch.Elapsed.TotalSeconds
    Write-Host ('Apply uninstall: {0:N2}s' -f $times.ApplySeconds)
    if (Test-Path -LiteralPath $root) { throw 'Fixture cleanup incomplete' }
    $receiptPath = @(Get-ChildItem -LiteralPath (Join-Path $fixture 'receipts') -File)[0].FullName
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if (-not $receipt.Completed -or @($receipt.DeletedFiles).Count -ne ($FileCount + 1)) {
        throw 'Cleanup receipt does not contain every owned file'
    }
    $result = [ordered]@{
        CapturedAtUtc = [datetime]::UtcNow.ToString('o')
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        SourceRoot = $SourceRoot; SmallFileCount = $FileCount
        SmallFileBytes = 4096; BinaryBytes = 64MB; Timings = $times
        Completed = $true; FixtureDirectory = $fixture
    }
    if (-not $OutputPath) { $OutputPath = Join-Path $fixture 'timings.json' }
    [IO.File]::WriteAllText($OutputPath, ($result | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
    $result | ConvertTo-Json -Depth 5
    Write-Host "Timing results: $OutputPath"
}
finally {
    $env:USERPROFILE = $originalProfile
    $env:Path = $originalPath
    if ((Get-StackRawUserPath | ConvertTo-Json -Compress) -cne $pathBefore) { throw 'Persistent user PATH changed' }
    if ((Get-ExecutionPolicy -List | ConvertTo-Json -Compress) -cne $policiesBefore) { throw 'Execution policies changed' }
}
