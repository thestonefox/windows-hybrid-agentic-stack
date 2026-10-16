#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts/installation-state.ps1')
. (Join-Path $repo 'scripts/command-registration.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('whas-cli-'+[guid]::NewGuid().ToString('N'))
$root=Join-Path $fixture 'installation'
$savedPath=$env:Path
$savedArgs=$env:WHAS_TEST_ARGUMENTS
$savedUser=$env:USERPROFILE
function Invoke-WhasTest {
    param([string[]]$Options,[int]$Expected=0)
    $result = & (Join-Path $fixture 'registration/bin/whas.exe') @Options 2>&1 | Out-String
    if ($LASTEXITCODE -ne $Expected) { throw "Unexpected exit for $Options : $result" }
    return $result
}
try {
    [IO.Directory]::CreateDirectory($fixture)|Out-Null
    $env:USERPROFILE=Join-Path $fixture 'user'
    [IO.Directory]::CreateDirectory($env:USERPROFILE)|Out-Null
    $session=Start-StackInstallationTracking $root
    foreach ($relative in @('scripts/configuration.ps1','scripts/command-host.cs','scripts/installation-state.ps1','scripts/script-invocation.ps1','scripts/agent-commands.ps1','scripts/agent-strategies.ps1','scripts/whas.ps1','config/defaults.json','agents/strategies/opencode/manifest.json','agents/strategies/opencode/adapter.ps1')) {
        $destination=Join-Path $root $relative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $destination))|Out-Null
        Copy-Item -LiteralPath (Join-Path $repo $relative) -Destination $destination
    }
    [IO.File]::WriteAllText((Join-Path $root 'opencode.json'),'{}')
    $fake=Join-Path $fixture 'opencode.exe'
    Add-Type -TypeDefinition @'
using System; using System.IO;
public class FakeOpenCode {
 public static int Main(string[] args) {
  File.WriteAllLines(Environment.GetEnvironmentVariable("WHAS_TEST_ARGUMENTS"),args);
  Console.WriteLine("{\"type\":\"text\",\"sessionID\":\"ses_fixture\",\"part\":{\"text\":\"ANSWER\"}}"); return 0;
 }
}
'@ -OutputAssembly $fake -OutputType ConsoleApplication
    $env:Path=$fixture+';'+$savedPath
    $env:WHAS_TEST_ARGUMENTS=Join-Path $fixture 'arguments.txt'
    Install-StackCommandRegistration -InstallPath $root -RegistrationDirectory (Join-Path $fixture 'registration') -PersistPath $false
    Complete-StackInstallationTracking $session $true
    $one=Invoke-WhasTest @('askl','literal & unchanged')
    $first=[IO.File]::ReadAllText($env:WHAS_TEST_ARGUMENTS)
    $two=Invoke-WhasTest @('ask','--local','literal & unchanged')
    if ($first -cne [IO.File]::ReadAllText($env:WHAS_TEST_ARGUMENTS) -or $one.Trim() -cne 'ANSWER' -or $two.Trim() -cne 'ANSWER') { throw 'Shortcut changed behaviour or output' }
    $null=Invoke-WhasTest @('performc','task')
    if ([IO.File]::ReadAllText($env:WHAS_TEST_ARGUMENTS) -notmatch 'ps-write') { throw 'Task permission routing failed' }
    $null=Invoke-WhasTest @('configure','--set','location','local')
    $settings=Invoke-WhasTest @('configure','--show')|ConvertFrom-Json
    if ($settings.interaction.location -ne 'local') { throw 'Shared configuration failed' }
    $null=Invoke-WhasTest @('configure','--set','speech.enabled','false')
    $settings=Invoke-WhasTest @('configure','--show')|ConvertFrom-Json
    if($settings.interaction.location -ne 'local' -or $settings.interaction.speech -ne $false) { throw 'Replacing existing configuration lost settings' }
    $null=Invoke-WhasTest @('ask','saved default')
    if ([IO.File]::ReadAllText($env:WHAS_TEST_ARGUMENTS) -notmatch 'ollama/qwen3:8b') { throw 'Saved default routing failed' }
    $response=Invoke-WhasTest @('chatl','--message','first turn')|ConvertFrom-Json
    if($response.sessionId -cne 'ses_fixture' -or $response.answer -cne 'ANSWER') { throw 'Graphical chat response contract failed' }
    $null=Invoke-WhasTest @('chatl','--session',$response.sessionId,'--message','second turn')
    if([IO.File]::ReadAllLines($env:WHAS_TEST_ARGUMENTS) -notcontains 'ses_fixture') { throw 'Contextual GUI turn lost the explicit session' }
    $null=Invoke-WhasTest @('chatl','--session',$response.sessionId)
    $received=[IO.File]::ReadAllLines($env:WHAS_TEST_ARGUMENTS)
    if ($received -notcontains '--session' -or $received -notcontains 'ses_fixture' -or $received -contains 'run') { throw 'Explicit contextual continuation failed' }
    # Native errors use stderr; keep them as data for expected failures.
    $ErrorActionPreference='Continue'
    $bad=Invoke-WhasTest @('askl','--cloud','question') 1
    $badSetting=Invoke-WhasTest @('configure','--set','location','invalid') 1
    $badSession=Invoke-WhasTest @('ask','--session','session_test','question') 1
    $wrongRoute=Invoke-WhasTest @('chatc','--session',$response.sessionId,'--message','private') 1
    $unknown=Invoke-WhasTest @('chatl','--session','unknown','--message','private') 1
    Push-Location $fixture
    try { $wrongWorkspace=Invoke-WhasTest @('chatl','--session',$response.sessionId,'--message','private') 1 } finally { Pop-Location }
    $ErrorActionPreference='Stop'
    if ($bad -notmatch 'Conflicting' -or $badSetting -notmatch 'must be local or cloud' -or $badSession -notmatch 'Session continuation') { throw 'Invalid options were not rejected clearly' }
    if($wrongRoute -notmatch 'does not match' -or $wrongWorkspace -notmatch 'does not match' -or $unknown -notmatch 'not registered') { throw 'Session isolation failed' }
    if ((Invoke-WhasTest @('configure','--show')|ConvertFrom-Json).interaction.location -ne 'local') { throw 'Invalid settings changed saved configuration' }
    Write-Host 'PASS: Native shortcuts, shared defaults, task permissions, literal prompts and explicit chat sessions'
} finally {
    $env:Path=$savedPath; $env:WHAS_TEST_ARGUMENTS=$savedArgs; $env:USERPROFILE=$savedUser
    $absolute=[IO.Path]::GetFullPath($fixture)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $absolute.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $absolute) -notmatch '^whas-cli-[a-f0-9]{32}$') { throw 'Unexpected cleanup target' }
    if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
