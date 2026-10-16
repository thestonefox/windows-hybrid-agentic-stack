#Requires -Version 5.1
# Real Python worker lifecycle; standard-library fixture backends, no ML/audio.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts/installation-state.ps1')
$beforePath=Get-StackRawUserPath | ConvertTo-Json -Compress
$beforePolicies=Get-ExecutionPolicy -List | ConvertTo-Json -Compress
$originalUser=$env:USERPROFILE; $originalPath=$env:Path
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('whas-process-switch-'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $fixture 'source'; $install=Join-Path $fixture 'installed'
$python=(Get-Command python -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$savedPython=$env:WHAS_TEST_PYTHON
$env:WHAS_TEST_PYTHON=$python
function Assert-True { param([bool]$Value,[string]$Message) if(-not $Value){throw "FAIL: $Message"}; Write-Host "PASS: $Message" }
function Write-Fixture {
    param([string]$Path,[string]$Text)
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))
}
function Wait-Service {
    param([string]$Engine)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($watch.Elapsed.TotalSeconds -lt 30){
        try { $status=Invoke-RestMethod "http://127.0.0.1:$port/status" -TimeoutSec 2; if($status.engine -ceq $Engine){return $status} } catch {}
        Start-Sleep -Milliseconds 100
    }
    throw "Worker did not become ready: $Engine"
}
try {
    [IO.Directory]::CreateDirectory($source) | Out-Null
    foreach($name in @('scripts','config','tts')){Copy-Item -LiteralPath (Join-Path $repo $name) -Destination (Join-Path $source $name) -Recurse}
    foreach($name in @('install.ps1','uninstall.ps1')){Copy-Item -LiteralPath (Join-Path $repo $name) -Destination (Join-Path $source $name)}
    $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
    $listener.Start(); try{$port=$listener.LocalEndpoint.Port}finally{$listener.Stop()}
    $defaultsPath=Join-Path $source 'config/defaults.json'
    $defaults=Get-Content -LiteralPath $defaultsPath -Raw | ConvertFrom-Json
    $defaults.tts.port=$port
    [IO.File]::WriteAllText($defaultsPath,($defaults | ConvertTo-Json -Depth 12))
    Write-Fixture (Join-Path $source 'scripts/check-prerequisites.ps1') 'param([switch]$Cloud,[switch]$Local,[switch]$Voice,[string]$StrategyManifestJson); exit 0'
    foreach($id in @('fixture-one','fixture-two')){
        $package=Join-Path $source "tts/strategies/$id"
        $manifest=Get-Content -LiteralPath (Join-Path $repo 'tts/strategies/chatterbox-turbo/manifest.json') -Raw | ConvertFrom-Json
        $manifest.id=$id; $manifest.name=$id; $manifest.models=@(); $manifest.devices=@('cpu')
        $manifest.files=@('install.ps1','uninstall.ps1','backend.py')
        $manifest.capabilities.voiceCloning=($id -eq 'fixture-two')
        if($id -eq 'fixture-two'){$manifest | Add-Member -NotePropertyName voiceReference -NotePropertyValue ([pscustomobject]@{transcriptRequired=$true})}
        Write-Fixture (Join-Path $package 'manifest.json') ($manifest | ConvertTo-Json -Depth 12)
        Write-Fixture (Join-Path $package 'install.ps1') @'
param($Context,[switch]$PrepareOnly)
$ErrorActionPreference='Stop'
$venv=Join-Path $Context.InstallPath $Context.EnvironmentPath
if(-not(Test-Path -LiteralPath (Join-Path $venv 'Scripts/python.exe'))){
    & $env:WHAS_TEST_PYTHON -m venv --without-pip $venv
    if($LASTEXITCODE -ne 0){throw 'Fixture environment creation failed'}
}
[IO.Directory]::CreateDirectory((Join-Path $Context.InstallPath $Context.ModelsPath)) | Out-Null
exit 0
'@
        Write-Fixture (Join-Path $package 'uninstall.ps1') 'param($Context); exit 0'
        Write-Fixture (Join-Path $package 'backend.py') @'
import io, wave
class Backend:
    loaded_voice='default'
    def load(self): pass
    def close(self): pass
    def list_voices(self): return ['default']
    def add_voice(self,name,source): pass
    def remove_voice(self,name): pass
    def synthesise(self,text,voice):
        result=io.BytesIO()
        with wave.open(result,'wb') as wav:
            wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(24000)
            wav.writeframes(b'\x01\x00'*2400)
        return result.getvalue()
def create_backend(context): return Backend()
'@
    }
    $env:USERPROFILE=Join-Path $fixture 'user'
    & (Join-Path $source 'install.ps1') -Voice -TtsEngine 'fixture-one,fixture-two' -Yes -PersistCommandPath $false -InstallPath $install
    Assert-True ($LASTEXITCODE -eq 0) 'Two fixture engines installed with private real Python runtimes'
    $bin=Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack/bin'
    & (Join-Path $bin 'tts-start.exe') --engine fixture-one
    Assert-True ($LASTEXITCODE -eq 0) 'Native first-engine start returns'
    $first=Wait-Service fixture-one
    $firstPid=[int][IO.File]::ReadAllText((Join-Path $install 'tts/service.pid'))
    $reference=Join-Path $fixture 'sample.wav'; Write-Fixture $reference 'fixture'
    $previousPreference=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        $output=@(& (Join-Path $bin 'tts-voice-add.exe') -Path $reference -Name custom --engine fixture-two 2>&1)
        $rejectedExit=$LASTEXITCODE
    }
    finally { $ErrorActionPreference=$previousPreference }
    Assert-True ($rejectedExit -ne 0 -and ($output -join "`n") -like '*Expected:*.txt*') 'Missing transcript rejected before switching the real worker'
    Assert-True ((Wait-Service fixture-one).engine -ceq 'fixture-one') 'Original engine still runs after rejected voice input'
    & (Join-Path $bin 'tts-start.exe') --engine fixture-two
    Assert-True ($LASTEXITCODE -eq 0) 'Native switch to another installed engine returns'
    $second=Wait-Service fixture-two
    $old=Get-Process -Id $firstPid -ErrorAction SilentlyContinue
    Assert-True ($null -eq $old) 'Previous engine launcher exited before the replacement became ready'
    $wav=Join-Path $fixture 'result.wav'
    Invoke-WebRequest -Uri "http://127.0.0.1:$port/speak" -Method Post -ContentType 'application/json' -Body '{"text":"fixture","voice":"default"}' -OutFile $wav -UseBasicParsing | Out-Null
    Assert-True ((Get-Item -LiteralPath $wav).Length -gt 44) 'Replacement worker generates WAV bytes without playback'
    & (Join-Path $source 'uninstall.ps1') -InstallPath $install -Apply -RetainManagedModels -PersistCommandPath $false -Confirm:$false
    Assert-True ($LASTEXITCODE -eq 0 -and -not(Test-Path -LiteralPath $install)) 'Full uninstall stops active worker and removes both private runtimes'
    $responding=$false; try{$null=Invoke-RestMethod "http://127.0.0.1:$port/status" -TimeoutSec 2;$responding=$true}catch{}
    Assert-True (-not $responding) 'No speech service remains after cleanup'
}
finally {
    try {
        if(Test-Path -LiteralPath (Join-Path $install '.whas-installation.json')){
            & (Join-Path $source 'uninstall.ps1') -InstallPath $install -Apply -RetainManagedModels -PersistCommandPath $false -Confirm:$false
            if($LASTEXITCODE -ne 0){throw 'Fixture rollback failed; retained for inspection'}
        }
        $absolute=[IO.Path]::GetFullPath($fixture); $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
        if(-not $absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $absolute) -notmatch '^whas-process-switch-[a-f0-9]{32}$'){throw 'Unexpected fixture cleanup path'}
        if(Test-Path -LiteralPath $absolute){Remove-Item -LiteralPath $absolute -Recurse -Force}
    }
    finally {
        $env:USERPROFILE=$originalUser; $env:Path=$originalPath; $env:WHAS_TEST_PYTHON=$savedPython
        Assert-True ((Get-StackRawUserPath | ConvertTo-Json -Compress) -ceq $beforePath) 'Saved PATH unchanged'
        Assert-True ((Get-ExecutionPolicy -List | ConvertTo-Json -Compress) -ceq $beforePolicies) 'Execution policies unchanged'
    }
}
