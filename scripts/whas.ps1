#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$InstallPath)
$script:WhasRoot = $InstallPath

function Show-WhasHelp {
    @'
Usage: whas COMMAND [OPTIONS]
  ask, askl, askc             Independent restricted question
  perform, performl, performc Independent tool-enabled task
  chat, chatl, chatc          Interactive conversation
  configure                  Shared settings menu
  configure --show           Print effective settings as JSON
  configure --set KEY VALUE  Change one setting
  tts COMMAND                Speech management (list, start, status, etc.)
  model list                 List local Ollama models
  model catalog --local      List local model IDs as JSON
  model catalog --cloud      List OpenCode cloud model IDs as JSON
  agent list                 List agent runtime strategies
  session list               List WHAS conversation associations
Request options: --local | --cloud, --runtime ID, -m | --model ID
Speech: --voice | --no-voice (interactive chat requires --no-voice).
Questions/tasks: -l | --log displays raw runtime output.
Chat: --new (default), --session ID, --message TEXT for a JSON turn.
Settings: configure --set speech.voice NAME --engine ID for an engine's voice.
Management: agent check ID | native ID [ARGS] | install ID [--yes]
            agent uninstall ID [--apply] [--yes] (managed runtimes only)
Sessions: session forget RUNTIME SESSION --yes (native history is retained).
Help: --help | -h | help; tts --help (also available as tts-help).
Full command and flag reference: docs/cli.md in the source repository.
Shortcuts ending l/c select local/cloud; conflicting options are errors.
'@ | Write-Output
}

function Show-WhasTtsHelp {
    @'
Usage: whas tts COMMAND [OPTIONS]   (legacy launchers: tts-COMMAND)
  list                         List installed/default/active engines
  inventory                    Engine capabilities and voices as JSON
  install ID [--device auto|cpu|cuda] [--yes]
  uninstall ID [--default-engine ID] [--apply] [--yes]
                               Preview by default; --apply requests removal
  default [ID]                 Show or save the default engine
  start | stop | status        Manage or probe the speech service
  say TEXT [--voice NAME]       Generate and play speech
  voice-list                   List voices
  voice-add --path FILE --name NAME
  voice-test NAME              Generate and play a test phrase
  voice-remove NAME [--yes]     Delete a custom voice
start/stop/status/say/voice-* accept --engine ID.
say also accepts --text TEXT; voice-test/remove accept --name NAME.
install/uninstall/default also accept --engine ID instead of positional ID.
Named speech options accept -Text/-Voice/-Path/-Name/-Engine/-Device,
-DefaultEngine/-Apply/-Yes as well as their --lower-case forms.
Engine resolution: explicit --engine, then active engine, then saved default.
GUI Assistant speech explicitly uses the saved default, independent of previews.
Piper has no custom voices. F5 requires matching WAV and UTF-8 .txt files.
Adding/testing a voice does not save a default. Use:
  whas configure --set speech.voice NAME --engine ID
Legacy engine launchers: tts-engine-list/install/uninstall/default.
Help: whas tts --help | whas tts -h | whas tts help | tts-help
'@ | Write-Output
}

function Set-WhasSetting {
    param([string]$Key,[string]$Value,[string]$Engine)
    $paths = @{
        location='interaction.location';runtime='interaction.runtime'
        'cloud.model'='agents.cloud.model';'local.model'='agents.local.model'
        'cloud.enabled'='agents.cloud.enabled';'local.enabled'='agents.local.enabled'
        'speech.enabled'='interaction.speech';'speech.voice'='tts.defaultVoice'
        'speech.device'='tts.device';'speech.autoStart'='tts.autoStart'
        'speech.idleTimeoutMinutes'='tts.idleTimeoutMinutes'
    }
    if (-not $paths.ContainsKey($Key)) { throw "Unknown setting: $Key" }
    $lock = Enter-StackOperationLock $script:WhasRoot
    try {
        $config = Get-StackConfiguration $script:WhasRoot
        if ($Engine) {
            if ($Key -ne 'speech.voice') { throw '--engine is only supported for speech.voice settings.' }
            $package=Get-TtsStrategy -Root $script:WhasRoot -Id $Engine
            if ($Value -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$') { throw 'Invalid voice name.' }
            if ($Value -cne 'default') {
                $state=Read-StackInstallationState $script:WhasRoot -ReadOnly
                $record=@($state.TtsStrategies | Where-Object { $_.Id -ceq $Engine -and $_.Status -eq 'Installed' })
                if ($record.Count -ne 1) { throw 'Install the selected speech engine first.' }
                if (@(Get-TtsReferenceNames -Root $script:WhasRoot -Package $package -Record $record[0]) -cnotcontains $Value) { throw 'Voice reference is unavailable for the selected engine.' }
            }
            $config.tts.voiceDefaults | Add-Member -NotePropertyName $Engine -NotePropertyValue $Value -Force
        }
        $parts = $paths[$Key].Split('.')
        $object = $config
        foreach ($part in $parts[0..($parts.Count-2)]) { $object = $object.$part }
        $name = $parts[-1]
        $converted = $Value
        if ($Key -eq 'speech.idleTimeoutMinutes') {
            $minutes=0
            if ($Value -notmatch '^[0-9]+$' -or -not [int]::TryParse($Value,[ref]$minutes)) { throw 'Speech idle timeout must be a non-negative whole number of minutes.' }
            $converted=$minutes
        }
        if ($Key -eq 'cloud.model' -and [string]::IsNullOrWhiteSpace($Value)) { $converted=$null }
        if ($object.$name -is [bool]) {
            if ($Value -notin @('true','false')) { throw 'Boolean settings require true or false.' }
            $converted = $Value -eq 'true'
        }
        if ($Key -eq 'runtime') { if($Value -eq 'none') { $converted=$null } else { $null = Get-WhasAgentExecutable (Get-WhasAgentStrategy $Value) } }
        if (-not $Engine) { $object.$name = $converted }
        $errors = @(Assert-Configuration $config)
        if ($errors.Count) { throw ($errors -join '; ') }
        $path = Join-Path $script:WhasRoot 'config/config.json'
        $null = Resolve-StackOwnedPath $script:WhasRoot 'config/config.json'
        foreach ($candidate in @((Split-Path -Parent $path),$path)) {
            if ((Test-Path -LiteralPath $candidate) -and ((Get-Item -LiteralPath $candidate -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Configuration must not use reparse points.' }
        }
        $temporary = $path + '.tmp.' + [guid]::NewGuid().ToString('N')
        try {
            [IO.File]::WriteAllText($temporary, ($config | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
            if (Test-Path -LiteralPath $path) { [IO.File]::Replace($temporary,$path,[System.Management.Automation.Language.NullString]::Value) }
            else { [IO.File]::Move($temporary,$path) }
        } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
        Write-Output "Saved $Key. New requests use the updated setting."
    } finally { $lock.ReleaseMutex(); $lock.Dispose() }
}

function Invoke-WhasConfigure {
    param([string[]]$Arguments)
    if ($Arguments.Count) {
        if ($Arguments.Count -eq 1 -and $Arguments[0] -eq '--show') { Get-StackConfiguration $script:WhasRoot | ConvertTo-Json -Depth 30; return }
        if ($Arguments.Count -eq 3 -and $Arguments[0] -eq '--set') { Set-WhasSetting $Arguments[1] $Arguments[2]; return }
        if ($Arguments.Count -eq 5 -and $Arguments[0] -eq '--set' -and $Arguments[3] -eq '--engine') { Set-WhasSetting $Arguments[1] $Arguments[2] $Arguments[4]; return }
        throw 'Usage: whas configure [--show | --set KEY VALUE]'
    }
    while ($true) {
        Write-Host "`nWHAS settings: General, Agents, Models, Voice, Sessions"
        Write-Host 'Settings: location, runtime, cloud.model, local.model, speech.enabled,'
        Write-Host 'speech.voice, speech.device, speech.autoStart, speech.idleTimeoutMinutes'
        Write-Host 'Voice management: whas tts list / voice-list / voice-add / voice-remove'
        Write-Host 'Engine management: whas tts install / uninstall / default'
        $key = Read-Host 'Setting to change (show to inspect, blank to finish)'
        if (-not $key) { return }
        if ($key -eq 'show') { Get-StackConfiguration $script:WhasRoot | ConvertTo-Json -Depth 30 | Write-Host; continue }
        try { Set-WhasSetting $key (Read-Host 'New value') } catch { Write-Warning $_.Exception.Message }
    }
}

function Invoke-Whas {
    param([string[]]$Arguments)
    $ownership=Read-StackInstallationState $script:WhasRoot -ReadOnly
    if(-not $ownership) { throw 'No tracked installation exists at the registered root.' }
    if (-not $Arguments.Count -or $Arguments[0] -in @('--help','-h','help')) { Show-WhasHelp; return }
    $verb = $Arguments[0]
    $rest = @($Arguments | Select-Object -Skip 1)
    if ($verb -eq 'configure') { Invoke-WhasConfigure $rest; return }
    if ($verb -eq 'tts') {
        if (-not $rest.Count -or ($rest.Count -eq 1 -and $rest[0] -in @('--help','-h','help'))) { Show-WhasTtsHelp; return }
        if (-not $rest.Count) { throw 'Specify a speech command; use whas --help.' }
        if ($rest.Count -eq 1 -and $rest[0] -eq 'inventory') {
            $state=Read-StackInstallationState $script:WhasRoot -ReadOnly
            $items=@(foreach($package in Get-TtsStrategies $script:WhasRoot) {
                $id=$package.Manifest.id
                $record=@($state.TtsStrategies | Where-Object { $_.Id -ceq $id -and $_.Status -eq 'Installed' })
                $names=@('default')
                if($record.Count) {
                    $names+=@(Get-TtsReferenceNames -Root $script:WhasRoot -Package $package -Record $record[0])
                }
                [pscustomobject]@{id=$id;installed=($record.Count -eq 1);voiceCloning=$package.Manifest.capabilities.voiceCloning;transcriptRequired=([bool]$package.Manifest.voiceReference.transcriptRequired);referenceInventoryVersion=1;voices=@($names | Select-Object -Unique)}
            })
            ConvertTo-Json -InputObject $items -Depth 8 -Compress
            return
        }
        $map = @{list='tts-engine-list';install='tts-engine-install';uninstall='tts-engine-uninstall';default='tts-engine-default'}
        $command = if ($map.ContainsKey($rest[0])) { $map[$rest[0]] } else { 'tts-' + $rest[0] }
        if ($command -notin @(Get-StackCommandNames | Where-Object { $_ -like 'tts-*' })) { throw 'Unknown speech command.' }
        & (Join-Path ([IO.Path]::GetDirectoryName([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)) "$command.exe") @($rest | Select-Object -Skip 1)
        if ($LASTEXITCODE -ne 0) { throw 'Speech command failed.' }; return
    }
    if ($verb -eq 'model' -and $rest.Count -eq 1 -and $rest[0] -eq 'list') { & ollama list; if ($LASTEXITCODE) { throw 'Ollama model listing failed.' }; return }
    if ($verb -eq 'model' -and $rest.Count -eq 2 -and $rest[0] -eq 'catalog' -and $rest[1] -in @('--local','--cloud')) {
        $previousConfig=$env:OPENCODE_CONFIG
        try {
            if ($rest[1] -eq '--local') {
                $lines=@(& ollama list)
                if ($LASTEXITCODE) { throw 'Ollama model listing failed.' }
                $names=@($lines | Select-Object -Skip 1 | ForEach-Object { ($_.Trim() -split '\s+')[0] } | Where-Object { $_ -cmatch '^[A-Za-z0-9][A-Za-z0-9._/:-]*$' })
            } else {
                $env:OPENCODE_CONFIG=Join-Path $script:WhasRoot 'opencode.json'
                $lines=@(& opencode models)
                if ($LASTEXITCODE) { throw 'OpenCode model listing failed. Connect a provider through OpenCode and retry.' }
                $names=@($lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -cmatch '^[A-Za-z0-9._-]+/[^\s]+$' -and $_ -notmatch '^ollama/' })
            }
            ConvertTo-Json -InputObject @($names | Sort-Object -Unique) -Compress
        } finally { $env:OPENCODE_CONFIG=$previousConfig }
        return
    }
    if ($verb -eq 'agent') { Invoke-WhasAgentManagement $rest; return }
    if ($verb -eq 'session') { Invoke-WhasSessionManagement $rest; return }
    if ($verb -notmatch '^(ask|perform|chat)([lc]?)$') { throw "Unknown command: $verb" }
    if($ownership.Status -ne 'Installed') { throw 'Installation is incomplete. Repair or uninstall it before running agent requests.' }
    $action = $Matches[1]; $shortcut = $Matches[2]
    $config = Get-StackConfiguration $script:WhasRoot
    $location = $config.interaction.location
    $explicitLocation = if ($shortcut -eq 'l') { 'local' } elseif ($shortcut -eq 'c') { 'cloud' } else { $null }
    $runtime = $config.interaction.runtime
    $session = $null; $newSession = $false; $forward = @(); $voice = $config.interaction.speech
    for ($i=0; $i -lt $rest.Count; $i++) {
        switch ($rest[$i]) {
            { $_ -in @('--local','--cloud') } {
                $choice = $rest[$i].Substring(2)
                if ($explicitLocation -and $explicitLocation -ne $choice) { throw 'Conflicting local/cloud selection.' }
                $explicitLocation = $choice; break
            }
            '--runtime' { if (++$i -ge $rest.Count) { throw 'Missing runtime.' }; $runtime = $rest[$i]; break }
            '--session' { if (++$i -ge $rest.Count) { throw 'Missing session ID.' }; $session=$rest[$i]; break }
            '--new' { $newSession=$true; break }
            '--voice' { $voice=$true; break }
            '--no-voice' { $voice=$false; break }
            default { $forward += $rest[$i] }
        }
    }
    if ($explicitLocation) { $location = $explicitLocation }
    if (-not $config.agents.$location.enabled) { throw "The $location feature has been removed. Add it in Configuration > Maintenance > Features before making requests." }
    if(-not $runtime) { throw 'No default agent runtime is selected. Install an agent or choose one with whas configure.' }
    if ($session -and ($newSession -or $action -ne 'chat')) { throw 'Session continuation is only valid for chat without --new.' }
    if ($session -and $session -cnotmatch '^[A-Za-z0-9_-]{1,160}$') { throw 'Invalid session ID.' }
    if ($voice -and $action -eq 'chat') { throw 'Interactive speech is not supported yet; use ask/perform with --voice.' }
    Invoke-WhasAgent -Runtime $runtime -Action $action -Location $location -Arguments $forward -Session $session -Voice:$voice
}
