#Requires -Version 5.1
$ErrorActionPreference='Stop'
if($env:WHAS_SANDBOX_TEST -ne '1'){throw 'Run this test in Windows Sandbox.'}
$repo=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('whas-model-tests-'+[guid]::NewGuid().ToString('N'))
function Pump {
 $frame=New-Object Windows.Threading.DispatcherFrame
 $null=[Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background,[Action]{$frame.Continue=$false})
 [Windows.Threading.Dispatcher]::PushFrame($frame)
}
function Discover {
 $controller.GetType().GetMethod('RefreshSetupModels',$flags).Invoke($controller,@())|Out-Null
 $deadline=[DateTime]::UtcNow.AddSeconds(15)
 do {Pump;Start-Sleep -Milliseconds 25}while($window.Busy -and [DateTime]::UtcNow -lt $deadline)
 if($window.Busy){throw 'Discovery timed out'}
 Pump
}
$originalPath=$env:PATH
try {
 [IO.Directory]::CreateDirectory($fixture)|Out-Null
 Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml,System.Drawing,System.Windows.Forms
 $refs=@('System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Web.Extensions.dll',[Windows.Window].Assembly.Location,[Windows.Media.Visual].Assembly.Location,[Windows.Threading.Dispatcher].Assembly.Location,[System.Xaml.XamlReader].Assembly.Location)
 Add-Type -Path (Join-Path $repo 'scripts/gui-host.cs'),(Join-Path $repo 'scripts/fluent-gui.cs') -ReferencedAssemblies $refs
 Add-Type -TypeDefinition 'public class FakeOllama {public static int Main(string[] args){if(args.Length!=1 || args[0]!="list")return 9;string state=System.Environment.GetEnvironmentVariable("WHAS_MODEL_FIXTURE");if(state=="error"){System.Console.Error.WriteLine("Cannot connect to Ollama");return 1;}System.Console.WriteLine("NAME ID SIZE MODIFIED");if(state=="existing"){System.Console.WriteLine("llama3.2:3b abc123 2GB today");System.Console.WriteLine("qwen3:8b def456 5GB today");}return 0;}}' -OutputAssembly (Join-Path $fixture 'ollama.exe') -OutputType ConsoleApplication
 $env:PATH=$fixture+';'+$originalPath
 $catalog=@(Get-ChildItem (Join-Path $repo 'tts/strategies') -Directory|ForEach-Object{Get-Content (Join-Path $_.FullName 'manifest.json') -Raw|ConvertFrom-Json})|ConvertTo-Json -Depth 12
 $window=New-Object WindowsHybridAgenticStack.FluentWindow($true,(Join-Path $fixture 'unused-setup.exe'),$catalog,(Join-Path $fixture 'not-installed'),[IO.File]::ReadAllText((Join-Path $repo 'scripts/gui-theme.xaml')))
 try {
  $null=(New-Object Windows.Interop.WindowInteropHelper($window)).EnsureHandle()
  $window.Render((Join-Path $fixture 'initial.png'))
  $flags=[Reflection.BindingFlags]'NonPublic,Instance'
  $controller=$window.GetType().GetField('controller',$flags).GetValue($window)
  $models=$controller.GetType().GetField('models',$flags).GetValue($controller)
  $default=$controller.GetType().GetField('defaultModel',$flags).GetValue($controller)
  $local=$controller.GetType().GetField('local',$flags).GetValue($controller)
  $selection=$controller.GetType().GetMethod('Selection',$flags)
  $env:WHAS_MODEL_FIXTURE='empty';Discover
  if(($models.CheckedItems -join ',') -cne 'qwen2.5:1.5b' -or $default.SelectedItem -cne 'qwen2.5:1.5b'){throw 'Empty Ollama did not select only the small starter'}
  $window.SelectPage(1);$window.Render((Join-Path $fixture 'empty.png'))
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'models-empty.png'))}
  $env:WHAS_MODEL_FIXTURE='existing';Discover
  if(($models.CheckedItems -join ',') -cne 'llama3.2:3b' -or $default.SelectedItem -cne 'llama3.2:3b'){throw 'Existing model was not selected instead of downloading starter'}
  $status=$controller.GetType().GetMethod('SetupModelStatus',$flags).Invoke($controller,@('llama3.2:3b'))
  if($status -notlike 'Installed*'){throw 'Existing model is not marked for reuse'}
  $args=$selection.Invoke($controller,@());$index=[Array]::IndexOf($args,'--local-models')
  if($index -lt 0 -or $args[$index+1] -cne 'llama3.2:3b'){throw 'Unselected models were included in installation'}
  if($env:WHAS_TEST_REPORTS){$window.Render((Join-Path $env:WHAS_TEST_REPORTS 'models-existing.png'))}
  $models.SetItemChecked($models.Items.IndexOf('llama3.2:3b'),$false)
  $models.Items.Add('custom:small',$true)|Out-Null;Pump
  Discover
  if(($models.CheckedItems -join ',') -cne 'custom:small'){throw 'Refresh overwrote user choice'}
  $env:WHAS_MODEL_FIXTURE='error';Discover
  if(($models.CheckedItems -join ',') -cne 'custom:small'){throw 'Discovery failure overwrote selection'}
  $notice=$controller.GetType().GetField('SetupModelNotice',$flags).GetValue($controller)
  if($notice -notlike 'Could not check*'){throw 'Discovery failure was treated as an empty library'}
  $models.SetItemChecked($models.Items.IndexOf('custom:small'),$false);Pump
  $rejected=$false;try {$selection.Invoke($controller,@())|Out-Null}catch {if($_.Exception.InnerException.Message -like 'Select at least one model*'){$rejected=$true}else{throw}}
  if(-not $rejected){throw 'Local AI permits no selected model'}
  $local.Checked=$false
  $args=$selection.Invoke($controller,@())
  if($args -contains '--local' -or $args -contains '--local-models' -or $args -contains '--default-local-model'){throw 'Cloud-only selection includes local model downloads'}
  Write-Host 'PASS: empty/existing Ollama discovery, reuse, preserved choices, failure, required local model and cloud-only selection'
 } finally {$window.Dispose()}
} finally {
 $env:PATH=$originalPath;Remove-Item Env:\WHAS_MODEL_FIXTURE -ErrorAction SilentlyContinue
 $absolute=[IO.Path]::GetFullPath($fixture);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $absolute) -notmatch '^whas-model-tests-[a-f0-9]{32}$'){throw 'Unexpected fixture cleanup'}
 if(Test-Path -LiteralPath $absolute){Remove-Item -LiteralPath $absolute -Recurse -Force}
}
