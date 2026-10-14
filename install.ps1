#Requires -Version 5.1

<#
.SYNOPSIS
    Windows Hybrid Agentic Stack installer.

.DESCRIPTION
    Loads effective configuration, selects components,
    checks prerequisites and configures OpenCode agents.

    External prerequisites must already be installed.
    Chatterbox installation is not yet implemented.

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -Cloud

.EXAMPLE
    .\install.ps1 -Cloud -Local

.EXAMPLE
    .\install.ps1 -Local -InstallPath 'D:\AI\AgentStack'
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
$agentSetupScript = Join-Path $repoRoot 'scripts\setup-agents.ps1'

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
                Write-Host 'Please enter Y or N.' `
                    -ForegroundColor Yellow
            }
        }
    }
}

try {
    Write-Host ''
    Write-Host 'Windows Hybrid Agentic Stack'
    Write-Host '============================'
    Write-Host ''

    # Check required project scripts.
    foreach ($file in @(
        $configScript,
        $prerequisiteScript,
        $agentSetupScript
    )) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Required project script missing: $file"
        }
    }

    # Validate the effective configuration.
    & $configScript -Validate

    if ($LASTEXITCODE -ne 0) {
        throw 'Configuration validation failed.'
    }

    # Load defaults combined with optional user overrides.
    $configJson = & $configScript -Show

    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to load configuration.'
    }

    $config = ($configJson | Out-String) | ConvertFrom-Json

    if ($null -eq $config) {
        throw 'Configuration could not be parsed.'
    }

    # Explicit switches select only the specified components.
    $explicitSelection = $Cloud -or $Local -or $Voice

    if (-not $explicitSelection) {
        Write-Host ''
        Write-Host 'Select components to install:'
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

    # Resolve installation path.
    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $InstallPath = $config.installation.directory
    }

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $InstallPath = Join-Path $HOME 'AI\WindowsHybridAgenticStack'
    }

    $InstallPath = [Environment]::ExpandEnvironmentVariables(
        $InstallPath
    )

    $InstallPath = $ExecutionContext.SessionState.Path.
        GetUnresolvedProviderPathFromPSPath($InstallPath)

    # Display installation plan.
    Write-Host ''
    Write-Host 'Installation plan'
    Write-Host '-----------------'

    Write-Host "Directory:    $InstallPath"
    Write-Host "Cloud agents: $Cloud"
    Write-Host "Local agents: $Local"
    Write-Host "Voice output: $Voice"

    if ($Cloud) {
        Write-Host "Cloud model:  $($config.agents.cloud.model)"
    }

    if ($Local) {
        Write-Host "Local model:  $($config.agents.local.model)"
    }

    if ($Voice) {
        Write-Host "TTS engine:   $($config.tts.engine)"
    }

    Write-Host ''

    if (-not (Read-YesNo -Question 'Continue with installation?')) {
        Write-Host 'Installation cancelled. No changes made.'
        exit 0
    }

    # Prerequisite checks.
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
        Write-Host 'Required prerequisites are missing.' `
            -ForegroundColor Red

        Write-Host 'Follow the installation guide in README.md.'
        Write-Host 'Then rerun this installer.'

        exit 1
    }

    Write-Host ''
    Write-Host 'Prerequisite checks completed.' `
        -ForegroundColor Green

    # Configure OpenCode for selected agent types.
    if ($Cloud -or $Local) {
        Write-Host ''
        Write-Host 'Configuring OpenCode agents...'
        Write-Host ''

        $setupArguments = @{
            Cloud = [bool]$Cloud
            Local = [bool]$Local
            InstallPath = $InstallPath
            CloudModel = [string]$config.agents.cloud.model
            LocalModel = [string]$config.agents.local.model
        }

        & $agentSetupScript @setupArguments

        if ($LASTEXITCODE -ne 0) {
            throw 'OpenCode agent setup failed.'
        }
    }

    # TTS setup will be integrated in a later commit.
    if ($Voice) {
        Write-Host ''
        Write-Host 'Chatterbox installation is not implemented yet.' `
            -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host 'Installation stage completed.' `
        -ForegroundColor Green

    if ($Cloud -or $Local) {
        $openCodeConfig = Join-Path $InstallPath 'opencode.json'

        Write-Host ''
        Write-Host "OpenCode configuration: $openCodeConfig"
        Write-Host ''
        Write-Host 'To use this configuration in the current session:'
        Write-Host "`$env:OPENCODE_CONFIG = '$openCodeConfig'"
    }

    Write-Host ''
    Write-Host 'PowerShell agent commands are not yet installed.'
    Write-Host 'TTS installation will be added in a later stage.'

    exit 0
}
catch {
    Write-Host ''
    Write-Host "Installer error: $($_.Exception.Message)" `
        -ForegroundColor Red

    exit 1
}
