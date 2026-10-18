#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts/scan-release.ps1')
$scannerLookup = ${function:Get-ReleaseDefenderScanner}
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('whas-scan-tests-' + [guid]::NewGuid().ToString('N'))
$files = @((Join-Path $fixture 'source [bundle].exe'), (Join-Path $fixture 'release package.exe'))
$originalProgramData = $env:ProgramData
$originalProgramFiles = $env:ProgramFiles

function Assert-True([bool]$Value, [string]$Message) {
    if (-not $Value) { throw "FAIL: $Message" }
}

function Reset-ScanFixture {
    [IO.Directory]::CreateDirectory($fixture) | Out-Null
    foreach ($file in $files) { [IO.File]::WriteAllText($file, 'Inert scan fixture; never executed.') }
    $script:Updates = 0
    $script:Scans = 0
    $script:Lookups = 0
    $script:Delays = 0
    $script:UpdateFailures = 0
    $script:StatusFailures = 0
    $script:DetectionFailures = 0
    $script:Active = $true
    $script:Updated = [datetime]::UtcNow.AddHours(-1)
    $script:SignatureVersion = '1.2.3.4'
    $script:ScanAction = 'clean'
    $script:LastScan = $null
    $script:ScanPaths = @()
}

function Get-ReleaseDefenderScanner {
    $script:Lookups++
    'fixture scanner ' + $script:Lookups
}

function Start-Sleep { param([int]$Seconds) $script:Delays++ }

function Get-MpComputerStatus {
    [CmdletBinding()]
    param()
    if ($script:StatusFailures -gt 0) {
        $script:StatusFailures--
        throw 'The remote procedure call failed (0x800706be).'
    }
    [pscustomobject]@{
        AMServiceEnabled = $script:Active
        AntivirusEnabled = $script:Active
        AntivirusSignatureVersion = $script:SignatureVersion
        AntivirusSignatureLastUpdated = $script:Updated
    }
}

function Invoke-ReleaseDefenderNative {
    param([string]$Scanner, [string[]]$Arguments)
    if ($Arguments[0] -eq '-SignatureUpdate') {
        $script:Updates++
        Assert-True ($Arguments.Count -eq 2 -and $Arguments[1] -eq '-MMPC') 'Use the native Microsoft signature source'
        if ($script:UpdateFailures -gt 0) {
            $script:UpdateFailures--
            throw 'The remote procedure call failed (0x800706be).'
        }
        return
    }
    Assert-True ($Arguments.Count -eq 5 -and $Arguments[0] -eq '-Scan' -and
        $Arguments[1] -eq '-ScanType' -and $Arguments[2] -eq '3' -and $Arguments[3] -eq '-File') 'Explicit custom file scan'
    $script:Scans++
    $script:LastScan = $Arguments[4]
    $script:ScanPaths += $Arguments[4]
    switch ($script:ScanAction) {
        'error' { throw 'Fixture scan failure' }
        'change' { [IO.File]::AppendAllText($Arguments[4], 'changed') }
        'remove' { Remove-Item -LiteralPath $Arguments[4] }
        'inactive' { $script:Active = $false }
    }
}

function Get-MpThreatDetection {
    [CmdletBinding()]
    param()
    if ($script:DetectionFailures -gt 0) {
        $script:DetectionFailures--
        throw 'The remote procedure call failed (0x800706be).'
    }
    if ($script:ScanAction -eq 'detect') {
        [pscustomobject]@{ InitialDetectionTime = (Get-Date).AddSeconds(1); Resources = @('file:' + $script:LastScan) }
    }
}

function Invoke-FixtureScan {
    Invoke-ReleaseDefenderScan -Paths $files -RetryDelaySeconds 0
}

function Assert-Blocked([string]$Expected) {
    $failure = $null
    try { Invoke-FixtureScan } catch { $failure = $_.Exception.Message }
    Assert-True ($failure -and $failure -like "*$Expected*") "Expected blocking error: $Expected; actual: $failure"
}

try {
    Reset-ScanFixture
    Invoke-FixtureScan
    Assert-True ($script:Updates -eq 1 -and $script:Scans -eq 2) 'Successful update and both scans are mandatory'
    Assert-True ($script:Lookups -eq 3) 'Rediscover the scanner after a platform update'
    Assert-True ($script:ScanPaths[0] -ceq (Resolve-Path -LiteralPath $files[0]).Path -and
        $script:ScanPaths[1] -ceq (Resolve-Path -LiteralPath $files[1]).Path) 'Preserve spaces and brackets in executable paths'
    Write-Host 'PASS: Native update, both explicit file scans and exact paths'

    Reset-ScanFixture
    $script:StatusFailures = 1
    $script:UpdateFailures = 2
    $script:DetectionFailures = 1
    Invoke-FixtureScan
    Assert-True ($script:Updates -eq 3 -and $script:Scans -eq 2 -and $script:Delays -eq 4) 'Recover from bounded RPC and updater failures'
    Write-Host 'PASS: Reported RPC failure reproduced and recovered without skipping scans'

    Reset-ScanFixture
    $script:UpdateFailures = 3
    Assert-Blocked 'signature update failed after 3 attempts'
    Assert-True ($script:Updates -eq 3 -and $script:Scans -eq 0) 'Exhausted updates block all scans and release'

    Reset-ScanFixture
    $script:StatusFailures = 3
    Assert-Blocked 'readiness failed after 3 attempts'
    Assert-True ($script:Updates -eq 0 -and $script:Scans -eq 0) 'Unavailable status blocks distribution'

    Reset-ScanFixture
    $script:Active = $false
    Assert-Blocked 'Defender is unavailable'
    Assert-True ($script:Updates -eq 0 -and $script:Scans -eq 0) 'Inactive protection cannot be bypassed'
    Write-Host 'PASS: Permanent update, readiness and protection failures block distribution'

    foreach ($case in @('stale', 'future', 'missing-version', 'missing-time')) {
        Reset-ScanFixture
        switch ($case) {
            'stale' { $script:Updated = [datetime]::UtcNow.AddHours(-25) }
            'future' { $script:Updated = [datetime]::UtcNow.AddHours(1) }
            'missing-version' { $script:SignatureVersion = '' }
            'missing-time' { $script:Updated = $null }
        }
        Assert-Blocked 'signatur'
        Assert-True ($script:Scans -eq 0) 'A successful updater cannot bypass signature validation'
    }
    Write-Host 'PASS: Stale, future and incomplete signature metadata is rejected'

    foreach ($action in @('error', 'change', 'remove', 'detect', 'inactive')) {
        Reset-ScanFixture
        $script:ScanAction = $action
        $message = switch ($action) {
            'error' { 'Fixture scan failure' }
            'change' { 'Executable changed' }
            'remove' { 'Defender removed' }
            'detect' { 'Defender detected' }
            'inactive' { 'Defender is unavailable' }
        }
        Assert-Blocked $message
        Assert-True ($script:Scans -le 2 -and $script:Updates -eq 1) 'Never retry a failed scan into a clean result'
    }

    Reset-ScanFixture
    $script:DetectionFailures = 3
    Assert-Blocked 'detection query failed after 3 attempts'
    Write-Host 'PASS: Scan failures, mutations, removal, detections and unreadable results all block distribution'

    $env:ProgramData = Join-Path $fixture 'ProgramData'
    $env:ProgramFiles = Join-Path $fixture 'ProgramFiles'
    $platform = Join-Path $env:ProgramData 'Microsoft/Windows Defender/Platform'
    $older = Join-Path $platform '4.18.1/MpCmdRun.exe'
    $newer = Join-Path $platform '4.18.2/MpCmdRun.exe'
    $fallback = Join-Path $env:ProgramFiles 'Windows Defender/MpCmdRun.exe'
    foreach ($file in @($older, $newer, $fallback)) {
        [IO.Directory]::CreateDirectory((Split-Path -Parent $file)) | Out-Null
        [IO.File]::WriteAllText($file, 'Inert tool path fixture; never executed.')
    }
    [IO.Directory]::CreateDirectory((Join-Path $platform '4.18.3')) | Out-Null
    Assert-True ((& $scannerLookup) -ceq $newer) 'Select the newest platform with an actual scanner'
    Remove-Item -LiteralPath $older, $newer
    Assert-True ((& $scannerLookup) -ceq $fallback) 'Support the official Program Files scanner location'
    Remove-Item -LiteralPath $fallback
    $blocked = $false
    try { & $scannerLookup } catch { $blocked = $_.Exception.Message -like '*scanner was not found*' }
    Assert-True $blocked 'Missing native scanner blocks distribution'
    Write-Host 'PASS: Platform selection, official fallback location and missing-tool rejection'
}
finally {
    $env:ProgramData = $originalProgramData
    $env:ProgramFiles = $originalProgramFiles
    $absolute = [IO.Path]::GetFullPath($fixture)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $absolute.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $absolute) -notmatch '^whas-scan-tests-[a-f0-9]{32}$') { throw 'Unexpected scan fixture cleanup target' }
    if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
