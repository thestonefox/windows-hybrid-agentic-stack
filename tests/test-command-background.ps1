#Requires -Version 5.1
# Reproduces native output capture with an independently running service.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
. (Join-Path $repository 'scripts\command-registration.ps1')
$originalPath = $env:Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('whas-background-test-' + [guid]::NewGuid().ToString('N'))
$root = Join-Path $testRoot 'installation'
$registration = Join-Path $testRoot 'registration'
$runner = $null
New-Item -ItemType Directory -Path (Join-Path $root 'tts') -Force | Out-Null
try {
    Add-Type -TypeDefinition @'
using System;
using System.Threading;
public static class BackgroundFixture {
    public static void Main() { Thread.Sleep(30000); }
}
'@ -OutputAssembly (Join-Path $root 'background.exe') -OutputType ConsoleApplication
    $runtime = @'
param([string]$InstallPath)
$script:FixtureRoot = $InstallPath
function tts-start {
    $childId = [WindowsHybridAgenticStack.CommandHost]::StartBackgroundProcess((Join-Path $script:FixtureRoot 'background.exe'), '', $script:FixtureRoot)
    [IO.File]::WriteAllText((Join-Path $script:FixtureRoot 'child.pid'), [string]$childId)
    'BACKGROUND STARTED'
}
'@
    [IO.File]::WriteAllText((Join-Path $root 'tts\tts.ps1'), $runtime, (New-Object Text.UTF8Encoding($true)))
    Install-StackCommandRegistration -InstallPath $root -RegistrationDirectory $registration -PersistPath $false
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = Join-Path $registration 'bin\tts-start.exe'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $runner = New-Object Diagnostics.Process
    $runner.StartInfo = $startInfo
    $null = $runner.Start()
    $stdout = $runner.StandardOutput.ReadToEndAsync()
    $stderr = $runner.StandardError.ReadToEndAsync()
    if (-not $runner.WaitForExit(10000)) { throw 'Launcher failed to exit while its service runs.' }
    if (-not $stdout.Wait(2000) -or -not $stderr.Wait(2000)) {
        throw 'Background service retained the launcher output pipes after launcher exit.'
    }
    if ($runner.ExitCode -ne 0 -or -not $stdout.Result.Contains('BACKGROUND STARTED')) {
        throw ('Unexpected launcher output: ' + $stdout.Result + $stderr.Result)
    }
    $childId = [int][IO.File]::ReadAllText((Join-Path $root 'child.pid'))
    $child = Get-Process -Id $childId -ErrorAction Stop
    if ($child.HasExited) { throw 'Fixture service must still be running when captured output completes.' }
    Write-Host 'PASS: Native launcher exits, captured output reaches EOF, and background service stays alive.'
}
finally {
    $pidFile = Join-Path $root 'child.pid'
    if (Test-Path -LiteralPath $pidFile) {
        $childId = [int][IO.File]::ReadAllText($pidFile)
        $childInfo = Get-Process -Id $childId -ErrorAction SilentlyContinue
        if ($null -ne $childInfo -and $childInfo.Path -ieq (Join-Path $root 'background.exe')) {
            Stop-Process -Id $childId -Force -ErrorAction SilentlyContinue
        }
    }
    if ($null -ne $runner) {
        if (-not $runner.HasExited) { $runner.Kill() }
        $runner.Dispose()
    }
    $env:Path = $originalPath
    Write-Host "Retained test files: $testRoot"
}
