#Requires -Version 5.1

<#
.SYNOPSIS
    Read-only prerequisite checker for Windows Hybrid Agentic Stack.

.EXAMPLE
    .\scripts\check-prerequisites.ps1 -Cloud -Local -Voice

.EXAMPLE
    .\scripts\check-prerequisites.ps1 -Cloud

.EXAMPLE
    .\scripts\check-prerequisites.ps1 -Voice
#>

[CmdletBinding()]
param(
    [switch]$Cloud,
    [switch]$Local,
    [switch]$Voice
)

$ErrorActionPreference = 'Stop'

# Without explicit options, inspect all three components.
if (-not ($Cloud -or $Local -or $Voice)) {
    $Cloud = $true
    $Local = $true
    $Voice = $true
}

$results = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param(
        [string]$Component,
        [string]$Status,
        [string]$Details,
        [bool]$Required
    )

    $results.Add([pscustomobject]@{
        Component = $Component
        Required  = if ($Required) { 'Yes' } else { 'No' }
        Status    = $Status
        Details   = $Details
    })
}

function Get-Executable {
    param([string]$Name)

    Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

function Test-VersionCommand {
    param(
        [string]$Name,
        [string[]]$Arguments = @('--version')
    )

    $command = Get-Executable $Name

    if (-not $command) {
        return $null
    }

    try {
        $output = & $command.Source @Arguments 2>&1 | Out-String

        if ($LASTEXITCODE -ne 0) {
            return $null
        }

        return $output.Trim()
    }
    catch {
        return $null
    }
}


function Get-PythonInstallations {
    $candidates = [System.Collections.Generic.List[string]]::new()

    # Discover Python installations registered with the Windows launcher.
    $launcher = Get-Executable 'py.exe'

    if ($launcher) {
        try {
            $lines = & $launcher.Source -0p 2>$null

            foreach ($line in $lines) {
                if ($line -match '([A-Za-z]:\\.*python\.exe)\s*$') {
                    $candidates.Add($Matches[1])
                }
            }
        }
        catch {}
    }

    # Discover Python executables on PATH.
    foreach ($name in @('python.exe', 'python3.exe')) {
        Get-Command $name -All -CommandType Application -ErrorAction SilentlyContinue |
            ForEach-Object {
                if ($_.Source) {
                    $candidates.Add($_.Source)
                }
            }
    }

    # Discover standard per-user Python installations.
    $pythonRoot = Join-Path $env:LOCALAPPDATA 'Programs\Python'

    if (Test-Path $pythonRoot) {
        Get-ChildItem $pythonRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $path = Join-Path $_.FullName 'python.exe'

                if (Test-Path $path) {
                    $candidates.Add($path)
                }
            }
    }

    $installations = @()

    foreach ($path in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        try {
            $code = 'import sys,struct; print(str(sys.version_info.major)+chr(46)+str(sys.version_info.minor)+chr(46)+str(sys.version_info.micro)+chr(124)+str(struct.calcsize(chr(80))*8))'

            $output = & $path -c $code 2>$null

            if ($LASTEXITCODE -ne 0 -or -not $output) {
                continue
            }

            $line = ($output | Select-Object -Last 1).ToString().Trim()

            if ($line -notmatch '^(\d+)\.(\d+)\.(\d+)\|(\d+)$') {
                continue
            }

            $installations += [pscustomobject]@{
                Path    = $path
                Version = [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
                Bits    = [int]$Matches[4]
            }
        }
        catch {}
    }

    return @($installations | Sort-Object Version -Descending)
}

Write-Host ''
Write-Host 'Windows Hybrid Agentic Stack - Prerequisite Check'
Write-Host '================================================='
Write-Host "Selected: Cloud=$Cloud, Local=$Local, Voice=$Voice"
Write-Host ''

# Windows
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $build = [int]$os.BuildNumber

    if ($build -ge 19041) {
        Add-Check 'Windows' 'PASS' "$($os.Caption) (build $build)" $true
    }
    else {
        Add-Check 'Windows' 'FAIL' "Windows build $build is below the initial supported baseline (19041)." $true
    }
}
catch {
    Add-Check 'Windows' 'FAIL' $_.Exception.Message $true
}

# PowerShell
$psVersion = $PSVersionTable.PSVersion

Add-Check 'PowerShell' 'PASS' "$psVersion" $true

# Execution policy
try {
    $policies = @(Get-ExecutionPolicy -List)
    $effective = Get-ExecutionPolicy

    $managed = @(
        $policies | Where-Object {
            $_.Scope -in @('MachinePolicy', 'UserPolicy') -and
            $_.ExecutionPolicy -ne 'Undefined'
        }
    )

    if ($managed.Count -gt 0) {
        Add-Check 'Execution policy' 'WARN' "Organisation-managed policy: $effective" $false
    }
    elseif ($effective -in @('Restricted', 'AllSigned')) {
        Add-Check 'Execution policy' 'WARN' "Current policy: $effective. Installer bootstrap guidance may be needed." $false
    }
    else {
        Add-Check 'Execution policy' 'PASS' "$effective" $false
    }
}
catch {
    Add-Check 'Execution policy' 'WARN' $_.Exception.Message $false
}

# OpenCode is required by cloud and local agents.
if ($Cloud -or $Local) {
    $openCode = Test-VersionCommand 'opencode.exe'

    if ($openCode) {
        Add-Check 'OpenCode' 'PASS' $openCode $true
    }
    else {
        Add-Check 'OpenCode' 'FAIL' 'OpenCode CLI not available or failed its version check.' $true
    }
}

# Cloud model access cannot be fully verified without authentication.
if ($Cloud) {
    Add-Check 'OpenAI access' 'INFO' 'Authentication and model access must be verified during setup.' $false
}

# Ollama
if ($Local) {
    $ollama = Test-VersionCommand 'ollama.exe'

    if ($ollama) {
        if ($ollama -match '(?is)client version is') {
            Add-Check 'Ollama' 'WARN' $ollama $true
        }
        else {
            Add-Check 'Ollama' 'PASS' $ollama $true
        }
    }
    else {
        Add-Check 'Ollama' 'FAIL' 'Ollama CLI not available or failed its version check.' $true
    }
}

# Python and NVIDIA are relevant only to voice installation.
if ($Voice) {
    $pythons = @(Get-PythonInstallations)

    $compatible = @(
        $pythons | Where-Object {
            $_.Bits -eq 64 -and
            $_.Version.Major -eq 3 -and
            $_.Version.Minor -ge 10 -and
            $_.Version.Minor -le 13
        }
    )

    $newer = @(
        $pythons | Where-Object {
            $_.Bits -eq 64 -and
            $_.Version.Major -eq 3 -and
            $_.Version.Minor -gt 13
        }
    )

    if ($compatible.Count -gt 0) {
        $python = $compatible | Select-Object -First 1
        Add-Check 'Python' 'PASS' "Python $($python.Version), 64-bit - $($python.Path)" $true
    }
    elseif ($newer.Count -gt 0) {
        $python = $newer | Select-Object -First 1
        Add-Check 'Python' 'WARN' "Python $($python.Version) found but full Chatterbox/CUDA compatibility is unverified." $true
    }
    else {
        Add-Check 'Python' 'FAIL' 'No suitable 64-bit Python 3 installation detected.' $true
    }

    $nvidia = Get-Executable 'nvidia-smi.exe'

    if ($nvidia) {
        try {
            $gpu = & $nvidia.Source --query-gpu=name,driver_version,memory.total --format=csv,noheader,nounits 2>$null

            if ($LASTEXITCODE -eq 0 -and $gpu) {
                Add-Check 'NVIDIA GPU' 'PASS' (($gpu | Out-String).Trim()) $false
            }
            else {
                Add-Check 'NVIDIA GPU' 'WARN' 'NVIDIA GPU query failed.' $false
            }
        }
        catch {
            Add-Check 'NVIDIA GPU' 'WARN' $_.Exception.Message $false
        }
    }
    else {
        Add-Check 'NVIDIA GPU' 'WARN' 'nvidia-smi not found. GPU acceleration cannot be verified.' $false
    }

    Add-Check 'CUDA/PyTorch' 'INFO' 'CUDA-enabled PyTorch compatibility will be verified during TTS installation.' $false
}

$results | Format-Table -AutoSize -Wrap

$failed = @(
    $results | Where-Object {
        $_.Required -eq 'Yes' -and $_.Status -eq 'FAIL'
    }
)

$warnings = @(
    $results | Where-Object { $_.Status -eq 'WARN' }
)

Write-Host ''

if ($failed.Count -gt 0) {
    Write-Host 'Result: Some selected components have missing prerequisites.' -ForegroundColor Red
    exit 1
}

if ($warnings.Count -gt 0) {
    Write-Host 'Result: No missing prerequisites detected; review compatibility warnings.' -ForegroundColor Yellow
    exit 0
}

Write-Host 'Result: Detected prerequisites satisfied.' -ForegroundColor Green
exit 0
