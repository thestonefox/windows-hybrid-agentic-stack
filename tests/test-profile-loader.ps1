#Requires -Version 5.1
# Legacy migration tests use only disposable profiles.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\profile-loader.ps1')
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('whas-profile-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$profilePath = Join-Path $testRoot 'profile.ps1'
function Write-Fixture {
    param([AllowEmptyString()][string]$Text)
    [IO.File]::WriteAllText($profilePath, $Text, (New-Object Text.UTF8Encoding($true)))
}
function Assert-Backup {
    param([string]$Original)
    $matches = @(Get-ChildItem -LiteralPath $testRoot -Filter '*.bak.*' | Where-Object {
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($_.FullName)) -ceq $Original
    })
    Assert-True ($matches.Count -gt 0) 'Original bytes backed up exactly'
}
Write-Host "Test files: $testRoot"
Remove-StackLegacyProfileLoader -ProfilePath $profilePath
Assert-True (-not (Test-Path -LiteralPath $profilePath)) 'Absent profile is not created'
Write-Fixture ('# unrelated ' + [char]0x00e9 + "`r`n")
$before = (Get-FileHash -LiteralPath $profilePath).Hash
$time = (Get-Item -LiteralPath $profilePath).LastWriteTimeUtc
Remove-StackLegacyProfileLoader -ProfilePath $profilePath
Assert-True ((Get-FileHash -LiteralPath $profilePath).Hash -ceq $before) 'Unrelated profile bytes unchanged'
Assert-True ((Get-Item -LiteralPath $profilePath).LastWriteTimeUtc -eq $time) 'Unrelated timestamp unchanged'
Write-Host 'PASS: Absent and unrelated profiles left untouched'
foreach ($newline in @("`r`n", "`n")) {
    $agent = '# BEGIN WINDOWS HYBRID AGENTIC STACK' + $newline + '# legacy' + $newline + '# END WINDOWS HYBRID AGENTIC STACK'
    $tts = '# BEGIN WINDOWS HYBRID AGENTIC STACK TTS' + $newline + '# legacy TTS' + $newline + '# END WINDOWS HYBRID AGENTIC STACK TTS'
    foreach ($order in @('agent-first','tts-first','tts-only')) {
        $beforeText = '# unrelated ' + [char]0x00e9 + $newline
        $between = $newline + '$unrelated = 42' + $newline
        $after = $newline + '# trailing text' + $newline
        $blocks = switch ($order) {
            'agent-first' { $agent + $between + $tts }
            'tts-first' { $tts + $between + $agent }
            'tts-only' { $tts + $between }
        }
        Write-Fixture ($beforeText + $blocks + $after)
        $original = [Convert]::ToBase64String([IO.File]::ReadAllBytes($profilePath))
        Remove-StackLegacyProfileLoader -ProfilePath $profilePath
        Assert-True ([IO.File]::ReadAllText($profilePath) -ceq ($beforeText + $between + $after)) 'Only exact managed blocks removed'
        Assert-Backup $original
        $hash = (Get-FileHash -LiteralPath $profilePath).Hash
        $backupCount = @(Get-ChildItem -LiteralPath $testRoot -Filter '*.bak.*').Count
        Remove-StackLegacyProfileLoader -ProfilePath $profilePath
        Assert-True ((Get-FileHash -LiteralPath $profilePath).Hash -ceq $hash) 'Repeat migration unchanged'
        Assert-True (@(Get-ChildItem -LiteralPath $testRoot -Filter '*.bak.*').Count -eq $backupCount) 'Repeat creates no backups'
    }
}
Write-Host 'PASS: Both legacy orders, TTS-only, CRLF/LF, Unicode, exact backups and repeat migration'
$encoding = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage)
$text = '# ANSI ' + [char]0x00e9 + "`r`n" + $agent
[IO.File]::WriteAllText($profilePath, $text, $encoding)
$original = [Convert]::ToBase64String([IO.File]::ReadAllBytes($profilePath))
Remove-StackLegacyProfileLoader -ProfilePath $profilePath
Assert-True ([IO.File]::ReadAllText($profilePath) -ceq ('# ANSI ' + [char]0x00e9 + "`r`n")) 'ANSI text preserved'
Assert-Backup $original
Write-Fixture ("`r`n" + $agent + "`r`n" + $tts + "`r`n")
$original = [Convert]::ToBase64String([IO.File]::ReadAllBytes($profilePath))
Remove-StackLegacyProfileLoader -ProfilePath $profilePath
Assert-True (-not (Test-Path -LiteralPath $profilePath)) 'Managed-only profile removed instead of leaving blocked empty script'
Assert-Backup $original
Write-Host 'PASS: ANSI preservation and managed-only profile removal'
foreach ($invalid in @('# BEGIN WINDOWS HYBRID AGENTIC STACK', '# END WINDOWS HYBRID AGENTIC STACK',
    ($agent + "`n" + $agent), ($agent.Replace('# END WINDOWS HYBRID AGENTIC STACK','# END WINDOWS HYBRID AGENTIC STACK TTS')))) {
    Write-Fixture $invalid
    $before = (Get-FileHash -LiteralPath $profilePath).Hash
    $rejected = $false
    try { Remove-StackLegacyProfileLoader -ProfilePath $profilePath } catch { $rejected = $true }
    Assert-True $rejected 'Malformed markers rejected'
    Assert-True ((Get-FileHash -LiteralPath $profilePath).Hash -ceq $before) 'Malformed profile unchanged'
}
Write-Host 'PASS: Incomplete, duplicate and mismatched markers rejected before writes'
Write-Host 'All legacy profile migration tests passed.'