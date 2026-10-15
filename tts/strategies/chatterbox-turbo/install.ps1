#Requires -Version 5.1

<#
.SYNOPSIS
    Installs Chatterbox Turbo for Windows Hybrid Agentic Stack.

.DESCRIPTION
    Creates an isolated Python 3.11 environment and installs
    Chatterbox Turbo 0.1.7.

    Called by the shared TTS coordinator with an installation context.
    Installs only into the supplied private environment and model directory.

    -PrepareOnly creates the Python environment without installing
    the Chatterbox dependencies.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]$Context,
    [string]$InstallPath,

    [ValidateSet('auto', 'cpu', 'cuda')]
    [string]$Device,

    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'

$InstallPath = $Context.InstallPath
$Device = $Context.Device

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$Executable,

        [string[]]$Arguments = @()
    )

    Write-Host ''
    Write-Host $Description -ForegroundColor Cyan

    $previousPreference = $ErrorActionPreference
    try {
        # Native stderr includes pip progress and import warnings. Preserve it
        # as diagnostic output; use the process exit code for success/failure.
        $ErrorActionPreference = 'Continue'
        & $Executable @Arguments 2>&1 | ForEach-Object { Write-Host $_.ToString() }
        $commandExitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }

    if ($commandExitCode -ne 0) {
        throw "$Description failed (exit code $commandExitCode)."
    }
}

function Test-NvidiaGpu {
    if ($null -eq (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
        return $false
    }

    try {
        $null = & nvidia-smi -L 2>$null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

try {
    if ($Device -notin @('cpu','cuda')) { throw 'The coordinator must resolve a supported device before calling this strategy.' }

    $venvPath = Join-Path $InstallPath $Context.EnvironmentPath
    $pythonPath = Join-Path $venvPath 'Scripts\python.exe'
    $serviceDirectory = Join-Path $InstallPath 'tts'
    $voicesDirectory = Join-Path $InstallPath $Context.VoicesPath

    Write-Host ''
    Write-Host 'Chatterbox Turbo Installation'
    Write-Host '============================'
    Write-Host "Directory: $InstallPath"
    Write-Host 'Python:    3.11 (64-bit)'

    if ($PrepareOnly) {
        Write-Host 'Mode:      Python environment only'
    }
    else {
        Write-Host "Device:    $Device"
    }

    if ($null -eq (Get-Command py -ErrorAction SilentlyContinue)) {
        throw 'Python launcher not found. Install Python 3.11.'
    }

    & py -3.11 --version

    if ($LASTEXITCODE -ne 0) {
        throw 'Python 3.11 was not found.'
    }

    # Use single quotes inside Python to avoid PowerShell 5.1 quoting issues.
    & py -3.11 -c "import struct, sys; print('Python architecture:', struct.calcsize('P') * 8, 'bit'); sys.exit(0 if sys.version_info[:2] == (3, 11) and struct.calcsize('P') * 8 == 64 else 1)"

    if ($LASTEXITCODE -ne 0) {
        throw 'A 64-bit Python 3.11 installation is required.'
    }

    if (Test-Path -LiteralPath $venvPath) {
        if (-not (Test-Path -LiteralPath $pythonPath -PathType Leaf)) {
            throw "Incomplete Python environment: $venvPath"
        }

        Write-Host 'Existing Python environment detected.'
    }
    else {
        if (-not (Test-Path -LiteralPath $InstallPath)) {
            New-Item `
                -ItemType Directory `
                -Path $InstallPath `
                -Force | Out-Null
        }

        Invoke-CheckedCommand `
            -Description 'Creating Python virtual environment' `
            -Executable 'py' `
            -Arguments @('-3.11', '-m', 'venv', $venvPath)
    }

    Invoke-CheckedCommand `
        -Description 'Checking virtual environment Python' `
        -Executable $pythonPath `
        -Arguments @('--version')

    Invoke-CheckedCommand `
        -Description 'Checking Python package manager' `
        -Executable $pythonPath `
        -Arguments @('-m', 'pip', '--version')

    # Fresh Python 3.11 environments may start with pip 22.3.1.
    # Upgrade packaging tools only inside this stack's virtual environment.
    # resemble-perth 1.0.1 imports pkg_resources, removed in setuptools 81+.
    # Keep setuptools below 81 until that dependency supports newer releases.
    # Use PyPI explicitly so build dependencies remain available.
    Invoke-CheckedCommand `
        -Description 'Updating virtual environment packaging tools' `
        -Executable $pythonPath `
        -Arguments @(
            '-m', 'pip', 'install', '--upgrade',
            '--index-url', 'https://pypi.org/simple',
            'pip', 'setuptools<81', 'wheel'
        )

    if ($PrepareOnly) {
        Write-Host ''
        Write-Host 'Python environment preparation completed.' `
            -ForegroundColor Green
        Write-Host "Python: $pythonPath"
        exit 0
    }

    if ($Device -eq 'cuda' -and -not (Test-NvidiaGpu)) {
        throw 'CUDA requested, but no NVIDIA GPU was detected.'
    }

    if ($Device -eq 'cuda') {
        $torchIndex = 'https://download.pytorch.org/whl/cu126'
        $expectedSuffix = '+cu126'
    }
    else {
        $torchIndex = 'https://download.pytorch.org/whl/cpu'
        $expectedSuffix = '+cpu'
    }

    # Pin the wheel build explicitly. PyPI provides general dependencies,
    # while the PyTorch index provides the selected CUDA/CPU wheels.
    # Without this, a package source build can fail when flit_core is
    # unavailable from the PyTorch-only index.
    Invoke-CheckedCommand `
        -Description "Installing PyTorch 2.6.0 ($Device)" `
        -Executable $pythonPath `
        -Arguments @(
            '-m', 'pip', 'install',
            '--index-url', 'https://pypi.org/simple',
            '--extra-index-url', $torchIndex,
            "torch==2.6.0$expectedSuffix",
            "torchaudio==2.6.0$expectedSuffix",
            "torchvision==0.21.0$expectedSuffix"
        )

    # Install Chatterbox without invoking its Git-based dependency.
    Invoke-CheckedCommand `
        -Description 'Installing Chatterbox TTS 0.1.7' `
        -Executable $pythonPath `
        -Arguments @(
            '-m', 'pip', 'install',
            '--no-deps',
            'chatterbox-tts==0.1.7'
        )

    # Dependency versions from the known-working Chatterbox installation.
    $dependencies = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'requirements.txt') | Where-Object { $_ -and -not $_.StartsWith('#') })

    Invoke-CheckedCommand `
        -Description 'Installing Chatterbox dependencies' `
        -Executable $pythonPath `
        -Arguments (
            @('-m', 'pip', 'install') + $dependencies
        )

    Invoke-CheckedCommand `
        -Description 'Checking dependency compatibility' `
        -Executable $pythonPath `
        -Arguments @('-m', 'pip', 'check')

    # Use a temporary Python file to avoid Windows PowerShell 5.1
    # stripping quotation marks from Python dictionary keys.
    $versionCheck = @'
import sys
from importlib.metadata import version

expected = {
    "chatterbox-tts": "0.1.7",
    "torch": "2.6.0",
    "torchaudio": "2.6.0",
    "torchvision": "0.21.0",
    "transformers": "5.2.0",
    "diffusers": "0.29.0",
    "numpy": "1.26.4",
}

suffix = sys.argv[1]

for name, wanted in expected.items():
    actual = version(name)
    print(f"{name}: {actual}")

    if name in ("torch", "torchaudio", "torchvision"):
        required = wanted + suffix
    else:
        required = wanted

    if actual != required:
        raise RuntimeError(
            f"{name}: expected {required}, found {actual}"
        )
'@

    $verifyScript = Join-Path $env:TEMP (
        'verify-chatterbox-' +
        [guid]::NewGuid().ToString('N') +
        '.py'
    )

    try {
        [System.IO.File]::WriteAllText(
            $verifyScript,
            $versionCheck,
            (New-Object System.Text.UTF8Encoding($false))
        )

        Invoke-CheckedCommand `
            -Description 'Verifying installed package versions' `
            -Executable $pythonPath `
            -Arguments @($verifyScript, $expectedSuffix)
    }
    finally {
        Remove-Item `
            -LiteralPath $verifyScript `
            -Force `
            -ErrorAction SilentlyContinue
    }

    # Perth silently replaces its watermarker class with None when an import
    # fails (for example if pkg_resources is unavailable). Check the actual
    # implementation rather than just the presence of the package.
    Invoke-CheckedCommand `
        -Description 'Verifying Perth watermarking implementation' `
        -Executable $pythonPath `
        -Arguments @(
            '-c',
            "from perth.perth_net.perth_net_implicit.perth_watermarker import PerthImplicitWatermarker; assert callable(PerthImplicitWatermarker), 'Perth watermarker is unavailable'; print('Perth watermarking import OK')"
        )

    Invoke-CheckedCommand `
        -Description 'Verifying Chatterbox Turbo import' `
        -Executable $pythonPath `
        -Arguments @(
            '-c',
            "from chatterbox.tts_turbo import ChatterboxTurboTTS; print('Chatterbox Turbo import OK')"
        )

    foreach ($directory in @(
        $serviceDirectory,
        $voicesDirectory
    )) {
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item `
                -ItemType Directory `
                -Path $directory `
                -Force | Out-Null
        }
    }

    if (-not $PrepareOnly) {
        Invoke-CheckedCommand -Description 'Preparing pinned Chatterbox model' -Executable $pythonPath `
            -Arguments @((Join-Path $PSScriptRoot 'prepare_model.py'), (Join-Path $InstallPath $Context.ModelsPath))
    }

    Write-Host ''
    Write-Host 'Chatterbox installation completed.' `
        -ForegroundColor Green

    Write-Host "Device:  $Device"
    Write-Host "Python:  $pythonPath"
    Write-Host "Service: $serviceDirectory"
    Write-Host "Voices:  $voicesDirectory"

    exit 0
}
catch {
    Write-Host ''
    Write-Host "TTS installation error: $($_.Exception.Message)" `
        -ForegroundColor Red

    exit 1
}
