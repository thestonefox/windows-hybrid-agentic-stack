#Requires -Version 5.1

<#
.SYNOPSIS
    Install Windows Hybrid Agentic Stack PowerShell commands.

.DESCRIPTION
    Copies the agent command runtime into the installation folder.
    Registers a loader in the current user's PowerShell profile.

    Preserves existing files, backs up changes and avoids duplicate
    profile entries.

    Offers to enable CurrentUser RemoteSigned when a normal
    Windows PowerShell session would otherwise block the profile.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Copy-StackFile {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Required source file not found: $Source"
    }

    $directory = Split-Path -Parent $Destination

    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory `
            -Path $directory -Force | Out-Null
    }

    if (Test-Path -LiteralPath $Destination) {
        if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
            throw "Destination is not a file: $Destination"
        }

        $sourceHash = (
            Get-FileHash -LiteralPath $Source -Algorithm SHA256
        ).Hash

        $destinationHash = (
            Get-FileHash -LiteralPath $Destination -Algorithm SHA256
        ).Hash

        if ($sourceHash -eq $destinationHash) {
            Write-Host "Unchanged: $Destination"
            return
        }

        $backup = "$Destination.bak.$([guid]::NewGuid().ToString('N'))"

        Copy-Item `
            -LiteralPath $Destination `
            -Destination $backup `
            -ErrorAction Stop

        Write-Host "Backup created: $backup"
    }

    Copy-Item `
        -LiteralPath $Source `
        -Destination $Destination `
        -Force `
        -ErrorAction Stop

    Write-Host "Installed: $Destination"
}

function Confirm-Action {
    param([string]$Question)

    while ($true) {
        $answer = Read-Host "$Question [y/N]"

        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $false
        }

        switch ($answer.Trim().ToLowerInvariant()) {
            'y'   { return $true }
            'yes' { return $true }
            'n'   { return $false }
            'no'  { return $false }
            default {
                Write-Host 'Enter Y or N.' -ForegroundColor Yellow
            }
        }
    }
}

function Test-PolicyAllowsProfile {
    param([string]$Policy)

    return $Policy -in @(
        'RemoteSigned',
        'Unrestricted',
        'Bypass'
    )
}

function Configure-ProfileExecutionPolicy {
    Write-Host ''
    Write-Host 'Checking PowerShell profile execution policy...'

    $policies = Get-ExecutionPolicy -List

    $machinePolicy = [string](
        $policies |
            Where-Object Scope -eq 'MachinePolicy'
    ).ExecutionPolicy

    $userPolicy = [string](
        $policies |
            Where-Object Scope -eq 'UserPolicy'
    ).ExecutionPolicy

    $currentUserPolicy = [string](
        $policies |
            Where-Object Scope -eq 'CurrentUser'
    ).ExecutionPolicy

    $localMachinePolicy = [string](
        $policies |
            Where-Object Scope -eq 'LocalMachine'
    ).ExecutionPolicy

    # MachinePolicy and UserPolicy are enforced by Group Policy.
    # The installer must never attempt to override them.
    $enforcedPolicy = $null

    if ($machinePolicy -ne 'Undefined') {
        $enforcedPolicy = $machinePolicy
    }
    elseif ($userPolicy -ne 'Undefined') {
        $enforcedPolicy = $userPolicy
    }

    if ($null -ne $enforcedPolicy) {
        if (Test-PolicyAllowsProfile -Policy $enforcedPolicy) {
            Write-Host "Group Policy permits profiles: $enforcedPolicy"
        }
        else {
            Write-Warning (
                "Group Policy may block the PowerShell profile: " +
                $enforcedPolicy
            )

            Write-Host (
                'Contact your administrator to change the policy.'
            )
        }

        return
    }

    # Process scope is intentionally ignored here.
    # A process-level Bypass used by the installer does not
    # persist into an ordinary new PowerShell window.
    $persistentPolicy = if (
        $currentUserPolicy -ne 'Undefined'
    ) {
        $currentUserPolicy
    }
    elseif ($localMachinePolicy -ne 'Undefined') {
        $localMachinePolicy
    }
    else {
        'Restricted'
    }

    if (Test-PolicyAllowsProfile -Policy $persistentPolicy) {
        Write-Host "Profile execution permitted: $persistentPolicy" `
            -ForegroundColor Green
        return
    }

    Write-Host ''
    Write-Host "Persistent execution policy: $persistentPolicy"
    Write-Host ''
    Write-Host (
        'New PowerShell windows may not automatically load ' +
        'the agent commands.'
    )
    Write-Host ''
    Write-Host 'Recommended setting: RemoteSigned (CurrentUser)'
    Write-Host ''
    Write-Host (
        'This permits locally created scripts to run and ' +
        'requires downloaded scripts to be signed or unblocked.'
    )
    Write-Host (
        'It affects only your Windows user account, not ' +
        'the machine-wide execution policy.'
    )
    Write-Host ''

    if (-not (Confirm-Action `
        -Question 'Set CurrentUser execution policy to RemoteSigned?')) {
        Write-Warning (
            'Execution policy unchanged. The agent commands may ' +
            'not load automatically in new PowerShell windows.'
        )
        return
    }

    try {
        Set-ExecutionPolicy `
            -Scope CurrentUser `
            -ExecutionPolicy RemoteSigned `
            -Force `
            -ErrorAction Stop
    }
    catch {
        Write-Warning (
            'Unable to change CurrentUser execution policy: ' +
            $_.Exception.Message
        )
        return
    }

    $updatedPolicy = [string](
        Get-ExecutionPolicy -List |
            Where-Object Scope -eq 'CurrentUser'
    ).ExecutionPolicy

    if ($updatedPolicy -ne 'RemoteSigned') {
        Write-Warning (
            'CurrentUser execution policy could not be verified.'
        )
        return
    }

    Write-Host ''
    Write-Host 'CurrentUser execution policy is now RemoteSigned.' `
        -ForegroundColor Green

    Write-Host (
        'Open a new Windows PowerShell window to verify ' +
        'automatic profile loading.'
    )
}

try {
    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        throw 'InstallPath cannot be empty.'
    }

    $InstallPath = [Environment]::ExpandEnvironmentVariables(
        $InstallPath
    )

    $InstallPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
        $InstallPath
    )

    $runtimeScripts = Join-Path $InstallPath 'scripts'
    $runtimeConfig = Join-Path $InstallPath 'config'

    $files = @(
        @{
            Source = Join-Path $repoRoot 'scripts\agent-commands.ps1'
            Destination = Join-Path $runtimeScripts 'agent-commands.ps1'
        },
        @{
            Source = Join-Path $repoRoot 'scripts\config.ps1'
            Destination = Join-Path $runtimeScripts 'config.ps1'
        },
        @{
            Source = Join-Path $repoRoot 'config\defaults.json'
            Destination = Join-Path $runtimeConfig 'defaults.json'
        }
    )

    foreach ($file in $files) {
        if (-not (Test-Path -LiteralPath $file.Source -PathType Leaf)) {
            throw "Required source file not found: $($file.Source)"
        }
    }

    $userConfigSource = Join-Path $repoRoot 'config\config.json'
    $userConfigDestination = Join-Path $runtimeConfig 'config.json'

    foreach ($file in $files) {
        Copy-StackFile `
            -Source $file.Source `
            -Destination $file.Destination
    }

    if (Test-Path -LiteralPath $userConfigSource -PathType Leaf) {
        Copy-StackFile `
            -Source $userConfigSource `
            -Destination $userConfigDestination
    }

    $commandScript = Join-Path $runtimeScripts 'agent-commands.ps1'

    # Current Windows PowerShell user and host only.
    $profilePath = $PROFILE.CurrentUserCurrentHost
    $profileDirectory = Split-Path -Parent $profilePath

    if (-not (Test-Path -LiteralPath $profileDirectory)) {
        New-Item -ItemType Directory `
            -Path $profileDirectory -Force | Out-Null
    }

    if (Test-Path -LiteralPath $profilePath) {
        if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
            throw "PowerShell profile path is not a file: $profilePath"
        }

        $profileContent = Get-Content `
            -LiteralPath $profilePath -Raw
    }
    else {
        $profileContent = ''
    }

    $beginMarker = '# BEGIN WINDOWS HYBRID AGENTIC STACK'
    $endMarker = '# END WINDOWS HYBRID AGENTIC STACK'

    $hasBegin = $profileContent.Contains($beginMarker)
    $hasEnd = $profileContent.Contains($endMarker)

    if ($hasBegin -ne $hasEnd) {
        throw 'PowerShell profile contains an incomplete agent loader.'
    }

    $escapedCommands = $commandScript.Replace("'", "''")
    $escapedInstallPath = $InstallPath.Replace("'", "''")

    $loader = @"
$beginMarker
if (Test-Path -LiteralPath '$escapedCommands' -PathType Leaf) {
    . '$escapedCommands' -InstallPath '$escapedInstallPath'
}
$endMarker
"@

    if ($hasBegin) {
        $start = $profileContent.IndexOf($beginMarker)
        $finish = $profileContent.IndexOf(
            $endMarker,
            $start
        )

        if ($finish -lt 0) {
            throw 'PowerShell profile loader markers are invalid.'
        }

        $finish += $endMarker.Length

        $existingLoader = $profileContent.Substring(
            $start,
            $finish - $start
        )

        if ($existingLoader -cne $loader) {
            throw @"
Existing PowerShell profile loader differs.
Review the marked loader in:
$profilePath

No profile changes were made.
"@
        }

        Write-Host 'PowerShell profile loader already installed.'
    }
    else {
        if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
            $backup = "$profilePath.bak.$([guid]::NewGuid().ToString('N'))"

            Copy-Item `
                -LiteralPath $profilePath `
                -Destination $backup `
                -ErrorAction Stop

            Write-Host "Profile backup created: $backup"
        }

        $newContent = $profileContent.TrimEnd("`r", "`n")

        if ($newContent.Length -gt 0) {
            $newContent += "`r`n`r`n"
        }

        $newContent += $loader + "`r`n"

        $newContent | Set-Content `
            -LiteralPath $profilePath `
            -Encoding UTF8 `
            -ErrorAction Stop

        Write-Host "Updated PowerShell profile: $profilePath"
    }

    Configure-ProfileExecutionPolicy

    Write-Host ''
    Write-Host 'PowerShell agent commands installed.' `
        -ForegroundColor Green

    Write-Host 'Commands: agent, agentdo, localagent, localagentdo'
    Write-Host "Profile:  $profilePath"

    exit 0
}
catch {
    Write-Host ''
    Write-Host "Agent command installation error: $($_.Exception.Message)" `
        -ForegroundColor Red

    exit 1
}
