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
  if((Get-Content $env:WHAS_GUI_CALLS -Raw).Contains('["configure","--set"')){throw 'Loading shared settings wrote configuration'}
  $folderPicker=$controller.GetType().Assembly.GetType('WindowsHybridAgenticStack.FolderPicker')
  $static=[Reflection.BindingFlags]'Static,NonPublic'
  $dialog=$folderPicker.GetMethod('CreateDialog',$static).Invoke($null,@([string]$fixture,[string]'Choose fixture folder'))
  $folderItem=$null;$folderName=[IntPtr]::Zero
  try {
   $dialogType=$folderPicker.GetNestedType('IFileDialog',[Reflection.BindingFlags]::NonPublic)
   $options=@([uint32]0);$dialogType.GetMethod('GetOptions').Invoke($dialog,$options)|Out-Null
   if(($options[0] -band 0x2000868) -ne 0x2000868){throw 'Modern picker does not require an existing filesystem folder or preserve cwd/recent items'}
   $folder=@($null);$dialogType.GetMethod('GetFolder').Invoke($dialog,$folder)|Out-Null;$folderItem=$folder[0]
   $name=@([Convert]::ToUInt32('80058000',16),[IntPtr]::Zero);$folderPicker.GetNestedType('IShellItem',[Reflection.BindingFlags]::NonPublic).GetMethod('GetDisplayName').Invoke($folderItem,$name)|Out-Null;$folderName=$name[1]
   if([Runtime.InteropServices.Marshal]::PtrToStringUni($folderName) -ine $fixture){throw 'Modern picker ignored its starting folder'}
  }finally{if($folderName -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::FreeCoTaskMem($folderName)};if($folderItem){[Runtime.InteropServices.Marshal]::FinalReleaseComObject($folderItem)|Out-Null};[Runtime.InteropServices.Marshal]::FinalReleaseComObject($dialog)|Out-Null}
  if($env:OPENCODE_CONFIG -cne 'parent-config-must-not-change'){throw 'Discovery changed the parent provider configuration'}
  if((Get-Content $env:WHAS_GUI_CALLS -Raw).Contains('["model",')){throw 'GUI discovery still depends on the newer WHAS model command'}
  if($controller.GetType().GetProperty('PresentationOutput',$flags).GetValue($controller).Text.Contains('Unknown command')){throw 'Old installed backend caused a startup error'}
  $runtime=$controller.GetType().GetField('runtime',$flags).GetValue($controller)
  if($runtime.Items.Contains('unavailable-runtime') -or -not $runtime.Items.Contains('opencode')){throw 'Unavailable runtime was offered'}
  if($settings['cloud.model'].SelectedItem -cne '' -or $settings['local.model'].SelectedItem -cne 'local-a:latest'){throw 'Model defaults were not loaded into selectors'}
  $engine=$controller.GetType().GetField('voiceEngine',$flags).GetValue($controller)
  if($engine.SelectedItem -cne 'piper-tts'){throw 'Saved speech engine did not load automatically'}
  $tabs=$controller.GetType().GetProperty('PresentationPages',$flags).GetValue($controller);$speechIndex=0;while($tabs.TabPages[$speechIndex].Text -ne 'Voice'){$speechIndex++}
  $window.SelectPage($speechIndex);Await {-not $window.Busy};$window.Render((Join-Path $fixture 'piper-panels.png'))
  if(@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.TextBlock] -and $_.Text -in @('Add a voice','Saved voices') -and (Shown $_)}).Count){throw 'Piper exposes unsupported custom-voice panels'}
  if(@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.TextBlock] -and $_.Text -eq 'Hardware' -and (Shown $_)}).Count){throw 'Piper exposes an irrelevant hardware selector'}
  if(@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Play test phrase' -and (Shown $_)}).Count -ne 1){throw 'Piper does not show its packaged-voice preview'}
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'piper-panels.png'))}
  $add=$controller.GetType().GetField('voiceAdd',$flags).GetValue($controller)
  if($add.Enabled){throw 'Piper incorrectly permits reference samples'}
  $engine.SelectedItem='f5-tts'
  $window.Render((Join-Path $fixture 'f5-available.png'))
  if(-not @(Children $window.Content|Where-Object {$_ -is [Windows.Controls.TextBlock] -and $_.Text -like 'Requires a WAV recording and a matching UTF-8 .txt*' -and (Shown $_)}).Count){throw 'F5 does not explain the required transcript before installation or file choice'}
  if($add.Enabled){throw 'Uninstalled F5 permits voice samples'}
  $installedActions=$controller.GetType().GetField('installedVoiceActions',$flags).GetValue($controller)
  if(@($installedActions|Where-Object Enabled).Count){throw 'Uninstalled engine actions are enabled'}
  $window.RenderPages((Join-Path $fixture 'pages'))
  $window.SelectPage(0);$window.Render((Join-Path $fixture 'assistant.png'))
  $operationChoice=Children $window.Content|Where-Object {$_ -is [Windows.Controls.ComboBox] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Operation'}|Select-Object -First 1
  if(($operationChoice.Items|ForEach-Object {$_.ToString()}) -join '|' -cne 'Conversation|Run a task|One-off question' -or $operationChoice.SelectedItem.Value -cne 'chat'){throw 'Conversation is not the default first operation, followed by task and one-off question'}
  $runOn=Children $window.Content|Where-Object {$_ -is [Windows.Controls.ComboBox] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Run on'}|Select-Object -First 1
  if(-not $runOn -or $runOn.Items.Count -ne 2 -or $runOn.Items[0].ToString() -cne 'This PC (Default)' -or $runOn.Items[1].ToString() -cne 'Cloud' -or $runOn.SelectedItem.ToString() -cne 'This PC (Default)'){throw 'Run on must contain two distinct destinations with the saved default first'}
  $featureDefault=$controller.GetType().GetField('defaultLocation',$flags).GetValue($controller)
  $featureDefault.SelectedItem='cloud';$window.Render((Join-Path $fixture 'unsaved-default.png'))
  if($runOn.SelectedItem.ToString() -cne 'This PC (Default)'){throw 'Unsaved feature choice changed the effective default label'}
  $featureDefault.SelectedItem='local'
  if($env:WHAS_TEST_REPORTS){$export=Join-Path $env:WHAS_TEST_REPORTS 'configured-pages';New-Item -ItemType Directory -Path $export -Force|Out-Null;Get-ChildItem (Join-Path $fixture 'pages') -Filter '*.png'|ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $export $_.Name) -Force};Copy-Item (Join-Path $fixture 'assistant.png') (Join-Path $env:WHAS_TEST_REPORTS 'assistant.png') -Force;$window.Width=940;$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'assistant-narrow.png'))}
  $prompt=$controller.GetType().GetField('prompt',$flags).GetValue($controller)
  $message=Children $window.Content|Where-Object {$_ -is [Windows.Controls.TextBox] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Your message'}|Select-Object -First 1
  if(-not $message.AcceptsReturn -or $message.TextWrapping -ne 'Wrap' -or $message.VerticalContentAlignment -ne 'Top' -or $message.MinHeight -gt 80){throw 'Composer lost compact multiline behavior'}
  $message.Text="first line`r`nsecond line"
  if($prompt.Text -cne $message.Text){throw 'Multiline message did not reach request controller'}
  $placeholder=Children $window.Content|Where-Object {$_ -is [Windows.Controls.TextBlock] -and $_.Text -like 'Type your message here*'}|Select-Object -First 1
  if(-not $placeholder -or $placeholder.Visibility -ne 'Collapsed'){throw 'Composer placeholder obscures typed text'}
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'assistant-multiline.png'))}
  $prompt.Clear()
  $window.Render((Join-Path $fixture 'assistant.png'))
  if($placeholder.Visibility -ne 'Visible'){throw 'Empty composer lost its placeholder'}
  $shell=$window.Content
  $toggle=$window.GetType().GetField('configurationToggle',$flags).GetValue($window)
  $position=$toggle.TransformToAncestor($shell).Transform((New-Object Windows.Point(0,0)))
  if($toggle.ToolTip -ne 'Configuration' -or $window.GetType().GetField('sidebar',$flags).GetValue($window).Visibility -ne 'Collapsed'){throw 'Installed application still exposes a sidebar instead of its cog'}
  $toggle.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
  $window.Render((Join-Path $fixture 'general.png'))
  $backPosition=$toggle.TransformToAncestor($shell).Transform((New-Object Windows.Point(0,0)))
  if($toggle.ToolTip -ne 'Back to Assistant' -or [Math]::Abs($position.X-$backPosition.X) -gt 1 -or [Math]::Abs($position.Y-$backPosition.Y) -gt 1){throw 'Back control moved from the cog position'}
  $generalChoices=@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.ComboBox]}|ForEach-Object {[Windows.Automation.AutomationProperties]::GetName($_)})
  if($generalChoices.Count -ne 3 -or $generalChoices -contains 'Cloud model' -or $generalChoices -contains 'Starting folder'){throw 'General still mixes model and workspace settings'}
  $toggle.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
  $window.Render((Join-Path $fixture 'assistant.png'))
  $session=$controller.GetType().GetField('session',$flags).GetValue($controller)
  $workspaceA=Join-Path $fixture 'Web Projects';$workspaceB=Join-Path $fixture 'workspace-b'
  New-Item -ItemType Directory -Path $workspaceA,$workspaceB|Out-Null
  [IO.File]::WriteAllText((Join-Path $workspaceA 'keep.txt'),'preserve')
  $controller.GetType().GetMethod('AddWorkspace',$flags).Invoke($controller,@([string]$workspaceA))|Out-Null
  $controller.GetType().GetMethod('AddWorkspace',$flags).Invoke($controller,@([string]$workspaceB))|Out-Null
  $session.Text='old-session'
  $controller.GetType().GetMethod('SetWorkspace',$flags).Invoke($controller,@([string]$workspaceA))|Out-Null
  if($session.Text -ne ''){throw 'Workspace switch retained another workspace session'}
  $controller.GetType().GetMethod('AddWorkspace',$flags).Invoke($controller,@([string]$workspaceA))|Out-Null
  $prefs=Get-Content $preferencesFile -Raw|ConvertFrom-Json
  if(@($prefs.workspaces|Where-Object {$_ -eq $workspaceA}).Count -ne 1){throw 'Saved workspace list permits duplicates'}
  $controller.GetType().GetMethod('RemoveWorkspace',$flags).Invoke($controller,@())|Out-Null
  if(-not (Test-Path (Join-Path $workspaceA 'keep.txt'))){throw 'Removing a saved workspace deleted files'}
  $prefs=Get-Content $preferencesFile -Raw|ConvertFrom-Json
  if($prefs.workspaces -contains $workspaceA -or $prefs.activeWorkspace -eq $workspaceA){throw 'Workspace removal did not update persisted active selection'}
  foreach($folder in @($prefs.workspaces|Where-Object {$_ -ne $workspaceB})){$controller.GetType().GetMethod('RemoveWorkspaceFolder',$flags).Invoke($controller,@([string]$folder))|Out-Null}
  $workspaceC=Join-Path $fixture 'workspace-c'
  New-Item -ItemType Directory -Path $workspaceC|Out-Null
  foreach($folder in @($workspaceA,$workspaceC)){$controller.GetType().GetMethod('AddWorkspace',$flags).Invoke($controller,@([string]$folder))|Out-Null}
  $workspaceIndex=0;$tabs=$controller.GetType().GetProperty('PresentationPages',$flags).GetValue($controller);while($tabs.TabPages[$workspaceIndex].Text -ne 'Workspaces'){$workspaceIndex++}
  $window.SelectPage($workspaceIndex);$window.Render((Join-Path $fixture 'workspaces.png'))
  $removeButtons=@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Remove'})
  if($removeButtons.Count -ne 3){throw 'Saved folders are not individually visible/removable'}
  $folderText=@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.TextBox] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Available folder'})
  if($folderText.Count -ne 3){throw 'Available folder paths are not individually selectable'}
  foreach($path in $folderText){$path.SelectAll();if(-not $path.IsReadOnly -or $path.SelectedText -cne $path.Text -or -not [Windows.Input.ApplicationCommands]::Copy.CanExecute($null,$path) -or $path.BorderThickness.Left -ne 0){throw 'Folder path cannot be selected/copied as plain read-only text'}}
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'workspaces.png'))}
  $window.SelectPage(1)
  $window.Render((Join-Path $fixture 'general.png'))
  $appearance=Children $window.Content|Where-Object {$_ -is [Windows.Controls.ComboBox] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Appearance'}|Select-Object -First 1
  foreach($mode in @('dark','light','system')) {
   # Reacquire after a theme change rebuilds the visible page.
   $appearance=Children $window.Content|Where-Object {$_ -is [Windows.Controls.ComboBox] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Appearance'}|Select-Object -First 1
   $appearance.SelectedItem=@($appearance.Items|Where-Object {$_.Value -eq $mode})[0];Pump
   $window.Render((Join-Path $fixture 'general.png'))
   $prefs=Get-Content $preferencesFile -Raw|ConvertFrom-Json
   if($prefs.theme -cne $mode){throw 'Appearance choice was not persisted'}
   if($mode -eq 'dark' -and $window.Background.Color.ToString() -ne '#FF202020'){throw 'Dark palette was not applied'}
   if($mode -eq 'light' -and $window.Background.Color.ToString() -ne '#FFF3F3F3'){throw 'Light palette was not applied'}
   if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS ('general-'+$mode+'.png')))}
  }
  $reopened=New-Object WindowsHybridAgenticStack.FluentWindow($false,$binary,$catalog,$fixture,[IO.File]::ReadAllText((Join-Path $repo 'scripts/gui-theme.xaml')),$preferencesFile)
  try {$other=$reopened.GetType().GetField('controller',$flags).GetValue($reopened);$savedWorkspace=$other.GetType().GetField('workspace',$flags).GetValue($other);if($savedWorkspace.Text -cne $prefs.activeWorkspace){throw 'Saved active workspace did not reload'}}finally{$reopened.Dispose()}
  $tabs=$controller.GetType().GetProperty('PresentationPages',$flags).GetValue($controller)
  $featureIndex=0;while($tabs.TabPages[$featureIndex].Text -ne 'Features'){$featureIndex++}
  $window.SelectPage($featureIndex)
  $window.Render((Join-Path $fixture 'features.png'))
  $labels=@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button]}|ForEach-Object {$_.Content})
  if($labels -contains 'Accounts' -or $labels -contains 'Agents' -or $labels -contains 'Features' -or $labels -contains 'Removal' -or $labels -notcontains 'Maintenance'){throw 'Obsolete configuration tabs remain'}
  if($labels -notcontains 'Preview removal' -or $labels -notcontains 'Uninstall…'){throw 'Maintenance does not include whole-app removal'}
  if(@($tabs.TabPages|Where-Object {$_.Text -in @('Accounts','Agents & models')}).Count){throw 'Removed account/agent pages still exist'}
  foreach($field in @('cloud','local','voice')){if($controller.GetType().GetField($field,$flags).GetValue($controller).AccessibleDescription -eq 'Not configured in this folder'){throw 'Installed feature status was lost'}}
  $repair=Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Repair…'}
  $remove=Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Remove…'}
  if(@($repair).Count -ne 3 -or @($remove).Count -ne 3){throw 'Installed feature cards do not offer Repair and Remove'}
  if(@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.CheckBox] -and [Windows.Automation.AutomationProperties]::GetName($_) -ne 'Retain installer-created Ollama models'}).Count){throw 'Installed features still use setup checkboxes'}
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'features-installed.png'))}
  [IO.File]::WriteAllText((Join-Path $fixture 'config/config.json'),'{"agents":{"local":{"enabled":false}}}')
  $window.SelectPage($featureIndex);$window.Render((Join-Path $fixture 'features-removed.png'))
  if(@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Add…'}).Count -ne 1){throw 'Removed route does not offer Add'}
  Remove-Item -LiteralPath (Join-Path $fixture 'config/config.json')
  $controller.GetType().GetMethod('BeginMaintenance',$flags).Invoke($controller,@('local'))|Out-Null
  if($controller.GetType().GetField('defaultModel',$flags).GetValue($controller).SelectedItem -cne 'local-a:latest'){throw 'Local maintenance discarded the saved model'}
  $statePath=Join-Path $fixture '.whas-installation.json';$originalState=[IO.File]::ReadAllText($statePath)
  $state=$originalState|ConvertFrom-Json;$state|Add-Member -NotePropertyName Models -NotePropertyValue @([pscustomobject]@{Name='qwen2.5:1.5b';Kind='Source'})
  $state|ConvertTo-Json -Depth 12|Set-Content $statePath
  $controller.GetType().GetMethod('SetControl',$flags).Invoke($controller,@('local.model','whas-qwen2-5-1-5b-ctx16384'))|Out-Null
  $controller.GetType().GetMethod('BeginMaintenance',$flags).Invoke($controller,@('local'))|Out-Null
  if($controller.GetType().GetField('defaultModel',$flags).GetValue($controller).SelectedItem -cne 'qwen2.5:1.5b'){throw 'Local repair would wrap a managed alias or change its source model'}
  [IO.File]::WriteAllText($statePath,$originalState);$controller.GetType().GetMethod('SetControl',$flags).Invoke($controller,@('local.model','local-a:latest'))|Out-Null
  $controller.GetType().GetMethod('BeginMaintenance',$flags).Invoke($controller,@('cloud'))|Out-Null
  $window.SelectPage($featureIndex)
  $window.Render((Join-Path $fixture 'maintenance.png'))
  $maintenanceButtons=@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button]})
  $ready=$maintenanceButtons|Where-Object Content -eq 'Check readiness'
  $review=$maintenanceButtons|Where-Object Content -eq 'Review changes'
  $apply=$maintenanceButtons|Where-Object Content -eq 'Apply changes…'
  if($review.IsEnabled -or $apply.IsEnabled){throw 'Maintenance bypasses readiness and preview'}
  $ready.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
  $window.Render((Join-Path $fixture 'maintenance-busy.png'))
  if($controller.GetType().GetProperty('PresentationCancel',$flags).GetValue($controller).Enabled -or @(Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Cancel' -and (Shown $_)}).Count){throw 'Configuration readiness exposes cancellation'}
  Await {(-not $window.Busy) -and $review.IsEnabled}
  if($apply.IsEnabled){throw 'Maintenance bypasses its preview'}
  $review.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
  Await {(-not $window.Busy) -and $apply.IsEnabled}
  $featureDefault.SelectedItem=if($featureDefault.SelectedItem -eq 'cloud'){'local'}else{'cloud'};Pump;$window.Render((Join-Path $fixture 'maintenance.png'))
  if($apply.IsEnabled -or $review.IsEnabled){throw 'Changed maintenance options reuse stale readiness/preview'}
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'maintenance.png'))}
  $window.SelectPage(0)
  $window.Render((Join-Path $fixture 'assistant.png'))
  $logSource=$controller.GetType().GetProperty('PresentationOutput',$flags).GetValue($controller)
  $logSource.Text='diagnostic history'
  $window.GetType().GetMethod('OpenLog',$flags).Invoke($window,@($true))|Out-Null
  $clear=$window.GetType().GetField('clearLog',$flags).GetValue($window)
  $clear.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
  if($logSource.Text.Length -or $clear.Visibility -ne 'Visible'){throw 'Clear log did not clear source history'}
  $window.GetType().GetMethod('OpenLog',$flags).Invoke($window,@($false))|Out-Null
  if($clear.Visibility -ne 'Collapsed' -or $window.GetType().GetField('logToggle',$flags).GetValue($window).Content -ne 'Show activity log'){throw 'Collapsed log actions are incorrect'}
  $action=$controller.GetType().GetField('action',$flags).GetValue($controller)
  # Keep these command-backend scenarios on Cloud. Direct local chat is
  # exercised against a loopback Ollama fixture in test-ollama-chat.ps1.
  $controller.GetType().GetField('route',$flags).GetValue($controller).SelectedItem='cloud'
  $speak=$controller.GetType().GetField('speak',$flags).GetValue($controller)
  $conversation=$controller.GetType().GetField('conversation',$flags).GetValue($controller)
  $action.SelectedItem='chat';$speak.Checked=$true;$prompt.Text='question'
  $send=Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Send'}|Select-Object -First 1
  $send.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
  Await {$window.Busy -and $controller.GetType().GetProperty('PresentationStatus',$flags).GetValue($controller) -eq 'Preparing speech…'}
  $window.Render((Join-Path $fixture 'composer-speaking.png'))
  if($send.Content -ne 'Cancel' -or -not $controller.GetType().GetProperty('IsAssistantRequestRunning',$flags).GetValue($controller)){throw 'Message speech lost its request cancellation state'}
  Await {(-not $window.Busy) -and $send.IsEnabled -and $conversation.Text.Contains('ANSWER') -and (Get-Content $env:WHAS_GUI_CALLS -Raw).Contains('"--maintain","speak"')}
  $chat=(Get-Content $env:WHAS_GUI_CALLS|Where-Object {$_.StartsWith('["chat"')}|Select-Object -Last 1)|ConvertFrom-Json
  if($chat -contains '--voice' -or $chat -notcontains '--no-voice'){throw 'GUI still invokes unsupported CLI chat speech'}
  $overlay=Get-Content $env:WHAS_GUI_CONTEXT -Raw|ConvertFrom-Json
  $permissionsOverlay=$controller.GetType().GetMethod('WorkspaceConfiguration',$flags).Invoke($controller,@())|ConvertFrom-Json
  $localOverlay=$controller.GetType().GetMethod('RequestConfiguration',$flags).Invoke($controller,@($true))|ConvertFrom-Json
  if($localOverlay.provider.ollama.models.'local-a:latest'.name -cne 'Custom local model' -or $localOverlay.provider.ollama.models.'local-a:latest'.limit.context -ne 8192 -or $localOverlay.provider.ollama.models.'local-b:latest'.name -cne 'local-b:latest'){throw 'Local task configuration omitted Ollama models discovered after installation'}
  $cloudOverlay=$controller.GetType().GetMethod('RequestConfiguration',$flags).Invoke($controller,@($false))|ConvertFrom-Json
  if($cloudOverlay.provider.ollama.models.PSObject.Properties['local-b:latest']){throw 'Cloud request added local model definitions'}
  if($overlay.model -cne 'provider/inherited' -or $overlay.agent.'ps-read'.permission.edit -cne 'deny'){throw 'Workspace access changed unrelated inherited model/tool permissions'}
  foreach($name in @('ps-read','ps-write')) {
   $rules=$permissionsOverlay.agent.$name.permission.external_directory
   if($rules.'*' -ne 'ask'){throw 'Workspace grants removed the external-directory fallback'}
   foreach($folder in @($workspaceA,$workspaceB,$workspaceC)) {
    $pattern=$folder.Replace('\','/')+'/**'
    if($rules.PSObject.Properties[$pattern].Value -ne 'allow'){throw 'A saved workspace or its subfolders is missing from child permissions'}
    $ruleRegex='^'+[regex]::Escape($pattern).Replace('\*','.*')+'$'
    if(($folder.Replace('\','/')+'/sub/deep/file.txt') -notmatch $ruleRegex -or ($folder.Replace('\','/')+'-sibling/file.txt') -match $ruleRegex){throw 'Workspace permission crossed a folder boundary'}
   }
  }
  if($chat[-1] -cne 'question'){throw 'Conversation message was rewritten with workspace instructions'}
  if($env:OPENCODE_CONFIG_CONTENT -cne '{"model":"provider/inherited","provider":{"ollama":{"options":{"baseURL":"http://127.0.0.1:11434/v1"},"models":{"local-a:latest":{"name":"Custom local model","limit":{"context":8192}}}}},"agent":{"ps-read":{"permission":{"edit":"deny"}}}}'){throw 'Request changed parent inline configuration'}
  if($conversation.Text.Contains('TTS_DIAGNOSTIC')){throw 'Speech diagnostics leaked into the answer'}
  if($controller.GetType().GetField('session',$flags).GetValue($controller).Text -cne 'ses_test'){throw 'Conversation did not retain its session'}
  $literal='write "blah.txt" in "'+$workspaceA+'" containing "weeb"'+"`r`n"+'Keep spaces in the path.'
  $action.SelectedItem='perform';$speak.Checked=$false;$prompt.Text=$literal
  $send.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)));Await {-not $window.Busy}
  $taskCall=(Get-Content $env:WHAS_GUI_CALLS|Where-Object {$_.StartsWith('["perform",')}|Select-Object -Last 1)|ConvertFrom-Json
  if(-not $taskCall[-1].EndsWith($literal,[StringComparison]::Ordinal)){throw 'GUI handoff changed a quoted task path or multiline message'}
  $action.SelectedItem='chat';$speak.Checked=$true
  $prompt.Text='fail speech'
  $send.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
  Await {(-not $window.Busy) -and $controller.GetType().GetProperty('PresentationStatus',$flags).GetValue($controller).StartsWith('Stopped or failed')}
  if(-not $conversation.Text.Contains('Assistant: fail speech')){throw 'Playback failure discarded the generated answer'}
  if(-not $controller.GetType().GetProperty('PresentationOutput',$flags).GetValue($controller).Text.Contains('Operation failed (exit 1)')){throw 'Playback failure left only a footer without log diagnostics'}
  $window.GetType().GetMethod('OpenLog',$flags).Invoke($window,@($false))|Out-Null
  $env:WHAS_GUI_DISCOVERY_FAIL='1'
  $controller.GetType().GetMethod('RefreshModels',$flags).Invoke($controller,@())|Out-Null
  Await {(-not $window.Busy) -and $controller.GetType().GetField('modelNotice',$flags).GetValue($controller).Text.Contains('OpenCode discovery failed')}
  Pump
  if($window.GetType().GetField('logOpen',$flags).GetValue($window)){throw 'Optional discovery failure opened the activity log as a fatal startup error'}
  if($settings['cloud.model'].SelectedItem -cne '' -or $settings['local.model'].SelectedItem -cne 'local-a:latest'){throw 'Discovery failure discarded saved model choices'}
  Remove-Item -LiteralPath (Join-Path $registration 'opencode.exe')
  $controller.GetType().GetMethod('RefreshModels',$flags).Invoke($controller,@())|Out-Null
  Await {(-not $window.Busy) -and $controller.GetType().GetField('modelNotice',$flags).GetValue($controller).Text.Contains('OpenCode was not found')}
  $env:WHAS_GUI_VOICE_MODE='legacy'
  $controller.GetType().GetMethod('RefreshVoice',$flags).Invoke($controller,@($null))|Out-Null
  Await {(-not $window.Busy) -and $engine.SelectedItem -eq 'chatterbox-turbo'}
  $names=$controller.GetType().GetField('voiceName',$flags).GetValue($controller)
  if(-not $names.Items.Contains('c3po') -or $names.Items.Contains('c3po_prompt')){throw 'Old backend still exposes storage filenames as voice IDs'}
  $names.SelectedItem='c3po'
  if(-not $controller.GetType().GetField('voiceDefault',$flags).GetValue($controller).Enabled){throw 'Older backend prevents saving a valid voice default'}
  $voiceIndex=0;while($tabs.TabPages[$voiceIndex].Text -ne 'Voice'){$voiceIndex++}
  $window.SelectPage($voiceIndex);$window.Render((Join-Path $fixture 'speech.png'))
  $play=Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Play test phrase'}|Select-Object -First 1
  $play.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
  Await {-not $window.Busy}
  $preview=(Get-Content $env:WHAS_GUI_CALLS|Where-Object {$_.StartsWith('["--maintain","speak"')}|Select-Object -Last 1)|ConvertFrom-Json
  if($preview[[array]::IndexOf($preview,'--voice-name')+1] -cne 'c3po'){throw 'Preview requested the wrong voice ID'}
  $reference=Join-Path $fixture 'recording.wav';[IO.File]::WriteAllText($reference,'fixture')
  $before=Get-Content $env:WHAS_GUI_CALLS -Raw
  $controller.GetType().GetMethod('SelectVoiceRecording',$flags).Invoke($controller,@([string]$reference))|Out-Null
  if((Get-Content $env:WHAS_GUI_CALLS -Raw) -cne $before){throw 'Choosing a WAV submitted or played it'}
  $nameField=$controller.GetType().GetField('voiceReferenceName',$flags).GetValue($controller)
  $nameField.Text='c3po';if($add.Enabled){throw 'Duplicate voice name can be submitted'}
  $nameField.Text='';if($add.Enabled){throw 'Empty voice name can be submitted'}
  $nameField.Text='new-voice';if(-not $add.Enabled){throw 'Complete staged voice cannot be saved'}
  $controller.GetType().GetMethod('SaveVoiceReference',$flags).Invoke($controller,@())|Out-Null
  Await {(-not $window.Busy) -and $names.SelectedItem -eq 'new-voice'}
  $newCalls=Get-Content $env:WHAS_GUI_CALLS -Raw
  if($newCalls.Substring($before.Length).Contains('"tts","say"') -or $newCalls.Substring($before.Length).Contains('"configure","--set"')){throw 'Saving a voice played it or changed its default'}
  $controller.GetType().GetMethod('SelectVoiceRecording',$flags).Invoke($controller,@([string]$reference))|Out-Null
  $nameField.Text='fail-save';$controller.GetType().GetMethod('SaveVoiceReference',$flags).Invoke($controller,@())|Out-Null
  Await {-not $window.Busy}
  if($nameField.Text -cne 'fail-save' -or $controller.GetType().GetField('voiceReferencePath',$flags).GetValue($controller).Text -cne $reference){throw 'Failed save discarded the staged form'}
  $nameField.Text='default-now';$controller.GetType().GetField('voiceMakeDefault',$flags).GetValue($controller).Checked=$true
  if(-not $controller.GetType().GetField('voiceImportNotice',$flags).GetValue($controller).Text.Contains('makes it this engine')){throw 'Voice import guidance contradicts the Make default checkbox'}
  $controller.GetType().GetMethod('SaveVoiceReference',$flags).Invoke($controller,@())|Out-Null
  Await {(-not $window.Busy) -and $controller.GetType().GetField('savedVoices',$flags).GetValue($controller)['chatterbox-turbo'] -eq 'default-now'}
  $savedCreation=(Get-Content $env:WHAS_GUI_CALLS|Where-Object {$_.StartsWith('["--maintain","voice-default"')}|Select-Object -Last 1)|ConvertFrom-Json
  if($savedCreation[[array]::IndexOf($savedCreation,'--voice-name')+1] -cne 'default-now'){throw 'Make default did not save the newly imported voice'}
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'speech-staged.png'));$window.GetType().GetMethod('OpenLog',$flags).Invoke($window,@($false))|Out-Null;$pageHost=$window.GetType().GetField('pageHost',$flags).GetValue($window);$pageHost.Content.ScrollToBottom();$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'voice-import.png'))}
  $env:WHAS_GUI_VOICE_MODE='current';$controller.GetType().GetMethod('RefreshVoice',$flags).Invoke($controller,@($null))|Out-Null
  Await {-not $window.Busy};$names.SelectedItem='c3po'
  $defaultButton=$controller.GetType().GetField('voiceDefault',$flags).GetValue($controller)
  if(-not $defaultButton.Enabled){throw 'Updated backend cannot save a custom default'}
  $controller.GetType().GetMethod('InvokePresentationAction',$flags).Invoke($controller,@($defaultButton))|Out-Null
  Await {-not $window.Busy}
  $saved=(Get-Content $env:WHAS_GUI_CALLS|Where-Object {$_.StartsWith('["--maintain","voice-default"')}|Select-Object -Last 1)|ConvertFrom-Json
  if($saved[[array]::IndexOf($saved,'--voice-name')+1] -cne 'c3po' -or $saved[[array]::IndexOf($saved,'--tts-engine')+1] -cne 'chatterbox-turbo'){throw 'Default action did not save the selected voice for its engine'}
  $savedVoices=$controller.GetType().GetField('savedVoices',$flags).GetValue($controller);$savedVoices['chatterbox-turbo']='C3PO';$names.SelectedItem='default';$names.SelectedItem='c3po'
  if($controller.GetType().GetField('voiceRemove',$flags).GetValue($controller).Enabled){throw 'Case differences bypass the current-default deletion guard'}
  $env:WHAS_GUI_VOICE_MODE='f5';$controller.GetType().GetMethod('RefreshVoice',$flags).Invoke($controller,@($null))|Out-Null
  Await {-not $window.Busy};$controller.GetType().GetMethod('SelectVoiceRecording',$flags).Invoke($controller,@([string]$reference))|Out-Null
  if($add.Enabled){throw 'F5 import accepts a missing transcript'}
  [IO.File]::WriteAllText([IO.Path]::ChangeExtension($reference,'.txt'),'Spoken words in the recording.')
  $nameField.Text='f5-sample';if(-not $add.Enabled){throw 'F5 WAV and matching transcript cannot be staged'}
  $window.Render((Join-Path $fixture 'f5-transcript.png'))
  $transcriptBox=Children $window.Content|Where-Object {$_ -is [Windows.Controls.TextBox] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Required matching transcript'}|Select-Object -First 1
  if(-not $transcriptBox -or -not (Shown $transcriptBox) -or $transcriptBox.Text -cne [IO.Path]::ChangeExtension($reference,'.txt')){throw 'F5 does not show the expected matching transcript path'}
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'f5-transcript.png'))}
  # Shared selectors save on user changes, never during load/discovery/rollback.
  $window.SelectPage(1);$window.Render((Join-Path $fixture 'autosave-general.png'))
  if(@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Save'}).Count){throw 'Settings still require Save buttons'}
  foreach($pair in @(@('location','cloud'),@('speech.enabled','true'),@('runtime','none'),@('runtime','opencode'),@('cloud.model','provider/model-a'),@('cloud.model',''),@('local.model','local-b:latest'),@('speech.device','cuda'),@('speech.autoStart','false'))) {
   $before=@(Get-Content $env:WHAS_GUI_CALLS|Where-Object {$_.StartsWith('["configure","--set"')}).Count
   $settings[$pair[0]].SelectedItem=$pair[1];Await {-not $window.Busy}
   $writes=@(Get-Content $env:WHAS_GUI_CALLS|Where-Object {$_.StartsWith('["configure","--set"')})
   if($writes.Count -ne $before+1){throw "Setting $($pair[0]) did not save exactly once"}
   $request=$writes[-1]|ConvertFrom-Json;if($request[2] -cne $pair[0] -or $request[3] -cne $pair[1]){throw 'Auto-save submitted the wrong setting/value'}
   if($pair[0] -eq 'location') {
    $window.SelectPage(0);$window.Render((Join-Path $fixture 'cloud-default.png'))
    $cloudRoute=Children $window.Content|Where-Object {$_ -is [Windows.Controls.ComboBox] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Run on'}|Select-Object -First 1
    if($cloudRoute.Items.Count -ne 2 -or $cloudRoute.Items[0].ToString() -cne 'Cloud (Default)' -or $cloudRoute.Items[1].ToString() -cne 'This PC'){throw 'Cloud default still produces a duplicate route'}
   }
  }
  $settings['cloud.model'].Items.Add('provider/rejected')|Out-Null;$settings['cloud.model'].SelectedItem='provider/rejected';Await {-not $window.Busy}
  if($settings['cloud.model'].SelectedItem -cne '' -or -not $controller.GetType().GetProperty('PresentationOutput',$flags).GetValue($controller).Text.Contains('Fixture settings rejection')){throw 'Failed auto-save did not restore its previous value and report its error'}
  $before=@(Get-Content $env:WHAS_GUI_CALLS|Where-Object {$_.StartsWith('["configure","--set"')}).Count
  $controller.GetType().GetMethod('ApplyModelChoices',$flags).Invoke($controller,@('cloud.model',[string[]]@('provider/model-a'),$true))|Out-Null
  $controller.GetType().GetMethod('LoadPresentationSettings',$flags).Invoke($controller,@())|Out-Null;Await {-not $window.Busy}
  if(@(Get-Content $env:WHAS_GUI_CALLS|Where-Object {$_.StartsWith('["configure","--set"')}).Count -ne $before){throw 'Reload/discovery or rollback caused an extra auto-save'}
  $window.GetType().GetMethod('OpenLog',$flags).Invoke($window,@($false))|Out-Null
  $window.SelectPage(0);$window.Render((Join-Path $fixture 'keyboard.png'))
  $action.SelectedItem='ask';$speak.Checked=$false
  $keyMethod=$window.GetType().GetMethod('HandleMessageKey',$flags)
  $logToggle=$window.GetType().GetField('logToggle',$flags).GetValue($window);$footerBefore=$logToggle.TransformToAncestor($window.Content).Transform((New-Object Windows.Point(0,0)))
  Copy-Item -LiteralPath $binary -Destination (Join-Path $registration 'opencode.exe')
  $env:WHAS_GUI_DISCOVERY_FAIL='wait';$controller.GetType().GetMethod('RefreshCloudModels',$flags).Invoke($controller,@())|Out-Null
  $window.Render((Join-Path $fixture 'composer-loading.png'))
  $loadingSend=Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Send'}|Select-Object -First 1
  if(-not $window.Busy -or -not $loadingSend -or $loadingSend.IsEnabled){throw "Model discovery did not show a ghosted Send: busy=$($window.Busy), button=$($null -ne $loadingSend), enabled=$($loadingSend.IsEnabled)"}
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'composer-loading.png'))}
  Await {-not $window.Busy};$env:WHAS_GUI_DISCOVERY_FAIL=$null;$window.Render((Join-Path $fixture 'composer-ready.png'))
  if($loadingSend.Content -ne 'Send' -or -not $loadingSend.IsEnabled){throw 'Send did not become ready after model discovery'}
  $prompt.Text='keyboard question'
  if($keyMethod.Invoke($window,@([Windows.Input.Key]::Return,[Windows.Input.ModifierKeys]::Shift,$false))){throw 'Shift+Enter was swallowed instead of allowing a newline'}
  $before=@(Get-Content $env:WHAS_GUI_CALLS|Where-Object {$_.StartsWith('["ask"')}).Count
  $messageBox=Children $window.Content|Where-Object {$_ -is [Windows.Controls.TextBox] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Your message'}|Select-Object -First 1
  $source=[Windows.Interop.HwndSource]::FromHwnd((New-Object Windows.Interop.WindowInteropHelper($window)).Handle)
  $enter=New-Object Windows.Input.KeyEventArgs([Windows.Input.Keyboard]::PrimaryDevice,$source,0,[Windows.Input.Key]::Return);$enter.RoutedEvent=[Windows.Input.Keyboard]::PreviewKeyDownEvent;$messageBox.RaiseEvent($enter)
  if(-not $enter.Handled){throw 'Enter did not submit the message'}
  $window.Render((Join-Path $fixture 'keyboard-busy.png'));$footerBusy=$logToggle.TransformToAncestor($window.Content).Transform((New-Object Windows.Point(0,0)))
  if([Math]::Abs($footerBefore.X-$footerBusy.X) -gt 1 -or [Math]::Abs($footerBefore.Y-$footerBusy.Y) -gt 1){throw 'Progress/cancel changed the footer button layout'}
  $null=$keyMethod.Invoke($window,@([Windows.Input.Key]::Return,[Windows.Input.ModifierKeys]::None,$true));Await {-not $window.Busy}
  if(@(Get-Content $env:WHAS_GUI_CALLS|Where-Object {$_.StartsWith('["ask"')}).Count -ne $before+1){throw 'Enter submitted zero or multiple requests'}
  $prompt.Clear();$null=$keyMethod.Invoke($window,@([Windows.Input.Key]::Return,[Windows.Input.ModifierKeys]::None,$false));if($window.Busy){throw 'Empty Enter submitted a request'}
  $window.Render((Join-Path $fixture 'composer-idle.png'))
  $composerAction=Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Send'}|Select-Object -First 1
  $sendWidth=$composerAction.ActualWidth;$sendPosition=$composerAction.TransformToAncestor($window.Content).Transform((New-Object Windows.Point(0,0)))
  $prompt.Text='wait for cancellation';$composerAction.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
  Await {$window.Busy -and $composerAction.Content -eq 'Cancel' -and $composerAction.IsEnabled}
  $window.Render((Join-Path $fixture 'composer-cancel.png'))
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'composer-cancel.png'))}
  $cancelPosition=$composerAction.TransformToAncestor($window.Content).Transform((New-Object Windows.Point(0,0)))
  if($composerAction.ActualWidth -ne $sendWidth -or $sendWidth -lt 80 -or [Math]::Abs($sendPosition.X-$cancelPosition.X) -gt 1 -or [Math]::Abs($sendPosition.Y-$cancelPosition.Y) -gt 1){throw 'Cancel did not replace Send at the same size and position'}
  $footerCancel=$window.GetType().GetField('cancel',$flags).GetValue($window)
  if($footerCancel.Visibility -ne 'Collapsed'){throw 'Assistant cancellation still occupies the footer'}
  $footer=$logToggle.Parent;$right=$logToggle.TransformToAncestor($footer).Transform((New-Object Windows.Point($logToggle.ActualWidth,0)))
  if([Math]::Abs($right.X-$footer.ActualWidth) -gt 1){throw 'Activity log is not at the footer right edge'}
  $composerAction.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)));Await {-not $window.Busy}
  $window.Render((Join-Path $fixture 'composer-cancelled.png'))
  if($composerAction.Content -ne 'Send' -or -not $composerAction.IsEnabled -or $composerAction.ActualWidth -ne $sendWidth){throw 'Send did not return after cancellation'}
  if(@(Children $window.Content|Where-Object {[Windows.Automation.AutomationProperties]::GetName($_) -eq 'Waiting for reply'}).Count -or -not @(Children $window.Content|Where-Object {$_ -is [Windows.Controls.TextBox] -and $_.Text -ceq 'Request cancelled.'}).Count){throw 'Cancellation left a waiting reply or lost the submitted message'}
  $prompt.Text='delayed reply';$composerAction.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
  $window.Render((Join-Path $fixture 'reply-pending.png'))
  $pendingQuestion=@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.Border] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Your question' -and $_.Child.Text -ceq 'delayed reply'})
  $waitingLine=Children $window.Content|Where-Object {$_ -is [Windows.Controls.TextBlock] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Waiting for reply'}|Select-Object -First 1
  if(-not $window.Busy -or $pendingQuestion.Count -ne 1 -or -not $waitingLine -or $prompt.Text.Length){throw 'Submitted message and waiting indicator are not visible immediately or the composer was not cleared'}
  $phases=@();$prompt.Text='Draft for next request'
  1..10|ForEach-Object {Start-Sleep -Milliseconds 150;$window.Render((Join-Path $fixture 'reply-pending.png'));$phases+=$waitingLine.Text;Pump}
  if(@($phases|Select-Object -Unique).Count -ne 3 -or @($phases|Where-Object {$_ -notmatch '^Waiting for reply\.{1,3}$'}).Count){throw 'Waiting dots do not cycle through one, two and three dots'}
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'reply-pending.png'))}
  Await {-not $window.Busy};$window.Render((Join-Path $fixture 'reply-arrived.png'))
  if($prompt.Text -cne 'Draft for next request' -or @(Children $window.Content|Where-Object {[Windows.Automation.AutomationProperties]::GetName($_) -eq 'Waiting for reply'}).Count){throw 'Reply arrival left a spinner or erased a new draft'}
  if(@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.Border] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Your question' -and $_.Child.Text -ceq 'delayed reply'}).Count -ne 1){throw 'Reply arrival duplicated the submitted question'}
  $prompt.Text='request failure';$composerAction.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)));Await {-not $window.Busy};$window.Render((Join-Path $fixture 'reply-failed.png'))
  if(@(Children $window.Content|Where-Object {[Windows.Automation.AutomationProperties]::GetName($_) -eq 'Waiting for reply'}).Count -or -not @(Children $window.Content|Where-Object {$_ -is [Windows.Controls.TextBox] -and $_.Text -like 'Could not get a reply.*'}).Count){throw 'Failed request left the waiting animation running'}
  $action.SelectedItem='chat';$prompt.Text='invalid chat response';$composerAction.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)));Await {-not $window.Busy};$window.Render((Join-Path $fixture 'reply-invalid.png'))
  if(@(Children $window.Content|Where-Object {[Windows.Automation.AutomationProperties]::GetName($_) -eq 'Waiting for reply'}).Count -or -not @(Children $window.Content|Where-Object {$_ -is [Windows.Controls.TextBox] -and $_.Text -ceq 'Could not read the reply. Try again.'}).Count){throw 'Malformed reply left the waiting animation running'}
  $action.SelectedItem='ask';$prompt.Clear()
  $window.GetType().GetMethod('OpenLog',$flags).Invoke($window,@($false))|Out-Null
  $window.SelectPage(0);$window.Render((Join-Path $fixture 'routing-updated.png'))
  $runOn=Children $window.Content|Where-Object {$_ -is [Windows.Controls.ComboBox] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Run on'}|Select-Object -First 1
  $defaultRoute=$controller.GetType().GetField('savedLocation',$flags).GetValue($controller)
  if($runOn.Items.Count -ne 2 -or $runOn.Items[0].Value -ne $defaultRoute -or $runOn.Items[0].ToString() -notlike '* (Default)'){throw 'Saved routing default did not move to the first of two choices'}
  $timeout=$controller.GetType().GetField('settings',$flags).GetValue($controller)['speech.idleTimeoutMinutes']
  $timeout.SelectedItem='30';Await {-not $window.Busy}
  if(-not ((Get-Content $env:WHAS_GUI_CALLS -Raw).Contains('"speech-timeout"'))){throw 'Idle timeout did not autosave through the bundled compatibility path'}
  $timeout.SelectedItem='120';Await {-not $window.Busy}
  if($timeout.SelectedItem -ne '30'){throw 'Rejected timeout did not roll back'}
  $window.GetType().GetMethod('OpenLog',$flags).Invoke($window,@($false))|Out-Null
  $window.Render((Join-Path $fixture 'timeout-saved.png'))
  foreach($theme in @('light','dark')){
   $controller.GetType().GetField('preferences',$flags).GetValue($controller).Theme=$theme;$window.GetType().GetMethod('ApplyTheme',$flags).Invoke($window,@())|Out-Null;$window.Render((Join-Path $fixture 'canvas.png'))
   $answerBox=Children $window.Content|Where-Object {$_ -is [Windows.Controls.Border] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Responses'}|Select-Object -First 1
   if($answerBox.Background.Color.ToString() -ne $window.Background.Color.ToString() -or $answerBox.BorderThickness.Left -le 0){throw 'Response background differs from canvas or lost its border'}
   $send=Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Send'}|Select-Object -First 1
   if($send.Background.Color.ToString() -cne '#FF173E76' -or $send.Foreground.Color.ToString() -cne '#FFFFFFFF'){throw 'Send colour differs between themes'}
   $palette=$window.GetType().GetField('shell',$flags).GetValue($window).Resources
   $cancelStyle=$palette['Cancel'];$probe=New-Object Windows.Controls.Button;$probe.Style=$cancelStyle
   if($probe.Background.Color.ToString() -cne '#FF762D17' -or $probe.Foreground.Color.ToString() -cne '#FFFFFFFF'){throw 'Cancel does not use the requested red and white'}
   $expectedLink=if($theme -eq 'light'){'#FF173E76'}else{'#FF60CDFF'}
   if($palette['Accent'].Color.ToString() -cne $expectedLink){throw 'Link contrast does not follow the selected theme'}
   if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS ('assistant-'+$theme+'.png')))}
  }
  $addReply=$controller.GetType().GetMethod('AddConversationReply',$flags)
  $question="Multiline question`nYou: literal text`nAssistant: also literal"
  $addReply.Invoke($controller,@($question,([string]::Join([Environment]::NewLine,(1..100|ForEach-Object {'Reply line '+$_})))))|Out-Null
  $window.Render((Join-Path $fixture 'responses-long.png'));Pump;$window.Render((Join-Path $fixture 'responses-scrolled.png'));Pump
  $history=$answerBox.Child
  if($history.ScrollableHeight -le 0 -or $history.VerticalOffset -lt ($history.ScrollableHeight-1)){throw 'New replies did not scroll to the bottom'}
  $bubble=Children $answerBox|Where-Object {$_ -is [Windows.Controls.Border] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Your question' -and $_.Child.Text -ceq $question}|Select-Object -First 1
  if(-not $bubble -or $bubble.CornerRadius.TopLeft -ne 8 -or $bubble.Padding.Left -lt 10 -or $bubble.Background.Color.ToString() -cne '#FF173E76' -or $bubble.Child.Foreground.Color.ToString() -cne '#FFFFFFFF'){throw 'Multiline question lost its bubble, padding, colours or literal content'}
  $bubble.Child.SelectAll()
  $replyText=Children $answerBox|Where-Object {$_ -is [Windows.Controls.TextBox] -and $_.Text.StartsWith('Reply line 1')}|Select-Object -First 1
  $replyText.Select(0,12);$selection=$replyText.SelectedText
  if(-not $bubble.Child.IsReadOnly -or $bubble.Child.SelectedText -cne $question -or -not $replyText.IsReadOnly -or -not [Windows.Input.ApplicationCommands]::Copy.CanExecute($null,$replyText) -or $replyText.BorderThickness.Left -ne 0){throw 'Chat messages are not selectable/copyable read-only text'}
  $history.ScrollToHome();$addReply.Invoke($controller,@('Latest question','Latest reply'))|Out-Null;$window.Render((Join-Path $fixture 'responses-appended.png'));Pump
  if($replyText.SelectedText -cne $selection -or $bubble.Child.SelectedText -cne $question -or -not @(Children $answerBox|Where-Object {$_ -eq $replyText}).Count){throw 'A new reply discarded the existing chat selection'}
  if($history.VerticalOffset -lt ($history.ScrollableHeight-1)){throw 'Appending a reply left the response pane scrolled above it'}
  $longQuestion=('A longer question that wraps naturally across the available width. '*25)+"`nSecond paragraph."
  $addReply.Invoke($controller,@($longQuestion,'A short answer.'))|Out-Null
  $window.Render((Join-Path $fixture 'wrapped-question.png'));Pump;$window.Render((Join-Path $fixture 'wrapped-question.png'));Pump
  $wrapped=Children $answerBox|Where-Object {$_ -is [Windows.Controls.Border] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Your question' -and $_.Child.Text -ceq $longQuestion}|Select-Object -First 1
  if(-not $wrapped -or $wrapped.ActualWidth -gt $history.ViewportWidth -or $wrapped.Child.ActualHeight -lt 50 -or $history.ScrollableWidth -gt 0){throw 'Long question bubble does not wrap within the output pane'}
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'assistant-wrapped-question.png'))}
  Write-Host 'PASS: composer layout, cog/back navigation, grouped settings, shared workspace grants, saved defaults and speech separation'
 }finally{if($env:WHAS_TEST_REPORTS){if(Test-Path $env:WHAS_GUI_CALLS){Copy-Item $env:WHAS_GUI_CALLS (Join-Path $env:WHAS_TEST_REPORTS 'workflow-calls.log') -Force};$controller.GetType().GetProperty('PresentationStatus',$flags).GetValue($controller)|Set-Content (Join-Path $env:WHAS_TEST_REPORTS 'workflow-status.log');$conversation.Text|Set-Content (Join-Path $env:WHAS_TEST_REPORTS 'workflow-answer.log');$controller.GetType().GetProperty('PresentationOutput',$flags).GetValue($controller).Text|Set-Content (Join-Path $env:WHAS_TEST_REPORTS 'workflow-output.log')};$window.Dispose()}
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
