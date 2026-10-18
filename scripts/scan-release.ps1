#Requires -Version 5.1
[CmdletBinding()]
param([string[]]$Paths = @('whas-gui.exe', 'dist/release/whas-gui.exe'))
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess) {
    throw 'Scan using 64-bit Windows PowerShell 5.1.'
}

function Get-ReleaseDefenderScanner {
    $platform = Join-Path $env:ProgramData 'Microsoft/Windows Defender/Platform'
    if (Test-Path -LiteralPath $platform -PathType Container) {
        foreach ($directory in Get-ChildItem -LiteralPath $platform -Directory | Sort-Object Name -Descending) {
            $candidate = Join-Path $directory.FullName 'MpCmdRun.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    $candidate = Join-Path $env:ProgramFiles 'Windows Defender/MpCmdRun.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    throw 'Defender scanner was not found; binary distribution is blocked.'
}

function Invoke-ReleaseDefenderNative {
    param([string]$Scanner, [string[]]$Arguments)
    & $Scanner @Arguments | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw ('Defender command failed: exit {0} (0x{0:X8}).' -f [int]$LASTEXITCODE)
    }
}

function Invoke-ReleaseDefenderRetry {
    param([string]$Name, [scriptblock]$Operation, [int]$Attempts, [int]$DelaySeconds)
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try { return (& $Operation) }
        catch {
            if ($attempt -eq $Attempts) {
                throw "$Name failed after $Attempts attempts: $($_.Exception.Message)"
            }
            Write-Warning "$Name attempt $attempt failed: $($_.Exception.Message). Retrying."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Get-ReleaseDefenderStatus {
    param([int]$Attempts, [int]$DelaySeconds)
    Invoke-ReleaseDefenderRetry -Name 'Defender readiness' -Attempts $Attempts -DelaySeconds $DelaySeconds -Operation {
        $status = Get-MpComputerStatus -ErrorAction Stop
        if (-not $status.AMServiceEnabled -or -not $status.AntivirusEnabled) {
            throw 'Defender is unavailable; binary distribution is blocked.'
        }
        $status
    }
}

function Assert-ReleaseDefenderSignatures {
    param($Status, [int]$MaximumAgeHours)
    if (-not $Status.AntivirusSignatureVersion -or -not $Status.AntivirusSignatureLastUpdated) {
        throw 'Defender signature metadata is missing; binary distribution is blocked.'
    }
    $updated = ([datetime]$Status.AntivirusSignatureLastUpdated).ToUniversalTime()
    $age = ([datetime]::UtcNow - $updated).TotalHours
    if ($age -gt $MaximumAgeHours -or $age -lt -(5.0 / 60)) {
        throw 'Defender signatures are stale or their timestamp is invalid; binary distribution is blocked.'
    }
    Write-Host ('Defender signatures: {0}; updated {1:u}.' -f $Status.AntivirusSignatureVersion, $updated)
}

function Invoke-ReleaseDefenderScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$Paths,
        [ValidateRange(1, 5)][int]$Attempts = 3,
        [ValidateRange(0, 30)][int]$RetryDelaySeconds = 5,
        [ValidateRange(1, 24)][int]$MaximumSignatureAgeHours = 24
    )
    $files = @($Paths | ForEach-Object {
        $path = (Resolve-Path -LiteralPath $_ -ErrorAction Stop).Path
        $item = Get-Item -LiteralPath $path -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Release scan inputs must be ordinary files.'
        }
        [pscustomobject]@{ Path = $path; Hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
    })
    $null = Get-ReleaseDefenderStatus -Attempts $Attempts -DelaySeconds $RetryDelaySeconds
    Invoke-ReleaseDefenderRetry -Name 'Defender signature update' -Attempts $Attempts -DelaySeconds $RetryDelaySeconds -Operation {
        # Use the documented native updater rather than the update CIM method.
        # Rediscover the tool in case a platform refresh replaced its directory.
        $scanner = Get-ReleaseDefenderScanner
        Invoke-ReleaseDefenderNative -Scanner $scanner -Arguments @('-SignatureUpdate', '-MMPC')
    }
    $status = Get-ReleaseDefenderStatus -Attempts $Attempts -DelaySeconds $RetryDelaySeconds
    Assert-ReleaseDefenderSignatures -Status $status -MaximumAgeHours $MaximumSignatureAgeHours
    foreach ($file in $files) {
        $scanner = Get-ReleaseDefenderScanner
        $began = Get-Date
        # Scan errors are never retried into a clean result. Update and RPC
        # readiness retries cannot bypass a detection or a changed executable.
        Invoke-ReleaseDefenderNative -Scanner $scanner -Arguments @('-Scan', '-ScanType', '3', '-File', $file.Path)
        if (-not (Test-Path -LiteralPath $file.Path -PathType Leaf)) {
            throw 'Defender removed the executable; binary distribution is blocked.'
        }
        if ((Get-FileHash -LiteralPath $file.Path -Algorithm SHA256).Hash -cne $file.Hash) {
            throw 'Executable changed during scanning; binary distribution is blocked.'
        }
        $detections = @(Invoke-ReleaseDefenderRetry -Name 'Defender detection query' -Attempts $Attempts -DelaySeconds $RetryDelaySeconds -Operation {
            Get-MpThreatDetection -ErrorAction Stop | Where-Object {
                $_.InitialDetectionTime -ge $began -and
                ($_.Resources -join ' ').IndexOf($file.Path, [StringComparison]::OrdinalIgnoreCase) -ge 0
            }
        })
        if ($detections.Count) { throw 'Defender detected the executable; binary distribution is blocked.' }
        Write-Host "PASS: Defender scan and unchanged SHA-256 for $($file.Path)"
    }
    $status = Get-ReleaseDefenderStatus -Attempts $Attempts -DelaySeconds $RetryDelaySeconds
    Assert-ReleaseDefenderSignatures -Status $status -MaximumAgeHours $MaximumSignatureAgeHours
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-ReleaseDefenderScan -Paths $Paths }
