#Requires -Version 5.1
<#
.SYNOPSIS
    Verify the bundled graphical executable matches its source and checksum.
.DESCRIPTION
    Reads files only. Does not compile or execute the GUI. This freshness check
    is separate from antivirus scanning and publisher verification.
#>
[CmdletBinding()]
param([string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess) { throw 'Verify using 64-bit Windows PowerShell 5.1.' }
$root=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RepositoryRoot)
$exe=Join-Path $root 'whas-gui.exe'
$manifest=Join-Path $root 'whas-gui.build.json'
foreach($file in @($exe,$manifest)) {
    if(-not(Test-Path -LiteralPath $file -PathType Leaf)) { throw 'Bundled GUI or its build manifest is missing.' }
    if((Get-Item -LiteralPath $file -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Bundled GUI files must not be links.' }
}
$metadata=Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
$keys=@('schemaVersion','inputsSHA256','executableSHA256','platform','signed')
if($metadata -isnot [pscustomobject] -or @($metadata.PSObject.Properties.Name).Count -ne $keys.Count -or @($metadata.PSObject.Properties.Name | Where-Object { $_ -cnotin $keys }).Count) { throw 'Invalid bundled GUI manifest.' }
if($metadata.schemaVersion -ne 1 -or $metadata.platform -cne 'windows-x64' -or $metadata.signed -isnot [bool] -or $metadata.signed -ne $false -or $metadata.inputsSHA256 -cnotmatch '^[A-F0-9]{64}$' -or $metadata.executableSHA256 -cnotmatch '^[A-F0-9]{64}$') { throw 'Invalid bundled GUI manifest values.' }
if((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -cne $metadata.executableSHA256) { throw 'Bundled GUI checksum mismatch. Do not run this executable.' }
# Fingerprint returns before compilation; Force only ignores an existing output.
$inputs=(& (Join-Path $root 'scripts/build-setup.ps1') -Fingerprint -Force | Out-String).Trim()
if($inputs -cne $metadata.inputsSHA256) { throw 'Bundled GUI is stale. Rebuild and scan it before updating the manifest.' }
Write-Host 'PASS: bundled GUI matches its source fingerprint and SHA-256.'
