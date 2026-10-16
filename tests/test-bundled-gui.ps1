#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('whas-bundle-tests-'+[guid]::NewGuid().ToString('N'))
try {
    [IO.Directory]::CreateDirectory((Join-Path $fixture 'scripts'))|Out-Null
    $inputs='A'*64
    [IO.File]::WriteAllText((Join-Path $fixture 'scripts/build-setup.ps1'),"param([switch]`$Fingerprint,[switch]`$Force); if(-not `$Fingerprint){throw 'Verification attempted compilation'}; '$inputs'")
    $exe=Join-Path $fixture 'whas-gui.exe'
    $manifest=Join-Path $fixture 'whas-gui.manifest.json'
    [IO.File]::WriteAllText($exe,'Inert checksum fixture; never executed.')
    $metadata=[ordered]@{schemaVersion=1;inputsSHA256=$inputs;executableSHA256=(Get-FileHash $exe).Hash;platform='windows-x64';signed=$false}
    $metadata|ConvertTo-Json|Set-Content -LiteralPath $manifest
    $checker=Join-Path $repo 'scripts/check-bundled-gui.ps1'
    & $checker -RepositoryRoot $fixture
    $original=[IO.File]::ReadAllText($manifest)
    [IO.File]::AppendAllText($exe,'tampered')
    $rejected=$false;try { & $checker -RepositoryRoot $fixture }catch{$rejected=$_.Exception.Message -like '*checksum mismatch*'}
    if(-not $rejected -or [IO.File]::ReadAllText($manifest) -cne $original){throw 'Tampering was accepted or verification changed metadata'}
    $metadata.executableSHA256=(Get-FileHash $exe).Hash
    $metadata.inputsSHA256='B'*64
    $metadata|ConvertTo-Json|Set-Content -LiteralPath $manifest
    $rejected=$false;try { & $checker -RepositoryRoot $fixture }catch{$rejected=$_.Exception.Message -like '*stale*'}
    if(-not $rejected){throw 'Stale source was accepted'}
    Remove-Item -LiteralPath $exe
    $rejected=$false;try { & $checker -RepositoryRoot $fixture }catch{$rejected=$_.Exception.Message -like '*missing*'}
    if(-not $rejected){throw 'Missing bundled executable was accepted'}
    Write-Host 'PASS: bundled GUI freshness, tamper rejection and read-only verification'
} finally {
    $absolute=[IO.Path]::GetFullPath($fixture)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not $absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $absolute) -notmatch '^whas-bundle-tests-[a-f0-9]{32}$'){throw 'Unexpected bundle fixture cleanup'}
    if(Test-Path -LiteralPath $absolute){Remove-Item -LiteralPath $absolute -Recurse -Force}
}
