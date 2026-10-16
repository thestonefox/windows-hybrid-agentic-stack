#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess) { throw 'Build using 64-bit Windows PowerShell 5.1.' }
if (-not $OutputPath) { $OutputPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'dist/whas-gui.exe' }
$OutputPath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) { throw 'GUI output exists; choose a new path.' }
[IO.Directory]::CreateDirectory((Split-Path -Parent $OutputPath))|Out-Null
$compiler=New-Object Microsoft.CSharp.CSharpCodeProvider
$options=New-Object CodeDom.Compiler.CompilerParameters
$options.GenerateExecutable=$true; $options.OutputAssembly=$OutputPath
$options.CompilerOptions='/target:winexe /platform:x64 /main:WindowsHybridAgenticStack.GuiHost'
foreach($assembly in @('System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Web.Extensions.dll')) { $null=$options.ReferencedAssemblies.Add($assembly) }
try {
    $result=$compiler.CompileAssemblyFromFile($options,[string[]]@((Join-Path $PSScriptRoot 'gui-host.cs')))
    if($result.Errors.HasErrors) { throw (($result.Errors|ForEach-Object ToString)-join "`n") }
    Write-Host "Built graphical client: $OutputPath"
} finally { $compiler.Dispose(); $options.TempFiles.Delete() }
