#Requires -Version 5.1
# Source scripts use normal file invocation. The native setup host supplies
# compiled application scripts in isolated runspaces, preserving child exit codes.
function Test-StackSetupHost {
    return ($null -ne ('WindowsHybridAgenticStack.SetupRuntime' -as [type]) -and
        [WindowsHybridAgenticStack.SetupRuntime]::IsHosting)
}
function Get-StackSetupScript {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (Test-StackSetupHost) { return [WindowsHybridAgenticStack.SetupRuntime]::LoadScript($Path) }
    if ($null -ne ('WindowsHybridAgenticStack.CommandHost' -as [type]) -and [WindowsHybridAgenticStack.CommandHost]::ManagedRoot) {
        $root = [WindowsHybridAgenticStack.CommandHost]::ManagedRoot
        $full = [IO.Path]::GetFullPath($Path)
        if (-not $full.StartsWith($root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Script is outside the installed application.' }
        $relative = $full.Substring($root.TrimEnd('\').Length + 1).Replace('\','/')
        $null = Resolve-StackOwnedPath $root $relative
        $ancestor = $full
        while ($ancestor -and $ancestor -ine $root) {
            if ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Application scripts must not use reparse points.' }
            $ancestor = Split-Path -Parent $ancestor
        }
        $state = Read-StackInstallationState $root -ReadOnly
        $hash = Get-StackFileSHA256 $full
        if (-not [WindowsHybridAgenticStack.CommandHost]::IsOwnedAsset($state,$relative,$hash)) { throw "Application script is unowned or changed: $relative" }
        $tokens = $null; $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($full), $full, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw 'Invalid installed application script.' }
        return $ast.GetScriptBlock()
    }
    return $Path
}
function Invoke-StackSetupScript {
    param([Parameter(Mandatory=$true)][string]$Path, [hashtable]$Arguments = @{})
    if (Test-StackSetupHost) {
        $result = [WindowsHybridAgenticStack.SetupRuntime]::InvokeScript($Path, $Arguments)
        $global:LASTEXITCODE = $result.ExitCode
        foreach ($item in $result.Output) { $item }
    }
    elseif ($null -ne ('WindowsHybridAgenticStack.CommandHost' -as [type]) -and [WindowsHybridAgenticStack.CommandHost]::ManagedRoot) {
        $result = [WindowsHybridAgenticStack.CommandHost]::InvokeManagedScript((Get-StackSetupScript $Path), $Arguments)
        $global:LASTEXITCODE = $result.ExitCode
        foreach ($item in $result.Output) { $item }
    }
    else {
        & $Path @Arguments
        $global:LASTEXITCODE = $LASTEXITCODE
    }
}

function Invoke-StackVerifiedHook {
    param([string]$Path,[string]$SHA256,[hashtable]$Arguments)
    if((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -cne $SHA256) { throw 'Strategy hook changed; execution refused.' }
    if(Test-StackSetupHost) {
        $result=[WindowsHybridAgenticStack.SetupRuntime]::InvokeVerifiedScript($Path,$SHA256,$Arguments)
        if($result.ExitCode -ne 0) { throw "Strategy hook failed (exit $($result.ExitCode))." }
        foreach($item in $result.Output) { $item }
    } elseif($null -ne ('WindowsHybridAgenticStack.CommandHost' -as [type]) -and [WindowsHybridAgenticStack.CommandHost]::ManagedRoot) {
        Invoke-StackSetupScript -Path $Path -Arguments $Arguments
        if($LASTEXITCODE -ne 0) { throw "Strategy hook failed (exit $LASTEXITCODE)." }
    } else {
        & $Path @Arguments
        if($LASTEXITCODE -ne 0) { throw "Strategy hook failed (exit $LASTEXITCODE)." }
    }
}
