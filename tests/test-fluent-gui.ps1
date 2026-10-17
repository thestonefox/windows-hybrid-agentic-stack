#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('whas-fluent-tests-'+[guid]::NewGuid().ToString('N'))
function Children($node) {for($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($node);$i++) {$child=[Windows.Media.VisualTreeHelper]::GetChild($node,$i);$child;Children $child}}
function Pump {
 $frame=New-Object Windows.Threading.DispatcherFrame
 $null=[Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background,[Action]{$frame.Continue=$false})
 [Windows.Threading.Dispatcher]::PushFrame($frame)
}
try {
 [IO.Directory]::CreateDirectory($fixture)|Out-Null
 Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml,System.Drawing,System.Windows.Forms
 $refs=@('System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Web.Extensions.dll',[Windows.Window].Assembly.Location,[Windows.Media.Visual].Assembly.Location,[Windows.Threading.Dispatcher].Assembly.Location,[System.Xaml.XamlReader].Assembly.Location)
 Add-Type -Path (Join-Path $repo 'scripts/gui-host.cs'),(Join-Path $repo 'scripts/fluent-gui.cs') -ReferencedAssemblies $refs
 $catalog=@(Get-ChildItem (Join-Path $repo 'tts/strategies') -Directory|ForEach-Object{Get-Content (Join-Path $_.FullName 'manifest.json') -Raw|ConvertFrom-Json})|ConvertTo-Json -Depth 12
 $exe=Join-Path $fixture 'whas-gui.exe'
 & (Join-Path $repo 'scripts/build-gui.ps1') -OutputPath $exe
 $theme=[IO.File]::ReadAllText((Join-Path $repo 'scripts/gui-theme.xaml'))
 $window=New-Object WindowsHybridAgenticStack.FluentWindow($true,$exe,$catalog,(Join-Path $fixture 'not-installed'),$theme)
 $flags=[Reflection.BindingFlags]'NonPublic,Instance'
 try {
  $null=(New-Object Windows.Interop.WindowInteropHelper($window)).EnsureHandle()
  $window.RenderPages((Join-Path $fixture 'pages'))
  $controller=$window.GetType().GetField('controller',$flags).GetValue($window)
  $nav=$window.GetType().GetField('navigation',$flags).GetValue($window)
  if(@($nav.Items|Where-Object Content -eq 'Remove WHAS').Count){throw 'Fresh installer shows removal navigation'}
  $destination=$controller.GetType().GetField('destination',$flags).GetValue($controller)
  [IO.Directory]::CreateDirectory($destination.Text)|Out-Null
  $record=Join-Path $destination.Text '.whas-installation.json'
  [IO.File]::WriteAllText($record,'{"Status":"Interrupted"}')
  $window.Render((Join-Path $fixture 'recovery.png'))
  if(-not @($nav.Items|Where-Object Content -eq 'Remove WHAS').Count){throw 'Interrupted installation lost its recovery removal route'}
  [IO.File]::WriteAllText($record,'{"Status":"Uninstalled"}')
  $window.Render((Join-Path $fixture 'removed-target.png'))
  if(@($nav.Items|Where-Object Content -eq 'Remove WHAS').Count){throw 'Completed uninstall still exposes removal navigation'}
  $controller.GetType().GetMethod('RefreshFeatureStatus',$flags).Invoke($controller,@())|Out-Null
  if($controller.GetType().GetField('cloud',$flags).GetValue($controller).AccessibleDescription -ne 'Not installed'){throw 'Completed uninstall is mislabeled incomplete'}
  $footerAction=$window.GetType().GetField('setupNext',$flags).GetValue($window)
  $actionWidth=$null;$logX=$null
  foreach($case in @(@(0,'Choose Models & Engines'),@(1,'Check Prerequisites'),@(2,'Go to Apply Features'),@(3,'Apply selected features'))) {
   $window.SelectPage($case[0]);$window.Render((Join-Path $fixture 'footer.png'))
   if($footerAction.Content -cne $case[1] -or $footerAction.Visibility -ne 'Visible'){throw 'Installer footer action has wrong label or is hidden'}
   $logToggle=$window.GetType().GetField('logToggle',$flags).GetValue($window)
   $currentLogX=$logToggle.TransformToAncestor($window.Content).Transform((New-Object Windows.Point(0,0))).X
   if($null -eq $actionWidth){$actionWidth=$footerAction.ActualWidth;$logX=$currentLogX}
   if([Math]::Abs($footerAction.ActualWidth-$actionWidth) -gt 0.1 -or [Math]::Abs($currentLogX-$logX) -gt 0.1){throw 'Installer button width or activity-log position changes between steps'}
   $pageHost=$window.GetType().GetField('pageHost',$flags).GetValue($window)
   $scroll=$pageHost.Content;$before=$footerAction.TransformToAncestor($window.Content).Transform((New-Object Windows.Point(0,0)))
   $scroll.ScrollToEnd();Pump;$window.Render((Join-Path $fixture 'footer-scrolled.png'))
   $after=$footerAction.TransformToAncestor($window.Content).Transform((New-Object Windows.Point(0,0)))
   if($before.Y -ne $after.Y -or $after.Y+$footerAction.ActualHeight -gt $window.Content.RenderSize.Height){throw 'Installer action scrolls away with the page'}
  }
  $window.SelectPage(0)
  $devices=$controller.GetType().GetField('setupDevices',$flags).GetValue($controller)
  $chatter=$devices['chatterbox-turbo'];$piperDevice=$devices['piper-tts'];$f5Device=$devices['f5-tts']
  if(($chatter.Items -join ',') -ne 'cpu,auto' -or ($f5Device.Items -join ',') -ne 'cpu,auto' -or ($piperDevice.Items -join ',') -ne 'cpu'){throw 'Device choices do not follow each engine capability'}
  $engines=$controller.GetType().GetField('engines',$flags).GetValue($controller)
  $ids=$controller.GetType().GetField('engineIds',$flags).GetValue($controller)
  $chatter.SelectedItem='auto';$engines.SetItemChecked($ids.IndexOf('piper-tts'),$true);Pump
  if($chatter.SelectedItem -ne 'auto' -or $piperDevice.SelectedItem -ne 'cpu'){throw 'Adding Piper changed the Chatterbox Prefer GPU choice'}
  $window.SelectPage(1);$window.Render((Join-Path $fixture 'mixed-devices.png'))
  $selection=$controller.GetType().GetMethod('Selection',$flags).Invoke($controller,@())
  $deviceIndex=[Array]::IndexOf($selection,'--tts-devices')
  if($deviceIndex -lt 0 -or $selection[$deviceIndex+1] -ne 'chatterbox-turbo=auto,piper-tts=cpu'){throw 'Mixed device choices were not forwarded independently'}
  $visibleDevices=@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.ComboBox] -and [Windows.Automation.AutomationProperties]::GetName($_) -in @('Chatterbox Turbo device','F5-TTS device') -and ([Windows.Media.VisualTreeHelper]::GetParent($_)).Visibility -eq [Windows.Visibility]::Visible})
  $device=$visibleDevices[0]
  if(($device.Items|ForEach-Object {$_.ToString()}) -join ',' -ne 'CPU,Prefer GPU'){throw 'UI exposes Automatic or strict GPU instead of CPU and Prefer GPU'}
  $devicePanel=[Windows.Media.VisualTreeHelper]::GetParent($device);$engineGroup=[Windows.Media.VisualTreeHelper]::GetParent($devicePanel)
  if($engineGroup.Children[0].Children[0].Content -ne 'Chatterbox Turbo' -or $engineGroup.Children[1] -ne $devicePanel){throw 'Device choice is not directly beneath its engine checkbox'}
  $piperCheck=Children $window.Content|Where-Object {$_ -is [Windows.Controls.CheckBox] -and $_.Content -eq 'Piper TTS'}|Select-Object -First 1
  $piperGroup=[Windows.Media.VisualTreeHelper]::GetParent([Windows.Media.VisualTreeHelper]::GetParent($piperCheck))
  if($piperGroup.Children.Count -ne 1){throw 'Piper displays unnecessary device controls or text'}
  if($visibleDevices.Count -ne 1){throw 'Piper has an unnecessary hardware dropdown, or Chatterbox has no dropdown'}
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'mixed-devices.png'))}
  $engines.SetItemChecked($ids.IndexOf('piper-tts'),$false);$chatter.SelectedItem='auto';Pump
  $cancel=$window.GetType().GetField('cancel',$flags).GetValue($window)
  if($cancel.Visibility -ne [Windows.Visibility]::Collapsed){throw 'Idle cancellation occupies footer space'}
  $window.SelectPage(0);$window.Render((Join-Path $fixture 'features.png'))
  $shell=$window.Content
  $route=Children $shell|Where-Object {$_ -is [Windows.Controls.ComboBox] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Default processing'}|Select-Object -First 1
  $routeValues=($route.Items|ForEach-Object {$_.Value}) -join ','
  if(-not $route -or $routeValues -cne 'cloud,local' -or $route.SelectedItem.Value -cne 'cloud'){throw 'Visible setup location is not an explicit Cloud/Local choice'}
  $route.SelectedIndex=1
  if($controller.GetType().GetField('defaultLocation',$flags).GetValue($controller).SelectedItem -cne 'local'){throw 'Visible Local selection did not reach setup'}
  $switch=Children $shell|Where-Object {$_ -is [Windows.Controls.CheckBox] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Cloud AI'}|Select-Object -First 1
  if(-not $switch -or -not $switch.IsChecked){throw 'Feature card has no accessible state binding'}
  $switch.IsChecked=$false
  if($controller.GetType().GetField('cloud',$flags).GetValue($controller).Checked){throw 'Feature switch did not update selection'}
  $window.SelectPage(1);$window.Render((Join-Path $fixture 'models.png'))
  $defaults=@(Children $shell|Where-Object {$_ -is [Windows.Controls.ComboBox] -and [Windows.Automation.AutomationProperties]::GetName($_).StartsWith('Default ')})
  if($defaults.Count -ne 2 -or @($defaults|Where-Object {$null -eq $_.SelectedItem}).Count){throw 'Labelled model/engine defaults are missing or blank'}
  $infos=@(Children $shell|Where-Object {$_ -is [Windows.Controls.Button] -and [Windows.Automation.AutomationProperties]::GetName($_).StartsWith('Licence information for ')})
  if($infos.Count -ne 5){throw 'Each model and engine must have its own licence information action'}
  $f5=$infos|Where-Object {[Windows.Automation.AutomationProperties]::GetName($_) -eq 'Licence information for F5-TTS'}
  if($f5.ToolTip.Content.Text -notmatch 'CC-BY-NC-4.0' -or $f5.ToolTip.Content.Text -notmatch 'Engine / package:' -or $f5.ToolTip.Content.Text -notmatch 'Downloaded model / assets:'){throw 'F5 licence scopes or noncommercial weights terms are missing'}
  $modelInfo=$infos|Where-Object {[Windows.Automation.AutomationProperties]::GetName($_) -eq 'Licence information for qwen3:8b'}
  if($modelInfo.ToolTip.Content.Text -notmatch 'Model weights: Apache-2.0'){throw 'Known model licence metadata is missing'}
  $focus=New-Object Windows.Input.KeyboardFocusChangedEventArgs([Windows.Input.Keyboard]::PrimaryDevice,0,$null,$modelInfo)
  $focus.RoutedEvent=[Windows.UIElement]::GotKeyboardFocusEvent;$modelInfo.RaiseEvent($focus)
  if(-not $modelInfo.ToolTip.IsOpen){throw 'Licence tooltip did not open for keyboard focus'}
  $blur=New-Object Windows.Input.KeyboardFocusChangedEventArgs([Windows.Input.Keyboard]::PrimaryDevice,0,$modelInfo,$null)
  $blur.RoutedEvent=[Windows.UIElement]::LostKeyboardFocusEvent;$modelInfo.RaiseEvent($blur)
  if($modelInfo.ToolTip.IsOpen){throw 'Licence tooltip remained open after keyboard focus left'}
  $modelSource=$controller.GetType().GetField('models',$flags).GetValue($controller)
  $before=$modelSource.GetItemChecked(0)
  $dialogChecked=New-Object Windows.Threading.DispatcherTimer
  $dialogChecked.Interval=[TimeSpan]::FromMilliseconds(100)
  $dialogChecked.Add_Tick({
   $dialogChecked.Stop()
   $dialog=@($window.OwnedWindows)|Where-Object {$_.Title -like '*licence'}|Select-Object -First 1
   if($dialog){$script:licenceDialogLinks=@(Children $dialog|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -is [Windows.Controls.TextBlock]}).Count;$dialog.Close()}
  })
  $dialogChecked.Start()
  try {$modelInfo.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))}finally{$dialogChecked.Stop()}
  if($script:licenceDialogLinks -ne 2 -or $modelSource.GetItemChecked(0) -ne $before){throw 'Licence details changed selection or omitted source links'}
  $null=$modelSource.Items.Add('custom-model:latest',$false)
  $window.Render((Join-Path $fixture 'custom-model.png'))
  $unknown=Children $shell|Where-Object {$_ -is [Windows.Controls.Button] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Licence information for custom-model:latest'}|Select-Object -First 1
  if(-not $unknown -or $unknown.ToolTip.Content.Text -notmatch 'Licence not verified'){throw 'Custom model incorrectly inherits a known licence'}
  if(@(Children $shell|Where-Object {$_ -is [Windows.Controls.TextBlock] -and $_.Text.StartsWith('Licence:')}).Count){throw 'Loose selected-engine licence line returned'}
  $bitmap=New-Object Drawing.Bitmap((Join-Path $fixture 'features.png'))
  try {$colours=New-Object 'Collections.Generic.HashSet[int]';for($x=24;$x -lt $bitmap.Width;$x+=8){for($y=24;$y -lt $bitmap.Height;$y+=8){$null=$colours.Add($bitmap.GetPixel($x,$y).ToArgb())}};if($colours.Count -lt 20){throw 'Fluent render omitted content'}}finally{$bitmap.Dispose()}
 }finally{$window.Dispose()}
 $window=New-Object WindowsHybridAgenticStack.FluentWindow($true,$exe,$catalog,(Join-Path $fixture 'not-installed'),$theme)
 try {
  $controller=$window.GetType().GetField('controller',$flags).GetValue($window)
  foreach($field in @('cloud','local','voice')){$controller.GetType().GetField($field,$flags).GetValue($controller).Checked=$false}
  $window.SelectPage(2)
  for($attempt=0;$attempt -lt 2;$attempt++) {
   if($attempt -gt 0) {
    $window.Render((Join-Path $fixture 'before-retry.png'))
    $again=Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Check Again'}|Select-Object -First 1
    if(-not $again -or -not $again.IsEnabled){throw 'Check again action is unavailable'}
    $again.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
   }
   $deadline=[DateTime]::UtcNow.AddSeconds(60)
   do {Pump;Start-Sleep -Milliseconds 30;$passed=$controller.GetType().GetField('checkPassed',$flags).GetValue($controller);if($passed -and -not $window.Busy){break}}while([DateTime]::UtcNow -lt $deadline)
   if(-not $passed){throw 'WPF initial/repeated prerequisite action did not pass'}
   Pump
  }
  $checkAgain=Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Check Again'}|Select-Object -First 1
  $window.SelectPage(3);$window.Render((Join-Path $fixture 'before-review.png'))
  $deadline=[DateTime]::UtcNow.AddSeconds(45);do {Pump;Start-Sleep -Milliseconds 30}while($window.Busy -and [DateTime]::UtcNow -lt $deadline)
  $window.Render((Join-Path $fixture 'review.png'))
  $apply=$window.GetType().GetField('setupNext',$flags).GetValue($window)
  if(-not $apply.IsEnabled -or -not $controller.GetType().GetProperty('SetupReviewed',$flags).GetValue($controller)){throw 'Reviewed ready selection cannot be applied'}
  $review=Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Check Again'}|Select-Object -First 1
  if(-not $review -or [Windows.Controls.Grid]::GetColumn($review) -ne 1 -or -not [Object]::ReferenceEquals($review.Style,$checkAgain.Style) -or [Math]::Abs($review.ActualWidth-$checkAgain.ActualWidth) -gt 0.1){throw 'Review again does not match Check again styling and header placement'}
  $review.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
  $window.Render((Join-Path $fixture 'review-refreshing.png'))
  if($apply.IsEnabled){throw 'Apply remains enabled during review refresh'}
  $deadline=[DateTime]::UtcNow.AddSeconds(45);do {Pump;Start-Sleep -Milliseconds 30}while($window.Busy -and [DateTime]::UtcNow -lt $deadline)
  $window.Render((Join-Path $fixture 'review-refreshed.png'))
  if(-not $apply.IsEnabled){throw 'Review again did not restore the ready plan'}
  if($window.GetType().GetField('logPanel',$flags).GetValue($window).Visibility -ne 'Collapsed'){throw 'Review selection opens the diagnostic log'}
  if(-not @(Children $window.Content|Where-Object {$_ -is [Windows.Controls.TextBlock] -and $_.Text -eq 'Installation folder'}).Count){throw 'Reviewed plan is not displayed on the Apply features page'}
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'setup-review.png'))}
  $controller.GetType().GetField('cloud',$flags).GetValue($controller).Checked=$true
  $window.Render((Join-Path $fixture 'review-invalid.png'))
  if($apply.IsEnabled){throw 'Changed selection leaves Apply enabled'}
  $controller.GetType().GetField('cloud',$flags).GetValue($controller).Checked=$false
  $window.SelectPage(2)
  $grid=$controller.GetType().GetField('checkGrid',$flags).GetValue($controller)
  if($grid.Rows.Count -lt 2){throw 'Prerequisite results were lost'}
  $null=$grid.Rows.Add('OpenCode','Yes','FAIL','Install OpenCode to enable cloud and local requests.')
  $null=$grid.Rows.Add('Ollama','Yes','FAIL','Ollama is missing.')
  $null=$grid.Rows.Add('Python 3.11','Yes','FAIL','Install 64-bit Python 3.11 with its Windows Python launcher.')
  $null=$grid.Rows.Add('Visual C++ x64','Yes','FAIL','Install the Visual C++ x64 runtime.')
  $window.Render((Join-Path $fixture 'checks.png'))
  $rows=$window.GetType().GetField('checkRows',$flags).GetValue($window)
  if(-not [double]::IsNaN($rows.Height) -or $rows.Children.Count -ne $grid.Rows.Count){throw 'Prerequisite rows are constrained or missing'}
  if(@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.DataGrid]}).Count){throw 'Nested prerequisite grid returned'}
  $downloads=@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Open download page ↗'})
  if($downloads.Count -ne 4){throw 'Missing-component actions are not attached to Python, Ollama, OpenCode and Visual C++ rows'}
  $wingetButtons=@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Install with WinGet'})
  if($wingetButtons.Count -ne 4){throw 'Missing WinGet actions'}
  foreach($button in $wingetButtons){if($button.IsEnabled){throw 'WinGet action enabled without WinGet'}}
  $packageMethod=$controller.GetType().GetMethod('PrerequisiteInstallArguments',[Reflection.BindingFlags]'NonPublic,Static')
  foreach($pair in @(@('Python 3.11','Python.Python.3.11'),@('Visual C++ x64','Microsoft.VCRedist.2015+.x64'),@('OpenCode','SST.opencode'),@('Ollama','Ollama.Ollama'))) {
   $actual=$packageMethod.Invoke($null,@([string]$pair[0]))
   if(($actual -join '|') -cne ('install|--id|'+$pair[1]+'|--exact|--source|winget|--accept-source-agreements|--accept-package-agreements|--disable-interactivity')){throw 'Incorrect WinGet arguments'}
  }
  $links=$window.GetType().GetMethod('InstallLink',[Reflection.BindingFlags]'NonPublic,Static')
  foreach($pair in @(@('Python 3.11','https://www.python.org/'),@('Ollama','https://ollama.com/'),@('OpenCode','https://opencode.ai/'),@('Visual C++ x64','https://learn.microsoft.com/'))) {
   $link=$links.Invoke($null,@([string]$pair[0]));if(-not $link.StartsWith($pair[1])){throw 'Prerequisite install action points to the wrong publisher'}
  }
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'missing-prerequisites.png'))}
  $fakeDir=Join-Path $fixture 'fake-winget';[IO.Directory]::CreateDirectory($fakeDir)|Out-Null
  $capture=Join-Path $fakeDir 'arguments.txt';$env:WHAS_WINGET_CAPTURE=$capture
  Add-Type -TypeDefinition 'public class FakeWinGet {public static int Main(string[] args){System.IO.File.WriteAllLines(System.Environment.GetEnvironmentVariable("WHAS_WINGET_CAPTURE"),args);System.Console.WriteLine("Simulated prerequisite installation");return 0;}}' -OutputAssembly (Join-Path $fakeDir 'winget.exe') -OutputType ConsoleApplication
  $originalPath=$env:PATH
  try {
   $env:PATH=$fakeDir+';'+$originalPath
   $controller.GetType().GetMethod('InstallPrerequisite',$flags).Invoke($controller,@('Ollama'))|Out-Null
   $deadline=[DateTime]::UtcNow.AddSeconds(40)
   do {Pump;Start-Sleep -Milliseconds 50} while($window.Busy -and [DateTime]::UtcNow -lt $deadline)
   if($window.Busy){throw 'WinGet/recheck did not complete'}
   if(([IO.File]::ReadAllLines($capture) -join '|') -cne 'install|--id|Ollama.Ollama|--exact|--source|winget|--accept-source-agreements|--accept-package-agreements|--disable-interactivity'){throw 'WinGet process arguments changed'}
   if($grid.Rows.Count -eq 0 -or @($grid.Rows|Where-Object {$_.Cells[2].Value -eq 'FAIL'}).Count){throw 'Successful installation did not rerun base prerequisites'}
  } finally {$env:PATH=$originalPath;Remove-Item Env:\WHAS_WINGET_CAPTURE -ErrorAction SilentlyContinue}
  $controller.GetType().GetField('setup',$flags).SetValue($controller,$false)
  $controller.GetType().GetMethod('BuildPages',$flags).Invoke($controller,@())|Out-Null
  $window.RenderPages((Join-Path $fixture 'configured-pages'))
  $navigation=$window.GetType().GetField('navigation',$flags).GetValue($window)
  if($navigation.Items[0].Content -ne 'Assistant'){throw 'Installed presenter did not rebuild into usage'}
  if($navigation.Items.Count -ne 2 -or $navigation.Items[1].Content -ne 'Configuration'){throw 'Installed navigation exposes disjoint maintenance pages'}
  $window.SelectPage(0);$window.Render((Join-Path $fixture 'assistant.png'))
  $inputs=@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.TextBox] -and [Windows.Automation.AutomationProperties]::GetName($_) -in @('Your message','Responses')})
  if($inputs.Count -ne 1 -or [Windows.Automation.AutomationProperties]::GetName($inputs[0]) -ne 'Your message'){throw 'Assistant has extra editable message inputs'}
  $response=@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.Border] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Responses'})
  if($response.Count -ne 1 -or $response[0].Focusable -or $response[0].Child.Focusable){throw 'Output pane takes keyboard focus'}
  $greeting=Children $response[0]|Where-Object {$_ -is [Windows.Controls.TextBox] -and [Windows.Automation.AutomationProperties]::GetName($_) -eq 'Greeting'}|Select-Object -First 1
  $greeting.SelectAll();if(-not $greeting.IsReadOnly -or $greeting.SelectedText -cne 'Hi, how can I help?' -or $greeting.BorderThickness.Left -ne 0){throw 'Output greeting is not selectable plain read-only text'}
  if(@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.ComboBox]}).Count -ne 2){throw 'Advanced configuration leaked onto Assistant'}
  $window.SelectPage($controller.GetType().GetField('featureTab',$flags).GetValue($controller));$window.Render((Join-Path $fixture 'configured-features.png'))
  $buttons=@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button]}|ForEach-Object Content)
  if($buttons -contains 'Review & apply' -or $buttons -contains 'Continue' -or $buttons -contains 'Check prerequisites'){throw 'Installed configuration still exposes installation steps'}
  if($buttons -notcontains 'Repair shared app files…' -or $buttons -notcontains 'Add…'){throw 'Installed maintenance actions are missing'}
  $controller.GetType().GetMethod('BeginMaintenance',$flags).Invoke($controller,@('core'))|Out-Null
  $window.SelectPage($controller.GetType().GetField('featureTab',$flags).GetValue($controller))
  $window.Render((Join-Path $fixture 'maintenance.png'))
  $buttons=@(Children $window.Content|Where-Object {$_ -is [Windows.Controls.Button]})
  foreach($label in @('Check readiness','Review changes','Apply changes…')){if(-not ($buttons|Where-Object Content -eq $label)){throw "Missing in-place maintenance action: $label"}}
  if(($buttons|Where-Object Content -eq 'Apply changes…').IsEnabled){throw 'Maintenance can apply without check and review'}
  $controller.GetType().GetMethod('LoadPresentationSettings',$flags).Invoke($controller,@())|Out-Null
  $controller.GetType().GetField('setup',$flags).SetValue($controller,$true)
  $controller.GetType().GetMethod('BuildPages',$flags).Invoke($controller,@())|Out-Null
  if($navigation.Items[0].Content -ne 'Features'){throw 'Presenter did not return to feature setup'}
  Write-Host 'PASS: WPF feature bindings, populated defaults, rendering, real initial/repeated checks and inline missing-component actions'
 }finally{$window.Dispose()}
}finally {
 $absolute=[IO.Path]::GetFullPath($fixture);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $absolute) -notmatch '^whas-fluent-tests-[a-f0-9]{32}$'){throw 'Unexpected Fluent fixture cleanup'}
 if(Test-Path -LiteralPath $absolute){Remove-Item -LiteralPath $absolute -Recurse -Force}
}
