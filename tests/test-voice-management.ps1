#Requires -Version 5.1
$ErrorActionPreference='Stop'
if($env:WHAS_SANDBOX_TEST -ne '1'){throw 'Run voice management fixtures in Windows Sandbox only.'}
$repo=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('whas-voice-management-'+[guid]::NewGuid().ToString('N'))
try {
 New-Item -ItemType Directory -Path (Join-Path $fixture 'config'),(Join-Path $fixture 'tts'),(Join-Path $fixture 'voices/chatterbox-turbo'),(Join-Path $fixture 'voices/f5-tts') -Force|Out-Null
 Copy-Item (Join-Path $repo 'config/defaults.json') (Join-Path $fixture 'config/defaults.json')
 Copy-Item (Join-Path $repo 'tts/strategies') (Join-Path $fixture 'tts/strategies') -Recurse
 . (Join-Path $repo 'scripts/configuration.ps1')
 . (Join-Path $repo 'scripts/installation-state.ps1')
 . (Join-Path $repo 'tts/strategy-management.ps1')
 . (Join-Path $repo 'scripts/whas.ps1') -InstallPath $fixture
 $script:voiceFixtureState=[pscustomobject]@{Status='Installed';TtsStrategies=@(
  [pscustomobject]@{Id='chatterbox-turbo';Status='Installed';Context=[pscustomobject]@{VoicesPath='voices/chatterbox-turbo'}},
  [pscustomobject]@{Id='f5-tts';Status='Installed';Context=[pscustomobject]@{VoicesPath='voices/f5-tts'}})}
 function Read-StackInstallationState {param($Root,[switch]$ReadOnly) return $script:voiceFixtureState}
 foreach($file in @('c3po_prompt.pt','c3po_prompt.wav','orphan_prompt.wav','r2_prompt_prompt.pt')){[IO.File]::WriteAllText((Join-Path $fixture ('voices/chatterbox-turbo/'+$file)),'fixture')}
 foreach($file in @('complete.wav','complete.txt','incomplete.wav')){[IO.File]::WriteAllText((Join-Path $fixture ('voices/f5-tts/'+$file)),'fixture')}
 $inventory=Invoke-Whas @('tts','inventory')|ConvertFrom-Json
 $chatterbox=$inventory|Where-Object id -eq 'chatterbox-turbo'
 if(($chatterbox.voices -join ',') -cne 'default,c3po,r2_prompt' -or $chatterbox.referenceInventoryVersion -ne 1){throw 'Chatterbox inventory returned storage filenames or orphan WAVs'}
 $f5=$inventory|Where-Object id -eq 'f5-tts'
 if(($f5.voices -join ',') -cne 'default,complete'){throw 'F5 offered a recording without its transcript'}
 $null=Set-WhasSetting 'speech.voice' 'c3po' 'chatterbox-turbo'
 $config=Get-StackConfiguration $fixture
 if($config.tts.voiceDefaults.'chatterbox-turbo' -cne 'c3po' -or $config.tts.defaultVoice -cne 'default'){throw 'Engine default changed the global fallback or used a storage filename'}
 $before=Get-Content (Join-Path $fixture 'config/config.json') -Raw
 $rejected=$false;try{$null=Set-WhasSetting 'speech.voice' 'c3po_prompt' 'chatterbox-turbo'}catch{$rejected=$true}
 if(-not $rejected -or (Get-Content (Join-Path $fixture 'config/config.json') -Raw) -cne $before){throw 'Invalid default was accepted or changed settings'}
 # Old installed strategy manifests remain usable after the shared-core update.
 $manifest=Join-Path $fixture 'tts/strategies/chatterbox-turbo/manifest.json'
 $old=Get-Content $manifest -Raw|ConvertFrom-Json;$old.PSObject.Properties.Remove('voiceReference');$old|ConvertTo-Json -Depth 20|Set-Content $manifest
 $null=Set-WhasSetting 'speech.voice' 'r2_prompt' 'chatterbox-turbo'
 # Load the command helpers without starting a service or using audio.
 . (Join-Path $repo 'tts/tts.ps1') -InstallPath $fixture
 $failure=New-Object Management.Automation.ErrorRecord((New-Object IO.IOException('The server returned 404')),'Fixture404',[Management.Automation.ErrorCategory]::ObjectNotFound,$null)
 $failure.ErrorDetails=New-Object Management.Automation.ErrorDetails('{"error":"Unknown voice"}')
 if((Get-TtsServiceError $failure) -cne 'Unknown voice'){throw 'Service JSON error was hidden behind an HTTP status'}
 $listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0);$listener.Start();$port=$listener.LocalEndpoint.Port
 $server=[PowerShell]::Create();$null=$server.AddScript({param($socket)
  $client=$socket.AcceptTcpClient();try{$stream=$client.GetStream();$reader=New-Object IO.StreamReader($stream);while($reader.ReadLine()){}
   $body='{"error":"Unknown voice"}';$reply="HTTP/1.1 404 Not Found`r`nContent-Type: application/json`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n$body"
   $bytes=[Text.Encoding]::UTF8.GetBytes($reply);$stream.Write($bytes,0,$bytes.Length);$stream.Flush()
  }finally{$client.Dispose()}
 }).AddArgument($listener);$pending=$server.BeginInvoke()
 try {
  $detail=$null
  try{Invoke-WebRequest -Uri "http://127.0.0.1:$port/speak" -OutFile (Join-Path $fixture 'error-response.wav') -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop|Out-Null}catch{$detail=Get-TtsServiceError $_}
  if($detail -cne 'Unknown voice'){throw "HTTP response body was not preserved: $detail"}
 }finally{$listener.Stop();$server.EndInvoke($pending)|Out-Null;$server.Dispose()}
 $script:TtsDefaultVoice='c3po';$rejected=$false;try{Invoke-TtsVoiceRemoveCore 'c3po' -Confirmed}catch{$rejected=$_.Exception.Message -like '*another default*'}
 if(-not $rejected){throw 'Deleting the configured default voice was allowed'}
 Write-Host 'PASS: strategy voice IDs, incomplete references, per-engine defaults, legacy packages, service errors and default deletion guard'
}finally{
 $absolute=[IO.Path]::GetFullPath($fixture);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $absolute) -notmatch '^whas-voice-management-[a-f0-9]{32}$'){throw 'Unexpected voice fixture cleanup path'}
 if(Test-Path -LiteralPath $absolute){Remove-Item -LiteralPath $absolute -Recurse -Force}
}
