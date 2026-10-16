#Requires -Version 5.1
[CmdletBinding()]
param([string]$Python = 'python', [string]$LogDirectory)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess) { throw 'Run with 64-bit Windows PowerShell 5.1.' }
$repo = Split-Path -Parent $PSScriptRoot
if (-not $LogDirectory) { $LogDirectory = Join-Path ([IO.Path]::GetTempPath()) ('whas-test-logs-' + [guid]::NewGuid().ToString('N')) }
[IO.Directory]::CreateDirectory($LogDirectory) | Out-Null
$tests = @(Get-ChildItem -LiteralPath (Join-Path $repo 'tests') -Filter 'test-*.ps1' -File | Sort-Object Name)
$tests += @(Get-ChildItem -LiteralPath (Join-Path $repo 'tests') -Filter 'test-*.py' -File | Sort-Object Name)
foreach ($test in $tests) {
    Write-Host "Running $($test.Name)..."
    $start = New-Object Diagnostics.ProcessStartInfo
    if ($test.Extension -eq '.ps1') {
        $start.FileName = Join-Path $PSHOME 'powershell.exe'
        $start.Arguments = '-NoLogo -NoProfile -File "' + $test.FullName + '"'
    } else {
        $start.FileName = (Get-Command $Python -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        $start.Arguments = '-B "' + $test.FullName + '"'
    }
    $start.WorkingDirectory = $repo
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(600000)) { $process.Kill(); throw "Test timed out: $($test.Name)" }
        $output = $stdout.Result + $stderr.Result
        [IO.File]::WriteAllText((Join-Path $LogDirectory ($test.BaseName + '.log')), $output, (New-Object Text.UTF8Encoding($false)))
        if ($process.ExitCode -ne 0) {
            Write-Host (($output -split "`n" | Select-Object -Last 25) -join "`n")
            throw "Test failed: $($test.Name). Logs: $LogDirectory"
        }
        Write-Host "PASS: $($test.Name)"
        # Successful suites expose their generated fixture roots. Remove only
        # exact GUID-named children of TEMP, after rejecting any remaining links.
        foreach ($match in [regex]::Matches($output, '(?m)^Retained[^:\r\n]*:\s*([^\r\n]+)')) {
            $root = [IO.Path]::GetFullPath($match.Groups[1].Value.Trim())
            $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
            if (-not $root.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
                (Split-Path -Leaf $root) -notmatch '^whas-[a-z-]+-[a-f0-9]{32}$') { throw "Unexpected test fixture path: $root" }
            if (Test-Path -LiteralPath $root) {
                $pending = New-Object 'Collections.Generic.Stack[string]'
                $pending.Push($root)
                while ($pending.Count) {
                    $directory = $pending.Pop()
                    if ((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Fixture link retained for review.' }
                    foreach ($item in Get-ChildItem -LiteralPath $directory -Force) {
                        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Fixture link retained for review.' }
                        if ($item.PSIsContainer) { $pending.Push($item.FullName) }
                    }
                }
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }
    finally { $process.Dispose() }
}
Write-Host "All $($tests.Count) isolated suites passed. Logs: $LogDirectory"
