#Requires -Version 5.1
$ErrorActionPreference='Stop'
if($env:WHAS_SANDBOX_TEST -ne '1'){throw 'Run local HTTP chat fixtures in Windows Sandbox only.'}
$repo=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('whas-ollama-chat-'+[guid]::NewGuid().ToString('N'))
$registration=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.windows-hybrid-agentic-stack/bin'
if(Test-Path -LiteralPath $registration){throw 'Guest registration must be unused.'}
$savedCalls=$env:WHAS_CHAT_CALLS
$server=$null;$window=$null
function Children($node){for($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($node);$i++){$child=[Windows.Media.VisualTreeHelper]::GetChild($node,$i);$child;Children $child}}
function Pump {$frame=New-Object Windows.Threading.DispatcherFrame;$null=[Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background,[Action]{$frame.Continue=$false});[Windows.Threading.Dispatcher]::PushFrame($frame)}
function Await($condition){$deadline=[DateTime]::UtcNow.AddSeconds(15);do{Pump;Start-Sleep -Milliseconds 20;if(&$condition){return}}while([DateTime]::UtcNow -lt $deadline);throw 'Local chat fixture timed out'}
function Reply { $list=$controller.GetType().GetField('ConversationReplies',$flags).GetValue($controller);$last=$list[$list.Count-1];$last.GetType().GetField('Value',$flags).GetValue($last) }
function Send([string]$mode,[string]$text){$action.SelectedItem=$mode;$prompt.Text=$text;$window.Render((Join-Path $fixture 'before.png'));$button=@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Send'})[0];$button.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))}
function Request { $server.Requests.ToArray()[-1]|ConvertFrom-Json }
try {
 New-Item -ItemType Directory -Path (Join-Path $fixture 'config'),$registration|Out-Null
 Copy-Item (Join-Path $repo 'config/defaults.json') (Join-Path $fixture 'config/defaults.json')
 [IO.File]::WriteAllText((Join-Path $registration 'install-root.txt'),$fixture)
 $env:WHAS_CHAT_CALLS=Join-Path $fixture 'calls.jsonl'
 Add-Type -TypeDefinition @'
using System;using System.IO;using System.Text;using System.Web.Script.Serialization;
public static class ChatFakeCli {
 public static int Main(string[] args){File.AppendAllText(Environment.GetEnvironmentVariable("WHAS_CHAT_CALLS"),new JavaScriptSerializer().Serialize(args)+Environment.NewLine);if(args.Length>1 && args[0]=="--maintain" && args[1]=="speak"){System.Threading.Thread.Sleep(1000);Console.WriteLine("FAKE_SPEECH_DIAGNOSTIC");return 0;}if(args.Length>0 && args[0]=="perform"){Console.WriteLine("FAKE_TASK");return 0;}Console.Error.WriteLine("Unexpected OpenCode/chat CLI invocation");return 3;}
}
'@ -OutputAssembly (Join-Path $fixture 'tool.exe') -OutputType ConsoleApplication -ReferencedAssemblies System.dll,System.Web.Extensions.dll
 Copy-Item (Join-Path $fixture 'tool.exe') (Join-Path $registration 'whas.exe')
 Add-Type -TypeDefinition @'
using System;using System.IO;using System.Net;using System.Net.Sockets;using System.Text;using System.Threading;using System.Linq;using System.Collections;using System.Collections.Generic;using System.Collections.Concurrent;using System.Web.Script.Serialization;
public sealed class ChatServer:IDisposable {
 private readonly HttpListener listener=new HttpListener();private readonly ManualResetEvent stop=new ManualResetEvent(false);private int disposed;
 public readonly ConcurrentQueue<string> Requests=new ConcurrentQueue<string>();public readonly string Endpoint;
 public ChatServer(){var reservation=new TcpListener(IPAddress.Loopback,0);reservation.Start();int port=((IPEndPoint)reservation.LocalEndpoint).Port;reservation.Stop();Endpoint="http://127.0.0.1:"+port+"/api/chat";listener.Prefixes.Add("http://127.0.0.1:"+port+"/");listener.Start();var thread=new Thread(delegate(){while(!stop.WaitOne(0)){try{var context=listener.GetContext();ThreadPool.QueueUserWorkItem(delegate{Handle(context);});}catch{break;}}});thread.IsBackground=true;thread.Start();}
 private void Handle(HttpListenerContext context){try{var json=new JavaScriptSerializer();string raw;using(var reader=new StreamReader(context.Request.InputStream,Encoding.UTF8)) raw=reader.ReadToEnd();Requests.Enqueue(raw);var payload=json.Deserialize<Dictionary<string,object>>(raw);var messages=((IEnumerable)payload["messages"]).Cast<Dictionary<string,object>>().ToArray();string prompt=Convert.ToString(messages.Last()["content"]);context.Response.ContentType="application/x-ndjson";context.Response.SendChunked=true;
  if(prompt=="error"){context.Response.StatusCode=404;using(var writer=new StreamWriter(context.Response.OutputStream,new UTF8Encoding(false))){writer.Write("{\"error\":\"fixture model not found\"}");}return;}
  using(var writer=new StreamWriter(context.Response.OutputStream,new UTF8Encoding(false))){
   if(prompt=="cancel"){writer.WriteLine("{\"message\":{\"content\":\"\"},\"done\":false}");writer.Flush();stop.WaitOne(10000);return;}
   if(prompt=="stream" || prompt=="truncated"){writer.WriteLine("{\"message\":{\"content\":\"First \"},\"done\":false}");writer.Flush();if(prompt=="truncated")return;stop.WaitOne(1000);writer.WriteLine("{\"message\":{\"content\":\"reply\"},\"done\":false}");}
   else{string answer=prompt=="remember 42"?"Remembered.":prompt=="number?"?(messages.Any(x=>Convert.ToString(x["content"])=="remember 42")?"42":"no context"):prompt=="unicode"?"caf\u00e9 \u2014 \u65e5\u672c\u8a9e":"OK";writer.WriteLine(json.Serialize(new {message=new {role="assistant",content=answer},done=false}));}
   writer.WriteLine("{\"done\":true}");writer.Flush();}
 }catch{}finally{try{context.Response.Close();}catch{}}}
 public void Dispose(){if(Interlocked.Exchange(ref disposed,1)!=0)return;stop.Set();listener.Stop();listener.Close();}
}
'@ -ReferencedAssemblies System.dll,System.Core.dll,System.Web.Extensions.dll
 $server=New-Object ChatServer
 Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml,System.Drawing,System.Windows.Forms
 $refs=@('System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Web.Extensions.dll',[Windows.Window].Assembly.Location,[Windows.Media.Visual].Assembly.Location,[Windows.Threading.Dispatcher].Assembly.Location,[System.Xaml.XamlReader].Assembly.Location)
 Add-Type -Path (Join-Path $repo 'scripts/gui-host.cs'),(Join-Path $repo 'scripts/fluent-gui.cs') -ReferencedAssemblies $refs
 $catalog=@(Get-ChildItem (Join-Path $repo 'tts/strategies') -Directory|ForEach-Object{Get-Content (Join-Path $_.FullName 'manifest.json') -Raw|ConvertFrom-Json})|ConvertTo-Json -Depth 12
 $window=New-Object WindowsHybridAgenticStack.FluentWindow($false,(Join-Path $fixture 'tool.exe'),$catalog,$fixture,[IO.File]::ReadAllText((Join-Path $repo 'scripts/gui-theme.xaml')),(Join-Path $fixture 'preferences.json'))
 $flags=[Reflection.BindingFlags]'Instance,NonPublic';$controller=$window.GetType().GetField('controller',$flags).GetValue($window)
 $controller.GetType().GetField('localChatEndpoint',$flags).SetValue($controller,[Uri]$server.Endpoint)
 $controller.GetType().GetField('savedRuntime',$flags).SetValue($controller,'opencode')
 $settings=$controller.GetType().GetField('settings',$flags).GetValue($controller);$settings['local.model'].Items.AddRange([object[]]@('model-a','model-b'));$settings['local.model'].SelectedItem='model-a'
 $controller.GetType().GetField('route',$flags).GetValue($controller).SelectedItem='local'
 $action=$controller.GetType().GetField('action',$flags).GetValue($controller);$prompt=$controller.GetType().GetField('prompt',$flags).GetValue($controller);$speak=$controller.GetType().GetField('speak',$flags).GetValue($controller);$speak.Checked=$false
 $null=(New-Object Windows.Interop.WindowInteropHelper($window)).EnsureHandle();$window.SelectPage(0);$window.Render((Join-Path $fixture 'initial.png'))
 Send chat 'remember 42';Await {-not $window.Busy};if((Reply) -cne 'Remembered.' -or (Request).messages.Count -ne 1){throw ('First chat request was not a plain message. Reply: '+(Reply)+'; requests: '+($server.Requests.ToArray() -join '; '))}
 Send chat 'number?';Await {-not $window.Busy};if((Reply) -cne '42' -or (Request).messages.Count -ne 3){throw 'Conversation did not resend prior user and assistant messages'}
 Send ask 'number?';Await {-not $window.Busy};if((Reply) -cne 'no context' -or (Request).messages.Count -ne 1){throw 'One-off question leaked conversation context'}
 Send chat 'number?';Await {-not $window.Busy};if((Reply) -cne '42' -or (Request).messages.Count -ne 5){throw 'One-off question changed the ongoing conversation'}
 $settings['local.model'].SelectedItem='model-b';Send chat 'number?';Await {-not $window.Busy};if((Request).model -cne 'model-b' -or (Request).messages.Count -ne 1){throw 'Model change reused another model context'}
 $window.Render((Join-Path $fixture 'before-new-chat.png'))
 $new=@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'New chat'})[0]
 if(-not $new -or -not $new.IsEnabled -or $new.HorizontalAlignment -ne 'Right'){throw 'New chat link missing or unavailable'}
 $new.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)));Pump
 $window.Render((Join-Path $fixture 'new-chat.png'))
 if(@(Children $window.Content|Where-Object {[Windows.Automation.AutomationProperties]::GetName($_) -eq 'Your message text'}).Count){throw 'New chat retained displayed history'}
 if(-not @(Children $window.Content|Where-Object {[Windows.Automation.AutomationProperties]::GetName($_) -eq 'Greeting'}).Count){throw 'New chat did not restore greeting'}
 if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'new-chat.png'))}
 Send chat 'number?';Await {-not $window.Busy};if((Request).messages.Count -ne 1){throw 'New conversation did not clear local context'}
 Send chat 'stream';Await {$window.Busy -and (Reply) -ceq 'First '};$window.Render((Join-Path $fixture 'streaming.png'))
 $selectedReply=Children $window.Content|Where-Object {$_ -is [Windows.Controls.TextBox] -and $_.Text -ceq 'First '}|Select-Object -First 1
 $selectedReply.Select(0,5)
 if(@(Children $window.Content|Where-Object {[Windows.Automation.AutomationProperties]::GetName($_) -eq 'Waiting for reply'}).Count){throw 'Waiting indicator remained after streaming started'}
 if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'ollama-streaming.png'))}
 Await {-not $window.Busy};$window.Render((Join-Path $fixture 'stream-finished.png'));if((Reply) -cne 'First reply'){throw 'Stream fragments did not form one completed answer'}
 if($selectedReply.Text -cne 'First reply' -or $selectedReply.SelectedText -cne 'First'){throw 'Streaming completion replaced the selectable reply or discarded its selection'}
 Send chat 'error';Await {-not $window.Busy};if((Reply) -notlike '*fixture model not found*'){throw 'Ollama HTTP error detail was lost'}
 Send chat 'probe';Await {-not $window.Busy};if(@((Request).messages|Where-Object content -eq 'error').Count){throw 'Failed request polluted history'}
 Send chat 'cancel';Await {$server.Requests.Count -ge 10 -and $window.Busy};$window.Render((Join-Path $fixture 'cancelling.png'))
 $button=@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Cancel'})[0];$button.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)));Await {-not $window.Busy}
 if((Reply) -notlike '*Request cancelled.*'){throw 'HTTP cancellation did not complete the reply state'}
 Send chat 'probe';Await {-not $window.Busy};if(@((Request).messages|Where-Object content -eq 'cancel').Count){throw 'Cancelled request polluted history'}
 Send chat 'truncated';Await {-not $window.Busy};if((Reply) -notlike '*ended before completion*'){throw 'Truncated stream was accepted as complete'}
 Send chat 'probe';Await {-not $window.Busy};if(@((Request).messages|Where-Object content -eq 'truncated').Count){throw 'Truncated response entered history'}
 Send ask 'unicode';Await {-not $window.Busy};$expected='caf'+[char]0xE9+' '+[char]0x2014+' '+[char]0x65E5+[char]0x672C+[char]0x8A9E;if((Reply) -cne $expected){throw 'HTTP response Unicode was corrupted'}
 $text="  line one`nline two  ";Send ask $text;Await {-not $window.Busy};if((Request).messages[0].content -cne $text){throw 'Message content or whitespace was rewritten'}
 if(Test-Path -LiteralPath $env:WHAS_CHAT_CALLS){throw 'Plain local chat launched a command process'}
 $speak.Checked=$true;Send chat 'stream';Await {$controller.GetType().GetProperty('PresentationStatus',$flags).GetValue($controller) -eq ('Preparing speech'+[char]0x2026)}
 if((Reply) -cne 'First reply'){throw 'Speech started before the answer completed'};Await {-not $window.Busy};$speak.Checked=$false
 Send perform 'create note';Await {-not $window.Busy};if((Reply) -cne 'FAKE_TASK'){throw 'Run a task did not retain the command backend'}
 $calls=@(Get-Content -LiteralPath $env:WHAS_CHAT_CALLS|ForEach-Object {,($_|ConvertFrom-Json)})
 if($calls.Count -ne 2 -or $calls[0][0] -cne '--maintain' -or $calls[0][1] -cne 'speak' -or $calls[1][0] -cne 'perform' -or $calls[1][-1] -notlike 'Available workspace folders*create note'){throw 'Only speech and file tasks should use the command backend'}
 foreach($raw in $server.Requests.ToArray()) {$request=$raw|ConvertFrom-Json;if($request.PSObject.Properties.Name -contains 'tools' -or @($request.messages|Where-Object {$_.role -notin @('user','assistant') -or $_.content -like 'Available workspace folders*'}).Count){throw 'Chat payload included tools, instructions or workspace scaffolding'}}
 $server.Dispose();Send ask 'offline';Await {-not $window.Busy};if((Reply) -notlike '*Check that Ollama is running*'){throw 'Unavailable Ollama was not handled clearly'}
 Write-Host 'PASS: direct loopback chat, history isolation, streaming, cancellation, Unicode, error recovery, speech separation and task routing'
} finally {
 if($window){$window.Dispose()};if($server){$server.Dispose()};$env:WHAS_CHAT_CALLS=$savedCalls
 $absolute=[IO.Path]::GetFullPath($fixture);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $absolute) -notmatch '^whas-ollama-chat-[a-f0-9]{32}$'){throw 'Unexpected fixture cleanup target'}
 if(Test-Path -LiteralPath $registration){$marker=Join-Path $registration 'install-root.txt';if((Test-Path -LiteralPath $marker) -and [IO.File]::ReadAllText($marker) -ceq $fixture){Remove-Item -LiteralPath (Join-Path $registration 'whas.exe'),$marker;Remove-Item -LiteralPath $registration}}
 if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
