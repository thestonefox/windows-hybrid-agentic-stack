#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts/installation-state.ps1')
. (Join-Path $repo 'scripts/command-registration.ps1')
. (Join-Path $repo 'scripts/uninstall.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('whas-multiple-models-'+[guid]::NewGuid().ToString('N'))
$script:inventory=@([pscustomobject]@{name='existing:latest';digest=('a'*64)})
function Get-StackOllamaModels { return $script:inventory }
try {
    $session=Start-StackInstallationTracking (Join-Path $fixture 'installation') -ManagedModelNames @('existing','new:small','whas-new-small-ctx4096')
    $script:inventory+=@([pscustomobject]@{name='new:small';digest=('b'*64)},[pscustomobject]@{name='whas-new-small-ctx4096:latest';digest=('c'*64)})
    Complete-StackInstallationTracking $session $true
    $plan=Get-StackUninstallPlan $session.Root -RemoveManagedModels
    if($plan.RemoveModels.Count -ne 2 -or $plan.RemoveModels.Name -contains 'existing:latest') { throw 'Multiple-model ownership did not preserve existing models' }
    $script:inventory[1].digest='d'*64
    $changed=Get-StackUninstallPlan $session.Root -RemoveManagedModels
    if($changed.RemoveModels.Count -ne 1 -or $changed.RemoveModels[0].Name -ne 'whas-new-small-ctx4096:latest') { throw 'Changed source model was not retained' }
    $retained=Get-StackUninstallPlan $session.Root
    if($retained.RemoveModels.Count) { throw 'Retain-models planning removed a model' }
    $state=Read-StackInstallationState $session.Root
    if(@($state.Models|Where-Object { $_.Kind -eq 'Source' }).Count -ne 2) { throw 'Source model metadata missing' }
    Write-Host 'PASS: Multiple source/derived models, existing-model preservation, digest changes and retention'
} finally {
    $absolute=[IO.Path]::GetFullPath($fixture)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not $absolute.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $absolute) -notmatch '^whas-multiple-models-[a-f0-9]{32}$') { throw 'Unexpected fixture cleanup' }
    if(Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
