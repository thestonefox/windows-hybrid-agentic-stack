#Requires -Version 5.1

<#
.SYNOPSIS
    Configure OpenCode and Ollama agents.

.DESCRIPTION
    Creates or updates the stack-specific OpenCode configuration.

    Preserves existing components and unrelated settings.
    Installs Windows PowerShell agent instructions.
    Registers ps-read and ps-write.
    Downloads missing Ollama models with confirmation.
    Validates configuration before saving changes.
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

$repoRoot = Split-Path -Parent $PSScriptRoot
$instructionsSource = Join-Path $repoRoot 'config\AGENTS.md'

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
        [pscustomobject]$Object,
        [string]$Name,
        [AllowNull()][object]$Value
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

    if ($Provider.options -isnot [pscustomobject]) {
        throw 'Existing Ollama provider has invalid options.'
    }

    if ($Provider.options.baseURL -notin @(
        'http://127.0.0.1:11434/v1',
        'http://localhost:11434/v1'
    )) {
        throw 'Existing Ollama provider uses a different URL.'
    }

    if ($Provider.models -isnot [pscustomobject]) {
        throw 'Existing Ollama provider has invalid models.'
    }
}

function Assert-AgentDefinition {
    param(
        [pscustomobject]$Existing,
        [pscustomobject]$Expected,
        [string]$Name
    )

    $actual = $Existing | ConvertTo-Json -Depth 20 -Compress
    $required = $Expected | ConvertTo-Json -Depth 20 -Compress

    if ($actual -cne $required) {
        throw @"
Existing $Name definition differs from this stack.
No agent permissions have been overwritten.
Review the existing OpenCode configuration.
"@
    }
}

$temporaryPath = $null

try {
    if (-not ($Cloud -or $Local)) {
        Write-Host 'No AI agent components selected.'
        exit 0
    }

    if (-not (Test-Path -LiteralPath $instructionsSource -PathType Leaf)) {
        throw "Instructions file missing: $instructionsSource"
    }

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        throw 'InstallPath cannot be empty.'
    }

    $InstallPath = [Environment]::ExpandEnvironmentVariables(
        $InstallPath
    )

    $InstallPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
        $InstallPath
    )

    $configPath = Join-Path $InstallPath 'opencode.json'
    $instructionsPath = Join-Path $InstallPath 'AGENTS.md'

    $existingFile = Test-Path -LiteralPath $configPath

    if ($existingFile) {
        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
            throw "Configuration path is not a file: $configPath"
        }

        $originalJson = Get-Content -LiteralPath $configPath -Raw
        $config = $originalJson | ConvertFrom-Json

        if ($config -isnot [pscustomobject]) {
            throw 'Existing OpenCode configuration must be an object.'
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

    # Refuse to overwrite different existing instructions.
    if (Test-Path -LiteralPath $instructionsPath) {
        if (-not (Test-Path -LiteralPath $instructionsPath -PathType Leaf)) {
            throw "Instructions path is not a file: $instructionsPath"
        }

        $existingInstructions = Get-Content `
            -LiteralPath $instructionsPath -Raw

        $requiredInstructions = Get-Content `
            -LiteralPath $instructionsSource -Raw

        if ($existingInstructions -cne $requiredInstructions) {
            throw @"
Existing instructions differ: $instructionsPath
No instructions were overwritten.
"@
        }
    }

    # Enforce Windows PowerShell rather than an optional shell.
    $shellProperty = $config.PSObject.Properties['shell']

    if ($null -ne $shellProperty -and
        $shellProperty.Value -ne 'powershell.exe') {
        throw 'Existing OpenCode configuration uses another shell.'
    }

    Set-JsonProperty `
        -Object $config `
        -Name 'shell' `
        -Value 'powershell.exe'

    # Preserve existing instructions and add our file once.
    if ($null -eq $config.PSObject.Properties['instructions']) {
        Set-JsonProperty `
            -Object $config `
            -Name 'instructions' `
            -Value @()
    }

    if ($config.instructions -isnot [array]) {
        throw 'Existing instructions setting must be an array.'
    }

    if ($config.instructions -notcontains $instructionsPath) {
        $newInstructions = @($config.instructions) + $instructionsPath

        Set-JsonProperty `
            -Object $config `
            -Name 'instructions' `
            -Value $newInstructions
    }

    # Set up both agents using explicit OpenCode permissions.
    $readAgent = [pscustomobject]@{
        description = 'Read-only Windows information assistant'
        mode = 'primary'
        permission = [pscustomobject]@{
            bash = 'deny'
            edit = 'deny'
            task = 'deny'
            webfetch = 'deny'
            websearch = 'deny'
        }
    }

    $writeAgent = [pscustomobject]@{
        description = 'Windows task execution assistant'
        mode = 'primary'
        permission = [pscustomobject]@{
            bash = 'allow'
            edit = 'allow'
            task = 'deny'
            webfetch = 'deny'
            websearch = 'deny'
        }
    }

    if ($null -eq $config.PSObject.Properties['agent']) {
        Set-JsonProperty `
            -Object $config `
            -Name 'agent' `
            -Value ([pscustomobject]@{})
    }

    if ($config.agent -isnot [pscustomobject]) {
        throw 'Existing agent configuration is invalid.'
    }

    $definitions = @{
        'ps-read' = $readAgent
        'ps-write' = $writeAgent
    }

    foreach ($name in @('ps-read', 'ps-write')) {
        $expectedAgent = $definitions[$name]

        if ($null -eq $config.agent.PSObject.Properties[$name]) {
            Set-JsonProperty `
                -Object $config.agent `
                -Name $name `
                -Value $expectedAgent
        }
        else {
            Assert-AgentDefinition `
                -Existing $config.agent.$name `
                -Expected $expectedAgent `
                -Name $name
        }
    }

    # Select the default model.
    if ($Cloud) {
        Set-JsonProperty `
            -Object $config `
            -Name 'model' `
            -Value $CloudModel
    }
    elseif ($Local) {
        $currentModel = $config.PSObject.Properties['model']

        if ($null -eq $currentModel -or
            [string]::IsNullOrWhiteSpace(
                [string]$currentModel.Value
            )) {
            Set-JsonProperty `
                -Object $config `
                -Name 'model' `
                -Value "ollama/$LocalModel"
        }
    }

    # Add the Ollama provider without removing existing models.
    if ($Local) {
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

            Assert-OllamaProvider -Provider $ollamaProvider
        }

        if ($null -eq $ollamaProvider.models.PSObject.Properties[$LocalModel]) {
            Set-JsonProperty `
                -Object $ollamaProvider.models `
                -Name $LocalModel `
                -Value ([pscustomobject]@{
                    name = $LocalModel
                })
        }

        Write-Host ''
        Write-Host "Checking Ollama model: $LocalModel"

        if (-not (Test-OllamaModel -Name $LocalModel)) {
            Write-Host "Model not installed: $LocalModel"

            if (-not (Confirm-Action `
                -Question "Download $LocalModel now?")) {
                throw "Required Ollama model is missing: $LocalModel"
            }

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

    $unchanged = $false

    if ($existingFile) {
        $before = ($originalJson | ConvertFrom-Json) |
            ConvertTo-Json -Depth 30 -Compress

        $after = ($newJson | ConvertFrom-Json) |
            ConvertTo-Json -Depth 30 -Compress

        $unchanged = ($before -ceq $after)
    }

    if (-not (Test-Path -LiteralPath $InstallPath)) {
        New-Item -ItemType Directory `
            -Path $InstallPath -Force | Out-Null
    }

    # OpenCode needs the instructions file during validation.
    $createdInstructions = $false

    if (-not (Test-Path -LiteralPath $instructionsPath)) {
        Copy-Item `
            -LiteralPath $instructionsSource `
            -Destination $instructionsPath `
            -ErrorAction Stop

        $createdInstructions = $true
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

    $previousConfig = $env:OPENCODE_CONFIG

    try {
        $env:OPENCODE_CONFIG = $temporaryPath

        Write-Host ''
        Write-Host 'Verifying OpenCode configuration...'

        $modelOutput = @(& opencode models 2>&1)

        if ($LASTEXITCODE -ne 0) {
            throw 'OpenCode rejected the model configuration.'
        }

        if ($Local) {
            $modelLines = @(
                $modelOutput |
                    ForEach-Object { $_.ToString().Trim() }
            )

            if ($modelLines -notcontains "ollama/$LocalModel") {
                throw "OpenCode did not list ollama/$LocalModel"
            }
        }

        $agentOutput = @(& opencode agent list 2>&1)

        if ($LASTEXITCODE -ne 0) {
            throw 'OpenCode could not list the configured agents.'
        }

        $agentText = $agentOutput | Out-String

        foreach ($name in @('ps-read', 'ps-write')) {
            if ($agentText -notmatch [regex]::Escape($name)) {
                throw "OpenCode did not list agent: $name"
            }
        }
    }
    finally {
        $env:OPENCODE_CONFIG = $previousConfig
    }

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
    Write-Host "Instructions:  $instructionsPath"
    Write-Host 'Agents:        ps-read, ps-write'
    Write-Host 'Shell:         powershell.exe'

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
