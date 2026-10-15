#Requires -Version 5.1
# Embedded setup selection and preview. No writes are performed here.
param(
    [string]$DefaultsJson,
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
if ($Voice -and $config.tts.engine -ne 'chatterbox-turbo') { throw "Unsupported TTS engine: $($config.tts.engine)" }
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
    }
    Write-Host 'Preview complete. No changes made.'
}
[pscustomobject]@{ Cloud = $Cloud; Local = $Local; Voice = $Voice; InstallPath = $InstallPath; ConfigJson = ($config | ConvertTo-Json -Depth 50) }
