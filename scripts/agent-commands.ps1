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
      -v, --voice    Speak the final answer using Chatterbox

    This file is dot-sourced into a PowerShell session.
#>

param(
    [string]$InstallPath
)

$script:AgentStackRepository = if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    Split-Path -Parent $PSScriptRoot
} else { $InstallPath }

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
        'provider/model'
    }

    Write-Host ''
    Write-Host "Usage: $CommandName [OPTIONS] `"prompt`""
    Write-Host ''
    Write-Host 'Options:'
    Write-Host '  -m, --model MODEL  Override the configured model'
    Write-Host '  -l, --log          Show full OpenCode output'
    Write-Host '  -h, --help         Show this help'
    Write-Host '  -v, --voice        Speak the final answer'
    Write-Host '                      Optionally specify a voice name'
    Write-Host ''
    Write-Host 'Examples:'
    Write-Host "  $CommandName `"Explain this code`""
    Write-Host "  $CommandName -m $exampleModel `"Explain this code`""
    Write-Host "  $CommandName -l `"Explain this code`""
    Write-Host "  $CommandName -v `"Explain this code`""
    Write-Host "  $CommandName -v default `"Explain this code`""
    Write-Host "  $CommandName --voice default `"Explain this code`""
    Write-Host ''
    Write-Host 'Voice uses the default voice unless a name is supplied.'
    Write-Host 'For a custom voice, put its name immediately before'
    Write-Host 'the quoted prompt.'
    Write-Host ''
}

function ConvertTo-AgentAnswer {
    param([string]$Text, [string]$Prompt)
    # Remove only the observed OpenCode help footer when echoed as a trailing
    # standalone block. Keep raw --log events and intentional markup examples.
    if ($Prompt -match '(?i)system-reminder|Remember to use /help') { return $Text }
    $pattern = '(?s)(?:\r?\n|\A)[ \t]*<system-reminder>\s*Remember to use /help for assistance or report issues at https://github\.com/anomalyco/opencode/issues\s*</system-reminder>\s*\z'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $Text }
    $answer = $Text.Substring(0, $match.Index)
    # A trailing example inside an unclosed Markdown fence is user content.
    if (([regex]::Matches($answer, '(?m)^\s*```').Count % 2) -or
        ([regex]::Matches($answer, '(?m)^\s*~~~').Count % 2)) { return $Text }
    return $answer.TrimEnd()
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
    $voiceEnabled = $false
    $voiceName = $null
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

                if (
                    [string]::IsNullOrWhiteSpace($modelOverride) -or
                    $modelOverride.StartsWith('-')
                ) {
                    Write-Error 'Invalid model name after -m'
                    return
                }

                break
            }

            { $_ -in @('-v', '--voice') } {
                $voiceEnabled = $true

                # A voice name is optional.
                #
                # -v "prompt"
                #     Uses the configured default voice.
                #
                # -v default "prompt"
                #     Uses the explicitly selected voice.
                #
                # Only consume the next argument as a voice name
                # when a separate prompt argument follows it.
                if ($i + 2 -lt $Arguments.Count) {
                    $candidate = [string]$Arguments[$i + 1]
                    $following = [string]$Arguments[$i + 2]

                    if (
                        $candidate -cmatch `
                            '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$' -and
                        -not $following.StartsWith('-')
                    ) {
                        $voiceName = $candidate
                        $i++
                    }
                }

                break
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

    try {
        if ($null -eq (Get-Command Get-StackConfiguration -ErrorAction Ignore)) {
            . (Join-Path $script:AgentStackRepository 'scripts\configuration.ps1')
        }
        $config = Get-StackConfiguration -Root $script:AgentStackRepository
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

    if (-not [string]::IsNullOrWhiteSpace($model) -and $model -notmatch '/') {
        if ([string]::IsNullOrWhiteSpace($provider)) {
            Write-Error 'Use a fully qualified model: provider/model.'
            return
        }
        $model = "$provider/$model"
    }

    # Let OpenCode select its model unless a model was explicitly requested.
    $modelArguments = @()
    if (-not [string]::IsNullOrWhiteSpace($model)) {
        $modelArguments = @('--model', $model)
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

    if ($voiceEnabled) {
        # When voice support is already loaded, use it directly.
        # This also allows a mock tts-say function during tests.
        if ($null -eq (
            Get-Command tts-say -CommandType Function -ErrorAction SilentlyContinue
        )) {
            $ttsScript = Join-Path `
                $script:AgentStackInstallPath 'tts\tts.ps1'

            if (-not (
                Test-Path -LiteralPath $ttsScript -PathType Leaf
            )) {
                # During development, the wrapper may be present
                # in the repository before the installed runtime
                # has been updated.
                $ttsScript = Join-Path `
                    $script:AgentStackRepository 'tts\tts.ps1'
            }

            if (-not (
                Test-Path -LiteralPath $ttsScript -PathType Leaf
            )) {
                Write-Error (
                    'Chatterbox voice commands were not found. ' +
                    'Install the TTS component first.'
                )
                return
            }

            try {
                . $ttsScript -InstallPath $script:AgentStackInstallPath
            }
            catch {
                Write-Error (
                    'Could not load Chatterbox commands: ' +
                    $_.Exception.Message
                )
                return
            }
        }

        if ($null -eq (
            Get-Command tts-say -CommandType Function -ErrorAction SilentlyContinue
        )) {
            Write-Error 'Chatterbox tts-say command is unavailable.'
            return
        }

        if ([string]::IsNullOrWhiteSpace($voiceName)) {
            $voiceName = [string]$config.tts.defaultVoice
        }

        if ([string]::IsNullOrWhiteSpace($voiceName)) {
            $voiceName = 'default'
        }
    }

    $prompt = $promptParts -join ' '

    $previousConfig = $env:OPENCODE_CONFIG

    # Windows PowerShell 5.1 may otherwise decode UTF-8
    # native application output using the console code page.
    $previousConsoleEncoding = [Console]::OutputEncoding
    $previousOutputEncoding = $OutputEncoding
    $activity = $null

    try {
        if ($null -ne ('WindowsHybridAgenticStack.OperationActivity' -as [type])) {
            $activity = [WindowsHybridAgenticStack.OperationActivity]::Begin('Waiting for model response')
        }
        $env:OPENCODE_CONFIG = $openCodeConfig

        $utf8 = New-Object System.Text.UTF8Encoding($false)

        [Console]::OutputEncoding = $utf8
        $OutputEncoding = $utf8

        # Preserve the existing full-output behaviour when
        # voice support is not requested.
        if ($verboseOutput -and -not $voiceEnabled) {
            & opencode run `
                --agent $agentName `
                @modelArguments `
                $prompt

            return
        }

        # JSON events provide the final response text for TTS.
        $lastText = $null
        $errorsFound = @()
        $exitCode = 0

        & opencode run `
            --agent $agentName `
            @modelArguments `
            --format json `
            $prompt 2>&1 |
            ForEach-Object {
                $line = [string]$_

                if ($verboseOutput) {
                    # With -v -l, display the complete JSON event
                    # stream and still extract text for speech.
                    Write-Output $line
                }

                try {
                    $eventData = $line |
                        ConvertFrom-Json -ErrorAction Stop

                    if (
                        $eventData.type -eq 'text' -and
                        $eventData.part.text
                    ) {
                        if (-not $eventData.part.synthetic) {
                            $answerText = ConvertTo-AgentAnswer -Text ([string]$eventData.part.text) -Prompt $prompt
                            if (-not [string]::IsNullOrWhiteSpace($answerText)) { $lastText = $answerText }
                        }
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

        $exitCode = $LASTEXITCODE
        if ($activity) { $activity.Dispose(); $activity = $null }

        if ($lastText -and -not $verboseOutput) {
            Write-Output $lastText
        }

        if ($errorsFound.Count -gt 0) {
            $errorsFound | ForEach-Object {
                Write-Warning $_
            }
        }

        if ($exitCode -ne 0) {
            Write-Warning "OpenCode exited with code $exitCode."
            return
        }

        if (-not $lastText) {
            if ($errorsFound.Count -eq 0) {
                Write-Warning (
                    'No answer received. ' +
                    'Retry with -l to see the full output.'
                )
            }

            return
        }

        if ($voiceEnabled) {
            # Speak only the final answer, not tool logs or
            # intermediate OpenCode events.
            try {
                tts-say -Text $lastText -Voice $voiceName
            }
            catch {
                Write-Warning (
                    'The agent answered, but speech failed: ' +
                    $_.Exception.Message
                )
            }
        }
    }
    finally {
        if ($activity) { $activity.Dispose() }
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
