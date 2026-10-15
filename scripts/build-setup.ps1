#Requires -Version 5.1
<#
.SYNOPSIS
    Build standalone setup with the Windows compiler and bundled application assets.
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
if (-not $OutputPath) { $OutputPath = Join-Path $repo 'dist\whas-setup.exe' }
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if ([IO.Path]::GetExtension($OutputPath) -ine '.exe') { throw 'OutputPath must name an .exe file.' }
if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) { throw 'Output already exists. Use -Force to replace the build artifact.' }
$properties = [ordered]@{
    Configuration = 'scripts\configuration.ps1'
    Preview = 'scripts\setup-preview.ps1'
    Prerequisites = 'scripts\check-prerequisites.ps1'
    Defaults = 'config\defaults.json'
    StrategyHelper = 'tts\strategy-management.ps1'
}
. (Join-Path $repo 'tts/strategy-management.ps1')
$packages = @(Get-TtsStrategies -Root $repo)
$catalog = ConvertTo-Json -InputObject @($packages | ForEach-Object { $_.Manifest }) -Depth 12 -Compress
$payload = New-Object Text.StringBuilder
$null = $payload.AppendLine('using System; using System.Text; using System.Collections.Generic; namespace WindowsHybridAgenticStack { internal static class SetupPayload {')
$null = $payload.AppendLine('internal static readonly Dictionary<string,string> Files = new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase) {')
$assets = @($properties.Values) + @('install.ps1','uninstall.ps1','config\AGENTS.md',
    'scripts\script-invocation.ps1','scripts\setup-agents.ps1','scripts\install-agent-commands.ps1',
    'scripts\command-host.cs','scripts\command-registration.ps1','scripts\profile-loader.ps1',
    'scripts\config.ps1','scripts\agent-commands.ps1','scripts\installation-state.ps1','scripts\uninstall.ps1',
    'tts\install-tts.ps1','tts\tts.ps1','tts\tts_service.py')
$assets += 'tts/strategy.schema.json'
foreach ($package in $packages) {
    foreach ($file in $package.Files) { $assets += "tts/strategies/$($package.Manifest.id)/$file" }
}
foreach ($relative in $assets | Select-Object -Unique) {
    $encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $repo $relative)))
    $null = $payload.AppendLine(('{"'+$relative.Replace('\','/')+'","'+$encoded+'"},'))
}
$null = $payload.AppendLine('}; internal static string ReadText(string name) { return Encoding.UTF8.GetString(Convert.FromBase64String(Files[name])).TrimStart(new char[] { (char)0xfeff }); }')
foreach ($name in $properties.Keys) {
    $null = $payload.AppendLine(('internal static string {0} {{ get {{ return ReadText("{1}"); }} }}' -f $name,$properties[$name].Replace('\','/')))
}
$catalogEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($catalog))
$null = $payload.AppendLine(('internal static string StrategyCatalog { get { return Encoding.UTF8.GetString(Convert.FromBase64String("' + $catalogEncoded + '")); } }'))
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
        (Join-Path $PSScriptRoot 'command-host.cs'), (Join-Path $PSScriptRoot 'setup-host.cs'), (Join-Path $PSScriptRoot 'setup-runtime.cs'), $generated))
    if ($result.Errors.HasErrors) { throw (($result.Errors | ForEach-Object ToString) -join [Environment]::NewLine) }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $OutputPath)) | Out-Null
    Move-Item -LiteralPath $compiled -Destination $OutputPath -Force:$Force
    Write-Host "Built standalone setup: $OutputPath"
}
finally {
    if ($null -ne $compiler) { $compiler.Dispose() }
    $parameters.TempFiles.Delete()
    foreach ($path in @($generated,$compiled)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    if (@(Get-ChildItem -LiteralPath $build -Force).Count -eq 0) { Remove-Item -LiteralPath $build }
}
