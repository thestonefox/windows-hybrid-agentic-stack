#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts\installation-state.ps1')
. (Join-Path $repo 'scripts\command-registration.ps1')
. (Join-Path $repo 'scripts\uninstall.ps1')
$originalUserProfile = $env:USERPROFILE
$originalPath = $env:Path
$pathBefore = Get-StackRawUserPath | ConvertTo-Json -Compress
$policiesBefore = Get-ExecutionPolicy -List | ConvertTo-Json -Compress
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('whas-uninstall-tests-' + [guid]::NewGuid().ToString('N'))
$env:USERPROFILE = Join-Path $testRoot 'user'
$receipts = Join-Path $testRoot 'receipts'
$script:Models = @()
$script:DeletedModels = @()
function Get-StackOllamaModels { return $script:Models }
function Invoke-RestMethod {
    param($Uri,$Method,$ContentType,$Body,$TimeoutSec)
    $request = $Body | ConvertFrom-Json
    if ($Uri -eq 'http://127.0.0.1:11434/api/delete' -and $Method -eq 'Delete') {
        $script:DeletedModels += $request.model
        $script:Models = @($script:Models | Where-Object name -ne $request.model)
    }
    elseif ($Uri -ne 'http://127.0.0.1:11434/api/generate') { throw "Unexpected network request: $Uri" }
    return @{}
}
function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}
function Write-Fixture {
    param([string]$Path,[string]$Content)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path,$Content,(New-Object Text.UTF8Encoding($true)))
}
function New-Fixture {
    param([string]$Name, [switch]$Register, [string]$ModelName)
    $root = Join-Path $testRoot $Name
    $session = Start-StackInstallationTracking -InstallPath $root -ManagedModelName $ModelName
    Write-Fixture (Join-Path $root 'scripts\program.ps1') '# installed program'
    Write-Fixture (Join-Path $root 'scripts\agent-commands.ps1') '# fixture command runtime'
    Write-Fixture (Join-Path $root '.venv\Lib\package.py') '# private package'
    if ($Register) { Install-StackCommandRegistration -InstallPath $root -PersistPath $false }
    return $session
}
function Apply-Plan {
    param($Plan)
    Invoke-StackUninstall -Plan $Plan -PersistPath $false -ReceiptDirectory $receipts -Confirm:$false
}
try {
    [IO.Directory]::CreateDirectory($testRoot) | Out-Null
    foreach ($name in @('empty.bin','bytes [literal].bin')) {
        $hashFile = Join-Path $testRoot $name
        $bytes = if ($name -eq 'empty.bin') { New-Object byte[] 0 } else { [byte[]](0..255) }
        [IO.File]::WriteAllBytes($hashFile, $bytes)
        Assert-True ((Get-StackFileSHA256 $hashFile) -ceq (Get-FileHash -LiteralPath $hashFile -Algorithm SHA256).Hash) 'Streaming hash matches the independent SHA256 reader for empty and binary files'
    }
    Push-Location $testRoot
    try {
        Assert-True ((Get-StackFileSHA256 'bytes [literal].bin') -ceq (Get-FileHash -LiteralPath 'bytes [literal].bin' -Algorithm SHA256).Hash) 'Relative hash paths use the PowerShell working directory and remain literal'
    }
    finally { Pop-Location }
    Write-Host 'PASS: Streaming SHA256 parity and relative literal paths'

    $largeHashPath = Join-Path $testRoot 'large-progress.bin'
    $largeBytes = New-Object byte[] (17MB + 7)
    $largeBytes[0] = 41; $largeBytes[$largeBytes.Length - 1] = 93
    [IO.File]::WriteAllBytes($largeHashPath, $largeBytes)
    $progress = New-StackOperationProgress 'Hashing fixture' -Enabled
    $progress.LastUpdate = -2000L
    $hashOutput = @(Get-StackFileSHA256 $largeHashPath -Progress $progress 6>&1)
    $hash = @($hashOutput | Where-Object { $_ -is [string] })[-1]
    Assert-True ($hash -ceq (Get-FileHash -LiteralPath $largeHashPath -Algorithm SHA256).Hash) 'Chunked progress hash matches independent SHA256 with a partial final block'
    Assert-True (@($hashOutput | Where-Object { $_.ToString() -like '*Reading large-progress.bin:*MiB*' }).Count -gt 0) 'Long-file verification emits progress from inside the hash'
    Remove-Item -LiteralPath $largeHashPath
    Write-Host 'PASS: Long-file progress and independent SHA256 parity'

    $session = New-Fixture "fresh A's [stack]"
    $hidden=Join-Path $session.Root 'owned-hidden-directory'
    [IO.Directory]::CreateDirectory($hidden)|Out-Null
    [IO.File]::SetAttributes($hidden,([IO.File]::GetAttributes($hidden) -bor [IO.FileAttributes]::Hidden))
    Install-StackCommandRegistration -InstallPath $session.Root -PersistPath $false
    Complete-StackInstallationTracking $session $true
    $manifest = Join-Path $session.Root '.whas-installation.json'
    $manifestHash = Get-StackFileSHA256 $manifest
    $plan = Get-StackUninstallPlan $session.Root
    Invoke-StackUninstall -Plan $plan -PersistPath $false -ReceiptDirectory $receipts -WhatIf
    Assert-True ((Get-StackFileSHA256 $manifest) -ceq $manifestHash -and -not (Test-Path -LiteralPath $receipts)) 'Preview and WhatIf cause no writes'
    Write-Fixture (Join-Path $session.Root 'tts\service.log') 'generated log after install'
    Write-Fixture (Join-Path $session.Root '.venv\Lib\__pycache__\generated.pyc') 'generated bytecode after install'
    Write-Fixture (Join-Path $session.Root '.venv\Lib\__pycache__\generated.py311.1.nbc') 'generated Numba compiled code'
    Write-Fixture (Join-Path $session.Root '.venv\Lib\__pycache__\generated.py311.nbi') 'generated Numba cache index'
    Apply-Plan (Get-StackUninstallPlan $session.Root)
    Assert-True (-not (Test-Path -LiteralPath $session.Root)) 'Fresh installation fully removed, including generated cache/logs'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack'))) 'Owned registration removed'
    Apply-Plan (Get-StackUninstallPlan $session.Root)
    Write-Host 'PASS: Preview/WhatIf, custom path, fresh removal, native registration and repeat uninstall'

    $session = New-Fixture 'edit-after-preview'
    Complete-StackInstallationTracking $session $true
    $plan = Get-StackUninstallPlan $session.Root
    $editedFile = Join-Path $session.Root 'scripts\program.ps1'
    Write-Fixture $editedFile '# user changed this after seeing the preview'
    Apply-Plan $plan
    Assert-True ([IO.File]::ReadAllText($editedFile).Contains('user changed this')) 'Changes after preview are preserved when applying the plan'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $session.Root '.venv\Lib\package.py'))) 'Unchanged owned files are still removed'
    Write-Host 'PASS: Applying an earlier preview preserves subsequent file edits'

    $session = New-Fixture 'running-service-log'
    $logPath = Join-Path $session.Root 'tts\service.log'
    Write-Fixture $logPath 'speech service is running'
    $writer = [IO.File]::Open($logPath, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    try {
        $ordinaryHashRejected = $false
        try { $null = Get-StackFileSHA256 $logPath } catch { $ordinaryHashRejected = $true }
        Assert-True $ordinaryHashRejected 'Fixture reproduces the default hash reader conflict with an open writer'
        Complete-StackInstallationTracking $session $true
        $manifest = Join-Path $session.Root '.whas-installation.json'
        $manifestHash = Get-StackFileSHA256 $manifest
        $plan = Get-StackUninstallPlan $session.Root
        Assert-True (@($plan.DeleteFiles | Where-Object Path -eq 'tts/service.log').Count -eq 1) 'Preview can hash a generated log while the service holds it open'
        Assert-True ((Get-StackFileSHA256 $manifest) -ceq $manifestHash) 'Open-log preview preserves ownership record'
    }
    finally { $writer.Dispose() }
    Apply-Plan $plan
    Assert-True (-not (Test-Path -LiteralPath $session.Root)) 'Generated log is removed after its writer closes'
    Write-Host 'PASS: Tracking and preview with a live service log writer, followed by removal'

    $root = Join-Path $testRoot 'existing-content'
    Write-Fixture (Join-Path $root 'config\config.json') '{"original":"user setting"}'
    Write-Fixture (Join-Path $root 'notes.txt') 'pre-existing user file'
    Write-Fixture (Join-Path $root '.venv\old.py') 'pre-existing environment'
    $originalBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root 'config\config.json')))
    $session = Start-StackInstallationTracking $root
    Write-Fixture (Join-Path $root 'config\config.json') '{"installed":"changed setting"}'
    Write-Fixture (Join-Path $root 'scripts\program.ps1') '# installed program'
    Write-Fixture (Join-Path $root '.venv\new.py') 'new package inside old environment'
    Complete-StackInstallationTracking $session $true
    $plan = Get-StackUninstallPlan $root
    Assert-True ($plan.RestoreFiles.Count -eq 1) 'Original config restoration planned'
    Apply-Plan $plan
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root 'config\config.json'))) -ceq $originalBytes) 'Original config restored byte-for-byte'
    Assert-True ((Test-Path -LiteralPath (Join-Path $root 'notes.txt')) -and (Test-Path -LiteralPath (Join-Path $root '.venv\old.py')) -and (Test-Path -LiteralPath (Join-Path $root '.venv\new.py'))) 'Existing files and environment preserved'
    Apply-Plan (Get-StackUninstallPlan $root)
    Write-Host 'PASS: Restore original config, preserve pre-existing content/environment, repeat with retained data'

    $session = New-Fixture 'modified-and-added'
    Complete-StackInstallationTracking $session $true
    Write-Fixture (Join-Path $session.Root 'scripts\program.ps1') '# user edited this program'
    Write-Fixture (Join-Path $session.Root 'voices\my-recording.wav') 'custom user recording'
    Write-Fixture (Join-Path $session.Root 'new-notes.txt') 'user added file'
    Write-Fixture (Join-Path $session.Root '.venv\Lib\__pycache__\notes.txt') 'user cache-directory note'
    Apply-Plan (Get-StackUninstallPlan $session.Root)
    Assert-True ([IO.File]::ReadAllText((Join-Path $session.Root 'scripts\program.ps1')).Contains('user edited')) 'Modified installed file preserved'
    Assert-True ((Test-Path -LiteralPath (Join-Path $session.Root 'voices\my-recording.wav')) -and (Test-Path -LiteralPath (Join-Path $session.Root 'new-notes.txt'))) 'New files and custom voices preserved'
    Assert-True (Test-Path -LiteralPath (Join-Path $session.Root '.venv\Lib\__pycache__\notes.txt')) 'Unknown files inside cache directories are preserved'
    Write-Host 'PASS: Preserve edited files, unknown files and custom voices'

    $session = New-Fixture 'repeat-install-user-change'
    Write-Fixture (Join-Path $session.Root 'config\config.json') '{"first":"installed"}'
    Complete-StackInstallationTracking $session $true
    Write-Fixture (Join-Path $session.Root 'config\config.json') '{"user":"edited between installs"}'
    $userBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $session.Root 'config\config.json')))
    $session = Start-StackInstallationTracking $session.Root
    Write-Fixture (Join-Path $session.Root 'config\config.json') '{"second":"installed"}'
    Complete-StackInstallationTracking $session $true
    Apply-Plan (Get-StackUninstallPlan $session.Root)
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $session.Root 'config\config.json'))) -ceq $userBytes) 'User edits made between installs restored'
    Write-Host 'PASS: Reinstallation retains user edits for later restoration'

    $session = New-Fixture 'repeat-engine-runtime-change'
    $runtimeFile = Join-Path $session.Root 'tts/engines/example/runtime.json'
    Write-Fixture $runtimeFile '{"installed":"original runtime"}'
    Complete-StackInstallationTracking $session $true
    Write-Fixture $runtimeFile '{"user":"edited runtime between installs"}'
    $runtimeBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($runtimeFile))
    $session = Start-StackInstallationTracking $session.Root
    Write-Fixture $runtimeFile '{"installed":"replacement runtime"}'
    Complete-StackInstallationTracking $session $true
    Apply-Plan (Get-StackUninstallPlan $session.Root)
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($runtimeFile)) -ceq $runtimeBytes) 'Edited per-engine runtime restored byte-for-byte after repeat installation'
    Write-Host 'PASS: Reinstallation preserves edited per-engine runtime settings'

    $session = New-Fixture 'repeat-generated-cache'
    Complete-StackInstallationTracking $session $true
    Write-Fixture (Join-Path $session.Root '.venv\Lib\__pycache__\runtime.pyc') 'bytecode created between installs'
    $session = Start-StackInstallationTracking $session.Root
    Complete-StackInstallationTracking $session $true
    Apply-Plan (Get-StackUninstallPlan $session.Root)
    Assert-True (-not (Test-Path -LiteralPath $session.Root)) 'Generated cache remains removable after repeat install'

    $sessionA = New-Fixture 'inactive-installation' -Register
    Complete-StackInstallationTracking $sessionA $true
    $sessionB = New-Fixture 'active-installation' -Register
    Complete-StackInstallationTracking $sessionB $true
    $registrationState = Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack\commands.json'
    $activeHash = Get-StackFileSHA256 $registrationState
    Apply-Plan (Get-StackUninstallPlan $sessionA.Root)
    Assert-True ((Get-StackFileSHA256 $registrationState) -ceq $activeHash) 'Removing old installation preserves active installation registration'
    Apply-Plan (Get-StackUninstallPlan $sessionB.Root)
    Write-Host 'PASS: Uninstalling an inactive root preserves another active installation'

    $sessionA = New-Fixture 'restore-earlier-root' -Register
    Complete-StackInstallationTracking $sessionA $true
    $registrationState = Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack\commands.json'
    $beforeNewInstall = Get-StackFileSHA256 $registrationState
    $sessionB = New-Fixture 'replacement-root' -Register
    Complete-StackInstallationTracking $sessionB $true
    Apply-Plan (Get-StackUninstallPlan $sessionB.Root)
    Assert-True ((Get-StackFileSHA256 $registrationState) -ceq $beforeNewInstall) 'Previous registration restored byte-for-byte'
    Assert-True (Test-Path -LiteralPath $sessionA.Root) 'Earlier installation preserved'
    Apply-Plan (Get-StackUninstallPlan $sessionA.Root)
    Write-Host 'PASS: Replaced command registration restored when its installation still exists'

    $session = New-Fixture 'installed-uninstaller'
    foreach ($relative in @('uninstall.ps1','scripts\script-invocation.ps1','scripts\installation-state.ps1','scripts\uninstall.ps1','scripts\command-registration.ps1')) {
        $destination = Join-Path $session.Root $relative
        Copy-Item -LiteralPath (Join-Path $repo $relative) -Destination $destination
    }
    Complete-StackInstallationTracking $session $true
    & (Join-Path $session.Root 'uninstall.ps1')
    Assert-True ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $session.Root)) 'Installed CLI defaults to preview'
    & (Join-Path $session.Root 'uninstall.ps1') -Apply -Confirm:$false -PersistCommandPath $false
    Assert-True ($LASTEXITCODE -eq 0 -and -not (Test-Path -LiteralPath $session.Root)) 'Installed uninstaller can remove itself with explicit apply'
    Write-Host 'PASS: Installed CLI preview and explicit apply; self-removal'

    $script:Models = @([pscustomobject]@{ name='qwen3:8b'; digest=('a'*64) })
    $session = New-Fixture 'models-retained' -ModelName 'whas-test-ctx4096'
    $script:Models += [pscustomobject]@{ name='whas-test-ctx4096:latest'; digest=('b'*64) }
    Complete-StackInstallationTracking $session $true
    Apply-Plan (Get-StackUninstallPlan $session.Root)
    Assert-True ($script:Models.Count -eq 2 -and $script:DeletedModels.Count -eq 0) 'All models retained by default'
    $script:Models = @([pscustomobject]@{ name='qwen3:8b'; digest=('a'*64) })
    $session = New-Fixture 'owned-model' -ModelName 'whas-test-ctx4096'
    $script:Models += [pscustomobject]@{ name='whas-test-ctx4096:latest'; digest=('c'*64) }
    Complete-StackInstallationTracking $session $true
    Apply-Plan (Get-StackUninstallPlan $session.Root -RemoveManagedModels)
    Assert-True ($script:Models.Count -eq 1 -and $script:Models[0].name -eq 'qwen3:8b' -and $script:DeletedModels.Count -eq 1) 'Only verified owned model deleted with opt-in'
    $session = New-Fixture 'pre-existing-model' -ModelName 'whas-existing-ctx4096'
    # Simulate a pre-existing managed tag by capturing it in a second session.
    $script:Models += [pscustomobject]@{ name='whas-existing-ctx4096:latest'; digest=('d'*64) }
    $session.ModelBefore = @($script:Models)
    Complete-StackInstallationTracking $session $true
    Apply-Plan (Get-StackUninstallPlan $session.Root -RemoveManagedModels)
    Assert-True (@($script:Models | Where-Object name -eq 'whas-existing-ctx4096:latest').Count -eq 1) 'Existing model never adopted or deleted'
    $session = New-Fixture 'changed-model' -ModelName 'whas-changed-ctx4096'
    $script:Models += [pscustomobject]@{ name='whas-changed-ctx4096:latest'; digest=('e'*64) }
    Complete-StackInstallationTracking $session $true
    ($script:Models | Where-Object name -eq 'whas-changed-ctx4096:latest').digest = 'f'*64
    Apply-Plan (Get-StackUninstallPlan $session.Root -RemoveManagedModels)
    Assert-True (@($script:Models | Where-Object name -eq 'whas-changed-ctx4096:latest').Count -eq 1) 'Changed model digest preserved'
    Write-Host 'PASS: Default model retention, explicit owned-model removal, existing and changed models preserved'

    $sessionA = New-Fixture 'shared-model-owner' -Register -ModelName 'whas-shared-ctx4096'
    $script:Models += [pscustomobject]@{ name='whas-shared-ctx4096:latest'; digest=('1'*64) }
    Complete-StackInstallationTracking $sessionA $true
    $sessionB = New-Fixture 'shared-model-user' -Register -ModelName 'whas-shared-ctx4096'
    Complete-StackInstallationTracking $sessionB $true
    Apply-Plan (Get-StackUninstallPlan $sessionA.Root -RemoveManagedModels)
    Assert-True (@($script:Models | Where-Object name -eq 'whas-shared-ctx4096:latest').Count -eq 1) 'Model used by another registered installation retained'
    Apply-Plan (Get-StackUninstallPlan $sessionB.Root -RemoveManagedModels)
    Write-Host 'PASS: Shared model preserved for another registered installation'

    $session = New-Fixture 'interrupted'
    Complete-StackInstallationTracking $session $false
    Assert-True ((Read-StackInstallationState $session.Root).Status -eq 'Interrupted') 'Interrupted install recorded'
    Apply-Plan (Get-StackUninstallPlan $session.Root)
    Assert-True (-not (Test-Path -LiteralPath $session.Root)) 'Normal interrupted installation can be removed'
    $session = New-Fixture 'tampered-manifest'
    Complete-StackInstallationTracking $session $true
    $state = Read-StackInstallationState $session.Root
    $state.Files[0].Path = '../outside.txt'
    Write-StackInstallationState $session.Root $state
    $rejected = $false
    try { $null = Get-StackUninstallPlan $session.Root } catch { $rejected = $true }
    Assert-True $rejected 'Traversal in manifest rejected'
    $rejected = $false
    try { $null = Get-StackUninstallPlan $env:USERPROFILE } catch { $rejected = $true }
    Assert-True $rejected 'Home directory rejected'
    Write-Host 'PASS: Interrupted installs, invalid manifest paths and protected roots'

    $session = New-Fixture 'reparse-rejection'
    Complete-StackInstallationTracking $session $true
    $outside = Join-Path $testRoot 'outside-link-target'
    Write-Fixture (Join-Path $outside 'keep.txt') 'outside file must survive'
    $link = Join-Path $session.Root 'junction'
    New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
    try {
        $rejected = $false
        try { $null = Get-StackUninstallPlan $session.Root } catch { $rejected = $true }
        Assert-True $rejected 'Directory junction rejected before removal'
        Assert-True ([IO.File]::ReadAllText((Join-Path $outside 'keep.txt')) -ceq 'outside file must survive') 'Junction target untouched'
    }
    finally { [IO.Directory]::Delete($link) }
    Write-Host 'PASS: Reparse-point rejection preserves the outside target'

    $script:FakeProcesses = @()
    $script:StoppedProcesses = @()
    $script:SimulateExitRace = $false
    function Get-CimInstance {
        param($ClassName,$Filter,$ErrorAction)
        if ($Filter -match '^ProcessId=(\d+)$') {
            $requested = [int]$Matches[1]
            $found = @($script:FakeProcesses | Where-Object ProcessId -eq $requested)
            if ($script:SimulateExitRace -and $requested -eq 100 -and $script:StoppedProcesses -contains 101 -and $found.Count -eq 1) {
                $found[0].CommandLine = $null
                $script:FakeProcesses = @($script:FakeProcesses | Where-Object ProcessId -ne 100)
            }
            return $found
        }
        return $script:FakeProcesses
    }
    function Stop-Process {
        param($Id,[switch]$Force,$ErrorAction)
        $script:StoppedProcesses += $Id
        $script:FakeProcesses = @($script:FakeProcesses | Where-Object ProcessId -ne $Id)
    }
    $session = New-Fixture 'speech-never-started'
    Write-Fixture (Join-Path $session.Root 'tts\tts_service.py') '# fixture service'
    Complete-StackInstallationTracking $session $true
    $script:FakeProcesses = @(
        [pscustomobject]@{ Name='System Idle Process'; ProcessId=0; ParentProcessId=0; CreationDate=$null; CommandLine=$null; ExecutablePath=$null }
    )
    Apply-Plan (Get-StackUninstallPlan $session.Root)
    Assert-True (-not (Test-Path -LiteralPath $session.Root) -and $script:StoppedProcesses.Count -eq 0) 'Never-started speech ignores system PID zero and removes owned files'
    Write-Host 'PASS: Speech installed without a PID file uninstalls without touching any process'

    $session = New-Fixture 'pid-verification'
    Write-Fixture (Join-Path $session.Root 'tts\tts_service.py') '# fixture service'
    Complete-StackInstallationTracking $session $true
    Write-Fixture (Join-Path $session.Root 'tts\service.pid') '101'
    $marker = '"' + (Join-Path $session.Root 'tts\tts_service.py') + '"'
    $script:FakeProcesses = @(
        [pscustomobject]@{ Name='explorer.exe'; ProcessId=101; ParentProcessId=0; CreationDate=[datetime]'2026-01-01'; CommandLine='unrelated'; ExecutablePath='C:\Windows\explorer.exe' }
    )
    $manifestHash = Get-StackFileSHA256 (Join-Path $session.Root '.whas-installation.json')
    $rejected = $false
    try { Apply-Plan (Get-StackUninstallPlan $session.Root) } catch { $rejected = $true }
    Assert-True ($rejected -and $script:StoppedProcesses.Count -eq 0 -and (Get-StackFileSHA256 (Join-Path $session.Root '.whas-installation.json')) -ceq $manifestHash) 'Unrelated PID rejected before file deletion'
    $script:FakeProcesses = @([pscustomobject]@{ Name='python.exe'; ProcessId=102; ParentProcessId=999; CreationDate=[datetime]'2026-01-01'; CommandLine=('-u ' + $marker); ExecutablePath='C:\Python\python.exe' })
    $rejected = $false
    try { Apply-Plan (Get-StackUninstallPlan $session.Root) } catch { $rejected = $true }
    Assert-True ($rejected -and $script:StoppedProcesses.Count -eq 0) 'Unverified orphan worker blocks deletion'
    $script:FakeProcesses = @(
        [pscustomobject]@{ Name='python.exe'; ProcessId=101; ParentProcessId=0; CreationDate=[datetime]'2026-01-01'; CommandLine=('-u ' + $marker); ExecutablePath=(Join-Path $session.Root '.venv\Scripts\python.exe') },
        [pscustomobject]@{ Name='python.exe'; ProcessId=102; ParentProcessId=101; CreationDate=[datetime]'2026-01-01'; CommandLine=('-u ' + $marker); ExecutablePath='C:\Python\python.exe' },
        [pscustomobject]@{ Name='python.exe'; ProcessId=103; ParentProcessId=0; CreationDate=[datetime]'2026-01-01'; CommandLine='unrelated.py'; ExecutablePath='C:\Python\python.exe' }
    )
    Apply-Plan (Get-StackUninstallPlan $session.Root)
    Assert-True ($script:StoppedProcesses.Count -eq 2 -and $script:StoppedProcesses -contains 101 -and $script:StoppedProcesses -contains 102 -and $script:FakeProcesses[0].ProcessId -eq 103) 'Only verified launcher and worker stopped'
    Write-Host 'PASS: PID reuse protection; only matching launcher and worker stopped'

    $session = New-Fixture 'speech-exit-race'
    Write-Fixture (Join-Path $session.Root 'tts\tts_service.py') '# fixture service'
    Complete-StackInstallationTracking $session $true
    Write-Fixture (Join-Path $session.Root 'tts\service.pid') '101'
    $marker = '"' + (Join-Path $session.Root 'tts\tts_service.py') + '"'
    $script:StoppedProcesses = @()
    $script:FakeProcesses = @(
        [pscustomobject]@{ Name='python.exe'; ProcessId=101; ParentProcessId=0; CreationDate=[datetime]'2026-01-01'; CommandLine=('-u ' + $marker); ExecutablePath=(Join-Path $session.Root '.venv\Scripts\python.exe') },
        [pscustomobject]@{ Name='python.exe'; ProcessId=100; ParentProcessId=101; CreationDate=[datetime]'2026-01-01'; CommandLine=('-u ' + $marker); ExecutablePath='C:\Python\python.exe' }
    )
    $script:SimulateExitRace = $true
    try { Apply-Plan (Get-StackUninstallPlan $session.Root) }
    finally { $script:SimulateExitRace = $false }
    Assert-True ($script:StoppedProcesses.Count -eq 1 -and $script:StoppedProcesses[0] -eq 101 -and $script:FakeProcesses.Count -eq 0 -and -not (Test-Path -LiteralPath $session.Root)) 'Exiting worker with an empty command line is allowed to exit without another kill'
    Write-Host 'PASS: Launcher shutdown race waits for the exiting worker'

    $realReader = (Get-Item Function:Get-StackRawUserPath).ScriptBlock
    $realWriter = (Get-Item Function:Set-StackRawUserPath).ScriptBlock
    $realPathEditor = (Get-Item Function:Set-StackUserCommandPath).ScriptBlock
    try {
        # Exercise PATH decisions with an in-memory registry adapter, never HKCU writes.
        function Get-StackRawUserPath {
            [pscustomobject]@{ Existed=$script:FakePath.Existed; Value=$script:FakePath.Value; Kind=$script:FakePath.Kind }
        }
        function Set-StackRawUserPath {
            param($PathState,$ExpectedValue)
            Assert-True ($script:FakePath.Value -ceq $ExpectedValue) 'Expected PATH value checked before restoration'
            $script:RawRestores++
            $script:FakePath = [pscustomobject]@{ Existed=$PathState.Existed; Value=$PathState.Value; Kind=$PathState.Kind }
        }
        function Set-StackUserCommandPath {
            param($Directory,[switch]$Remove)
            Assert-True ([bool]$Remove) 'Uninstall only removes its PATH entry'
            $value = @($script:FakePath.Value -split ';' | Where-Object { $_ -ine $Directory }) -join ';'
            $script:FakePath.Value = $value
            if ($value.Length -eq 0) { $script:FakePath.Existed = $false }
            return $true
        }
        foreach ($case in @('absent','empty-string','references','concurrent-entry')) {
            $env:USERPROFILE = Join-Path $testRoot ('path-user-' + $case)
            $script:FakePath = switch ($case) {
                'absent' { [pscustomobject]@{ Existed=$false; Value=''; Kind='ExpandString' } }
                'empty-string' { [pscustomobject]@{ Existed=$true; Value=''; Kind='String' } }
                default { [pscustomobject]@{ Existed=$true; Value='C:\First;;%USERPROFILE%\other'; Kind='ExpandString' } }
            }
            $before = Get-StackRawUserPath | ConvertTo-Json -Compress
            $script:RawRestores = 0
            $session = New-Fixture ('path-' + $case) -Register
            $regFile = Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack\commands.json'
            $regState = Get-Content -LiteralPath $regFile -Raw | ConvertFrom-Json
            $regState.PathEntryAdded = $true
            $regState | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $regFile -Encoding UTF8
            $bin = Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack\bin'
            $script:FakePath.Value = if ($script:FakePath.Value.Length -eq 0) { $bin } else { $script:FakePath.Value + ';' + $bin }
            $script:FakePath.Existed = $true
            Complete-StackInstallationTracking $session $true
            if ($case -eq 'concurrent-entry') { $script:FakePath.Value += ';C:\UserAdded' }
            Invoke-StackUninstall -Plan (Get-StackUninstallPlan $session.Root) -PersistPath $true -ReceiptDirectory $receipts -Confirm:$false
            if ($case -eq 'concurrent-entry') {
                Assert-True ($script:FakePath.Value -ceq 'C:\First;;%USERPROFILE%\other;C:\UserAdded' -and $script:RawRestores -eq 0) 'Concurrent PATH addition preserved'
            }
            else { Assert-True ((Get-StackRawUserPath | ConvertTo-Json -Compress) -ceq $before -and $script:RawRestores -eq 1) ('Exact PATH restoration: ' + $case) }
        }
    }
    finally {
        Set-Item Function:Get-StackRawUserPath $realReader
        Set-Item Function:Set-StackRawUserPath $realWriter
        Set-Item Function:Set-StackUserCommandPath $realPathEditor
    }
    Write-Host 'PASS: Exact absent/empty/expanded PATH restoration and concurrent additions (isolated adapter)'
    $completeReceipts = @(Get-ChildItem -LiteralPath $receipts -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json } | Where-Object Completed)
    Assert-True ($completeReceipts.Count -ge 8) 'Uninstall receipts recorded outside removed roots'
    Write-Host 'All isolated uninstaller tests passed.'
}
finally {
    $env:USERPROFILE = $originalUserProfile
    $env:Path = $originalPath
    Assert-True ((Get-StackRawUserPath | ConvertTo-Json -Compress) -ceq $pathBefore) 'Real user PATH untouched'
    Assert-True ((Get-ExecutionPolicy -List | ConvertTo-Json -Compress) -ceq $policiesBefore) 'Policies unchanged'
    Write-Host "Retained test fixtures: $testRoot"
}
