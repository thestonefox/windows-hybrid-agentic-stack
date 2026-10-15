#Requires -Version 5.1

# Uses only fresh temporary files and stub commands. Does not install
# software, change execution policy, or read/write the real user profile.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\profile-loader.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Write-Fixture {
    param([string]$Path, [AllowEmptyString()][string]$Content)
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    [System.IO.File]::WriteAllText($Path, $Content,
        (New-Object System.Text.UTF8Encoding($true)))
}

function Assert-ProfileLoads {
    param([string]$ProfilePath, [string]$LocalPath,
        [string]$ExpectedRoot, [int]$ExpectedCommands)
    $env:LOCALAPPDATA = $LocalPath
    & {
        $script:TestAgentRoot = $null
        $script:TestTtsRoot = $null
        $Error.Clear()
        . $ProfilePath
        $commands = @(Get-Command agent,agentdo,localagent,localagentdo,
            tts-start,tts-stop,tts-status,tts-say,tts-voice-list,
            tts-voice-add,tts-voice-remove,tts-voice-test -ErrorAction Ignore)
        Assert-True ($commands.Count -eq $ExpectedCommands) 'Expected command registration count'
        Assert-True ($Error.Count -eq 0) 'No profile startup errors'
        if ($ExpectedCommands -gt 0) {
            Assert-True ($script:TestAgentRoot -ceq $ExpectedRoot) 'Explicit custom agent root'
        }
        if ($ExpectedCommands -eq 12) {
            Assert-True ($script:TestTtsRoot -ceq $ExpectedRoot) 'Explicit custom TTS root'
        }
        Assert-True ($null -eq (Get-Variable whasInstallRoot -ErrorAction Ignore)) 'Runtime variables removed'
    }
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'whas-profile-tests-' + [guid]::NewGuid().ToString('N'))
$originalLocal = $env:LOCALAPPDATA

try {
    Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Host "Test files: $testRoot"
    $profilePath = Join-Path $testRoot 'shared\Microsoft.PowerShell_profile.ps1'
    $machineA = Join-Path $testRoot 'machine-a\LocalAppData'
    $machineB = Join-Path $testRoot 'machine-b\LocalAppData'
    $machineAbsent = Join-Path $testRoot 'machine-absent\LocalAppData'
    # Include spaces, an apostrophe, brackets and non-ASCII in a custom root.
    $rootA = Join-Path $testRoot ("Custom A's [stack] " + [char]0x00e9)
    $rootB = Join-Path $testRoot 'Different B\Stack'
    $agentStub = @'
param([string]$InstallPath)
$script:TestAgentRoot = $InstallPath
function agent {}
function agentdo {}
function localagent {}
function localagentdo {}
'@
    $ttsStub = @'
param([string]$InstallPath)
$script:TestTtsRoot = $InstallPath
function tts-start {}
function tts-stop {}
function tts-status {}
function tts-say {}
function tts-voice-list {}
function tts-voice-add {}
function tts-voice-remove {}
function tts-voice-test {}
'@
    foreach ($root in @($rootA, $rootB)) {
        Write-Fixture (Join-Path $root 'scripts\agent-commands.ps1') $agentStub
        Write-Fixture (Join-Path $root 'tts\tts.ps1') $ttsStub
    }

    Write-Fixture $profilePath ''
    Install-StackProfileLoader -InstallPath $rootA -ProfilePath $profilePath -LocalAppDataPath $machineA
    Assert-ProfileLoads $profilePath $machineA $rootA 12
    Write-Host 'PASS: Empty profile; both command loaders; custom path and escaping'

    $profileBefore = [System.IO.File]::ReadAllText($profilePath)
    $localFile = Join-Path $machineA 'WindowsHybridAgenticStack\profile.ps1'
    $localBefore = [System.IO.File]::ReadAllText($localFile)
    $backupCount = @(Get-ChildItem -LiteralPath $testRoot -Recurse -Filter '*.bak.*').Count
    Install-StackProfileLoader -InstallPath $rootA -ProfilePath $profilePath -LocalAppDataPath $machineA
    Assert-True ([System.IO.File]::ReadAllText($profilePath) -ceq $profileBefore) 'Repeat profile unchanged'
    Assert-True ([System.IO.File]::ReadAllText($localFile) -ceq $localBefore) 'Repeat local loader unchanged'
    Assert-True (@(Get-ChildItem -LiteralPath $testRoot -Recurse -Filter '*.bak.*').Count -eq $backupCount) 'Repeat creates no backups'
    Assert-True (-not $profileBefore.Contains($rootA)) 'No installation path in synced profile'
    Assert-True (-not $profileBefore.Contains($machineA)) 'No local app data path in synced profile'
    Write-Host 'PASS: Idempotence and location-independent synced profile'

    Install-StackProfileLoader -InstallPath $rootB -ProfilePath $profilePath -LocalAppDataPath $machineB
    Assert-True ([System.IO.File]::ReadAllText($profilePath) -ceq $profileBefore) 'Second PC leaves shared profile unchanged'
    Assert-ProfileLoads $profilePath $machineA $rootA 12
    Assert-ProfileLoads $profilePath $machineB $rootB 12
    Assert-ProfileLoads $profilePath $machineAbsent '' 0
    $env:LOCALAPPDATA = ''
    & { . $profilePath }
    Write-Host 'PASS: Two PCs, different roots; absent PC; unset LOCALAPPDATA'

    Install-StackProfileLoader -InstallPath (Join-Path $testRoot 'never-installed') -ProfilePath $profilePath -LocalAppDataPath $machineA
    Assert-ProfileLoads $profilePath $machineA '' 0
    Install-StackProfileLoader -InstallPath $rootB -ProfilePath $profilePath -LocalAppDataPath $machineA
    Assert-ProfileLoads $profilePath $machineA $rootB 12
    Write-Host 'PASS: Stale registration skips missing stack; changing roots works'

    $onlyAgents = Join-Path $testRoot 'agents-only'
    Write-Fixture (Join-Path $onlyAgents 'scripts\agent-commands.ps1') $agentStub
    Install-StackProfileLoader -InstallPath $onlyAgents -ProfilePath $profilePath -LocalAppDataPath $machineA
    Assert-ProfileLoads $profilePath $machineA $onlyAgents 4
    Write-Host 'PASS: Missing optional TTS component'

    foreach ($newline in @("`r`n", "`n")) {
        foreach ($order in @('agent-first', 'tts-first', 'tts-only')) {
            $agentBlock = '# BEGIN WINDOWS HYBRID AGENTIC STACK' + $newline +
                '# old absolute agent path' + $newline + '# END WINDOWS HYBRID AGENTIC STACK'
            $ttsBlock = '# BEGIN WINDOWS HYBRID AGENTIC STACK TTS' + $newline +
                '# old absolute TTS path' + $newline + '# END WINDOWS HYBRID AGENTIC STACK TTS'
            $before = '# unrelated ' + [char]0x00e9 + $newline + '$unrelatedBefore = 123' + $newline
            $between = $newline + '$unrelatedBetween = 456' + $newline
            $after = $newline + '$unrelatedAfter = 789' + $newline
            $blocks = switch ($order) {
                'agent-first' { $agentBlock + $between + $ttsBlock }
                'tts-first' { $ttsBlock + $between + $agentBlock }
                'tts-only' { $ttsBlock + $between }
            }
            Write-Fixture $profilePath ($before + $blocks + $after)
            Install-StackProfileLoader -InstallPath $rootA -ProfilePath $profilePath -LocalAppDataPath $machineA
            $migrated = [System.IO.File]::ReadAllText($profilePath)
            Assert-True ($migrated.StartsWith($before) -and $migrated.Contains($between) -and $migrated.EndsWith($after)) 'Unrelated text preserved verbatim'
            Assert-True (-not $migrated.Contains('old absolute')) 'Legacy bodies removed'
            Assert-True (-not $migrated.Contains('STACK TTS')) 'Separate TTS block removed'
            Assert-True ([regex]::Matches($migrated, '# BEGIN WINDOWS HYBRID AGENTIC STACK').Count -eq 1) 'One unified block'
            Assert-ProfileLoads $profilePath $machineA $rootA 12
        }
    }
    Write-Host 'PASS: Legacy migration in either order and TTS-only; CRLF/LF; unrelated Unicode text'

    $ansiCodePage = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage
    $legacyEncoding = [System.Text.Encoding]::GetEncoding($ansiCodePage)
    $legacyText = '# Legacy ANSI profile ' + [char]0x00e9 + "`r`n" + '$legacySetting = 42' + "`r`n"
    [System.IO.File]::WriteAllText($profilePath, $legacyText, $legacyEncoding)
    $legacyBytes = [System.IO.File]::ReadAllBytes($profilePath)
    Install-StackProfileLoader -InstallPath $rootA -ProfilePath $profilePath -LocalAppDataPath $machineA
    Assert-True ([System.IO.File]::ReadAllText($profilePath).StartsWith($legacyText)) 'Legacy ANSI characters preserved'
    $legacyBackups = @(Get-ChildItem -LiteralPath (Split-Path -Parent $profilePath) -Filter '*.bak.*')
    $matchingBackup = @($legacyBackups | Where-Object {
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($_.FullName)) -ceq [Convert]::ToBase64String($legacyBytes)
    })
    Assert-True ($matchingBackup.Count -gt 0) 'Original ANSI bytes backed up exactly'
    Assert-ProfileLoads $profilePath $machineA $rootA 12
    Write-Host 'PASS: Legacy ANSI profile text preserved; original bytes backed up'

    foreach ($invalid in @(
        '# BEGIN WINDOWS HYBRID AGENTIC STACK',
        '# END WINDOWS HYBRID AGENTIC STACK',
        ($agentBlock + $newline + $agentBlock),
        ($agentBlock.Replace('# END WINDOWS HYBRID AGENTIC STACK', '# END WINDOWS HYBRID AGENTIC STACK TTS'))
    )) {
        Write-Fixture $profilePath $invalid
        $localBefore = [System.IO.File]::ReadAllText($localFile)
        $rejected = $false
        try {
            Install-StackProfileLoader -InstallPath $rootB -ProfilePath $profilePath -LocalAppDataPath $machineA
        }
        catch { $rejected = $true }
        Assert-True $rejected 'Malformed markers rejected'
        Assert-True ([System.IO.File]::ReadAllText($profilePath) -ceq $invalid) 'Invalid profile untouched'
        Assert-True ([System.IO.File]::ReadAllText($localFile) -ceq $localBefore) 'Local registration untouched on invalid profile'
    }
    Write-Host 'PASS: Malformed/duplicate markers rejected before writes'

    Write-Fixture $profilePath $profileBefore
    Disable-StackProfileLoader -LocalAppDataPath $machineA
    Disable-StackProfileLoader -LocalAppDataPath $machineA
    Assert-ProfileLoads $profilePath $machineA '' 0
    Assert-ProfileLoads $profilePath $machineB $rootB 12
    Assert-True ([System.IO.File]::ReadAllText($profilePath) -ceq $profileBefore) 'Local cleanup preserves synced bootstrap'
    Write-Host 'PASS: Repeat local cleanup leaves other PC working'

    $parseErrors = @()
    Get-ChildItem -LiteralPath $testRoot -Recurse -Filter '*.ps1' |
        Where-Object { $_.FullName -ne $profilePath } |
        ForEach-Object {
            $tokens = $null
            $errorsFound = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $_.FullName, [ref]$tokens, [ref]$errorsFound)
            $parseErrors += $errorsFound
        }
    Assert-True ($parseErrors.Count -eq 0) 'Generated scripts parse'
    Write-Host 'PASS: Generated script syntax'
    Write-Host 'All profile-helper tests passed.'
}
finally {
    $env:LOCALAPPDATA = $originalLocal
    # Retain fixtures and backups for inspection; no cleanup deletes.
    Write-Host "Retained test files: $testRoot"
}
