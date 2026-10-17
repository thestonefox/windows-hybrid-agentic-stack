#Requires -Version 5.1
# Strategy discovery is data-only. Custom strategy hooks/backends are trusted code.
function Resolve-TtsPackagePath {
    param([string]$Root, [string]$Relative)
    if ([string]::IsNullOrWhiteSpace($Relative) -or $Relative -match '(^|[/\\])\.\.?([/\\]|$)|[:*?]' -or
        [IO.Path]::IsPathRooted($Relative)) { throw 'Invalid strategy-relative path.' }
    $full = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    if (-not $full.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Strategy path escapes its package.' }
    $check = $full
    while ($check) {
        if ((Test-Path -LiteralPath $check) -and ((Get-Item -LiteralPath $check -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Strategy paths must not contain reparse points.' }
        $check = Split-Path -Parent $check
    }
    return $full
}

function Read-TtsStrategy {
    param([string]$Directory)
    $manifestPath = Resolve-TtsPackagePath $Directory 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Strategy manifest is missing.' }
    if ((Get-Item -LiteralPath $manifestPath).Length -gt 64KB) { throw 'Strategy manifest is too large.' }
    $m = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $required = @('schemaVersion','apiVersion','id','version','name','description','platforms','devices','prerequisites','capabilities','entrypoints','files','license','models')
    if ($m -isnot [pscustomobject] -or @($required | Where-Object { $_ -notin $m.PSObject.Properties.Name }).Count -or @($m.PSObject.Properties.Name | Where-Object { $_ -notin ($required + @('voiceReference')) }).Count) { throw 'Invalid strategy manifest fields.' }
    if (($m.schemaVersion -isnot [int] -and $m.schemaVersion -isnot [long]) -or
        ($m.apiVersion -isnot [int] -and $m.apiVersion -isnot [long]) -or $m.schemaVersion -ne 1 -or $m.apiVersion -ne 1) { throw 'Unsupported TTS strategy schema/API version.' }
    if ($m.id -isnot [string] -or $m.version -isnot [string] -or $m.id -cnotmatch '^[a-z][a-z0-9-]{0,47}$' -or (Split-Path $Directory -Leaf) -cne $m.id -or
        $m.version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid strategy ID, directory or version.' }
    foreach ($field in @('name','description','license')) {
        if ($m.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($m.$field)) { throw "Invalid strategy $field." }
    }
    if ($m.platforms -isnot [array] -or $m.platforms.Count -ne 1 -or $m.platforms[0] -cne 'windows-x64') { throw 'Unsupported strategy platform.' }
    if ($m.devices -isnot [array] -or $m.devices.Count -eq 0 -or @($m.devices | Where-Object { $_ -cnotin @('cpu','cuda') }).Count -or
        @($m.devices | Select-Object -Unique).Count -ne $m.devices.Count) { throw 'Unsupported or duplicate strategy device.' }
    if ($m.prerequisites.python -isnot [string] -or $m.prerequisites.python -notmatch '^3\.\d+$' -or $m.prerequisites.visualCpp -isnot [bool]) { throw 'Invalid Python/Visual C++ prerequisites.' }
    foreach ($cap in @('builtinVoice','voiceCloning')) { if ($m.capabilities.$cap -isnot [bool]) { throw "Invalid capability: $cap" } }
    if ($m.PSObject.Properties.Name -contains 'voiceReference') {
        if ($m.voiceReference -isnot [pscustomobject] -or
            @($m.voiceReference.PSObject.Properties.Name | Where-Object { $_ -notin @('transcriptRequired','files') }).Count -or
            $m.voiceReference.transcriptRequired -isnot [bool] -or -not $m.capabilities.voiceCloning) { throw 'Invalid voice reference requirements.' }
        if ($m.voiceReference.PSObject.Properties.Name -contains 'files') {
            if ($m.voiceReference.files -isnot [array] -or $m.voiceReference.files.Count -lt 1 -or $m.voiceReference.files.Count -gt 4 -or
                @($m.voiceReference.files | Where-Object { $_ -isnot [string] -or $_.Length -gt 80 -or $_ -cnotmatch '^\{name\}[A-Za-z0-9_.-]*\.(wav|pt|txt)$' }).Count -or
                @($m.voiceReference.files | Select-Object -Unique).Count -ne $m.voiceReference.files.Count) { throw 'Invalid voice reference file patterns.' }
        }
    }
    if ($m.files -isnot [array] -or $m.files.Count -eq 0) { throw 'Strategy files must be an explicit list.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $m.files) {
        if ($file -isnot [string] -or $file.Contains('\') -or -not $seen.Add($file) -or $file -eq 'manifest.json' -or
            $file -match '(^|[/\\])(?:\.env|auth\.json|credentials\.json|config\.json|__pycache__|\.venv|voices)([/\\]|$)' -or
            [IO.Path]::GetExtension($file) -notin @('.ps1','.py','.json','.txt','.md','.toml','.cfg','.ini')) { throw 'Invalid, duplicate or private strategy package file.' }
        $path = Resolve-TtsPackagePath $Directory $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -gt 2MB) { throw "Missing or oversized package asset: $file" }
    }
    foreach ($pair in @(@('install','.ps1'),@('uninstall','.ps1'),@('backend','.py'))) {
        $entry = [string]$m.entrypoints.($pair[0])
        if (-not $seen.Contains($entry) -or [IO.Path]::GetExtension($entry) -cne $pair[1]) { throw "Invalid entry point: $($pair[0])" }
    }
    foreach ($item in @(@('prerequisites',@('python','visualCpp')),@('capabilities',@('builtinVoice','voiceCloning')),@('entrypoints',@('install','uninstall','backend')))) {
        if ($m.($item[0]) -isnot [pscustomobject] -or @(Compare-Object @($item[1] | Sort-Object) @($m.($item[0]).PSObject.Properties.Name | Sort-Object)).Count) { throw 'Invalid nested strategy fields.' }
    }
    if ($m.models -isnot [array]) { throw 'Strategy models must be an array.' }
    foreach ($model in @($m.models)) {
        $uri = $null
        if ($model -isnot [pscustomobject] -or @($model.PSObject.Properties.Name | Where-Object { $_ -notin @('license','revision','sha256','source') }).Count -or
            $model.source -isnot [string] -or -not [Uri]::TryCreate($model.source, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or
            ($model.PSObject.Properties.Name -contains 'revision' -and ($model.revision -isnot [string] -or $model.revision -cnotmatch '^[a-f0-9]{40}$')) -or
            ($model.PSObject.Properties.Name -contains 'sha256' -and ($model.sha256 -isnot [string] -or $model.sha256 -cnotmatch '^[a-f0-9]{64}$')) -or
            (-not $model.revision -and -not $model.sha256) -or $model.license -isnot [string] -or [string]::IsNullOrWhiteSpace($model.license)) { throw 'Models require a public HTTPS source without credentials/query/fragment, pinned revision or SHA256, and licence.' }
    }
    [pscustomobject]@{ Manifest=$m; Directory=[IO.Path]::GetFullPath($Directory); Files=@('manifest.json') + @($m.files) }
}

function Get-TtsStrategies {
    param([string]$Root)
    $directory = Join-Path $Root 'tts\strategies'
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw 'No TTS strategy directory found.' }
    $ids = @{}
    foreach ($child in Get-ChildItem -LiteralPath $directory -Directory | Sort-Object Name) {
        $package = Read-TtsStrategy $child.FullName
        if ($ids.ContainsKey($package.Manifest.id)) { throw 'Duplicate TTS strategy ID.' }
        $ids[$package.Manifest.id] = $true
        $package
    }
}

function Get-TtsStrategy {
    param([string]$Root, [string]$Id)
    $packages = @(Get-TtsStrategies $Root)
    $selected = @($packages | Where-Object { $_.Manifest.id -ceq $Id })
    if ($selected.Count -ne 1) { throw "TTS strategy unavailable: $Id" }
    return $selected[0]
}

function Get-TtsReferenceNames {
    param([string]$Root,$Package,$Record)
    if (-not $Package.Manifest.capabilities.voiceCloning -or -not $Record -or $Record.Status -ne 'Installed') { return }
    $patterns=@($Package.Manifest.voiceReference.files)
    # Compatibility with packages installed before file patterns were declared.
    if (-not $patterns.Count -or -not $patterns[0]) {
        $patterns=@(if ($Package.Manifest.id -ceq 'chatterbox-turbo') { @('{name}_prompt.pt') }
                  elseif ($Package.Manifest.voiceReference.transcriptRequired) { @('{name}.wav','{name}.txt') }
                  else { @('{name}.wav') })
    }
    $directory=Resolve-TtsPackagePath $Root $Record.Context.VoicesPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { return }
    $suffix=$patterns[0].Substring(6)
    foreach ($file in Get-ChildItem -LiteralPath $directory -File) {
        if (-not $file.Name.EndsWith($suffix,[StringComparison]::Ordinal)) { continue }
        $name=$file.Name.Substring(0,$file.Name.Length-$suffix.Length)
        if ($name -ceq 'default' -or $name -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$') { continue }
        $complete=$true
        foreach ($pattern in $patterns) {
            $path=Resolve-TtsPackagePath $Root ($Record.Context.VoicesPath+'/'+$pattern.Replace('{name}',$name))
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $complete=$false; break }
        }
        if ($complete) { $name }
    }
}

function Select-TtsEngine {
    param([object[]]$Manifests, [string]$Default)
    if ($Manifests.Count -eq 1 -and $Manifests[0].id -ceq $Default) { return $Default }
    for ($i=0; $i -lt $Manifests.Count; $i++) {
        Write-Host ("{0}. {1}: {2}" -f ($i+1), $Manifests[$i].name, $Manifests[$i].description)
    }
    $choice = Read-Host "Speech engines: numbers separated by commas; first is default [default: $Default]"
    if (-not $choice) { return $Default }
    $selected = @()
    foreach ($part in $choice.Split(',')) {
        $number = 0
        if (-not [int]::TryParse($part.Trim(), [ref]$number) -or $number -lt 1 -or $number -gt $Manifests.Count) { throw 'Invalid engine selection.' }
        $id = $Manifests[$number-1].id
        if ($selected -contains $id) { throw 'Duplicate engine selection.' }
        $selected += $id
    }
    return ($selected -join ',')
}

function Invoke-TtsVerifiedHook {
    param([string]$Path, [string]$SHA256, [hashtable]$Arguments)
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -cne $SHA256) { throw 'Strategy hook changed; execution refused.' }
    if ($null -ne ('WindowsHybridAgenticStack.SetupRuntime' -as [type]) -and [WindowsHybridAgenticStack.SetupRuntime]::IsHosting) {
        $result = [WindowsHybridAgenticStack.SetupRuntime]::InvokeVerifiedScript($Path, $SHA256, $Arguments)
        if ($result.ExitCode -ne 0) { throw "Strategy hook failed (exit $($result.ExitCode))." }
        foreach ($item in $result.Output) { $item }
    }
    elseif ($null -ne ('WindowsHybridAgenticStack.CommandHost' -as [type]) -and [WindowsHybridAgenticStack.CommandHost]::ManagedRoot) {
        Invoke-StackSetupScript -Path $Path -Arguments $Arguments
        if ($LASTEXITCODE -ne 0) { throw "Strategy hook failed (exit $LASTEXITCODE)." }
    }
    else {
        & $Path @Arguments
        if ($LASTEXITCODE -ne 0) { throw "Strategy hook failed (exit $LASTEXITCODE)." }
    }
}

function Get-TtsInstalledHooks {
    param([string]$Root, $State)
    foreach ($strategy in @($State.TtsStrategies)) {
        if ($null -eq $strategy) { continue }
        if ($strategy.Id -notmatch '^[a-z][a-z0-9-]{0,47}$' -or $strategy.ApiVersion -ne 1 -or
            $strategy.Context.InstallPath -ine $Root -or $strategy.Context.Engine -cne $strategy.Id) { throw 'Invalid installed strategy identity.' }
        $expectedPackage = "tts/strategies/$($strategy.Id)/"
        foreach ($asset in @($strategy.PackageFiles)) {
            if (-not $asset.Path.StartsWith($expectedPackage, [StringComparison]::Ordinal)) { throw 'Strategy file is outside its recorded package.' }
            $path = Resolve-TtsPackagePath $Root $asset.Path
            if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path).Hash -cne $asset.SHA256) { throw 'Installed strategy package missing or modified; repair before executing cleanup.' }
        }
        $hook = @($strategy.PackageFiles | Where-Object Path -ceq $strategy.UninstallPath)
        if ($hook.Count -ne 1) { throw 'Uninstall hook is not in the recorded strategy package.' }
        [pscustomobject]@{ Id=$strategy.Id; Path=(Resolve-TtsPackagePath $Root $strategy.UninstallPath); SHA256=$hook[0].SHA256; Context=$strategy.Context }
    }
}
