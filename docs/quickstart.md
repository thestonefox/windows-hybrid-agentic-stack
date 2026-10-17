# Quickstart

Use a normal **Windows PowerShell 5.1** window on Windows 10/11.
This guide gets you running; the [installation guide](installation.md) covers
configuration and alternatives in detail.

## 1. Get the project

Open the [repository](https://github.com/thestonefox/windows-hybrid-agentic-stack),
select `main`, then **Code > Download ZIP**. In File Explorer, use **Extract All**
and choose a location.

For graphical setup, open the extracted folder and double-click
**`whas-gui.exe`**. It includes feature selection and prerequisite checks; see
the [graphical route](#standalone-exe-route). You do not need to build it.

For PowerShell setup, open the folder containing `install.ps1`, copy its full
path from the address bar and replace the placeholder below:

```powershell
Set-Location -LiteralPath 'PASTE YOUR EXTRACTED PROJECT FOLDER PATH HERE'
```

```powershell
Get-Item .\install.ps1
```

The installer should be listed. Source commands below run from this folder.
[Git cloning instructions](installation.md#clone-with-git-instead) are optional.
The download includes both PowerShell sources and the built graphical EXE.
Follow the commands below if you chose the PowerShell route.

## 2. Check prerequisites and install what is missing

The read-only checker inspects all components by default:

```powershell
.\install.ps1 -Check
```

If ordinary execution policy blocks it, use temporary permission for that
process only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Check
```

For graphical setup, use the [standalone EXE route](#standalone-exe-route).

Review required `FAIL` results and any `WARN` messages. Add component flags only
for a subset; see [check options](installation.md#prerequisite-checks).
Windows and PowerShell checks must pass. Install missing prerequisites below
in order, running each command separately. Skip components you do not need.

WinGet commands work in normal PowerShell without an execution-policy change.
An individual installer may request administrator approval through UAC.
If WinGet is missing, see [WinGet setup](installation.md#1-check-winget).

**Python (speech only):**

```powershell
winget install --id Python.Python.3.11 --exact --source winget
```

**Visual C++ x64 (speech only):**

```powershell
winget install --id Microsoft.VCRedist.2015+.x64 --exact --source winget
```

**NVIDIA (optional GPU speech with Chatterbox or F5):** install a compatible
[driver](installation.md#4-nvidia-gpu-drivers-optional-tts-acceleration) if needed.
Piper and CPU speech do not need it. Check detection:

```powershell
nvidia-smi
```

**OpenCode (cloud or local agents):**

```powershell
winget install --id SST.opencode --exact --source winget
```

**Ollama (local agents only):**

```powershell
winget install --id Ollama.Ollama --exact --source winget
```

### Refresh PATH

After prerequisite installation, reload PATH in the same PowerShell window:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
```

This updates this window from saved values without changing saved settings.
Alternatively, close and reopen the terminal application, then return to the
project or EXE folder. Rerun the prerequisite check before continuing.

## 3. Connect your cloud provider

Skip this for local-only or speech-only installation:

```powershell
opencode
```

Use `/connect` to sign in and `/models` to select your model, then exit OpenCode.

## 4. Install the stack

From the repository root, choose components interactively:

```powershell
.\install.ps1
```

If ordinary execution policy blocks it, use this instead:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

The GUI offers installed Ollama models for reuse. If none are installed, it
preselects `qwen2.5:1.5b` as a small starter (about 1 GB); you can choose another
model. Local AI requires at least one selected model. Missing selected models
are downloaded when you apply features; cloud-only setup downloads none.
PowerShell/CLI setup retains its configured default (`qwen3:8b` when unchanged).
For speech, choose one or more engines; the first is the default. Chatterbox is
the initial default. F5 pretrained weights are for noncommercial use only.
The default destination is `%USERPROFILE%\AI\WindowsHybridAgenticStack`.
Both installation routes provide the command line and graphical applications.
For multiple local models, see [model selection](cli.md#local-model-selection).

### Standalone EXE route

Use `whas-gui.exe` from the extracted repository ZIP. No build is required.
You can also copy just this EXE to another PC; it embeds setup and does not
need the source checkout there. Keep `whas-gui.manifest.json` if you want to
compare its published checksum. See [verification](installation.md#unsigned-exe-and-windows-warnings).

The EXE is **unsigned**; read [Windows warnings and verification](installation.md#unsigned-exe-and-windows-warnings).
Double-click `whas-gui.exe`. On first run, choose **Features**, models/engines,
use **Check Prerequisites**, then the fixed **Go to Apply Features** button. On that
page, read the automatically loaded plan (use **Check Again** to refresh), then use the fixed
**Apply selected features** button. Once
configured, the same application opens usage and settings. See the
[graphical guide](gui.md). Use `install.ps1` for console setup.

## 5. Try your installed components

Run the [PATH refresh command](#refresh-path) again or reopen the terminal
application. Use the examples for components you installed:

```powershell
whas askc "Explain the difference between RAM and storage"
```

```powershell
whas askl "What is 2 plus 2?"
```

```powershell
whas tts say "Hello, the speech service is working."
```

```powershell
whas askc --voice "Explain gravity in one sentence"
```

The first speech request loads a model. See [engine management](tts-strategies.md#manage-installed-engines)
and the [per-engine guides](tts-strategies.md#user-guides) for selection and custom voices.
Use `whas configure` to change defaults. For contextual conversations use
`whas chatl` or `whas chatc`; [session guidance](agent-strategies.md#sessions-and-memory)
explains resumption and personal data. CLI chat uses OpenCode; GUI chat on
This PC uses Ollama directly with history kept in the current window.
Open the repository or installed `whas-gui.exe` for graphical use, then use
the top-right cog for **Configuration**. Choose **Maintenance > Removal**
for whole-app uninstallation. Opening a newer repository EXE uses the existing
installation but does not update its installed files; see [updates](gui.md#use-and-configure).

For all commands and flags, open the [CLI reference](cli.md#complete-command-and-flag-reference).
Installed help is `whas --help` for requests and `whas tts --help` or
`tts-help` for speech.

## Uninstall

From the repository root or installed directory, preview first:

```powershell
.\uninstall.ps1
```

Apply with confirmation, including unchanged installer-created Ollama models:

```powershell
.\uninstall.ps1 -Apply
```

Add `-RetainManagedModels` to keep those models. If execution policy blocks the
script, see the [temporary uninstall permission commands](installation.md#if-execution-policy-blocks-the-uninstall-script).

Or open `whas-gui.exe`, go to **Configuration > Maintenance > Removal**,
preview removal, choose whether
to retain installer-created models, then confirm removal. Choose one uninstall
route. Personal voices, modified/unknown files, original models and separately
installed prerequisites are preserved. Read the cleanup receipt.

After uninstalling, reload PATH in the same PowerShell window, or close
and reopen the terminal application:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
```

Then check command removal has succeeded:

```powershell
Get-Command whas -CommandType Application -ErrorAction SilentlyContinue
```

No output means the unified command is no longer discoverable, unless uninstall
restored an earlier installation's registration. See [full removal details](installation.md#uninstallation)
for custom paths and preservation rules, or [troubleshooting](troubleshooting.md).
