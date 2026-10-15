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
    [string]$LocalModel = 'qwen3:8b',
    [ValidateRange(4096, 131072)]
    [int]$LocalContextSize = 16384
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$instructionsSource = Join-Path $repoRoot 'config\AGENTS.md'

function Invoke-AgentNativeCommand {
    param([string]$Executable,[string[]]$Arguments)
    # Windows PowerShell 5.1 represents redirected native stderr as ErrorRecord
    # objects. Tools use that stream for progress too; their exit code decides
    # success. Keep output available without turning progress into termination.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Executable @Arguments 2>&1 | ForEach-Object { $_.ToString() }
        $global:LASTEXITCODE = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
}

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

function Get-ManagedOllamaName {
    param([string]$Name, [int]$ContextSize)

    # Keep the original Ollama model unchanged. Use a stable model name.
    $safeName = ($Name.ToLowerInvariant() -replace '[^a-z0-9-]', '-')
    $safeName = $safeName.Trim('-')
    if (-not $safeName) { throw 'Invalid local model name.' }
    return "whas-$safeName-ctx$ContextSize"
}

function Get-OllamaModelParameters {
    param([string]$Name)
    $body = @{ model = $Name } | ConvertTo-Json -Compress
    try {
        $detail = Invoke-RestMethod -Method Post `
            -Uri 'http://127.0.0.1:11434/api/show' `
            -ContentType 'application/json' -Body $body -TimeoutSec 30
    }
    catch {
        throw "Unable to inspect Ollama model '$Name': $($_.Exception.Message)"
    }
    return [string]$detail.parameters
}

function Ensure-ContextModel {
    param([string]$SourceModel, [int]$ContextSize)

    $managedName = Get-ManagedOllamaName -Name $SourceModel `
        -ContextSize $ContextSize

    if (Test-OllamaModel -Name $managedName) {
        $parameters = Get-OllamaModelParameters -Name $managedName
        $expression = '(?m)^\s*num_ctx\s+' + $ContextSize + '\s*$'
        if ($parameters -notmatch $expression) {
            throw "Existing Ollama model '$managedName' has different parameters. Refusing to overwrite it."
        }
        Write-Host "Configured Ollama model already exists: $managedName"
        return $managedName
    }

    $modelfile = Join-Path ([System.IO.Path]::GetTempPath()) `
        ('whas-' + [guid]::NewGuid().ToString('N') + '.Modelfile')
    try {
        $modelfileText = "FROM $SourceModel`nPARAMETER num_ctx $ContextSize`n"
        [System.IO.File]::WriteAllText(
            $modelfile, $modelfileText,
            (New-Object System.Text.UTF8Encoding($false))
        )
        Write-Host "Creating context-enabled Ollama model: $managedName"
        Invoke-AgentNativeCommand 'ollama' @('create',$managedName,'-f',$modelfile) | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create Ollama model: $managedName"
        }
    }
    finally {
        Remove-Item -LiteralPath $modelfile -Force `
            -ErrorAction SilentlyContinue
    }
    if (-not (Test-OllamaModel -Name $managedName)) {
        throw "Generated Ollama model not found: $managedName"
    }
    $parameters = Get-OllamaModelParameters -Name $managedName
    if ($parameters -notmatch ('(?m)^\s*num_ctx\s+' + $ContextSize + '\s*$')) {
        throw "Ollama did not apply context $ContextSize to $managedName"
    }
    return $managedName
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

    # Upgrade managed instructions without overwriting user additions.
    $requiredInstructions = Get-Content `
        -LiteralPath $instructionsSource -Raw
    $instructionsChanged = $false
    $instructionsToWrite = $requiredInstructions
    $managedHeading = '## Windows command execution'
    $markerIndex = $requiredInstructions.IndexOf($managedHeading)
    if ($markerIndex -lt 0) {
        throw 'Instruction migration marker missing from source.'
    }
    $managedSection = $requiredInstructions.Substring($markerIndex).Trim()

    if (Test-Path -LiteralPath $instructionsPath) {
        if (-not (Test-Path -LiteralPath $instructionsPath -PathType Leaf)) {
            throw "Instructions path is not a file: $instructionsPath"
        }
        $existingInstructions = Get-Content `
            -LiteralPath $instructionsPath -Raw

        # Compare without depending on CRLF/LF or trailing newlines.
        $existingNormal = ($existingInstructions -replace "`r`n", "`n").Trim()
        $requiredNormal = ($requiredInstructions -replace "`r`n", "`n").Trim()
        if ($existingNormal -cne $requiredNormal) {
            if ($existingInstructions.Contains($managedHeading)) {
                # The managed section exists already. Preserve user changes
                # rather than overwriting an unknown version.
                $sectionStart = $existingInstructions.IndexOf($managedHeading)
                $actualSection = ($existingInstructions.Substring($sectionStart) `
                    -replace "`r`n", "`n").Trim()
                $expectedSection = ($managedSection -replace "`r`n", "`n").Trim()
                if ($actualSection -cne $expectedSection) {
                    throw "Existing managed instruction section differs: $instructionsPath"
                }
                $instructionsToWrite = $existingInstructions
            }
            else {
                # Previously installed instructions or user extensions:
                # preserve every existing line, append only our new guidance.
                $instructionsToWrite = $existingInstructions.TrimEnd() + `
                    "`r`n`r`n" + $managedSection + "`r`n"
                $instructionsChanged = $true
            }
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

    # Ensure the source model exists before deriving a context variant.
    $configuredLocalModel = $LocalModel
    if ($Local) {
        if (($LocalContextSize % 1024) -ne 0) {
            throw 'LocalContextSize must be a multiple of 1024.'
        }
        Write-Host "Checking Ollama source model: $LocalModel"
        if (-not (Test-OllamaModel -Name $LocalModel)) {
            if (-not (Confirm-Action -Question "Download $LocalModel now?")) {
                throw "Required Ollama model is missing: $LocalModel"
            }
            Invoke-AgentNativeCommand 'ollama' @('pull',$LocalModel) | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0 -or
                -not (Test-OllamaModel -Name $LocalModel)) {
                throw "Ollama model download failed: $LocalModel"
            }
        }
        $configuredLocalModel = Ensure-ContextModel `
            -SourceModel $LocalModel -ContextSize $LocalContextSize
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
                -Value "ollama/$configuredLocalModel"
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

        if ($null -eq $ollamaProvider.models.PSObject.Properties[$configuredLocalModel]) {
            Set-JsonProperty `
                -Object $ollamaProvider.models `
                -Name $configuredLocalModel `
                -Value ([pscustomobject]@{
                    name = $configuredLocalModel
                })
        }

        Write-Host "Ollama context model available: $configuredLocalModel" `
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

        $modelOutput = @(Invoke-AgentNativeCommand 'opencode' @('models'))

        if ($LASTEXITCODE -ne 0) {
            throw 'OpenCode rejected the model configuration.'
        }

        if ($Local) {
            $modelLines = @(
                $modelOutput |
                    ForEach-Object { $_.ToString().Trim() }
            )

            if ($modelLines -notcontains "ollama/$configuredLocalModel") {
                throw "OpenCode did not list ollama/$LocalModel"
            }
        }

        $agentOutput = @(Invoke-AgentNativeCommand 'opencode' @('agent','list'))

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

    if ($instructionsChanged) {
        $instructionsBackup = "$instructionsPath.bak.$([guid]::NewGuid().ToString('N'))"
        Copy-Item -LiteralPath $instructionsPath `
            -Destination $instructionsBackup -ErrorAction Stop
        [System.IO.File]::WriteAllText(
            $instructionsPath, $instructionsToWrite,
            (New-Object System.Text.UTF8Encoding($false))
        )
        Write-Host "Updated Windows agent instructions: $instructionsPath"
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
