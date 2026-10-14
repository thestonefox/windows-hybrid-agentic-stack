#Requires -Version 5.1

<#
.SYNOPSIS
    Windows Hybrid Agentic Stack installer.

.DESCRIPTION
    Loads configuration, selects components, checks prerequisites
    and installs cloud agents, local agents and Chatterbox Turbo.

    Chatterbox automatically selects CPU or CUDA PyTorch.
    External prerequisites must already be installed.

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -Cloud

.EXAMPLE
    .\install.ps1 -Local

.EXAMPLE
    .\install.ps1 -Voice

.EXAMPLE
    .\install.ps1 -Cloud -Local -Voice
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
$commandInstallScript = Join-Path $repoRoot 'scripts\install-agent-commands.ps1'
$ttsInstallScript = Join-Path $repoRoot 'tts\install-tts.ps1'

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

function Copy-StackFile {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        return
    }

    $directory = Split-Path -Parent $Destination

    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force |
            Out-Null
    }

    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        $sourceHash = (
            Get-FileHash -LiteralPath $Source -Algorithm SHA256
        ).Hash

        $destinationHash = (
            Get-FileHash -LiteralPath $Destination -Algorithm SHA256
        ).Hash

        if ($sourceHash -eq $destinationHash) {
            Write-Host "Unchanged: $Destination"
            return
        }

        $backup = "$Destination.bak.$(
            [guid]::NewGuid().ToString('N')
        )"

        Copy-Item -LiteralPath $Destination -Destination $backup
        Write-Host "Backup: $backup"
    }
    elseif (Test-Path -LiteralPath $Destination) {
        throw "Destination is not a file: $Destination"
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    Write-Host "Installed: $Destination"
}

function Install-TtsProfileLoader {
    param(
        [string]$Root
    )

    $ttsScript = Join-Path $Root 'tts\tts.ps1'

    if (-not (Test-Path -LiteralPath $ttsScript -PathType Leaf)) {
        throw "TTS command script not found: $ttsScript"
    }

    $profilePath = $PROFILE.CurrentUserCurrentHost
    $profileDirectory = Split-Path -Parent $profilePath

    if (-not (Test-Path -LiteralPath $profileDirectory)) {
        New-Item `
            -ItemType Directory `
            -Path $profileDirectory `
            -Force | Out-Null
    }

    $beginMarker = '# BEGIN WINDOWS HYBRID AGENTIC STACK TTS'
    $endMarker = '# END WINDOWS HYBRID AGENTIC STACK TTS'

    $escapedPath = $ttsScript.Replace("'", "''")

    $loader = @(
        $beginMarker
        "`$stackTtsFile = '$escapedPath'"
        'if (Test-Path -LiteralPath $stackTtsFile -PathType Leaf) {'
        '    . $stackTtsFile'
        '}'
        'Remove-Variable stackTtsFile -ErrorAction SilentlyContinue'
        $endMarker
    ) -join [Environment]::NewLine

    $existing = ''

    if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
        $existing = [System.IO.File]::ReadAllText($profilePath)
    }

    $start = $existing.IndexOf(
        $beginMarker,
        [System.StringComparison]::Ordinal
    )

    $end = $existing.IndexOf(
        $endMarker,
        [System.StringComparison]::Ordinal
    )

    if (($start -ge 0) -ne ($end -ge 0)) {
        throw 'PowerShell profile contains an incomplete TTS loader.'
    }

    if ($start -ge 0) {
        if ($end -lt $start) {
            throw 'PowerShell profile TTS loader markers are invalid.'
        }

        $end += $endMarker.Length

        $newContent = (
            $existing.Substring(0, $start) +
            $loader +
            $existing.Substring($end)
        )
    }
    else {
        $separator = ''

        if (
            $existing.Length -gt 0 -and
            -not $existing.EndsWith("`n")
        ) {
            $separator = [Environment]::NewLine
        }

        $newContent = (
            $existing +
            $separator +
            $loader +
            [Environment]::NewLine
        )
    }

    if ($newContent -ceq $existing) {
        Write-Host 'PowerShell TTS profile loader is unchanged.'
        return
    }

    if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
        $backup = "$profilePath.bak.$(
            [guid]::NewGuid().ToString('N')
        )"

        Copy-Item `
            -LiteralPath $profilePath `
            -Destination $backup `
            -ErrorAction Stop

        Write-Host "Profile backup: $backup"
    }

    [System.IO.File]::WriteAllText(
        $profilePath,
        $newContent,
        (New-Object System.Text.UTF8Encoding($false))
    )

    Write-Host "TTS commands registered in: $profilePath"
}

try {
    Write-Host ''
    Write-Host 'Windows Hybrid Agentic Stack'
    Write-Host '============================'
    Write-Host ''

    foreach ($file in @($configScript, $prerequisiteScript)) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Required project script missing: $file"
        }
    }

    & $configScript -Validate

    if ($LASTEXITCODE -ne 0) {
        throw 'Configuration validation failed.'
    }

    $configJson = & $configScript -Show

    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to load configuration.'
    }

    $config = ($configJson | Out-String) | ConvertFrom-Json

    if ($null -eq $config) {
        throw 'Configuration could not be parsed.'
    }

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

    if ($Cloud -or $Local) {
        foreach ($file in @($agentSetupScript, $commandInstallScript)) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                throw "Required project script missing: $file"
            }
        }
    }

    if ($Voice) {
        if (-not (Test-Path -LiteralPath $ttsInstallScript -PathType Leaf)) {
            throw "Required TTS installer missing: $ttsInstallScript"
        }

        if ($config.tts.engine -ne 'chatterbox-turbo') {
            throw "Unsupported TTS engine: $($config.tts.engine)"
        }
    }

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $InstallPath = [string]$config.installation.directory
    }

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $InstallPath = Join-Path $HOME 'AI\WindowsHybridAgenticStack'
    }

    $InstallPath = [Environment]::ExpandEnvironmentVariables(
        $InstallPath
    )

    if ($InstallPath -match '^\$HOME(?=[\\/]|$)') {
        $InstallPath = $HOME + $InstallPath.Substring(5)
    }

    $InstallPath = $ExecutionContext.SessionState.Path.
        GetUnresolvedProviderPathFromPSPath($InstallPath)

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
        Write-Host "TTS device:   $($config.tts.device)"
    }

    Write-Host ''

    if (-not (Read-YesNo -Question 'Continue with installation?')) {
        Write-Host 'Installation cancelled. No changes made.'
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
        Write-Host 'Required prerequisites are missing.' `
            -ForegroundColor Red
        Write-Host 'Follow the installation guide in README.md.'
        Write-Host 'Then rerun this installer.'
        exit 1
    }

    Write-Host ''
    Write-Host 'Prerequisite checks completed.' `
        -ForegroundColor Green

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

        Write-Host ''
        Write-Host 'Installing PowerShell agent commands...'
        Write-Host ''

        & $commandInstallScript -InstallPath $InstallPath

        if ($LASTEXITCODE -ne 0) {
            throw 'PowerShell agent command installation failed.'
        }
    }

    if ($Voice) {
        Write-Host ''
        Write-Host 'Installing Chatterbox Turbo...'
        Write-Host ''

        & $ttsInstallScript `
            -InstallPath $InstallPath `
            -Device ([string]$config.tts.device)

        if ($LASTEXITCODE -ne 0) {
            throw 'Chatterbox Turbo installation failed.'
        }

        # Keep the installed runtime configuration alongside TTS.
        # Existing files are preserved with a backup on changes.
        Copy-StackFile `
            -Source (Join-Path $repoRoot 'config\defaults.json') `
            -Destination (Join-Path $InstallPath 'config\defaults.json')

        Copy-StackFile `
            -Source (Join-Path $repoRoot 'config\config.json') `
            -Destination (Join-Path $InstallPath 'config\config.json')

        Install-TtsProfileLoader -Root $InstallPath
    }

    Write-Host ''
    Write-Host 'Installation completed.' -ForegroundColor Green

    if ($Cloud -or $Local) {
        $openCodeConfig = Join-Path $InstallPath 'opencode.json'

        Write-Host ''
        Write-Host "OpenCode configuration: $openCodeConfig"
        Write-Host ''
        Write-Host 'Open a new Windows PowerShell window to use:'
        Write-Host '  agent'
        Write-Host '  agentdo'
        Write-Host '  localagent'
        Write-Host '  localagentdo'
    }

    if ($Voice) {
        Write-Host ''
        Write-Host 'Open a new Windows PowerShell window to use:'
        Write-Host '  tts-start'
        Write-Host '  tts-stop'
        Write-Host '  tts-status'
        Write-Host '  tts-say'
        Write-Host '  tts-voice-list'
        Write-Host '  tts-voice-add'
        Write-Host '  tts-voice-remove'
        Write-Host '  tts-voice-test'
    }

    exit 0
}
catch {
    Write-Host ''
    Write-Host "Installer error: $($_.Exception.Message)" `
        -ForegroundColor Red

    exit 1
}
