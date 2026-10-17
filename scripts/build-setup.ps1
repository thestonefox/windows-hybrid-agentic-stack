#Requires -Version 5.1
<#
.SYNOPSIS
    Build standalone setup with the Windows compiler and bundled application assets.
.DESCRIPTION
    Packages only checked-in application scripts and defaults. No user config,
    credentials, profiles or environment values are embedded in the executable.
#>
[CmdletBinding()]
param([string]$OutputPath, [switch]$Force, [switch]$Fingerprint, [switch]$Graphical)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess) {
    throw 'Build using 64-bit Windows PowerShell 5.1.'
}
$repo = Split-Path -Parent $PSScriptRoot
if (-not (Get-Command Get-StackSetupScript -ErrorAction Ignore)) { . (Join-Path $PSScriptRoot 'script-invocation.ps1') }
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
. (Get-StackSetupScript (Join-Path $repo 'tts/strategy-management.ps1'))
$packages = @(Get-TtsStrategies -Root $repo)
$catalog = ConvertTo-Json -InputObject @($packages | ForEach-Object { $_.Manifest }) -Depth 12 -Compress
$payload = New-Object Text.StringBuilder
$null = $payload.AppendLine('using System; using System.Text; using System.Collections.Generic; namespace WindowsHybridAgenticStack { internal static class SetupPayload {')
$null = $payload.AppendLine('internal static readonly Dictionary<string,string> Files = new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase) {')
$assets = @($properties.Values) + @('install.ps1','uninstall.ps1','config\AGENTS.md',
    'scripts\script-invocation.ps1','scripts\setup-agents.ps1','scripts\install-agent-commands.ps1',
    'scripts\command-host.cs','scripts\command-registration.ps1','scripts\profile-loader.ps1',
    'scripts\config.ps1','scripts\agent-commands.ps1','scripts\agent-strategies.ps1','scripts\whas.ps1','scripts\installation-state.ps1','scripts\uninstall.ps1',
    'tts\install-tts.ps1','tts\engine-management.ps1','tts\tts.ps1','tts\tts_service.py')
$assets += @('tts/strategy.schema.json','scripts/gui-maintenance.ps1')
$assets += @('scripts/gui-host.cs','scripts/fluent-gui.cs','scripts/gui-theme.xaml','scripts/build-gui.ps1','scripts/build-setup.ps1','scripts/setup-host.cs','scripts/setup-runtime.cs')
. (Get-StackSetupScript (Join-Path $repo 'scripts/agent-strategies.ps1')) -InstallPath $repo
. (Get-StackSetupScript (Join-Path $repo 'scripts/installation-state.ps1'))
foreach ($strategy in Get-WhasAgentStrategies) {
    foreach ($file in $strategy.Manifest.files) { $assets += "agents/strategies/$($strategy.Manifest.id)/$file" }
}
foreach ($package in $packages) {
    foreach ($file in $package.Files) { $assets += "tts/strategies/$($package.Manifest.id)/$file" }
}
if ($Fingerprint) {
    # Git ZIPs use LF while Windows clones may use CRLF. Canonicalise UTF-8
    # text for freshness checks; binary assets retain their exact byte hashes.
    $utf8=New-Object Text.UTF8Encoding($false,$true)
    $inputLines = @($assets | Select-Object -Unique | Sort-Object | ForEach-Object {
        $bytes=[IO.File]::ReadAllBytes((Join-Path $repo $_))
        try {
            $text=$utf8.GetString($bytes)
            if($text.IndexOf([char]0) -lt 0) { $bytes=$utf8.GetBytes($text.Replace("`r`n","`n")) }
        } catch [Text.DecoderFallbackException] { }
        $assetSha=[Security.Cryptography.SHA256]::Create()
        try { $assetHash=([BitConverter]::ToString($assetSha.ComputeHash($bytes))).Replace('-','') }
        finally { $assetSha.Dispose() }
        $_.Replace('\','/') + ':' + $assetHash
    })
    $sha=[Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($inputLines -join "`n"))))).Replace('-','') }
    finally { $sha.Dispose() }
    return
}
$resourceAssets = @($assets | Select-Object -Unique)
for ($index=0; $index -lt $resourceAssets.Count; $index++) {
    $relative=$resourceAssets[$index]
    $null = $payload.AppendLine(('{"'+$relative.Replace('\','/')+'","whas-asset-'+$index+'"},'))
}
$null = $payload.AppendLine('}; internal static byte[] ResourceBytes(string resource) { using(var stream=typeof(SetupPayload).Assembly.GetManifestResourceStream(resource)) { if(stream==null) throw new InvalidOperationException("Missing application resource: "+resource); using(var bytes=new System.IO.MemoryStream()) { stream.CopyTo(bytes); return bytes.ToArray(); } } }')
$null = $payload.AppendLine('internal static byte[] ReadBytes(string name) { return ResourceBytes(Files[name]); } internal static string ReadText(string name) { return Encoding.UTF8.GetString(ReadBytes(name)).TrimStart(new char[] { (char)0xfeff }); }')
foreach ($name in $properties.Keys) {
    $null = $payload.AppendLine(('internal static string {0} {{ get {{ return ReadText("{1}"); }} }}' -f $name,$properties[$name].Replace('\','/')))
}
$null = $payload.AppendLine('internal static string StrategyCatalog { get { return Encoding.UTF8.GetString(ResourceBytes("whas-strategy-catalog")); } }')
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
    $parameters.CompilerOptions = if($Graphical) { '/target:winexe /platform:x64 /main:WindowsHybridAgenticStack.GuiBootstrap' } else { '/platform:x64 /main:WindowsHybridAgenticStack.SetupHost' }
    $parameters.TempFiles = New-Object CodeDom.Compiler.TempFileCollection($build, $false)
    # Store original file bytes as ordinary .NET resources, not encoded C# text.
    for ($index=0; $index -lt $resourceAssets.Count; $index++) {
        $resource=Join-Path $build "whas-asset-$index"
        Copy-Item -LiteralPath (Join-Path $repo $resourceAssets[$index]) -Destination $resource
        $null=$parameters.EmbeddedResources.Add($resource)
    }
    $catalogResource=Join-Path $build 'whas-strategy-catalog'
    [IO.File]::WriteAllText($catalogResource,$catalog,(New-Object Text.UTF8Encoding($false)))
    $null=$parameters.EmbeddedResources.Add($catalogResource)
    $null = $parameters.ReferencedAssemblies.Add('System.dll')
    $null = $parameters.ReferencedAssemblies.Add('System.Core.dll')
    foreach ($assembly in @('System.Drawing.dll','System.Windows.Forms.dll','System.Web.Extensions.dll')) { $null = $parameters.ReferencedAssemblies.Add($assembly) }
    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml
    foreach ($assembly in @([System.Windows.Window].Assembly.Location,[System.Windows.Media.Visual].Assembly.Location,[System.Windows.Threading.Dispatcher].Assembly.Location,[System.Xaml.XamlReader].Assembly.Location)) { $null=$parameters.ReferencedAssemblies.Add($assembly) }
    $null = $parameters.ReferencedAssemblies.Add([Management.Automation.PSObject].Assembly.Location)
    $compiler = New-Object Microsoft.CSharp.CSharpCodeProvider
    $result = $compiler.CompileAssemblyFromFile($parameters, [string[]]@(
        (Join-Path $PSScriptRoot 'command-host.cs'), (Join-Path $PSScriptRoot 'gui-host.cs'), (Join-Path $PSScriptRoot 'fluent-gui.cs'), (Join-Path $PSScriptRoot 'setup-host.cs'), (Join-Path $PSScriptRoot 'setup-runtime.cs'), $generated))
    if ($result.Errors.HasErrors) { throw (($result.Errors | ForEach-Object ToString) -join [Environment]::NewLine) }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $OutputPath)) | Out-Null
    Move-Item -LiteralPath $compiled -Destination $OutputPath -Force:$Force
    Write-Host "Built standalone setup: $OutputPath"
}
finally {
    if ($null -ne $compiler) { $compiler.Dispose() }
    $parameters.TempFiles.Delete()
    foreach ($path in @($generated,$compiled) + @($parameters.EmbeddedResources)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    if (@(Get-ChildItem -LiteralPath $build -Force).Count -eq 0) { Remove-Item -LiteralPath $build }
}
