#Requires -Version 5.1

# Dot-source this file to remove legacy stack profile blocks. Loading it alone
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

function Remove-StackProfileContent {
    param([AllowEmptyString()][string]$Content)


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

    if ($ranges.Count -eq 0) { return $Content }

    # Remove only complete managed blocks and preserve all
    # text outside the marked blocks, including the original line endings.
    for ($i = $ranges.Count - 1; $i -ge 0; $i--) {
        $range = $ranges[$i]
        $Content = $Content.Remove($range.Start, $range.Length)
    }
    return $Content
}

function Remove-StackLegacyProfileLoader {
    [CmdletBinding()]
    param([string]$ProfilePath = $PROFILE.CurrentUserCurrentHost)

    # Application-hosted runspaces do not load or define a console profile.
    if ([string]::IsNullOrWhiteSpace($ProfilePath)) { return }
    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) { return }
    $before = Read-StackProfileFile -Path $ProfilePath
    $after = Remove-StackProfileContent -Content $before
    if ($before -ceq $after) { return }
    if ([string]::IsNullOrWhiteSpace($after)) {
        $backup = "$ProfilePath.bak.$([guid]::NewGuid().ToString('N'))"
        Copy-Item -LiteralPath $ProfilePath -Destination $backup -ErrorAction Stop
        # Leaving an empty .ps1 would still trigger Restricted startup errors.
        Remove-Item -LiteralPath $ProfilePath -Force -ErrorAction Stop
        Write-Host "Removed empty legacy stack profile; backup: $backup"
    }
    else {
        Write-StackProfileFile -Path $ProfilePath -Content $after
        Write-Host 'Removed legacy stack profile blocks; unrelated code preserved.'
    }
}
