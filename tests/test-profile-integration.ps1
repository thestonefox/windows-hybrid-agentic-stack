#Requires -Version 5.1

# Runs the real profile registration, root installer orchestration and
# command wrappers against a disposable copy. Dependency installation,
# prerequisites, inference, HTTP and audio generation are mocked.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'whas-integration-tests-' + [guid]::NewGuid().ToString('N'))
$originalLocal = $env:LOCALAPPDATA
$originalProfile = $PROFILE

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Write-Fixture {
    param([string]$Path, [AllowEmptyString()][string]$Content)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [System.IO.File]::WriteAllText($Path, $Content,
        (New-Object System.Text.UTF8Encoding($true)))
}

function Assert-Runtime {
    param([string]$ExpectedRoot, [int]$Count)
    & {
        $Error.Clear()
        . $PROFILE.CurrentUserCurrentHost
        $commands = @(Get-Command agent,agentdo,localagent,localagentdo,
            tts-start,tts-stop,tts-status,tts-say,tts-voice-list,
            tts-voice-add,tts-voice-remove,tts-voice-test -ErrorAction Ignore)
        Assert-True ($commands.Count -eq $Count) 'Real command functions registered'
        Assert-True ($Error.Count -eq 0) 'Real scripts load without startup errors'
        if ($Count -eq 12) {
            Assert-True ($script:AgentStackInstallPath -ceq $ExpectedRoot) 'Agent uses selected root'
            agent --help
        }
        Assert-True ($script:TtsRoot -ceq $ExpectedRoot) 'TTS uses selected root'
        Assert-True ($script:TtsPython -ceq (Join-Path $ExpectedRoot '.venv\Scripts\python.exe')) 'TTS Python path'
        tts-voice-list
    }
}

try {
    Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Host "Test files: $testRoot"
    $fixtureRepo = Join-Path $testRoot 'repository'
    foreach ($relative in @('install.ps1', 'scripts\install-agent-commands.ps1',
        'scripts\profile-loader.ps1', 'scripts\config.ps1', 'scripts\agent-commands.ps1',
        'config\defaults.json', 'tts\tts.ps1', 'tts\tts_service.py')) {
        $destination = Join-Path $fixtureRepo $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $sourceRoot $relative) -Destination $destination
    }
    Write-Fixture (Join-Path $fixtureRepo 'scripts\check-prerequisites.ps1') 'exit 0'
    Write-Fixture (Join-Path $fixtureRepo 'scripts\setup-agents.ps1') @'
param([switch]$Cloud, [switch]$Local, [string]$InstallPath,
    [string]$CloudModel, [string]$LocalModel, [int]$LocalContextSize)
New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $InstallPath 'opencode.json'), '{}')
exit 0
'@
    Write-Fixture (Join-Path $fixtureRepo 'tts\install-tts.ps1') @'
param([string]$InstallPath, [string]$Device)
$destination = Join-Path $InstallPath 'tts'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
foreach ($name in @('tts.ps1', 'tts_service.py')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $destination $name) -Force
}
exit 0
'@

    $profilePath = Join-Path $testRoot 'shared\Microsoft.PowerShell_profile.ps1'
    $PROFILE = $profilePath
    $PROFILE | Add-Member -NotePropertyName CurrentUserCurrentHost -NotePropertyValue $profilePath
    $machineA = Join-Path $testRoot 'machine-a\LocalAppData'
    $machineB = Join-Path $testRoot 'machine-b\LocalAppData'
    $env:LOCALAPPDATA = $machineA
    $rootA = Join-Path $testRoot ("Custom A's [stack] " + [char]0x00e9)
    $rootB = Join-Path $testRoot 'Different B\Stack'
    $entryPoint = Join-Path $fixtureRepo 'install.ps1'
    Write-Fixture $profilePath ''

    # Keep installer questions and policy handling isolated in this process.
    function Read-Host { 'y' }
    function Get-ExecutionPolicy {
        param([switch]$List)
        if ($List) {
            foreach ($scope in @('MachinePolicy', 'UserPolicy', 'CurrentUser', 'LocalMachine')) {
                [pscustomobject]@{ Scope = $scope; ExecutionPolicy = $(
                    if ($scope -eq 'CurrentUser') { 'RemoteSigned' } else { 'Undefined' }) }
            }
        }
        else { 'RemoteSigned' }
    }
    function Set-ExecutionPolicy { throw 'Tests must not change execution policy.' }
    function Start-Process { throw 'Tests must not start a service.' }

    & $entryPoint -Voice -InstallPath $rootA
    Assert-True ($LASTEXITCODE -eq 0) 'Root installer voice-only succeeds'
    Assert-Runtime $rootA 8
    Write-Host 'PASS: Voice-only installer registers real TTS commands at a custom root'

    $syncedBefore = [System.IO.File]::ReadAllText($profilePath)
    & $entryPoint -Cloud -InstallPath $rootA
    Assert-True ($LASTEXITCODE -eq 0) 'Adding agents succeeds after voice-only'
    Assert-Runtime $rootA 12
    Assert-True ([System.IO.File]::ReadAllText($profilePath) -ceq $syncedBefore) 'Adding agents preserves synced bootstrap'
    Write-Host 'PASS: Agent installer reuses the same bootstrap; all 12 real commands load'

    $profileHash = (Get-FileHash -LiteralPath $profilePath).Hash
    $localFile = Join-Path $machineA 'WindowsHybridAgenticStack\profile.ps1'
    $localHash = (Get-FileHash -LiteralPath $localFile).Hash
    & $entryPoint -Cloud -Voice -InstallPath $rootA
    Assert-True ($LASTEXITCODE -eq 0) 'Repeat combined installation succeeds'
    Assert-True ((Get-FileHash -LiteralPath $profilePath).Hash -ceq $profileHash) 'Repeat profile bytes unchanged'
    Assert-True ((Get-FileHash -LiteralPath $localFile).Hash -ceq $localHash) 'Repeat local loader bytes unchanged'
    Assert-Runtime $rootA 12
    Write-Host 'PASS: Repeat combined installer leaves registration unchanged'

    $env:LOCALAPPDATA = $machineB
    & $entryPoint -Cloud -Voice -InstallPath $rootB
    Assert-True ($LASTEXITCODE -eq 0) 'Second simulated machine installer succeeds'
    Assert-Runtime $rootB 12
    Assert-True ((Get-FileHash -LiteralPath $profilePath).Hash -ceq $profileHash) 'Second machine preserves synced profile'
    $env:LOCALAPPDATA = $machineA
    Assert-Runtime $rootA 12
    Write-Host 'PASS: Same synced profile loads real scripts from each PC root'

    # Exercise lazy voice loading without starting Python or producing audio.
    # HTTP readiness is mocked, and WAV generation stops at the request boundary.
    & {
        . (Join-Path $rootA 'scripts\agent-commands.ps1') -InstallPath $rootA
        Assert-True ($null -eq (Get-Command tts-say -ErrorAction Ignore)) 'TTS initially absent in lazy-load scope'
        function opencode {
            $global:LASTEXITCODE = 0
            '{"type":"text","part":{"text":"Paris"}}'
        }
        function Invoke-RestMethod { @{ running = $true } }
        function Invoke-WebRequest {
            param($Uri, $Method, $ContentType, $Body, $OutFile, $TimeoutSec, [switch]$UseBasicParsing, $ErrorAction)
            $script:RequestedWav = $OutFile
            throw 'TEST: stopped at mocked audio generation boundary'
        }
        $script:RequestedWav = $null
        $WarningPreference = 'SilentlyContinue'
        $answer = @(agent -v 'What is the capital of France?')
        Assert-True ($answer -contains 'Paris') 'Real wrapper extracts mocked agent answer'
        Assert-True ($script:TtsRoot -ceq $rootA) 'Lazy TTS loader receives custom root'
        Assert-True ($script:RequestedWav -ceq (Join-Path $rootA 'tts\last-spoken.wav')) 'Speech uses custom output path'
    }
    Write-Host 'PASS: Real agent -v lazily loads real TTS wrapper with explicit custom root'

    $env:LOCALAPPDATA = $machineA
    & $entryPoint -Cloud -Voice -InstallPath $rootB
    Assert-True ($LASTEXITCODE -eq 0) 'Changing selected root succeeds'
    Assert-Runtime $rootB 12
    Write-Host 'PASS: Installer updates machine-local registration when selected root changes'

    $parseErrors = @()
    Get-ChildItem -LiteralPath $sourceRoot -Recurse -Filter '*.ps1' |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
        ForEach-Object {
            $tokens = $null
            $foundErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $_.FullName, [ref]$tokens, [ref]$foundErrors)
            $parseErrors += $foundErrors
        }
    Assert-True ($parseErrors.Count -eq 0) 'All repository PowerShell scripts parse in 5.1'
    Write-Host 'PASS: Repository PowerShell 5.1 syntax'
    Write-Host 'All isolated integration tests passed.'
}
finally {
    $env:LOCALAPPDATA = $originalLocal
    $PROFILE = $originalProfile
    Write-Host "Retained test files: $testRoot"
}
