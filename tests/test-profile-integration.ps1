#Requires -Version 5.1

# Runs real executable registration, root installer orchestration and
# command wrappers against a disposable copy. Dependency installation,
# prerequisites, inference, HTTP and audio generation are mocked.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'whas-integration-tests-' + [guid]::NewGuid().ToString('N'))
$originalLocal = $env:LOCALAPPDATA
$originalUserProfile = $env:USERPROFILE
$originalProfile = $PROFILE
$originalPath = $env:Path
$userPathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')

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
    $bin = Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack\bin'
    $ownership = Get-Content -LiteralPath (Join-Path $ExpectedRoot '.whas-installation.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($ownership.Status -eq 'Installed' -and $ownership.InstallPath -ceq $ExpectedRoot) 'Installer finalises ownership record'
    Assert-True (@($ownership.Files.Path) -contains 'uninstall.ps1') 'Installed uninstaller is tracked'
    $commands = @(Get-Command agent,agentdo,localagent,localagentdo,
        tts-start,tts-stop,tts-status,tts-say,tts-voice-list,
        tts-voice-add,tts-voice-remove,tts-voice-test -CommandType Application)
    Assert-True (@($commands | Select-Object -ExpandProperty Name -Unique).Count -eq 12) 'Native command entry points registered'
    Assert-True ([IO.File]::ReadAllText((Join-Path $bin 'install-root.txt')) -ceq $ExpectedRoot) 'Selected root registered locally'
    if ($Count -eq 12) {
        & (Join-Path $bin 'agent.exe') --help
        Assert-True ($LASTEXITCODE -eq 0) 'Real agent help works'
    }
    & (Join-Path $bin 'tts-voice-list.exe')
    Assert-True ($LASTEXITCODE -eq 0) 'Real TTS wrapper loads'
    Assert-True (-not (Test-Path -LiteralPath $PROFILE.CurrentUserCurrentHost)) 'No shared profile created'
}
try {
    Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Host "Test files: $testRoot"
    $fixtureRepo = Join-Path $testRoot 'repository'
    foreach ($relative in @('install.ps1', 'uninstall.ps1', 'scripts\script-invocation.ps1', 'scripts\installation-state.ps1', 'scripts\uninstall.ps1', 'scripts\install-agent-commands.ps1',
        'scripts\command-registration.ps1', 'scripts\command-host.cs', 'scripts\configuration.ps1', 'scripts\profile-loader.ps1', 'scripts\config.ps1', 'scripts\agent-commands.ps1',
        'config\defaults.json', 'tts\tts.ps1', 'tts\tts_service.py', 'tts\strategy-management.ps1', 'tts\strategy.schema.json', 'tts\strategies\chatterbox-turbo\manifest.json', 'tts\strategies\chatterbox-turbo\install.ps1', 'tts\strategies\chatterbox-turbo\uninstall.ps1', 'tts\strategies\chatterbox-turbo\backend.py', 'tts\strategies\chatterbox-turbo\requirements.txt', 'tts\strategies\chatterbox-turbo\prepare_model.py')) {
        $destination = Join-Path $fixtureRepo $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $sourceRoot $relative) -Destination $destination
    }
    Write-Fixture (Join-Path $fixtureRepo 'scripts\check-prerequisites.ps1') 'exit 0'
    $configEntry = Join-Path $fixtureRepo 'scripts\config.ps1'
    $overridePath = Join-Path $testRoot 'partial-config.json'
    Write-Fixture $overridePath '{"agents":{"cloud":{"model":"openai/test-model"}}}'
    $effective = (& $configEntry -Show -ConfigPath $overridePath | Out-String) | ConvertFrom-Json
    Assert-True ($LASTEXITCODE -eq 0 -and $effective.agents.cloud.model -eq 'openai/test-model') 'Partial configuration merges'
    Assert-True ($effective.tts.port -gt 0) 'Partial configuration retains defaults'
    Write-Fixture $overridePath '{"unknownSetting":42}'
    & $configEntry -Validate -ConfigPath $overridePath
    Assert-True ($LASTEXITCODE -eq 1) 'Unknown configuration rejected'
    $initPath = Join-Path $testRoot 'initialised-config.json'
    & $configEntry -Init -ConfigPath $initPath
    Assert-True ($LASTEXITCODE -eq 0) 'Config Init succeeds'
    $initHash = (Get-FileHash -LiteralPath $initPath).Hash
    & $configEntry -Init -ConfigPath $initPath
    Assert-True ($LASTEXITCODE -eq 1 -and (Get-FileHash -LiteralPath $initPath).Hash -ceq $initHash) 'Config Init refuses overwrite'
    Write-Host 'PASS: Shared configuration loader merges defaults, rejects unknown keys and preserves existing config'
    Write-Fixture (Join-Path $fixtureRepo 'scripts\setup-agents.ps1') @'
param([switch]$Cloud, [switch]$Local, [string]$InstallPath,
    [string]$CloudModel, [string]$LocalModel, [int]$LocalContextSize)
New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $InstallPath 'opencode.json'), '{}')
exit 0
'@
    Write-Fixture (Join-Path $fixtureRepo 'tts\install-tts.ps1') @'
param([string]$InstallPath, [string]$Device, [string]$TtsEngine)
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
    $env:USERPROFILE = $machineA
    $rootA = Join-Path $testRoot ("Custom A's [stack] " + [char]0x00e9)
    $rootB = Join-Path $testRoot 'Different B\Stack'
    $entryPoint = Join-Path $fixtureRepo 'install.ps1'


    # Keep installer questions isolated; a policy mutation is always a failure.
    function Read-Host { 'y' }
    function Set-ExecutionPolicy { throw 'Tests must not change execution policy.' }
    function Start-Process { throw 'Tests must not start a service.' }

    & $entryPoint -PersistCommandPath $false -Voice -InstallPath $rootA
    Assert-True ($LASTEXITCODE -eq 0) 'Root installer voice-only succeeds'
    Assert-Runtime $rootA 8
    Write-Host 'PASS: Voice-only installer registers real TTS commands at a custom root'


    & $entryPoint -PersistCommandPath $false -Cloud -InstallPath $rootA
    Assert-True ($LASTEXITCODE -eq 0) 'Adding agents succeeds after voice-only'
    Assert-Runtime $rootA 12
    Assert-True (-not (Test-Path -LiteralPath $profilePath)) 'Adding agents creates no profile'
    Write-Host 'PASS: Agent installer reuses the same registration; all 12 real commands load'


    $localFile = Join-Path $machineA '.windows-hybrid-agentic-stack\commands.json'
    $localHash = (Get-FileHash -LiteralPath $localFile).Hash
    & $entryPoint -PersistCommandPath $false -Cloud -Voice -InstallPath $rootA
    Assert-True ($LASTEXITCODE -eq 0) 'Repeat combined installation succeeds'
    Assert-True (-not (Test-Path -LiteralPath $profilePath)) 'Repeat profile bytes unchanged'
    Assert-True ((Get-FileHash -LiteralPath $localFile).Hash -ceq $localHash) 'Repeat local loader bytes unchanged'
    Assert-Runtime $rootA 12
    Write-Host 'PASS: Repeat combined installer leaves registration unchanged'

    $env:LOCALAPPDATA = $machineB
    $env:USERPROFILE = $machineB
    & $entryPoint -PersistCommandPath $false -Cloud -Voice -InstallPath $rootB
    Assert-True ($LASTEXITCODE -eq 0) 'Second simulated machine installer succeeds'
    Assert-Runtime $rootB 12
    Assert-True (-not (Test-Path -LiteralPath $profilePath)) 'Second machine preserves synced profile'
    $env:LOCALAPPDATA = $machineA
    $env:USERPROFILE = $machineA
    Assert-Runtime $rootA 12
    Write-Host 'PASS: Separate local registrations select each simulated PC root without a profile'

    # Exercise lazy voice loading without starting Python or producing audio.
    # HTTP readiness is mocked, and WAV generation stops at the request boundary.
    & {
        . (Join-Path $rootA 'scripts\configuration.ps1')
        . (Join-Path $rootA 'scripts\agent-commands.ps1') -InstallPath $rootA
        Assert-True ($null -eq (Get-Command tts-say -CommandType Function -ErrorAction Ignore)) 'TTS initially absent in lazy-load scope'
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
    $env:USERPROFILE = $machineA
    & $entryPoint -PersistCommandPath $false -Cloud -Voice -InstallPath $rootB
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
    $env:USERPROFILE = $originalUserProfile
    $PROFILE = $originalProfile
    $env:Path = $originalPath
    Assert-True ([Environment]::GetEnvironmentVariable('Path', 'User') -ceq $userPathBefore) 'Persistent user PATH unchanged'
    Write-Host "Retained test files: $testRoot"
}
