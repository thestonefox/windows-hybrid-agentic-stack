# Windows Hybrid Agentic Stack

A configurable Windows AI agent toolkit combining local language models, cloud AI models, agent orchestration, and local text-to-speech.

The project provides PowerShell commands for interacting with cloud and local AI agents, running agent-assisted tasks, and optionally speaking responses using Chatterbox Turbo, Piper TTS or F5-TTS.

> **Development status:** Native command registration passed a live Windows 11 installation test, fresh-terminal command discovery, cloud/local inference and CUDA speech, with both responses confirmed audible. Profiles and execution policies remained unchanged. Isolated Windows PowerShell 5.1 tests also pass under Restricted. Controlled rollback also passed: exact user PATH, profile state, policies and original model digests matched the baseline. The user also confirmed that a second physical PC starts PowerShell without profile errors.

## Features

The stack combines four components:

- **Local AI — [Ollama](https://ollama.com/):** Run language models locally.
- **Cloud AI — OpenCode providers:** Access your chosen cloud provider through OpenCode.
- **Agent orchestration — [OpenCode](https://opencode.ai/):** Run AI agents with separate read-only and write-capable permissions.
- **Text-to-speech — [Chatterbox](https://github.com/resemble-ai/chatterbox), [Piper](https://github.com/OHF-Voice/piper1-gpl) or [F5-TTS](https://github.com/SWivid/F5-TTS):** Generate speech locally with the selected engine. Chatterbox supports reference-WAV voices; F5 also requires a transcript.

Components can be installed independently or in combination.

The project supports:

- Configurable cloud and local agent models.
- Installer-managed Ollama context windows (16,384 tokens by default).
- Four PowerShell agent commands.
- Read-only and write-capable agent modes.
- Optional spoken agent responses.
- Custom Chatterbox voice profiles and F5 WAV-plus-transcript voices.
- CPU speech with all three engines, plus automatic CPU/NVIDIA CUDA selection for Chatterbox and F5.
- On-demand TTS service startup and configured idle shutdown.
- Stack-specific OpenCode configuration.
- Isolated Python environments for the selected TTS strategy.
- Repeat installations that preserve existing configuration and profile content.

## Requirements

The project targets **Windows 10/11 and Windows PowerShell 5.1**.

| Component | Requirements |
|---|---|
| Cloud agents | OpenCode and authentication for your chosen provider |
| Local agents | OpenCode, Ollama, and a downloaded local model |
| Text-to-speech | Python 3.11 (64-bit) and Microsoft Visual C++ Redistributable (x64) |
| NVIDIA-accelerated TTS | Compatible NVIDIA GPU and driver |

You only need the prerequisites for the components you intend to install.

Cloud-only agents do not require Python or Ollama. Voice-only installation does not require OpenCode or Ollama.

The project installer manages the selected TTS strategy's private Python environment, model and dependencies: PyTorch for Chatterbox/F5, or CPU ONNX Runtime for Piper. External applications such as Python, OpenCode, and Ollama must be installed separately.

## Installing prerequisites

We recommend **Windows Package Manager (WinGet)** for external application installation.

The project does not require users to install npm, Scoop, Chocolatey, Visual Studio, or the CUDA Toolkit for its standard setup.

### 1. Check WinGet

Open Windows PowerShell and run:

```powershell
winget --version
```

If WinGet is unavailable, follow Microsoft's [WinGet installation instructions](https://learn.microsoft.com/en-us/windows/package-manager/winget/).

Windows Sandbox may require additional WinGet setup.

### 2. Install Python 3.11 (TTS only)

The bundled TTS strategies require a compatible Python installation. The project's tested reference is **64-bit Python 3.11**.

Install it using:

```powershell
winget install --id Python.Python.3.11 --exact --source winget
```

Open a new PowerShell window and verify:

```powershell
py -3.11 --version
```

You can also list installed Python versions:

```powershell
py -0p
```

The TTS installer uses Python 3.11 to create a separate virtual environment inside the selected stack installation directory.

It does not install TTS packages into your global Python installation.

### 3. Install Microsoft Visual C++ Redistributable (TTS only)

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

### 4. Install OpenCode (cloud or local agents)

Install the OpenCode CLI:

```powershell
winget install --id SST.opencode --exact --source winget
```

Open a new PowerShell window and verify:

```powershell
opencode --version
```

See the [OpenCode website](https://opencode.ai/) for documentation.

### 5. Install Ollama (local agents only)

Install Ollama:

```powershell
winget install --id Ollama.Ollama --exact --source winget
```

Open a new PowerShell window and verify:

```powershell
ollama --version
```

List downloaded models:

```powershell
ollama list
```

The built-in local model default is `qwen3:8b`. The installer checks whether the configured model is available and offers to download it if necessary.

To download the default model manually:

```powershell
ollama pull qwen3:8b
```

You can configure another model in `config/config.json`. During local-agent installation, the installer creates a separate context-enabled variant of the selected Ollama model instead of modifying the source model. See [Local Ollama context size](#local-ollama-context-size).

### 6. Configure provider authentication (cloud agents only)

Cloud agents use the provider and model selected in OpenCode.

Launch OpenCode:

```powershell
opencode
```

Follow its provider authentication instructions.

Use `/connect` to connect your provider and `/models` to select an available model. Signing in alone does not guarantee a particular model selection.

Model availability and billing depend on your provider account and authentication method.

The installer leaves OpenCode model selection unchanged by default. It does not authenticate your account or guarantee model access.

### 7. NVIDIA GPU drivers (optional TTS acceleration)

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

## Prerequisite checks

The prerequisite checker reports detected software and potential compatibility issues.

Check all components:

```powershell
.\scripts\check-prerequisites.ps1 -Cloud -Local -Voice
```

Or check components independently:

```powershell
.\scripts\check-prerequisites.ps1 -Cloud
```

```powershell
.\scripts\check-prerequisites.ps1 -Local
```

```powershell
.\scripts\check-prerequisites.ps1 -Voice
```

The checker uses the following result categories:

| Result | Meaning |
|---|---|
| `PASS` | A prerequisite was detected successfully |
| `WARN` | A potential issue requires attention |
| `FAIL` | A required prerequisite is missing or a check failed |
| `INFO` | Additional information or verification is required |

A successful prerequisite check does not guarantee successful cloud authentication, model inference, or TTS generation.

## Configuration

The project includes built-in defaults in:

```text
config/defaults.json
```

You can optionally override individual settings using:

```text
config/config.json
```

The user-specific configuration file is excluded from Git.

### Create a configuration file

Copy the example:

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

### Cloud model selection

`agent` and `agentdo` use OpenCode model selection by default: its configured model, then its last-used model, then its own fallback. The wrapper does not choose a provider based on login. `--model provider/model` overrides one invocation.

For a persistent stack override, set `agents.cloud.model` to a fully qualified `provider/model` ID. The optional `agents.cloud.provider` supports shorter model names. Both default to `null`; local commands continue to select their configured Ollama model explicitly.

Existing explicit stack settings are preserved. To inherit OpenCode selection, set `agents.cloud.model` to `null` in your stack configuration. Older installations may also have a `model` entry in the installation directory's `opencode.json`; remove that entry if it is the old stack default you no longer want. Reinstalling preserves existing model entries rather than guessing whether they are personal choices.

### Local Ollama context size

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

When `-Local` is selected, the installer checks for the original Ollama model and creates a **separate managed model** whose Modelfile includes `PARAMETER num_ctx 16384`. For `qwen3:8b`, the generated name is `whas-qwen3-8b-ctx16384`. `localagent` and `localagentdo` use that model automatically; the original `qwen3:8b` remains unchanged.

The generated name is based on the exact configured source model and context size. For example, choosing the already customised source `qwen3-8b-16k` produces `whas-qwen3-8b-16k-ctx16384`. Prefer selecting the original model when no other customisations are needed.

To inspect the generated model:

```powershell
ollama show whas-qwen3-8b-ctx16384 --modelfile
```

Look for `PARAMETER num_ctx 16384`. You can also use `ollama list` to see available models. Re-running the installer reuses an existing managed model when its context setting matches; it refuses to overwrite a same-named model with conflicting parameters. Changing the source model or context size requires rerunning `.\install.ps1 -Local` to update the installed agent configuration.

### Inspect configuration

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

### Installation directory

The default installation directory is:

```text
%USERPROFILE%\AI\WindowsHybridAgenticStack
```

You do not need to specify this path when running the installer.

The installation directory can be overridden through `config/config.json` or the root installer's optional `-InstallPath` parameter.

The root installer passes the selected directory to individual components so they use the same installation.

## PowerShell execution policy

Installed commands are native console applications built locally with Windows PowerShell 5.1's bundled compiler. They host the stack's PowerShell command code through Microsoft's [PowerShell hosting API](https://learn.microsoft.com/en-us/powershell/scripting/developer/hosting/adding-and-invoking-commands?view=powershell-7.2), without loading profiles or setting execution policies. Runtime tests pass with the caller's effective policy remaining Restricted. Enforced organisation policies are checked and restrictive settings cause an explicit error.

The source installer and maintenance scripts are still `.ps1` files and require a context that permits running those scripts. The installer does not configure execution policy or offer to change it. The standalone setup EXE can install and uninstall the stack under Restricted without changing execution policy, as described below.

## Installation

Open Windows PowerShell in the repository root.

### Standalone executable setup

Build with 64-bit Windows PowerShell 5.1 in a context permitted to run the build script:

```powershell
.\scripts\build-setup.ps1
```

This uses the Windows compiler and creates `dist\whas-setup.exe`. No .NET SDK is required. Existing output is preserved unless `-Force` is supplied. The generated `dist` directory is ignored by Git. Copy the EXE to the destination PC and keep it outside the installation directory for later uninstall.

```powershell
.\dist\whas-setup.exe --help
.\dist\whas-setup.exe --plan --cloud --local --voice
.\dist\whas-setup.exe --check --cloud --local --voice
.\dist\whas-setup.exe --install --cloud --local --voice
```

Explicit component flags select only those components. Without component flags, plan/check/install use the bundled defaults (all three enabled). Installation asks for confirmation; `--yes` accepts that confirmation. Missing local source models still require download confirmation. `--config 'C:\path\settings.json'` reads JSON overrides, and `--install-path 'D:\AI\AgentStack'` selects the destination. Prerequisites must already be installed; setup does not install OpenCode, Ollama or Python itself.

The EXE embeds application scripts, agent instructions, the speech service and `config/defaults.json`. User configuration and credentials are not packaged. Help, preview and prerequisite checks run from memory. Install/uninstall extract the compiled assets to a unique temporary directory, host the bundled code, then remove only those known assets and empty temporary directories. Loose scripts beside the EXE are ignored. Profiles are not loaded or changed, and saved execution policies are not changed. Restrictive enforced organization policy stops setup.

Use the same EXE to preview or apply tracked cleanup:

```powershell
.\dist\whas-setup.exe --uninstall
.\dist\whas-setup.exe --uninstall --apply
.\dist\whas-setup.exe --uninstall --apply --remove-managed-models
```

Uninstall resolves the active local registration, or accepts `--install-path`. `--apply` requests confirmation; add `--yes` to accept it. Model removal is opt-in and includes only unchanged models created by this installation. Changed files, custom voices, pre-existing environments and unrelated tools/models are preserved. `--no-path` leaves saved user PATH unchanged during install/uninstall. Keep that option consistent across a test cycle.

Run the isolated executable tests with:

```powershell
.\tests\test-setup-prototype.ps1
```

Tests cover portable embedded assets, poisoned sidecars, Restricted execution, literal paths, JSON validation, component selection, cancellation, prerequisite/child failures, interrupted cleanup and Git checkout protection. Dependency installation is mocked in isolated tests. A real full native install/uninstall cycle also passed all 35 checks, including cloud/local inference, CUDA speech and baseline restoration. See [live setup evidence](docs/install-test-rollback.md#verified-full-native-setup-and-cleanup).

### Interactive installation

Run:

```powershell
.\install.ps1
```

The installer prompts you to select the components you want.

### Select components explicitly

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

### What the installer does

Depending on the selected components, the installer:

- Loads and validates configuration.
- Checks the required external prerequisites.
- Creates a stack-specific OpenCode configuration.
- Configures the cloud and/or local agent models.
- Offers to download a missing Ollama source model.
- Creates or reuses a separate Ollama variant with the configured context window.
- Installs Windows PowerShell 5.1-specific agent instructions without discarding existing instructions.
- Installs `ps-read` and `ps-write` agent permissions.
- Registers PowerShell agent commands.
- Creates an isolated Python 3.11 environment for the selected TTS strategy.
- Selects supported CPU/CUDA execution for the chosen TTS strategy.
- Installs the selected TTS engine and its pinned dependencies and models.
- Verifies Python package compatibility and key package versions.
- Copies TTS service and command files into the installation directory.
- Registers native agent and TTS commands through the local user PATH.

Repeat installations attempt to reuse existing installations and preserve unrelated PowerShell profile content.

Changed installed files are backed up where supported.

### Machine-local command registration

Agent and TTS commands are executable files in:

```text
%USERPROFILE%\.windows-hybrid-agentic-stack\bin
```

The installer adds this directory to the current user's local PATH. Open a new terminal application after installation so it inherits the updated environment. Existing terminal applications may retain the old PATH.

Registration lives outside AppData because packaged Windows applications can redirect AppData writes into their own private cache. The live test exposed this: the installer could see its executables while ordinary PowerShell could not. Keeping registration directly under the Windows user directory avoids that redirection; it also avoids a synced Documents profile. See Microsoft's [filesystem virtualization documentation](https://learn.microsoft.com/en-us/windows/msix/desktop/flexible-virtualization).

The adjacent `install-root.txt` selects the installation directory. `commands.json` records the executable hashes and whether registration added the user PATH entry. Repeat registration preserves unchanged files; changes to owned files receive backups. Unknown or modified executables are rejected instead of overwritten.

Fresh installation creates no PowerShell profile. A PC without a local installation receives no stack startup code through OneDrive. Each PC has its own executable registration and selected installation root. A missing component reports an error only when its command is invoked.

For upgrades, only legacy stack blocks marked `BEGIN/END WINDOWS HYBRID AGENTIC STACK` or `... STACK TTS` are removed from an existing profile. Original bytes are backed up. Unrelated text is preserved, and malformed markers stop migration. A profile containing only the removed blocks and whitespace is deleted instead of leaving an empty script that Restricted would still reject. Unrelated profiles can still produce their own startup errors under Restricted.

Each PC has one active root. Selecting another `-InstallPath` switches local registration and retains the previous installation. Continue specifying your custom path, or save it in `config/config.json`, when rerunning the installer; registration does not choose the installer's destination.

### Remove command registration on one PC

Stop any running TTS service with `tts-stop`, then run from the repository root in a context permitted to run maintenance scripts:

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

For a controlled fresh-install test, see [Installation test and rollback](docs/install-test-rollback.md). Capture a baseline before installation and review cleanup targets before removing anything.

### Uninstall a tracked installation

New installations include an ownership record and a copy of `uninstall.ps1`. From the repository or the installed directory, preview removal:

```powershell
.\uninstall.ps1
```

Use `-InstallPath 'D:\AI\AgentStack'` to select a particular installation. Add `-Verbose` to list every file action. Preview does not stop services, change PATH or remove files. To apply the displayed plan with confirmation:

```powershell
.\uninstall.ps1 -Apply
```

All Ollama models are retained by default. To also remove unchanged models that this installation created:

```powershell
.\uninstall.ps1 -Apply -RemoveManagedModels
```

The uninstaller verifies file hashes, stops only the matching speech launcher/worker, removes owned command registration and files, and restores original configuration bytes when the installed copy has not been edited. A previous command registration is restored when its installation still exists. Pre-existing models and changed model digests are preserved; a model referenced by another registered tracked installation is also retained.

Custom voices, added files, edited files, pre-existing virtual environments and unrelated software are preserved. Known generated speech logs, the last-spoken WAV and bytecode caches in a newly created private environment are removed. Preserved data can leave the installation directory and ownership record in place. A receipt lists removed, restored and retained items under `%USERPROFILE%\WHAS-UninstallReceipts`.

Older installations without `.whas-installation.json` require reviewed cleanup; the uninstaller does not assume ownership of their files. Source installer and maintenance scripts still require a context permitted to execute `.ps1` files. Neither uninstall nor its preview changes profiles or execution policies. Package updates made inside an already existing Python environment are not reversed. External caches, credentials and other machine state are outside its ownership record.

The uninstaller has passed isolated Windows PowerShell 5.1 tests, mocked installer integration and live cloud-only and local/voice cleanup tests. The cloud cycle passed 20 checks. The local/voice test exposed and fixed open-log hashing, Numba cache recognition and a speech-process exit race; after a successful shutdown-helper retest, the corrected repository uninstaller removed 46,685 files and the test-created model. All 28 post-cleanup checks passed, including exact PATH restoration, clean normal-profile startup, unchanged profiles/policies and original model digests, and preservation of 12 unrelated Python processes. The earlier 90-check rollback below used the supervised procedure. See [test evidence and limitations](docs/install-test-rollback.md#verified-tracked-uninstaller-local-and-voice-test).

### Ownership performance measurements

Ownership hashing now streams bytes directly through SHA-256, uses filesystem path combination after validating relative paths, classifies generated files once per plan and avoids repeatedly copying the growing deletion receipt. Full plan revalidation and the hash check immediately before each file removal remain in place. Ordinary owned files still reject concurrent writers; recognized generated logs support shared reads until speech stops.

On the reference PC in Windows PowerShell 5.1, an isolated fixture of 2,000 files of 4 KiB each plus one 64 MiB binary produced these timings, comparing commit `0418803` with the optimized implementation:

| Operation | Before | After |
| --- | ---: | ---: |
| Hash all fixture files | 3.71 s | 0.70 s |
| Record installation ownership | 3.64 s | 1.23 s |
| Preview uninstall | 5.08 s | 1.99 s |
| Apply uninstall | 17.77 s | 7.68 s |

The measured cleanup improvement was about 2.3 times. A larger optimized fixture of 46,641 small files plus one 64 MiB binary also completed: hashing 12.40 s, ownership recording 24.30 s, preview 35.33 s and cleanup 165.76 s. These fixtures measure file-count overhead; they do not reproduce the bytes, disk throughput or running services of a complete CUDA installation. Full cleanup can still take several minutes.

The optimized code at commit `5307d7c` subsequently passed a full physical-PC cloud/local/CUDA voice installation and installed-CLI uninstall. Cloud and local inference succeeded, the user confirmed audible speech, and all 35 checks passed after classifying a transient installer pip worker separately from unrelated processes. The installed preview took 51.01 s; applying the installed uninstaller took 267.93 s, including plan creation and revalidation, and removed 46,685 files and only the test-created model. The installed helpers matched the committed source, speech was stopped by uninstall, and the user confirmed clean startup in a new PowerShell window afterward. No helper patching or separate speech shutdown was needed. See [full-cycle evidence](docs/install-test-rollback.md#verified-optimized-full-installation-cycle).

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

## Using the AI agents

After installation, open a new Windows PowerShell window.

The project provides four commands:

| Command | Model | Permissions |
|---|---|---|
| `agent` | Cloud | Read-only |
| `agentdo` | Cloud | Write-capable |
| `localagent` | Ollama | Read-only |
| `localagentdo` | Ollama | Write-capable |

Examples:

```powershell
agent "Explain the difference between RAM and storage"
```

```powershell
agentdo "Create a notes.txt file in the current directory"
```

```powershell
localagent "Explain this PowerShell script"
```

```powershell
localagentdo "Create a summary.txt file in the current directory"
```

### Agent options

All four commands support the same options:

| Option | Behaviour |
|---|---|
| `-m MODEL`, `--model MODEL` | Override the model for this invocation |
| `-l`, `--log` | Show full OpenCode output |
| `-h`, `--help` | Show usage information |
| `-v`, `--voice` | Speak the final answer using the selected engine |

Examples:

```powershell
localagent -m qwen3:0.6b "What is 2 plus 2?"
```

```powershell
agent --model openai/gpt-6-luna "Explain this error"
```

```powershell
localagent --log "Explain this PowerShell command"
```

```powershell
agentdo --help
```

### Speaking agent responses

To speak a response using the configured default voice:

```powershell
agent -v "Explain gravity"
```

```powershell
localagent -v "What is 2 plus 2?"
```

To select a custom voice:

```powershell
agent -v myvoice "Explain gravity"
```

The voice name comes immediately after `-v`, followed by the prompt.

Voice output can also be combined with full logging:

```powershell
localagent -v -l "What is 2 plus 2?"
```

The command displays the OpenCode events and passes the final answer to the selected speech engine.

**Native cloud and local voice commands generated valid 24 kHz WAV files, completed playback and returned normally on the reference machine. The user confirmed hearing both responses. Earlier profile-registration tests are retained as historical results.**

### Agent permissions

`ps-read` is designed for read-only interactions and denies command execution and file editing.

`ps-write` allows execution and editing within OpenCode's permission system.

Other OpenCode restrictions remain active. For example, an operation outside the working directory may require approval or be rejected.

The supplied agent instructions target Windows PowerShell 5.1 and do not depend on WSL, Git Bash, or PowerShell 7. They direct agents to prefer native Windows commands, inspect execution errors, verify results before claiming success, convert memory units correctly, and respect exact file-content requests.

These instructions improve reliability but do not guarantee that smaller local models will always choose correct commands or obey every request. Read-only protection is enforced through OpenCode agent permissions as well as being described in the instructions.

### OpenCode configuration isolation

The project stores its own OpenCode configuration at:

```text
%USERPROFILE%\AI\WindowsHybridAgenticStack\opencode.json
```

This is separate from the user's global OpenCode configuration.

Agent commands temporarily use the stack-specific configuration and restore the previous environment setting afterward.

To inspect the installed model configuration manually:

```powershell
$env:OPENCODE_CONFIG = Join-Path $HOME 'AI\WindowsHybridAgenticStack\opencode.json'
```

```powershell
opencode models
```

Listing a model confirms configuration visibility, not successful model inference or authentication.

## TTS commands

After voice installation, open a new Windows PowerShell window.

The installer registers the following commands:

| Command | Purpose |
|---|---|
| `tts-start` | Start the selected speech engine |
| `tts-stop` | Stop the selected speech engine |
| `tts-status` | Display service status |
| `tts-say` | Generate and play speech |
| `tts-voice-list` | List locally cached voices |
| `tts-voice-add` | Create a voice profile from a WAV reference |
| `tts-voice-remove` | Remove a custom voice profile |
| `tts-voice-test` | Test a custom voice |

### Start and stop the service

```powershell
tts-start
```

```powershell
tts-status
```

```powershell
tts-stop
```

When automatic startup is enabled, requesting speech starts the service if it is not already running.

The service listens on `127.0.0.1` and uses the configured port, defaulting to `18765`.

The default idle timeout is ten minutes.

### Generate speech

```powershell
tts-say "Hello, this is a test of Chatterbox Turbo."
```

To specify a voice using PowerShell parameters:

```powershell
tts-say -Text "Hello from my custom voice." -Voice "myvoice"
```

### Manage voices

List available voices:

```powershell
tts-voice-list
```

Create a custom voice from a suitable WAV recording (Chatterbox; F5 also needs a matching transcript as described in [TTS strategies](docs/tts-strategies.md); Piper uses its pre-trained voice):

```powershell
tts-voice-add -Path 'C:\VoiceSamples\sample.wav' -Name 'myvoice'
```

Test a custom voice:

```powershell
tts-voice-test myvoice
```

Remove a custom voice:

```powershell
tts-voice-remove myvoice
```

Custom voices are stored inside the stack installation's `voices` directory.

The built-in `default` voice is reserved and cannot be removed.

**Only create voice profiles using recordings you have permission to use.**

## TTS engine strategies

Chatterbox Turbo, Piper TTS and F5-TTS are bundled strategies. TTS packages are discovered from `tts/strategies/<id>/`; additional trusted packages can supply their own installation, backend and uninstall behavior. Source and standalone setup support explicit engine selection:

```powershell
.\install.ps1 -Voice -TtsEngine chatterbox-turbo
# Standalone: whas-setup.exe --install --voice --tts-engine chatterbox-turbo
.\install.ps1 -Voice -TtsEngine piper-tts
# Standalone: whas-setup.exe --install --voice --tts-engine piper-tts
.\install.ps1 -Voice -TtsEngine f5-tts
# Standalone: whas-setup.exe --install --voice --tts-engine f5-tts
```

Chatterbox remains the default and supports CPU/CUDA and reference-WAV voice cloning. Piper is a lighter CPU-only option using a pre-trained English voice; it does not install PyTorch or support voice cloning. F5 supports CPU/CUDA and reference voices with a WAV plus an exact transcript; its pretrained weights are CC-BY-NC-4.0 (noncommercial use only). All three require Python 3.11 x64 and the Visual C++ runtime. Interactive setup offers the engine choice. Only one engine is installed at a time; uninstall before switching engines.

The main uninstaller coordinates the installed strategy's cleanup hook and ownership-based removal. Personal voice data is preserved. See [TTS strategy packages](docs/tts-strategies.md) for the package contract, runtime layout, compatibility and licensing notices.

## Troubleshooting

See [Troubleshooting](docs/troubleshooting.md) for installation, PowerShell, Ollama, OpenCode and Chatterbox issues.

## Testing status

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

## Development

Development is carried out incrementally, with changes tested in Windows Sandbox before commits.

The project uses [Conventional Commits](https://www.conventionalcommits.org/) with scoped commit messages.

Future work includes signed executable distribution and further performance work for large voice environments.

## License

See [LICENSE](LICENSE) for licensing information.
