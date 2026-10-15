#Requires -Version 5.1

<#
.SYNOPSIS
    Install Windows Hybrid Agentic Stack PowerShell commands.

.DESCRIPTION
    Copies the agent command runtime into the installation folder.
    Registers native command launchers through the machine-local user PATH.

    Preserves existing files, backs up changes and avoids duplicate
    command registration.

    Does not create profiles or change execution policies.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallPath,
    [bool]$PersistPath = $true
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not ($null -ne ('WindowsHybridAgenticStack.SetupRuntime' -as [type]) -and [WindowsHybridAgenticStack.SetupRuntime]::IsHosting)) {
    . (Join-Path $PSScriptRoot 'script-invocation.ps1')
}

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

try {
    . (Get-StackSetupScript (Join-Path $PSScriptRoot 'command-registration.ps1'))

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
            Source = Join-Path $repoRoot 'scripts\configuration.ps1'
            Destination = Join-Path $runtimeScripts 'configuration.ps1'
        },
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
    Copy-StackFile -Source (Join-Path $PSScriptRoot 'script-invocation.ps1') -Destination (Join-Path $runtimeScripts 'script-invocation.ps1')

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

    Install-StackCommandRegistration -InstallPath $InstallPath -PersistPath $PersistPath
    . (Get-StackSetupScript (Join-Path $PSScriptRoot 'profile-loader.ps1'))
    Remove-StackLegacyProfileLoader
    Write-Host ''
    Write-Host 'PowerShell agent commands installed.' `
        -ForegroundColor Green

    Write-Host 'Commands: agent, agentdo, localagent, localagentdo'
    Write-Host "Location: $env:USERPROFILE\.windows-hybrid-agentic-stack\bin"

    exit 0
}
catch {
    Write-Host ''
    Write-Host "Agent command installation error: $($_.ScriptStackTrace) $($_.Exception.Message)" `
        -ForegroundColor Red

    exit 1
}
