#Requires -Version 5.1

<#
.SYNOPSIS
    Manage Windows Hybrid Agentic Stack configuration.

.DESCRIPTION
    Load config/defaults.json and optionally merge
    config/config.json.

    -Show      Display the effective configuration.
    -Validate  Validate without changing files.
    -Init      Create config/config.json from the defaults.

    No config/config.json is required.

.EXAMPLE
    .\scripts\config.ps1 -Show

.EXAMPLE
    .\scripts\config.ps1 -Validate

.EXAMPLE
    .\scripts\config.ps1 -Init
#>

[CmdletBinding(DefaultParameterSetName = 'Show')]
param(
    [Parameter(ParameterSetName = 'Show')]
    [switch]$Show,

    [Parameter(ParameterSetName = 'Validate')]
    [switch]$Validate,

    [Parameter(ParameterSetName = 'Init')]
    [switch]$Init,

    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$configDirectory = Join-Path $repoRoot 'config'
$defaultsPath = Join-Path $configDirectory 'defaults.json'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $configDirectory 'config.json'
}

if (-not ($null -ne ('WindowsHybridAgenticStack.SetupRuntime' -as [type]) -and [WindowsHybridAgenticStack.SetupRuntime]::IsHosting)) {
    . (Join-Path $PSScriptRoot 'script-invocation.ps1')
}
. (Get-StackSetupScript (Join-Path $PSScriptRoot 'configuration.ps1'))

try {
    if (-not (Test-Path -LiteralPath $defaultsPath -PathType Leaf)) {
        throw "Defaults file not found: $defaultsPath"
    }

    $config = Get-Content -LiteralPath $defaultsPath -Raw |
        ConvertFrom-Json
    if (-not $config.interaction) { $config | Add-Member -NotePropertyName interaction -NotePropertyValue ([pscustomobject]@{location='cloud';runtime='opencode';speech=$false}) }
    if ($config.tts -and -not $config.tts.PSObject.Properties['voiceDefaults']) { $config.tts | Add-Member -NotePropertyName voiceDefaults -NotePropertyValue ([pscustomobject]@{}) }

    if ($config -isnot [pscustomobject]) {
        throw 'Defaults must contain a JSON object'
    }

    if ($Init) {
        if (Test-Path -LiteralPath $ConfigPath) {
            throw "Configuration already exists: $ConfigPath"
        }

        $destinationDirectory = Split-Path -Parent $ConfigPath

        if ($destinationDirectory -and
            -not (Test-Path -LiteralPath $destinationDirectory)) {
            throw "Directory does not exist: $destinationDirectory"
        }

        Copy-Item `
            -LiteralPath $defaultsPath `
            -Destination $ConfigPath

        Write-Host "Created configuration: $ConfigPath"
    }

    $config = Get-StackConfiguration -Root $repoRoot -ConfigPath $ConfigPath

    if ($Show) {
        $config | ConvertTo-Json -Depth 20
    }
    elseif ($Validate) {
        Write-Host 'Configuration is valid.' `
            -ForegroundColor Green

        if (-not (Test-Path -LiteralPath $ConfigPath)) {
            Write-Host (
                'Using built-in defaults (no config/config.json).'
            )
        }
        else {
            Write-Host "Using user configuration: $ConfigPath"
        }
    }
    elseif ($Init) {
        Write-Host 'Configuration is valid.' `
            -ForegroundColor Green
    }

    exit 0
}
catch {
    Write-Host "Configuration error: $($_.Exception.Message)" `
        -ForegroundColor Red

    exit 1
}
