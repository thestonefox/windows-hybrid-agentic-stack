#Requires -Version 5.1
$ErrorActionPreference='Stop'
if($env:WHAS_SANDBOX_TEST -ne '1'){throw 'Run bundled maintenance fixtures in Windows Sandbox only.'}
$repo=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('whas-maintenance-test-'+[guid]::NewGuid().ToString('N'))
$root=Join-Path $fixture 'installation'
function Invoke-MaintenanceTest($Options,[int]$Expected=0) {
 $start=New-Object Diagnostics.ProcessStartInfo
 $start.FileName=Join-Path $fixture 'setup.exe';$start.Arguments=($Options|ForEach-Object {[WindowsHybridAgenticStack.GuiProcess]::Quote($_)}) -join ' '
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $p=[Diagnostics.Process]::Start($start)
 try{$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync();if(-not $p.WaitForExit(60000)){$p.Kill();throw 'Bundled maintenance timed out'};$text=$o.Result+$e.Result;if($p.ExitCode -ne $Expected){throw "Unexpected maintenance exit $($p.ExitCode): $text"};return $text}finally{$p.Dispose()}
}
try{
 New-Item -ItemType Directory -Path $fixture,(Join-Path $root 'config'),(Join-Path $root 'tts'),(Join-Path $root 'voices/chatterbox-turbo') -Force|Out-Null
 Copy-Item (Join-Path $repo 'config/defaults.json') (Join-Path $root 'config/defaults.json')
 Copy-Item (Join-Path $repo 'tts/strategies') (Join-Path $root 'tts/strategies') -Recurse
 . (Join-Path $repo 'scripts/installation-state.ps1')
 $state=[pscustomobject]@{SchemaVersion=2;InstallPath=$root;OwnerSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;InstallationId=[guid]::NewGuid().ToString('N');Status='Installed';Files=@();OriginalFiles=@();TtsStrategies=@([pscustomobject]@{Id='chatterbox-turbo';ApiVersion=1;Status='Installed';Context=[pscustomobject]@{InstallPath=$root;Engine='chatterbox-turbo';EnvironmentPath='tts/engines/chatterbox-turbo/.venv';ModelsPath='tts/engines/chatterbox-turbo/models';VoicesPath='voices/chatterbox-turbo';Device='cpu'}})}
 Write-StackInstallationState $root $state
 [IO.File]::WriteAllText((Join-Path $root 'voices/chatterbox-turbo/c3po_prompt.pt'),'fixture cache')
 $manifest=Join-Path $root 'tts/strategies/chatterbox-turbo/manifest.json'
 $legacy=Get-Content $manifest -Raw|ConvertFrom-Json;$legacy.PSObject.Properties.Remove('voiceReference');$legacy|ConvertTo-Json -Depth 20|Set-Content $manifest
 & (Join-Path $repo 'scripts/build-setup.ps1') -OutputPath (Join-Path $fixture 'setup.exe')|Out-Null
 Add-Type -AssemblyName System.Drawing,System.Windows.Forms,System.Web.Extensions
 Add-Type -Path (Join-Path $repo 'scripts/gui-host.cs') -ReferencedAssemblies System.dll,System.Core.dll,System.Drawing.dll,System.Windows.Forms.dll,System.Web.Extensions.dll
 $null=Invoke-MaintenanceTest @('--maintain','voice-default','--install-path',$root,'--tts-engine','chatterbox-turbo','--voice-name','c3po')
 $config=Get-Content (Join-Path $root 'config/config.json') -Raw|ConvertFrom-Json
 if($config.tts.voiceDefaults.'chatterbox-turbo' -cne 'c3po'){throw 'Bundled default writer rejected a legacy Chatterbox cache'}
 $before=Get-Content (Join-Path $root 'config/config.json') -Raw
 $invalid=Invoke-MaintenanceTest @('--maintain','voice-default','--install-path',$root,'--tts-engine','chatterbox-turbo','--voice-name','missing') 1
 if($invalid -notmatch 'unavailable' -or (Get-Content (Join-Path $root 'config/config.json') -Raw) -cne $before){throw 'Invalid default changed configuration'}
 $null=Invoke-MaintenanceTest @('--maintain','remove-route','--install-path',$root,'--feature','local')
 $null=Invoke-MaintenanceTest @('--maintain','speech-timeout','--install-path',$root,'--idle-timeout-minutes','30')
 $timeoutConfig=Get-Content (Join-Path $root 'config/config.json') -Raw|ConvertFrom-Json
 if($timeoutConfig.tts.idleTimeoutMinutes -isnot [int] -or $timeoutConfig.tts.idleTimeoutMinutes -ne 30){throw 'Idle timeout was not saved as integer minutes'}
 $null=Invoke-MaintenanceTest @('--maintain','speech-timeout','--install-path',$root,'--idle-timeout-minutes','0')
 $beforeTimeout=[IO.File]::ReadAllText((Join-Path $root 'config/config.json'))
 foreach($badTimeout in @('-1','1.5','oops','2147483648','')) {
  $null=Invoke-MaintenanceTest @('--maintain','speech-timeout','--install-path',$root,'--idle-timeout-minutes',$badTimeout) 1
  if([IO.File]::ReadAllText((Join-Path $root 'config/config.json')) -cne $beforeTimeout){throw 'Invalid timeout changed saved settings'}
 }
 if((Get-Content (Join-Path $root 'config/config.json') -Raw|ConvertFrom-Json).tts.idleTimeoutMinutes -ne 0){throw 'Zero did not disable idle shutdown'}
 $config=Get-Content (Join-Path $root 'config/config.json') -Raw|ConvertFrom-Json
 if($config.agents.local.enabled -ne $false -or $config.agents.cloud.enabled -ne $true -or $config.tts.voiceDefaults.'chatterbox-turbo' -cne 'c3po'){throw 'Route removal changed unrelated settings'}
 if(-not (Test-Path (Join-Path $root 'voices/chatterbox-turbo/c3po_prompt.pt'))){throw 'Route removal deleted personal voices'}
 # Loading bundled speech must not interpret installed helper scripts. This
 # fixture has no installed helpers/runtime; fail clearly after bundled loading.
 $speech=Invoke-MaintenanceTest @('--maintain','speak','--install-path',$root,'--speech-text','fixture') 1
 if($speech -match 'outside the bundled|not recognized|not a bundled setup asset'){throw "Bundled speech helper source mismatch: $speech"}
 $runtimeFolder=Join-Path $root 'tts/engines/chatterbox-turbo';New-Item -ItemType Directory -Path $runtimeFolder -Force|Out-Null
 [pscustomobject]@{schemaVersion=1;engine='chatterbox-turbo';environmentPath='tts/engines/chatterbox-turbo/.venv';modelsPath='tts/engines/chatterbox-turbo/models';voicesPath='voices/chatterbox-turbo';device='cpu';backendPath=('tts/strategies/chatterbox-turbo/'+$legacy.entrypoints.backend);capabilities=$legacy.capabilities}|ConvertTo-Json -Depth 12|Set-Content (Join-Path $runtimeFolder 'runtime.json')
 $missing=Invoke-MaintenanceTest @('--maintain','voice-add','--install-path',$root,'--tts-engine','chatterbox-turbo','--voice-name','new-voice','--reference-path',(Join-Path $fixture 'missing.wav')) 1
 if($missing -notmatch 'Reference WAV not found'){throw "Bundled voice import did not validate its recording: $missing"}
 $protected=Invoke-MaintenanceTest @('--maintain','voice-remove','--install-path',$root,'--tts-engine','chatterbox-turbo','--voice-name','c3po') 1
 if($protected -notmatch 'another default voice'){throw "Bundled deletion did not protect the saved default: $protected"}
 $state.OwnerSid='foreign-user';Write-StackInstallationState $root $state
 $foreign=Invoke-MaintenanceTest @('--maintain','voice-default','--install-path',$root,'--tts-engine','chatterbox-turbo','--voice-name','default') 1
 if($foreign -notmatch 'foreign installation'){throw 'Maintenance accepted foreign ownership'}
 $state.OwnerSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Write-StackInstallationState $root $state
 # Exercise the actual GUI speech dispatcher without a model or audio. The
 # fake speech layer tracks the running engine separately from its default.
 $script:mockSpeechPath=Join-Path $fixture 'mock-speech.ps1'
 @'
param([string]$InstallPath)
function Get-TtsDefaultEngine {return $script:DefaultForTest}
function tts-say {
 param([string]$Text,[string]$Engine,[string]$Voice)
 $script:SpokenEngine=if($Engine){$Engine}else{$script:ActiveForTest}
 $script:ActiveForTest=$script:SpokenEngine
 $script:SpeechCalls++
}
'@|Set-Content -LiteralPath $script:mockSpeechPath
 $loader=Get-Item Function:Get-StackSetupScript -ErrorAction SilentlyContinue
 try {
  function Get-StackSetupScript {param([string]$Path) if([IO.Path]::GetFullPath($Path) -ieq [IO.Path]::GetFullPath((Join-Path $repo 'tts/tts.ps1'))){return $script:mockSpeechPath};return $Path}
  $script:SpeechCalls=0
  foreach($default in @('chatterbox-turbo','piper-tts')) {
   $other=if($default -eq 'piper-tts'){'chatterbox-turbo'}else{'piper-tts'}
   $script:DefaultForTest=$default;$script:ActiveForTest=$other
   . (Join-Path $repo 'scripts/gui-maintenance.ps1') -InstallPath $root -Action speak -Text 'Assistant answer'
   if($script:SpokenEngine -cne $default){throw 'Assistant preferred the running engine over the saved default'}
   . (Join-Path $repo 'scripts/gui-maintenance.ps1') -InstallPath $root -Action speak -Text 'Preview' -Engine $other
   if($script:SpokenEngine -cne $other -or $script:DefaultForTest -cne $default){throw 'Preview ignored its selection or changed the default'}
   . (Join-Path $repo 'scripts/gui-maintenance.ps1') -InstallPath $root -Action speak -Text 'Next assistant answer'
   if($script:SpokenEngine -cne $default){throw 'A preview changed subsequent Assistant speech'}
  }
  $script:DefaultForTest=$null;$calls=$script:SpeechCalls;$rejected=$false
  try{. (Join-Path $repo 'scripts/gui-maintenance.ps1') -InstallPath $root -Action speak -Text 'No default'}catch{$rejected=$_.Exception.Message -like '*Choose a default speech engine*'}
  if(-not $rejected -or $script:SpeechCalls -ne $calls){throw 'Missing default silently used an active engine'}
 }finally{if($loader){Set-Item Function:Get-StackSetupScript $loader.ScriptBlock}else{Remove-Item Function:Get-StackSetupScript}}
 Write-Host 'PASS: bundled legacy voice defaults, invalid defaults, route removal boundaries, speech loading and ownership guards'
 Write-Host 'PASS: Assistant uses the saved engine after default changes and previews; explicit previews remain separate'
}finally{
 $absolute=[IO.Path]::GetFullPath($fixture);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $absolute) -notmatch '^whas-maintenance-test-[a-f0-9]{32}$'){throw 'Unexpected maintenance fixture cleanup'}
 if(Test-Path -LiteralPath $absolute){Remove-Item -LiteralPath $absolute -Recurse -Force}
}
