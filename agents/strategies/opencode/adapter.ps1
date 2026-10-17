param([string]$Action,[string]$Location,[string[]]$Arguments,[string]$Session,[bool]$Voice,[string]$Root)
if ($Action -ne 'chat') {
    $kind = if ($Location -eq 'local') { if ($Action -eq 'perform') { 'localagentdo' } else { 'localagent' } } else { if ($Action -eq 'perform') { 'agentdo' } else { 'agent' } }
    if ($Voice) { $Arguments = @('--voice') + $Arguments }
    Invoke-AgentStackTask -Kind $kind -Arguments $Arguments -StrictOutcome -PlainQuestion:($Action -eq 'ask')
    return
}
$config = Get-StackConfiguration $Root
$model = [string]$config.agents.$Location.model
$provider = [string]$config.agents.$Location.provider
$message=$null
for ($i=0; $i -lt $Arguments.Count; $i++) {
    $option=$Arguments[$i]
    if ($option -notin @('--model','-m','--message') -or ++$i -ge $Arguments.Count) { throw 'Chat accepts --model MODEL and --message TEXT.' }
    if ($option -eq '--message') { $message=$Arguments[$i] } else { $model = $Arguments[$i] }
}
if ($model -and $model -notmatch '/') { $model = "$provider/$model" }
$options = @('--agent','whas-chat')
if ($model) { $options += @('--model',$model) }
if ($Session) { $options += @('--session',$Session) }
$previous = $env:OPENCODE_CONFIG
$previousInline = $env:OPENCODE_CONFIG_CONTENT
try {
    $env:OPENCODE_CONFIG = Join-Path $Root 'opencode.json'
    $env:OPENCODE_CONFIG_CONTENT=Add-AgentConversationConfiguration
    if($Location -eq 'local') { $env:OPENCODE_CONFIG_CONTENT=Add-AgentLocalModelConfiguration $model }
    if ($null -ne $message) {
        if ([string]::IsNullOrWhiteSpace($message)) { throw 'Enter a chat message.' }
        $text=$null; $sessionId=$Session; $failed=$false; $activity=$null;$failureReasons=New-Object 'Collections.Generic.List[string]'
        if ($null -ne ('WindowsHybridAgenticStack.OperationActivity' -as [type])) { $activity=[WindowsHybridAgenticStack.OperationActivity]::Begin('Waiting for conversation response') }
        $previousConsoleEncoding=[Console]::OutputEncoding
        $previousOutputEncoding=$OutputEncoding
        $previousWriter=[Console]::Out; $previousErrorWriter=[Console]::Error
        try {
            $utf8=New-Object Text.UTF8Encoding($false)
            [Console]::OutputEncoding=$utf8; $OutputEncoding=$utf8
            Invoke-AgentOpenCode (@('run')+$options+@('--format','json',$message)) | ForEach-Object {
                try { $event=$_ | ConvertFrom-Json -ErrorAction Stop }
                catch { if(([string]$_).Trim()) {$failureReasons.Add('OpenCode returned invalid response data.')} ;return }
                if ($event.sessionID) { $sessionId=$event.sessionID } elseif ($event.session_id) { $sessionId=$event.session_id }
                if ($event.type -eq 'text' -and -not $event.part.synthetic) { $text=ConvertTo-AgentAnswer ([string]$event.part.text) $message }
                if ($event.type -eq 'error') {
                    $failed=$true
                    $reason=[string]$event.error.data.message
                    if(-not $reason) {$reason=[string]$event.error.message}
                    if(-not $reason) {$reason=[string]$event.error.name;if($event.error.data.modelID){$reason+=': '+$event.error.data.providerID+'/'+$event.error.data.modelID}}
                    if($reason) {$failureReasons.Add($reason)}
                }
            }
            if ($LASTEXITCODE -ne 0 -or $failed -or -not $text) {
                $reason=if($failureReasons.Count){' '+(($failureReasons|Select-Object -Unique)-join '; ')}elseif($LASTEXITCODE -ne 0){" OpenCode exited with code $LASTEXITCODE."}else{''}
                throw ('Conversation request failed; no completed answer was received.'+$reason)
            }
            if (-not $sessionId) { throw 'The runtime did not return a session ID; continuation is unavailable.' }
            [pscustomobject]@{answer=$text;sessionId=$sessionId;runtime='opencode';location=$Location} | ConvertTo-Json -Compress
        } finally {
            [Console]::OutputEncoding=$previousConsoleEncoding; $OutputEncoding=$previousOutputEncoding
            [Console]::SetOut($previousWriter); [Console]::SetError($previousErrorWriter)
            if($activity) { $activity.Dispose() }
        }
        return
    }
    if ($null -ne ('WindowsHybridAgenticStack.CommandHost' -as [type]) -and -not [Console]::IsInputRedirected) {
        $code=[WindowsHybridAgenticStack.CommandHost]::RunInteractive((Get-Command opencode -CommandType Application -ErrorAction Stop).Source,[string[]]$options)
    } else { & opencode @options; $code=$LASTEXITCODE }
    if ($code -ne 0) { throw "OpenCode exited with code $code" }
} finally { $env:OPENCODE_CONFIG = $previous;$env:OPENCODE_CONFIG_CONTENT=$previousInline }
