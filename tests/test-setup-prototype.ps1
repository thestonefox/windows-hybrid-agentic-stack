#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts\installation-state.ps1')
$pathBefore = Get-StackRawUserPath | ConvertTo-Json -Compress
$policiesBefore = Get-ExecutionPolicy -List | ConvertTo-Json -Compress
$profileBefore = if (Test-Path -LiteralPath $PROFILE.CurrentUserCurrentHost) { (Get-FileHash -LiteralPath $PROFILE.CurrentUserCurrentHost).Hash } else { 'ABSENT' }
$defaultInstall = Join-Path $HOME 'AI\WindowsHybridAgenticStack'
$defaultRegistration = Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack'
$installBefore = Test-Path -LiteralPath $defaultInstall
$registrationBefore = Test-Path -LiteralPath $defaultRegistration
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('whas-setup-tests-' + [guid]::NewGuid().ToString('N'))
$fakeUser = Join-Path $fixture 'user'
function Assert-True {
    param([bool]$Value,[string]$Message)
    if (-not $Value) { throw "FAIL: $Message" }
}
function Quote-Literal {
    param([string]$Text)
    return "'" + $Text.Replace("'", "''") + "'"
}
function Invoke-RestrictedSetup {
    param([string[]]$SetupArguments, [int]$ExpectedExit = 0, [switch]$FailPrerequisites, [switch]$FailAgentSetup, [string]$InputText)
    $arguments = @($SetupArguments | ForEach-Object { Quote-Literal $_ }) -join ','
    $code = @"
`$ErrorActionPreference='Stop'
[Console]::InputEncoding=New-Object Text.UTF8Encoding(`$false)
if ((Get-ExecutionPolicy) -ne 'Restricted') { throw 'Test child is not Restricted' }
`$env:WHAS_TEST_PREREQUISITE_FAIL='$([int][bool]$FailPrerequisites)'
`$env:WHAS_TEST_AGENT_FAIL='$([int][bool]$FailAgentSetup)'
`$env:USERPROFILE=$(Quote-Literal $fakeUser)
`$arguments=@($arguments)
`$ErrorActionPreference='Continue'
& $(Quote-Literal $portableExe) @arguments
`$actual=`$LASTEXITCODE
`$ErrorActionPreference='Stop'
if ((Get-ExecutionPolicy) -ne 'Restricted') { throw 'Caller policy changed' }
exit `$actual
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path $PSHOME 'powershell.exe'
    $start.Arguments = '-NoLogo -NoProfile -OutputFormat Text -ExecutionPolicy Restricted -EncodedCommand ' + $encoded
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.RedirectStandardInput = $true
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if ($null -ne $InputText) {
            $inputBytes=(New-Object Text.UTF8Encoding($false)).GetBytes($InputText)
            $process.StandardInput.BaseStream.Write($inputBytes,0,$inputBytes.Length)
        }
        $process.StandardInput.BaseStream.Close()
        if (-not $process.WaitForExit(60000)) { $process.Kill(); throw 'Restricted test child timed out.' }
        $output = $stdout.Result + $stderr.Result
        if ($process.ExitCode -ne $ExpectedExit) { Write-Host $output; throw "FAIL: Child exit $($process.ExitCode), expected $ExpectedExit" }
        return $output
    }
    finally { $process.Dispose() }
}
try {
    # Build a disposable source fixture with a deterministic prerequisite checker.
    $source = Join-Path $fixture 'source'
    foreach ($relative in @('install.ps1','uninstall.ps1','scripts\command-host.cs','scripts\setup-host.cs','scripts\setup-runtime.cs','scripts\build-setup.ps1',
        'scripts\setup-preview.ps1','scripts\configuration.ps1','scripts\gui-host.cs','scripts\gui-maintenance.ps1','scripts\fluent-gui.cs','scripts\gui-theme.xaml','scripts\build-gui.ps1','scripts\build-setup.ps1','scripts\setup-host.cs','scripts\setup-runtime.cs','scripts\agent-strategies.ps1','scripts\whas.ps1','agents\strategies\opencode\manifest.json','agents\strategies\opencode\adapter.ps1','config\defaults.json','config\AGENTS.md','scripts\script-invocation.ps1',
        'scripts\setup-agents.ps1','scripts\install-agent-commands.ps1','scripts\command-registration.ps1','scripts\profile-loader.ps1',
        'scripts\config.ps1','scripts\agent-commands.ps1','scripts\installation-state.ps1','scripts\uninstall.ps1',
        'tts\install-tts.ps1','tts\tts.ps1','tts\tts_service.py', 'tts\strategy-management.ps1', 'tts\engine-management.ps1', 'tts\strategy.schema.json', 'tts\strategies\chatterbox-turbo\manifest.json', 'tts\strategies\chatterbox-turbo\install.ps1', 'tts\strategies\chatterbox-turbo\uninstall.ps1', 'tts\strategies\chatterbox-turbo\backend.py', 'tts\strategies\chatterbox-turbo\requirements.txt', 'tts\strategies\chatterbox-turbo\prepare_model.py')) {
        $destination = Join-Path $source $relative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
        Copy-Item -LiteralPath (Join-Path $repo $relative) -Destination $destination
    }
    # Native component orchestration must not depend on a real host Ollama API.
    Add-Content -LiteralPath (Join-Path $source 'scripts\installation-state.ps1') -Value "`r`nfunction Get-StackOllamaModels { return @() }"
    [IO.File]::WriteAllText((Join-Path $source 'scripts\check-prerequisites.ps1'), @'
param([switch]$Cloud,[switch]$Local,[switch]$Voice,[string]$StrategyManifestJson)
Write-Error 'Expected optional discovery probe' -ErrorAction SilentlyContinue
Write-Host "CHECK Cloud=$Cloud Local=$Local Voice=$Voice POLICY=$(Get-ExecutionPolicy)"
'CHECK PIPELINE OUTPUT'
if ($env:WHAS_TEST_PREREQUISITE_FAIL -eq '1') { exit 1 }
exit 0
'@)
    [IO.File]::WriteAllText((Join-Path $source 'scripts\setup-agents.ps1'), @'
param([switch]$Cloud,[switch]$Local,[string]$InstallPath,[string]$CloudModel,[string]$LocalModel,[int]$LocalContextSize)
if ($env:WHAS_TEST_AGENT_FAIL -eq '1') { exit 2 }
if (-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\AGENTS.md'))) { throw 'Bundled script lost its source path' }
[IO.Directory]::CreateDirectory($InstallPath) | Out-Null
[IO.File]::WriteAllText((Join-Path $InstallPath 'opencode.json'), (@{model=$CloudModel}|ConvertTo-Json))
[IO.File]::WriteAllText((Join-Path $InstallPath 'AGENTS.md'), 'fixture instructions')
exit 0
'@)
    [IO.File]::WriteAllText((Join-Path $source 'tts\install-tts.ps1'), @'
param([string]$InstallPath,[string]$Device,[string]$TtsEngine)
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'tts_service.py'))) { throw 'Missing bundled speech service' }
[IO.Directory]::CreateDirectory((Join-Path $InstallPath 'tts')) | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'tts.ps1') -Destination (Join-Path $InstallPath 'tts\tts.ps1')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'tts_service.py') -Destination (Join-Path $InstallPath 'tts\tts_service.py')
Write-Host "VOICE FIXTURE Device=$Device"
exit 0
'@)
    $portable = Join-Path $fixture ("Portable A's [setup] " + [char]0xe9)
    [IO.Directory]::CreateDirectory($portable) | Out-Null
    $portableExe = Join-Path $portable 'whas-setup-preview.exe'
    & (Join-Path $source 'scripts\build-setup.ps1') -OutputPath $portableExe
    Assert-True (Test-Path -LiteralPath $portableExe) 'Prototype built'
    # Exercise the actual WinExe backend with pipes and no console handle.
    $graphicalExe=Join-Path $portable 'whas-gui.exe'
    & (Join-Path $source 'scripts\build-setup.ps1') -Graphical -OutputPath $graphicalExe
    foreach($fails in @('0','1')) {
        $checkStart=New-Object Diagnostics.ProcessStartInfo
        $checkStart.FileName=$graphicalExe; $checkStart.Arguments='--check --local'
        $checkStart.UseShellExecute=$false; $checkStart.CreateNoWindow=$true
        $checkStart.RedirectStandardOutput=$true; $checkStart.RedirectStandardError=$true
        $checkStart.StandardOutputEncoding=[Text.Encoding]::UTF8; $checkStart.StandardErrorEncoding=[Text.Encoding]::UTF8
        $checkStart.EnvironmentVariables['WHAS_PROGRESS_EVENTS']='1'
        $checkStart.EnvironmentVariables['WHAS_TEST_PREREQUISITE_FAIL']=$fails
        $checkProcess=[Diagnostics.Process]::Start($checkStart)
        try {
            $stdout=$checkProcess.StandardOutput.ReadToEndAsync(); $stderr=$checkProcess.StandardError.ReadToEndAsync()
            if(-not $checkProcess.WaitForExit(60000)) { $checkProcess.Kill(); throw 'Graphical prerequisite check timed out' }
            Assert-True ($checkProcess.ExitCode -eq [int]$fails -and $stdout.Result.Contains('CHECK PIPELINE OUTPUT') -and -not $stderr.Result.Contains('handle is invalid')) 'WinExe prerequisite check returns results and success/failure without a console'
        } finally { $checkProcess.Dispose() }
    }
    $fingerprintBefore=(& (Join-Path $source 'scripts/build-setup.ps1') -Fingerprint -Force|Out-String).Trim()
    $inputPath=Join-Path $source 'install.ps1'
    $inputBytes=[IO.File]::ReadAllBytes($inputPath)
    try {
        $inputText=[Text.Encoding]::UTF8.GetString($inputBytes).Replace("`r`n","`n")
        [IO.File]::WriteAllBytes($inputPath,[Text.Encoding]::UTF8.GetBytes($inputText))
        $lf=(& (Join-Path $source 'scripts/build-setup.ps1') -Fingerprint -Force|Out-String).Trim()
        [IO.File]::WriteAllBytes($inputPath,[Text.Encoding]::UTF8.GetBytes($inputText.Replace("`n","`r`n")))
        $crlf=(& (Join-Path $source 'scripts/build-setup.ps1') -Fingerprint -Force|Out-String).Trim()
        Assert-True ($lf -ceq $crlf -and $lf -ceq $fingerprintBefore) 'Source freshness accepts LF ZIPs and CRLF Windows clones'
    } finally { [IO.File]::WriteAllBytes($inputPath,$inputBytes) }
    $rejected = $false
    try { & (Join-Path $source 'scripts\build-setup.ps1') -OutputPath $portableExe } catch { $rejected = $true }
    Assert-True $rejected 'Build refuses to replace existing output without Force'
    $output = Invoke-RestrictedSetup @('--help')
    Assert-True ($output.Contains('Install selected cloud, local and voice components')) 'Standalone help identifies installation scope'
    $render = Join-Path $fixture 'setup-render.png'
    $output = Invoke-RestrictedSetup @('--gui-render',$render)
    Assert-True ((Test-Path -LiteralPath $render) -and (Get-Item -LiteralPath $render).Length -gt 1000) 'Graphical setup renders under Restricted'
    # Poison loose scripts/defaults next to the EXE: only compiled assets may run.
    [IO.Directory]::CreateDirectory((Join-Path $portable 'scripts')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $portable 'config')) | Out-Null
    foreach ($name in @('configuration.ps1','setup-preview.ps1','check-prerequisites.ps1')) {
        [IO.File]::WriteAllText((Join-Path $portable ('scripts\' + $name)), "throw 'LOOSE SCRIPT RAN'")
    }
    [IO.File]::WriteAllText((Join-Path $portable 'config\defaults.json'), 'not json')
    $target = Join-Path $fixture 'literal & [target]; $(throw INJECTED)'
    $output = Invoke-RestrictedSetup @('--plan','--cloud','--install-path',$target)
    Assert-True ($output.Contains($target) -and $output.Contains('Cloud agents: True') -and $output.Contains('Voice output: False')) 'Embedded plan preserves literal paths and explicit selection'
    Assert-True (-not (Test-Path -LiteralPath $target)) 'Preview does not create target'
    $output = Invoke-RestrictedSetup @('--plan')
    Assert-True ($output.Contains('Local agents: True') -and $output.Contains('Voice output: True')) 'Bundled defaults used without loose files'
    Write-Host 'PASS: Portable embedded assets, Restricted execution, default/explicit selection and literal paths'
    $overrides = Join-Path $fixture 'my config [custom].json'
    [IO.File]::WriteAllText($overrides, '{"agents":{"cloud":{"model":"openai/test-preview-model"},"local":{"enabled":false}},"tts":{"enabled":false}}')
    $output = Invoke-RestrictedSetup @('--plan','--config',$overrides)
    Assert-True ($output.Contains('openai/test-preview-model') -and $output.Contains('Local agents: False')) 'Explicit JSON overrides merged and validated'
    [IO.File]::WriteAllText($overrides, '{"unknownSetting":true}')
    $output = Invoke-RestrictedSetup @('--plan','--config',$overrides) -ExpectedExit 1
    Assert-True ($output.Contains('Unknown configuration setting')) 'Unknown configuration rejected'
    [IO.File]::WriteAllText($overrides, 'invalid json')
    $null = Invoke-RestrictedSetup @('--plan','--config',$overrides) -ExpectedExit 1
    $null = Invoke-RestrictedSetup @('--install-path') -ExpectedExit 1
    $null = Invoke-RestrictedSetup @('--plan','--check') -ExpectedExit 1
    $null = Invoke-RestrictedSetup @('--install','--remove-managed-models') -ExpectedExit 1
    $null = Invoke-RestrictedSetup @('--install','--retain-managed-models') -ExpectedExit 1
    $null = Invoke-RestrictedSetup @('--uninstall','--retain-managed-models','--remove-managed-models') -ExpectedExit 1
    Write-Host 'PASS: JSON override validation, missing values, incompatible actions and invalid model-removal action rejected'
    $output = Invoke-RestrictedSetup @('--check','--local')
    Assert-True ($output.Contains('CHECK Cloud=False Local=True Voice=False POLICY=Restricted') -and $output.Contains('CHECK PIPELINE OUTPUT')) 'Embedded checker sees Restricted and forwards selection/output'
    $null = Invoke-RestrictedSetup @('--check','--voice') -ExpectedExit 1 -FailPrerequisites
    Write-Host 'PASS: Prerequisite success/failure exit codes and formatted pipeline output'
    $target = Join-Path $fixture ("Cloud A's [installed] " + [char]0xe9)
    $null = Invoke-RestrictedSetup @('--install','--cloud','--install-path',$target,'--no-path') -InputText "n`n"
    Assert-True (-not (Test-Path -LiteralPath $target)) 'Declining installation creates no target'
    $null = Invoke-RestrictedSetup @('--install','--cloud','--install-path',$target,'--no-path','--yes') -FailPrerequisites -ExpectedExit 1
    Assert-True (-not (Test-Path -LiteralPath $target)) 'Failed prerequisites leave target absent'
    [IO.File]::WriteAllText($overrides, '{"agents":{"cloud":{"model":"openai/native-fixture"}}}')
    $output = Invoke-RestrictedSetup @('--install','--cloud','--config',$overrides,'--install-path',$target,'--no-path','--yes')
    $ownershipPath = Join-Path $target '.whas-installation.json'
    $ownership = Get-Content -LiteralPath $ownershipPath -Raw | ConvertFrom-Json
    Assert-True ($ownership.Status -eq 'Installed' -and @($ownership.Files.Path) -contains 'scripts/script-invocation.ps1') 'Native nested scripts finish and track runtime dispatcher'
    $configuration = Get-Content -LiteralPath (Join-Path $target 'opencode.json') -Raw | ConvertFrom-Json
    Assert-True ($configuration.model -ceq 'openai/native-fixture') 'Native installation applies explicit config overrides'
    Assert-True (Test-Path -LiteralPath (Join-Path $fakeUser '.windows-hybrid-agentic-stack\bin\agent.exe')) 'Native installation registers real executable launchers in isolated user folder'
    $hash = (Get-FileHash -LiteralPath $ownershipPath).Hash
    $start=New-Object Diagnostics.ProcessStartInfo
    Assert-True ((Test-Path -LiteralPath (Join-Path $target 'whas-gui.exe')) -and -not (Test-Path -LiteralPath (Join-Path $target 'whas-setup.exe'))) 'Single self-contained graphical application installed'
    $commandStart=New-Object Diagnostics.ProcessStartInfo
    $commandStart.FileName=Join-Path $fakeUser '.windows-hybrid-agentic-stack\bin\whas.exe'; $commandStart.Arguments='--help'
    $commandStart.UseShellExecute=$false; $commandStart.CreateNoWindow=$true
    $commandStart.RedirectStandardOutput=$true; $commandStart.RedirectStandardError=$true
    $commandStart.EnvironmentVariables['WHAS_PROGRESS_EVENTS']='1'
    $commandProcess=[Diagnostics.Process]::Start($commandStart)
    try {
        $commandOut=$commandProcess.StandardOutput.ReadToEndAsync(); $commandErr=$commandProcess.StandardError.ReadToEndAsync()
        if(-not $commandProcess.WaitForExit(60000)) { $commandProcess.Kill(); throw 'Graphical command child timed out' }
        Assert-True ($commandProcess.ExitCode -eq 0 -and $commandOut.Result -match 'whas' -and $commandErr.Result -notmatch 'handle is invalid') 'Installed command supports GUI progress pipes without a console'
    } finally { $commandProcess.Dispose() }
    $start.FileName=Join-Path $target 'whas-gui.exe'; $start.Arguments='--uninstall --apply --yes'
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    $self=[Diagnostics.Process]::Start($start)
    try { $text=$self.StandardError.ReadToEnd();$self.WaitForExit();Assert-True ($self.ExitCode -eq 1 -and $text -like '*outside the installation*' -and (Get-FileHash -LiteralPath $ownershipPath).Hash -ceq $hash) 'Console self-uninstall refuses locked-image removal before making changes' } finally { $self.Dispose() }
    $null = Invoke-RestrictedSetup @('--uninstall','--install-path',$target,'--no-path')
    Assert-True ((Get-FileHash -LiteralPath $ownershipPath).Hash -ceq $hash) 'Native uninstall preview is read-only'
    $null = Invoke-RestrictedSetup @('--uninstall','--install-path',$target,'--no-path','--apply','--yes')
    Assert-True (-not (Test-Path -LiteralPath $target) -and -not (Test-Path -LiteralPath (Join-Path $fakeUser '.windows-hybrid-agentic-stack'))) 'Native uninstall removes owned target and isolated registration under Restricted'
    Write-Host 'PASS: Cloud install/uninstall under Restricted, decline/failure safety, config overrides and ownership tracking'
    $interrupted = Join-Path $fixture 'interrupted'
    $null = Invoke-RestrictedSetup @('--install','--cloud','--install-path',$interrupted,'--no-path','--yes') -FailAgentSetup -ExpectedExit 1
    $ownership = Get-Content -LiteralPath (Join-Path $interrupted '.whas-installation.json') -Raw | ConvertFrom-Json
    Assert-True ($ownership.Status -eq 'Interrupted') 'Failed child setup propagates its exit status and records partial ownership'
    $null = Invoke-RestrictedSetup @('--uninstall','--install-path',$interrupted,'--no-path','--apply','--yes')
    Assert-True (-not (Test-Path -LiteralPath $interrupted)) 'Interrupted native installation can be removed'
    $protected = Join-Path $fixture 'git checkout'
    [IO.Directory]::CreateDirectory((Join-Path $protected '.git')) | Out-Null
    $null = Invoke-RestrictedSetup @('--install','--cloud','--install-path',$protected,'--no-path','--yes') -ExpectedExit 1
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $protected '.whas-installation.json'))) 'Native installer refuses a Git checkout before tracking writes'
    Write-Host 'PASS: Interrupted native install cleanup and Git checkout protection'
    foreach ($components in @(@('--core'),@('--local'),@('--voice'),@('--cloud','--local','--voice'))) {
        $componentTarget = Join-Path $fixture ('components-' + [guid]::NewGuid().ToString('N'))
        $output = Invoke-RestrictedSetup (@('--install','--install-path',$componentTarget,'--no-path','--yes') + $components)
        $expectedSelection = 'CHECK Cloud=' + [string]($components -contains '--cloud') + ' Local=' + [string]($components -contains '--local') + ' Voice=' + [string]($components -contains '--voice') + ' POLICY=Restricted'
        Assert-True ($output.Contains($expectedSelection)) 'Component switches reach nested prerequisite checker'
        $ownership = Get-Content -LiteralPath (Join-Path $componentTarget '.whas-installation.json') -Raw | ConvertFrom-Json
        Assert-True ($ownership.Status -eq 'Installed') 'Selected native components finalize ownership'
        if ($components -contains '--voice') {
            Assert-True ($output.Contains('VOICE FIXTURE Device=auto') -and (Test-Path -LiteralPath (Join-Path $componentTarget 'tts\tts_service.py'))) 'Native voice invokes bundled installer and preserves source paths'
        }
        $null = Invoke-RestrictedSetup @('--uninstall','--install-path',$componentTarget,'--no-path','--apply','--yes','--remove-managed-models')
        Assert-True (-not (Test-Path -LiteralPath $componentTarget)) 'Selected native components uninstall cleanly'
    }
    Write-Host 'PASS: Local-only, voice-only and full native component orchestration under Restricted (dependencies mocked)'
    Write-Host 'All setup prototype tests passed.'
}
finally {
    Assert-True ((Get-StackRawUserPath | ConvertTo-Json -Compress) -ceq $pathBefore) 'Persistent PATH unchanged'
    Assert-True ((Get-ExecutionPolicy -List | ConvertTo-Json -Compress) -ceq $policiesBefore) 'Execution policies unchanged'
    $profileAfter = if (Test-Path -LiteralPath $PROFILE.CurrentUserCurrentHost) { (Get-FileHash -LiteralPath $PROFILE.CurrentUserCurrentHost).Hash } else { 'ABSENT' }
    Assert-True ($profileAfter -ceq $profileBefore) 'User profile unchanged'
    Assert-True ((Test-Path -LiteralPath $defaultInstall) -eq $installBefore) 'Default installation state unchanged'
    Assert-True ((Test-Path -LiteralPath $defaultRegistration) -eq $registrationBefore) 'Default registration state unchanged'
    Write-Host "Retained prototype fixtures: $fixture"
}
