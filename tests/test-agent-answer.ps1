#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts/agent-commands.ps1')
function Assert-Equal {
    param($Actual,$Expected,[string]$Message)
    if ($Actual -cne $Expected) { throw "FAIL: $Message" }
}
$footer = '<system-reminder>Remember to use /help for assistance or report issues at https://github.com/anomalyco/opencode/issues</system-reminder>'
Assert-Equal (ConvertTo-AgentAnswer "Paris`n$footer" 'capital of France') 'Paris' 'Known leaked footer removed'
Assert-Equal (ConvertTo-AgentAnswer $footer 'capital of France') '' 'Reminder-only text is not an answer'
Assert-Equal (ConvertTo-AgentAnswer "Paris`r`n$footer`r`n" 'capital of France') 'Paris' 'CRLF and trailing whitespace handled'
Assert-Equal (ConvertTo-AgentAnswer "Paris`n$footer" 'Explain system-reminder') "Paris`n$footer" 'Requested reminder content preserved'
$literal = 'Example:' + "`n" + '```xml' + "`n" + $footer
Assert-Equal (ConvertTo-AgentAnswer $literal 'Show markup') $literal 'Fenced example preserved'
$unknown = 'Paris <system-reminder>some unrelated text</system-reminder>'
Assert-Equal (ConvertTo-AgentAnswer $unknown 'capital of France') $unknown 'Unknown or inline markup is not stripped blindly'
Assert-Equal (ConvertTo-AgentAnswer "Paris`nSee /help for assistance." 'capital of France') "Paris`nSee /help for assistance." 'Ordinary answer text preserved'
Write-Host 'PASS: Answer footer boundaries, literal examples and normal text'

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('whas-agent-answer-' + [guid]::NewGuid().ToString('N'))
$savedInline=$env:OPENCODE_CONFIG_CONTENT
try {
    $env:OPENCODE_CONFIG_CONTENT='{"model":"provider/cloud-default","provider":{"ollama":{"options":{"baseURL":"http://127.0.0.1:11434/v1"},"models":{"qwen3:8b":{"name":"My model","limit":{"context":16384}}}}},"agent":{"ps-read":{"permission":{"edit":"deny"}}}}'
    $inheritedInline=$env:OPENCODE_CONFIG_CONTENT
    $registered=Add-AgentLocalModelConfiguration 'ollama/qwen2.5:1.5b'|ConvertFrom-Json
    if($registered.provider.ollama.models.'qwen2.5:1.5b'.name -cne 'qwen2.5:1.5b' -or $registered.provider.ollama.models.'qwen3:8b'.name -cne 'My model' -or $registered.provider.ollama.models.'qwen3:8b'.limit.context -ne 16384 -or $registered.model -cne 'provider/cloud-default' -or $registered.agent.'ps-read'.permission.edit -cne 'deny'){throw 'Local model registration replaced unrelated model, provider or permission settings'}
    if($env:OPENCODE_CONFIG_CONTENT -cne $inheritedInline){throw 'Registration modified the parent environment'}
    $plain=Add-AgentConversationConfiguration|ConvertFrom-Json
    if($plain.agent.'whas-chat'.permission.'*' -cne 'deny' -or $plain.agent.'whas-chat'.permission.read -cne 'deny' -or $plain.agent.'whas-chat'.permission.bash -cne 'deny' -or $plain.agent.'ps-read'.permission.edit -cne 'deny' -or $plain.model -cne 'provider/cloud-default'){throw 'Plain chat did not deny tools while preserving unrelated inherited settings'}
    [IO.Directory]::CreateDirectory((Join-Path $fixture 'config')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $fixture 'scripts')) | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'config/defaults.json') -Destination (Join-Path $fixture 'config/defaults.json')
    Copy-Item -LiteralPath (Join-Path $repo 'scripts/configuration.ps1') -Destination (Join-Path $fixture 'scripts/configuration.ps1')
    [IO.File]::WriteAllText((Join-Path $fixture 'opencode.json'), '{}')
    . (Join-Path $repo 'scripts/agent-commands.ps1') -InstallPath $fixture
    $script:Spoken = $null
    function tts-say { param($Text,$Voice) $script:Spoken = $Text }
    function opencode {
        $script:ReceivedInline=$env:OPENCODE_CONFIG_CONTENT
        ConvertTo-Json -Compress -Depth 5 @{type='text';part=@{text="Paris`n$footer"}}
        ConvertTo-Json -Compress -Depth 5 @{type='text';part=@{text=$footer;synthetic=$true}}
        $global:LASTEXITCODE = 0
    }
    $printed = @(localagent -v 'capital of France') -join "`n"
    Assert-Equal $printed 'Paris' 'Printed final answer is clean'
    Assert-Equal $script:Spoken 'Paris' 'Speech receives the same clean answer'
    if($env:OPENCODE_CONFIG_CONTENT -cne $inheritedInline -or ($script:ReceivedInline|ConvertFrom-Json).provider.ollama.models.'qwen3:8b'.name -cne 'My model'){throw 'Wrapper did not preserve inherited model metadata or restore the parent environment'}
    $raw = @(localagent -v -l 'capital of France') -join "`n"
    $loggedText = @($raw -split "`n" | ForEach-Object { ($_ | ConvertFrom-Json).part.text })
    if ($loggedText -cnotcontains "Paris`n$footer") { throw 'FAIL: Full log must retain raw diagnostic events' }
    Assert-Equal $script:Spoken 'Paris' 'Speech stays clean with raw logging enabled'
    Write-Host 'PASS: Real wrapper display, speech extraction and raw diagnostic logging'
}
finally {
    $env:OPENCODE_CONFIG_CONTENT=$savedInline
    $absolute = [IO.Path]::GetFullPath($fixture)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $absolute.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $absolute) -notmatch '^whas-agent-answer-[a-f0-9]{32}$') { throw 'Unexpected fixture cleanup path' }
    if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
