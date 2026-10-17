#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess) { throw 'Run with 64-bit Windows PowerShell 5.1.' }

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repo 'docs/images' }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('whas-gui-docs-' + [guid]::NewGuid().ToString('N'))
$window = $null
try {
    [IO.Directory]::CreateDirectory($fixture) | Out-Null
    $preferences = Join-Path $fixture 'preferences.json'
    [IO.File]::WriteAllText($preferences, '{"schemaVersion":1,"theme":"dark","workspaces":["C:\\Users\\Public\\Documents"],"activeWorkspace":"C:\\Users\\Public\\Documents"}')

    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml,System.Drawing,System.Windows.Forms
    $references = @('System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Web.Extensions.dll',
        [Windows.Window].Assembly.Location,[Windows.Media.Visual].Assembly.Location,
        [Windows.Threading.Dispatcher].Assembly.Location,[System.Xaml.XamlReader].Assembly.Location)
    Add-Type -Path (Join-Path $repo 'scripts/gui-host.cs'),(Join-Path $repo 'scripts/fluent-gui.cs') -ReferencedAssemblies $references
    $catalog = @(Get-ChildItem (Join-Path $repo 'tts/strategies') -Directory |
        ForEach-Object { Get-Content (Join-Path $_.FullName 'manifest.json') -Raw | ConvertFrom-Json }) | ConvertTo-Json -Depth 12
    $theme = [IO.File]::ReadAllText((Join-Path $repo 'scripts/gui-theme.xaml'))
    $executable = Join-Path $fixture 'whas-gui.exe'
    $window = New-Object WindowsHybridAgenticStack.FluentWindow($true,$executable,$catalog,(Join-Path $fixture 'sample-install'),$theme,$preferences)
    $null = (New-Object Windows.Interop.WindowInteropHelper($window)).EnsureHandle()
    $flags = [Reflection.BindingFlags]'NonPublic,Instance'
    $controller = $window.GetType().GetField('controller',$flags).GetValue($window)
    $destination = $controller.GetType().GetField('destination',$flags).GetValue($controller)
    $destination.Text = 'C:\WHAS'

    $screens = Join-Path $fixture 'screens'
    [IO.Directory]::CreateDirectory($screens) | Out-Null
    $window.SelectPage(0)
    $window.Render((Join-Path $screens 'gui-setup-features.png'))
    $window.SelectPage(1)
    $window.Render((Join-Path $screens 'gui-setup-models.png'))

    $controller.GetType().GetField('setup',$flags).SetValue($controller,$false)
    $controller.GetType().GetMethod('BuildPages',$flags).Invoke($controller,@()) | Out-Null
    foreach ($screen in @(@('Assistant','gui-assistant.png'),@('Workspaces','gui-workspaces.png'))) {
        $pages = $controller.GetType().GetField('tabs',$flags).GetValue($controller).TabPages
        $index = -1
        for ($i=0; $i -lt $pages.Count; $i++) { if ($pages[$i].Text -eq $screen[0]) { $index=$i; break } }
        if ($index -lt 0) { throw "GUI page missing: $($screen[0]). Available: $(@(for($i=0;$i -lt $pages.Count;$i++){$pages[$i].Text}) -join ', ')" }
        $window.SelectPage($index)
        $window.Render((Join-Path $screens $screen[1]))
    }
    $controller.GetType().GetMethod('AddConversationReply',$flags).Invoke($controller,@(
        'What can WHAS help me with?',
        'I can answer questions, continue a conversation, or run a task in a workspace you choose.')) | Out-Null
    $window.SelectPage(0)
    $window.Render((Join-Path $screens 'gui-conversation.png'))

    [IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
    foreach ($image in Get-ChildItem -LiteralPath $screens -Filter '*.png' -File) {
        Copy-Item -LiteralPath $image.FullName -Destination (Join-Path $OutputDirectory $image.Name) -Force
        Write-Host "Rendered $($image.Name)"
    }
}
finally {
    if ($window) { $window.Dispose() }
    $absolute = [IO.Path]::GetFullPath($fixture)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $absolute) -notmatch '^whas-gui-docs-[a-f0-9]{32}$') { throw 'Unexpected GUI documentation fixture path.' }
    if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
