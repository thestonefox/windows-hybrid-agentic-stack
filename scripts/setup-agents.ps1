#Requires -Version 5.1

<#
.SYNOPSIS
    Configure OpenCode and Ollama agents.

.DESCRIPTION
    Creates or updates a stack-specific OpenCode configuration.

    Preserves existing components and unrelated settings.
    Does not modify global OpenCode configuration.

    Downloads missing Ollama models with confirmation.
    Validates proposed configuration before saving it.
#>

[CmdletBinding()]
param(
    [switch]$Cloud,
    [switch]$Local,

    [Parameter(Mandatory = $true)]
    [string]$InstallPath,

    [string]$CloudModel = 'openai/gpt-6-luna',
    [string]$LocalModel = 'qwen3:8b'
)

$ErrorActionPreference = 'Stop'

function Confirm-Action {
    param([string]$Question)

    while ($true) {
        $answer = Read-Host "$Question [Y/n]"

        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $true
        }

        switch ($answer.Trim().ToLowerInvariant()) {
            'y'   { return $true }
            'yes' { return $true }
            'n'   { return $false }
            'no'  { return $false }
        }

        Write-Host 'Enter Y or N.' -ForegroundColor Yellow
    }
}

function Set-JsonProperty {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowNull()]
        [object]$Value
    )

    if ($null -ne $Object.PSObject.Properties[$Name]) {
        $Object.PSObject.Properties[$Name].Value = $Value
    }
    else {
        $Object | Add-Member `
            -MemberType NoteProperty `
            -Name $Name `
            -Value $Value
    }
}

function Test-OllamaModel {
    param([string]$Name)

    try {
        $response = Invoke-RestMethod `
            -Uri 'http://127.0.0.1:11434/api/tags' `
            -TimeoutSec 10 `
            -ErrorAction Stop
    }
    catch {
        throw 'Cannot connect to Ollama at 127.0.0.1:11434.'
    }

    $expected = if ($Name.Contains(':')) {
        $Name
    }
    else {
        "${Name}:latest"
    }

    foreach ($model in @($response.models)) {
        if ($model.name -eq $expected) {
            return $true
        }
    }

    return $false
}

function Assert-OllamaProvider {
    param([pscustomobject]$Provider)

    if ($Provider.npm -ne '@ai-sdk/openai-compatible') {
        throw 'Existing Ollama provider uses a different SDK.'
    }

    if ($null -eq $Provider.options -or
        $Provider.options -isnot [pscustomobject]) {
        throw 'Existing Ollama provider has invalid options.'
    }

    $baseUrl = [string]$Provider.options.baseURL

    if ($baseUrl -notin @(
        'http://127.0.0.1:11434/v1',
        'http://localhost:11434/v1'
    )) {
        throw "Existing Ollama provider has a different URL: $baseUrl"
    }

    if ($null -eq $Provider.models -or
        $Provider.models -isnot [pscustomobject]) {
        throw 'Existing Ollama provider has invalid models.'
    }
}

$temporaryPath = $null

try {
    if (-not ($Cloud -or $Local)) {
        Write-Host 'No AI agent components selected.'
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        throw 'InstallPath cannot be empty.'
    }

    if ($Cloud -and
        [string]::IsNullOrWhiteSpace($CloudModel)) {
        throw 'Cloud model cannot be empty.'
    }

    if ($Local -and
        [string]::IsNullOrWhiteSpace($LocalModel)) {
        throw 'Local model cannot be empty.'
    }

    $InstallPath = [Environment]::ExpandEnvironmentVariables(
        $InstallPath
    )

    $InstallPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
        $InstallPath
    )

    $configPath = Join-Path $InstallPath 'opencode.json'
    $existingFile = Test-Path -LiteralPath $configPath

    if ($existingFile) {
        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
            throw "Configuration path is not a file: $configPath"
        }

        $originalJson = Get-Content `
            -LiteralPath $configPath -Raw

        $config = $originalJson | ConvertFrom-Json

        if ($config -isnot [pscustomobject]) {
            throw 'Existing OpenCode configuration is not an object.'
        }

        Write-Host 'Loading existing OpenCode configuration.'
    }
    else {
        $originalJson = $null

        $config = [pscustomobject]@{
            '$schema' = 'https://opencode.ai/config.json'
        }

        Write-Host 'Creating new OpenCode configuration.'
    }

    # Preserve the existing default when adding local agents.
    # When cloud agents are explicitly selected, prefer the
    # configured cloud model as the default.
    if ($Cloud) {
        Set-JsonProperty `
            -Object $config `
            -Name 'model' `
            -Value $CloudModel
    }
    elseif ($Local) {
        $currentDefault = $config.PSObject.Properties['model']

        if ($null -eq $currentDefault -or
            [string]::IsNullOrWhiteSpace(
                [string]$currentDefault.Value
            )) {
            Set-JsonProperty `
                -Object $config `
                -Name 'model' `
                -Value "ollama/$LocalModel"
        }
    }

    if ($Local) {
        # Preserve existing provider entries.
        if ($null -eq $config.PSObject.Properties['provider']) {
            Set-JsonProperty `
                -Object $config `
                -Name 'provider' `
                -Value ([pscustomobject]@{})
        }

        if ($config.provider -isnot [pscustomobject]) {
            throw 'Existing provider configuration is invalid.'
        }

        if ($null -eq $config.provider.PSObject.Properties['ollama']) {
            $ollamaProvider = [pscustomobject]@{
                npm = '@ai-sdk/openai-compatible'
                name = 'Ollama (local)'
                options = [pscustomobject]@{
                    baseURL = 'http://127.0.0.1:11434/v1'
                }
                models = [pscustomobject]@{}
            }

            Set-JsonProperty `
                -Object $config.provider `
                -Name 'ollama' `
                -Value $ollamaProvider
        }
        else {
            $ollamaProvider = $config.provider.ollama

            if ($ollamaProvider -isnot [pscustomobject]) {
                throw 'Existing Ollama provider is invalid.'
            }

            Assert-OllamaProvider -Provider $ollamaProvider
        }

        # Add the requested model without removing other models.
        if ($null -eq $ollamaProvider.models.PSObject.Properties[$LocalModel]) {
            $modelDefinition = [pscustomobject]@{
                name = $LocalModel
            }

            Set-JsonProperty `
                -Object $ollamaProvider.models `
                -Name $LocalModel `
                -Value $modelDefinition
        }

        # Check availability before starting any download.
        Write-Host ''
        Write-Host "Checking Ollama model: $LocalModel"

        if (-not (Test-OllamaModel -Name $LocalModel)) {
            Write-Host "Model not installed: $LocalModel"

            if (-not (Confirm-Action `
                -Question "Download $LocalModel now?")) {
                throw "Required Ollama model is missing: $LocalModel"
            }

            Write-Host ''
            Write-Host "Downloading $LocalModel..."

            & ollama pull $LocalModel

            if ($LASTEXITCODE -ne 0) {
                throw "Ollama download failed: $LocalModel"
            }

            if (-not (Test-OllamaModel -Name $LocalModel)) {
                throw "Ollama model verification failed: $LocalModel"
            }
        }

        Write-Host "Ollama model available: $LocalModel" `
            -ForegroundColor Green
    }

    $newJson = $config | ConvertTo-Json -Depth 30

    # Avoid modifying the file when the effective config matches.
    $unchanged = $false

    if ($existingFile) {
        $before = ($originalJson | ConvertFrom-Json) |
            ConvertTo-Json -Depth 30 -Compress

        $after = ($newJson | ConvertFrom-Json) |
            ConvertTo-Json -Depth 30 -Compress

        $unchanged = ($before -ceq $after)
    }

    # Prepare a temporary configuration for OpenCode validation.
    if (-not (Test-Path -LiteralPath $InstallPath)) {
        New-Item -ItemType Directory `
            -Path $InstallPath -Force | Out-Null
    }

    $temporaryPath = Join-Path $InstallPath (
        '.opencode-' + [guid]::NewGuid().ToString('N') + '.json'
    )

    $utf8 = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText(
        $temporaryPath,
        $newJson,
        $utf8
    )

    # Validate using OpenCode before changing the saved config.
    $previousConfig = $env:OPENCODE_CONFIG

    try {
        $env:OPENCODE_CONFIG = $temporaryPath

        Write-Host ''
        Write-Host 'Verifying OpenCode configuration...'

        $modelOutput = @(& opencode models 2>&1)
        $modelExit = $LASTEXITCODE

        if ($modelExit -ne 0) {
            throw "OpenCode rejected the configuration (exit $modelExit)."
        }

        if ($Local) {
            $expectedModel = "ollama/$LocalModel"

            $modelLines = @(
                $modelOutput |
                    ForEach-Object { $_.ToString().Trim() }
            )

            if ($modelLines -notcontains $expectedModel) {
                throw "OpenCode did not list: $expectedModel"
            }
        }
    }
    finally {
        $env:OPENCODE_CONFIG = $previousConfig
    }

    # Write only after validation has succeeded.
    if ($unchanged) {
        Write-Host 'Existing OpenCode configuration is unchanged.'
    }
    else {
        if ($existingFile) {
            $backupPath = "$configPath.bak.$([guid]::NewGuid().ToString('N'))"

            Copy-Item `
                -LiteralPath $configPath `
                -Destination $backupPath `
                -ErrorAction Stop

            Write-Host "Backup created: $backupPath"
        }

        # The validated file becomes the saved configuration.
        Move-Item `
            -LiteralPath $temporaryPath `
            -Destination $configPath `
            -Force `
            -ErrorAction Stop

        $temporaryPath = $null

        Write-Host "Saved OpenCode configuration: $configPath" `
            -ForegroundColor Green
    }

    Write-Host ''
    Write-Host 'Agent configuration completed.' `
        -ForegroundColor Green

    Write-Host "Configuration: $configPath"

    if ($Cloud) {
        Write-Host "Cloud model: $CloudModel"
    }

    if ($Local) {
        Write-Host "Local model: ollama/$LocalModel"
    }

    Write-Host 'Global OpenCode configuration was not changed.'

    exit 0
}
catch {
    Write-Host ''
    Write-Host "Agent setup error: $($_.Exception.Message)" `
        -ForegroundColor Red

    exit 1
}
finally {
    if ($null -ne $temporaryPath -and
        (Test-Path -LiteralPath $temporaryPath)) {
        Remove-Item `
            -LiteralPath $temporaryPath `
            -Force `
            -ErrorAction SilentlyContinue
    }
}
