#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)]$Context)
$ErrorActionPreference = 'Stop'
if ($Context.Engine -cne 'f5-tts') { throw 'Invalid F5 uninstall context.' }
Write-Host 'F5 has no external registration to remove. Shared ownership cleanup removes its private environment, models and package; personal WAV/transcript voices are preserved.'
exit 0
