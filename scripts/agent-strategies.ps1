#Requires -Version 5.1
param([Alias('InstallPath')][string]$StrategyRoot)
$script:AgentStrategyRoot = $StrategyRoot

function Get-WhasAgentStrategies {
    $directory = Join-Path $script:AgentStrategyRoot 'agents/strategies'
    if (-not (Test-Path -LiteralPath $directory)) { return }
    foreach ($folder in Get-ChildItem -LiteralPath $directory -Directory) {
        if ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Agent strategy directories must not use reparse points.' }
        $path = Join-Path $folder.FullName 'manifest.json'
        $manifest = [IO.File]::ReadAllText($path) | ConvertFrom-Json
        if ($manifest.schemaVersion -ne 1 -or $manifest.id -cne $folder.Name -or $manifest.id -cnotmatch '^[a-z][a-z0-9-]{0,47}$' -or $manifest.executable -cnotmatch '^[a-z][a-z0-9-]{0,47}$') { throw 'Invalid agent strategy manifest.' }
        foreach ($capability in @('ask','perform','chat','local','sessionResume','managedInstall')) {
            if ($manifest.capabilities.$capability -isnot [bool]) { throw 'Invalid agent capability declaration.' }
        }
        $hooks=@('adapter')
        if($manifest.capabilities.managedInstall) { $hooks+=@('install','uninstall') }
        foreach($hook in $hooks) {
            if($manifest.entrypoints.$hook -isnot [string] -or $manifest.files -cnotcontains $manifest.entrypoints.$hook -or $manifest.entrypoints.$hook -notlike '*.ps1') { throw 'Agent strategy requires declared lifecycle entrypoints.' }
        }
        foreach ($file in $manifest.files) {
            $full = Resolve-StackOwnedPath $folder.FullName $file
            if (-not (Test-Path -LiteralPath $full -PathType Leaf) -or ((Get-Item -LiteralPath $full -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Missing or invalid agent strategy asset.' }
        }
        [pscustomobject]@{Manifest=$manifest;Directory=$folder.FullName}
    }
}
function Get-WhasAgentStrategy {
    param([string]$Id)
    $matches = @(Get-WhasAgentStrategies | Where-Object { $_.Manifest.id -ceq $Id })
    if ($matches.Count -ne 1) { throw "Unknown agent runtime: $Id" }
    return $matches[0]
}
function Resolve-WhasDataPath {
    param([string]$Relative)
    $path=Resolve-StackOwnedPath $script:AgentStrategyRoot $Relative
    $ancestor=$path
    while($ancestor -and $ancestor -ine $script:AgentStrategyRoot) {
        if((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Agent data must not use reparse points.' }
        $ancestor=Split-Path -Parent $ancestor
    }
    return $path
}
function Get-WhasSessionPath {
    param([string]$Runtime,[string]$Session)
    if($Runtime -cnotmatch '^[a-z][a-z0-9-]{0,47}$' -or $Session -cnotmatch '^[A-Za-z0-9_-]{1,160}$') { throw 'Invalid session identity.' }
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $key=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Runtime+':'+$Session)))).Replace('-','') } finally { $sha.Dispose() }
    return Resolve-WhasDataPath ('agents/data/whas/sessions/'+$key+'.json')
}
function Assert-WhasSession {
    param([string]$Runtime,[string]$Location,[string]$Session)
    $path=Get-WhasSessionPath $Runtime $Session
    if(-not (Test-Path -LiteralPath $path)) { throw 'This session is not registered with WHAS. Use the native runtime to inspect external sessions.' }
    $record=[IO.File]::ReadAllText($path)|ConvertFrom-Json
    $workspace=[IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.CurrentFileSystemLocation.Path).TrimEnd('\')
    if($record.schemaVersion -ne 1 -or $record.runtime -cne $Runtime -or $record.sessionId -cne $Session -or $record.location -cne $Location -or $record.workspace -ine $workspace -or $record.ownerSid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) { throw 'Session runtime, location, workspace or owner does not match. Start a new conversation.' }
}
function Save-WhasSession {
    param([string]$Runtime,[string]$Location,[string]$Session)
    $path=Get-WhasSessionPath $Runtime $Session
    $lock=Enter-StackOperationLock $script:AgentStrategyRoot
    try {
        if(Test-Path -LiteralPath $path) { Assert-WhasSession $Runtime $Location $Session; return }
        [IO.Directory]::CreateDirectory((Split-Path -Parent $path))|Out-Null
        $record=[ordered]@{schemaVersion=1;runtime=$Runtime;location=$Location;sessionId=$Session;workspace=[IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.CurrentFileSystemLocation.Path).TrimEnd('\');ownerSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;createdUtc=[DateTime]::UtcNow.ToString('o')}
        $temporary=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
        try { [IO.File]::WriteAllText($temporary,($record|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false))); [IO.File]::Move($temporary,$path) }
        finally { if(Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
    } finally { $lock.ReleaseMutex();$lock.Dispose() }
}
function Invoke-WhasSessionManagement {
    param([string[]]$Arguments)
    if($Arguments.Count -eq 1 -and $Arguments[0] -eq 'list') {
        $directory=Resolve-WhasDataPath 'agents/data/whas/sessions'
        $records=@(if(Test-Path -LiteralPath $directory) { foreach($file in Get-ChildItem -LiteralPath $directory -Filter '*.json' -File) { if($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Session records must not use reparse points.' }; [IO.File]::ReadAllText($file.FullName)|ConvertFrom-Json } })
        ConvertTo-Json -InputObject $records -Depth 5 -Compress
        return
    }
    if($Arguments.Count -eq 4 -and $Arguments[0] -eq 'forget' -and $Arguments[3] -eq '--yes') {
        $path=Get-WhasSessionPath $Arguments[1] $Arguments[2]
        $lock=Enter-StackOperationLock $script:AgentStrategyRoot
        try { if(Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } } finally { $lock.ReleaseMutex();$lock.Dispose() }
        Write-Output 'Forgot the WHAS session association. Native conversation history and memory remain in the runtime storage.'
        return
    }
    throw 'Usage: whas session list | forget RUNTIME SESSION --yes (native history is retained)'
}
function Invoke-WhasAgent {
    param([string]$Runtime,[string]$Action,[string]$Location,[string[]]$Arguments,[string]$Session,[switch]$Voice)
    $strategy = Get-WhasAgentStrategy $Runtime
    if (-not $strategy.Manifest.capabilities.$Action) { throw "$Runtime does not support $Action with WHAS permissions." }
    if ($Location -eq 'local' -and -not $strategy.Manifest.capabilities.local) { throw "$Runtime does not support local models." }
    if ($Session -and -not $strategy.Manifest.capabilities.sessionResume) { throw "$Runtime does not support session continuation." }
    if($Session) { Assert-WhasSession $Runtime $Location $Session }
    $null = Get-WhasAgentExecutable $strategy
    $adapter = Join-Path $strategy.Directory $strategy.Manifest.entrypoints.adapter
    if($Action -eq 'chat' -and $Arguments -contains '--message') {
        $response=(& (Get-StackSetupScript $adapter) -Action $Action -Location $Location -Arguments $Arguments -Session $Session -Voice ([bool]$Voice) -Root $script:AgentStrategyRoot)|Out-String
        $result=$response|ConvertFrom-Json -ErrorAction Stop
        if($Session -and $result.sessionId -cne $Session) { throw 'Runtime returned a different session ID; continuation was not registered.' }
        Save-WhasSession $Runtime $Location $result.sessionId
        Write-Output $response.Trim()
    } else {
        & (Get-StackSetupScript $adapter) -Action $Action -Location $Location -Arguments $Arguments -Session $Session -Voice ([bool]$Voice) -Root $script:AgentStrategyRoot
    }
}
function Get-WhasAgentExecutable {
    param($Strategy)
    $managed = Resolve-WhasDataPath "agents/runtime/$($Strategy.Manifest.id)/home/bin/$($Strategy.Manifest.executable).exe"
    if (Test-Path -LiteralPath $managed -PathType Leaf) {
        $state = Read-StackInstallationState $script:AgentStrategyRoot -ReadOnly
        $relative = "agents/runtime/$($Strategy.Manifest.id)/home/bin/$($Strategy.Manifest.executable).exe"
        $record = @($state.Files | Where-Object { $_.Path -ceq $relative })
        if ($record.Count -ne 1 -or (Get-StackFileSHA256 $managed) -cne $record[0].SHA256) { throw 'Managed agent launcher is unowned or changed.' }
        return $managed
    }
    $external = Get-Command $Strategy.Manifest.executable -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    if ($external) { return $external.Source }
    throw "$($Strategy.Manifest.id) is unavailable. Run whas agent install $($Strategy.Manifest.id) or see $($Strategy.Manifest.documentation)"
}
function Invoke-WhasAgentManagement {
    param([string[]]$Arguments)
    if (-not $Arguments.Count) { throw 'Usage: whas agent list | check ID | native ID [arguments]' }
    if ($Arguments.Count -eq 1 -and $Arguments[0] -eq 'list') {
        foreach ($strategy in Get-WhasAgentStrategies) {
            $available = $false
            try { $null = Get-WhasAgentExecutable $strategy; $available = $true } catch { }
            [pscustomobject]@{Id=$strategy.Manifest.id;Available=$available;Capabilities=$strategy.Manifest.capabilities} | ConvertTo-Json -Compress
        }
        return
    }
    if ($Arguments.Count -lt 2) { throw 'Specify a runtime ID.' }
    $strategy = Get-WhasAgentStrategy $Arguments[1]
    if ($Arguments[0] -eq 'install') {
        if (-not $strategy.Manifest.capabilities.managedInstall) { throw "Install this external prerequisite yourself using $($strategy.Manifest.documentation)" }
        if ($Arguments.Count -gt 3 -or ($Arguments.Count -eq 3 -and $Arguments[2] -ne '--yes')) { throw 'Usage: whas agent install ID [--yes]' }
        if ($Arguments -notcontains '--yes' -and (Read-Host "Install $($strategy.Manifest.name) and its private dependencies? Type YES") -cne 'YES') { Write-Host 'Cancelled.'; return }
        $lock=Enter-StackOperationLock $script:AgentStrategyRoot
        $activity=$null
        try {
            if($null -ne ('WindowsHybridAgenticStack.OperationActivity' -as [type])) { $activity=[WindowsHybridAgenticStack.OperationActivity]::Begin('Installing agent runtime and private dependencies') }
            . (Get-StackSetupScript (Join-Path $script:AgentStrategyRoot 'scripts/command-registration.ps1'))
            & (Get-StackSetupScript (Join-Path $strategy.Directory $strategy.Manifest.entrypoints.install)) -Root $script:AgentStrategyRoot
            if(-not (Get-StackConfiguration $script:AgentStrategyRoot).interaction.runtime) { Set-WhasSetting runtime $strategy.Manifest.id }
        } finally { if($activity) { $activity.Dispose() }; $lock.ReleaseMutex(); $lock.Dispose() }
        return
    }
    if ($Arguments[0] -eq 'uninstall') {
        $root=$script:AgentStrategyRoot
        $prefix="agents/runtime/$($strategy.Manifest.id)/"
        $lock=Enter-StackOperationLock $root
        try {
            $state=Read-StackInstallationState $root
            $candidates=@($state.Files | Where-Object { $_.Path.StartsWith($prefix,[StringComparison]::Ordinal) })
            Write-Host "Preview: inspect $($candidates.Count) tracked runtime files. Personal agent data is retained."
            if ($Arguments -notcontains '--apply') { return }
            $clearDefault=(Get-StackConfiguration $root).interaction.runtime -ceq $strategy.Manifest.id
            if($clearDefault) {
                $others=@(foreach($candidate in Get-WhasAgentStrategies) { if($candidate.Manifest.id -ceq $strategy.Manifest.id) { continue }; try { $null=Get-WhasAgentExecutable $candidate; $candidate.Manifest.id } catch { } })
                if($others.Count) { throw 'Choose another default runtime with whas configure before removing this one.' }
            }
            if ($Arguments -notcontains '--yes' -and (Read-Host 'Remove unchanged owned runtime files? Type YES') -cne 'YES') { Write-Host 'Cancelled.'; return }
            foreach($hook in @(Get-StackAgentHooks $root $state | Where-Object { $_.Id -ceq $strategy.Manifest.id })) {
                Invoke-StackVerifiedHook -Path $hook.Path -SHA256 $hook.SHA256 -Arguments @{Context=$hook.Context}
            }
            $deleted=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            $progress=New-StackOperationProgress 'Removing verified agent runtime files' -Enabled
            $inspected=0
            foreach ($entry in $candidates) {
                Write-StackOperationProgress $progress -Completed (++$inspected) -Total $candidates.Count
                $path=Resolve-StackOwnedPath $root $entry.Path
                $parent=$path
                while ($parent -and $parent -ine $root) {
                    if (([IO.File]::Exists($parent) -or [IO.Directory]::Exists($parent)) -and ([IO.File]::GetAttributes($parent) -band [IO.FileAttributes]::ReparsePoint)) { throw 'Agent cleanup requires review of reparse points.' }
                    $parent=[IO.Path]::GetDirectoryName($parent)
                }
                if ([IO.File]::Exists($path) -and (Get-StackFileSHA256 $path -Progress $progress) -ceq $entry.SHA256) {
                    $attributes=[IO.File]::GetAttributes($path)
                    if($attributes -band [IO.FileAttributes]::ReadOnly) { [IO.File]::SetAttributes($path,($attributes -band (-bnot [IO.FileAttributes]::ReadOnly))) }
                    [IO.File]::Delete($path); $null=$deleted.Add($entry.Path)
                }
            }
            Write-StackOperationProgress $progress -Completed $inspected -Total $candidates.Count -Force
            $state.Files=@($state.Files | Where-Object { -not $deleted.Contains($_.Path) })
            Write-StackInstallationState $root $state
            $runtime=Join-Path $root $prefix
            if (Test-Path -LiteralPath $runtime) {
                $null=Get-StackInstallationTree $runtime
                foreach ($directory in @(Get-ChildItem -LiteralPath $runtime -Directory -Force -Recurse | Sort-Object { $_.FullName.Length } -Descending)+@((Get-Item -LiteralPath $runtime))) {
                    if (-not @(Get-ChildItem -LiteralPath $directory.FullName -Force).Count) { Remove-Item -LiteralPath $directory.FullName -Force }
                }
            }
            Write-Host "Removed $($deleted.Count) verified runtime files. Modified files and personal data were preserved."
            if($clearDefault) { Set-WhasSetting runtime none }
        } finally { $lock.ReleaseMutex(); $lock.Dispose() }
        return
    }
    if ($Arguments[0] -eq 'check') {
        & (Get-WhasAgentExecutable $strategy) --version
        if ($LASTEXITCODE) { throw 'Agent version check failed.' }
        return
    }
    if ($Arguments[0] -eq 'native') {
        $native=@($Arguments | Select-Object -Skip 2)
        & (Get-WhasAgentExecutable $strategy) @native
        if ($LASTEXITCODE) { throw 'Native agent command failed.' }
        return
    }
    throw 'Unknown agent management operation.'
}
