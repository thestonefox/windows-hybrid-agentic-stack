#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)]$Context)
# The shared uninstaller stops the service and removes unchanged owned files.
# Piper has no external service, global cache or registration to remove.
Write-Host 'Piper cleanup: private environment and models are removed by the shared coordinator.'
exit 0
