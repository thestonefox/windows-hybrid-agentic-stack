#Requires -Version 5.1

function Merge-Configuration {
    param(
        [pscustomobject]$Target,
        [pscustomobject]$Overrides,
        [string]$Prefix = ''
    )

    foreach ($property in $Overrides.PSObject.Properties) {
        $name = $property.Name

        if ($Prefix) {
            $key = "$Prefix.$name"
        }
        else {
            $key = $name
        }

        $targetProperty = $Target.PSObject.Properties[$name]

        if ($Prefix -eq 'tts.voiceDefaults' -and $null -eq $targetProperty) {
            if ($name -cnotmatch '^[a-z][a-z0-9-]{0,47}$' -or $property.Value -isnot [string] -or $property.Value -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$') { throw 'Invalid engine voice default.' }
            $Target | Add-Member -NotePropertyName $name -NotePropertyValue $property.Value
            continue
        }

        if ($null -eq $targetProperty) {
            throw "Unknown configuration setting: $key"
        }

        $value = $property.Value

        if ($targetProperty.Value -is [pscustomobject]) {
            if ($value -isnot [pscustomobject]) {
                throw "$key must be a JSON object"
            }

            Merge-Configuration `
                -Target $targetProperty.Value `
                -Overrides $value `
                -Prefix $key
        }
        else {
            $targetProperty.Value = $value
        }
    }
}

function Assert-Configuration {
    param([pscustomobject]$Config)

    $errors = [System.Collections.Generic.List[string]]::new()
    if ($Config.interaction) {
        if ($Config.interaction.location -notin @('local','cloud')) { $errors.Add('interaction.location must be local or cloud') }
        if ($null -ne $Config.interaction.runtime -and $Config.interaction.runtime -cnotmatch '^[a-z][a-z0-9-]{0,47}$') { $errors.Add('interaction.runtime must be a strategy ID or null') }
        if ($Config.interaction.speech -isnot [bool]) { $errors.Add('interaction.speech must be a boolean') }
    }
    if ($Config.tts.voiceDefaults) {
        if ($Config.tts.voiceDefaults -isnot [pscustomobject]) { $errors.Add('tts.voiceDefaults must be an object') }
        else { foreach($entry in $Config.tts.voiceDefaults.PSObject.Properties) {
            if ($entry.Name -cnotmatch '^[a-z][a-z0-9-]{0,47}$' -or $entry.Value -isnot [string] -or $entry.Value -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$') { $errors.Add('Invalid engine voice default') }
        } }
    }

    $directory = $Config.installation.directory

    if ($null -ne $directory) {
        if ($directory -isnot [string] -or
            [string]::IsNullOrWhiteSpace($directory)) {
            $errors.Add(
                'installation.directory must be null or a non-empty string'
            )
        }
    }

    foreach ($type in @('cloud', 'local')) {
        $agent = $Config.agents.$type

        if ($agent.enabled -isnot [bool]) {
            $errors.Add("agents.$type.enabled must be a boolean")
        }

        foreach ($name in @('provider', 'model')) {
            $value = $agent.$name

            if ($type -eq 'cloud' -and $null -eq $value) { continue }

            if ($value -isnot [string] -or
                [string]::IsNullOrWhiteSpace($value)) {
                $errors.Add(
                    "agents.$type.$name must be a non-empty string"
                )
            }
        }
    }

    if ($Config.agents.cloud.model -is [string] -and
        $Config.agents.cloud.model -notmatch '/' -and
        [string]::IsNullOrWhiteSpace([string]$Config.agents.cloud.provider)) {
        $errors.Add('agents.cloud.model must use provider/model when provider is null')
    }

    $contextSize = $Config.agents.local.contextSize

    if ($contextSize -isnot [int] -and $contextSize -isnot [long]) {
        $errors.Add('agents.local.contextSize must be an integer')
    }
    elseif ($contextSize -lt 4096 -or $contextSize -gt 131072) {
        $errors.Add('agents.local.contextSize must be 4096 to 131072')
    }
    elseif (($contextSize % 1024) -ne 0) {
        $errors.Add('agents.local.contextSize must be a multiple of 1024')
    }

    foreach ($name in @('enabled', 'autoStart')) {
        if ($Config.tts.$name -isnot [bool]) {
            $errors.Add("tts.$name must be a boolean")
        }
    }

    foreach ($name in @('engine', 'defaultVoice', 'device')) {
        $value = $Config.tts.$name

        if ($value -isnot [string] -or
            [string]::IsNullOrWhiteSpace($value)) {
            $errors.Add("tts.$name must be a non-empty string")
        }
    }

    # This service is designed for local-only HTTP access.
    if ($Config.tts.host -cne '127.0.0.1') {
        $errors.Add('tts.host must be 127.0.0.1')
    }

    if ($Config.tts.device -cnotin @('auto', 'cpu', 'cuda')) {
        $errors.Add('tts.device must be auto, cpu or cuda')
    }

    $timeout = $Config.tts.idleTimeoutMinutes

    if ($timeout -isnot [int] -and
        $timeout -isnot [long]) {
        $errors.Add('tts.idleTimeoutMinutes must be an integer')
    }
    elseif ($timeout -lt 0) {
        $errors.Add(
            'tts.idleTimeoutMinutes must be zero or greater'
        )
    }

    $port = $Config.tts.port

    if ($port -isnot [int] -and $port -isnot [long]) {
        $errors.Add('tts.port must be an integer')
    }
    elseif ($port -lt 1 -or $port -gt 65535) {
        $errors.Add('tts.port must be between 1 and 65535')
    }

    return $errors.ToArray()
}

function Get-StackConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$ConfigPath
    )
    $defaultsPath = Join-Path $Root 'config\defaults.json'
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Join-Path $Root 'config\config.json'
    }
    if (-not (Test-Path -LiteralPath $defaultsPath -PathType Leaf)) {
        throw "Defaults file not found: $defaultsPath"
    }
    $config = Get-Content -LiteralPath $defaultsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $config.interaction) { $config | Add-Member -NotePropertyName interaction -NotePropertyValue ([pscustomobject]@{location='cloud';runtime='opencode';speech=$false}) }
    if ($config.tts -and -not $config.tts.PSObject.Properties['voiceDefaults']) { $config.tts | Add-Member -NotePropertyName voiceDefaults -NotePropertyValue ([pscustomobject]@{}) }
    if ($config -isnot [pscustomobject]) { throw 'Defaults must contain a JSON object' }
    if (Test-Path -LiteralPath $ConfigPath) {
        if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
            throw "Configuration path is not a file: $ConfigPath"
        }
        $overrides = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($overrides -isnot [pscustomobject]) { throw 'User configuration must contain a JSON object' }
        Merge-Configuration -Target $config -Overrides $overrides
    }
    $errors = @(Assert-Configuration -Config $config)
    if ($errors.Count -gt 0) { throw ($errors -join [Environment]::NewLine) }
    return $config
}
