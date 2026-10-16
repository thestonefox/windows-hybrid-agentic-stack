#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts/installation-state.ps1')
. (Join-Path $repo 'scripts/agent-strategies.ps1') -StrategyRoot $repo
$strategies=@(Get-WhasAgentStrategies)
if($strategies.Count -ne 1 -or $strategies[0].Manifest.id -cne 'opencode'){throw 'Only the agreed OpenCode strategy should ship'}
$rejected=$false
try {Get-WhasAgentStrategy 'unavailable-runtime'|Out-Null}catch {$rejected=$true}
if(-not $rejected){throw 'An unsupported runtime was accepted'}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('whas-agent-tests-'+[guid]::NewGuid().ToString('N'))
try {
    $tracking=Start-StackInstallationTracking $fixture
    $profile=Join-Path $fixture 'agents/runtime/fixture/home/profiles/local/private.txt'
    [IO.Directory]::CreateDirectory((Split-Path -Parent $profile))|Out-Null
    [IO.File]::WriteAllText($profile,'synthetic personal data')
    [IO.File]::WriteAllText((Join-Path $fixture 'owned.txt'),'owned')
    Complete-StackInstallationTracking $tracking $true
    $state=Read-StackInstallationState $fixture
    if(@($state.Files|Where-Object {$_.Path -like 'agents/runtime/*/home/profiles/*'}).Count){throw 'Personal native profiles were tracked as disposable files'}
    if(@($state.Files|Where-Object {$_.Path -ceq 'owned.txt'}).Count -ne 1){throw 'Normal owned files were not tracked'}
    Write-Host 'PASS: OpenCode-only catalogue, unsupported runtime rejection and generic personal-profile protection'
} finally {
    $absolute=[IO.Path]::GetFullPath($fixture)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not $absolute.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $absolute) -notmatch '^whas-agent-tests-[a-f0-9]{32}$'){throw 'Unexpected cleanup target'}
    if(Test-Path -LiteralPath $absolute){Remove-Item -LiteralPath $absolute -Recurse -Force}
}
