#Requires -Version 5.1

<#
.SYNOPSIS
    PowerShell commands for Windows Hybrid Agentic Stack.

.DESCRIPTION
    Provides four OpenCode commands:

      agent          Cloud, read-only
      agentdo        Cloud, write-capable
      localagent     Local, read-only
      localagentdo   Local, write-capable

    Flags:
      -m, --model    Override the configured model
      -l, --log      Display full OpenCode output
      -h, --help     Show usage
      -v, --voice    Reserved for Chatterbox integration

    This file is dot-sourced into a PowerShell session.
#>

param(
    [string]$InstallPath
)

$script:AgentStackRepository = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = Join-Path $HOME 'AI\WindowsHybridAgenticStack'
}

$script:AgentStackInstallPath = $InstallPath

function Show-AgentHelp {
    param([string]$CommandName)

    $isLocal = $CommandName -in @('localagent', 'localagentdo')

    $exampleModel = if ($isLocal) {
        'qwen3:8b'
    }
    else {
        'openai/gpt-6-luna'
    }

    Write-Host ''
    Write-Host "Usage: $CommandName [OPTIONS] `"prompt`""
    Write-Host ''
    Write-Host 'Options:'
    Write-Host '  -m, --model MODEL  Override the configured model'
    Write-Host '  -l, --log          Show full OpenCode output'
    Write-Host '  -h, --help         Show this help'
    Write-Host '  -v, --voice        Voice support (not installed yet)'
    Write-Host ''
    Write-Host 'Examples:'
    Write-Host "  $CommandName `"Explain this code`""
    Write-Host "  $CommandName -m $exampleModel `"Explain this code`""
    Write-Host "  $CommandName -l `"Explain this code`""
    Write-Host ''
}

function Invoke-AgentStackTask {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'agent',
            'agentdo',
            'localagent',
            'localagentdo'
        )]
        [string]$Kind,

        [object[]]$Arguments = @()
    )

    $isLocal = $Kind -in @('localagent', 'localagentdo')
    $canWrite = $Kind -in @('agentdo', 'localagentdo')

    $agentName = if ($canWrite) {
        'ps-write'
    }
    else {
        'ps-read'
    }

    $verboseOutput = $false
    $modelOverride = $null
    $promptParts = @()

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $argument = [string]$Arguments[$i]

        switch ($argument) {
            { $_ -in @('-h', '--help') } {
                Show-AgentHelp -CommandName $Kind
                return
            }

            { $_ -in @('-l', '--log') } {
                $verboseOutput = $true
                break
            }

            { $_ -in @('-m', '--model') } {
                if ($i + 1 -ge $Arguments.Count) {
                    Write-Error 'Missing model name after -m'
                    return
                }

                $i++
                $modelOverride = [string]$Arguments[$i]

                if ([string]::IsNullOrWhiteSpace($modelOverride) -or
                    $modelOverride.StartsWith('-')) {
                    Write-Error 'Invalid model name after -m'
                    return
                }

                break
            }

            { $_ -in @('-v', '--voice') } {
                Write-Error (
                    'Voice support is not installed yet. ' +
                    'Chatterbox integration will be added later.'
                )
                return
            }

            default {
                if ($argument.StartsWith('-')) {
                    Write-Error "Unknown option: $argument"
                    return
                }

                $promptParts += $argument
            }
        }
    }

    if ($promptParts.Count -eq 0) {
        Show-AgentHelp -CommandName $Kind
        return
    }

    $configScript = Join-Path `
        $script:AgentStackRepository 'scripts\config.ps1'

    if (-not (Test-Path -LiteralPath $configScript -PathType Leaf)) {
        Write-Error "Configuration loader not found: $configScript"
        return
    }

    $configJson = & $configScript -Show

    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Unable to load agent configuration.'
        return
    }

    try {
        $config = ($configJson | Out-String) | ConvertFrom-Json
    }
    catch {
        Write-Error "Invalid configuration: $($_.Exception.Message)"
        return
    }

    if ($isLocal) {
        $provider = [string]$config.agents.local.provider
        $model = [string]$config.agents.local.model
    }
    else {
        $provider = [string]$config.agents.cloud.provider
        $model = [string]$config.agents.cloud.model
    }

    if (-not [string]::IsNullOrWhiteSpace($modelOverride)) {
        $model = $modelOverride
    }

    if ($model -notmatch '/') {
        $model = "$provider/$model"
    }

    $openCodeConfig = Join-Path `
        $script:AgentStackInstallPath 'opencode.json'

    if (-not (Test-Path -LiteralPath $openCodeConfig -PathType Leaf)) {
        Write-Error (
            "OpenCode configuration not found: $openCodeConfig. " +
            'Run the stack installer for the selected component.'
        )
        return
    }

    if ($null -eq (Get-Command opencode -ErrorAction SilentlyContinue)) {
        Write-Error 'OpenCode CLI was not found.'
        return
    }

    $prompt = $promptParts -join ' '

    $previousConfig = $env:OPENCODE_CONFIG

    # Windows PowerShell 5.1 may otherwise decode UTF-8
    # native application output using the console code page.
    $previousConsoleEncoding = [Console]::OutputEncoding
    $previousOutputEncoding = $OutputEncoding

    try {
        $env:OPENCODE_CONFIG = $openCodeConfig

        $utf8 = New-Object System.Text.UTF8Encoding($false)

        [Console]::OutputEncoding = $utf8
        $OutputEncoding = $utf8

        if ($verboseOutput) {
            & opencode run `
                --agent $agentName `
                --model $model `
                $prompt

            return
        }

        # Show only the final answer from OpenCode JSON events.
        $lastText = $null
        $errorsFound = @()

        & opencode run `
            --agent $agentName `
            --model $model `
            --format json `
            $prompt 2>&1 |
            ForEach-Object {
                $line = [string]$_

                try {
                    $eventData = $line |
                        ConvertFrom-Json -ErrorAction Stop

                    if ($eventData.type -eq 'text' -and
                        $eventData.part.text) {
                        $lastText = $eventData.part.text
                    }

                    if ($eventData.type -eq 'error') {
                        $errorsFound += (
                            $eventData |
                                ConvertTo-Json -Depth 10 -Compress
                        )
                    }
                }
                catch {
                    if ($line.Trim()) {
                        $errorsFound += $line
                    }
                }
            }

        if ($lastText) {
            Write-Output $lastText
        }

        if ($errorsFound.Count -gt 0) {
            $errorsFound | ForEach-Object {
                Write-Warning $_
            }
        }

        if (-not $lastText -and $errorsFound.Count -eq 0) {
            Write-Warning (
                'No answer received. ' +
                'Retry with -l to see the full output.'
            )
        }
    }
    finally {
        $env:OPENCODE_CONFIG = $previousConfig
        [Console]::OutputEncoding = $previousConsoleEncoding
        $OutputEncoding = $previousOutputEncoding
    }
}

function agent {
    Invoke-AgentStackTask -Kind 'agent' -Arguments $args
}

function agentdo {
    Invoke-AgentStackTask -Kind 'agentdo' -Arguments $args
}

function localagent {
    Invoke-AgentStackTask -Kind 'localagent' -Arguments $args
}

function localagentdo {
    Invoke-AgentStackTask -Kind 'localagentdo' -Arguments $args
}
