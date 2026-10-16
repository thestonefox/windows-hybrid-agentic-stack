#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference='Stop'
if (-not $OutputPath) { $OutputPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'dist/whas-gui.exe' }
# Embed the same reviewed payload as console setup; no adjacent EXE is needed.
if (-not (Get-Command Invoke-StackSetupScript -ErrorAction Ignore)) { . (Join-Path $PSScriptRoot 'script-invocation.ps1') }
Invoke-StackSetupScript -Path (Join-Path $PSScriptRoot 'build-setup.ps1') -Arguments @{OutputPath=$OutputPath;Graphical=$true}
