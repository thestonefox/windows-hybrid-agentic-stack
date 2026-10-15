#Requires -Version 5.1

# Dot-source this file to manage profile registration. Loading it alone
# does not change the profile, execution policy, or installed software.

function Read-StackProfileFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        # ReadAllText detects Unicode BOMs. For BOM-less files, reject
        # invalid UTF-8 rather than silently replacing unrelated text.
        return [System.IO.File]::ReadAllText(
            $Path, (New-Object System.Text.UTF8Encoding($false, $true))
        )
    }
    catch [System.Text.DecoderFallbackException] {
        # Windows PowerShell 5.1 profiles may use the legacy ANSI code page.
        $codePage = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage
        return [System.IO.File]::ReadAllText(
            $Path, [System.Text.Encoding]::GetEncoding($codePage)
        )
    }
}

function Write-StackProfileFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    if (Test-Path -LiteralPath $Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Profile registration path is not a file: $Path"
        }
        if ((Read-StackProfileFile -Path $Path) -ceq $Content) {
            return
        }
        $backup = "$Path.bak.$([guid]::NewGuid().ToString('N'))"
        Copy-Item -LiteralPath $Path -Destination $backup -ErrorAction Stop
        Write-Host "Registration backup: $backup"
    }
    else {
        $directory = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop |
                Out-Null
        }
    }

    # A BOM lets Windows PowerShell 5.1 read non-ASCII custom paths and
    # existing profile text correctly, independently of the system code page.
    [System.IO.File]::WriteAllText(
        $Path, $Content, (New-Object System.Text.UTF8Encoding($true))
    )
    Write-Host "Updated registration: $Path"
}

function Get-StackProfileContent {
    param([AllowEmptyString()][string]$Content)

    $loader = @'
# BEGIN WINDOWS HYBRID AGENTIC STACK
if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $whasProfileFile = Join-Path $env:LOCALAPPDATA 'WindowsHybridAgenticStack\profile.ps1'
    try {
        if (Test-Path -LiteralPath $whasProfileFile -PathType Leaf) {
            . $whasProfileFile
        }
    }
    finally {
        Remove-Variable whasProfileFile -ErrorAction SilentlyContinue
    }
}
# END WINDOWS HYBRID AGENTIC STACK
'@

    # Match complete marker lines: agent markers are prefixes of TTS
    # markers, so substring matching cannot safely distinguish them.
    $markers = [regex]::Matches($Content,
        '(?m)^[\t ]*# (?<edge>BEGIN|END) WINDOWS HYBRID AGENTIC STACK(?<tts> TTS)?[\t ]*(?=\r?$)')
    $ranges = @()
    $openMarker = $null
    $seen = @{}
    foreach ($marker in $markers) {
        $kind = if ($marker.Groups['tts'].Success) { 'tts' } else { 'agent' }
        if ($marker.Groups['edge'].Value -eq 'BEGIN') {
            if ($null -ne $openMarker -or $seen.ContainsKey($kind)) {
                throw 'PowerShell profile contains duplicate or nested stack loader markers.'
            }
            $openMarker = $marker
            $seen[$kind] = $true
        }
        else {
            if ($null -eq $openMarker -or
                $openMarker.Groups['tts'].Success -ne $marker.Groups['tts'].Success) {
                throw 'PowerShell profile stack loader markers are incomplete or out of order.'
            }
            $ranges += [pscustomobject]@{
                Start = $openMarker.Index
                Length = $marker.Index + $marker.Length - $openMarker.Index
            }
            $openMarker = $null
        }
    }
    if ($null -ne $openMarker) {
        throw 'PowerShell profile contains an incomplete stack loader.'
    }

    $newline = if ($Content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $loader = ($loader -replace "`r`n", "`n") -replace "`n", $newline
    if ($ranges.Count -eq 0) {
        $separator = if ($Content.Length -gt 0 -and -not $Content.EndsWith("`n")) {
            $newline
        }
        else { '' }
        return $Content + $separator + $loader + $newline
    }

    # Replace the first managed block, remove the other, and preserve all
    # text outside the marked blocks, including the original line endings.
    for ($i = $ranges.Count - 1; $i -ge 0; $i--) {
        $range = $ranges[$i]
        $replacement = if ($i -eq 0) { $loader } else { '' }
        $Content = $Content.Remove($range.Start, $range.Length).
            Insert($range.Start, $replacement)
    }
    return $Content
}

function Install-StackProfileLoader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallPath,
        [string]$ProfilePath = $PROFILE.CurrentUserCurrentHost,
        [string]$LocalAppDataPath = $env:LOCALAPPDATA
    )

    foreach ($value in @($InstallPath, $ProfilePath, $LocalAppDataPath)) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw 'Installation, profile and local application data paths must not be empty.'
        }
    }
    $root = [Environment]::ExpandEnvironmentVariables($InstallPath)
    if ($root -match '^\$HOME(?=[\\/]|$)') {
        $root = $HOME + $root.Substring(5)
    }
    $root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($root)
    $localLoader = Join-Path $LocalAppDataPath 'WindowsHybridAgenticStack\profile.ps1'

    $existing = ''
    if (Test-Path -LiteralPath $ProfilePath) {
        if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
            throw "PowerShell profile path is not a file: $ProfilePath"
        }
        $existing = Read-StackProfileFile -Path $ProfilePath
    }
    # Validate markers before writing either file.
    $updated = Get-StackProfileContent -Content $existing

    $runtime = @'
# Windows Hybrid Agentic Stack machine-local registration.
$whasInstallRoot = '__INSTALL_ROOT__'
try {
    foreach ($whasRelativeScript in @('scripts\agent-commands.ps1', 'tts\tts.ps1')) {
        $whasCommandFile = Join-Path $whasInstallRoot $whasRelativeScript
        if (Test-Path -LiteralPath $whasCommandFile -PathType Leaf) {
            . $whasCommandFile -InstallPath $whasInstallRoot
        }
    }
}
finally {
    Remove-Variable whasInstallRoot, whasRelativeScript, whasCommandFile -ErrorAction SilentlyContinue
}
'@
    $runtime = $runtime.Replace('__INSTALL_ROOT__', $root.Replace("'", "''"))
    Write-StackProfileFile -Path $localLoader -Content $runtime
    Write-StackProfileFile -Path $ProfilePath -Content $updated
}

function Disable-StackProfileLoader {
    [CmdletBinding()]
    param([string]$LocalAppDataPath = $env:LOCALAPPDATA)

    if ([string]::IsNullOrWhiteSpace($LocalAppDataPath)) {
        throw 'Local application data path must not be empty.'
    }
    $localLoader = Join-Path $LocalAppDataPath 'WindowsHybridAgenticStack\profile.ps1'
    if (Test-Path -LiteralPath $localLoader) {
        # Leave the synced bootstrap intact for installations on other PCs.
        Write-StackProfileFile -Path $localLoader -Content '# Stack command loading is disabled on this PC.'
    }
}
