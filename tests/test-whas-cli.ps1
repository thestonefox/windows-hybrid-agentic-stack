#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts/installation-state.ps1')
. (Join-Path $repo 'scripts/command-registration.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('whas-cli-'+[guid]::NewGuid().ToString('N'))
$root=Join-Path $fixture 'installation'
. (Join-Path $repo 'scripts/agent-commands.ps1') -InstallPath $root
$savedPath=$env:Path
$savedArgs=$env:WHAS_TEST_ARGUMENTS
$savedUser=$env:USERPROFILE
function Invoke-WhasTest {
    param([string[]]$Options,[int]$Expected=0)
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Join-Path $fixture 'registration/bin/whas.exe'
    $start.WorkingDirectory=$ExecutionContext.SessionState.Path.CurrentFileSystemLocation.Path
    $start.Arguments=(@($Options|ForEach-Object {ConvertTo-AgentNativeArgument $_}) -join ' ')
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $start.StandardOutputEncoding=New-Object Text.UTF8Encoding($false);$start.StandardErrorEncoding=New-Object Text.UTF8Encoding($false)
    $process=[Diagnostics.Process]::Start($start)
    try{$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();if(-not $process.WaitForExit(30000)){$process.Kill();throw 'CLI fixture timed out'};$result=$stdout.Result+$stderr.Result;if($process.ExitCode -ne $Expected){throw "Unexpected exit for $Options : $result"};return $result}finally{$process.Dispose()}
}
try {
    [IO.Directory]::CreateDirectory($fixture)|Out-Null
    $env:USERPROFILE=Join-Path $fixture 'user'
    [IO.Directory]::CreateDirectory($env:USERPROFILE)|Out-Null
    $session=Start-StackInstallationTracking $root
    foreach ($relative in @('scripts/configuration.ps1','scripts/command-host.cs','scripts/installation-state.ps1','scripts/script-invocation.ps1','scripts/agent-commands.ps1','scripts/agent-strategies.ps1','scripts/whas.ps1','config/defaults.json','agents/strategies/opencode/manifest.json','agents/strategies/opencode/adapter.ps1')) {
        $destination=Join-Path $root $relative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $destination))|Out-Null
        Copy-Item -LiteralPath (Join-Path $repo $relative) -Destination $destination
    }
    [IO.File]::WriteAllText((Join-Path $root 'opencode.json'),'{}')
    $fake=Join-Path $fixture 'opencode.exe'
    Add-Type -TypeDefinition @'
using System; using System.IO; using System.Collections.Generic; using System.Web.Script.Serialization;
public class FakeOpenCode {
 public static int Main(string[] args) {
  Console.OutputEncoding=new System.Text.UTF8Encoding(false);
  File.WriteAllLines(Environment.GetEnvironmentVariable("WHAS_TEST_ARGUMENTS"),args);
  File.WriteAllText(Environment.GetEnvironmentVariable("WHAS_TEST_ARGUMENTS")+".argv.json",new JavaScriptSerializer().Serialize(args));
  File.WriteAllText(Environment.GetEnvironmentVariable("WHAS_TEST_ARGUMENTS")+".inline.json",Environment.GetEnvironmentVariable("OPENCODE_CONFIG_CONTENT")??"{}");
  int modelIndex=Array.IndexOf(args,"--model");
  if(modelIndex>=0 && args[modelIndex+1].StartsWith("ollama/")) {
   var inline=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(Environment.GetEnvironmentVariable("OPENCODE_CONFIG_CONTENT")??"{}");
   object providers,ollama,models;string id=args[modelIndex+1].Substring(7);
   if(!inline.TryGetValue("provider",out providers) || !((Dictionary<string,object>)providers).TryGetValue("ollama",out ollama) || !((Dictionary<string,object>)ollama).TryGetValue("models",out models) || !((Dictionary<string,object>)models).ContainsKey(id)) {Console.WriteLine("{\"type\":\"error\",\"error\":{\"message\":\"Local model is not registered in OpenCode\"}}");return 1;}
  }
  if(Array.IndexOf(args,"model event failure")>=0) {Console.WriteLine("{\"type\":\"error\",\"error\":{\"name\":\"ProviderModelNotFoundError\",\"data\":{\"providerID\":\"ollama\",\"modelID\":\"qwen2.5:1.5b\"}}}");return 0;}
  if(Array.IndexOf(args,"provider event failure")>=0) {Console.WriteLine("{\"type\":\"error\",\"error\":{\"data\":{\"message\":\"Local Ollama connection refused\"}}}");return 0;}
  if(Array.IndexOf(args,"unicode fixture")>=0) {Console.WriteLine("{\"type\":\"text\",\"sessionID\":\"ses_unicode\",\"part\":{\"text\":\"Yes\u2014what about caf\u00e9 and \u65e5\u672c\u8a9e?\"}}");return 0;}
  if(args.Length>0 && args[0]=="models") {Console.WriteLine("provider/model-a\nollama/local-a\nnot a model\nprovider/model-a");return 0;}
  if(args.Length>0 && args[0]=="list") {Console.WriteLine("NAME ID SIZE MODIFIED\nlocal-a:latest 123 1GB now\nlocal-b:latest 456 2GB now");return 0;}
  Console.WriteLine("{\"type\":\"text\",\"sessionID\":\"ses_fixture\",\"part\":{\"text\":\"ANSWER\"}}"); return 0;
 }
}
'@ -OutputAssembly $fake -OutputType ConsoleApplication -ReferencedAssemblies System.dll,System.Web.Extensions.dll
    Copy-Item -LiteralPath $fake -Destination (Join-Path $fixture 'ollama.exe')
    $env:Path=$fixture+';'+$savedPath
    $env:WHAS_TEST_ARGUMENTS=Join-Path $fixture 'arguments.txt'
    Install-StackCommandRegistration -InstallPath $root -RegistrationDirectory (Join-Path $fixture 'registration') -PersistPath $false
    Complete-StackInstallationTracking $session $true
    $help=Invoke-WhasTest @('--help')
    if($help -notmatch '--no-voice' -or $help -notmatch '--message'){throw 'Unified help omitted request options'}
    foreach($options in @(@('tts','--help'),@('tts','-h'),@('tts','help'),@('tts'))) {
        $help=Invoke-WhasTest $options
        if($help -notmatch 'voice-add --path FILE --name NAME' -or $help -notmatch '--default-engine'){throw 'Speech help omitted commands or flags'}
    }
    $help=& (Join-Path $fixture 'registration/bin/tts-help.exe')
    if($LASTEXITCODE -ne 0 -or ($help -join "`n") -notmatch 'Usage: whas tts'){throw 'Standalone tts-help failed'}
    if(Test-Path -LiteralPath $env:WHAS_TEST_ARGUMENTS){throw 'Help unexpectedly invoked a provider'}
    $catalog=Invoke-WhasTest @('model','catalog','--cloud')|ConvertFrom-Json
    if(@($catalog).Count -ne 1 -or $catalog -cnotcontains 'provider/model-a'){throw 'Cloud catalogue is not a clean provider/model list'}
    $catalog=Invoke-WhasTest @('model','catalog','--local')|ConvertFrom-Json
    if(($catalog -join ',') -cne 'local-a:latest,local-b:latest'){throw ('Local catalogue did not extract installed model IDs: '+($catalog|ConvertTo-Json -Compress))}
    $one=Invoke-WhasTest @('askl','literal & unchanged')
    $first=[IO.File]::ReadAllText($env:WHAS_TEST_ARGUMENTS)
    $two=Invoke-WhasTest @('ask','--local','literal & unchanged')
    if ($first -cne [IO.File]::ReadAllText($env:WHAS_TEST_ARGUMENTS) -or $one.Trim() -cne 'ANSWER' -or $two.Trim() -cne 'ANSWER') { throw 'Shortcut changed behaviour or output' }
    $null=Invoke-WhasTest @('performc','task')
    if ([IO.File]::ReadAllText($env:WHAS_TEST_ARGUMENTS) -notmatch 'ps-write') { throw 'Task permission routing failed' }
    $inline=Get-Content -LiteralPath ($env:WHAS_TEST_ARGUMENTS+'.inline.json') -Raw|ConvertFrom-Json
    if($inline.agent.'whas-chat'){throw 'Task execution inherited the plain conversation profile'}
    $literal='write "blah.txt" in "D:\Work\Web Projects\voice test\voices" containing "weeb"'+"`r`n"+'Keep the path unchanged.'
    $null=Invoke-WhasTest @('performc',$literal)
    if((Get-Content -LiteralPath ($env:WHAS_TEST_ARGUMENTS+'.argv.json') -Raw|ConvertFrom-Json)[-1] -cne $literal){throw 'Native task handoff split a quoted workspace path'}
    $null=Invoke-WhasTest @('configure','--set','location','local')
    $settings=Invoke-WhasTest @('configure','--show')|ConvertFrom-Json
    if ($settings.interaction.location -ne 'local') { throw 'Shared configuration failed' }
    $null=Invoke-WhasTest @('configure','--set','speech.enabled','false')
    $settings=Invoke-WhasTest @('configure','--show')|ConvertFrom-Json
    if($settings.interaction.location -ne 'local' -or $settings.interaction.speech -ne $false) { throw 'Replacing existing configuration lost settings' }
    $null=Invoke-WhasTest @('configure','--set','speech.idleTimeoutMinutes','15')
    $settings=Invoke-WhasTest @('configure','--show')|ConvertFrom-Json
    if($settings.tts.idleTimeoutMinutes -ne 15 -or $settings.tts.idleTimeoutMinutes -isnot [int] -or $settings.interaction.location -ne 'local'){throw 'CLI timeout did not preserve a numeric value and other defaults'}
    $null=Invoke-WhasTest @('ask','saved default')
    if ([IO.File]::ReadAllText($env:WHAS_TEST_ARGUMENTS) -notmatch 'ollama/qwen3:8b') { throw 'Saved default routing failed' }
    $inline=Get-Content -LiteralPath ($env:WHAS_TEST_ARGUMENTS+'.inline.json') -Raw|ConvertFrom-Json
    if([IO.File]::ReadAllText($env:WHAS_TEST_ARGUMENTS) -notmatch 'whas-chat' -or $inline.agent.'whas-chat'.permission.'*' -cne 'deny'){throw 'One-off question still uses the file-reading agent'}
    $response=Invoke-WhasTest @('chatl','--message',$literal)|ConvertFrom-Json
    if($response.sessionId -cne 'ses_fixture' -or $response.answer -cne 'ANSWER') { throw 'Graphical chat response contract failed' }
    if((Get-Content -LiteralPath ($env:WHAS_TEST_ARGUMENTS+'.argv.json') -Raw|ConvertFrom-Json)[-1] -cne $literal){throw 'Native chat handoff split a quoted workspace path'}
    $providerBefore=[IO.File]::ReadAllText((Join-Path $root 'opencode.json'))
    $null=Invoke-WhasTest @('configure','--set','local.model','qwen2.5:1.5b')
    foreach($options in @(@('askl','switched question'),@('performl','switched task'),@('chatl','--message','switched chat'),@('askl','--model','ollama/overridden:latest','override question'))) {$null=Invoke-WhasTest $options}
    if([IO.File]::ReadAllText((Join-Path $root 'opencode.json')) -cne $providerBefore){throw 'Requests rewrote saved OpenCode provider configuration'}
    $ErrorActionPreference='Continue'
    $modelFailure=Invoke-WhasTest @('chatl','--message','model event failure') 1
    $providerFailure=Invoke-WhasTest @('chatl','--message','provider event failure') 1
    $ErrorActionPreference='Stop'
    if(($modelFailure -replace '\s+',' ') -notmatch 'ProviderModelNotFoundError: ollama/qwen2\.5:1\.5b' -or ($providerFailure -replace '\s+',' ') -notmatch 'Local Ollama connection refused'){throw ("Conversation failure hid the runtime model/provider reason. Model result: $modelFailure Provider result: $providerFailure")}
    $null=Invoke-WhasTest @('configure','--set','local.model','qwen3:8b')
    $previousEncoding=[Console]::OutputEncoding
    try {
        [Console]::OutputEncoding=[Text.Encoding]::GetEncoding(850)
        $start=New-Object Diagnostics.ProcessStartInfo
        $start.FileName=Join-Path $fixture 'registration/bin/whas.exe';$start.Arguments='chatl --message "unicode fixture"'
        $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
        $start.StandardOutputEncoding=[Text.Encoding]::UTF8;$start.StandardErrorEncoding=[Text.Encoding]::UTF8;$start.EnvironmentVariables['WHAS_PROGRESS_EVENTS']='1'
        $process=[Diagnostics.Process]::Start($start)
        try {
            $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
            if(-not $process.WaitForExit(30000)){$process.Kill();throw 'Unicode conversation timed out'}
            $unicode=$stdout.Result|ConvertFrom-Json
            $expected='Yes'+[char]0x2014+'what about caf'+[char]0xE9+' and '+[char]0x65E5+[char]0x672C+[char]0x8A9E+'?'
            if($process.ExitCode -or $unicode.answer -cne $expected){throw ('Conversation Unicode was corrupted: '+$stdout.Result+' '+$stderr.Result)}
        } finally {$process.Dispose()}
    } finally {[Console]::OutputEncoding=$previousEncoding}
    $null=Invoke-WhasTest @('chatl','--session',$response.sessionId,'--message','second turn')
    if([IO.File]::ReadAllLines($env:WHAS_TEST_ARGUMENTS) -notcontains 'ses_fixture') { throw 'Contextual GUI turn lost the explicit session' }
    $null=Invoke-WhasTest @('chatl','--session',$response.sessionId)
    $received=[IO.File]::ReadAllLines($env:WHAS_TEST_ARGUMENTS)
    if ($received -notcontains '--session' -or $received -notcontains 'ses_fixture' -or $received -contains 'run') { throw 'Explicit contextual continuation failed' }
    # Native errors use stderr; keep them as data for expected failures.
    $ErrorActionPreference='Continue'
    $bad=Invoke-WhasTest @('askl','--cloud','question') 1
    $badSetting=Invoke-WhasTest @('configure','--set','location','invalid') 1
    $badSession=Invoke-WhasTest @('ask','--session','session_test','question') 1
    $wrongRoute=Invoke-WhasTest @('chatc','--session',$response.sessionId,'--message','private') 1
    $unknown=Invoke-WhasTest @('chatl','--session','unknown','--message','private') 1
    Push-Location $fixture
    try { $wrongWorkspace=Invoke-WhasTest @('chatl','--session',$response.sessionId,'--message','private') 1 } finally { Pop-Location }
    $ErrorActionPreference='Stop'
    if ($bad -notmatch 'Conflicting' -or $badSetting -notmatch 'must be local or cloud' -or $badSession -notmatch 'Session continuation') { throw 'Invalid options were not rejected clearly' }
    if($wrongRoute -notmatch 'does not match' -or $wrongWorkspace -notmatch 'does not match' -or $unknown -notmatch 'not registered') { throw 'Session isolation failed' }
    if ((Invoke-WhasTest @('configure','--show')|ConvertFrom-Json).interaction.location -ne 'local') { throw 'Invalid settings changed saved configuration' }
    $null=Invoke-WhasTest @('configure','--set','local.enabled','false')
    $ErrorActionPreference='Continue'
    $removed=Invoke-WhasTest @('askl','question') 1
    $ErrorActionPreference='Stop'
    if($removed -notmatch 'feature has been removed'){throw 'Removed feature still accepts requests'}
    $null=Invoke-WhasTest @('configure','--set','local.enabled','true')
    $null=Invoke-WhasTest @('askl','restored question')
    # Readiness probes can catch errors while the command succeeds. No audio,
    # network or machine configuration is involved in this native-host fixture.
    New-Item -ItemType Directory (Join-Path $root 'tts') -Force|Out-Null
    @'
param([string]$InstallPath)
function tts-say {
 param([string]$Text)
 try {Get-Item -LiteralPath (Join-Path $InstallPath 'probe-does-not-exist') -ErrorAction Stop|Out-Null} catch {}
 if($Text -ne 'handled') { & $env:ComSpec /c exit 7 }
 if($Text -eq 'fail') {Write-Error 'Genuine speech failure';return}
 Write-Output 'Speech completed'
}
'@|Set-Content (Join-Path $root 'tts/tts.ps1')
    $spoken=& (Join-Path $fixture 'registration/bin/tts-say.exe') 'success' 2>&1|Out-String
    if($LASTEXITCODE -ne 0 -or $spoken -notmatch 'Speech completed'){throw "Handled probe became false speech failure: $spoken"}
    $handled=& (Join-Path $fixture 'registration/bin/tts-say.exe') 'handled' 2>&1|Out-String
    if($LASTEXITCODE -ne 0 -or $handled -notmatch 'Speech completed'){throw "Caught error became a command failure: $handled"}
    $ErrorActionPreference='Continue'
    $failed=& (Join-Path $fixture 'registration/bin/tts-say.exe') 'fail' 2>&1|Out-String
    $failedExit=$LASTEXITCODE;$ErrorActionPreference='Stop'
    if($failedExit -ne 1 -or $failed -notmatch 'Genuine speech failure'){throw 'Genuine speech errors are hidden'}
    Write-Host 'PASS: Native shortcuts, shared defaults, route removal, sessions, handled speech probes and genuine error exits'
} finally {
    $env:Path=$savedPath; $env:WHAS_TEST_ARGUMENTS=$savedArgs; $env:USERPROFILE=$savedUser
    $absolute=[IO.Path]::GetFullPath($fixture)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $absolute.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $absolute) -notmatch '^whas-cli-[a-f0-9]{32}$') { throw 'Unexpected cleanup target' }
    if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
