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
    return $Path
}
function Invoke-StackSetupScript {
    param([Parameter(Mandatory=$true)][string]$Path, [hashtable]$Arguments = @{})
    if (Test-StackSetupHost) {
        $result = [WindowsHybridAgenticStack.SetupRuntime]::InvokeScript($Path, $Arguments)
        $global:LASTEXITCODE = $result.ExitCode
        foreach ($item in $result.Output) { $item }
    }
    else {
        & $Path @Arguments
        $global:LASTEXITCODE = $LASTEXITCODE
    }
}
