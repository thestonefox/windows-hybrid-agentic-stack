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
function Assert-True {
    param([bool]$Value,[string]$Message)
    if (-not $Value) { throw "FAIL: $Message" }
}
function Quote-Literal {
    param([string]$Text)
    return "'" + $Text.Replace("'", "''") + "'"
}
function Invoke-RestrictedSetup {
    param([string[]]$SetupArguments, [int]$ExpectedExit = 0, [switch]$FailPrerequisites)
    $arguments = @($SetupArguments | ForEach-Object { Quote-Literal $_ }) -join ','
    $code = @"
`$ErrorActionPreference='Stop'
if ((Get-ExecutionPolicy) -ne 'Restricted') { throw 'Test child is not Restricted' }
`$env:WHAS_TEST_PREREQUISITE_FAIL='$([int][bool]$FailPrerequisites)'
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
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
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
    foreach ($relative in @('scripts\command-host.cs','scripts\setup-host.cs','scripts\build-setup.ps1',
        'scripts\setup-preview.ps1','scripts\configuration.ps1','config\defaults.json')) {
        $destination = Join-Path $source $relative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
        Copy-Item -LiteralPath (Join-Path $repo $relative) -Destination $destination
    }
    [IO.File]::WriteAllText((Join-Path $source 'scripts\check-prerequisites.ps1'), @'
param([switch]$Cloud,[switch]$Local,[switch]$Voice)
Write-Host "CHECK Cloud=$Cloud Local=$Local Voice=$Voice POLICY=$(Get-ExecutionPolicy)"
'CHECK PIPELINE OUTPUT'
if ($env:WHAS_TEST_PREREQUISITE_FAIL -eq '1') { exit 1 }
exit 0
'@)
    $portable = Join-Path $fixture ("Portable A's [setup] " + [char]0xe9)
    [IO.Directory]::CreateDirectory($portable) | Out-Null
    $portableExe = Join-Path $portable 'whas-setup-preview.exe'
    & (Join-Path $source 'scripts\build-setup.ps1') -OutputPath $portableExe
    Assert-True (Test-Path -LiteralPath $portableExe) 'Prototype built'
    $rejected = $false
    try { & (Join-Path $source 'scripts\build-setup.ps1') -OutputPath $portableExe } catch { $rejected = $true }
    Assert-True $rejected 'Build refuses to replace existing output without Force'
    $output = Invoke-RestrictedSetup @('--help')
    Assert-True ($output.Contains('does not install components')) 'Standalone help identifies prototype scope'
    $output = Invoke-RestrictedSetup @()
    Assert-True ($output.Contains('Usage:')) 'No arguments show help'
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
    $null = Invoke-RestrictedSetup @('--install') -ExpectedExit 1
    Write-Host 'PASS: JSON override validation, missing values, incompatible actions and unsupported install rejected'
    $output = Invoke-RestrictedSetup @('--check','--local')
    Assert-True ($output.Contains('CHECK Cloud=False Local=True Voice=False POLICY=Restricted') -and $output.Contains('CHECK PIPELINE OUTPUT')) 'Embedded checker sees Restricted and forwards selection/output'
    $null = Invoke-RestrictedSetup @('--check','--voice') -ExpectedExit 1 -FailPrerequisites
    Write-Host 'PASS: Prerequisite success/failure exit codes and formatted pipeline output'
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
