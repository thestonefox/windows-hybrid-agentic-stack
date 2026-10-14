# Windows Hybrid Agentic Stack

A configurable Windows AI agent toolkit combining local language models, cloud AI models, agent orchestration, and local text-to-speech.

The project provides PowerShell commands for interacting with cloud and local AI agents, running agent-assisted tasks, and optionally speaking responses using Chatterbox Turbo.

> **Development status:** This project is under active development. Cloud and local agent setup, PowerShell commands, Chatterbox dependency installation, and TTS command registration are implemented. Voice integration has been tested with a mock speech function. Actual speech synthesis and GPU inference still require end-to-end verification.

## Features

The stack combines four components:

- **Local AI — [Ollama](https://ollama.com/):** Run language models locally.
- **Cloud AI — [OpenAI](https://openai.com/):** Access cloud-hosted AI models.
- **Agent orchestration — [OpenCode](https://opencode.ai/):** Run AI agents with separate read-only and write-capable permissions.
- **Text-to-speech — [Chatterbox](https://github.com/resemble-ai/chatterbox):** Generate speech locally, with support for custom voice profiles.

Components can be installed independently or in combination.

The project supports:

- Configurable cloud and local agent models.
- Four PowerShell agent commands.
- Read-only and write-capable agent modes.
- Optional spoken agent responses.
- Custom Chatterbox voice profiles.
- Automatic CPU or NVIDIA CUDA selection for TTS.
- On-demand TTS service startup and configured idle shutdown.
- Stack-specific OpenCode configuration.
- Isolated Python environments for Chatterbox.
- Repeat installations that preserve existing configuration and profile content.

## Requirements

The project targets **Windows 10/11 and Windows PowerShell 5.1**.

| Component | Requirements |
|---|---|
| Cloud agents | OpenCode and suitable OpenAI authentication |
| Local agents | OpenCode, Ollama, and a downloaded local model |
| Text-to-speech | Python 3.11 (64-bit) and Microsoft Visual C++ Redistributable (x64) |
| NVIDIA-accelerated TTS | Compatible NVIDIA GPU and driver |

You only need the prerequisites for the components you intend to install.

Cloud-only agents do not require Python or Ollama. Voice-only installation does not require OpenCode or Ollama.

The project installer manages the Chatterbox Python virtual environment, PyTorch, and Python package dependencies. External applications such as Python, OpenCode, and Ollama must be installed separately.

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

Chatterbox requires a compatible Python installation. The project's tested reference is **64-bit Python 3.11**.

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

It does not install Chatterbox packages into your global Python installation.

### 3. Install Microsoft Visual C++ Redistributable (TTS only)

**Microsoft Visual C++ Redistributable 2015–2022 (x64) is required for Chatterbox Turbo on Windows.**

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

Install the redistributable, reopen PowerShell if necessary, and retry the Chatterbox installer.

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

You can configure another model in `config/config.json`.

### 6. Configure OpenAI authentication (cloud agents only)

Cloud agents use OpenCode to access OpenAI models.

Launch OpenCode:

```powershell
opencode
```

Follow its provider authentication instructions.

You need access to the model selected in the stack configuration.

Model availability and billing depend on your OpenAI account and authentication method.

The installer configures the model selection but does not authenticate your account or guarantee access to a particular cloud model.

### 7. NVIDIA GPU drivers (optional TTS acceleration)

Chatterbox can use CPU-only PyTorch or CUDA-enabled PyTorch.

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
      "model": "qwen3:8b"
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

Windows PowerShell may block script execution on systems with restrictive execution policies.

For a temporary override in the current PowerShell session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

This change is temporary and does not permit automatic profile loading in later sessions.

When installing agent commands, the installer may offer to configure `RemoteSigned` for the current user. It makes this change only after confirmation.

The installer does not intentionally override machine-wide or Group Policy restrictions.

Execution policies are not a security boundary. Only run scripts from sources you trust.

## Installation

Open Windows PowerShell in the repository root.

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
- Offers to download a missing Ollama model.
- Installs `ps-read` and `ps-write` agent permissions.
- Registers PowerShell agent commands.
- Creates an isolated Python 3.11 environment for Chatterbox.
- Automatically selects CPU or CUDA PyTorch when TTS is selected.
- Installs Chatterbox Turbo and its Python dependencies.
- Verifies Python package compatibility and key package versions.
- Copies TTS service and command files into the installation directory.
- Registers TTS commands in the current user's PowerShell profile.

Repeat installations attempt to reuse existing installations and preserve unrelated PowerShell profile content.

Changed installed files are backed up where supported.

### Chatterbox Python environment

The TTS installer is located at:

```text
tts/install-tts.ps1
```

It can also be run independently:

```powershell
.\tts\install-tts.ps1
```

To prepare only the Python virtual environment:

```powershell
.\tts\install-tts.ps1 -PrepareOnly
```

To force CPU installation:

```powershell
.\tts\install-tts.ps1 -Device cpu
```

To request CUDA installation explicitly:

```powershell
.\tts\install-tts.ps1 -Device cuda
```

For normal use, omit `-Device` so the installer uses the configured default of `auto`.

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
| `-v`, `--voice` | Speak the final answer using Chatterbox |

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

The command displays the OpenCode events and passes the final answer to Chatterbox.

**Voice integration has passed mock testing. End-to-end speech output has not yet been verified in the project installation.**

### Agent permissions

`ps-read` is designed for read-only interactions and denies command execution and file editing.

`ps-write` allows execution and editing within OpenCode's permission system.

Other OpenCode restrictions remain active. For example, an operation outside the working directory may require approval or be rejected.

The supplied agent instructions target Windows PowerShell 5.1 and do not depend on WSL, Git Bash, or PowerShell 7.

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

## Chatterbox TTS commands

After voice installation, open a new Windows PowerShell window.

The installer registers the following commands:

| Command | Purpose |
|---|---|
| `tts-start` | Start the Chatterbox service |
| `tts-stop` | Stop the Chatterbox service |
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

Create a custom voice from a suitable WAV recording:

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

## Troubleshooting

### PyTorch fails to load `c10.dll`

An error such as:

```text
OSError: [WinError 126] Error loading torch\lib\c10.dll
```

may indicate that Microsoft Visual C++ Redistributable (x64) is missing.

Install it using:

```powershell
winget install --id Microsoft.VCRedist.2015+.x64 --exact --source winget
```

Then reopen PowerShell and retry the installation or import.

### Chatterbox starts, then stops

Inspect the error log:

```powershell
Get-Content "$HOME\AI\WindowsHybridAgenticStack\tts\service-errors.log" -Tail 80
```

Inspect normal service output:

```powershell
Get-Content "$HOME\AI\WindowsHybridAgenticStack\tts\service.log" -Tail 40
```

These default paths assume the standard installation directory. Adjust them if you configured a custom location.

### Windows error 1455 during model loading

If the error log contains:

```text
OSError: The paging file is too small for this operation to complete.
(os error 1455)
```

Windows does not have enough available committed memory to load the model.

This occurred during testing in a Windows Sandbox instance with 4 GB RAM.

The Python packages installed correctly, but Chatterbox Turbo could not load its model.

Use a machine with sufficient available RAM and virtual memory. CPU inference may also be substantially slower than GPU inference.

### TTS commands are not recognised

Open a new Windows PowerShell window after installation.

Check the command registration:

```powershell
Get-Command tts-start,tts-stop,tts-status,tts-say
```

If commands are missing, check the current PowerShell profile and execution policy:

```powershell
Get-Content $PROFILE.CurrentUserCurrentHost
```

```powershell
Get-ExecutionPolicy -List
```

### CUDA is unavailable

Check your NVIDIA GPU:

```powershell
nvidia-smi
```

Check CUDA availability using the installed Python environment:

```powershell
& "$HOME\AI\WindowsHybridAgenticStack\.venv\Scripts\python.exe" -c "import torch; print('CUDA available:', torch.cuda.is_available())"
```

If CUDA is unavailable, verify your driver and installed PyTorch build.

### OpenCode commands are not recognised

Open a new PowerShell window and check:

```powershell
Get-Command agent,agentdo,localagent,localagentdo
```

Check your profile configuration:

```powershell
Get-Content $PROFILE.CurrentUserCurrentHost
```

If script execution is blocked, review [PowerShell execution policy](#powershell-execution-policy).

## Testing status

The project has been tested incrementally using Windows Sandbox.

| Feature | Status |
|---|---|
| Python 3.11 environment creation | Passed |
| TTS environment repeat installation | Passed |
| CPU PyTorch installation | Passed |
| Chatterbox dependency installation | Passed |
| Python dependency compatibility | Passed |
| Chatterbox Turbo import | Passed after installing Visual C++ Redistributable |
| TTS PowerShell command registration | Passed |
| TTS profile loader idempotence | Passed |
| Agent-to-TTS integration | Passed with mocked speech |
| Full TTS model loading in 4 GB Sandbox | Failed due to insufficient committed memory |
| Actual CPU speech generation | Not yet verified |
| CUDA installation and inference | Not yet verified |
| Cloud model authentication and inference | Not verified by installer |

Passing the installation and import checks does not mean speech generation has been fully validated.

## Development

Development is carried out incrementally, with changes tested in Windows Sandbox before commits.

The project uses [Conventional Commits](https://www.conventionalcommits.org/) with scoped commit messages.

Future work includes additional end-to-end TTS verification, CUDA testing, and uninstallation support.

## License

See [LICENSE](LICENSE) for licensing information.
