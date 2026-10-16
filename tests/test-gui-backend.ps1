#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('whas-gui-tests-'+[guid]::NewGuid().ToString('N'))
try {
    [IO.Directory]::CreateDirectory($fixture)|Out-Null
    $library=Join-Path $fixture 'gui-library.dll'
    Add-Type -Path (Join-Path $repo 'scripts/gui-host.cs') -OutputAssembly $library -ReferencedAssemblies System.dll,System.Core.dll,System.Drawing.dll,System.Windows.Forms.dll,System.Web.Extensions.dll
    [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($library))|Out-Null
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
    for(int i=0;i<100 && !File.Exists(pidFile);i++) Thread.Sleep(100);
    if(!File.Exists(pidFile)) throw new Exception("Owned child did not start");
    int child=int.Parse(File.ReadAllText(pidFile));
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
