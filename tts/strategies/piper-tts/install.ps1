#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)]$Context, [switch]$PrepareOnly)
$ErrorActionPreference = 'Stop'

function Invoke-PiperTool {
    param([string]$Executable, [string[]]$Arguments)
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Executable @Arguments 2>&1 | ForEach-Object { Write-Host $_.ToString() }
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    if ($code -ne 0) { throw "Piper setup command failed (exit $code)." }
}

try {
    if ($Context.Engine -cne 'piper-tts' -or $Context.Device -cne 'cpu') { throw 'Piper requires a CPU strategy context.' }
    $environment = Join-Path $Context.InstallPath $Context.EnvironmentPath
    $python = Join-Path $environment 'Scripts/python.exe'
    $models = Join-Path $Context.InstallPath $Context.ModelsPath
    Invoke-PiperTool 'py.exe' @('-3.11','-c',"import struct,sys; assert sys.version_info[:2] == (3,11) and struct.calcsize('P') == 8")
    if (-not (Test-Path -LiteralPath $environment)) {
        Invoke-PiperTool 'py.exe' @('-3.11','-m','venv',$environment)
    }
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Piper environment is incomplete.' }
    Invoke-PiperTool $python @('-c',"import struct,sys; assert sys.version_info[:2] == (3,11) and struct.calcsize('P') == 8")
    if ($PrepareOnly) { Write-Host 'Piper Python environment prepared; speech dependencies are not installed.'; exit 0 }
    Invoke-PiperTool $python @('-m','pip','--isolated','--disable-pip-version-check','install',
        '--index-url','https://pypi.org/simple','--only-binary=:all:','--require-hashes','--no-cache-dir',
        '-r',(Join-Path $PSScriptRoot 'requirements.txt'))
    Invoke-PiperTool $python @('-m','pip','--disable-pip-version-check','check')
    Invoke-PiperTool $python @('-c',"from importlib.metadata import version; from piper import PiperVoice; import onnxruntime; assert version('piper-tts') == '1.8.0'; assert version('onnxruntime') == '1.31.0'; print('Piper imports and versions verified')")
    Invoke-PiperTool $python @((Join-Path $PSScriptRoot 'prepare_model.py'),$models)
    New-Item -ItemType Directory -Path (Join-Path $Context.InstallPath $Context.VoicesPath) -Force | Out-Null
    Write-Host 'Piper TTS installation completed (CPU).'
    exit 0
}
catch { Write-Error "Piper installation failed: $_" -ErrorAction Continue; exit 1 }
