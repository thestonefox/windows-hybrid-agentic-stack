#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('whas-native-output-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$exe = Join-Path $fixture 'diagnostic.exe'
Add-Type -OutputAssembly $exe -OutputType ConsoleApplication -TypeDefinition @'
using System;
public static class DiagnosticFixture {
    public static int Main(string[] args) {
        Console.Out.WriteLine("native standard output");
        Console.Error.WriteLine("native progress on stderr");
        return args.Length == 0 ? 0 : Int32.Parse(args[0]);
    }
}
'@
function Import-Function([string]$Path,[string]$Name) {
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) { throw 'Source parse failed' }
    $definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name},$true)
    if ($null -eq $definition) { throw "Missing function: $Name" }
    return [scriptblock]::Create($definition.Extent.Text)
}
. (Import-Function (Join-Path $repo 'scripts\setup-agents.ps1') 'Invoke-AgentNativeCommand')
. (Import-Function (Join-Path $repo 'tts\install-tts.ps1') 'Invoke-CheckedCommand')
$output=@(Invoke-AgentNativeCommand $exe @())
if ($LASTEXITCODE -ne 0 -or $output -notcontains 'native standard output' -or $output -notcontains 'native progress on stderr' -or $ErrorActionPreference -ne 'Stop') { throw 'Agent wrapper mishandled successful stderr or caller preference' }
$output=@(Invoke-AgentNativeCommand $exe @('7'))
if ($LASTEXITCODE -ne 7 -or $output -notcontains 'native progress on stderr' -or $ErrorActionPreference -ne 'Stop') { throw 'Agent wrapper lost a failure exit code or caller preference' }
Invoke-CheckedCommand -Description 'Successful stderr fixture' -Executable $exe
$failed=$false
try { Invoke-CheckedCommand -Description 'Failed stderr fixture' -Executable $exe -Arguments @('9') }
catch { $failed=$_.Exception.Message.Contains('exit code 9') }
if (-not $failed -or $ErrorActionPreference -ne 'Stop') { throw 'Voice wrapper failed to reject a nonzero exit code or restore caller preference' }
$missingRejected=$false
try { $null=Invoke-AgentNativeCommand (Join-Path $fixture 'missing.exe') @() }
catch { $missingRejected=$true }
if (-not $missingRejected -or $ErrorActionPreference -ne 'Stop') { throw 'Agent wrapper accepted a missing executable or changed caller preference' }
$missingRejected=$false
try { Invoke-CheckedCommand -Description 'Missing executable fixture' -Executable (Join-Path $fixture 'missing.exe') }
catch { $missingRejected=$true }
if (-not $missingRejected -or $ErrorActionPreference -ne 'Stop') { throw 'Voice wrapper accepted a missing executable or changed caller preference' }
Write-Host 'PASS: Native stderr progress preserved, success/failure exit codes honored, Stop preference restored'
Write-Host "Retained fixture: $fixture"
