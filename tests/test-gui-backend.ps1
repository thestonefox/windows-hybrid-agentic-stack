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
    [IO.File]::WriteAllText((Join-Path $stateRoot '.whas-installation.json'),'invalid')
    if([WindowsHybridAgenticStack.WhasWindow]::IsConfigured($stateRoot)) { throw 'Malformed state opened usage' }
    # Inspect/rebuild controls without showing or activating a desktop window.
    $window=New-Object WindowsHybridAgenticStack.WhasWindow($true,'fixture.exe','[]',$stateRoot)
    try {
        $flags=[Reflection.BindingFlags]'NonPublic,Instance'
        $tabs=$window.GetType().GetField('tabs',$flags).GetValue($window)
        if($tabs.TabPages[0].Text -ne 'Features') { throw 'First-run page was not feature configuration' }
        $window.GetType().GetField('setup',$flags).SetValue($window,$false)
        $window.GetType().GetMethod('BuildPages',$flags).Invoke($window,@())|Out-Null
        if($tabs.TabPages[0].Text -ne 'Ask & chat' -or @($tabs.TabPages|Where-Object Text -eq 'Remove WHAS').Count -ne 1) { throw 'Configured view lacks usage or same-window removal' }
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
