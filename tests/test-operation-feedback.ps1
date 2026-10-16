#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts/installation-state.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('whas-feedback-' + [guid]::NewGuid().ToString('N'))
$root = Join-Path $fixture 'installation'
try {
    Add-Type -Path (Join-Path $repo 'scripts/command-host.cs') -ReferencedAssemblies ([Management.Automation.PSObject].Assembly.Location)
    $session = Start-StackInstallationTracking $root
    [IO.File]::WriteAllBytes((Join-Path $root 'large.bin'), (New-Object byte[] (20MB)))
    $output = @(Complete-StackInstallationTracking $session $true 6>&1) -join "`n"
    foreach ($phase in @('Finalising installation','Scanning installed files','Recording installed file hashes','Saving installation ownership')) {
        if ($output -notmatch [regex]::Escape($phase)) { throw "Missing phase: $phase" }
    }
    $state = Read-StackInstallationState $root
    if ($state.Files[0].SHA256 -cne (Get-FileHash -LiteralPath (Join-Path $root 'large.bin')).Hash) { throw 'Progress changed hashing' }
    $entries = @(for ($i=0; $i -lt 10000; $i++) { [pscustomobject]@{Path="packages/$i.py";SHA256=('0'*64)} })
    $state.Files = $entries
    Write-StackInstallationState $root $state
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $first = Read-StackInstallationState $root -ReadOnly
    $cold = $watch.Elapsed.TotalMilliseconds
    $watch.Restart(); $second = Read-StackInstallationState $root -ReadOnly
    $warm = $watch.Elapsed.TotalMilliseconds
    if (-not [object]::ReferenceEquals($first,$second)) { throw 'Validated read-only snapshot was not reused' }
    $mutable = Read-StackInstallationState $root
    if ([object]::ReferenceEquals($mutable,$second)) { throw 'Mutable state shared the reader snapshot' }
    $state.Status='Interrupted'; Write-StackInstallationState $root $state
    if ((Read-StackInstallationState $root -ReadOnly).Status -ne 'Interrupted') { throw 'Read-only snapshot was stale after a write' }
    Write-Host ('PASS: 10,000-entry validated state: cold {0:N0}ms, cached {1:N0}ms' -f $cold,$warm)
    foreach($bad in @('../escape','C:\escape','safe/../../escape','safe:stream')) {
        $rejected=$false
        try { [WindowsHybridAgenticStack.CommandHost]::ValidateOwnershipPaths($root,[Management.Automation.PSObject[]]@([pscustomobject]@{Path=$bad})) } catch { $rejected=$true }
        if(-not $rejected) { throw "Native validator accepted $bad" }
    }
    if(-not [WindowsHybridAgenticStack.CommandHost]::IsOwnedAsset($state,'packages/1.py',('0'*64)) -or
        [WindowsHybridAgenticStack.CommandHost]::IsOwnedAsset($state,'packages/1.py',('1'*64))) { throw 'Native ownership lookup changed hash enforcement' }
    $events = Join-Path $fixture 'events.txt'
    $previous = $env:WHAS_PROGRESS_EVENTS
    $saved = [Console]::Error
    $writer = New-Object IO.StringWriter
    try {
        [Console]::SetError($writer); $env:WHAS_PROGRESS_EVENTS='1'
        $activity = [WindowsHybridAgenticStack.OperationActivity]::Begin('Waiting for model response')
        Start-Sleep -Milliseconds 2200
        $activity.Dispose()
        $lines = @($writer.ToString() -split '\r?\n' | Where-Object { $_ })
        if ($lines.Count -lt 3) { throw 'Missing start, heartbeat or completion activity' }
        $parsed = @($lines | ForEach-Object { $_.Substring('WHAS_EVENT '.Length) | ConvertFrom-Json })
        if (-not $parsed[-1].complete -or $parsed[0].complete) { throw 'Invalid activity completion' }
        $before = $writer.ToString(); Start-Sleep -Milliseconds 2200
        if ($writer.ToString() -cne $before) { throw 'Activity continued after completion' }
    } finally { [Console]::SetError($saved); $env:WHAS_PROGRESS_EVENTS=$previous; $writer.Dispose() }
    Write-Host 'PASS: Finalisation progress, hash parity, snapshot isolation and activity lifecycle'
} finally {
    $absolute = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $absolute.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $absolute) -notmatch '^whas-feedback-[a-f0-9]{32}$') { throw 'Unexpected fixture cleanup target' }
    if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
