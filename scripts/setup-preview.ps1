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
