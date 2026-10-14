#Requires -Version 5.1

<#
.SYNOPSIS
    Windows Hybrid Agentic Stack installer.

.DESCRIPTION
    Loads configuration, selects components, and checks prerequisites.

    Component installation is not yet implemented. This entry point
    currently performs preflight checks only.

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -Cloud -Local

.EXAMPLE
    .\install.ps1 -Voice -InstallPath 'D:\AI\AgentStack'
#>

[CmdletBinding()]
param(
    [switch]$Cloud,
    [switch]$Local,
    [switch]$Voice,

    [string]$InstallPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$configScript = Join-Path $repoRoot 'scripts\config.ps1'
$prerequisiteScript = Join-Path $repoRoot 'scripts\check-prerequisites.ps1'

function Read-YesNo {
    param(
        [string]$Question,
        [bool]$Default = $true
    )

    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }

    while ($true) {
        $answer = Read-Host "$Question $suffix"

        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $Default
        }

        switch ($answer.Trim().ToLowerInvariant()) {
            'y'   { return $true }
            'yes' { return $true }
            'n'   { return $false }
            'no'  { return $false }
            default {
                Write-Host 'Please enter Y or N.' -ForegroundColor Yellow
            }
        }
    }
}

try {
    Write-Host ''
    Write-Host 'Windows Hybrid Agentic Stack'
    Write-Host '============================'
    Write-Host ''

    foreach ($file in @($configScript, $prerequisiteScript)) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Required script not found: $file"
        }
    }

    # Validate configuration before using it.
    & $configScript -Validate

    if ($LASTEXITCODE -ne 0) {
        throw 'Configuration validation failed.'
    }

    # Obtain the effective configuration from the existing loader.
    $configJson = & $configScript -Show

    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to load configuration.'
    }

    $config = ($configJson | Out-String) | ConvertFrom-Json

    # Explicit component switches override interactive selection.
    $explicitSelection = $Cloud -or $Local -or $Voice

    if (-not $explicitSelection) {
        Write-Host ''
        Write-Host 'Select the components to install:'
        Write-Host ''

        $Cloud = Read-YesNo `
            -Question 'Cloud agents (OpenCode + OpenAI)?' `
            -Default ([bool]$config.agents.cloud.enabled)

        $Local = Read-YesNo `
            -Question 'Local agents (OpenCode + Ollama)?' `
            -Default ([bool]$config.agents.local.enabled)

        $Voice = Read-YesNo `
            -Question 'Voice output (Chatterbox Turbo)?' `
            -Default ([bool]$config.tts.enabled)
    }

    if (-not ($Cloud -or $Local -or $Voice)) {
        throw 'No components selected.'
    }

    # Resolve installation directory.
    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $InstallPath = $config.installation.directory
    }

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $InstallPath = Join-Path $HOME 'AI\WindowsHybridAgenticStack'
    }

    $InstallPath = [Environment]::ExpandEnvironmentVariables($InstallPath)
    $InstallPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
        $InstallPath
    )

    Write-Host ''
    Write-Host 'Installation plan'
    Write-Host '-----------------'
    Write-Host "Directory:    $InstallPath"
    Write-Host "Cloud agents: $Cloud"
    Write-Host "Local agents: $Local"
    Write-Host "Voice output: $Voice"
    Write-Host ''

    if (-not (Read-YesNo -Question 'Continue with prerequisite checks?')) {
        Write-Host 'Cancelled. No changes made.'
        exit 0
    }

    Write-Host ''
    Write-Host 'Checking prerequisites...'
    Write-Host ''

    $checkArguments = @{
        Cloud = [bool]$Cloud
        Local = [bool]$Local
        Voice = [bool]$Voice
    }

    & $prerequisiteScript @checkArguments

    if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Host 'Required prerequisites are missing.' -ForegroundColor Red
        Write-Host 'Install the missing software using the README.'
        Write-Host 'Then rerun this installer.'
        exit 1
    }

    Write-Host ''
    Write-Host 'Prerequisite checks completed.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Component installation is not implemented yet.'
    Write-Host 'No files or system settings have been changed.'
    exit 0
}
catch {
    Write-Host ''
    Write-Host "Installer error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
