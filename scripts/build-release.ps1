#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputPath, [string]$Version = 'development')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if ($PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess) { throw 'Build using 64-bit Windows PowerShell 5.1.' }
if ($Version -cnotmatch '^(development|v?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)$') { throw 'Invalid release version.' }
if (-not $OutputPath) { $OutputPath = Join-Path $repo 'dist/release' }
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) { throw 'Release output already exists. Choose a new output directory.' }
$dirty = & git -c "safe.directory=$repo" -C $repo status --porcelain --untracked-files=normal
if ($LASTEXITCODE -ne 0 -or $dirty) { throw 'Build release assets from a clean, committed checkout.' }
$commit = & git -c "safe.directory=$repo" -C $repo rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[a-f0-9]{40}$') { throw 'Cannot identify source commit.' }
. (Join-Path $repo 'tts/strategy-management.ps1')
$tracked = @(& git -c "safe.directory=$repo" -C $repo ls-files)
if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate tracked release sources.' }
$packages = @(Get-TtsStrategies $repo)
. (Join-Path $repo 'scripts/installation-state.ps1')
. (Join-Path $repo 'scripts/agent-strategies.ps1') -InstallPath $repo
foreach ($strategy in Get-WhasAgentStrategies) {
    foreach ($file in $strategy.Manifest.files) {
        if ($tracked -cnotcontains "agents/strategies/$($strategy.Manifest.id)/$file") { throw 'Release agent strategy assets must be committed, including ignored files.' }
    }
}
foreach ($package in $packages) {
    foreach ($file in $package.Files) {
        if ($tracked -cnotcontains "tts/strategies/$($package.Manifest.id)/$file") { throw 'Release strategy assets must be committed, including ignored files.' }
    }
}
[IO.Directory]::CreateDirectory($OutputPath) | Out-Null
$bundle = Join-Path $OutputPath 'bundle'
[IO.Directory]::CreateDirectory($bundle) | Out-Null
& (Join-Path $PSScriptRoot 'build-setup.ps1') -OutputPath (Join-Path $bundle 'whas-setup.exe')
foreach ($file in @('README.md','LICENSE')) { Copy-Item -LiteralPath (Join-Path $repo $file) -Destination (Join-Path $bundle $file) }
[IO.Directory]::CreateDirectory((Join-Path $bundle 'docs')) | Out-Null
foreach ($file in @($tracked | Where-Object { $_ -like 'docs/*.md' })) {
    $relative = $file.Substring(5)
    $destination = Join-Path (Join-Path $bundle 'docs') $relative
    [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo $file) -Destination $destination
}
$notices = New-Object Text.StringBuilder
$null = $notices.AppendLine('TTS packages and models are installed separately; their licences apply.')
foreach ($package in $packages) {
    $null = $notices.AppendLine("`n$($package.Manifest.name): $($package.Manifest.license)")
    foreach ($model in $package.Manifest.models) { $null = $notices.AppendLine("$($model.source) - $($model.license)") }
    $notice = Join-Path $package.Directory 'NOTICE.md'
    if (Test-Path -LiteralPath $notice) {
        $null = $notices.AppendLine([IO.File]::ReadAllText($notice))
        $noticeRelative = "tts/strategies/$($package.Manifest.id)/NOTICE.md"
        if ($tracked -cnotcontains $noticeRelative) { throw 'Release licence notices must be committed.' }
        $noticeDest = Join-Path $bundle $noticeRelative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $noticeDest)) | Out-Null
        Copy-Item -LiteralPath $notice -Destination $noticeDest
    }
}
[IO.File]::WriteAllText((Join-Path $bundle 'THIRD-PARTY-NOTICES.txt'), $notices.ToString(), (New-Object Text.UTF8Encoding($false)))
$metadata = [pscustomobject]@{version=$Version;commit=$commit;platform='windows-x64';signed=$false}
[IO.File]::WriteAllText((Join-Path $bundle 'build.json'), ($metadata | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
$exe = Join-Path $OutputPath 'whas-setup.exe'
Copy-Item -LiteralPath (Join-Path $bundle 'whas-setup.exe') -Destination $exe
$zip = Join-Path $OutputPath ('whas-windows-x64-' + $Version + '.zip')
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in Get-ChildItem -LiteralPath $bundle -File -Recurse) {
        $entry = $file.FullName.Substring($bundle.Length + 1).Replace('\','/')
        $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $entry)
    }
}
finally { $archive.Dispose() }
$sums = @($exe,$zip) | ForEach-Object { ((Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()) + '  ' + [IO.Path]::GetFileName($_) }
[IO.File]::WriteAllLines((Join-Path $OutputPath 'SHA256SUMS.txt'), $sums, (New-Object Text.UTF8Encoding($false)))
Write-Host "Unsigned release assets built from $commit in $OutputPath"
