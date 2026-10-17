# Installation and uninstallation guide

Follow the installation process from getting the project through checking the
installed commands. A separate uninstallation process follows it. Source
commands using `.\` paths run from the repository root, even though this guide
lives in `docs`; EXE commands run from the indicated containing directory.

For the shorter path, see the [quickstart](quickstart.md).
Return to the [project overview](../README.md).

- [Installation](#installation)
  - [Get the project and open PowerShell](#get-the-project-and-open-powershell)
  - [Check prerequisites](#prerequisite-checks)
  - [Install missing prerequisites](#installing-prerequisites)
  - [Connect your cloud provider](#configure-provider-authentication-cloud-agents-only)
  - [Configure the stack](#configuration)
  - [PowerShell execution policy](#powershell-execution-policy)
  - [Choose a speech engine](#tts-engine-strategies)
  - [Run setup](#install-the-stack)
  - [Refresh PATH and check commands](#finish-installation-and-check-commands)
- [Uninstallation](#uninstallation)
  - [Source-script removal](#uninstall-a-tracked-installation)
  - [Graphical removal](#uninstall-with-the-graphical-application)
  - [What cleanup preserves](#what-cleanup-removes-and-preserves)
  - [Refresh PATH and check removal](#refresh-path-and-check-removal)
- [Use WHAS: ask, chat and perform](#use-whas-ask-chat-and-perform)
- [TTS commands](#tts-commands)
- [Troubleshooting](#troubleshooting)
- [Technical reference and historical tests](#technical-reference-and-historical-tests)

## Installation

Work through the following sections in order. Install only the prerequisites
and stack components you intend to use.

### Get the project and open PowerShell

Start on Windows 10/11. Open **Windows PowerShell** from the Start menu, using
a normal window rather than **Run as administrator**. The scripts and build
target 64-bit Windows PowerShell 5.1, the version supplied with Windows.

Choose one way to get the source below. Git is optional. You need the source
to run `install.ps1` or build `whas-gui.exe`; a destination PC receiving an
already-built EXE does not need Git or a source checkout.

#### Download a ZIP (no Git required)

1. Open the [project repository](https://github.com/thestonefox/windows-hybrid-agentic-stack).
2. Select the `main` branch, then **Code > Download ZIP**.
3. In File Explorer, right-click the downloaded ZIP and select **Extract All**.
   Choose where to extract it. Use the extracted files, rather than running
   anything from inside the ZIP.
4. Open the extracted folder containing `install.ps1`. There may be an extra
   enclosing folder, so check that the file is visible.
5. Click File Explorer's address bar and copy the full folder path.
6. In PowerShell, replace the placeholder below with that copied path:

```powershell
Set-Location -LiteralPath 'PASTE YOUR EXTRACTED PROJECT FOLDER PATH HERE'
```

Keep the path in quotes so spaces are handled correctly. The ZIP's download
location and the extracted project location can be different; use the extracted
folder containing `install.ps1`.

#### Clone with Git instead

If Git is already installed, run these commands in PowerShell. The HTTPS URL
does not require an SSH key for a public repository:

```powershell
New-Item -ItemType Directory -Path "$HOME\Source" -Force | Out-Null
Set-Location -LiteralPath "$HOME\Source"
git clone https://github.com/thestonefox/windows-hybrid-agentic-stack.git
Set-Location -LiteralPath .\windows-hybrid-agentic-stack
```

If `git` is not recognised, use the ZIP route above. If the destination already
contains a checkout, open that checkout instead of cloning over it.

#### Confirm you are in the project root

The **repository root** is the folder containing `install.ps1`, `scripts` and
`tts`. Check it before continuing:

```powershell
Get-Location
Get-Item .\install.ps1
```

The installer should be listed. If it is missing, check the folder path; ZIP
extraction can leave an extra enclosing folder. Commands beginning with `.\`
refer to the current folder. Run source checks, builds and installation from
this root, even while reading instructions in `docs`.

The source folder is separate from the installed stack, whose default location
is `%USERPROFILE%\AI\WindowsHybridAgenticStack`.

#### If you already have the standalone EXE

You can run it from the extracted repository, Downloads or the installation
folder. It discovers the active installation through local command registration;
its containing folder does not choose a different configuration. In PowerShell,
move into its containing folder, for example:

```powershell
Set-Location -LiteralPath "$HOME\Downloads"
Get-Item .\whas-gui.exe
```

Use the actual containing folder if different. Double-click a reviewed build
and use its **Prerequisites** screen. For developer build instructions, follow
[standalone executable setup](#standalone-executable-setup). Review the
[unsigned EXE guidance](#unsigned-exe-and-windows-warnings) before running it.
A prebuilt project release is not yet published.

### Prerequisite checks

Start by checking what is already installed. The checker is read-only: it
reports detected software and potential compatibility issues without installing
anything. Use a normal Windows PowerShell window; administrator PowerShell is
not required for this check.

From the repository root, check all components (the default):

```powershell
.\install.ps1 -Check
```

If ordinary execution policy blocks the source script, run it with permission
limited to a child process:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Check
```

This leaves saved policies and the parent terminal unchanged. Enforced
organisation policies still apply. See [PowerShell execution policy](#powershell-execution-policy).

The repository ZIP includes both `install.ps1` and `whas-gui.exe`. For the
graphical route, double-click the EXE and use its **Prerequisites** screen;
see [standalone executable setup](#standalone-executable-setup) and
[unsigned EXE warnings](#unsigned-exe-and-windows-warnings).

The checker inspects cloud agents, local agents and speech when no component
flags are supplied.

Or check components independently:

```powershell
.\install.ps1 -Check -Cloud
```

```powershell
.\install.ps1 -Check -Local
```

```powershell
.\install.ps1 -Check -Voice
```

Check a particular speech engine, or comma-separated engines:

```powershell
.\install.ps1 -Check -Voice -TtsEngine piper-tts
```

`-Check` never prompts or installs anything. It exits with code `0` when the
selected prerequisites pass, or `1` when prerequisites are missing or selection
is invalid. The helper in `scripts/check-prerequisites.ps1` remains available
for direct use.

The checker uses the following result categories:

| Result | Meaning |
|---|---|
| `PASS` | A prerequisite was detected successfully |
| `WARN` | A potential issue requires attention |
| `FAIL` | A required prerequisite is missing or a check failed |
| `INFO` | Additional information or verification is required |

A successful prerequisite check does not guarantee successful cloud authentication, model inference, or TTS generation.

Review required `FAIL` results and any `WARN` messages, install only missing
prerequisites using the instructions below, then rerun the same check.

### Requirements

The project targets **Windows 10/11 and Windows PowerShell 5.1**.

| Component | Requirements |
|---|---|
| Cloud agents | OpenCode and authentication for your chosen provider |
| Local agents | OpenCode, Ollama, and a downloaded local model |
| Text-to-speech | Python 3.11 (64-bit) and Microsoft Visual C++ Redistributable (x64) |
| NVIDIA-accelerated TTS | Compatible NVIDIA GPU and driver |

You only need the prerequisites for the components you intend to install.

Cloud-only agents do not require Python or Ollama. Voice-only installation does not require OpenCode or Ollama.

The project installer manages the selected TTS strategy's private Python environment, model and dependencies: PyTorch for Chatterbox/F5, or CPU ONNX Runtime for Piper. External applications such as Python, OpenCode and Ollama are installed separately from the stack; use the GUI's WinGet action or the manual installation instructions below.

### Installing prerequisites

First confirm the Windows and PowerShell checks pass. If source scripts are
blocked, follow [execution-policy guidance](#powershell-execution-policy).
Then work through the applicable prerequisites below in check order: Python,
Visual C++, optional NVIDIA drivers, OpenCode and Ollama. Run each command
separately and check its result before continuing.

Install only what the prerequisite check reports missing for your selected
components. We recommend **Windows Package Manager (WinGet)** for external
application installation.

Run WinGet from a normal PowerShell window. These executable commands do not
need a PowerShell execution-policy change. An individual prerequisite installer
may ask for administrator approval through a UAC prompt; you do not normally
need to start PowerShell as administrator. See [Microsoft's WinGet guidance](https://learn.microsoft.com/en-us/windows/package-manager/winget/).

The project does not require users to install npm, Scoop, Chocolatey, Visual Studio, or the CUDA Toolkit for its standard setup.

#### Refresh PATH after an installation

If an installer reports that PATH changed, refresh the current PowerShell
window before using the newly installed command:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
```

This reloads the current process PATH from the saved machine and user entries.
It does not change saved PATH values, execution policy or administrator rights,
and you stay in the same working directory. It is a built-in PowerShell/.NET
command; no extra refresh tool is needed.

Alternatively, close and reopen the terminal application. A new tab in an
already-running terminal may inherit its old PATH. For other environment
changes, follow the application's restart instructions; this command refreshes
PATH only.

Use this refresh after stack installation or uninstall too. Those operations
update saved user PATH and their own process environment, but a setup EXE or
child PowerShell process cannot update the already-open parent terminal's
environment. Refresh in the terminal where you want to use or check commands.
No PowerShell profile reload is needed; the stack commands do not use a profile.

The GUI prerequisite page offers **Open download page** and **Install with WinGet** for supported missing dependencies. The WinGet action installs that package, accepts source and package agreements, logs output, and rechecks prerequisites after success. Windows may ask for administrator approval. If WinGet is unavailable or installation fails, use the download page and select **Check Again** after installing. NVIDIA drivers remain a manual download.

#### 1. Check WinGet

Open Windows PowerShell and run:

```powershell
winget --version
```

If WinGet is unavailable, follow Microsoft's [WinGet installation instructions](https://learn.microsoft.com/en-us/windows/package-manager/winget/).

Windows Sandbox may require additional WinGet setup.

#### 2. Install Python 3.11 (TTS only)

The bundled TTS strategies require a compatible Python installation. The project's tested reference is **64-bit Python 3.11**.

Install it using:

```powershell
winget install --id Python.Python.3.11 --exact --source winget
```

Run the [PATH refresh command](#refresh-path-after-an-installation) above, then verify:

```powershell
py -3.11 --version
```

You can also list installed Python versions:

```powershell
py -0p
```

The TTS installer uses Python 3.11 to create a separate virtual environment inside the selected stack installation directory.

It does not install TTS packages into your global Python installation.

#### 3. Install Microsoft Visual C++ Redistributable (TTS only)

**Microsoft Visual C++ Redistributable 2015–2022 (x64) is required for the bundled TTS strategies on Windows.**

This applies to both CPU-only and CUDA-enabled installations.

PyTorch uses native Windows DLLs that depend on the Microsoft Visual C++ runtime.

Install the redistributable using:

```powershell
winget install --id Microsoft.VCRedist.2015+.x64 --exact --source winget
```

If the runtime is already installed, WinGet may report that no applicable update is available.

Alternatively, download the supported x64 redistributable from [Microsoft](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist).

Without this prerequisite, importing PyTorch may fail with an error such as:

```text
OSError: [WinError 126] The specified module could not be found.
Error loading torch\lib\c10.dll or one of its dependencies.
```

Install the redistributable, reopen PowerShell if necessary, and retry the selected TTS installer.

**The full Visual Studio IDE, C++ build tools, and a separate CUDA Toolkit are not required for the precompiled PyTorch packages used by this installer.**

#### 4. NVIDIA GPU drivers (optional TTS acceleration)

Chatterbox and F5 can use CPU-only PyTorch or CUDA-enabled PyTorch. Piper uses CPU ONNX Runtime.

For GPU acceleration, install a compatible NVIDIA graphics driver.

Verify GPU detection:

```powershell
nvidia-smi
```

The TTS installer uses the `tts.device` configuration setting.

| Setting | Behaviour |
|---|---|
| `auto` | Select CUDA when an NVIDIA GPU is detected; otherwise CPU |
| `cpu` | Use CPU-only PyTorch |
| `cuda` | Use CUDA 12.6 PyTorch |

The project's CUDA package versions are based on a working installation using PyTorch `2.6.0+cu126`.

A separate CUDA Toolkit installation is not required for the precompiled wheels. A sufficiently recent, compatible NVIDIA driver is required.

**Important:** Automatic GPU detection does not guarantee successful CUDA inference. Actual GPU execution must still be verified on the target hardware.

#### 5. Install OpenCode (cloud or local agents)

Install the OpenCode CLI:

```powershell
winget install --id SST.opencode --exact --source winget
```

Run the [PATH refresh command](#refresh-path-after-an-installation) above, then verify:

```powershell
opencode --version
```

See the [OpenCode website](https://opencode.ai/) for documentation.

#### 6. Install Ollama (local agents only)

Install Ollama:

```powershell
winget install --id Ollama.Ollama --exact --source winget
```

Run the [PATH refresh command](#refresh-path-after-an-installation) above, then verify:

```powershell
ollama --version
```

List downloaded models:

```powershell
ollama list
```

The GUI offers installed Ollama models for reuse. If none are installed, it
preselects `qwen2.5:1.5b` as a small starter (about 1 GB); you can choose another
model. Local AI requires at least one selected model. Missing selected models
are downloaded when you apply features; cloud-only setup downloads none.
PowerShell/CLI setup retains its configured default (`qwen3:8b` when unchanged).

To download the default model manually:

```powershell
ollama pull qwen3:8b
```

You can configure another model in `config/config.json`. During local-agent installation, the installer creates a separate context-enabled variant of the selected Ollama model instead of modifying the source model. See [Local Ollama context size](#local-ollama-context-size).

### Configure provider authentication (cloud agents only)

Cloud agents use the provider and model selected in OpenCode.

Launch OpenCode:

```powershell
opencode
```

Follow its provider authentication instructions.

Use `/connect` to connect your provider and `/models` to select an available model. Signing in alone does not guarantee a particular model selection.

Model availability and billing depend on your provider account and authentication method.

The installer leaves OpenCode model selection unchanged by default. It does not authenticate your account or guarantee model access.

### Configuration

The project includes built-in defaults in:

```text
config/defaults.json
```

You can optionally override individual settings using:

```text
config/config.json
```

The user-specific configuration file is excluded from Git. Before installation,
these paths refer to the source checkout and control setup. Afterwards, the
active settings live in the installation's `config/config.json`; use
**Configuration** in the GUI or `whas configure` to change them. Editing the
checkout's file does not update the installed copy.

#### Create a configuration file

For a new source configuration, copy the example. If `config/config.json`
already exists, edit that file instead of replacing it:

```powershell
Copy-Item .\config\config.json.example .\config\config.json
```

Edit only the values you want to override.

For example:

```json
{
  "agents": {
    "local": {
      "model": "qwen3:8b",
      "contextSize": 16384
    }
  },
  "tts": {
    "device": "auto",
    "defaultVoice": "default",
    "idleTimeoutMinutes": 10,
    "autoStart": true,
    "port": 18765
  }
}
```

The configuration loader merges overrides with the built-in defaults.

It validates settings and rejects unsupported or unknown values.

#### Cloud model selection

Cloud requests inherit OpenCode's model selection unless WHAS has a saved
override. Signing in does not choose a model. `whas askc --model provider/model
"Your question"` overrides one invocation; use a model ID actually available
to your connected provider. After installation, use **Configuration > Models**
or `whas configure --set cloud.model provider/model` to save an override.

For a persistent stack override, set `agents.cloud.model` to a fully qualified `provider/model` ID. The optional `agents.cloud.provider` supports shorter model names. Both default to `null`; local commands continue to select their configured Ollama model explicitly.

Existing explicit stack settings are preserved. To inherit OpenCode selection, set `agents.cloud.model` to `null` in your stack configuration. Older installations may also have a `model` entry in the installation directory's `opencode.json`; remove that entry if it is the old stack default you no longer want. Reinstalling preserves existing model entries rather than guessing whether they are personal choices.

#### Local Ollama context size

The local agent uses `agents.local.contextSize`, defaulting to **16384 tokens**. This is a context-window setting, not a guarantee of output length or model accuracy. Valid configuration values range from **4096 to 131072** tokens; larger values can require substantially more memory.

For example, to select the source model and context size in `config/config.json`:

```json
{
  "agents": {
    "local": {
      "model": "qwen3:8b",
      "contextSize": 16384
    }
  }
}
```

When `-Local` is selected, the installer checks for the original Ollama model and
creates a **separate managed model** whose Modelfile includes `PARAMETER num_ctx
16384`. For `qwen3:8b`, the generated name is `whas-qwen3-8b-ctx16384`. Setup
saves that alias as the local model used by local requests; the original
`qwen3:8b` remains unchanged. Choosing a different installed model afterwards
uses that exact model and its parameters; it does not create another alias.
GUI Conversation and One-off question call Ollama directly; tasks and CLI
requests use OpenCode. See [local model selection](cli.md#local-model-selection).

The generated name is based on the exact configured source model and context size. For example, choosing the already customised source `qwen3-8b-16k` produces `whas-qwen3-8b-16k-ctx16384`. Prefer selecting the original model when no other customisations are needed.

To inspect the generated model:

```powershell
ollama show whas-qwen3-8b-ctx16384 --modelfile
```

Look for `PARAMETER num_ctx 16384`. You can also use `ollama list` to see available models. Re-running the installer reuses an existing managed model when its context setting matches; it refuses to overwrite a same-named model with conflicting parameters. Changing the source model or context size requires rerunning `.\install.ps1 -Local` to update the installed agent configuration.

#### Inspect configuration

Show the effective configuration:

```powershell
.\scripts\config.ps1 -Show
```

Validate it:

```powershell
.\scripts\config.ps1 -Validate
```

Generate a configuration from defaults:

```powershell
.\scripts\config.ps1 -Init
```

#### Installation directory

The default installation directory is:

```text
%USERPROFILE%\AI\WindowsHybridAgenticStack
```

You do not need to specify this path when running the installer.

The installation directory can be overridden through `config/config.json` or the root installer's optional `-InstallPath` parameter.

The root installer passes the selected directory to individual components so they use the same installation.

### PowerShell execution policy

Installed commands are native console applications built locally with Windows PowerShell 5.1's bundled compiler. They host the stack's PowerShell command code through Microsoft's [PowerShell hosting API](https://learn.microsoft.com/en-us/powershell/scripting/developer/hosting/adding-and-invoking-commands?view=powershell-7.2), without loading profiles or setting execution policies. Runtime tests pass with the caller's effective policy remaining Restricted. Enforced organisation policies are checked and restrictive settings cause an explicit error.

The source installer and maintenance scripts are still `.ps1` files and require a context that permits running those scripts. The installer does not configure execution policy or offer to change it. The standalone setup EXE can install and uninstall the stack under Restricted without changing execution policy, as described below.

#### Run the source installer with temporary permission

On a personal machine where script execution is blocked by the ordinary user
or machine setting, you can explicitly allow it for just the installer process.
After reviewing the downloaded source, run this from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

You can pass the usual installer options after the script path:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Cloud -Local -Voice
```

`Bypass` permits scripts in that child PowerShell process and its children.
It does not save a policy to the registry or change the parent terminal's
policy. The temporary setting ends when those processes exit. `-NoProfile`
also skips profile scripts for this invocation. This is an explicit choice
you make when launching setup; the installer does not change policy itself.

The same process-only approach can build the standalone EXE using 64-bit
Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-gui.ps1
```

Once built, the EXE can install under an ordinary `Restricted` policy without
this option. Source-script uninstall has its own temporary-permission examples
in [Uninstallation](#uninstallation).

You do **not** need temporary permission each time you use installed `whas`
commands. They are native executables, and runtime
tests pass under ordinary `Restricted` policy without changing it.
This does not grant an AI agent permission to execute arbitrary `.ps1` files:
scripts it launches still follow the policy of the process running them.

Group Policy (`MachinePolicy` or `UserPolicy`) takes precedence over a
process-only option. The setup and command hosts also reject enforced
restrictive organisation policies. This method does not override those
restrictions or Windows application-control blocks.

See Microsoft's [execution-policy documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-5.1)
for process scope and policy precedence.

### TTS engine strategies

In graphical setup, select the device separately for each selected speech
engine under **Models & engines**. Chatterbox and F5 offer CPU and Prefer GPU;
Prefer GPU uses CUDA when a compatible NVIDIA GPU is detected and falls back
to CPU otherwise. Piper is CPU-only and has no device selector. The EXE accepts
`--tts-devices chatterbox-turbo=cuda,piper-tts=cpu` with `--voice` and the matching
`--tts-engine` selection. Source configuration uses `tts.deviceDefaults`, keyed
by engine ID; `tts.device` remains the fallback for engines without an override.
Selections are validated per engine. The internal `auto` value corresponds to
Prefer GPU and checks that engine's supported
devices and available hardware. Actual resolved devices are saved separately
in `tts/engines/ENGINE/runtime.json`. Changing setup choices does not convert an
already installed environment; existing device/environment checks still apply.

Chatterbox Turbo, Piper TTS and F5-TTS are bundled strategies. TTS packages are discovered from `tts/strategies/<id>/`; additional trusted packages can supply their own installation, backend and uninstall behavior. Source and standalone setup support explicit engine selection:

```powershell
.\install.ps1 -Voice -TtsEngine chatterbox-turbo
.\install.ps1 -Voice -TtsEngine piper-tts
.\install.ps1 -Voice -TtsEngine f5-tts
```

Chatterbox remains the default and supports CPU/CUDA and reference-WAV voice cloning. Piper is a lighter CPU-only option using a pre-trained English voice; it does not install PyTorch or support voice cloning. F5 supports CPU/CUDA and reference voices with a WAV plus an exact transcript; its pretrained weights are CC-BY-NC-4.0 (noncommercial use only). All three require Python 3.11 x64 and the Visual C++ runtime. Interactive setup offers the engine choice. Multiple engines may be installed; only one runs at a time. Select comma-separated engine IDs during setup, with the first as default. See [engine management](tts-strategies.md#manage-installed-engines) for adding, selecting and removing individual engines.

The main uninstaller coordinates the installed strategy's cleanup hook and ownership-based removal. Personal voice data is preserved. See [TTS strategy packages](tts-strategies.md) for the package contract, runtime layout, compatibility and licensing notices.

### Install the stack

For source scripts and builds, use the repository root. For a copied EXE, use
its containing directory. Choose one installation route below.

#### Interactive installation

Run:

```powershell
.\install.ps1
```

The installer prompts you to select the components you want.

#### Select components explicitly

Cloud agents only:

```powershell
.\install.ps1 -Cloud
```

Local agents only:

```powershell
.\install.ps1 -Local
```

Voice only:

```powershell
.\install.ps1 -Voice
```

Cloud and local agents:

```powershell
.\install.ps1 -Cloud -Local
```

All components:

```powershell
.\install.ps1 -Cloud -Local -Voice
```

To use a custom installation directory:

```powershell
.\install.ps1 -Cloud -Local -Voice -InstallPath 'D:\AI\AgentStack'
```

Specifying component switches selects those components without the interactive component-selection questions.

The installer still prompts before proceeding with installation.

#### Standalone executable setup

`whas-gui.exe` is the graphical entry point for first-run configuration,
everyday use, settings and removal. Its setup payload is embedded; no separate
setup EXE, source checkout or build tools are needed on the destination PC.
External prerequisites are still required for the selected features.

The repository includes the built `whas-gui.exe` at its root, so cloning or
**Code > Download ZIP** provides it alongside the PowerShell scripts. No build
is required: extract the ZIP and double-click the EXE. The adjacent
`whas-gui.manifest.json` records its source fingerprint and SHA-256 checksum.

For developer builds, use 64-bit Windows PowerShell 5.1:

```powershell
.\scripts\build-gui.ps1
```

This produces `dist\whas-gui.exe` using the Windows compiler; no .NET SDK is
required. Existing output is preserved. Copy a reviewed build to the destination
PC and double-click it. The application opens feature configuration before
installation and usage/settings after a complete installation. See the
[graphical application guide](gui.md) for prerequisite checks, adding features,
engine/runtime removal and complete removal in the same window.

The application embeds only declared application files and defaults as ordinary
.NET resources. User configuration and credentials are not packaged. It does
not load PowerShell profiles or change saved execution policies. Enforced
organisation policy still applies. Use the PowerShell scripts above for
terminal installation; the legacy developer `build-setup.ps1` console build
remains available for compatibility but is not required by the GUI.

#### Unsigned EXE and Windows warnings

The setup EXE and the command launchers it creates are unsigned. A downloaded
EXE may trigger Microsoft Defender SmartScreen's **Windows protected your PC**
warning, and Windows may show **Unknown publisher** when asking for elevation.
This means Windows has not established trust in the publisher or file; it does
not by itself establish whether the program is safe.

Only proceed with a file you built from reviewed source or obtained from a
project release you trust. For a release that supplies a SHA-256 checksum,
calculate the downloaded EXE's hash and compare it with the value published
for that exact version:

```powershell
Get-FileHash -LiteralPath .\whas-gui.exe -Algorithm SHA256
```

A matching checksum confirms the bytes match the published value; it is not a
publisher signature or a guarantee of safety. Do not run a file whose checksum
differs. For the repository's bundled EXE, compare against `executableSHA256`
in `whas-gui.manifest.json`. A versioned GitHub Release is not yet published.

An antivirus malware detection is different from an unsigned-publisher or
SmartScreen reputation warning. Do not restore a quarantined build, add an
antivirus exclusion or disable protection to run it; stop and report the finding.

If you trust and have verified the file, SmartScreen may offer **More info**
then **Run anyway**. That choice is not available under every policy. Smart
App Control or managed organisation policies may block unsigned setup or
installed command launchers entirely. Do not disable Windows protections or
change execution policy to work around a block; use a deployment route
approved for that machine.

See Microsoft's [SmartScreen documentation](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)
and [Smart App Control FAQ](https://support.microsoft.com/en-us/windows/security/threat-malware-protection/smart-app-control-frequently-asked-questions)
for how Windows treats unsigned applications.

#### What the installer does

Depending on the selected components, the installer:

- Loads and validates configuration.
- Checks the required external prerequisites.
- Creates a stack-specific OpenCode configuration.
- Configures the cloud and/or local agent models.
- Offers to download a missing Ollama source model.
- Creates or reuses a separate Ollama variant with the configured context window.
- Installs Windows PowerShell 5.1-specific agent instructions without discarding existing instructions.
- Installs `ps-read` and `ps-write` agent permissions.
- Registers the unified native `whas` launcher and compatibility launchers.
- Creates an isolated Python 3.11 environment for the selected TTS strategy.
- Selects supported CPU/CUDA execution for the chosen TTS strategy.
- Installs the selected TTS engine and its pinned dependencies and models.
- Verifies Python package compatibility and key package versions.
- Copies TTS service and command files into the installation directory.
- Registers native agent and TTS commands through the local user PATH.

Repeat installations attempt to reuse existing installations and preserve unrelated PowerShell profile content.

Changed installed files are backed up where supported.

#### Machine-local command registration

Agent and TTS commands are executable files in:

```text
%USERPROFILE%\.windows-hybrid-agentic-stack\bin
```

The installer adds this directory to the current user's local PATH. Refresh
PATH using the completion step below, or reopen the terminal application.
Existing terminal applications may retain the old PATH.

Registration lives outside AppData because packaged Windows applications can redirect AppData writes into their own private cache. The live test exposed this: the installer could see its executables while ordinary PowerShell could not. Keeping registration directly under the Windows user directory avoids that redirection; it also avoids a synced Documents profile. See Microsoft's [filesystem virtualization documentation](https://learn.microsoft.com/en-us/windows/msix/desktop/flexible-virtualization).

The adjacent `install-root.txt` selects the installation directory. `commands.json` records the executable hashes and whether registration added the user PATH entry. Repeat registration preserves unchanged files; changes to owned files receive backups. Unknown or modified executables are rejected instead of overwritten.

Fresh installation creates no PowerShell profile. A PC without a local installation receives no stack startup code through OneDrive. Each PC has its own executable registration and selected installation root. A missing component reports an error only when its command is invoked.

For upgrades, only legacy stack blocks marked `BEGIN/END WINDOWS HYBRID AGENTIC STACK` or `... STACK TTS` are removed from an existing profile. Original bytes are backed up. Unrelated text is preserved, and malformed markers stop migration. A profile containing only the removed blocks and whitespace is deleted instead of leaving an empty script that Restricted would still reject. Unrelated profiles can still produce their own startup errors under Restricted.

Each PC has one active root. Selecting another `-InstallPath` switches local registration and retains the previous installation. Continue specifying your custom path, or save it in `config/config.json`, when rerunning the installer; registration does not choose the installer's destination.

### Finish installation and check commands

Both source and EXE installations include the unified `whas` command and
`whas-gui.exe` for usage, configuration and graphical removal in the
installation folder. See [graphical workflows](gui.md) and
[shared CLI settings](cli.md). Opening setup without arguments shows its GUI;
explicit `--install`, `--check`, `--plan` and `--uninstall` retain console use.

Setup can select multiple local models and a separate default with
`-LocalModels`/`-DefaultLocalModel` or the equivalent EXE options. See
[local model selection](cli.md#local-model-selection). `-DefaultLocation` /
`--default-location` selects the initial local/cloud request route.

After either installation route completes, refresh PATH in your original
PowerShell window:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
```

Alternatively, close and reopen the terminal application. No profile reload
is required. The installer process cannot update its parent terminal's PATH.

Check which commands are available:

```powershell
Get-Command whas -CommandType Application -ErrorAction SilentlyContinue
```

Registration supplies the common command names; their presence does not mean
every component is installed. Use commands for your selected components. For
an actual response or speech test, continue with [ask, chat and perform](#use-whas-ask-chat-and-perform) and
[TTS commands](#tts-commands). Command discovery alone does not verify inference
or audio playback.

## Uninstallation

Follow this process when you want to remove an installed stack. Choose either
the source script or the standalone EXE; you do not need to run both.
Uninstall uses the installation's ownership record to identify what it can
remove. External prerequisites are separate applications and remain installed.

### Uninstall a tracked installation

From the repository root or the installed directory, preview removal first:

```powershell
.\uninstall.ps1
```

Preview does not stop services, change PATH or remove files. To apply the plan
with confirmation:

```powershell
.\uninstall.ps1 -Apply
```

#### Keep managed Ollama models if needed

Preview and applied uninstall include unchanged Ollama models created by this
installation by default. Original models, modified models and models needed by
another registered tracked installation are preserved.

To preview keeping the managed models instead:

```powershell
.\uninstall.ps1 -RetainManagedModels
```

Then apply that cleanup:

```powershell
.\uninstall.ps1 -Apply -RetainManagedModels
```

`-Apply` enables removal; `-RetainManagedModels` changes the model-retention
choice. Neither preview removes anything. The old `-RemoveManagedModels` flag
is accepted for compatibility but is redundant; combining it with the retain
flag is rejected. Use `-InstallPath 'D:\AI\AgentStack'` for a custom installation,
and `-Verbose` for individual file actions.

#### If execution policy blocks the uninstall script

After reviewing the source, use a temporary child-process permission instead.
Preview:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Apply, including eligible installer-created models:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -Apply
```

Or retain those models:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -Apply -RetainManagedModels
```

These commands leave saved execution policies unchanged. Enforced organisation
policies still apply; see [execution-policy guidance](#powershell-execution-policy).

### Uninstall with the graphical application

Open `whas-gui.exe` and use the top-right cog, then
**Configuration > Maintenance > Removal**. Preview removal, choose whether to retain installer-created
Ollama models, then confirm removal. This uses the same ownership checks,
strategy hooks and retention rules as the source uninstaller.

Normal graphical launch uses a temporary copy outside the installation, so its
installed executable can be removed safely. Close other installed WHAS windows
first. The application returns to first-run configuration after removal.

### What cleanup removes and preserves

The uninstaller verifies file hashes, stops only the matching speech launcher/worker, removes owned command registration and files, and restores original configuration bytes when the installed copy has not been edited. A previous command registration is restored when its installation still exists. Pre-existing models and changed model digests are preserved; a model referenced by another registered tracked installation is also retained.

Custom voices, added files, edited files, pre-existing virtual environments and unrelated software are preserved. Known generated speech logs, the last-spoken WAV and bytecode caches in a newly created private environment are removed. Preserved data can leave the installation directory and ownership record in place. A receipt lists removed, restored and retained items under `%USERPROFILE%\WHAS-UninstallReceipts`.

Older installations without `.whas-installation.json` require reviewed cleanup; the uninstaller does not assume ownership of their files. Source installer and maintenance scripts still require a context permitted to execute `.ps1` files. Neither uninstall nor its preview changes profiles or execution policies. Package updates made inside an already existing Python environment are not reversed. External caches, credentials and other machine state are outside its ownership record.

Separately installed OpenCode, Ollama, Python and Visual C++ are not removed.
File verification and cleanup of a large speech environment can take several
minutes. Progress reports the current phase, processed/total file counts and
elapsed time, including updates within large-file verification. Counts describe
the phase being processed, not an estimate of the total time remaining.
Redirected logs retain periodic plain-text messages.

### Refresh PATH and check removal

After uninstalling, reload PATH in the same PowerShell window, or close
and reopen the terminal application:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
```

Then check command removal:

```powershell
Get-Command whas -CommandType Application -ErrorAction SilentlyContinue
```

No output means the unified command is no longer discoverable. If uninstall
restored a previous installation's registration, its commands may still be
listed. Read the uninstall receipt for removed and retained files/models;
personal data can leave the installation directory in place.

## Use WHAS: ask, chat and perform

The [complete command and flag reference](cli.md#complete-command-and-flag-reference)
lists every WHAS request, speech and setup option. Run `whas --help` for
requests and `whas tts --help` or `tts-help` for speech help.


After installation, refresh PATH as described above or reopen your terminal
application. The unified interface is `whas`:

| Operation | Saved route | This PC | Cloud |
|---|---|---|---|
| One-off question, no file/system tools | `whas ask` | `whas askl` | `whas askc` |
| Contextual CLI conversation | `whas chat` | `whas chatl` | `whas chatc` |
| Task with file/system tools | `whas perform` | `whas performl` | `whas performc` |

`ask` answers without file tools; `chat` keeps conversation context; `perform`
can use files and system tools. Choose the working folder before running a
task. For example, from a folder where you want a notes file:

```powershell
whas askc "Explain the difference between RAM and storage"
```

```powershell
whas askl "What is 2 plus 2?"
```

```powershell
whas performl "Create notes.txt in the current directory containing Hello"
```

```powershell
whas chatc --no-voice
```

CLI conversations use OpenCode's interactive interface and native session
history. The GUI has its own Conversation mode: on This PC it sends message
history directly to Ollama, without file tools or OpenCode startup. Only
Run a task receives the saved workspace folders and file/system tools. See
[conversations and sessions](agent-strategies.md#sessions-and-memory).

### Agent options

| Option | Behaviour |
|---|---|
| `--local`, `--cloud` | Override the saved route; equivalent to the `l`/`c` suffix |
| `--runtime ID` | Override the runtime for this request |
| `--model MODEL` | Override the model for this request |
| `--log` | Show native OpenCode events for one-off questions and tasks |
| `--voice`, `--no-voice` | Enable or disable speech for one-off questions and tasks |
| `--session ID` | Continue a registered CLI chat session |
| `--new` | Start a new CLI chat, the default |

Use an installed model, for example:

```powershell
whas askl --model ollama/qwen2.5:1.5b "What is 2 plus 2?"
```

```powershell
whas performl --log "Report total system RAM in GB"
```

`whas --help` lists the unified interface. Session options only apply to chat;
interactive CLI chat does not support speech, so use `--no-voice` when speech
is enabled in your saved defaults. For settings and the differences from the
older launchers, see [CLI reference](cli.md).

### Speaking agent responses

```powershell
whas askc --voice "Explain gravity in one sentence"
```

```powershell
whas askl --voice "What is 2 plus 2?"
```

`--voice` uses the selected engine's saved voice; it does not take a voice
name. To save a custom voice for an engine after adding it:

```powershell
whas configure --set speech.voice myvoice --engine chatterbox-turbo
```

Choose the default engine separately with `whas tts default chatterbox-turbo`.
GUI **Speak the answer** also works for completed Conversation replies.
Speech startup, synthesis and playback can take time independently of text
generation. A speech failure does not discard the displayed GUI answer.

### Agent permissions

Questions and conversations have no file or system tools. OpenCode requests
use a managed `whas-chat` profile with tools denied; GUI local chat talks to
Ollama directly. Use `perform` or **Run a task** to inspect live system state,
read files or make changes. These tasks use `ps-write` and OpenCode's permission
system, not an operating-system sandbox. Requests outside permitted folders
can require approval or be rejected.

The compatibility `agent`/`localagent` launchers retain their older read-only
`ps-read` behaviour. They are not exact permission-equivalent aliases for
`whas ask`; see [compatibility commands](cli.md#compatibility-commands).

Task instructions target Windows PowerShell 5.1 and direct the model to inspect
errors and verify results. They do not guarantee that a smaller local model
will always choose correct commands or obey every request.

### OpenCode configuration isolation

The project stores its own OpenCode configuration at:

```text
%USERPROFILE%\AI\WindowsHybridAgenticStack\opencode.json
```

This is separate from the user's global OpenCode configuration.

Agent commands temporarily use the stack-specific configuration and restore the previous environment setting afterward.

To list the cloud model IDs visible through the installed configuration:

```powershell
whas model catalog --cloud
```

Listing a model confirms configuration visibility, not successful model inference or authentication.

## TTS commands

Run `whas tts --help` or `tts-help` for speech commands and their flags.
There is no bare `tts` launcher. See the [speech flag reference](cli.md#speech-flags).


After voice installation, refresh PATH as described above or reopen your
terminal application.

The unified speech commands are below. Older `tts-*` launchers remain
available for [compatibility](cli.md#compatibility-commands).

| Command | Purpose |
|---|---|
| `whas tts start` | Start the selected speech engine |
| `whas tts stop` | Stop the selected speech engine |
| `whas tts status` | Display service status |
| `whas tts say` | Generate and play speech |
| `whas tts voice-list` | List locally cached voices |
| `whas tts voice-add` | Create a voice profile from a WAV reference |
| `whas tts voice-remove` | Remove a custom voice profile |
| `whas tts voice-test` | Test a custom voice |
| `whas tts list` | Show available, installed, default and active engines |
| `whas tts install` | Install another catalog engine |
| `whas tts uninstall` | Preview or apply removal of one engine |
| `whas tts default` | Show or set the saved default engine |

### Start and stop the service

```powershell
whas tts start
```

```powershell
whas tts status
```

```powershell
whas tts stop
```

When automatic startup is enabled, requesting speech starts the service if it is not already running.

The service listens on `127.0.0.1` and uses the configured port, defaulting to `18765`.

The default idle timeout is ten minutes. Speech and voice commands accept
`--engine ID`; without it they use the active engine, or the saved default when
stopped. Selecting another installed engine stops the previous service first.
See [engine management](tts-strategies.md#manage-installed-engines) and the
[Chatterbox](tts/chatterbox-turbo.md), [Piper](tts/piper-tts.md) and
[F5](tts/f5-tts.md) user guides.

### Generate speech

```powershell
whas tts say "Hello, this is a test of Chatterbox Turbo."
```

To specify a voice using PowerShell parameters:

```powershell
whas tts say -Text "Hello from my custom voice." -Voice "myvoice"
```

### Manage voices

List available voices:

```powershell
whas tts voice-list
```

Create a custom voice from a suitable WAV recording (Chatterbox; F5 also needs a matching transcript as described in [TTS strategies](tts-strategies.md); Piper uses its pre-trained voice):

```powershell
whas tts voice-add -Path 'C:\VoiceSamples\sample.wav' -Name 'myvoice' --engine chatterbox-turbo
```

Test a custom voice:

```powershell
whas tts voice-test myvoice --engine chatterbox-turbo
```

Adding or testing a voice does not select it for future answers. Save the
default voice for its engine explicitly, for example:

```powershell
whas configure --set speech.voice myvoice --engine chatterbox-turbo
```

This selects a voice for Chatterbox; it does not change the default engine.
Use `whas tts default chatterbox-turbo` to choose that separately.

Remove a custom voice:

```powershell
whas tts voice-remove myvoice --engine chatterbox-turbo
```

New installations store custom voices under `voices/ENGINE` inside the stack
installation. Recognized older Chatterbox layouts can retain their legacy paths.

The built-in `default` voice is reserved and cannot be removed.

**Only create voice profiles using recordings you have permission to use.**

## Troubleshooting

See [Troubleshooting](troubleshooting.md) for installation, PowerShell, Ollama, OpenCode and Chatterbox issues.

## Technical reference and historical tests

### Remove command registration on one PC

Stop any running TTS service with `whas tts stop`, then run from the repository root in a context permitted to run maintenance scripts:

```powershell
. .\scripts\command-registration.ps1
Unregister-StackCommands
```

This removes recognised executable commands and the user PATH entry only if registration added it. Changed executables cause cleanup to stop for review. Installation files, models, backups and unrelated PATH entries are retained. This is not a full uninstaller.

To register an existing compatible installation without reinstalling dependencies:

```powershell
. .\scripts\command-registration.ps1
Install-StackCommandRegistration -InstallPath 'D:\AI\AgentStack'
```

For a controlled fresh-install test, see [Installation test and rollback](install-test-rollback.md). Capture a baseline before installation and review cleanup targets before removing anything.

### Standalone setup tests

Run the isolated executable tests with:

```powershell
.\tests\test-setup-prototype.ps1
```

Tests cover portable embedded assets, poisoned sidecars, Restricted execution, literal paths, JSON validation, component selection, cancellation, prerequisite/child failures, interrupted cleanup and Git checkout protection. Dependency installation is mocked in isolated tests. A real full native install/uninstall cycle also passed all 35 checks, including cloud/local inference, CUDA speech and baseline restoration. See [controlled test and rollback procedure](install-test-rollback.md).

### Ownership performance measurements

Ownership hashing now streams bytes directly through SHA-256, uses filesystem path combination after validating relative paths, classifies generated files once per plan and avoids repeatedly copying the growing deletion receipt. Full plan revalidation and the hash check immediately before each file removal remain in place. Ordinary owned files still reject concurrent writers; recognized generated logs support shared reads until speech stops.

On the reference PC in Windows PowerShell 5.1, an isolated fixture of 2,000 files of 4 KiB each plus one 64 MiB binary produced these historical timings, comparing the earlier implementation with the optimized implementation. The original commit IDs predate the repository history cleanup and are no longer resolvable here:

| Operation | Before | After |
| --- | ---: | ---: |
| Hash all fixture files | 3.71 s | 0.70 s |
| Record installation ownership | 3.64 s | 1.23 s |
| Preview uninstall | 5.08 s | 1.99 s |
| Apply uninstall | 17.77 s | 7.68 s |

The measured cleanup improvement was about 2.3 times. A larger optimized fixture of 46,641 small files plus one 64 MiB binary also completed: hashing 12.40 s, ownership recording 24.30 s, preview 35.33 s and cleanup 165.76 s. These fixtures measure file-count overhead; they do not reproduce the bytes, disk throughput or running services of a complete CUDA installation. Full cleanup can still take several minutes.

That optimized revision subsequently passed a full physical-PC cloud/local/CUDA voice installation and installed-CLI uninstall. Cloud and local inference succeeded, the user confirmed audible speech, and all 35 checks passed after classifying a transient installer pip worker separately from unrelated processes. The installed preview took 51.01 s; applying the installed uninstaller took 267.93 s, including plan creation and revalidation, and removed 46,685 files and only the test-created model. The installed helpers matched that revision's source, speech was stopped by uninstall, and the user confirmed clean startup in a new PowerShell window afterward. No helper patching or separate speech shutdown was needed. These are historical results, not a test of the current GUI. See [controlled test and rollback procedure](install-test-rollback.md).

Reproduce the measurements without installing components, starting services, downloading models or changing persistent PATH:

```powershell
.\tests\measure-installation-performance.ps1
.\tests\measure-installation-performance.ps1 -FileCount 46641
```

Each run creates its own temporary fixture, verifies ownership and cleanup, removes its tracked installation and retains a JSON timing report and receipt. The small fixture is the default. Use `-OutputPath` to choose an absolute JSON destination, or `-SourceRoot` to benchmark helpers from another checkout.

### Isolated command and installer tests

Run these in Windows PowerShell 5.1 from a context permitted to run test scripts:

```powershell
.\tests\test-command-registration.ps1
.\tests\test-command-background.ps1
.\tests\test-profile-loader.ps1
.\tests\test-profile-integration.ps1
.\tests\test-uninstall.ps1
```

Tests use temporary directories and fixture profiles, retaining evidence at the printed paths. They leave the real user profile, persistent PATH and execution policies unchanged. Native command tests run children with Restricted policy and check arguments, voice confirmation, custom roots, repeat registration, simulated PCs and unregistering. Legacy migration tests check exact backups and unrelated profile preservation. Integration tests run real installer orchestration and wrappers with dependency installation, model setup, inference and audio mocked.

The background-process test checks that a command returns and captured output reaches EOF while its service remains running. Native speech startup creates a hidden process with handle inheritance disabled; the Python service opens its own logs before loading dependencies.

`-PersistCommandPath $false` on the root installer, or `-PersistPath $false` on the registration helper, suppresses persistent PATH changes for isolated testing. Production installation uses the default `$true`.

The native command path passed live installation, fresh-terminal discovery, cloud/local inference and audible CUDA speech on the reference PC. Live testing exposed and fixed AppData redirection and a background-service pipe inheritance issue. Controlled rollback of the revised installation passed all 90 checks, including exact PATH restoration, clean startup, removal of owned files and preservation of original model digests. The user also confirmed clean PowerShell startup without profile errors on a second physical PC.

### Chatterbox Python environment

Use the root installer so the environment, strategy package and model copy are ownership-tracked:

```powershell
.\install.ps1 -Voice -TtsEngine chatterbox-turbo
```

The shared coordinator is `tts/install-tts.ps1`; the engine-specific dependency installer lives in `tts/strategies/chatterbox-turbo/install.ps1`. Component/hook scripts are not fresh-install entry points.

Set `tts.device` in your local configuration to `cpu`, `cuda` or `auto` before installation. New environments live under `tts/engines/chatterbox-turbo/.venv`; recognized legacy installations retain their existing environment path. See `tts/runtime.json` in the installation for the actual layout.

The initial reference dependency versions include:

| Package | Version |
|---|---|
| Chatterbox TTS | 0.1.7 |
| PyTorch | 2.6.0 |
| TorchAudio | 2.6.0 |
| TorchVision | 0.21.0 |
| Transformers | 5.2.0 |
| Diffusers | 0.29.0 |
| NumPy | 1.26.4 |

The CPU and CUDA PyTorch installations use different wheel indexes but matching package versions.

Packaging tools are updated only inside the stack's virtual environment. The installer retains `setuptools<81` for the published `resemble-perth==1.0.1` dependency and explicitly verifies its watermarking implementation. CUDA wheels use an explicit `+cu126` build suffix, with PyPI available for general dependencies.

### Historical uninstall validation

The uninstaller has passed isolated Windows PowerShell 5.1 tests, mocked installer integration and live cloud-only and local/voice cleanup tests. The cloud cycle passed 20 checks. The local/voice test exposed and fixed open-log hashing, Numba cache recognition and a speech-process exit race; after a successful shutdown-helper retest, the corrected repository uninstaller removed 46,685 files and the test-created model. All 28 post-cleanup checks passed, including exact PATH restoration, clean normal-profile startup, unchanged profiles/policies and original model digests, and preservation of 12 unrelated Python processes. The earlier 90-check rollback used the supervised procedure. See [controlled test and rollback procedure](install-test-rollback.md).

### Historical testing status

The following records describe earlier development milestones, including limitations at the time. They are not a current coverage summary. Later Piper and F5 CPU/CUDA validation is described in [TTS strategy packages](tts-strategies.md).

The project has been tested incrementally using Windows Sandbox and a reference Windows 11 machine. The full installation on 15 October 2026 used the previous profile loader. Subsequent physical-PC testing exposed Restricted-policy startup errors from a synced profile, so registration now uses local executable commands. The revised native registration subsequently passed live fresh-terminal discovery, cloud/local inference and audible CUDA speech. Seven isolated Windows PowerShell 5.1 test suites cover registration, background process lifetime, legacy migration, installer orchestration, tracked uninstall, standalone setup and native-tool stderr/exit handling. Earlier Sandbox results retain their original context below.

| Feature | Status |
|---|---|
| Python 3.11 environment creation | Passed |
| TTS environment repeat installation | Passed |
| CPU PyTorch installation | Passed |
| Chatterbox dependency installation | Passed |
| Python dependency compatibility | Passed |
| Chatterbox Turbo import | Passed after installing Visual C++ Redistributable |
| TTS PowerShell command registration | Passed |
| Native executable registration idempotence | Passed in isolated tests |
| Agent-to-TTS integration | Passed through native launchers; user confirmed hearing both cloud and local responses |
| Full TTS model loading in 4 GB Sandbox | Failed due to insufficient committed memory |
| Actual CPU speech generation | Not yet verified |
| CUDA installation and speech generation | Passed through native launchers on a CUDA-capable NVIDIA GPU with PyTorch 2.6.0+cu126 |
| Cloud model authentication and inference | Passed in the latest reference-machine smoke test; installer does not verify authentication/inference |
| Managed 16K Ollama model creation and selection | Passed in Windows Sandbox with Qwen3 8B |
| Local agent executing `Get-Date` | Passed |
| Local agent reporting total RAM (16 GB Sandbox) | Passed |
| Exact local-agent file contents | Passed |
| Local read-only agent refusal and independent file absence | Passed |
| Local-agent installation repeat run | Passed |
| Native commands under Restricted, custom roots, simulated PCs and cleanup | Passed in isolated Windows PowerShell 5.1 tests; persistent user PATH unchanged |
| Root/agent installer registration and all 12 executable entry points | Passed in isolated Windows PowerShell 5.1 integration tests with dependency/model setup mocked |
| Standalone EXE install/uninstall under Restricted | Passed a real cloud/local/CUDA voice cycle and all 35 final restoration checks; seven isolated suites also passed |
| Agent lazy TTS loading with custom root | Passed with real wrappers and mocked inference/HTTP/audio |
| Second-PC PowerShell startup after the redesign | Passed: user confirmed no profile errors when opening a fresh window |
| Previous profile sync between physical PCs | Matching profile hash confirmed; Restricted blocked startup, prompting the native registration redesign |
| Full installation after profile-sync changes | Passed from an absent target; all 12 commands loaded in a fresh real-user session; original model digests and persistent policies unchanged |
| Live native command installation, fresh terminal and audible cloud/local voice | Passed after fixing AppData redirection and background pipe inheritance; profile absence, original models and policies preserved |
| Native service launch with captured command output | Passed regression test and real voice startup; command returns while service remains running |
| Controlled native-install rollback | Passed all 90 automatic checks: test files/registration/model removed; exact PATH, profile state, policies and original model digests restored; no TTS processes or startup commands remained |
| Controlled real-install rollback (previous profile design) | Passed: original profile bytes, backup inventory, four original model digests and persistent policies matched baseline; test installation/registration removed; fresh-session startup verified |

Passing the installation and import checks does not mean speech generation has been fully validated.

