#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$InstallPath,
    [Parameter(Mandatory=$true)][ValidateSet('voice-default','voice-add','voice-remove','speak','remove-route','speech-timeout')][string]$Action,
    [string]$Engine,[string]$VoiceName,[string]$Text,[string]$ReferencePath,
    [ValidateSet('cloud','local')][string]$Feature,
    [string]$IdleTimeoutMinutes
)
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
. (Get-StackSetupScript (Join-Path $PSScriptRoot 'configuration.ps1'))
. (Get-StackSetupScript (Join-Path $PSScriptRoot 'installation-state.ps1'))
$InstallPath=Assert-StackInstallationRoot -Root ([IO.Path]::GetFullPath($InstallPath))
$state=Read-StackInstallationState -Root $InstallPath -ReadOnly
if (-not $state -or $state.Status -ne 'Installed') { throw 'Choose a complete installation owned by this Windows user.' }
. (Get-StackSetupScript (Join-Path $source 'tts/strategy-management.ps1'))
. (Get-StackSetupScript (Join-Path $PSScriptRoot 'whas.ps1')) -InstallPath $InstallPath
if ($Action -eq 'speech-timeout') {
    Set-WhasSetting -Key 'speech.idleTimeoutMinutes' -Value $IdleTimeoutMinutes
}
elseif ($Action -eq 'voice-default') {
    if (-not $Engine -or -not $VoiceName) { throw 'Choose an engine and a saved voice.' }
    Set-WhasSetting -Key 'speech.voice' -Value $VoiceName -Engine $Engine
}
elseif ($Action -eq 'remove-route') {
    if (-not $Feature) { throw 'Choose Cloud or Local AI.' }
    Set-WhasSetting -Key "$Feature.enabled" -Value 'false'
    Write-Output 'WHAS route removed. Provider accounts, external applications and local model files are retained.'
}
else {
    if ($Action -eq 'speak' -and [string]::IsNullOrWhiteSpace($Text)) { throw 'Enter text to speak.' }
    . (Get-StackSetupScript (Join-Path $source 'tts/tts.ps1')) -InstallPath $InstallPath
    if ($Action -eq 'voice-add') {tts-voice-add -Path $ReferencePath -Name $VoiceName -Engine $Engine;return}
    if ($Action -eq 'voice-remove') {tts-voice-remove -Name $VoiceName -Engine $Engine -Yes;return}
    $arguments=@{Text=$Text}
    if ($VoiceName) { $arguments.Voice=$VoiceName }
    # Assistant replies follow the saved default, not the engine left running
    # by a preview. Explicit preview selections still override this request.
    if (-not $Engine) { $Engine=Get-TtsDefaultEngine }
    if (-not $Engine) { throw 'Choose a default speech engine under Configuration > Speech.' }
    $arguments.Engine=$Engine
    tts-say @arguments
}
