#Requires -Version 5.1

<#
.SYNOPSIS
    Read-only prerequisite checker for Windows Hybrid Agentic Stack.

.DESCRIPTION
    Checks prerequisites for cloud agents, local agents and
    Chatterbox Turbo TTS.

    For TTS, requires:
      - 64-bit Python 3.11
      - Microsoft Visual C++ Redistributable (x64)

    An NVIDIA GPU is optional. Without one, the TTS installer
    selects CPU-only PyTorch.

    This script does not install or change anything.

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

    # Discover installations registered with the Windows launcher.
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
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $pythonRoot = Join-Path $env:LOCALAPPDATA 'Programs\Python'

        if (Test-Path -LiteralPath $pythonRoot -PathType Container) {
            Get-ChildItem $pythonRoot -Directory -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $path = Join-Path $_.FullName 'python.exe'

                    if (Test-Path -LiteralPath $path -PathType Leaf) {
                        $candidates.Add($path)
                    }
                }
        }
    }

    $installations = @()

    foreach ($path in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        try {
            # chr() avoids native-command argument quoting issues
            # in Windows PowerShell 5.1.
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

function Get-VcRedistributable {
    # Microsoft's supported Visual C++ 2015-2022/2026
    # redistributables register installation information here.
    #
    # Check both registry views so detection works if the
    # prerequisite checker is launched from 32-bit PowerShell.
    $subkey = 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'

    foreach ($view in @(
        [Microsoft.Win32.RegistryView]::Registry64,
        [Microsoft.Win32.RegistryView]::Registry32
    )) {
        $base = $null
        $key = $null

        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                [Microsoft.Win32.RegistryHive]::LocalMachine,
                $view
            )

            $key = $base.OpenSubKey($subkey)

            if ($null -eq $key) {
                continue
            }

            $installed = $key.GetValue('Installed', 0)

            if ([int]$installed -ne 1) {
                continue
            }

            $version = [string]$key.GetValue('Version', '')

            if ([string]::IsNullOrWhiteSpace($version)) {
                $major = $key.GetValue('Major', 0)
                $minor = $key.GetValue('Minor', 0)
                $build = $key.GetValue('Bld', 0)
                $revision = $key.GetValue('Rbld', 0)

                $version = "$major.$minor.$build.$revision"
            }

            return [pscustomobject]@{
                Version = $version
                View    = $view.ToString()
            }
        }
        catch {
            # Missing or inaccessible registry entries are
            # treated as not detected, never as installed.
        }
        finally {
            if ($null -ne $key) {
                $key.Close()
            }

            if ($null -ne $base) {
                $base.Close()
            }
        }
    }

    return $null
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

if (
    $psVersion.Major -ge 5 -and
    -not ($psVersion.Major -eq 5 -and $psVersion.Minor -lt 1)
) {
    Add-Check 'PowerShell' 'PASS' "$psVersion" $true
}
else {
    Add-Check 'PowerShell' 'FAIL' "PowerShell $psVersion is below the required version 5.1." $true
}

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
    elseif ($effective -in @('Restricted', 'AllSigned') -and $Host.Name -eq 'WindowsHybridAgenticStack') {
        Add-Check 'Execution policy' 'PASS' "Current policy: $effective. Application-hosted check; policy unchanged." $false
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
    Add-Check 'Cloud provider access' 'INFO' 'Authentication and model access must be verified during setup.' $false
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

# Python, Visual C++ and NVIDIA are relevant only to TTS.
if ($Voice) {
    $pythons = @(Get-PythonInstallations)

    # The TTS installer explicitly uses "py -3.11".
    $compatible = @(
        $pythons | Where-Object {
            $_.Bits -eq 64 -and
            $_.Version.Major -eq 3 -and
            $_.Version.Minor -eq 11
        }
    )

    $launcher = Get-Executable 'py.exe'

    if ($compatible.Count -gt 0 -and $launcher) {
        $python = $compatible | Select-Object -First 1

        # Also verify that the precise interpreter requested by the
        # TTS installer is available through the Python launcher.
        $launcherWorks = $false

        try {
            & $launcher.Source -3.11 -c "import struct,sys; sys.exit(0 if sys.version_info[:2] == (3,11) and struct.calcsize('P')*8 == 64 else 1)" 2>$null

            $launcherWorks = ($LASTEXITCODE -eq 0)
        }
        catch {
            $launcherWorks = $false
        }

        if ($launcherWorks) {
            Add-Check 'Python 3.11' 'PASS' "Python $($python.Version), 64-bit - $($python.Path)" $true
        }
        else {
            Add-Check 'Python 3.11' 'FAIL' '64-bit Python 3.11 was found, but the Python launcher could not run it using py -3.11.' $true
        }
    }
    elseif ($compatible.Count -gt 0) {
        Add-Check 'Python 3.11' 'FAIL' '64-bit Python 3.11 found, but py.exe is missing. Install the Windows Python launcher.' $true
    }
    else {
        Add-Check 'Python 3.11' 'FAIL' '64-bit Python 3.11 not found. Install with: winget install --id Python.Python.3.11 --exact --source winget' $true
    }

    # Microsoft Visual C++ runtime is needed for PyTorch DLLs.
    $vcRuntime = Get-VcRedistributable

    if ($null -ne $vcRuntime) {
        Add-Check `
            'Visual C++ x64' `
            'PASS' `
            "Microsoft Visual C++ Redistributable x64 detected ($($vcRuntime.Version))." `
            $true
    }
    else {
        Add-Check `
            'Visual C++ x64' `
            'FAIL' `
            'Microsoft Visual C++ Redistributable x64 not detected. Install with: winget install --id Microsoft.VCRedist.2015+.x64 --exact --source winget' `
            $true
    }

    # An NVIDIA GPU is optional; CPU TTS is supported.
    $nvidia = Get-Executable 'nvidia-smi.exe'

    if ($nvidia) {
        try {
            $gpu = & $nvidia.Source --query-gpu=name,driver_version,memory.total --format=csv,noheader,nounits 2>$null

            if ($LASTEXITCODE -eq 0 -and $gpu) {
                Add-Check 'NVIDIA GPU' 'PASS' (($gpu | Out-String).Trim()) $false
            }
            else {
                Add-Check 'NVIDIA GPU' 'WARN' 'NVIDIA GPU query failed; the TTS installer may select CPU mode.' $false
            }
        }
        catch {
            Add-Check 'NVIDIA GPU' 'WARN' $_.Exception.Message $false
        }
    }
    else {
        Add-Check 'NVIDIA GPU' 'INFO' 'No NVIDIA GPU detected. The TTS installer will select CPU-only PyTorch by default.' $false
    }

    Add-Check 'CUDA/PyTorch' 'INFO' 'The TTS installer installs CPU or CUDA 12.6 PyTorch and verifies its dependencies.' $false
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
