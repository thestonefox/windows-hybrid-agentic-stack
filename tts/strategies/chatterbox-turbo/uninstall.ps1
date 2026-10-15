#Requires -Version 5.1
param([Parameter(Mandatory=$true)]$Context)
$ErrorActionPreference = 'Stop'
# Shared ownership cleanup removes the private environment and model files.
# Personal voices and shared/global caches are deliberately preserved.
Write-Host 'Chatterbox cleanup: no external resources require removal.'
exit 0
