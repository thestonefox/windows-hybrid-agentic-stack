#Requires -Version 5.1

<#
.SYNOPSIS
    TTS Turbo commands for Windows Hybrid Agentic Stack.

.DESCRIPTION
    Automatically loads the configured installation directory.

    Commands:
      tts-start
      tts-stop
      tts-status
      tts-say
      tts-voice-list
      tts-voice-add
      tts-voice-remove
      tts-voice-test

    Dot-source this file to load the commands.
#>

param(
    [string]$InstallPath
)

$script:TtsStackRoot = if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    Split-Path -Parent $PSScriptRoot
} else { $InstallPath }

function Get-TtsConfiguration {
    $settings = @{
        InstallPath = $null
        Port = 18765
        IdleMinutes = 10
        Device = 'auto'
        AutoStart = $true
        Engine = 'chatterbox-turbo'
        DefaultVoice = 'default'
    }

    foreach ($relativePath in @(
        'config\defaults.json',
        'config\config.json'
    )) {
        $configPath = Join-Path $script:TtsStackRoot $relativePath

        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
            continue
        }

        $config = Get-Content `
            -LiteralPath $configPath `
            -Raw `
            -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop

        if ($null -ne $config.installation) {
            $directory = [string]$config.installation.directory

            if (-not [string]::IsNullOrWhiteSpace($directory)) {
                $settings.InstallPath = $directory
            }
        }

        if ($null -ne $config.tts) {
            if ($config.tts.engine) { $settings.Engine = [string]$config.tts.engine }
            if ($null -ne $config.tts.port) {
                $settings.Port = [int]$config.tts.port
            }

            if ($null -ne $config.tts.idleTimeoutMinutes) {
                $settings.IdleMinutes = [int](
                    $config.tts.idleTimeoutMinutes
                )
            }

            if ($null -ne $config.tts.device) {
                $settings.Device = [string]$config.tts.device
            }

            if ($null -ne $config.tts.autoStart) {
                $settings.AutoStart = [bool]$config.tts.autoStart
            }

            if ($null -ne $config.tts.defaultVoice) {
                $settings.DefaultVoice = [string](
                    $config.tts.defaultVoice
                )
            }
        }
    }

    return $settings
}

$script:TtsSettings = Get-TtsConfiguration

if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = $script:TtsSettings.InstallPath
}

if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = Join-Path $HOME 'AI\WindowsHybridAgenticStack'
}

$InstallPath = [Environment]::ExpandEnvironmentVariables($InstallPath)

if ($InstallPath -match '^\$HOME(?=[\\/]|$)') {
    $InstallPath = $HOME + $InstallPath.Substring(5)
}

$script:TtsRoot = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($InstallPath)

$script:TtsServiceDir = Join-Path $script:TtsRoot 'tts'
$script:TtsServiceFile = Join-Path $script:TtsServiceDir 'tts_service.py'
$script:TtsPython = Join-Path $script:TtsRoot '.venv\Scripts\python.exe'
$script:TtsPidFile = Join-Path $script:TtsServiceDir 'service.pid'
$script:TtsVoiceDirectory = Join-Path $script:TtsRoot 'voices'
$script:TtsRuntime = $null
$runtimePath = Join-Path $script:TtsServiceDir 'runtime.json'
if (Test-Path -LiteralPath $runtimePath) {
    if (-not (Get-Command Resolve-TtsPackagePath -ErrorAction Ignore)) {
        . (Join-Path $script:TtsServiceDir 'strategy-management.ps1')
    }
    $script:TtsRuntime = Get-Content -LiteralPath $runtimePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($script:TtsRuntime.schemaVersion -ne 1 -or $script:TtsRuntime.engine -cne $script:TtsSettings.Engine) { throw 'TTS runtime and configured engine differ; reinstall the selected engine.' }
    $script:TtsPython = Join-Path (Resolve-TtsPackagePath $script:TtsRoot $script:TtsRuntime.environmentPath) 'Scripts/python.exe'
    $script:TtsVoiceDirectory = Resolve-TtsPackagePath $script:TtsRoot $script:TtsRuntime.voicesPath
}

$script:TtsPort = $script:TtsSettings.Port
$script:TtsIdleMinutes = $script:TtsSettings.IdleMinutes
$script:TtsDevice = $script:TtsSettings.Device
if ($script:TtsRuntime) { $script:TtsDevice = $script:TtsRuntime.device }
$script:TtsAutoStart = $script:TtsSettings.AutoStart
$script:TtsDefaultVoice = $script:TtsSettings.DefaultVoice

$script:TtsBaseUrl = "http://127.0.0.1:$script:TtsPort"

function Get-TtsStatusResponse {
    try {
        $response = Invoke-RestMethod `
            -Uri "$script:TtsBaseUrl/status" `
            -TimeoutSec 2 `
            -ErrorAction Stop
    }
    catch {
        return $null
    }
    if ($script:TtsRuntime -and ($response.engine -cne $script:TtsRuntime.engine -or $response.installation_root -ine $script:TtsRoot)) { throw 'Another service is using the configured speech port.' }
    return $response
}

function Get-TtsServiceProcess {
    if (-not (Test-Path -LiteralPath $script:TtsPidFile -PathType Leaf)) {
        return $null
    }

    $savedPid = (
        Get-Content -LiteralPath $script:TtsPidFile -Raw
    ).Trim()

    if ($savedPid -notmatch '^[0-9]+$') {
        return $null
    }

    $processInfo = Get-CimInstance `
        -ClassName Win32_Process `
        -Filter "ProcessId=$savedPid" `
        -ErrorAction SilentlyContinue

    if ($null -eq $processInfo) {
        return $null
    }

    if ($processInfo.Name -notmatch '^python(w)?\.exe$') {
        return $null
    }

    if ($processInfo.ExecutablePath -ine $script:TtsPython -or -not $processInfo.CommandLine -or -not $processInfo.CommandLine.Contains(('"' + $script:TtsServiceFile + '"'))) {
        return $null
    }

    return $processInfo
}

function tts-status {
    $status = Get-TtsStatusResponse

    if ($null -ne $status) {
        $voice = if ($status.loaded_voice) {
            $status.loaded_voice
        }
        else {
            'unknown'
        }

        Write-Host 'TTS: RUNNING'
        Write-Host "Address:     $script:TtsBaseUrl"
        Write-Host "Voice:       $voice"
        Write-Host "Idle limit:  $script:TtsIdleMinutes minutes"
        return
    }

    if ($null -ne (Get-TtsServiceProcess)) {
        Write-Host 'TTS: STARTING or still loading'
        return
    }

    Write-Host 'TTS: STOPPED'
}

function tts-start {
    if ($null -ne (Get-TtsStatusResponse)) {
        Write-Host 'TTS is already running.'
        return
    }

    if ($null -ne (Get-TtsServiceProcess)) {
        Write-Host 'TTS is already starting.'
        return
    }

    if (-not (Test-Path -LiteralPath $script:TtsPython -PathType Leaf)) {
        Write-Error (
            'TTS Python environment is not installed: ' +
            $script:TtsPython
        )
        return
    }

    if (-not (Test-Path -LiteralPath $script:TtsServiceFile -PathType Leaf)) {
        Write-Error "TTS service not found: $script:TtsServiceFile"
        return
    }

    $device = $script:TtsDevice

    if ($device -eq 'auto') {
        $nvidiaCommand = Get-Command `
            nvidia-smi `
            -ErrorAction SilentlyContinue

        if ($null -ne $nvidiaCommand) {
            try {
                $null = & nvidia-smi -L 2>$null

                if ($LASTEXITCODE -eq 0) {
                    $device = 'cuda'
                }
                else {
                    $device = 'cpu'
                }
            }
            catch {
                $device = 'cpu'
            }
        }
        else {
            $device = 'cpu'
        }
    }

    $names = @(
        'AGENT_STACK_TTS_ROOT',
        'AGENT_STACK_TTS_PORT',
        'AGENT_STACK_TTS_IDLE_SECONDS',
        'AGENT_STACK_TTS_DEVICE',
        'AGENT_STACK_TTS_OWN_LOGS'
    )

    $original = @{}

    foreach ($name in $names) {
        $original[$name] = [Environment]::GetEnvironmentVariable(
            $name,
            'Process'
        )
    }

    try {
        $env:AGENT_STACK_TTS_ROOT = $script:TtsRoot
        $env:AGENT_STACK_TTS_PORT = [string]$script:TtsPort
        $env:AGENT_STACK_TTS_IDLE_SECONDS = [string](
            $script:TtsIdleMinutes * 60
        )
        $env:AGENT_STACK_TTS_DEVICE = $device

        if ($null -ne ('WindowsHybridAgenticStack.CommandHost' -as [type])) {
            $env:AGENT_STACK_TTS_OWN_LOGS = '1'
            $servicePid = [WindowsHybridAgenticStack.CommandHost]::StartBackgroundProcess(
                $script:TtsPython, ('-u "' + $script:TtsServiceFile + '"'), $script:TtsServiceDir)
        }
        else {
            $process = Start-Process `
            -FilePath $script:TtsPython `
            -ArgumentList ('-u "' + $script:TtsServiceFile + '"') `
            -WorkingDirectory $script:TtsServiceDir `
            -WindowStyle Hidden `
            -RedirectStandardOutput (
                Join-Path $script:TtsServiceDir 'service.log'
            ) `
            -RedirectStandardError (
                Join-Path $script:TtsServiceDir 'service-errors.log'
            ) `
            -PassThru `
            -ErrorAction Stop
            $servicePid = $process.Id
        }

        Set-Content `
            -LiteralPath $script:TtsPidFile `
            -Value $servicePid

        Write-Host "TTS starting (PID $servicePid)."
        Write-Host 'Run tts-status to check when it is ready.'
    }
    finally {
        foreach ($name in $names) {
            [Environment]::SetEnvironmentVariable(
                $name,
                $original[$name],
                'Process'
            )
        }
    }
}

function tts-stop {
    $process = Get-TtsServiceProcess

    if ($null -eq $process) {
        Write-Host 'No matching TTS process found.'
        return
    }

    Stop-Process `
        -Id ([int]$process.ProcessId) `
        -Force `
        -ErrorAction Stop

    Remove-Item `
        -LiteralPath $script:TtsPidFile `
        -Force `
        -ErrorAction SilentlyContinue

    Write-Host 'TTS stopped.'
}

function Wait-TtsReady {
    if ($null -ne (Get-TtsStatusResponse)) {
        return $true
    }

    if (-not $script:TtsAutoStart) {
        Write-Warning 'TTS is stopped and autoStart is disabled.'
        return $false
    }

    if ($null -eq (Get-TtsServiceProcess)) {
        tts-start
    }

    $watch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($watch.Elapsed.TotalSeconds -lt 60) {
        if ($null -ne (Get-TtsStatusResponse)) {
            return $true
        }

        if ($null -eq (Get-TtsServiceProcess)) {
            break
        }

        Start-Sleep -Milliseconds 500
    }

    Write-Warning (
        'TTS did not become ready. Check service-errors.log.'
    )

    return $false
}

function Get-TtsWavDurationSeconds {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $stream = [System.IO.File]::OpenRead($Path)
    $reader = New-Object System.IO.BinaryReader($stream)

    try {
        $ascii = [System.Text.Encoding]::ASCII

        if ($ascii.GetString($reader.ReadBytes(4)) -ne 'RIFF') {
            throw 'Not a RIFF WAV file.'
        }

        $null = $reader.ReadUInt32()

        if ($ascii.GetString($reader.ReadBytes(4)) -ne 'WAVE') {
            throw 'Not a WAVE file.'
        }

        $bytesPerSecond = [uint32]0
        $audioBytes = [uint32]0

        while ($stream.Position + 8 -le $stream.Length) {
            $chunkName = $ascii.GetString($reader.ReadBytes(4))
            $chunkSize = $reader.ReadUInt32()
            $chunkStart = $stream.Position

            if ($chunkSize -gt $stream.Length - $chunkStart) {
                throw 'Invalid WAV chunk size.'
            }

            if ($chunkName -eq 'fmt ') {
                if ($chunkSize -lt 16) {
                    throw 'Invalid WAV format header.'
                }

                $null = $reader.ReadUInt16()
                $null = $reader.ReadUInt16()
                $null = $reader.ReadUInt32()
                $bytesPerSecond = $reader.ReadUInt32()
            }
            elseif ($chunkName -eq 'data') {
                $audioBytes = $chunkSize
            }

            $stream.Position = (
                $chunkStart + $chunkSize + ($chunkSize % 2)
            )

            if ($bytesPerSecond -gt 0 -and $audioBytes -gt 0) {
                return [double]$audioBytes / [double]$bytesPerSecond
            }
        }

        throw 'Could not determine WAV duration.'
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function tts-say {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Text,

        [string]$Voice = $script:TtsDefaultVoice
    )

    if (-not (Wait-TtsReady)) {
        Write-Error 'The selected speech engine is not ready.'
        return
    }

    $outputFile = Join-Path $script:TtsServiceDir 'last-spoken.wav'

    $payload = @{
        text = $Text
        voice = $Voice
    } | ConvertTo-Json -Compress

    try {
        Invoke-WebRequest `
            -Uri "$script:TtsBaseUrl/speak" `
            -Method Post `
            -ContentType 'application/json; charset=utf-8' `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) `
            -OutFile $outputFile `
            -TimeoutSec 180 `
            -UseBasicParsing `
            -ErrorAction Stop | Out-Null

        $duration = Get-TtsWavDurationSeconds -Path $outputFile
        $player = New-Object System.Media.SoundPlayer($outputFile)

        try {
            $player.Load()
            $player.Play()

            $watch = [System.Diagnostics.Stopwatch]::StartNew()

            while ($watch.Elapsed.TotalSeconds -lt $duration) {
                Start-Sleep -Milliseconds 100
            }
        }
        finally {
            $player.Stop()
            $player.Dispose()
        }
    }
    catch {
        Write-Error "Speech failed: $($_.Exception.Message)"
    }
}

function tts-voice-list {
    if ($script:TtsRuntime) {
        if (-not (Wait-TtsReady)) { Write-Error 'The selected speech engine is not ready.'; return }
        try {
            $response = Invoke-RestMethod -Uri "$script:TtsBaseUrl/voices" -TimeoutSec 10 -ErrorAction Stop
            foreach ($name in $response.voices) { Write-Host $name }
        }
        catch { Write-Error "Could not list engine voices: $($_.Exception.Message)" }
        return
    }
    Write-Host 'default (built-in)'

    if (-not (Test-Path -LiteralPath $script:TtsVoiceDirectory)) {
        return
    }

    Get-ChildItem `
        -LiteralPath $script:TtsVoiceDirectory `
        -Filter '*_prompt.pt' `
        -File `
        -ErrorAction SilentlyContinue |
        ForEach-Object {
            $_.BaseName -replace '_prompt$', ''
        } |
        Where-Object { $_ -ne 'default' } |
        Sort-Object |
        ForEach-Object { Write-Host $_ }
}

function tts-voice-add {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($script:TtsRuntime -and -not $script:TtsRuntime.capabilities.voiceCloning) { Write-Error 'The selected engine does not support reference-recording voices.'; return }

    if ($Name -eq 'default') {
        Write-Error 'default is the reserved built-in voice.'
        return
    }

    if ($Name -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$') {
        Write-Error 'Invalid voice name.'
        return
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Error "WAV file not found: $Path"
        return
    }

    if ([System.IO.Path]::GetExtension($Path) -ine '.wav') {
        Write-Error 'Only WAV reference files are supported.'
        return
    }

    if (-not (Wait-TtsReady)) {
        Write-Error 'The selected speech engine is not ready.'
        return
    }

    $absolutePath = (Resolve-Path -LiteralPath $Path).ProviderPath

    $payload = @{
        name = $Name
        path = $absolutePath
    } | ConvertTo-Json -Compress

    try {
        $result = Invoke-RestMethod `
            -Uri "$script:TtsBaseUrl/voices/add" `
            -Method Post `
            -ContentType 'application/json; charset=utf-8' `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) `
            -TimeoutSec 180 `
            -ErrorAction Stop

        Write-Host "Voice '$($result.added)' cached."
    }
    catch {
        Write-Error "Could not create voice: $($_.Exception.Message)"
    }
}

function tts-voice-remove {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Name
    )

    if ($script:TtsRuntime -and -not $script:TtsRuntime.capabilities.voiceCloning) { Write-Error 'The selected engine does not support reference-recording voices.'; return }

    if ($Name -eq 'default') {
        Write-Error 'Cannot remove the built-in default voice.'
        return
    }

    if ($Name -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$') {
        Write-Error 'Invalid voice name.'
        return
    }

    $confirmation = Read-Host (
        "Delete voice '$Name' and its reference WAV? Type YES"
    )

    if ($confirmation -cne 'YES') {
        Write-Host 'Cancelled.'
        return
    }

    if (-not (Wait-TtsReady)) {
        Write-Error 'The selected speech engine is not ready.'
        return
    }

    $payload = @{
        name = $Name
    } | ConvertTo-Json -Compress

    try {
        $result = Invoke-RestMethod `
            -Uri "$script:TtsBaseUrl/voices/remove" `
            -Method Post `
            -ContentType 'application/json; charset=utf-8' `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) `
            -TimeoutSec 15 `
            -ErrorAction Stop

        Write-Host "Voice '$($result.removed)' removed."
    }
    catch {
        Write-Error "Could not remove voice: $($_.Exception.Message)"
    }
}

function tts-voice-test {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Name
    )

    tts-say `
        -Text 'Hello! This is a test of my TTS voice.' `
        -Voice $Name
}
