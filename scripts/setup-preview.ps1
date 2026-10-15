#Requires -Version 5.1
# Embedded setup selection and preview. No writes are performed here.
param(
    [string]$DefaultsJson,
    [string]$StrategyCatalogJson,
    [string]$TtsEngine,
    [bool]$Interactive,
    [string]$ConfigPath,
    [string]$InstallPath,
    [bool]$Cloud,
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
if ($errors.Count) { throw ($errors -join [Environment]::NewLine) }
if (-not ($Cloud -or $Local -or $Voice)) {
    $Cloud = $config.agents.cloud.enabled
    $Local = $config.agents.local.enabled
    $Voice = $config.tts.enabled
}
if (-not ($Cloud -or $Local -or $Voice)) { throw 'No components selected.' }
if (-not $InstallPath) { $InstallPath = $config.installation.directory }
if (-not $InstallPath) { $InstallPath = Join-Path $HOME 'AI\WindowsHybridAgenticStack' }
$InstallPath = [Environment]::ExpandEnvironmentVariables($InstallPath)
if ($InstallPath -match '^\$HOME(?=[\\/]|$)') { $InstallPath = $HOME + $InstallPath.Substring(5) }
$InstallPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallPath)
$config.installation.directory = $InstallPath
if ($TtsEngine -and -not $Voice) { throw '--tts-engine requires --voice.' }
if ($TtsEngine) { $config.tts.engine = $TtsEngine }
$engineManifest = $null
if ($Voice) {
    $catalog = $StrategyCatalogJson | ConvertFrom-Json
    if ($Interactive -and -not $TtsEngine -and -not $ConfigPath) {
        $config.tts.engine = Select-TtsEngine -Manifests @($catalog | ForEach-Object { $_ }) -Default $config.tts.engine
    }
    $selectedManifests = @($catalog | Where-Object { $_.id -ceq $config.tts.engine })
    if ($selectedManifests.Count -ne 1) { throw "TTS strategy unavailable: $($config.tts.engine)" }
    $engineManifest = $selectedManifests[0]
    if ($config.tts.device -ne 'auto' -and $config.tts.device -notin $engineManifest.devices) { throw 'Device unsupported by selected strategy.' }
}
if ($ShowPlan) {
    Write-Host 'Installation preview'
    Write-Host "Directory:    $InstallPath"
    Write-Host "Cloud agents: $Cloud"
    Write-Host "Local agents: $Local"
    Write-Host "Voice output: $Voice"
    if ($Cloud) { Write-Host ('Cloud model:  ' + $(if ($config.agents.cloud.model) { $config.agents.cloud.model } else { 'OpenCode default' })) }
    if ($Local) {
        Write-Host "Local model:  $($config.agents.local.model)"
        Write-Host "Context:      $($config.agents.local.contextSize) tokens"
    }
    if ($Voice) {
        Write-Host "TTS engine:   $($config.tts.engine)"
        Write-Host "TTS device:   $($config.tts.device)"
        Write-Host "TTS package:  $($engineManifest.name) $($engineManifest.version); licence: $($engineManifest.license)"
        foreach ($model in $engineManifest.models) {
            $pin = if ($model.revision) { "revision $($model.revision)" } else { "SHA256 $($model.sha256)" }
            Write-Host "Model download: $($model.source), $pin; licence: $($model.license)"
        }
    }
    Write-Host 'Preview complete. No changes made.'
}
[pscustomobject]@{ Cloud = $Cloud; Local = $Local; Voice = $Voice; InstallPath = $InstallPath; StrategyManifestJson = ($engineManifest | ConvertTo-Json -Depth 12 -Compress); ConfigJson = ($config | ConvertTo-Json -Depth 50) }
