#Requires -Version 5.1
<#
.SYNOPSIS
    Build the standalone read-only setup prototype with the Windows compiler.
.DESCRIPTION
    Packages only checked-in application scripts and defaults. No user config,
    credentials, profiles or environment values are embedded in the executable.
#>
[CmdletBinding()]
param([string]$OutputPath, [switch]$Force)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess) {
    throw 'Build using 64-bit Windows PowerShell 5.1.'
}
$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutputPath) { $OutputPath = Join-Path $repo 'dist\whas-setup-preview.exe' }
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if ([IO.Path]::GetExtension($OutputPath) -ine '.exe') { throw 'OutputPath must name an .exe file.' }
if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) { throw 'Output already exists. Use -Force to replace the build artifact.' }
$assets = [ordered]@{
    Configuration = 'scripts\configuration.ps1'
    Preview = 'scripts\setup-preview.ps1'
    Prerequisites = 'scripts\check-prerequisites.ps1'
    Defaults = 'config\defaults.json'
}
$payload = New-Object Text.StringBuilder
$null = $payload.AppendLine('using System; using System.Text; namespace WindowsHybridAgenticStack { internal static class SetupPayload {')
foreach ($name in $assets.Keys) {
    $content = [IO.File]::ReadAllText((Join-Path $repo $assets[$name]), [Text.Encoding]::UTF8)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))
    $null = $payload.AppendLine(('internal static string {0} {{ get {{ return Encoding.UTF8.GetString(Convert.FromBase64String("{1}")); }} }}' -f $name,$encoded))
}
$null = $payload.AppendLine('} }')
$build = Join-Path ([IO.Path]::GetTempPath()) ('whas-setup-build-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($build) | Out-Null
$generated = Join-Path $build 'payload.cs'
$compiled = Join-Path $build 'setup.exe'
$compiler = $null
$parameters = New-Object CodeDom.Compiler.CompilerParameters
try {
    [IO.File]::WriteAllText($generated, $payload.ToString(), (New-Object Text.UTF8Encoding($false)))
    $parameters.GenerateExecutable = $true
    $parameters.OutputAssembly = $compiled
    $parameters.CompilerOptions = '/platform:x64 /main:WindowsHybridAgenticStack.SetupHost'
    $parameters.TempFiles = New-Object CodeDom.Compiler.TempFileCollection($build, $false)
    $null = $parameters.ReferencedAssemblies.Add('System.dll')
    $null = $parameters.ReferencedAssemblies.Add('System.Core.dll')
    $null = $parameters.ReferencedAssemblies.Add([Management.Automation.PSObject].Assembly.Location)
    $compiler = New-Object Microsoft.CSharp.CSharpCodeProvider
    $result = $compiler.CompileAssemblyFromFile($parameters, [string[]]@(
        (Join-Path $PSScriptRoot 'command-host.cs'), (Join-Path $PSScriptRoot 'setup-host.cs'), $generated))
    if ($result.Errors.HasErrors) { throw (($result.Errors | ForEach-Object ToString) -join [Environment]::NewLine) }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $OutputPath)) | Out-Null
    Move-Item -LiteralPath $compiled -Destination $OutputPath -Force:$Force
    Write-Host "Built read-only setup prototype: $OutputPath"
}
finally {
    if ($null -ne $compiler) { $compiler.Dispose() }
    $parameters.TempFiles.Delete()
    foreach ($path in @($generated,$compiled)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    if (@(Get-ChildItem -LiteralPath $build -Force).Count -eq 0) { Remove-Item -LiteralPath $build }
}
