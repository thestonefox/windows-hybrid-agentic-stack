#Requires -Version 5.1
# Exercise the real CLI against isolated tracked files and a fake model API.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts/installation-state.ps1')
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('whas-uninstall-cli-' + [guid]::NewGuid().ToString('N'))
$inventoryPath = Join-Path $fixtureRoot 'models.json'
$script:FixtureModels = @()
function Get-StackOllamaModels { return $script:FixtureModels }
function Assert-True {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw "FAIL: $Message" }
}
try {
    [IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
    foreach ($case in @('default','retain','legacy')) {
        $root = Join-Path $fixtureRoot $case
        $name = 'whas-cli-' + $case + '-ctx4096'
        $tag = $name + ':latest'
        $script:FixtureModels = @([pscustomobject]@{name='original:latest';digest=('a'*64)})
        $session = Start-StackInstallationTracking $root -ManagedModelName $name
        foreach ($relative in @('uninstall.ps1','scripts/script-invocation.ps1','scripts/installation-state.ps1','scripts/command-registration.ps1','scripts/uninstall.ps1')) {
            $dest = Join-Path $root $relative
            [IO.Directory]::CreateDirectory((Split-Path -Parent $dest)) | Out-Null
            Copy-Item -LiteralPath (Join-Path $repo $relative) -Destination $dest
        }
        $helperPath = Join-Path $root 'scripts/uninstall.ps1'
        $receiptLiteral = "'" + (Join-Path $fixtureRoot 'receipts').Replace("'", "''") + "'"
        $helperText = [IO.File]::ReadAllText($helperPath).Replace("(Join-Path `$env:USERPROFILE 'WHAS-UninstallReceipts')", $receiptLiteral)
        [IO.File]::WriteAllText($helperPath, $helperText)
        $script:FixtureModels += [pscustomobject]@{name=$tag;digest=('b'*64)}
        [IO.File]::WriteAllText($inventoryPath, (ConvertTo-Json -InputObject @($script:FixtureModels)))
        $literalInventory = "'" + $inventoryPath.Replace("'", "''") + "'"
        # Only fixture copies are patched. No real Ollama requests are possible.
        $mock = @"
function Get-StackOllamaModels {
    `$models = Get-Content -LiteralPath $literalInventory -Raw | ConvertFrom-Json
    foreach (`$model in `$models) { `$model }
}
function Invoke-RestMethod {
    param(`$Uri,`$Method,`$ContentType,`$Body,`$TimeoutSec)
    `$request = `$Body | ConvertFrom-Json
    if (`$request.model -cne '$tag') { throw 'Unexpected model request' }
    if (`$Uri -eq 'http://127.0.0.1:11434/api/delete' -and `$Method -eq 'Delete') {
        `$remaining = @(Get-StackOllamaModels | Where-Object name -cne '$tag')
        [IO.File]::WriteAllText($literalInventory, (ConvertTo-Json -InputObject `$remaining))
    } elseif (`$Uri -ne 'http://127.0.0.1:11434/api/generate') { throw 'Unexpected network request' }
    return @{}
}
"@
        Add-Content -LiteralPath (Join-Path $root 'scripts/installation-state.ps1') -Value $mock -Encoding UTF8
        Complete-StackInstallationTracking $session $true
        $entry = Join-Path $root 'uninstall.ps1'
        $options = @{InstallPath=$root;PersistCommandPath=$false}
        if ($case -eq 'retain') { $options.RetainManagedModels = $true }
        if ($case -eq 'legacy') { $options.RemoveManagedModels = $true }
        $preview = @(& $entry @options 6>&1)
        Assert-True ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $root)) 'Preview does not remove installation'
        $previewModels = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
        Assert-True (@($previewModels).Count -eq 2) 'Preview does not remove models'
        if ($case -eq 'retain') {
            Assert-True (($preview -join "`n") -match ('Retain models: ' + [regex]::Escape($tag))) 'Retain option is reflected in preview'
        } else {
            Assert-True (($preview -join "`n") -match ('Remove verified models: ' + [regex]::Escape($tag))) 'Default and legacy option preview managed-model removal'
        }
        $apply = @(& $entry @options -Apply -Confirm:$false 6>&1)
        Assert-True ($LASTEXITCODE -eq 0 -and -not (Test-Path -LiteralPath $root)) 'Apply removes tracked installation'
        $remaining = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
        $expected = if ($case -eq 'retain') { 2 } else { 1 }
        Assert-True (@($remaining).Count -eq $expected) 'Default removal, explicit retention and legacy option work'
        Assert-True (@($remaining | Where-Object name -ceq 'original:latest').Count -eq 1) 'Original model survives'
        Assert-True (($apply -join "`n") -like '*Removing tracked files:*') 'CLI displays cleanup progress'
        Write-Host "PASS: $case preview/apply, model ownership and progress"
    }
    Write-Host 'All isolated uninstall CLI tests passed.'
}
finally {
    # This exact, generated fixture root contains only files created by this test.
    $absolute = [IO.Path]::GetFullPath($fixtureRoot)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $absolute.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $absolute) -notmatch '^whas-uninstall-cli-[a-f0-9]{32}$') { throw 'Unexpected fixture cleanup path' }
    if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
