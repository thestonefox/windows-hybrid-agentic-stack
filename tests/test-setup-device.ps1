#Requires -Version 5.1
$ErrorActionPreference='Stop'
if($env:WHAS_SANDBOX_TEST -ne '1'){throw 'Run this fixture in Windows Sandbox only.'}
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts/configuration.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('whas-device-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture|Out-Null
try {
 $config=Join-Path $fixture 'config.json';'{"tts":{"device":"cuda"}}'|Set-Content $config
 $hash=(Get-FileHash $config).Hash
 $catalog=@(Get-ChildItem (Join-Path $repo 'tts/strategies') -Directory|ForEach-Object{Get-Content (Join-Path $_.FullName 'manifest.json') -Raw|ConvertFrom-Json})|ConvertTo-Json -Depth 12
 $options=@{DefaultsJson=[IO.File]::ReadAllText((Join-Path $repo 'config/defaults.json'));StrategyCatalogJson=$catalog;Voice=$true;Core=$true;ConfigPath=$config;InstallPath=(Join-Path $fixture 'install');TtsEngine='chatterbox-turbo,piper-tts,f5-tts';Interactive=$false;ShowPlan=$false}
 $result=& (Join-Path $repo 'scripts/setup-preview.ps1') @options -TtsDevice auto
 if(($result.ConfigJson|ConvertFrom-Json).tts.device -ne 'auto' -or $result.StrategyManifestJsons.Count -ne 3){throw 'Automatic device override did not reach installation selection'}
 $result=& (Join-Path $repo 'scripts/setup-preview.ps1') @options -TtsDevice cpu
 if(($result.ConfigJson|ConvertFrom-Json).tts.device -ne 'cpu'){throw 'CPU choice was lost'}
 foreach($device in @('cuda','invalid')) {
  $rejected=$false
  try {$null=& (Join-Path $repo 'scripts/setup-preview.ps1') @options -TtsDevice $device} catch {
   if($device -eq 'cuda' -and $_.Exception.Message -notmatch 'piper-tts.*cuda.*cpu'){throw 'Unsupported-device error does not name the engine and supported choice'}
   $rejected=$true
  }
  if(-not $rejected){throw 'Invalid explicit speech device was accepted'}
 }
 $result=& (Join-Path $repo 'scripts/setup-preview.ps1') @options -TtsDevices 'chatterbox-turbo=cuda,piper-tts=cpu,f5-tts=auto'
 $resolved=$result.ConfigJson|ConvertFrom-Json
 foreach($pair in @(@('chatterbox-turbo','cuda'),@('piper-tts','cpu'),@('f5-tts','auto'))) {
  if((Get-TtsConfiguredDevice $resolved $pair[0]) -ne $pair[1]){throw 'Per-engine selection did not survive setup configuration'}
 }
 $roundtrip=Get-Content (Join-Path $repo 'config/defaults.json') -Raw|ConvertFrom-Json
 Merge-Configuration $roundtrip $resolved
 if(@(Assert-Configuration $roundtrip).Count){throw 'Per-engine device defaults fail persisted configuration validation'}
 $bad=$false;try {$null=& (Join-Path $repo 'scripts/setup-preview.ps1') @options -TtsDevices 'piper-tts=cuda'}catch{$bad=$true};if(-not $bad){throw 'Invalid per-engine device accepted'}
 function Test-TtsGpuAvailable {return $script:GpuPresent}
 $manifest=($catalog|ConvertFrom-Json)|Where-Object id -eq 'chatterbox-turbo'
 $script:GpuPresent=$true
 if((Resolve-TtsInstallDevice auto $manifest) -ne 'cuda'){throw 'Prefer GPU did not select detected GPU'}
 if((Resolve-TtsInstallDevice cpu $manifest) -ne 'cpu'){throw 'Explicit CPU ignored'}
 $script:GpuPresent=$false
 $fallback=@(Resolve-TtsInstallDevice auto $manifest 6>&1)
 if($fallback[-1] -ne 'cpu' -or -not @($fallback|Where-Object {$_ -like '*GPU unavailable - using CPU*'}).Count){throw 'Prefer GPU did not report fallback to CPU'}
 if((Get-FileHash $config).Hash -ne $hash){throw 'Preview changed retained configuration'}
 'PASS: retained CUDA config, automatic mixed-engine selection, explicit CPU, unsupported CUDA and invalid device rejection'
}finally{if([IO.Path]::GetFullPath($fixture).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) -and (Split-Path $fixture -Leaf) -match '^whas-device-[a-f0-9]{32}$'){Remove-Item -LiteralPath $fixture -Recurse -Force}}
