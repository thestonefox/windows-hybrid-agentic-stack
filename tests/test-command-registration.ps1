#Requires -Version 5.1
# Isolated tests: no persistent PATH/policy changes or real profile writes.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
. (Join-Path $repository 'scripts\command-registration.ps1')
$originalPath = $env:Path
$originalRecorder = $env:WHAS_TEST_ARGUMENTS
$userPathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')
$policyBefore = Get-ExecutionPolicy -List | ConvertTo-Json -Compress
$profileBefore = if ($PROFILE.CurrentUserCurrentHost -and (Test-Path -LiteralPath $PROFILE.CurrentUserCurrentHost)) {
    (Get-FileHash -LiteralPath $PROFILE.CurrentUserCurrentHost -Algorithm SHA256).Hash
} else { 'ABSENT' }
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('whas-native-tests-' + [guid]::NewGuid().ToString('N'))
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
}
function Write-Fixture {
    param([string]$Path, [AllowEmptyString()][string]$Content)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($true)))
}
function Invoke-Restricted {
    param([string]$Code, [int]$ExpectedExit = 0)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code))
    $output = @(& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Restricted -EncodedCommand $encoded 2>&1)
    $actualExit = $LASTEXITCODE
    if ($actualExit -ne $ExpectedExit) { $output | Out-Host; throw "FAIL: Restricted child exit $actualExit, expected $ExpectedExit" }
    return $output
}
try {
    Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Host "Test files: $testRoot"
    $rootA = Join-Path $testRoot ("A's [custom] " + [char]0x00e9)
    $rootB = Join-Path $testRoot 'Other root\Stack'
    $localA = Join-Path $testRoot 'PC-A\Local'
    $localB = Join-Path $testRoot 'PC-B\Local'
    foreach ($root in @($rootA,$rootB)) {
        foreach ($relative in @('scripts\agent-commands.ps1','scripts\configuration.ps1','config\defaults.json')) {
            $destination = Join-Path $root $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $repository $relative) -Destination $destination
        }
        Write-Fixture (Join-Path $root 'opencode.json') '{}'
        Write-Fixture (Join-Path $root 'tts\tts.ps1') @'
param([string]$InstallPath)
$script:FixtureRoot = $InstallPath
function tts-start { 'TTS START ' + $script:FixtureRoot }
function tts-stop { 'TTS STOP' }
function tts-status { 'TTS STATUS' }
function tts-voice-list { 'default' }
function tts-say {
    param([Parameter(Position=0,Mandatory=$true)][string]$Text, [string]$Voice='default')
    'SPOKEN ' + $Voice + ': ' + $Text + ' ROOT=' + $script:FixtureRoot
}
function tts-voice-add { param([string]$Path,[string]$Name) 'ADD ' + $Path + ' NAME=' + $Name }
function tts-voice-remove { param([Parameter(Position=0)][string]$Name) $reply=Read-Host 'Type YES'; 'REMOVE ' + $Name + ' REPLY=' + $reply }
function tts-voice-test { param([Parameter(Position=0)][string]$Name) 'VOICE ' + $Name }
'@
    }
    $fakeBin = Join-Path $testRoot 'fake-bin'
    New-Item -ItemType Directory -Path $fakeBin | Out-Null
    Add-Type -TypeDefinition @'
using System;
using System.IO;
public static class FakeOpenCode {
    public static int Main(string[] args) {
        string[] lines = new string[args.Length];
        for (int i=0; i<args.Length; i++) lines[i] = Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(args[i]));
        File.WriteAllLines(Environment.GetEnvironmentVariable("WHAS_TEST_ARGUMENTS"), lines);
        Console.WriteLine("{\"type\":\"text\",\"part\":{\"text\":\"TEST ANSWER\"}}");
        return 0;
    }
}
'@ -OutputAssembly (Join-Path $fakeBin 'opencode.exe') -OutputType ConsoleApplication
    $env:Path = $fakeBin + ';' + $originalPath
    $env:WHAS_TEST_ARGUMENTS = Join-Path $testRoot 'received-arguments.txt'
    Install-StackCommandRegistration -InstallPath $rootA -RegistrationDirectory (Join-Path $localA 'WindowsHybridAgenticStack') -PersistPath $false
    $commands = @(Get-Command agent,agentdo,localagent,localagentdo,tts-start,tts-stop,tts-status,
        tts-say,tts-voice-list,tts-voice-add,tts-voice-remove,tts-voice-test,tts-engine-list,tts-engine-install,tts-engine-uninstall,tts-engine-default,whas,tts-help -CommandType Application)
    Assert-True ($commands.Count -eq 18) 'All 18 executable names discovered'
    $beforeFiles = @(Get-ChildItem -LiteralPath (Join-Path $localA 'WindowsHybridAgenticStack') -Recurse -File |
        Select-Object FullName,LastWriteTimeUtc,Length) | ConvertTo-Json -Compress
    Install-StackCommandRegistration -InstallPath $rootA -RegistrationDirectory (Join-Path $localA 'WindowsHybridAgenticStack') -PersistPath $false
    $afterFiles = @(Get-ChildItem -LiteralPath (Join-Path $localA 'WindowsHybridAgenticStack') -Recurse -File |
        Select-Object FullName,LastWriteTimeUtc,Length) | ConvertTo-Json -Compress
    Assert-True ($beforeFiles -ceq $afterFiles) 'Repeat registration leaves files/timestamps unchanged'
    Write-Host 'PASS: All 18 native entry points; custom root and idempotence'
    $result = Invoke-Restricted @'
$ErrorActionPreference='Stop'
if ((Get-ExecutionPolicy) -ne 'Restricted') { throw 'Test policy not Restricted' }
agent --help
if ($LASTEXITCODE -ne 0) { exit 1 }
agent 'literal & echo INJECTED %PATH% ! ^'
if ($LASTEXITCODE -ne 0) { exit 2 }
agentdo -v sample 'voice question'
if ($LASTEXITCODE -ne 0) { exit 3 }
localagent -m 'qwen3:8b' 'local question'
if ($LASTEXITCODE -ne 0) { exit 4 }
localagentdo -v 'local voice question'
if ($LASTEXITCODE -ne 0) { exit 5 }
tts-say -Text 'named text' -Voice sample
if ($LASTEXITCODE -ne 0) { exit 6 }
tts-voice-add -Path 'C:\samples\my voice.wav' -Name sample
if ($LASTEXITCODE -ne 0) { exit 7 }
tts-voice-test sample
if ($LASTEXITCODE -ne 0) { exit 8 }
tts-start
tts-status
tts-stop
tts-voice-list
if ((Get-ExecutionPolicy) -ne 'Restricted') { throw 'Policy changed' }
'@
    Assert-True (($result | Out-String).Contains('TEST ANSWER')) 'Agent output forwarded'
    Assert-True (($result | Out-String).Contains('SPOKEN sample: TEST ANSWER')) 'Voice flag/name forwarded'
    Assert-True (($result | Out-String).Contains('ROOT=' + $rootA)) 'Custom TTS root forwarded'
    Assert-True (($result | Out-String).Contains('named text')) 'Named TTS arguments preserved'
    Write-Host 'PASS: Restricted policy unchanged; agent flags, native arguments and TTS syntax work'
    $null = Invoke-Restricted "agent 'literal & echo INJECTED %PATH% ! ^'; exit `$LASTEXITCODE"
    $received = @([IO.File]::ReadAllLines($env:WHAS_TEST_ARGUMENTS) | ForEach-Object {
        [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_))
    })
    Assert-True ($received -contains 'literal & echo INJECTED %PATH% ! ^') 'Literal shell characters arrive unchanged'
    Write-Host 'PASS: Exact native argument round trip; shell characters remain literal'
    $result = @('YES' | & (Join-Path $localA 'WindowsHybridAgenticStack\bin\tts-voice-remove.exe') sample)
    Assert-True (($result | Out-String).Contains('REPLY=YES')) 'Interactive confirmation reads stdin'
    Write-Host 'PASS: Interactive voice confirmation supported'
    Install-StackCommandRegistration -InstallPath $rootB -RegistrationDirectory (Join-Path $localB 'WindowsHybridAgenticStack') -PersistPath $false
    $result = Invoke-Restricted 'tts-start; if ($LASTEXITCODE -ne 0) { exit 1 }'
    Assert-True (($result | Out-String).Contains($rootB)) 'Second machine uses its own root'
    Install-StackCommandRegistration -InstallPath $rootB -RegistrationDirectory (Join-Path $localA 'WindowsHybridAgenticStack') -PersistPath $false
    $result = @(& (Join-Path $localA 'WindowsHybridAgenticStack\bin\tts-start.exe'))
    Assert-True (($result | Out-String).Contains($rootB)) 'Changing installation root works'
    Write-Host 'PASS: Two simulated machines and installation path changes'
    $env:Path = $originalPath
    $result = Invoke-Restricted @'
$ErrorActionPreference='Stop'
if (@(Get-Command agent,localagent,tts-start -ErrorAction Ignore).Count -ne 0) { throw 'Unexpected commands' }
'NO COMMANDS; NO STARTUP LOADER'
'@
    Assert-True (($result | Out-String).Contains('NO COMMANDS')) 'Absent PC remains clean'
    Write-Host 'PASS: Absent machine starts under Restricted without stack commands'
    $unknown = Join-Path $localA 'WindowsHybridAgenticStack\bin\notes.txt'
    Write-Fixture $unknown 'unrelated file'
    $changed = Join-Path $localA 'WindowsHybridAgenticStack\bin\tts-status.exe'
    $originalExecutable = [IO.File]::ReadAllBytes($changed)
    [IO.File]::WriteAllText($changed, 'unrecognised executable')
    $rejected = $false
    try { Unregister-StackCommands -RegistrationDirectory (Join-Path $localA 'WindowsHybridAgenticStack') -PersistPath $false } catch { $rejected = $true }
    Assert-True $rejected 'Cleanup refuses a modified executable'
    Assert-True (Test-Path -LiteralPath (Join-Path $localA 'WindowsHybridAgenticStack\bin\agent.exe')) 'Failed preflight leaves other commands intact'
    $rejected = $false
    try { Install-StackCommandRegistration -InstallPath $rootB -RegistrationDirectory (Join-Path $localA 'WindowsHybridAgenticStack') -PersistPath $false } catch { $rejected = $true }
    Assert-True $rejected 'Registration refuses a modified executable'
    [IO.File]::WriteAllBytes($changed, $originalExecutable)
    Unregister-StackCommands -RegistrationDirectory (Join-Path $localA 'WindowsHybridAgenticStack') -PersistPath $false
    Unregister-StackCommands -RegistrationDirectory (Join-Path $localA 'WindowsHybridAgenticStack') -PersistPath $false
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $localA 'WindowsHybridAgenticStack\bin\agent.exe'))) 'Unregister removes managed entry points'
    Assert-True (Test-Path -LiteralPath $rootA -PathType Container) 'Unregister preserves installation files'
    Assert-True ([IO.File]::ReadAllText($unknown) -ceq 'unrelated file') 'Unregister preserves unrelated bin files'
    Write-Host 'PASS: Repeat unregister preserves installation and unrelated files'
    Write-Host 'All isolated native registration tests passed.'
}
finally {
    $env:Path = $originalPath
    $env:WHAS_TEST_ARGUMENTS = $originalRecorder
    Assert-True ([Environment]::GetEnvironmentVariable('Path', 'User') -ceq $userPathBefore) 'Persistent user PATH unchanged'
    Assert-True ((Get-ExecutionPolicy -List | ConvertTo-Json -Compress) -ceq $policyBefore) 'Policy scopes unchanged'
    $profileAfter = if ($PROFILE.CurrentUserCurrentHost -and (Test-Path -LiteralPath $PROFILE.CurrentUserCurrentHost)) {
        (Get-FileHash -LiteralPath $PROFILE.CurrentUserCurrentHost -Algorithm SHA256).Hash
    } else { 'ABSENT' }
    Assert-True ($profileBefore -ceq $profileAfter) 'Real profile untouched'
    Write-Host "Retained isolated test fixtures: $testRoot"
}
