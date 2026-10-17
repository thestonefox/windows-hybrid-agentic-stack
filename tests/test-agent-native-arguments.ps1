#Requires -Version 5.1
$ErrorActionPreference='Stop'
if($env:WHAS_SANDBOX_TEST -ne '1'){throw 'Run native argument fixtures in Windows Sandbox only.'}
$repo=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('whas-native-arguments-'+[guid]::NewGuid().ToString('N'))
$savedPath=$env:Path;$savedCapture=$env:WHAS_NATIVE_CAPTURE
try {
 New-Item -ItemType Directory -Path (Join-Path $fixture 'config'),(Join-Path $fixture 'scripts')|Out-Null
 Copy-Item (Join-Path $repo 'config/defaults.json') (Join-Path $fixture 'config/defaults.json')
 Copy-Item (Join-Path $repo 'scripts/configuration.ps1') (Join-Path $fixture 'scripts/configuration.ps1')
 [IO.File]::WriteAllText((Join-Path $fixture 'opencode.json'),'{}')
 $env:WHAS_NATIVE_CAPTURE=Join-Path $fixture 'argv.json'
 Add-Type -TypeDefinition @'
using System;using System.IO;using System.Web.Script.Serialization;
public static class NativeArgumentFixture {
 public static int Main(string[] args){
  Console.OutputEncoding=new System.Text.UTF8Encoding(false);
  File.WriteAllText(Environment.GetEnvironmentVariable("WHAS_NATIVE_CAPTURE"),new JavaScriptSerializer().Serialize(args));
  File.WriteAllText(Environment.GetEnvironmentVariable("WHAS_NATIVE_CAPTURE")+".cwd",Directory.GetCurrentDirectory());
  if(Array.IndexOf(args,"--stderr-flood")>=0) for(int i=0;i<10000;i++) Console.Error.WriteLine("diagnostic-"+i);
  if(Array.IndexOf(args,"--failure")>=0){Console.Error.WriteLine("fixture failure");return 7;}
  Console.WriteLine("{\"type\":\"text\",\"sessionID\":\"ses_fixture\",\"part\":{\"text\":\"caf\u00e9 \u65e5\u672c\u8a9e\"}}");return 0;
 }
}
'@ -OutputAssembly (Join-Path $fixture 'opencode.exe') -OutputType ConsoleApplication -ReferencedAssemblies System.dll,System.Web.Extensions.dll
 $env:Path=$fixture+';'+$env:Path
 . (Join-Path $repo 'scripts/agent-commands.ps1') -InstallPath $fixture
 $prompt='can you write a file called "blah.txt" in here "D:\Work\Web Projects\voice test\voices" with the content of "weeb"'
 $unicode='caf'+[char]0xE9+' '+[char]0x65E5+[char]0x672C+[char]0x8A9E
 $values=@('run','', $prompt, 'D:\Web Projects\', 'slashes\\"quoted"', "first`r`nsecond",$unicode,'literal & | ; $() ` > <','["D:\\Web Projects\\voices"]')
 $null=Invoke-AgentOpenCode $values
 $actual=Get-Content -LiteralPath $env:WHAS_NATIVE_CAPTURE -Raw -Encoding UTF8|ConvertFrom-Json
 if($actual.Count -ne $values.Count){throw 'Native argument count changed'}
 for($i=0;$i -lt $values.Count;$i++){if($actual[$i] -cne $values[$i]){throw "Native argument $i was corrupted"}}
 $taskFolder=Join-Path $fixture 'Web Projects';New-Item -ItemType Directory -Path $taskFolder|Out-Null
 Push-Location -LiteralPath $taskFolder
 try{$null=Invoke-AgentOpenCode @('run',$prompt);if([IO.File]::ReadAllText($env:WHAS_NATIVE_CAPTURE+'.cwd') -cne $taskFolder){throw 'Native request lost the PowerShell working folder'}}finally{Pop-Location}
 foreach($kind in @('agentdo','localagentdo')) {
  $answer=@(Invoke-AgentStackTask -Kind $kind -Arguments @($prompt) -StrictOutcome) -join "`n"
  $actual=Get-Content -LiteralPath $env:WHAS_NATIVE_CAPTURE -Raw -Encoding UTF8|ConvertFrom-Json
  if($actual[-1] -cne $prompt -or $answer -cne $unicode){throw "Task wrapper $kind corrupted the literal prompt or UTF-8 answer"}
 }
 $null=Invoke-AgentStackTask -Kind agentdo -Arguments @('--log',$prompt) -StrictOutcome
 if((Get-Content -LiteralPath $env:WHAS_NATIVE_CAPTURE -Raw -Encoding UTF8|ConvertFrom-Json)[-1] -cne $prompt){throw 'Raw-log path corrupted the prompt'}
 $output=@(Invoke-AgentOpenCode @('--stderr-flood'))
 if($LASTEXITCODE -ne 0 -or $output.Count -ne 10001 -or $output -cnotcontains 'diagnostic-9999'){throw 'Concurrent stderr drain lost output or exit status'}
 $output=@(Invoke-AgentOpenCode @('--failure'))
 if($LASTEXITCODE -ne 7 -or $output -cnotcontains 'fixture failure'){throw 'Native failure status or diagnostic was lost'}
 if((ConvertTo-AgentNativeArgument '') -cne '""'){throw 'Empty argument was not encoded'}
 $rejected=$false;try{ConvertTo-AgentNativeArgument ([string][char]0)|Out-Null}catch{$rejected=$true};if(-not $rejected){throw 'Null character was accepted'}
 Write-Host 'PASS: exact native arguments, quoted workspace paths, multiline/Unicode, task wrappers, raw output, pipe draining and error exits'
} finally {
 $env:Path=$savedPath;$env:WHAS_NATIVE_CAPTURE=$savedCapture
 $absolute=[IO.Path]::GetFullPath($fixture);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $absolute) -notmatch '^whas-native-arguments-[a-f0-9]{32}$'){throw 'Unexpected native-argument fixture path'}
 if(Test-Path -LiteralPath $absolute){Remove-Item -LiteralPath $absolute -Recurse -Force}
}
