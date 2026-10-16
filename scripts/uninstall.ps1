#Requires -Version 5.1
# Uninstall implementation; dot-source alongside installation-state and command-registration.

function Get-StackUninstallPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$InstallPath, [switch]$RemoveManagedModels,
        [switch]$ShowProgress)
    $root = Assert-StackInstallationRoot -Root $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallPath)
    $scanProgress = New-StackOperationProgress 'Scanning installation' -Enabled:$ShowProgress
    $tree = Get-StackInstallationTree -Root $root -Progress $scanProgress
    Write-StackOperationProgress $scanProgress -Completed $tree.Files.Count -Total $tree.Files.Count -Force
    $state = Read-StackInstallationState -Root $root
    $plan = [pscustomobject]@{
        Root = $root; State = $state
        DeleteFiles = New-Object 'System.Collections.Generic.List[object]'
        RestoreFiles = New-Object 'System.Collections.Generic.List[object]'
        KeepFiles = New-Object 'System.Collections.Generic.List[string]'
        RemoveModels = @(); KeepModels = @(); RegistrationBackups = @()
        GeneratedDirectories = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        RestoreUserPathExactly = $false
        RestorePreviousRegistration = $false
        ManifestSHA256 = $null; RegistrationSHA256 = $null
        UnregisterCommands = $false; RemoveManagedModels = [bool]$RemoveManagedModels
        TtsHooks = @()
        AlreadyAbsent = -not (Test-Path -LiteralPath $root)
    }
    if ($null -eq $state) {
        if (-not $plan.AlreadyAbsent) { throw 'No installation ownership record. Existing files were left untouched; older installations require reviewed cleanup.' }
        return $plan
    }
    $plan.ManifestSHA256 = Get-StackFileSHA256 (Join-Path $root '.whas-installation.json')
    $owned = @{}
    foreach ($entry in $state.Files) { $owned[$entry.Path] = $entry }
    $original = @{}
    foreach ($entry in $state.OriginalFiles) {
        $bytes = [Convert]::FromBase64String($entry.Base64)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') } finally { $sha.Dispose() }
        if ($hash -cne $entry.SHA256) { throw "Original-file backup failed verification: $($entry.Path)" }
        $original[$entry.Path] = $entry
    }
    $verifyProgress = New-StackOperationProgress 'Verifying installation ownership' -Enabled:$ShowProgress
    $verifiedCount = 0
    foreach ($relative in $tree.Files) {
        if ($verifyProgress) {
            $verifyProgress.Completed = $verifiedCount
            $verifyProgress.Total = $tree.Files.Count
            if ($verifyProgress.Timer.ElapsedMilliseconds - $verifyProgress.LastUpdate -ge 2000) { Write-StackOperationProgress $verifyProgress }
        }
        $verifiedCount++
        if ($relative -eq '.whas-installation.json') { continue }
        $path = Resolve-StackOwnedPath $root $relative
        $generated = Test-StackGeneratedFile $relative $state
        if ($original.ContainsKey($relative)) {
            $hash = Get-StackFileSHA256 $path -Progress $verifyProgress
            if ($hash -ceq $original[$relative].SHA256) { $plan.KeepFiles.Add($relative) }
            elseif ($owned.ContainsKey($relative) -and $hash -ceq $owned[$relative].SHA256) {
                $plan.RestoreFiles.Add([pscustomobject]@{ Path = $relative; SHA256 = $hash; Original = $original[$relative] })
            }
            else { $plan.KeepFiles.Add($relative) }
        }
        elseif ($generated -or $owned.ContainsKey($relative)) {
            # Generated files are rehashed after verified speech shutdown before deletion.
            $hash = Get-StackFileSHA256 $path -AllowConcurrentWrite:$generated -Progress $verifyProgress
            if ($generated -or $hash -ceq $owned[$relative].SHA256) {
                $plan.DeleteFiles.Add([pscustomobject]@{ Path = $relative; SHA256 = $hash })
                if ($generated) {
                    $parent = (Split-Path -Parent $relative).Replace('\','/')
                    if ($parent -and @($state.PreexistingDirectories) -notcontains $parent) { $null = $plan.GeneratedDirectories.Add($parent) }
                }
            } else { $plan.KeepFiles.Add($relative) }
        }
        else { $plan.KeepFiles.Add($relative) }
    }
    Write-StackOperationProgress $verifyProgress -Completed $tree.Files.Count -Total $tree.Files.Count -Force
    if ($ShowProgress) { Write-Host 'Checking command registration and managed-model ownership...' }
    $registration = [IO.Path]::GetFullPath($state.RegistrationDirectory).TrimEnd('\')
    $expectedRegistration = Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack'
    if ($registration -ine $expectedRegistration) { throw 'Registration ownership points outside this user''s command directory.' }
    $statePath = Join-Path $registration 'commands.json'
    $otherModels = @()
    if (Test-Path -LiteralPath $statePath) {
        $null = Assert-StackInstallationRoot -Root $registration
        $null = Get-StackInstallationTree -Root $registration
        $commands = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($commands.InstallPath -ieq $root) {
            if ($commands.SchemaVersion -ne 1 -or -not (Test-StackCommandNames @($commands.Commands))) { throw 'Invalid command registration; no changes made.' }
            $allowed = @($commands.Commands)
            $bin = Join-Path $registration 'bin'
            if ([IO.File]::ReadAllText((Join-Path $bin 'install-root.txt')) -cne $root) { throw 'Local command root changed; no changes made.' }
            foreach ($name in $allowed) {
                $file = Join-Path $bin ($name + '.exe')
                if ((Test-Path -LiteralPath $file) -and (Get-StackFileSHA256 $file) -cne $commands.ExecutableSHA256) { throw "Changed executable requires review: $file" }
            }
            $plan.UnregisterCommands = $true
            $plan.RegistrationSHA256 = Get-StackFileSHA256 $statePath
            if ($null -ne $state.PreviousRegistration) {
                $previous = $state.PreviousRegistration
                $previousRoot = Assert-StackInstallationRoot -Root $previous.InstallPath
                $exists = (Test-Path -LiteralPath (Join-Path $previousRoot 'scripts\agent-commands.ps1')) -or (Test-Path -LiteralPath (Join-Path $previousRoot 'tts\tts.ps1'))
                if ($previousRoot -ieq $root -and -not $state.RootExisted) { $exists = $false }
                if ($previousRoot -ine $root -and (Test-Path -LiteralPath (Join-Path $previousRoot '.whas-installation.json'))) {
                    if ((Read-StackInstallationState $previousRoot).Status -eq 'Uninstalled') { $exists = $false }
                }
                $previousCommandsFile = @($previous.Files | Where-Object Path -ceq 'commands.json')
                if ($previousCommandsFile.Count -ne 1) { throw 'Missing previous command registration.' }
                $previousCommands = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($previousCommandsFile[0].Base64)).TrimStart([char]0xfeff) | ConvertFrom-Json
                if (-not (Test-StackCommandNames @($previousCommands.Commands))) { throw 'Unknown previous command names.' }
                $expectedFiles = @('commands.json','bin/install-root.txt') + @($previousCommands.Commands | ForEach-Object { 'bin/' + $_ + '.exe' })
                if (@(Compare-Object $expectedFiles @($previous.Files.Path)).Count -gt 0) { throw 'Invalid previous-registration backup paths.' }
                foreach ($entry in $previous.Files) {
                    $null = Resolve-StackOwnedPath $registration $entry.Path
                    $sha = [Security.Cryptography.SHA256]::Create()
                    try { $hash = ([BitConverter]::ToString($sha.ComputeHash([Convert]::FromBase64String($entry.Base64)))).Replace('-','') } finally { $sha.Dispose() }
                    if ($hash -cne $entry.SHA256) { throw 'Previous-registration backup failed verification.' }
                }
                $plan.RestorePreviousRegistration = $exists
                if ($exists -and $previousRoot -ine $root -and (Test-Path -LiteralPath (Join-Path $previousRoot '.whas-installation.json'))) {
                    $previousState = Read-StackInstallationState $previousRoot
                    $otherModels += @($previousState.Models.Name)
                }
            }
            $path = Get-StackRawUserPath
            $expectedPath = if ($state.OriginalUserPath.Value.Length -eq 0) { $bin } else { $state.OriginalUserPath.Value + ';' + $bin }
            $plan.RestoreUserPathExactly = $commands.PathEntryAdded -and $path.Value -ceq $expectedPath
            foreach ($backup in $state.RegistrationBackups) {
                if ($backup.Name -notmatch '^(agent|agentdo|localagent|localagentdo|tts-(start|stop|status|say|voice-(list|add|remove|test)|engine-(list|install|uninstall|default)))\.exe\.bak\.[a-f0-9]{32}$|^install-root\.txt\.bak\.[a-f0-9]{32}$') { throw 'Invalid registration backup name.' }
                $file = Join-Path $bin $backup.Name
                if ((Test-Path -LiteralPath $file) -and (Get-StackFileSHA256 $file) -ceq $backup.SHA256) { $plan.RegistrationBackups += $backup }
            }
        }
        elseif ($commands.InstallPath -and (Test-Path -LiteralPath (Join-Path $commands.InstallPath '.whas-installation.json'))) {
            $otherRoot = Assert-StackInstallationRoot -Root $commands.InstallPath
            $otherState = Read-StackInstallationState -Root $otherRoot
            $otherModels = @($otherState.Models.Name)
        }
    }
    foreach ($model in $state.Models) {
        if ($model.Name -notmatch '^whas-[a-z0-9-]+:latest$' -or $model.Digest -notmatch '^(sha256:)?[a-f0-9]{64}$') { throw 'Invalid managed-model ownership record.' }
        if ($RemoveManagedModels -and $model.Created -and $otherModels -notcontains $model.Name) {
            # One read-only inventory for all eligible managed-model checks.
            if ($null -eq (Get-Variable inventory -Scope Local -ErrorAction Ignore)) { $inventory = @(Get-StackOllamaModels) }
            $current = @($inventory | Where-Object name -eq $model.Name)
            if ($current.Count -eq 1 -and $current[0].digest -ceq $model.Digest) { $plan.RemoveModels += $model }
            elseif ($current.Count -gt 0) { $plan.KeepModels += $model.Name }
        }
        else { $plan.KeepModels += $model.Name }
    }
    if ($state.SchemaVersion -eq 2 -and $state.Status -ne 'Uninstalled') {
        if (-not (Get-Command Get-TtsInstalledHooks -ErrorAction Ignore)) { throw 'TTS strategy cleanup helper is unavailable.' }
        $plan.TtsHooks = @(Get-TtsInstalledHooks $root $state)
    }
    return $plan
}

function Stop-StackOwnedSpeech {
    param([string]$Root)
    $pidFile = Join-Path $Root 'tts\service.pid'
    $hasPid = Test-Path -LiteralPath $pidFile
    if (-not $hasPid -and -not (Test-Path -LiteralPath (Join-Path $Root 'tts\tts_service.py'))) { return }
    $saved = if ($hasPid) { [IO.File]::ReadAllText($pidFile).Trim() } else { '0' }
    if ($saved -notmatch '^\d+$') { throw 'Invalid speech PID file; no processes stopped.' }
    $pythonPath = Join-Path $Root '.venv\Scripts\python.exe'
    $state = Read-StackInstallationState $Root
    if ($state.SchemaVersion -eq 2 -and @($state.TtsStrategies).Count -eq 1) {
        $environment = Resolve-StackOwnedPath $Root $state.TtsStrategies[0].Context.EnvironmentPath
        $pythonPath = Join-Path $environment 'Scripts/python.exe'
    }
    $marker = '"' + (Join-Path $Root 'tts\tts_service.py') + '"'
    $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    $launcher = @($processes | Where-Object { $hasPid -and $_.ProcessId -eq ([int]$saved) })
    if ($launcher.Count -eq 0) {
        if (@($processes | Where-Object { $_.Name -match '^python(w)?\.exe$' -and $_.CommandLine -and $_.CommandLine.Contains($marker) }).Count -gt 0) {
            throw 'Speech worker has no verified launcher PID; stop it before uninstalling.'
        }
        return
    }
    if ($state.SchemaVersion -eq 2) {
        $allowedPythons = @($state.TtsStrategies | ForEach-Object {
            Join-Path (Resolve-StackOwnedPath $Root $_.Context.EnvironmentPath) 'Scripts/python.exe'
        })
        if ($allowedPythons -icontains $launcher[0].ExecutablePath) { $pythonPath = $launcher[0].ExecutablePath }
    }
    if ($launcher[0].Name -notmatch '^python(w)?\.exe$' -or -not $launcher[0].CommandLine.Contains($marker) -or
        $launcher[0].ExecutablePath -ine $pythonPath) { throw 'Saved PID belongs to another process; it was not stopped.' }
    $matching = @($processes | Where-Object {
        $_.Name -match '^python(w)?\.exe$' -and $_.CommandLine -and $_.CommandLine.Contains($marker) -and
        ($_.ProcessId -eq [int]$saved -or $_.ParentProcessId -eq [int]$saved)
    } | Sort-Object ProcessId -Descending)
    foreach ($process in $matching) {
        $current = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $process.ProcessId) -ErrorAction Stop
        if ($null -ne $current) {
            if ($current.CreationDate -ne $process.CreationDate) { throw 'Speech process identity changed; cleanup stopped.' }
            # Terminating a venv launcher can also terminate its worker. CIM may
            # briefly return that exiting process with no command line. Do not
            # kill an unverifiable process; require its exit in the wait below.
            if ([string]::IsNullOrEmpty($current.CommandLine)) { continue }
            if ($current.CommandLine -cne $process.CommandLine) { throw 'Speech process identity changed; cleanup stopped.' }
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($process in $matching) {
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            $remaining = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $process.ProcessId) -ErrorAction Stop
            if ($null -eq $remaining -or $remaining.CreationDate -ne $process.CreationDate) { break }
            Start-Sleep -Milliseconds 100
        }
        if ($attempt -eq 20) { throw 'Speech process did not exit; files retained.' }
    }
}

function Invoke-StackUninstall {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param([Parameter(Mandatory=$true)]$Plan, [bool]$PersistPath = $true,
        [string]$ReceiptDirectory = (Join-Path $env:USERPROFILE 'WHAS-UninstallReceipts'))
    if ($Plan.AlreadyAbsent) { Write-Host 'Installation is already absent; no changes made.'; return }
    $receiptRoot = [IO.Path]::GetFullPath($ReceiptDirectory).TrimEnd('\')
    if ($receiptRoot -ieq $Plan.Root -or $receiptRoot.StartsWith($Plan.Root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Keep uninstall receipts outside the installation.' }
    if (-not $PSCmdlet.ShouldProcess($Plan.Root, ('Uninstall tracked stack files; remove managed models: ' + $Plan.RemoveManagedModels))) { return }
    Write-Host 'Revalidating the cleanup plan after confirmation...'
    $current = Get-StackUninstallPlan -InstallPath $Plan.Root -RemoveManagedModels:$Plan.RemoveManagedModels -ShowProgress
    $receipt = [ordered]@{ StartedAtUtc = [DateTime]::UtcNow.ToString('o'); InstallationId = $current.State.InstallationId;
        InstallPath = $current.Root; DeletedFiles = [Collections.Generic.List[string]]::new(); RestoredFiles = @(); RemovedModels = @(); KeptFiles = $current.KeepFiles;
        TtsStrategies = @(); KeptModels = $current.KeepModels; PreviousRegistrationRestored = $false; Completed = $false }
    New-Item -ItemType Directory -Path $receiptRoot -Force -ErrorAction Stop | Out-Null
    $receiptPath = Join-Path $receiptRoot ('uninstall-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        Write-Host 'Stopping the installation speech service, if running...'
        Stop-StackOwnedSpeech -Root $current.Root
        # Logs may change while the service shuts down. Rebuild the plan after stopping it.
        Write-Host 'Rechecking files after speech shutdown...'
        $current = Get-StackUninstallPlan -InstallPath $Plan.Root -RemoveManagedModels:$Plan.RemoveManagedModels -ShowProgress
        $receipt.KeptFiles = $current.KeepFiles
        $receipt.KeptModels = $current.KeepModels
        foreach ($hook in $current.TtsHooks) {
            Write-Host "Running TTS cleanup: $($hook.Id)..."
            Invoke-TtsVerifiedHook -Path $hook.Path -SHA256 $hook.SHA256 -Arguments @{Context=$hook.Context}
            $receipt.TtsStrategies += [pscustomobject]@{Id=$hook.Id; HookCompleted=$true}
        }
        # Hooks are trusted code. Revalidate file ownership after they return.
        Write-Host 'Rechecking ownership after strategy cleanup...'
        $current = Get-StackUninstallPlan -InstallPath $Plan.Root -RemoveManagedModels:$Plan.RemoveManagedModels -ShowProgress
        foreach ($model in $current.RemoveModels) {
            Write-Host "Removing verified managed model: $($model.Name)..."
            $verified = @(Get-StackOllamaModels | Where-Object { $_.name -ceq $model.Name -and $_.digest -ceq $model.Digest })
            if ($verified.Count -ne 1) { throw 'Managed model changed since preview; files retained.' }
            $body = @{ model = $model.Name }
            $null = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/generate' -Method Post -ContentType 'application/json' -Body (@{ model=$model.Name; keep_alive=0 } | ConvertTo-Json) -TimeoutSec 30
            $null = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/delete' -Method Delete -ContentType 'application/json' -Body ($body | ConvertTo-Json) -TimeoutSec 30
            $receipt.RemovedModels += $model.Name
        }
        if ($current.UnregisterCommands) {
            Write-Host 'Removing command registration...'
            if ((Get-StackFileSHA256 (Join-Path $current.State.RegistrationDirectory 'commands.json')) -cne $current.RegistrationSHA256) { throw 'Command registration changed during uninstall; retained for review.' }
            $preservePreviousPath = $current.RestorePreviousRegistration -and $current.State.PreviousRegistration.HadPathEntry
            Unregister-StackCommands -RegistrationDirectory $current.State.RegistrationDirectory -PersistPath ($PersistPath -and -not $preservePreviousPath)
            $pathAfterRemoval = Get-StackRawUserPath
            if ($PersistPath -and -not $preservePreviousPath -and $current.RestoreUserPathExactly -and $pathAfterRemoval.Value -ceq $current.State.OriginalUserPath.Value) {
                Set-StackRawUserPath -PathState $current.State.OriginalUserPath -ExpectedValue $current.State.OriginalUserPath.Value
            }
            $regBin = Join-Path $current.State.RegistrationDirectory 'bin'
            foreach ($backup in $current.RegistrationBackups) {
                $path = Join-Path $regBin $backup.Name
                if ((Test-Path -LiteralPath $path) -and (Get-StackFileSHA256 $path) -ceq $backup.SHA256) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
            }
            if ($current.RestorePreviousRegistration) {
                foreach ($entry in $current.State.PreviousRegistration.Files) {
                    $path = Resolve-StackOwnedPath $current.State.RegistrationDirectory $entry.Path
                    if (Test-Path -LiteralPath $path) { throw 'Command files were recreated during uninstall; previous registration was not written over them.' }
                    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
                    [IO.File]::WriteAllBytes($path, [Convert]::FromBase64String($entry.Base64))
                }
                $env:Path = $regBin + ';' + $env:Path
                $receipt.PreviousRegistrationRestored = $true
            }
            if ((Test-Path -LiteralPath $regBin) -and @(Get-ChildItem -LiteralPath $regBin -Force).Count -eq 0 -and -not $current.State.RegistrationBinExisted) { Remove-Item -LiteralPath $regBin }
            if ($current.State.RegistrationBinExisted -and -not (Test-Path -LiteralPath $regBin)) { New-Item -ItemType Directory -Path $regBin -Force | Out-Null }
            if ((Test-Path -LiteralPath $current.State.RegistrationDirectory) -and @(Get-ChildItem -LiteralPath $current.State.RegistrationDirectory -Force).Count -eq 0 -and -not $current.State.RegistrationRootExisted) { Remove-Item -LiteralPath $current.State.RegistrationDirectory }
        }
        $fileProgress = New-StackOperationProgress 'Restoring original files' -Enabled
        foreach ($entry in $current.RestoreFiles) {
            $path = Resolve-StackOwnedPath $current.Root $entry.Path
            if ((Get-StackFileSHA256 $path -Progress $fileProgress) -cne $entry.SHA256) { throw "File changed during uninstall: $path" }
            [IO.File]::WriteAllBytes($path, [Convert]::FromBase64String($entry.Original.Base64))
            $receipt.RestoredFiles += $entry.Path
            if ($fileProgress.Timer.ElapsedMilliseconds - $fileProgress.LastUpdate -ge 2000) {
                Write-StackOperationProgress $fileProgress -Completed $receipt.RestoredFiles.Count -Total $current.RestoreFiles.Count
            }
        }
        Write-StackOperationProgress $fileProgress -Completed $receipt.RestoredFiles.Count -Total $current.RestoreFiles.Count -Force
        $fileProgress = New-StackOperationProgress 'Removing tracked files' -Enabled
        foreach ($entry in $current.DeleteFiles) {
            $fileProgress.Completed = $receipt.DeletedFiles.Count
            $fileProgress.Total = $current.DeleteFiles.Count
            if ($fileProgress.Timer.ElapsedMilliseconds - $fileProgress.LastUpdate -ge 2000) { Write-StackOperationProgress $fileProgress }
            $path = Resolve-StackOwnedPath $current.Root $entry.Path
            if ((Get-StackFileSHA256 $path -Progress $fileProgress) -cne $entry.SHA256) { throw "File changed during uninstall: $path" }
            Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            $receipt.DeletedFiles.Add($entry.Path)
        }
        Write-StackOperationProgress $fileProgress -Completed $receipt.DeletedFiles.Count -Total $current.DeleteFiles.Count -Force
        Write-Host "Preserving $($current.KeepFiles.Count) files. Removing empty directories..."
        $directories = @(@($current.State.Directories) + @($current.GeneratedDirectories) | Sort-Object -Unique | Sort-Object Length -Descending)
        $directoryProgress = New-StackOperationProgress 'Checking empty directories' -Enabled -Unit 'directories'
        $directoryCount = 0
        foreach ($relative in $directories) {
            $directory = Resolve-StackOwnedPath $current.Root $relative
            if ((Test-Path -LiteralPath $directory -PathType Container) -and @(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) { Remove-Item -LiteralPath $directory -ErrorAction Stop }
            $directoryCount++
            if ($directoryProgress.Timer.ElapsedMilliseconds - $directoryProgress.LastUpdate -ge 2000) {
                Write-StackOperationProgress $directoryProgress -Completed $directoryCount -Total $directories.Count
            }
        }
        Write-StackOperationProgress $directoryProgress -Completed $directoryCount -Total $directories.Count -Force
        $left = Get-StackInstallationTree -Root $current.Root -Progress (New-StackOperationProgress 'Checking remaining files' -Enabled)
        if ((Get-StackFileSHA256 (Join-Path $current.Root '.whas-installation.json')) -cne $current.ManifestSHA256) { throw 'Ownership record changed during uninstall; preserved for review.' }
        if (@($left.Files | Where-Object { $_ -ne '.whas-installation.json' }).Count -eq 0 -and $left.Directories.Count -eq 0 -and -not $current.State.RootExisted) {
            Remove-Item -LiteralPath (Join-Path $current.Root '.whas-installation.json') -Force -ErrorAction Stop
            Remove-Item -LiteralPath $current.Root -ErrorAction Stop
        }
        else { $current.State.Status = 'Uninstalled'; Write-StackInstallationState -Root $current.Root -State $current.State }
        $receipt.Completed = $true
    }
    catch { $receipt.Error = $_.Exception.Message; throw }
    finally {
        $receipt.FinishedAtUtc = [DateTime]::UtcNow.ToString('o')
        [IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($true)))
        Write-Host "Uninstall receipt: $receiptPath"
    }
    Write-Host 'Uninstall completed. Preserved files and models are listed in the receipt.'
    Write-Host 'Refresh PATH in your original terminal, or close and reopen the terminal application.'
}
