#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('whas-check-tests-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $fixture 'source'
$target = Join-Path $fixture 'must-not-exist'
$pathBefore = [Environment]::GetEnvironmentVariable('Path','User')
$policiesBefore = Get-ExecutionPolicy -List | ConvertTo-Json -Compress
function Invoke-Check {
    param([string]$Options, [string]$Expected, [int]$ExitCode = 0)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path $PSHOME 'powershell.exe'
    $start.Arguments = '-NoProfile -File "' + (Join-Path $source 'install.ps1') + '" -Check -InstallPath "' + $target + '" ' + $Options
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.RedirectStandardInput = $true
    $process = [Diagnostics.Process]::Start($start)
    try {
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Check prompted or timed out' }
        $output = $stdout.Result + $stderr.Result
        if ($process.ExitCode -ne $ExitCode -or $output -notmatch $Expected) { throw "Unexpected check result: $output" }
        if ($output -match 'Select components to install|Continue with installation|Installation completed') { throw 'Check entered installation flow' }
        if (Test-Path -LiteralPath $target) { throw 'Check created installation directory' }
    } finally { $process.Dispose() }
}
try {
    $files = @(& git -c "safe.directory=$repo" -C $repo ls-files)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate source fixture files' }
    foreach ($relative in @($files | Where-Object { $_ -in @('install.ps1','uninstall.ps1') -or $_ -match '^(scripts|config|tts)/' })) {
        $destination = Join-Path $source $relative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
        Copy-Item -LiteralPath (Join-Path $repo $relative) -Destination $destination
    }
    # Fail immediately if any installation helper is called.
    foreach ($relative in @('scripts/setup-agents.ps1','scripts/install-agent-commands.ps1','tts/install-tts.ps1')) {
        [IO.File]::WriteAllText((Join-Path $source $relative), "throw 'Installation helper must not run during check'")
    }
    $defaultsPath = Join-Path $source 'config/defaults.json'
    $defaults = Get-Content -LiteralPath $defaultsPath -Raw | ConvertFrom-Json
    $defaults.agents.cloud.enabled = $false
    $defaults.agents.local.enabled = $false
    $defaults.tts.enabled = $false
    [IO.File]::WriteAllText($defaultsPath, ($defaults | ConvertTo-Json -Depth 20))
    $checker = Join-Path $source 'scripts/check-prerequisites.ps1'
    [IO.File]::WriteAllText($checker, @"
param([switch]`$Cloud,[switch]`$Local,[switch]`$Voice,[string]`$StrategyManifestJson)
`$id = if (`$StrategyManifestJson) { (`$StrategyManifestJson | ConvertFrom-Json).id } else { 'none' }
Write-Host "CHECK Cloud=`$Cloud Local=`$Local Voice=`$Voice Engine=`$id"
exit 0
"@)
    Invoke-Check '' 'CHECK Cloud=True Local=True Voice=True Engine=chatterbox-turbo'
    Invoke-Check '-Cloud' 'CHECK Cloud=True Local=False Voice=False Engine=none'
    Invoke-Check '-Local' 'CHECK Cloud=False Local=True Voice=False Engine=none'
    Invoke-Check '-Voice -TtsEngine piper-tts' 'CHECK Cloud=False Local=False Voice=True Engine=piper-tts'
    Invoke-Check '-Voice -TtsEngine piper-tts,f5-tts' '(?s)Engine=piper-tts.*Engine=f5-tts'
    Invoke-Check '-Voice -TtsEngine missing-engine' 'Installer error:' 1
    Invoke-Check '-Cloud -TtsEngine piper-tts' '-TtsEngine requires -Voice' 1
    [IO.File]::WriteAllText($checker, "Write-Host 'MISSING FIXTURE PREREQUISITE'; exit 1")
    Invoke-Check '-Cloud' 'Required prerequisites are missing' 1
    if ([Environment]::GetEnvironmentVariable('Path','User') -cne $pathBefore) { throw 'Saved PATH changed' }
    if ((Get-ExecutionPolicy -List | ConvertTo-Json -Compress) -cne $policiesBefore) { throw 'Saved policies changed' }
    Write-Host 'PASS: Read-only checks, default and explicit selection, engines and exit codes'
} finally {
    $absolute = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $absolute.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $absolute) -notmatch '^whas-check-tests-[a-f0-9]{32}$') { throw 'Unexpected cleanup target' }
    if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
