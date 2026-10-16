#Requires -Version 5.1
# Embedded setup selection and preview. No writes are performed here.
param(
    [string]$DefaultsJson,
    [string]$StrategyCatalogJson,
    [string]$TtsEngine,
    [string]$LocalModels,
    [string]$DefaultLocalModel,
    [string]$DefaultLocation,
    [bool]$Interactive,
    [string]$ConfigPath,
    [string]$InstallPath,
    [bool]$Cloud,
    [bool]$Core,
    [bool]$Local,
    [bool]$Voice,
    [bool]$ShowPlan
)
$ErrorActionPreference = 'Stop'
$config = $DefaultsJson | ConvertFrom-Json
if ($ConfigPath) {
    $overrides = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($overrides -isnot [pscustomobject]) { throw 'Configuration must contain a JSON object.' }
    Merge-Configuration -Target $config -Overrides $overrides
}
$errors = @(Assert-Configuration -Config $config)
if($DefaultLocation) {
    if($DefaultLocation -cnotin @('cloud','local')) { throw 'Default location must be local or cloud.' }
    $config.interaction.location=$DefaultLocation
}
if ($errors.Count) { throw ($errors -join [Environment]::NewLine) }
if (-not $Core -and -not ($Cloud -or $Local -or $Voice)) {
    $Cloud = $config.agents.cloud.enabled
    $Local = $config.agents.local.enabled
    $Voice = $config.tts.enabled
}
if (-not ($Core -or $Cloud -or $Local -or $Voice)) { throw 'No components selected.' }
if(-not $DefaultLocation -and $Local -and -not $Cloud) { $config.interaction.location='local' }
if (($LocalModels -or $DefaultLocalModel) -and -not $Local) { throw 'Local model selection requires --local.' }
if ($DefaultLocalModel) { $config.agents.local.model = $DefaultLocalModel }
$modelSelection = if ($LocalModels) { @($LocalModels.Split(',') | ForEach-Object { $_.Trim() }) } else { @([string]$config.agents.local.model) }
if ($Local) {
    if ($modelSelection -notcontains $config.agents.local.model) { throw 'Default local model must be in the selected models.' }
    if (@($modelSelection | Select-Object -Unique).Count -ne $modelSelection.Count) { throw 'Duplicate local model selection.' }
    foreach ($modelId in $modelSelection) {
        if ($modelId -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9._/-]*(?::[a-zA-Z0-9._-]+)?$' -or $modelId -match '(^|/)\.\.?(/|$)') { throw 'Invalid Ollama model selection.' }
    }
}
if (-not $InstallPath) { $InstallPath = $config.installation.directory }
if (-not $InstallPath) { $InstallPath = Join-Path $HOME 'AI\WindowsHybridAgenticStack' }
$InstallPath = [Environment]::ExpandEnvironmentVariables($InstallPath)
if ($InstallPath -match '^\$HOME(?=[\\/]|$)') { $InstallPath = $HOME + $InstallPath.Substring(5) }
$InstallPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallPath)
$config.installation.directory = $InstallPath
if ($TtsEngine -and -not $Voice) { throw '--tts-engine requires --voice.' }
if ($TtsEngine) { $engineIds = @($TtsEngine.Split(',') | ForEach-Object { $_.Trim() }); $config.tts.engine = $engineIds[0] } else { $engineIds = @($config.tts.engine) }
$engineManifest = $null
if ($Voice) {
    $catalog = $StrategyCatalogJson | ConvertFrom-Json
    if ($Interactive -and -not $TtsEngine -and -not $ConfigPath) {
        $engineIds = @((Select-TtsEngine -Manifests @($catalog | ForEach-Object { $_ }) -Default $config.tts.engine).Split(','))
        $config.tts.engine = $engineIds[0]
    }
    if (@($engineIds | Select-Object -Unique).Count -ne $engineIds.Count) { throw 'Duplicate engine selection.' }
    $allManifests = @()
    foreach ($engineId in $engineIds) {
        $matches = @($catalog | Where-Object { $_.id -ceq $engineId })
        if ($matches.Count -ne 1) { throw "TTS strategy unavailable: $engineId" }
        if ($config.tts.device -ne 'auto' -and $config.tts.device -notin $matches[0].devices) { throw 'Device unsupported by selected strategy.' }
        $allManifests += $matches[0]
    }
    $selectedManifests = @($allManifests | Select-Object -First 1)
    if ($selectedManifests.Count -ne 1) { throw "TTS strategy unavailable: $($config.tts.engine)" }
    $engineManifest = $selectedManifests[0]
    if ($config.tts.device -ne 'auto' -and $config.tts.device -notin $engineManifest.devices) { throw 'Device unsupported by selected strategy.' }
}
if ($ShowPlan) {
    Write-Host 'Installation preview'
    Write-Host "Directory:    $InstallPath"
    Write-Host "Cloud agents: $Cloud"
    Write-Host "Local agents: $Local"
    Write-Host "Default location: $($config.interaction.location)"
    if ($Local) { Write-Host "Local models: $($modelSelection -join ', ')"; Write-Host "Default local model: $($config.agents.local.model)" }
    Write-Host "Voice output: $Voice"
    if ($Cloud) { Write-Host ('Cloud model:  ' + $(if ($config.agents.cloud.model) { $config.agents.cloud.model } else { 'OpenCode default' })) }
    if ($Local) {
        Write-Host "Local model:  $($config.agents.local.model)"
        Write-Host "Context:      $($config.agents.local.contextSize) tokens"
    }
    if ($Voice) {
        Write-Host "TTS engines:  $($engineIds -join ',')"
        Write-Host "Default TTS:  $($config.tts.engine)"
        Write-Host "TTS device:   $($config.tts.device)"
        foreach ($manifest in $allManifests) {
            Write-Host "TTS package:  $($manifest.name) $($manifest.version); licence: $($manifest.license)"
            foreach ($model in $manifest.models) {
                $pin = if ($model.revision) { "revision $($model.revision)" } else { "SHA256 $($model.sha256)" }
                Write-Host "Model download: $($model.source), $pin; licence: $($model.license)"
            }
        }
    }
    Write-Host 'Preview complete. No changes made.'
}
[pscustomobject]@{ EngineSelection=($engineIds -join ','); StrategyManifestJsons=@($allManifests | ForEach-Object { $_ | ConvertTo-Json -Depth 12 -Compress }); Cloud = $Cloud; Local = $Local; Voice = $Voice; InstallPath = $InstallPath; StrategyManifestJson = ($engineManifest | ConvertTo-Json -Depth 12 -Compress); ConfigJson = ($config | ConvertTo-Json -Depth 50) }
