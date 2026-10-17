#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('whas-gui-tests-'+[guid]::NewGuid().ToString('N'))
try {
    [IO.Directory]::CreateDirectory($fixture)|Out-Null
    $library=Join-Path $fixture 'gui-library.dll'
    Add-Type -Path (Join-Path $repo 'scripts/gui-host.cs') -OutputAssembly $library -ReferencedAssemblies System.dll,System.Core.dll,System.Drawing.dll,System.Windows.Forms.dll,System.Web.Extensions.dll
    [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($library))|Out-Null
    $stateRoot=Join-Path $fixture 'state'
    [IO.Directory]::CreateDirectory((Join-Path $stateRoot 'config'))|Out-Null
    if([WindowsHybridAgenticStack.WhasWindow]::IsConfigured($stateRoot)) { throw 'Fresh root was treated as configured' }
    [IO.File]::WriteAllText((Join-Path $stateRoot '.whas-installation.json'),'{"Status":"Interrupted"}')
    if([WindowsHybridAgenticStack.WhasWindow]::IsConfigured($stateRoot)) { throw 'Interrupted installation opened usage' }
    [IO.File]::WriteAllText((Join-Path $stateRoot '.whas-installation.json'),'{"Status":"Installed"}')
    if([WindowsHybridAgenticStack.WhasWindow]::IsConfigured($stateRoot)) { throw 'Missing shared files opened usage' }
    [IO.File]::WriteAllText((Join-Path $stateRoot 'config/defaults.json'),'{}')
    if(-not [WindowsHybridAgenticStack.WhasWindow]::IsConfigured($stateRoot)) { throw 'Installed root failed to open usage' }
    $entries=1..20000|ForEach-Object {'{"Path":"runtime/file-'+$_+'.py","SHA256":"'+('0'*64)+'"}'}
    $largeRecord='{"Status":"Installed","Files":['+($entries -join ',')+']}'
    if($largeRecord.Length -le 2097152){throw 'Large-record fixture does not exceed the default parser limit'}
    [IO.File]::WriteAllText((Join-Path $stateRoot '.whas-installation.json'),$largeRecord)
    if(-not [WindowsHybridAgenticStack.WhasWindow]::IsConfigured($stateRoot)){throw 'Large installed ownership record incorrectly opens setup'}
    [IO.File]::WriteAllText((Join-Path $stateRoot '.whas-installation.json'),$largeRecord.Replace('"Status":"Installed"','"Status":"Interrupted"'))
    if([WindowsHybridAgenticStack.WhasWindow]::IsConfigured($stateRoot)){throw 'Large interrupted ownership record incorrectly opens usage'}
    [IO.File]::WriteAllText((Join-Path $stateRoot '.whas-installation.json'),'invalid')
    if([WindowsHybridAgenticStack.WhasWindow]::IsConfigured($stateRoot)) { throw 'Malformed state opened usage' }
    # Inspect/rebuild controls without showing or activating a desktop window.
    $window=New-Object WindowsHybridAgenticStack.WhasWindow($true,'fixture.exe','[]',$stateRoot)
    try {
        $flags=[Reflection.BindingFlags]'NonPublic,Instance'
        $tabs=$window.GetType().GetField('tabs',$flags).GetValue($window)
        if($tabs.TabPages[0].Text -ne 'Features') { throw 'First-run page was not feature configuration' }
        $route=$window.GetType().GetField('defaultLocation',$flags).GetValue($window)
        if(($route.Items -join ',') -cne 'cloud,local' -or $route.SelectedItem -cne 'cloud'){throw 'Fresh setup must show an explicit Cloud or Local default'}
        $selection=$window.GetType().GetMethod('Selection',$flags)
        # Inspect base-only arguments without invoking the installer.
        foreach($name in @('cloud','local','voice')){$window.GetType().GetField($name,$flags).GetValue($window).Checked=$false}
        foreach($value in @('cloud','local')){
            $route.SelectedItem=$value
            $arguments=$selection.Invoke($window,@())
            $index=[array]::IndexOf($arguments,'--default-location')
            if($index -lt 0 -or $arguments[$index+1] -cne $value){throw 'Setup omitted or changed the displayed default location'}
        }
        $savedConfig=Join-Path $stateRoot 'config/config.json'
        [IO.File]::WriteAllText($savedConfig,'{"interaction":{"location":"local"}}')
        $window.GetType().GetMethod('BuildPages',$flags).Invoke($window,@())|Out-Null
        $route=$window.GetType().GetField('defaultLocation',$flags).GetValue($window)
        if($route.SelectedItem -cne 'local'){throw 'Feature reconfiguration lost the saved Local default'}
        $destination=$window.GetType().GetField('destination',$flags).GetValue($window)
        $destination.Text=Join-Path $fixture 'another-fresh-root'
        if($route.SelectedItem -cne 'cloud'){throw 'New destination retained another installation default'}
        [IO.File]::WriteAllText($savedConfig,'{"interaction":{"location":"cloud"}}')
        $destination.Text=$stateRoot
        if($route.SelectedItem -cne 'cloud'){throw 'Destination change failed to load the saved Cloud default'}
        [IO.File]::WriteAllText($savedConfig,'{"interaction":{"location":"automatic"}}')
        $window.GetType().GetMethod('LoadDefaultLocation',$flags).Invoke($window,@())|Out-Null
        if($route.SelectedIndex -ne -1){throw 'Invalid saved location silently selected a route'}
        $rejected=$false
        try {$null=$selection.Invoke($window,@())}catch{$rejected=$_.Exception.InnerException.Message -like '*Choose Cloud or This PC*'}
        if(-not $rejected){throw 'Setup accepted an unspecified default location'}
        Remove-Item -LiteralPath $savedConfig
        $window.GetType().GetMethod('LoadDefaultLocation',$flags).Invoke($window,@())|Out-Null
        if($window.GetType().GetField('details',$flags).GetValue($window).Visible) { throw 'Diagnostics consume first-run content space' }
        foreach($field in @('defaultModel','defaultEngine')) {
            $control=$window.GetType().GetField($field,$flags).GetValue($window)
            if(-not $control.AccessibleName.StartsWith('Default ')) { throw 'Default selector has no accessible label' }
        }
        $window.RenderPages((Join-Path $fixture 'first-run-pages'))
        $bitmap=New-Object Drawing.Bitmap((Join-Path $fixture 'first-run-pages\00.png'))
        try {
            $colours=New-Object 'Collections.Generic.HashSet[int]'
            for($x=24;$x -lt $bitmap.Width-24;$x+=8) { for($y=50;$y -lt $bitmap.Height-24;$y+=8) { $null=$colours.Add($bitmap.GetPixel($x,$y).ToArgb()) } }
            if($colours.Count -lt 12) { throw 'Offscreen render omitted the controls' }
        } finally { $bitmap.Dispose() }
        $window.GetType().GetField('setup',$flags).SetValue($window,$false)
        $window.GetType().GetMethod('BuildPages',$flags).Invoke($window,@())|Out-Null
        if($tabs.TabPages[0].Text -ne 'Assistant' -or @($tabs.TabPages|Where-Object Text -eq 'Remove WHAS').Count -ne 1) { throw 'Configured view lacks usage or same-window removal' }
        $window.GetType().GetMethod('OpenSetup',$flags).Invoke($window,@())|Out-Null
        if($tabs.SelectedTab.Text -ne 'Features') { throw 'Feature management launched outside the application' }
        $window.GetType().GetField('setup',$flags).SetValue($window,$true)
        $window.GetType().GetMethod('BuildPages',$flags).Invoke($window,@())|Out-Null
        if($tabs.TabPages[0].Text -ne 'Features') { throw 'Removal did not return to first-run configuration' }
    } finally { $window.Dispose() }
    $fake=Join-Path $fixture 'echo.exe'
    Add-Type -TypeDefinition @'
using System; using System.Text; using System.IO;
public static class Echo {
 public static void Main(string[] args) {
  if(args.Length>0 && args[0]=="--child") { File.WriteAllText(args[1],System.Diagnostics.Process.GetCurrentProcess().Id.ToString()); System.Threading.Thread.Sleep(60000); return; }
  if(args.Length>0 && args[0]=="--hold") { System.Threading.Thread.Sleep(500); System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(System.Reflection.Assembly.GetExecutingAssembly().Location,"--child \""+args[1]+"\""){UseShellExecute=false,CreateNoWindow=true}); System.Threading.Thread.Sleep(60000); return; }
  foreach(string arg in args) Console.WriteLine(Convert.ToBase64String(Encoding.UTF8.GetBytes(arg)));
 }
}
'@ -OutputType ConsoleApplication -OutputAssembly $fake
    $expected=@('plain','a b','a"b','x\"y','C:\folder\','','literal & $(nothing); %PATH%','first'+"`n"+'second',[string][char]0x03C0)
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$fake; $start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.RedirectStandardOutput=$true
    $start.Arguments=(@($expected|ForEach-Object { [WindowsHybridAgenticStack.GuiProcess]::Quote($_) })-join ' ')
    $process=[Diagnostics.Process]::Start($start)
    try {
        $result=$process.StandardOutput.ReadToEnd(); $process.WaitForExit()
        $actual=@($result.TrimEnd("`r","`n") -split '\r?\n'|ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) })
        if($actual.Count -ne $expected.Count) { throw 'GUI argument count changed' }
        for($i=0;$i -lt $actual.Count;$i++) { if($actual[$i] -cne $expected[$i]) { throw "GUI argument $i changed" } }
    } finally { $process.Dispose() }
    Add-Type -TypeDefinition @'
using System; using System.IO; using System.Threading;
using WindowsHybridAgenticStack;
public static class GuiLifecycleTest {
 public static void Run(string executable,string pidFile) {
  var done=new ManualResetEvent(false); int exit=-1;
  using(var process=new GuiProcess()) {
   process.Start(executable,new[]{"--hold",pidFile},delegate(string line,bool error){},delegate(int code){exit=code;done.Set();});
   try {
    if(!process.CanCancel) throw new Exception("Owned request cancellation unavailable");
    int child=0;
    for(int i=0;i<100 && child==0;i++) {
     try { if(File.Exists(pidFile)) int.TryParse(File.ReadAllText(pidFile),out child); } catch(IOException) { }
     if(child==0) Thread.Sleep(100);
    }
    if(child<=0) throw new Exception("Owned child did not publish its process ID");
    process.Cancel();
    if(!done.WaitOne(10000) || exit!=130 || process.Running) throw new Exception("Cancellation did not complete");
    try { var remaining=System.Diagnostics.Process.GetProcessById(child); if(!remaining.WaitForExit(5000)) throw new Exception("Cancellation left a child running"); remaining.Dispose(); } catch(ArgumentException) { }
   } finally { if(process.Running) { process.Cancel();process.WaitForStop(10000); } }
  }
  done.Dispose();
 }
}
'@ -ReferencedAssemblies $library
    [GuiLifecycleTest]::Run($fake,(Join-Path $fixture 'child.pid'))
    $maintenance=[WindowsHybridAgenticStack.GuiMaintenance]::CopySetup($fake)
    try {
        if((Get-FileHash -LiteralPath $maintenance).Hash -cne (Get-FileHash -LiteralPath $fake).Hash -or (Split-Path -Parent $maintenance) -eq $fixture -or -not [WindowsHybridAgenticStack.GuiMaintenance]::IsTemporarySetup($maintenance) -or [WindowsHybridAgenticStack.GuiMaintenance]::IsTemporarySetup($fake)) { throw 'Maintenance copy did not preserve the executable outside the installation' }
    } finally { Remove-Item -LiteralPath $maintenance -Force; Remove-Item -LiteralPath (Split-Path -Parent $maintenance) }
    $cleanupCopy=[WindowsHybridAgenticStack.GuiMaintenance]::CopySetup($fake)
    $cleanupCode="[Reflection.Assembly]::Load([IO.File]::ReadAllBytes('"+$library.Replace("'","''")+"'))|Out-Null; [WindowsHybridAgenticStack.GuiMaintenance]::CleanupAfterExit('"+$cleanupCopy.Replace("'","''")+"')"
    $cleanupStart=New-Object Diagnostics.ProcessStartInfo
    $cleanupStart.FileName=Join-Path $PSHOME 'powershell.exe'
    $cleanupStart.Arguments='-NoLogo -NoProfile -ExecutionPolicy Restricted -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cleanupCode))
    $cleanupStart.UseShellExecute=$false; $cleanupStart.CreateNoWindow=$true
    $cleanupProcess=[Diagnostics.Process]::Start($cleanupStart)
    try { if(-not $cleanupProcess.WaitForExit(15000) -or $cleanupProcess.ExitCode) { throw 'Temporary GUI cleanup helper failed' } } finally { $cleanupProcess.Dispose() }
    for($attempt=0;$attempt -lt 100 -and (Test-Path -LiteralPath (Split-Path -Parent $cleanupCopy));$attempt++){Start-Sleep -Milliseconds 100}
    if(Test-Path -LiteralPath (Split-Path -Parent $cleanupCopy)) { throw 'Temporary GUI copy was not cleaned under Restricted policy' }
    $lockedRoot=Join-Path $fixture 'locked-installation'
    [IO.Directory]::CreateDirectory($lockedRoot)|Out-Null
    $lockedExe=Join-Path $lockedRoot 'whas-gui.exe'; Copy-Item -LiteralPath $fake -Destination $lockedExe
    $locked=Start-Process -FilePath $lockedExe -ArgumentList @('--child',(Join-Path $fixture 'locked.pid')) -WindowStyle Hidden -PassThru
    try {
        $rejected=$false
        try { [WindowsHybridAgenticStack.GuiMaintenance]::CheckUnlockedGui($lockedRoot) } catch { $rejected=$_.Exception.Message -like '*Close other WHAS windows*' }
        if(-not $rejected) { throw 'Graphical uninstall accepted an installed application image that is still running' }
    } finally { if(-not $locked.HasExited) {$locked.Kill();$locked.WaitForExit()};$locked.Dispose() }
    $exe=Join-Path $fixture 'whas-gui.exe'
    & (Join-Path $repo 'scripts/build-gui.ps1') -OutputPath $exe
    # Drive the real graphical backend and UI event queue without showing a form.
    $checksWindow=New-Object WindowsHybridAgenticStack.WhasWindow($true,$exe,'[]',$stateRoot)
    try {
        $flags=[Reflection.BindingFlags]'NonPublic,Instance'
        foreach($field in @('cloud','local','voice')) { $checksWindow.GetType().GetField($field,$flags).GetValue($checksWindow).Checked=$false }
        $null=$checksWindow.Handle
        $checksWindow.GetType().GetMethod('PrepareRender',[Reflection.BindingFlags]'NonPublic,Static').Invoke($null,[object[]]@($checksWindow.PSObject.BaseObject))|Out-Null
        $checkTabs=$checksWindow.GetType().GetField('tabs',$flags).GetValue($checksWindow)
        $grid=$checksWindow.GetType().GetField('checkGrid',$flags).GetValue($checksWindow)
        $checkTabs.SelectedIndex=2
        for($attempt=0;$attempt -lt 2;$attempt++) {
            if($attempt -gt 0) {$checksWindow.GetType().GetMethod('CheckPrerequisites',$flags).Invoke($checksWindow,@())|Out-Null}
            $deadline=[DateTime]::UtcNow.AddSeconds(60)
            do {
                [Windows.Forms.Application]::DoEvents()
                $current=$checksWindow.GetType().GetField('operation',$flags).GetValue($checksWindow)
                $passed=$checksWindow.GetType().GetField('checkPassed',$flags).GetValue($checksWindow)
                if($current -and -not $current.Running -and $passed) {break}
                Start-Sleep -Milliseconds 50
            } while([DateTime]::UtcNow -lt $deadline)
            if(-not $passed -or $grid.Rows.Count -lt 2) {
                $diagnostic=$checksWindow.GetType().GetField('output',$flags).GetValue($checksWindow).Text
                $state=$checksWindow.GetType().GetField('status',$flags).GetValue($checksWindow).Text
                throw "Initial/repeated graphical prerequisite check failed: $state; rows=$($grid.Rows.Count); $diagnostic"
            }
        }
        Write-Host 'PASS: initial and repeated real WinExe checks populate the GUI grid without a console'
    } finally { $checksWindow.Dispose() }
    $render=Join-Path $fixture 'client.png'
    $process=Start-Process -FilePath $exe -ArgumentList @('--render',$render) -WindowStyle Hidden -PassThru
    try { if(-not $process.WaitForExit(20000)) { $process.Kill(); throw 'GUI render timed out' }; if($process.ExitCode) { throw 'GUI render failed' } } finally { $process.Dispose() }
    if(-not (Test-Path -LiteralPath $render) -or (Get-Item -LiteralPath $render).Length -lt 1000) { throw 'GUI did not render' }
    Write-Host 'PASS: GUI arguments, owned process-tree cancellation, executable build and background rendering'
} finally {
    $absolute=[IO.Path]::GetFullPath($fixture)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not $absolute.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $absolute) -notmatch '^whas-gui-tests-[a-f0-9]{32}$') { throw 'Unexpected fixture cleanup' }
    if(Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
