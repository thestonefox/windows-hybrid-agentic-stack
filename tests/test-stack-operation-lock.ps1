#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$helper = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/installation-state.ps1'
. $helper
$root = Join-Path ([IO.Path]::GetTempPath()) ('whas-lock-' + [guid]::NewGuid().ToString('N'))
$lock = Enter-StackOperationLock $root
try {
    $helperLiteral = "'" + $helper.Replace("'", "''") + "'"
    $rootLiteral = "'" + $root.Replace("'", "''") + "'"
    $code = @"
`$ErrorActionPreference='Stop'
. $helperLiteral
try { `$unexpected=Enter-StackOperationLock $rootLiteral; `$unexpected.ReleaseMutex(); `$unexpected.Dispose(); exit 2 }
catch { if (`$_.Exception.Message -notlike 'Another stack operation*') { exit 3 } }
`$other=Enter-StackOperationLock ($rootLiteral+'-other')
try { 'PASS: Same root blocked; independent root permitted' }
finally { `$other.ReleaseMutex(); `$other.Dispose() }
exit 0
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    & (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -OutputFormat Text -EncodedCommand $encoded
    if ($LASTEXITCODE -ne 0) { throw 'Concurrent root lock test failed' }
}
finally { $lock.ReleaseMutex(); $lock.Dispose() }
$after = Enter-StackOperationLock $root
try { Write-Host 'PASS: Lock can be acquired after the first operation releases it' }
finally { $after.ReleaseMutex(); $after.Dispose() }
