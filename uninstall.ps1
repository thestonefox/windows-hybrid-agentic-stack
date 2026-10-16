#Requires -Version 5.1
<#
.SYNOPSIS
    Preview or uninstall files recorded by the stack installer.
.DESCRIPTION
    Preview is the default. -Apply requests confirmation before removal.
    Custom voices, added/edited files, existing tools and models are retained.
    -RemoveManagedModels includes only installer-created, unchanged models.
.EXAMPLE
    .\uninstall.ps1
.EXAMPLE
    .\uninstall.ps1 -Apply
.EXAMPLE
    .\uninstall.ps1 -Apply -RemoveManagedModels
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param([string]$InstallPath, [switch]$Apply, [switch]$RemoveManagedModels,
    [bool]$PersistCommandPath = $true)
$ErrorActionPreference = 'Stop'
try {
    if (-not ($null -ne ('WindowsHybridAgenticStack.SetupRuntime' -as [type]) -and [WindowsHybridAgenticStack.SetupRuntime]::IsHosting)) {
        . (Join-Path $PSScriptRoot 'scripts\script-invocation.ps1')
    }
    . (Get-StackSetupScript (Join-Path $PSScriptRoot 'scripts\installation-state.ps1'))
    . (Get-StackSetupScript (Join-Path $PSScriptRoot 'scripts\command-registration.ps1'))
    . (Get-StackSetupScript (Join-Path $PSScriptRoot 'scripts\uninstall.ps1'))
    $ttsHelper = Join-Path $PSScriptRoot 'tts/strategy-management.ps1'
    if (Test-Path -LiteralPath $ttsHelper) { . (Get-StackSetupScript $ttsHelper) }
    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $registration = Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack\commands.json'
        if (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.whas-installation.json')) { $InstallPath = $PSScriptRoot }
        elseif (Test-Path -LiteralPath $registration) { $InstallPath = (Get-Content -LiteralPath $registration -Raw -Encoding UTF8 | ConvertFrom-Json).InstallPath }
        else { $InstallPath = Join-Path $HOME 'AI\WindowsHybridAgenticStack' }
    }
    $plan = Get-StackUninstallPlan -InstallPath $InstallPath -RemoveManagedModels:$RemoveManagedModels -ShowProgress
    Write-Host "Installation: $($plan.Root)"
    Write-Host "Remove tracked files: $($plan.DeleteFiles.Count); restore original files: $($plan.RestoreFiles.Count)"
    Write-Host "Preserve files: $($plan.KeepFiles.Count); unregister local commands: $($plan.UnregisterCommands)"
    Write-Host "Restore previous command registration: $($plan.RestorePreviousRegistration)"
    Write-Host "Remove verified models: $($plan.RemoveModels.Name -join ', ')"
    Write-Host "Retain models: $($plan.KeepModels -join ', ')"
    foreach ($file in $plan.DeleteFiles) { Write-Verbose "Remove: $($file.Path)" }
    foreach ($file in $plan.RestoreFiles) { Write-Verbose "Restore original: $($file.Path)" }
    foreach ($file in $plan.KeepFiles) { Write-Verbose "Retain: $file" }
    if (-not $Apply) { Write-Host 'Preview only. Use -Apply to request removal.'; exit 0 }
    Invoke-StackUninstall -Plan $plan -PersistPath $PersistCommandPath
    exit 0
}
catch { Write-Error "Uninstall failed: $($_.Exception.Message)" -ErrorAction Continue; exit 1 }
