#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('whas-release-tests-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $fixture 'source'
function Write-Fixture {
    param([string]$Relative,[string]$Text)
    $path=Join-Path $source $Relative
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    [IO.File]::WriteAllText($path,$Text,(New-Object Text.UTF8Encoding($false)))
}
function Invoke-FixtureGit {
    param([string[]]$GitArguments)
    & git -c "safe.directory=$source" -c core.autocrlf=false -c user.name=Fixture -c user.email=fixture@example.invalid -C $source @GitArguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Fixture Git operation failed' }
}
try {
    [IO.Directory]::CreateDirectory((Join-Path $source 'scripts')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $source 'tts')) | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'scripts/build-release.ps1') -Destination (Join-Path $source 'scripts/build-release.ps1')
    Copy-Item -LiteralPath (Join-Path $repo 'scripts/agent-strategies.ps1') -Destination (Join-Path $source 'scripts/agent-strategies.ps1')
    Copy-Item -LiteralPath (Join-Path $repo 'scripts/installation-state.ps1') -Destination (Join-Path $source 'scripts/installation-state.ps1')
    Copy-Item -LiteralPath (Join-Path $repo 'tts/strategy-management.ps1') -Destination (Join-Path $source 'tts/strategy-management.ps1')
    Write-Fixture 'scripts/build-setup.ps1' 'param($OutputPath); [IO.File]::WriteAllText($OutputPath, "fixture executable")'
    Write-Fixture 'README.md' '# Fixture'
    Write-Fixture 'LICENSE' 'Fixture licence'
    Write-Fixture 'docs/installation.md' '# Public installation guide'
    Write-Fixture 'docs/private.md' 'DO_NOT_SHIP'
    Write-Fixture '.gitignore' 'docs/private.md'
    $manifest=Get-Content -LiteralPath (Join-Path $repo 'tts/strategies/chatterbox-turbo/manifest.json') -Raw | ConvertFrom-Json
    $manifest.id='fixture'; $manifest.name='Fixture'; $manifest.models=@()
    $manifest.files=@('install.ps1','uninstall.ps1','backend.py')
    foreach ($name in $manifest.files) { Write-Fixture "tts/strategies/fixture/$name" '# fixture code' }
    Write-Fixture 'tts/strategies/fixture/manifest.json' ($manifest | ConvertTo-Json -Depth 12)
    Invoke-FixtureGit @('init','--quiet')
    Invoke-FixtureGit @('add','.')
    Invoke-FixtureGit @('commit','--quiet','-m','test(fixture): create release source')
    $builder=Join-Path $source 'scripts/build-release.ps1'
    $output=Join-Path $fixture 'release'
    & $builder -OutputPath $output -Version v1.2.3
    $zip=Join-Path $output 'whas-windows-x64-v1.2.3.zip'
    $archive=[IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $entries=@($archive.Entries.FullName)
        if (@($entries | Where-Object { $_.Contains('\') }).Count) { throw 'ZIP entries must use portable forward slashes' }
        if ($entries -contains 'docs/private.md' -or $entries -notcontains 'docs/installation.md' -or $entries -notcontains 'build.json') { throw 'Release asset allowlist failed' }
    }
    finally { $archive.Dispose() }
    foreach ($line in Get-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt')) {
        if ($line -notmatch '^([a-f0-9]{64})  (.+)$') { throw 'Invalid checksum format' }
        $expected=$Matches[1]; $file=Join-Path $output $Matches[2]
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected) { throw 'Release checksum mismatch' }
    }
    Write-Host 'PASS: Committed docs only, release metadata, ZIP contents and checksums'
    Write-Fixture 'README.md' '# Dirty source'
    $rejected=$false; try { & $builder -OutputPath (Join-Path $fixture 'dirty') } catch { $rejected=$_.Exception.Message -like '*clean, committed*' }
    if (-not $rejected) { throw 'Dirty release source was accepted' }
    Write-Fixture 'README.md' '# Fixture'
    $manifest.files += 'ignored.txt'
    Write-Fixture 'tts/strategies/fixture/manifest.json' ($manifest | ConvertTo-Json -Depth 12)
    Write-Fixture '.gitignore' "docs/private.md`ntts/strategies/fixture/ignored.txt"
    Invoke-FixtureGit @('add','.')
    Invoke-FixtureGit @('commit','--quiet','-m','test(fixture): declare ignored asset')
    Write-Fixture 'tts/strategies/fixture/ignored.txt' 'DO_NOT_SHIP'
    $rejected=$false; try { & $builder -OutputPath (Join-Path $fixture 'ignored') } catch { $rejected=$_.Exception.Message -like '*must be committed*' }
    if (-not $rejected) { throw 'Ignored untracked strategy asset was accepted' }
    Write-Host 'PASS: Dirty checkout and ignored uncommitted package files rejected'
}
finally {
    $absolute=[IO.Path]::GetFullPath($fixture)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $absolute) -notmatch '^whas-release-tests-[a-f0-9]{32}$') { throw 'Unexpected fixture cleanup path' }
    if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
