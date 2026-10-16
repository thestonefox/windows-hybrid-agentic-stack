# Quickstart

Run the commands below in **Windows PowerShell 5.1** on Windows 10/11.
Open **Windows PowerShell** from Start in a normal, non-administrator window.

Source `.ps1` scripts require permission to run. If an ordinary `Restricted`
policy blocks them, the process-only commands below allow setup without saving
a policy change. Alternatively, use the standalone EXE. Installed commands
work under ordinary `Restricted` policy without this option. Enforced
organisation policies still apply; see [execution-policy guidance](installation.md#powershell-execution-policy).

## 1. Get the project and open its folder

Without Git: open the [repository](https://github.com/thestonefox/windows-hybrid-agentic-stack),
select `main`, then **Code > Download ZIP**. In File Explorer, use **Extract All**
and choose where to extract it. Open the extracted folder containing
`install.ps1`, click File Explorer's address bar and copy its full path.
In PowerShell, replace the placeholder below with that copied path:

```powershell
Set-Location -LiteralPath 'PASTE YOUR EXTRACTED PROJECT FOLDER PATH HERE'
```

Or, if Git is already installed:

```powershell
New-Item -ItemType Directory -Path "$HOME\Source" -Force | Out-Null
Set-Location -LiteralPath "$HOME\Source"
git clone https://github.com/thestonefox/windows-hybrid-agentic-stack.git
Set-Location -LiteralPath .\windows-hybrid-agentic-stack
```

Confirm you are in the folder containing the installer:

```powershell
Get-Item .\install.ps1, .\scripts\check-prerequisites.ps1
```

Source commands below run from this folder.
See [getting the project](installation.md#get-the-project-and-open-powershell)
for more detail.

If you already have `whas-setup.exe`, no source checkout is needed on the
destination PC. Use `Set-Location` to open its containing folder instead;
for example, `Set-Location -LiteralPath "$HOME\Downloads"`.
If you need to build it first, see [standalone EXE setup](#option-b-standalone-exe).

## 2. Check and install prerequisites

Check what is already installed before installing anything. From the
repository root, run this read-only check:

```powershell
.\scripts\check-prerequisites.ps1
```

If ordinary execution policy blocks the script, use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-prerequisites.ps1
```

With a standalone EXE, run this from its containing directory instead. If you
do not have it yet, see [standalone EXE build and setup](#option-b-standalone-exe).

```powershell
.\whas-setup.exe --check
```

Without component flags, both checks inspect all three components. Add
`-Cloud`, `-Local` or `-Voice` for a subset with the script, or `--cloud`,
`--local` or `--voice` with the EXE. Review required `FAIL` results
and any `WARN` messages, install missing prerequisites below, then rerun the
check. A pass checks prerequisites; it does not prove provider authentication
or successful inference. See [prerequisite checks](installation.md#prerequisite-checks)
for the result categories.

Skip applications already installed. These commands use
[WinGet](https://learn.microsoft.com/en-us/windows/package-manager/winget/)
from a normal PowerShell window, with no execution-policy change. An individual
prerequisite installer may request administrator approval through a UAC prompt.

First confirm the Windows and PowerShell checks pass. Use the temporary
script permission above if needed. Install missing prerequisites in the order
below, running each command separately and checking its result.

**Python 3.11 (speech only):**

```powershell
winget install --id Python.Python.3.11 --exact --source winget
```

**Visual C++ x64 runtime (speech only):**

```powershell
winget install --id Microsoft.VCRedist.2015+.x64 --exact --source winget
```

**NVIDIA driver (optional acceleration for Chatterbox or F5):**

If you want GPU speech, make sure a compatible NVIDIA driver is installed.
Check detection with:

```powershell
nvidia-smi
```

See [NVIDIA driver requirements](installation.md#4-nvidia-gpu-drivers-optional-tts-acceleration).
Skip this for CPU speech, including Piper.

**OpenCode (cloud or local agents):**

```powershell
winget install --id SST.opencode --exact --source winget
```

**Ollama (local agents only):**

```powershell
winget install --id Ollama.Ollama --exact --source winget
```

### Refresh PATH

After installing prerequisites, reload PATH in the same PowerShell window so
new commands such as `opencode` are available:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
```

This updates only this window's PATH from saved machine and user values; it
leaves saved settings and your working directory unchanged. Alternatively,
close and reopen the terminal application, then return to your project or EXE
folder. Rerun the prerequisite check before continuing.

## 3. Connect your cloud provider

Skip this step for local-only or speech-only setup.

```powershell
opencode
```

In OpenCode, use `/connect` to sign in to your provider and `/models` to select
your model. Exit OpenCode when done.

## 4. Install the stack

Choose either route below. Both require the external prerequisites above.

### Option A: PowerShell source installer

Run the interactive installer and choose cloud agents, local agents, speech,
or a combination:

```powershell
.\install.ps1
```

Or select components directly:

```powershell
# Cloud agents only
.\install.ps1 -Cloud

# Cloud and local agents with speech
.\install.ps1 -Cloud -Local -Voice
```

If scripts are blocked, use this instead of the source commands above, after
reviewing the source:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

This permits scripts only in that installer process and its children. The
parent terminal and saved user/machine policies stay unchanged.

### Option B: Standalone EXE

A prebuilt release is not yet published. To build the EXE from source, run this
in the repository root using 64-bit Windows PowerShell 5.1 in a context that
permits the build script:

```powershell
.\scripts\build-setup.ps1
```

If ordinary execution policy blocks the build script, use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-setup.ps1
```

Copy `dist\whas-setup.exe` to the destination PC if needed. No source checkout
is needed on that PC. From the directory containing the EXE, check and install
your chosen components:

```powershell
# Cloud agents only
.\whas-setup.exe --check --cloud
.\whas-setup.exe --install --cloud

# Or cloud and local agents with speech
.\whas-setup.exe --check --cloud --local --voice
.\whas-setup.exe --install --cloud --local --voice
```

The EXE is **unsigned**. Windows may warn that the app is unrecognized or the
publisher is unknown. Read [unsigned EXE verification](installation.md#unsigned-exe-and-windows-warnings)
before proceeding. Some Windows security policies may block it entirely.

Both installers ask for confirmation and offer to download a missing local
model. The default local model is `qwen3:8b`. Chatterbox Turbo is the default
speech engine; use `--tts-engine piper-tts` or `--tts-engine f5-tts` with EXE
voice installation to choose another engine. Source interactive setup offers
the engine choice. F5 pretrained weights are for noncommercial use only.

The default destination is `%USERPROFILE%\AI\WindowsHybridAgenticStack`.
Keep the setup EXE outside that directory if you want to use it for uninstall.

## 5. Try the components you installed

Run the [PATH refresh command](#refresh-path) again to pick up the stack
commands, or close and reopen your terminal application.

```powershell
# Cloud agent
agent "Explain the difference between RAM and storage"

# Local agent
localagent "What is 2 plus 2?"

# Speech
tts-say "Hello, the speech service is working."

# Cloud response spoken aloud (requires cloud agents and speech)
agent -v "Explain gravity in one sentence"
```

The first speech request loads the selected model and can take some time.

## Uninstall

For source-script cleanup, run from the repository root. Preview removal first:

```powershell
.\uninstall.ps1
```

Then apply it with confirmation. This also removes unchanged Ollama models
created by the stack:

```powershell
.\uninstall.ps1 -Apply
```

If ordinary execution policy blocks the script, use the process-only fallback
instead. Preview:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Apply, including unchanged stack-created models:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -Apply
```

Or use the standalone EXE from its containing directory. Preview:

```powershell
.\whas-setup.exe --uninstall
```

Apply with confirmation, including unchanged stack-created Ollama models:

```powershell
.\whas-setup.exe --uninstall --apply
```

Use one route, not both. Unchanged, installer-created Ollama models are removed
by default. Add `-RetainManagedModels` to the script, or
`--retain-managed-models` to the EXE, to keep them. For a custom destination, add `-InstallPath 'D:\AI\AgentStack'`
to the script or `--install-path 'D:\AI\AgentStack'` to the EXE, using your actual
installation path.

Cleanup removes tracked stack files and command registration. It preserves
personal voices, edited or added files, original Ollama models, and separately
installed applications such as OpenCode, Ollama, Python and Visual C++.
Preserved files may leave the installation folder in place. Review the cleanup
receipt printed by the uninstaller.

After uninstalling, reload PATH in the same PowerShell window, or close
and reopen the terminal application:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
```

Then check command removal has succeeded:

```powershell
Get-Command agent,localagent,tts-start -ErrorAction SilentlyContinue
```

No output means those commands are no longer discoverable. See the
[full uninstall guide](installation.md#uninstall-a-tracked-installation)
for ownership rules and cleanup limitations.

For custom settings, voice profiles and removal, see the
[installation guide](installation.md). If a step fails, see
[troubleshooting](troubleshooting.md).
