#Requires -Version 5.1
[CmdletBinding()]
param([string]$InstallPath, [string]$Device, [string]$TtsEngine, [switch]$PrepareOnly)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if ($null -eq (Get-Command Invoke-StackSetupScript -ErrorAction Ignore)) { . (Join-Path $repoRoot 'scripts\script-invocation.ps1') }
. (Get-StackSetupScript (Join-Path $PSScriptRoot 'strategy-management.ps1'))
. (Get-StackSetupScript (Join-Path $repoRoot 'scripts\configuration.ps1'))
. (Get-StackSetupScript (Join-Path $repoRoot 'scripts\installation-state.ps1'))
function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$Executable,

        [string[]]$Arguments = @()
    )

    Write-Host ''
    Write-Host $Description -ForegroundColor Cyan

    $previousPreference = $ErrorActionPreference
    try {
        # Native stderr includes pip progress and import warnings. Preserve it
        # as diagnostic output; use the process exit code for success/failure.
        $ErrorActionPreference = 'Continue'
        & $Executable @Arguments 2>&1 | ForEach-Object { Write-Host $_.ToString() }
        $commandExitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }

    if ($commandExitCode -ne 0) {
        throw "$Description failed (exit code $commandExitCode)."
    }
}

try {
    $config = Get-StackConfiguration -Root $repoRoot
    if (-not $TtsEngine) { $TtsEngine = $config.tts.engine }
    if (-not $Device) { $Device = $config.tts.device }
    if (-not $InstallPath) { $InstallPath = $config.installation.directory }
    if (-not $InstallPath) { $InstallPath = Join-Path $HOME 'AI\WindowsHybridAgenticStack' }
    $InstallPath = Assert-StackInstallationRoot ([IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($InstallPath)))
    $package = Get-TtsStrategy -Root $repoRoot -Id $TtsEngine
    if ($Device -ne 'auto' -and $Device -notin $package.Manifest.devices) { throw 'Device is not supported by this strategy.' }
    if ($Device -eq 'auto') {
        $Device = 'cpu'
        if ('cuda' -in $package.Manifest.devices -and (Get-Command nvidia-smi -ErrorAction Ignore)) {
            $null = & nvidia-smi -L 2>$null
            if ($LASTEXITCODE -eq 0) { $Device = 'cuda' }
        }
        if ($Device -notin $package.Manifest.devices) { throw 'No supported device is available.' }
    }
    $state = Read-StackInstallationState $InstallPath
    if ($null -eq $state) { throw 'Run the root installer so strategy resources are ownership-tracked.' }
    $existing = @($state.TtsStrategies | Where-Object { $_ -and $_.Id -eq $TtsEngine })
    $legacyChatterbox = -not $state.PreexistingVenv -and @($state.Files.Path | Where-Object { $_ -like '.venv/*' }).Count -gt 0
    $migratedChatterbox = @($state.TtsStrategies | Where-Object { $_ -and $_.Id -ceq 'chatterbox-turbo' }).Count -gt 0
    if (-not $existing.Count -and $legacyChatterbox -and -not $migratedChatterbox -and $TtsEngine -ne 'chatterbox-turbo') { throw 'Migrate the owned legacy Chatterbox installation before adding another engine.' }
    $environment = "tts/engines/$TtsEngine/.venv"
    $voices = "voices/$TtsEngine"
    if ($existing.Count) {
        $null = @(Get-TtsInstalledHooks $InstallPath $state)
        $environment = $existing[0].Context.EnvironmentPath
        $voices = $existing[0].Context.VoicesPath
    }
    elseif ($TtsEngine -eq 'chatterbox-turbo' -and $legacyChatterbox) {
        $environment = '.venv'; $voices = 'voices'
    }
    $environmentPath = Resolve-TtsPackagePath $InstallPath $environment
    if (Test-Path -LiteralPath $environmentPath) {
        $prefix = $environment.TrimEnd('/') + '/'
        $ownedFiles = @{}
        foreach ($entry in $state.Files) { $ownedFiles[$entry.Path] = $entry }
        foreach ($file in (Get-StackInstallationTree $environmentPath).Files) {
            $relative = $prefix + $file
            $entry = $ownedFiles[$relative]
            if ($null -eq $entry -or ((Get-StackFileSHA256 (Join-Path $InstallPath $relative)) -cne $entry.SHA256 -and -not (Test-StackGeneratedFile $relative $state))) { throw 'Existing environment is unowned or modified; it was not changed.' }
        }
    }
    if (-not $existing.Count -and (Test-Path -LiteralPath (Join-Path $InstallPath "tts/engines/$TtsEngine/models"))) { throw 'Pre-existing model directory is not owned by this strategy.' }
    if ($existing.Count) {
        $modelRoot = Resolve-TtsPackagePath $InstallPath $existing[0].Context.ModelsPath
        $ownedModels = @{}
        foreach ($entry in $state.Files) { $ownedModels[$entry.Path] = $entry.SHA256 }
        foreach ($file in (Get-StackInstallationTree $modelRoot).Files) {
            $relative = $existing[0].Context.ModelsPath + '/' + $file
            if (-not $ownedModels.ContainsKey($relative) -or (Get-StackFileSHA256 (Join-Path $modelRoot $file)) -cne $ownedModels[$relative]) { throw 'Existing model files are unowned or modified; they were not changed.' }
        }
    }
    $context = [pscustomobject]@{ InstallPath=$InstallPath; Engine=$TtsEngine; Device=$Device; EnvironmentPath=$environment; VoicesPath=$voices; ModelsPath="tts/engines/$TtsEngine/models" }
    $installedPackage = "tts/strategies/$TtsEngine"
    $assets = @()
    foreach ($file in $package.Files) {
        $source = Resolve-TtsPackagePath $package.Directory $file
        $relative = "$installedPackage/$file"
        $destination = Resolve-TtsPackagePath $InstallPath $relative
        if ((Test-Path -LiteralPath $destination) -and (Get-StackFileSHA256 $destination) -cne (Get-StackFileSHA256 $source)) { throw 'Existing strategy package differs; automatic upgrades are not supported.' }
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        if ([IO.Path]::GetFullPath($source) -ine [IO.Path]::GetFullPath($destination)) { Copy-Item -LiteralPath $source -Destination $destination -Force }
        $assets += [pscustomobject]@{Path=$relative; SHA256=(Get-StackFileSHA256 $destination)}
    }
    foreach ($file in @('tts.ps1','tts_service.py','strategy-management.ps1','install-tts.ps1','engine-management.ps1','strategy.schema.json')) {
        $sharedSource = Join-Path $PSScriptRoot $file
        $sharedDest = Join-Path $InstallPath "tts/$file"
        if ([IO.Path]::GetFullPath($sharedSource) -ine [IO.Path]::GetFullPath($sharedDest)) { Copy-Item -LiteralPath $sharedSource -Destination $sharedDest -Force }
    }
    $record = [pscustomobject]@{Id=$TtsEngine; Version=$package.Manifest.version; ApiVersion=1; Status='Installing'; PackageFiles=$assets; UninstallPath="$installedPackage/$($package.Manifest.entrypoints.uninstall)"; Context=$context}
    $state.SchemaVersion = 2
    $records = @($state.TtsStrategies | Where-Object { $_ -and $_.Id -cne $TtsEngine }) + @($record)
    $state | Add-Member -NotePropertyName TtsStrategies -NotePropertyValue $records -Force
    Write-StackInstallationState $InstallPath $state
    $runtime = [pscustomobject]@{schemaVersion=1; engine=$TtsEngine; environmentPath=$environment; voicesPath=$voices; modelsPath=$context.ModelsPath; backendPath="$installedPackage/$($package.Manifest.entrypoints.backend)"; capabilities=$package.Manifest.capabilities; device=$Device}
    $runtimeJson = $runtime | ConvertTo-Json -Depth 8
    New-Item -ItemType Directory -Path (Join-Path $InstallPath "tts/engines/$TtsEngine") -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $InstallPath "tts/engines/$TtsEngine/runtime.json"), $runtimeJson, (New-Object Text.UTF8Encoding($false)))
    if (-not (Test-Path -LiteralPath (Join-Path $InstallPath 'tts/runtime.json'))) {
        [IO.File]::WriteAllText((Join-Path $InstallPath 'tts/runtime.json'), $runtimeJson, (New-Object Text.UTF8Encoding($false)))
    }
    # Keep a verified catalog so additional engines can be installed later.
    foreach ($catalogPackage in @(Get-TtsStrategies -Root $repoRoot)) {
        foreach ($catalogFile in $catalogPackage.Files) {
            $catalogSource = Resolve-TtsPackagePath $catalogPackage.Directory $catalogFile
            $catalogDest = Resolve-TtsPackagePath $InstallPath "tts/strategies/$($catalogPackage.Manifest.id)/$catalogFile"
            if ([IO.Path]::GetFullPath($catalogSource) -ieq [IO.Path]::GetFullPath($catalogDest)) { continue }
            if ((Test-Path -LiteralPath $catalogDest) -and (Get-StackFileSHA256 $catalogDest) -cne (Get-StackFileSHA256 $catalogSource)) { throw 'Catalog package changed; automatic upgrades are not supported.' }
            New-Item -ItemType Directory -Path (Split-Path -Parent $catalogDest) -Force | Out-Null
            Copy-Item -LiteralPath $catalogSource -Destination $catalogDest -Force
        }
    }
    Invoke-StackSetupScript -Path (Resolve-TtsPackagePath $package.Directory $package.Manifest.entrypoints.install) -Arguments @{Context=$context; PrepareOnly=[bool]$PrepareOnly}
    if ($LASTEXITCODE -ne 0) { throw "Strategy installation failed (exit $LASTEXITCODE)." }
    $record.Status = if ($PrepareOnly) { 'Prepared' } else { 'Installed' }
    Write-StackInstallationState $InstallPath $state
    Write-Host "TTS strategy ready: $TtsEngine"
    exit 0
}
catch { Write-Error "TTS strategy installation failed: $_" -ErrorAction Continue; exit 1 }
