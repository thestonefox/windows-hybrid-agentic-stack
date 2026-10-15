#Requires -Version 5.1
# Verify routing without provider credentials, inference, PATH changes or audio.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('whas-model-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $fixture 'config') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'config\defaults.json') -Destination (Join-Path $fixture 'config\defaults.json')
[IO.File]::WriteAllText((Join-Path $fixture 'opencode.json'), '{}')
. (Join-Path $repo 'scripts\configuration.ps1')
. (Join-Path $repo 'scripts\agent-commands.ps1') -InstallPath $fixture
function Assert-True([bool]$Value, [string]$Message) {
    if (-not $Value) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}
function Set-CloudConfig([string]$Json) {
    [IO.File]::WriteAllText((Join-Path $fixture 'config\config.json'), $Json)
}
function opencode {
    $script:CapturedArguments = @($args)
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'models') { 'ollama/whas-qwen3-8b-ctx16384'; return }
    if ($args[0] -eq 'agent') { 'ps-read'; 'ps-write'; return }
    '{"type":"text","part":{"text":"Test answer"}}'
}
function Invoke-RestMethod {
    param($Uri, $Method, $ContentType, $Body, $TimeoutSec, $ErrorAction)
    if ($Uri -like '*/tags') {
        return @{models=@(@{name='qwen3:8b'}, @{name='whas-qwen3-8b-ctx16384:latest'})}
    }
    return @{parameters='num_ctx 16384'}
}
$previousConfig = $env:OPENCODE_CONFIG
foreach ($kind in @('agent','agentdo')) {
    foreach ($flags in @('', '--log')) {
        $arguments = @('A prompt with spaces')
        if ($flags) { $arguments = @($flags) + $arguments }
        $null = Invoke-AgentStackTask -Kind $kind -Arguments $arguments
        Assert-True ($script:CapturedArguments -notcontains '--model') "$kind $flags inherits OpenCode selection"
        Assert-True ($script:CapturedArguments[-1] -ceq 'A prompt with spaces') 'Prompt remains one argument'
    }
}
$null = agent --model anthropic/test-model 'Test prompt'
Assert-True (($script:CapturedArguments -join '|') -like '*--model|anthropic/test-model*') 'Provider-qualified CLI override reaches OpenCode'
Set-CloudConfig '{"agents":{"cloud":{"model":"google/test-model"}}}'
$null = agent 'Test prompt'
Assert-True ($script:CapturedArguments -contains 'google/test-model') 'Explicit cloud configuration reaches OpenCode'
$null = agent --model anthropic/test-model 'Test prompt'
Assert-True ($script:CapturedArguments -contains 'anthropic/test-model') 'CLI override wins over saved configuration'
Set-CloudConfig '{"agents":{"cloud":{"provider":"openai","model":"legacy-model"}}}'
$null = agent 'Test prompt'
Assert-True ($script:CapturedArguments -contains 'openai/legacy-model') 'Existing provider plus short model remains supported'
Set-CloudConfig '{"agents":{"cloud":{"provider":"openai","model":null}}}'
$null = agent 'Test prompt'
Assert-True ($script:CapturedArguments -notcontains '--model') 'Null model opts out even with a saved provider'
$null = localagent 'Test prompt'
Assert-True ($script:CapturedArguments -contains 'ollama/qwen3:8b') 'Local command still selects configured Ollama model'
Set-CloudConfig '{"agents":{"cloud":{"model":"ambiguous-model"}}}'
$rejected = $false
try { $null = Get-StackConfiguration -Root $fixture } catch { $rejected = $true }
Assert-True $rejected 'Unqualified cloud model requires a provider'
Assert-True ($env:OPENCODE_CONFIG -ceq $previousConfig) 'Caller OpenCode configuration environment restored'

$setup = Join-Path $repo 'scripts\setup-agents.ps1'
foreach ($component in @('Cloud','Local','Both')) {
    $install = Join-Path $fixture $component
    $parameters = @{InstallPath=$install; Cloud=($component -ne 'Local'); Local=($component -ne 'Cloud')}
    & $setup @parameters
    Assert-True ($LASTEXITCODE -eq 0) "$component setup succeeds"
    $configPath = Join-Path $install 'opencode.json'
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    Assert-True ($null -eq $config.PSObject.Properties['model']) "$component setup leaves OpenCode default unspecified"
    $config | Add-Member -NotePropertyName model -NotePropertyValue 'anthropic/personal-model'
    [IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 30))
    & $setup @parameters
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    Assert-True ($LASTEXITCODE -eq 0 -and $config.model -ceq 'anthropic/personal-model') "$component reinstall preserves existing model selection"
}
& $setup -Cloud -InstallPath (Join-Path $fixture 'override') -CloudModel 'google/test-model'
$config = Get-Content -LiteralPath (Join-Path $fixture 'override\opencode.json') -Raw | ConvertFrom-Json
Assert-True ($LASTEXITCODE -eq 0 -and $config.model -ceq 'google/test-model') 'Setup retains explicit cloud override support'
Write-Host "Retained fixture: $fixture"
