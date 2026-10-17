#Requires -Version 5.1
$ErrorActionPreference='Stop'
if($env:WHAS_SANDBOX_TEST -ne '1'){throw 'Run this isolated registration test in Windows Sandbox only.'}
$repo=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('whas-workflows-'+[guid]::NewGuid().ToString('N'))
$registration=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.windows-hybrid-agentic-stack/bin'
$marker=Join-Path $registration 'install-root.txt';$binary=Join-Path $registration 'whas.exe'
$parentExisted=Test-Path (Split-Path -Parent $registration)
if(Test-Path $registration){throw 'Workflow fixture requires an unused guest command registration.'}
function Children($node){for($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($node);$i++){$child=[Windows.Media.VisualTreeHelper]::GetChild($node,$i);$child;Children $child}}
function Shown($node){while($node){if($node -is [Windows.UIElement] -and $node.Visibility -ne 'Visible'){return $false};$node=[Windows.Media.VisualTreeHelper]::GetParent($node)};return $true}
function Pump {
 $frame=New-Object Windows.Threading.DispatcherFrame
 $null=[Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background,[Action]{$frame.Continue=$false})
 [Windows.Threading.Dispatcher]::PushFrame($frame)
}
function Await($condition){$deadline=[DateTime]::UtcNow.AddSeconds(30);do{Pump;Start-Sleep -Milliseconds 30;if(&$condition){return}}while([DateTime]::UtcNow -lt $deadline);throw 'Workflow operation did not complete'}
$savedCalls=$env:WHAS_GUI_CALLS
$savedContext=$env:WHAS_GUI_CONTEXT;$savedInline=$env:OPENCODE_CONFIG_CONTENT
$savedVoiceMode=$env:WHAS_GUI_VOICE_MODE
$savedPath=$env:Path;$savedFailure=$env:WHAS_GUI_DISCOVERY_FAIL;$savedConfig=$env:OPENCODE_CONFIG;$savedExpectedConfig=$env:WHAS_GUI_EXPECTED_CONFIG
try {
 [IO.Directory]::CreateDirectory($fixture)|Out-Null
 [IO.Directory]::CreateDirectory($registration)|Out-Null
 [IO.Directory]::CreateDirectory((Join-Path $fixture 'config'))|Out-Null
 Copy-Item (Join-Path $repo 'config/defaults.json') (Join-Path $fixture 'config/defaults.json')
 [IO.File]::WriteAllText($marker,$fixture)
 [IO.File]::WriteAllText((Join-Path $fixture 'opencode.json'),'{"agent":{"ps-read":{}},"provider":{"ollama":{}}}')
 [IO.File]::WriteAllText((Join-Path $fixture '.whas-installation.json'),'{"Status":"Installed","TtsStrategies":[{"Id":"piper-tts","Status":"Installed"},{"Id":"chatterbox-turbo","Status":"Installed","Context":{"VoicesPath":"voices/chatterbox-turbo"}}]}')
 New-Item -ItemType Directory -Path (Join-Path $fixture 'voices/chatterbox-turbo')|Out-Null
 foreach($file in @('c3po_prompt.pt','c3po_prompt.wav')){[IO.File]::WriteAllText((Join-Path $fixture ('voices/chatterbox-turbo/'+$file)),'fixture')}
 $env:WHAS_GUI_VOICE_MODE=$null
 $env:WHAS_GUI_CALLS=Join-Path $fixture 'calls.log'
 $env:WHAS_GUI_CONTEXT=Join-Path $fixture 'request-context.json'
 $env:OPENCODE_CONFIG_CONTENT='{"model":"provider/inherited","provider":{"ollama":{"options":{"baseURL":"http://127.0.0.1:11434/v1"},"models":{"local-a:latest":{"name":"Custom local model","limit":{"context":8192}}}}},"agent":{"ps-read":{"permission":{"edit":"deny"}}}}'
 $env:WHAS_GUI_EXPECTED_CONFIG=Join-Path $fixture 'opencode.json'
 $env:OPENCODE_CONFIG='parent-config-must-not-change'
 $env:WHAS_GUI_DISCOVERY_FAIL=$null
 $env:Path=$registration+';'+$env:Path
 Add-Type -TypeDefinition @'
using System;using System.IO;using System.Web.Script.Serialization;
public static class WorkflowCli {
 public static int Main(string[] args) {
  var json=new JavaScriptSerializer();File.AppendAllText(Environment.GetEnvironmentVariable("WHAS_GUI_CALLS"),json.Serialize(args)+Environment.NewLine);
  string verb=String.Join(" ",args);
  if(args.Length==4 && args[0]=="configure" && args[1]=="--set") {if(args[3]=="provider/rejected"){Console.Error.WriteLine("Fixture settings rejection");return 1;}Console.WriteLine("Setting saved");return 0;}
  if(args.Length>0 && args[0]=="--check") {Console.Error.WriteLine("WHAS_EVENT {\"type\":\"check\",\"component\":\"Windows\",\"status\":\"PASS\",\"details\":\"Fixture ready\",\"required\":true}");return 0;}
  if(args.Length>1 && args[0]=="--maintain") {
   if(args[1]=="speech-timeout" && Array.IndexOf(args,"120")>=0){Console.Error.WriteLine("Fixture timeout rejection");return 1;}
   if(args[1]=="speak") {System.Threading.Thread.Sleep(500);Console.WriteLine("TTS_DIAGNOSTIC");if(Array.IndexOf(args,"fail speech")>=0)return 1;}
   if(args[1]=="voice-add") {
    string name=args[Array.IndexOf(args,"--voice-name")+1];if(name=="fail-save"){Console.Error.WriteLine("Could not save voice: fixture rejection");return 1;}
    string folder=Path.Combine(Path.GetDirectoryName(Environment.GetEnvironmentVariable("WHAS_GUI_EXPECTED_CONFIG")),"voices","chatterbox-turbo");
    File.WriteAllText(Path.Combine(folder,name+"_prompt.pt"),"fixture");File.WriteAllText(Path.Combine(folder,name+"_prompt.wav"),"fixture");Console.WriteLine("Voice saved");
   }
   return 0;
  }
  string app=Path.GetFileNameWithoutExtension(Environment.GetCommandLineArgs()[0]);
  if(app=="ollama") {Console.WriteLine("NAME ID SIZE MODIFIED\nlocal-a:latest 123 1GB now\nlocal-b:latest 456 2GB now");return 0;}
  if(app=="opencode") {
   System.Threading.Thread.Sleep(Environment.GetEnvironmentVariable("WHAS_GUI_DISCOVERY_FAIL")=="wait"?5000:500);
   if(Environment.GetEnvironmentVariable("OPENCODE_CONFIG")!=Environment.GetEnvironmentVariable("WHAS_GUI_EXPECTED_CONFIG")) return 2;
   if(Environment.GetEnvironmentVariable("WHAS_GUI_DISCOVERY_FAIL")=="1") {Console.Error.WriteLine("Discovery fixture unavailable");return 1;}
   Console.WriteLine("provider/model-a\nollama/local-a\nnot a model");return 0;
  }
  if(verb=="configure --show") Console.WriteLine("{\"interaction\":{\"location\":\"local\",\"runtime\":\"opencode\",\"speech\":false},\"agents\":{\"cloud\":{\"model\":null},\"local\":{\"model\":\"local-a:latest\"}},\"tts\":{\"engine\":\"piper-tts\",\"defaultVoice\":\"default\",\"voiceDefaults\":{},\"device\":\"cpu\",\"autoStart\":true}}");
  else if(verb=="agent list") {Console.WriteLine("{\"Available\":true,\"Id\":\"opencode\"}");Console.WriteLine("{\"Available\":false,\"Id\":\"unavailable-runtime\"}");}
  else if(verb=="tts inventory") {
   string mode=Environment.GetEnvironmentVariable("WHAS_GUI_VOICE_MODE");
   if(mode=="legacy") Console.WriteLine("[{\"id\":\"chatterbox-turbo\",\"installed\":true,\"voiceCloning\":true,\"transcriptRequired\":false,\"voices\":[\"default\",\"c3po_prompt\"]}]");
   else if(mode=="current") Console.WriteLine("[{\"id\":\"chatterbox-turbo\",\"installed\":true,\"voiceCloning\":true,\"transcriptRequired\":false,\"referenceInventoryVersion\":1,\"voices\":[\"default\",\"c3po\",\"new-voice\"]}]");
   else if(mode=="f5") Console.WriteLine("[{\"id\":\"f5-tts\",\"installed\":true,\"voiceCloning\":true,\"transcriptRequired\":true,\"referenceInventoryVersion\":1,\"voices\":[\"default\"]}]");
   else Console.WriteLine("[{\"id\":\"piper-tts\",\"installed\":true,\"voiceCloning\":false,\"transcriptRequired\":false,\"voices\":[\"default\"]},{\"id\":\"f5-tts\",\"installed\":false,\"voiceCloning\":true,\"transcriptRequired\":true,\"voices\":[\"default\"]}]");
  }
  else if(args.Length>1 && args[0]=="tts" && (args[1]=="voice-add" || args[1]=="voice-remove")) {Console.Error.WriteLine("Legacy voice writes must not be used");return 1;}
  else if(args.Length>0 && args[0]=="model") {Console.Error.WriteLine("Stack command error: Unknown command: model");return 1;}
  else if(args.Length>0 && args[0]=="chat") {File.WriteAllText(Environment.GetEnvironmentVariable("WHAS_GUI_CONTEXT"),Environment.GetEnvironmentVariable("OPENCODE_CONFIG_CONTENT"));if(verb.EndsWith("invalid chat response")){Console.WriteLine("invalid JSON");return 0;}Console.WriteLine("{\"sessionId\":\"ses_test\",\"answer\":\""+(verb.EndsWith("fail speech")?"fail speech":"ANSWER")+"\"}");}
  else if(args.Length>1 && args[0]=="tts" && args[1]=="say") {Console.WriteLine("TTS_DIAGNOSTIC");if(Array.IndexOf(args,"fail speech")>=0)return 1;}
  else {if(verb.EndsWith("wait for cancellation")) System.Threading.Thread.Sleep(30000);if(verb.EndsWith("delayed reply")) System.Threading.Thread.Sleep(5000);if(verb.EndsWith("request failure")){Console.Error.WriteLine("Fixture request failed");return 1;}Console.WriteLine("ANSWER");}
  return 0;
 }
}
'@ -OutputAssembly $binary -OutputType ConsoleApplication -ReferencedAssemblies System.dll,System.Web.Extensions.dll
 Copy-Item -LiteralPath $binary -Destination (Join-Path $registration 'opencode.exe')
 Copy-Item -LiteralPath $binary -Destination (Join-Path $registration 'ollama.exe')
 Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml,System.Drawing,System.Windows.Forms
 $refs=@('System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Web.Extensions.dll',[Windows.Window].Assembly.Location,[Windows.Media.Visual].Assembly.Location,[Windows.Threading.Dispatcher].Assembly.Location,[System.Xaml.XamlReader].Assembly.Location)
 Add-Type -Path (Join-Path $repo 'scripts/gui-host.cs'),(Join-Path $repo 'scripts/fluent-gui.cs') -ReferencedAssemblies $refs
 $catalog=@(Get-ChildItem (Join-Path $repo 'tts/strategies') -Directory|ForEach-Object{Get-Content (Join-Path $_.FullName 'manifest.json') -Raw|ConvertFrom-Json})|ConvertTo-Json -Depth 12
 $preferencesFile=Join-Path $fixture 'gui-preferences.json'
 $window=New-Object WindowsHybridAgenticStack.FluentWindow($false,$binary,$catalog,$fixture,[IO.File]::ReadAllText((Join-Path $repo 'scripts/gui-theme.xaml')),$preferencesFile)
 $flags=[Reflection.BindingFlags]'Instance,NonPublic'
 try {
  $null=(New-Object Windows.Interop.WindowInteropHelper($window)).EnsureHandle()
  $controller=$window.GetType().GetField('controller',$flags).GetValue($window)
  $controller.GetType().GetMethod('LoadPresentationSettings',$flags).Invoke($controller,@())|Out-Null
  $settings=$controller.GetType().GetField('settings',$flags).GetValue($controller)
  Await {(-not $window.Busy) -and $settings['cloud.model'].Items.Contains('provider/model-a')}
  $tabs=$controller.GetType().GetProperty('PresentationPages',$flags).GetValue($controller)
  $featureIndex=0;while($tabs.TabPages[$featureIndex].Text -ne 'Features'){$featureIndex++}
  $controller.GetType().GetMethod('CloseMaintenance',$flags).Invoke($controller,@())|Out-Null
  $window.SelectPage($featureIndex);$window.Render((Join-Path $fixture 'removal-before-preview.png'))
  $preview=Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Preview removal'}|Select-Object -First 1
  $preview.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)));Await {-not $window.Busy};Pump
  $window.Render((Join-Path $fixture 'removal-after-preview.png'));Pump
  $uninstall=Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Uninstall…'}|Select-Object -First 1
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'removal-after-preview.png'))}
  if(-not $uninstall -or -not $uninstall.IsEnabled){throw 'Uninstall action missing after preview'}
  $point=$uninstall.TransformToAncestor($window.Content).Transform((New-Object Windows.Point(0,0)))
  Write-Host ('Removal button geometry: '+$point.Y+' / '+$window.Content.RenderSize.Height)
  if($point.Y -lt 0 -or $point.Y+$uninstall.ActualHeight -gt $window.Content.RenderSize.Height){throw 'Uninstall action scrolled out after preview'}
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'removal-after-preview.png'))}
  try {$controller.GetType().GetMethod('CompleteRemoval',$flags).Invoke($controller,@($fixture.PSObject.BaseObject))|Out-Null} catch {throw ($_|Out-String)+$_.Exception.InnerException.ToString()}
  $window.Render((Join-Path $fixture 'after-removal.png'));Pump
  if(-not $controller.GetType().GetProperty('IsSetup',$flags).GetValue($controller)){throw 'Successful removal did not return to setup'}
  if($controller.GetType().GetField('destination',$flags).GetValue($controller).Text -cne $fixture){throw 'Successful removal lost the installation path'}
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'after-removal.png'))}
  Write-Host 'PASS: removal controls remain visible after preview and successful removal returns to setup'
 }finally{$window.Dispose()}
}finally {
 $env:WHAS_GUI_CALLS=$savedCalls
 $env:WHAS_GUI_CONTEXT=$savedContext;$env:OPENCODE_CONFIG_CONTENT=$savedInline
 $env:WHAS_GUI_VOICE_MODE=$savedVoiceMode
 $env:Path=$savedPath;$env:WHAS_GUI_DISCOVERY_FAIL=$savedFailure;$env:OPENCODE_CONFIG=$savedConfig;$env:WHAS_GUI_EXPECTED_CONFIG=$savedExpectedConfig
 $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not [IO.Path]::GetFullPath($fixture).StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $fixture) -notmatch '^whas-workflows-[a-f0-9]{32}$'){throw 'Unexpected workflow cleanup path'}
 if((Test-Path $marker) -and [IO.File]::ReadAllText($marker) -ceq $fixture){foreach($file in @($binary,$marker,(Join-Path $registration 'opencode.exe'),(Join-Path $registration 'ollama.exe'))){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file -Force}};Remove-Item -LiteralPath $registration;if(-not $parentExisted -and @(Get-ChildItem -LiteralPath (Split-Path -Parent $registration) -Force).Count -eq 0){Remove-Item -LiteralPath (Split-Path -Parent $registration)}}
 if(Test-Path $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
