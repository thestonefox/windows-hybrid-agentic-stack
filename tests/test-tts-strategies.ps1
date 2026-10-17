#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('whas-strategies-'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $fixture 'source'
New-Item -ItemType Directory -Path $source -Force | Out-Null
foreach ($name in @('scripts','config','tts')) { Copy-Item -LiteralPath (Join-Path $repo $name) -Destination (Join-Path $source $name) -Recurse }
foreach ($name in @('install.ps1','uninstall.ps1')) { Copy-Item -LiteralPath (Join-Path $repo $name) -Destination (Join-Path $source $name) }
# Keep the disposable command check independent of any live speech installation.
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
try { $testPort = $listener.LocalEndpoint.Port } finally { $listener.Stop() }
$defaultsPath = Join-Path $source 'config/defaults.json'
$defaults = Get-Content -LiteralPath $defaultsPath -Raw | ConvertFrom-Json
$defaults.tts.port = $testPort
$defaults | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $defaultsPath -Encoding UTF8
function Write-Fixture([string]$Path,[string]$Text) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))
}
function Assert-True([bool]$Value,[string]$Message) { if (-not $Value) {throw "FAIL: $Message"}; Write-Host "PASS: $Message" }
$bundledCount=@(Get-ChildItem -LiteralPath (Join-Path $source 'tts/strategies') -Directory).Count
$fake=Join-Path $source 'tts/strategies/test-engine'
$manifest=Get-Content -LiteralPath (Join-Path $repo 'tts/strategies/chatterbox-turbo/manifest.json') -Raw | ConvertFrom-Json
$manifest.id='test-engine';$manifest.name='Test engine';$manifest.capabilities.voiceCloning=$false
$manifest.PSObject.Properties.Remove('voiceReference')
$manifest.devices=@('cpu');$manifest.models=@();$manifest.prerequisites.visualCpp=$false
$manifest.files=@('install.ps1','uninstall.ps1','backend.py')
Write-Fixture (Join-Path $fake 'manifest.json') ($manifest|ConvertTo-Json -Depth 12)
Write-Fixture (Join-Path $fake 'backend.py') "raise RuntimeError('Discovery/build must not import strategy backends')"
Write-Fixture (Join-Path $fake 'install.ps1') @'
param($Context,[switch]$PrepareOnly)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path (Join-Path $Context.InstallPath ($Context.EnvironmentPath+'/Scripts')) -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $Context.InstallPath ($Context.EnvironmentPath+'/Scripts/python.exe')),'test-owned-runtime')
New-Item -ItemType Directory -Path (Join-Path $Context.InstallPath $Context.ModelsPath) -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $Context.InstallPath ($Context.ModelsPath+'/model.txt')),'test-owned-model')
if ($Context.InstallPath.EndsWith('failed-install')) {throw 'Intentional partial installation failure'}
exit 0
'@
Write-Fixture (Join-Path $fake 'uninstall.ps1') @'
param($Context)
$ErrorActionPreference='Stop'
if (-not (Test-Path -LiteralPath (Join-Path $Context.InstallPath ($Context.EnvironmentPath+'/Scripts/python.exe')))) {throw 'Hook ran after environment removal'}
if (Test-Path -LiteralPath (Join-Path $Context.InstallPath 'hook-fail.txt')) {throw 'Intentional hook failure'}
Write-Host 'TEST ENGINE UNINSTALL HOOK'
exit 0
'@
Write-Fixture (Join-Path $source 'scripts/check-prerequisites.ps1') @'
param([switch]$Cloud,[switch]$Local,[switch]$Voice,[string]$StrategyManifestJson)
$manifest=$StrategyManifestJson|ConvertFrom-Json
if ($Voice -and $manifest.id -notin @('test-engine','another-engine','chatterbox-turbo')) {throw 'Wrong prerequisite strategy'}
exit 0
'@
$secondFake = Join-Path $source 'tts/strategies/another-engine'
Copy-Item -LiteralPath $fake -Destination $secondFake -Recurse
$secondManifest = Get-Content -LiteralPath (Join-Path $secondFake 'manifest.json') -Raw | ConvertFrom-Json
$secondManifest.id = 'another-engine'; $secondManifest.name = 'Another test engine'
Write-Fixture (Join-Path $secondFake 'manifest.json') ($secondManifest | ConvertTo-Json -Depth 12)
. (Join-Path $repo 'tts/strategy-management.ps1')
$packages=@(Get-TtsStrategies $source)
Assert-True ($packages.Count -eq ($bundledCount+2) -and 'test-engine' -in $packages.Manifest.id) 'Drop-in folder adds another discovered engine without shared-code edits'
$bad=Get-Content -LiteralPath (Join-Path $fake 'manifest.json') -Raw
Write-Fixture (Join-Path $fake 'manifest.json') ($bad.Replace('"apiVersion":  1','"apiVersion":  99').Replace('"apiVersion": 1','"apiVersion": 99'))
$rejected=$false;try {$null=Get-TtsStrategies $source}catch{$rejected=$true}
Assert-True $rejected 'Unsupported API rejected without executing package code'
Write-Fixture (Join-Path $fake 'manifest.json') $bad
foreach ($mutation in @('duplicate-device','wrong-python-type','unvalidated-model-pin')) {
    $invalid = $bad | ConvertFrom-Json
    switch ($mutation) {
        'duplicate-device' { $invalid.devices = @('cpu','cpu') }
        'wrong-python-type' { $invalid.prerequisites.python = 3.11 }
        'unvalidated-model-pin' { $invalid.models = @(@{source='https://example.com/model';license='MIT';revision='';sha256=('a'*64)}) }
    }
    Write-Fixture (Join-Path $fake 'manifest.json') ($invalid | ConvertTo-Json -Depth 12)
    $rejected=$false;try {$null=Get-TtsStrategies $source}catch{$rejected=$true}
    Assert-True $rejected "Malformed strategy manifest rejected: $mutation"
}
Write-Fixture (Join-Path $fake 'manifest.json') $bad
$rejected=$false;try {$null=Resolve-TtsPackagePath $fake '../escape.ps1'}catch{$rejected=$true}
Assert-True $rejected 'Package traversal rejected'
$rejected=$false;try {$null=Get-TtsStrategy -Root $source -Id 'missing-engine'}catch{$rejected=$true}
Assert-True $rejected 'Unavailable engine rejected rather than substituted'
$originalUser=$env:USERPROFILE
. (Join-Path $repo 'scripts/installation-state.ps1')
$pathBefore=Get-StackRawUserPath | ConvertTo-Json -Compress
$policyBefore=Get-ExecutionPolicy -List|ConvertTo-Json -Compress
try {
    $env:USERPROFILE=Join-Path $fixture 'user'
    $install=Join-Path $fixture ("Installed engine's [root] "+[char]0xe9)
    & (Join-Path $source 'install.ps1') -Voice -TtsEngine test-engine -Yes -PersistCommandPath $false -InstallPath $install
    Assert-True ($LASTEXITCODE -eq 0) 'Real root installer dispatches drop-in strategy'
    $state=Get-Content -LiteralPath (Join-Path $install '.whas-installation.json') -Raw|ConvertFrom-Json
    Assert-True ($state.SchemaVersion -eq 2 -and $state.TtsStrategies[0].Id -eq 'test-engine') 'Installed strategy version and context recorded'
    Assert-True ($state.Files.Path -contains 'tts/engines/test-engine/models/model.txt') 'Private model ownership recorded'
    & {
        . (Join-Path $install 'tts/tts.ps1') -InstallPath $install
        function Get-TtsStatusResponse { @{running=$true;engine='test-engine'} }
        function Invoke-RestMethod { @{voices=@('default','provider-voice')} }
        $listed=@(tts-voice-list 6>&1 | ForEach-Object ToString)
        Assert-True ($listed -contains 'provider-voice') 'Voice listing uses the selected backend rather than Chatterbox cache filenames'
        $unsupported=$false
        try {tts-voice-add -Path 'not-needed.wav' -Name custom} catch {$unsupported=$_.Exception.Message -like '*does not support*'}
        Assert-True $unsupported 'Unsupported voice cloning rejected before service startup'
    }
    & (Join-Path $source 'install.ps1') -Voice -TtsEngine test-engine -Yes -PersistCommandPath $false -InstallPath $install
    Assert-True ($LASTEXITCODE -eq 0) 'Repeat installation uses the same owned environment'
    $installedManifest=Join-Path $install 'tts/strategies/test-engine/manifest.json'
    $installedHash=(Get-FileHash -LiteralPath $installedManifest).Hash
    $changedCatalog=$bad|ConvertFrom-Json;$changedCatalog.version='1.0.1'
    Write-Fixture (Join-Path $fake 'manifest.json') ($changedCatalog|ConvertTo-Json -Depth 12)
    & (Join-Path $source 'install.ps1') -Core -Yes -PersistCommandPath $false -InstallPath $install
    $repaired=Get-Content -LiteralPath (Join-Path $install '.whas-installation.json') -Raw|ConvertFrom-Json
    $trackedManifest=@($repaired.TtsStrategies[0].PackageFiles|Where-Object Path -ceq 'tts/strategies/test-engine/manifest.json')[0]
    Assert-True ($LASTEXITCODE -eq 0 -and (Get-FileHash -LiteralPath $installedManifest).Hash -ceq $installedHash -and $trackedManifest.SHA256 -ceq $installedHash) 'Shared repair preserves installed engine package and integrity record despite a newer catalog'
    & (Join-Path $source 'install.ps1') -Voice -TtsEngine another-engine -Yes -PersistCommandPath $false -InstallPath $install
    $multiEngine=Get-Content -LiteralPath (Join-Path $install '.whas-installation.json') -Raw | ConvertFrom-Json
    Assert-True ($LASTEXITCODE -eq 0 -and $multiEngine.TtsStrategies.Count -eq 2 -and $multiEngine.TtsStrategies.Id -contains 'test-engine' -and $multiEngine.TtsStrategies.Id -contains 'another-engine') 'A second engine installs without replacing the first'
    Assert-True ((Get-FileHash -LiteralPath $installedManifest).Hash -ceq $installedHash) 'Installing another engine does not upgrade an existing engine through catalog copying'
    Write-Fixture (Join-Path $fake 'manifest.json') $bad
    & {
        . (Join-Path $install 'tts/tts.ps1') -InstallPath $install
        $script:FixtureActive = $null
        $script:FixtureStarts = @()
        function Get-TtsStatusResponse { if ($script:FixtureActive) { @{running=$true;engine=$script:FixtureActive} } }
        function Stop-StackOwnedSpeech { param($Root) $script:FixtureActive = $null }
        function Invoke-TtsStartCore { $script:FixtureActive=$script:TtsRuntime.engine; $script:FixtureStarts += $script:TtsRuntime.engine }
        tts-start -Engine test-engine
        tts-start -Engine another-engine
        Assert-True ($script:FixtureActive -ceq 'another-engine' -and $script:FixtureStarts.Count -eq 2) 'Explicit selection switches only one active engine'
        $rejected=$false; try { tts-start -Engine missing-engine } catch { $rejected=$true }
        Assert-True ($rejected -and $script:FixtureActive -ceq 'another-engine') 'Unknown engine fails without stopping the active one'
        $rejected=$false; try { tts-start -Engine piper-tts } catch { $rejected=$_.Exception.Message -like '*not installed*' }
        Assert-True ($rejected -and $script:FixtureActive -ceq 'another-engine') 'Known uninstalled engine fails without switching'
        tts-engine-default test-engine
        Assert-True ((Get-TtsDefaultEngine) -ceq 'test-engine' -and $script:FixtureActive -ceq 'another-engine') 'Saving a default does not switch a running engine'
        $rejected=$false; try { tts-voice-add -Path 'not-needed.wav' -Name sample -Engine test-engine } catch { $rejected=$_.Exception.Message -like '*does not support*' }
        Assert-True ($rejected -and $script:FixtureActive -ceq 'another-engine') 'Unsupported operation fails before engine switching or startup'
        $originalReader = ${function:Get-TtsInstalledRuntime}
        function Get-TtsInstalledRuntime {
            param($Engine)
            [pscustomobject]@{Runtime=[pscustomobject]@{capabilities=[pscustomobject]@{voiceCloning=$true}};Package=[pscustomobject]@{Manifest=[pscustomobject]@{name='Transcript fixture';voiceReference=[pscustomobject]@{transcriptRequired=$true}}}}
        }
        try {
            $reference = Join-Path $fixture 'reference.wav'
            Write-Fixture $reference 'fixture'
            $rejected=$false; try { tts-voice-add -Path $reference -Name custom -Engine reference-engine } catch { $rejected=$_.Exception.Message -like '*Expected:*.txt*' }
            Assert-True ($rejected -and $script:FixtureActive -ceq 'another-engine') 'Manifest-declared transcript requirement fails before switching or loading'
            Write-Fixture ([IO.Path]::ChangeExtension($reference,'.txt')) ' '
            $rejected=$false; try { tts-voice-add -Path $reference -Name custom -Engine reference-engine } catch { $rejected=$_.Exception.Message -like '*1-4000*' }
            Assert-True ($rejected -and $script:FixtureActive -ceq 'another-engine') 'Empty transcript is rejected before model startup'
            function Read-Host { 'NO' }
            tts-voice-remove custom -Engine reference-engine
            Assert-True ($script:FixtureActive -ceq 'another-engine') 'Cancelled voice removal does not switch the running engine'
        }
        finally { Set-Item -LiteralPath Function:Get-TtsInstalledRuntime -Value $originalReader }
    }
    $nativeBin = Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack/bin'
    $defaultOutput = & (Join-Path $nativeBin 'tts-engine-default.exe') test-engine
    Assert-True ($LASTEXITCODE -eq 0) 'Native default management works without loading a profile'
    & (Join-Path $nativeBin 'tts-engine-uninstall.exe') another-engine --apply --yes
    Assert-True ($LASTEXITCODE -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $install 'tts/engines/another-engine/.venv/Scripts/python.exe'))) 'Native individual uninstall removes only the selected engine'
    & (Join-Path $nativeBin 'tts-engine-install.exe') another-engine --yes --device cpu
    Assert-True ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $install 'tts/engines/another-engine/.venv/Scripts/python.exe'))) 'Native engine install reuses the verified catalog'
    & (Join-Path $nativeBin 'tts-engine-uninstall.exe') test-engine --apply --yes
    Assert-True ($LASTEXITCODE -ne 0 -and (Test-Path -LiteralPath (Join-Path $install 'tts/engines/test-engine/.venv/Scripts/python.exe'))) 'Removing the default requires an explicit replacement'
    & (Join-Path $nativeBin 'tts-engine-uninstall.exe') test-engine --default-engine another-engine --apply --yes
    Assert-True ($LASTEXITCODE -eq 0 -and (Get-Content -LiteralPath (Join-Path $install 'tts/engines.json') -Raw | ConvertFrom-Json).defaultEngine -ceq 'another-engine') 'Individual removal saves the explicitly selected replacement default'
    & (Join-Path $nativeBin 'tts-engine-install.exe') test-engine --yes --device cpu
    Assert-True ($LASTEXITCODE -eq 0) 'Removed engine can be installed again without replacing the default'
    $legacy=Join-Path $fixture 'legacy-install'
    $legacySession=Start-StackInstallationTracking -InstallPath $legacy
    Write-Fixture (Join-Path $legacy '.venv/Scripts/python.exe') 'test-owned-runtime'
    Write-Fixture (Join-Path $legacy 'voices/personal.txt') 'preserve legacy voice'
    Complete-StackInstallationTracking -Session $legacySession -Succeeded $true
    & (Join-Path $source 'install.ps1') -Voice -TtsEngine test-engine -Yes -PersistCommandPath $false -InstallPath $legacy
    Assert-True ($LASTEXITCODE -ne 0 -and [IO.File]::ReadAllText((Join-Path $legacy '.venv/Scripts/python.exe')) -ceq 'test-owned-runtime' -and -not (Test-Path -LiteralPath (Join-Path $legacy 'tts/engines/test-engine'))) 'Owned legacy Chatterbox cannot be silently replaced by another strategy'
    Copy-Item -LiteralPath (Join-Path $fake 'install.ps1') -Destination (Join-Path $source 'tts/strategies/chatterbox-turbo/install.ps1') -Force
    & (Join-Path $source 'install.ps1') -Voice -TtsEngine chatterbox-turbo -Yes -PersistCommandPath $false -InstallPath $legacy
    $legacyState=Get-Content -LiteralPath (Join-Path $legacy '.whas-installation.json') -Raw | ConvertFrom-Json
    Assert-True ($LASTEXITCODE -eq 0 -and $legacyState.SchemaVersion -eq 2 -and $legacyState.TtsStrategies[0].Context.EnvironmentPath -ceq '.venv' -and $legacyState.TtsStrategies[0].Context.VoicesPath -ceq 'voices') 'Owned schema-1 Chatterbox layout migrates without relocating environment or voices'
    & (Join-Path $source 'install.ps1') -Voice -TtsEngine test-engine -Yes -PersistCommandPath $false -InstallPath $legacy
    $expandedLegacy=Get-Content -LiteralPath (Join-Path $legacy '.whas-installation.json') -Raw | ConvertFrom-Json
    Assert-True ($LASTEXITCODE -eq 0 -and $expandedLegacy.TtsStrategies.Count -eq 2) 'Migrated legacy Chatterbox can coexist with an additional engine'
    & (Join-Path $source 'uninstall.ps1') -InstallPath $legacy -Apply -Confirm:$false -PersistCommandPath $false
    Assert-True ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $legacy 'voices/personal.txt'))) 'Migrated installation cleanup preserves legacy personal voices'
    $failedInstall=Join-Path $fixture 'failed-install'
    & (Join-Path $source 'install.ps1') -Voice -TtsEngine test-engine -Yes -PersistCommandPath $false -InstallPath $failedInstall
    $failedState=Get-Content -LiteralPath (Join-Path $failedInstall '.whas-installation.json') -Raw | ConvertFrom-Json
    Assert-True ($LASTEXITCODE -ne 0 -and $failedState.Status -eq 'Interrupted' -and $failedState.Files.Path -contains 'tts/engines/test-engine/models/model.txt') 'Partial failed installation retains a complete ownership record'
    & (Join-Path $source 'uninstall.ps1') -InstallPath $failedInstall -Apply -Confirm:$false -PersistCommandPath $false
    Assert-True ($LASTEXITCODE -eq 0 -and -not (Test-Path -LiteralPath $failedInstall)) 'Main uninstaller cleans a partially installed strategy'
    $setupExe=Join-Path $fixture 'strategy-setup.exe'
    & (Join-Path $source 'scripts/build-setup.ps1') -OutputPath $setupExe
    Assert-True ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $setupExe)) 'Standalone build discovers drop-in package'
    $multiInstall = Join-Path $fixture 'native-multiple'
    & $setupExe --install --voice --tts-engine 'test-engine,another-engine' --install-path $multiInstall --yes --no-path
    $multiState = Get-Content -LiteralPath (Join-Path $multiInstall '.whas-installation.json') -Raw | ConvertFrom-Json
    Assert-True ($LASTEXITCODE -eq 0 -and $multiState.TtsStrategies.Count -eq 2 -and (Get-Content -LiteralPath (Join-Path $multiInstall 'tts/engines.json') -Raw | ConvertFrom-Json).defaultEngine -ceq 'test-engine') 'Standalone multi-selection installs both engines and sets the first as default'
    & $setupExe --uninstall --install-path $multiInstall --apply --yes --no-path
    Assert-True ($LASTEXITCODE -eq 0 -and -not (Test-Path -LiteralPath $multiInstall)) 'Full uninstall cleans all installed engine runtimes'
    foreach ($bundled in @($packages | Where-Object { $_.Manifest.id -notin @('test-engine','another-engine') })) {
        $planText = (& $setupExe --plan --voice --tts-engine $bundled.Manifest.id | Out-String)
        Assert-True ($LASTEXITCODE -eq 0 -and $planText.Contains($bundled.Manifest.id)) "Standalone catalog exposes bundled strategy: $($bundled.Manifest.id)"
    }
    . (Join-Path $repo 'scripts/installation-state.ps1')
    . (Join-Path $repo 'scripts/command-registration.ps1')
    . (Join-Path $repo 'scripts/uninstall.ps1')
    Write-Fixture (Join-Path $install 'hook-fail.txt') 'test'
    $before=(Get-FileHash -LiteralPath (Join-Path $install '.whas-installation.json')).Hash
    $plan=Get-StackUninstallPlan $install
    Assert-True ($plan.TtsHooks.Count -eq 2 -and (Get-FileHash -LiteralPath (Join-Path $install '.whas-installation.json')).Hash -ceq $before) 'Preview reads recorded cleanup without executing hooks or changing state'
    $installedHook=Join-Path $install 'tts/strategies/test-engine/uninstall.ps1'
    $hookBytes=[IO.File]::ReadAllBytes($installedHook)
    [IO.File]::AppendAllText($installedHook,"`n# edited")
    $rejected=$false;try{$null=Get-StackUninstallPlan $install}catch{$rejected=$true}
    Assert-True $rejected 'Modified installed hook rejected before execution'
    [IO.File]::WriteAllBytes($installedHook,$hookBytes)
    $rejected=$false;try{Invoke-StackUninstall -Plan (Get-StackUninstallPlan $install) -Confirm:$false -PersistPath $false -ReceiptDirectory (Join-Path $fixture 'receipts')}catch{$rejected=$true}
    Assert-True ($rejected -and (Test-Path -LiteralPath $installedHook)) 'Hook failure retains installation and reports failure'
    Remove-Item -LiteralPath (Join-Path $install 'hook-fail.txt')
    # Discarding the source strategy must not prevent installed cleanup.
    $removedSource=Join-Path $fixture 'removed-source-package'
    if (-not ([IO.Path]::GetFullPath($fake).StartsWith([IO.Path]::GetFullPath($fixture)+'\')) -or
        -not ([IO.Path]::GetFullPath($removedSource).StartsWith([IO.Path]::GetFullPath($fixture)+'\'))) {throw 'Fixture move escaped its test root'}
    Move-Item -LiteralPath $fake -Destination $removedSource
    Write-Fixture (Join-Path $install 'voices/test-engine/personal.txt') 'preserve'
    Invoke-StackUninstall -Plan (Get-StackUninstallPlan $install) -Confirm:$false -PersistPath $false -ReceiptDirectory (Join-Path $fixture 'receipts')
    Assert-True (-not (Test-Path -LiteralPath $installedHook)) 'Main uninstaller invokes installed hook then removes owned package'
    Assert-True (Test-Path -LiteralPath (Join-Path $install 'voices/test-engine/personal.txt')) 'Personal voice data preserved'
    $null=Get-StackUninstallPlan $install
    Assert-True $true 'Repeat preview works after removal with retained personal data'
    & $setupExe --install --voice --tts-engine chatterbox-turbo --install-path $install --yes --no-path
    $reinstalled=Get-Content -LiteralPath (Join-Path $install '.whas-installation.json') -Raw | ConvertFrom-Json
    Assert-True ($LASTEXITCODE -eq 0 -and $reinstalled.TtsStrategies[0].Id -ceq 'chatterbox-turbo' -and [IO.File]::ReadAllText((Join-Path $install 'voices/test-engine/personal.txt')) -ceq 'preserve') 'Native engine selection after completed uninstall preserves retained personal voices'
    & $setupExe --uninstall --install-path $install --apply --yes --no-path
    Assert-True ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $install 'voices/test-engine/personal.txt'))) 'Native cleanup after engine change preserves the original user data'
    & $setupExe --install --core --install-path $install --yes --no-path
    Assert-True ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $install 'tts/strategies/chatterbox-turbo/manifest.json'))) 'Base reinstall after completed removal restores available catalog packages'
    & $setupExe --uninstall --install-path $install --apply --yes --no-path
    Assert-True ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $install 'voices/test-engine/personal.txt'))) 'Base reinstall cleanup keeps retained voices'
    $nativeInstall=Join-Path $fixture 'native-install'
    & $setupExe --install --voice --tts-engine test-engine --install-path $nativeInstall --yes --no-path
    Assert-True ($LASTEXITCODE -eq 0) 'Standalone EXE installs the bundled drop-in package after source removal'
    $statusExe=Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack/bin/tts-status.exe'
    $statusCommand="& '"+$statusExe.Replace("'","''")+"'"
    & (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -ExecutionPolicy Restricted -Command $statusCommand
    Assert-True ($LASTEXITCODE -eq 0) 'Strategy-aware native TTS command loads under Restricted without a policy override'
    & $setupExe --uninstall --install-path $nativeInstall --apply --yes --no-path
    Assert-True ($LASTEXITCODE -eq 0 -and -not (Test-Path -LiteralPath $nativeInstall)) 'Standalone main uninstaller invokes installed strategy hook and removes the installation'
    Assert-True ((Get-StackRawUserPath | ConvertTo-Json -Compress) -ceq $pathBefore) 'Persistent PATH unchanged'
    Assert-True ((Get-ExecutionPolicy -List|ConvertTo-Json -Compress) -ceq $policyBefore) 'Execution policies unchanged'
}
finally {$env:USERPROFILE=$originalUser;Write-Host "Retained fixture: $fixture"}
