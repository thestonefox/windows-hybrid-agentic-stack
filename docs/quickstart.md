# Quickstart

Use a normal **Windows PowerShell 5.1** window on Windows 10/11.
This guide gets you running; the [installation guide](installation.md) covers
configuration and alternatives in detail.

## 1. Get the project

Open the [repository](https://github.com/thestonefox/windows-hybrid-agentic-stack),
select `main`, then **Code > Download ZIP**. In File Explorer, use **Extract All**
and choose a location. Open the extracted folder containing `install.ps1` and
copy its full path from the address bar. Replace the placeholder below:

```powershell
Set-Location -LiteralPath 'PASTE YOUR EXTRACTED PROJECT FOLDER PATH HERE'
```

```powershell
Get-Item .\install.ps1, .\scripts\check-prerequisites.ps1
```

Both files should be listed. Source commands below run from this folder.
[Git cloning instructions](installation.md#clone-with-git-instead) are optional.
If you already have the EXE, open its containing folder instead; see
[standalone setup](#standalone-exe-route). A prebuilt release is not yet published.

## 2. Check prerequisites and install what is missing

The read-only checker inspects all components by default:

```powershell
.\scripts\check-prerequisites.ps1
```

If ordinary execution policy blocks it, use temporary permission for that
process only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-prerequisites.ps1
```

Or, from the folder containing the [standalone EXE](#standalone-exe-route):

```powershell
.\whas-setup.exe --check
```

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

The default local model is `qwen3:8b`; setup offers to download it if missing.
For speech, choose one or more engines; the first is the default. Chatterbox is
the initial default. F5 pretrained weights are for noncommercial use only.
The default destination is `%USERPROFILE%\AI\WindowsHybridAgenticStack`.

### Standalone EXE route

If you need to build the EXE first, see [standalone build instructions](installation.md#standalone-executable-setup),
including [temporary build permission](installation.md#powershell-execution-policy).
Copy `dist\whas-setup.exe` to the destination PC; no source checkout is needed
there. Keep the EXE outside the installation directory.

The EXE is **unsigned**; read [Windows warnings and verification](installation.md#unsigned-exe-and-windows-warnings).
From its containing folder, check prerequisites as above, then install:

```powershell
.\whas-setup.exe --install
```

With no component flags, EXE setup uses configured defaults (initially all
components). See [component and engine options](installation.md#standalone-executable-setup)
if you only want part of the stack.

## 5. Try your installed components

Run the [PATH refresh command](#refresh-path) again or reopen the terminal
application. Use the examples for components you installed:

```powershell
agent "Explain the difference between RAM and storage"
```

```powershell
localagent "What is 2 plus 2?"
```

```powershell
tts-say "Hello, the speech service is working."
```

```powershell
agent -v "Explain gravity in one sentence"
```

The first speech request loads a model. See [engine management](tts-strategies.md#manage-installed-engines)
and the [per-engine guides](tts-strategies.md#user-guides) for selection and custom voices.

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

Or use the EXE from its containing folder. Preview:

```powershell
.\whas-setup.exe --uninstall
```

Apply:

```powershell
.\whas-setup.exe --uninstall --apply
```

Add `--retain-managed-models` to keep stack-created models. Choose one uninstall
route. Personal voices, modified/unknown files, original models and separately
installed prerequisites are preserved. Read the cleanup receipt.

After uninstalling, reload PATH in the same PowerShell window, or close
and reopen the terminal application:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
```

Then check command removal has succeeded:

```powershell
Get-Command agent,localagent,tts-start -ErrorAction SilentlyContinue
```

No output means those commands are no longer discoverable, unless uninstall
restored an earlier installation's registration. See [full removal details](installation.md#uninstallation)
for custom paths and preservation rules, or [troubleshooting](troubleshooting.md).
