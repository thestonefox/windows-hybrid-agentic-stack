#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)]$Context, [switch]$PrepareOnly)
$ErrorActionPreference = 'Stop'

function Invoke-F5Tool {
    param([string]$Executable, [string[]]$Arguments)
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Executable @Arguments 2>&1 | ForEach-Object { Write-Host $_.ToString() }
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    if ($code -ne 0) { throw "F5 setup command failed (exit $code)." }
}

try {
    if ($Context.Engine -cne 'f5-tts' -or $Context.Device -notin @('cpu','cuda')) { throw 'F5 requires a CPU or CUDA strategy context.' }
    Write-Host 'F5 pretrained weights: CC-BY-NC-4.0 (noncommercial use only).'
    $environment = Join-Path $Context.InstallPath $Context.EnvironmentPath
    $python = Join-Path $environment 'Scripts/python.exe'
    $models = Join-Path $Context.InstallPath $Context.ModelsPath
    Invoke-F5Tool 'py.exe' @('-3.11','-c',"import struct,sys; assert sys.version_info[:2] == (3,11) and struct.calcsize('P') == 8")
    if (-not (Test-Path -LiteralPath $environment)) {
        Invoke-F5Tool 'py.exe' @('-3.11','-m','venv',$environment)
    }
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'F5 environment is incomplete.' }
    Invoke-F5Tool $python @('-c',"import struct,sys; assert sys.version_info[:2] == (3,11) and struct.calcsize('P') == 8")
    if ($PrepareOnly) { Write-Host 'F5 Python environment prepared; speech dependencies are not installed.'; exit 0 }
    # All artifacts are explicit HTTPS URLs with SHA256, including the build
    # tools. Do not let source-build isolation fetch unpinned dependencies.
    Invoke-F5Tool $python @('-m','pip','--isolated','--disable-pip-version-check','install',
        '--no-index','--no-deps','--require-hashes','--no-cache-dir',
        '-r',(Join-Path $PSScriptRoot 'bootstrap.txt'))
    Invoke-F5Tool $python @('-m','pip','--isolated','--disable-pip-version-check','install',
        '--no-index','--no-deps','--no-build-isolation','--require-hashes','--no-cache-dir',
        '-r',(Join-Path $PSScriptRoot ("requirements-$($Context.Device).txt")),
        '-r',(Join-Path $PSScriptRoot 'requirements.txt'))
    Invoke-F5Tool $python @('-m','pip','--disable-pip-version-check','check')
    Invoke-F5Tool $python @((Join-Path $PSScriptRoot 'prepare_model.py'),$models)
    # Import in the same private cache/offline configuration as the service.
    Invoke-F5Tool $python @('-B',(Join-Path $PSScriptRoot 'prepare_model.py'),$models,'--verify-runtime',$Context.Device)
    New-Item -ItemType Directory -Path (Join-Path $Context.InstallPath $Context.VoicesPath) -Force | Out-Null
    Write-Host "F5-TTS installation completed ($($Context.Device))."
    exit 0
}
catch { Write-Error "F5 installation failed: $_" -ErrorAction Continue; exit 1 }
