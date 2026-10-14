# Windows Hybrid Agentic Stack

A configurable Windows AI agent toolkit combining local language models, cloud AI models, agent orchestration, and GPU-accelerated text-to-speech.

The goal is to provide a straightforward way to set up a hybrid AI environment on Windows, with PowerShell commands for interacting with local and cloud models and optional spoken responses.

> **Development status:** This project is under active development. Prerequisite detection, configuration management, OpenCode/Ollama agent setup, and four PowerShell agent commands are implemented. Chatterbox installation, voice output, and uninstallation are still being developed.

## Features

The project is designed around four main components:

- **Local AI — [Ollama](https://ollama.com/)**: Run language models locally on your machine.
- **Cloud AI — [OpenAI](https://openai.com/)**: Access cloud-hosted AI models.
- **Agent orchestration — [OpenCode](https://opencode.ai/)**: Manage AI interactions, coding tasks, and tool execution.
- **Text-to-speech — [Chatterbox](https://github.com/resemble-ai/chatterbox)**: Generate speech locally, with support for custom voice profiles.

### Planned capabilities

- Independent setup of cloud and local agents; optional TTS installation is planned.
- Configurable agent model selection; TTS configuration is implemented but not yet applied to a service.
- PowerShell commands for cloud and local AI agents are implemented; spoken responses are planned.
- Automatic startup and idle shutdown of the TTS service.
- Runtime configuration changes where supported.
- Installation and uninstallation scripts.
- Local GPU acceleration for speech generation.

## Requirements

The project targets Windows 10/11 with Windows PowerShell 5.1 or later.

Depending on the components you choose, you will need:

| Component | Dependencies |
|---|---|
| Cloud agents | OpenCode and an OpenAI account with suitable model access |
| Local agents | OpenCode, Ollama, and downloaded local models |
| Text-to-speech | Compatible 64-bit Python installation and Chatterbox dependencies |
| GPU-accelerated TTS | Compatible NVIDIA GPU, graphics driver, and CUDA-enabled PyTorch |

You do not need to install every component. For example, cloud-only agents do not require Python or Ollama.

A future installer stage will manage TTS dependencies, including a Python virtual environment, PyTorch, Chatterbox packages, and service configuration. The current installer configures OpenCode and can download Ollama models.

**External applications such as Python, Ollama, and OpenCode must be installed by the user before running the project installer.**

## Installing prerequisites

Install the external software required for your chosen features before running the project's prerequisite checker or installer.

The recommended installation method is **Windows Package Manager (WinGet)**, which is normally included with current Windows 10 and Windows 11 installations through Microsoft's App Installer.

We do not require npm, Scoop, or Chocolatey.

### 1. Check WinGet

Open **Windows PowerShell** and run:

```powershell
winget --version
```

If a version is displayed, WinGet is available.

If the command is not recognised, follow Microsoft's official [WinGet installation instructions](https://learn.microsoft.com/en-us/windows/package-manager/winget/).

> **Windows Sandbox:** WinGet is not normally included in a fresh Sandbox environment. See the Microsoft documentation above for Sandbox-specific setup instructions.

### 2. Install Python (text-to-speech only)

Python is required for Chatterbox TTS. It is not required for text-only cloud or local agents.

Python 3.11 (64-bit) is our initial known-working reference for Chatterbox Turbo. Newer versions may be supported once their compatibility with Chatterbox and PyTorch has been verified.

Install Python 3.11 using WinGet:

```powershell
winget install --id Python.Python.3.11 --exact --source winget
```

Alternatively, download Python from the [official Python website](https://www.python.org/downloads/windows/).

After installation, **open a new PowerShell window** and verify:

```powershell
py --version
```

You can list Python installations using:

```powershell
py -0p
```

Chatterbox and PyTorch installation is not yet implemented in this project. Their dependencies will be managed in an isolated virtual environment in a later stage.

### 3. Install OpenCode (cloud or local agents)

OpenCode provides the AI agent framework used by this project.

Install the **OpenCode CLI** using WinGet:

```powershell
winget install --id SST.opencode --exact --source winget
```

This installs the command-line application, not the separate OpenCode desktop application.

Open a new PowerShell window and verify:

```powershell
opencode --version
```

For more information, visit the [OpenCode website](https://opencode.ai/).

OpenCode is required when using cloud or local AI agent features.

### 4. Install Ollama (local agents only)

Ollama allows language models to run locally on your computer.

Install Ollama using WinGet:

```powershell
winget install --id Ollama.Ollama --exact --source winget
```

Alternatively, download it from the [official Ollama website](https://ollama.com/download/windows).

Open a new PowerShell window and verify:

```powershell
ollama --version
```

To confirm the locally available models:

```powershell
ollama list
```

For example, you can download and run Qwen3 8B using:

```powershell
ollama run qwen3:8b
```

Qwen3 8B is the built-in default model, not a mandatory choice. You can select a different model in `config/config.json`. The installer checks for the selected model and offers to download it if missing.

You can skip Ollama if you only intend to use cloud agents.

### 5. Configure OpenAI access (cloud agents only)

Cloud agents use OpenCode to access remote AI models.

You will need an OpenAI account and a supported authentication method with access to your chosen model.

After installing OpenCode, launch it:

```powershell
opencode
```

Follow OpenCode's provider connection and authentication instructions.

Model selection is managed through this project's configuration. The installer creates a stack-specific OpenCode configuration; authentication and actual cloud model access must still be set up and verified separately.

Cloud AI may incur usage charges depending on your provider and authentication method.

You can skip this step if you intend to use local AI only.

### 6. NVIDIA drivers (GPU-accelerated TTS)

For NVIDIA GPU acceleration, ensure that you have a compatible GPU and an up-to-date graphics driver.

Download drivers from the [official NVIDIA website](https://www.nvidia.com/Download/index.aspx).

Verify that Windows recognises your NVIDIA GPU:

```powershell
nvidia-smi
```

If the command succeeds, it should display the GPU model, driver version, and memory information.

A separately installed CUDA Toolkit is not necessarily required. A later installer stage is intended to manage appropriate CUDA-enabled PyTorch packages where supported.

NVIDIA acceleration is optional in the prerequisite checker. CPU-based TTS compatibility and performance are not yet verified.

## Prerequisite checks

Once the external software for your selected components is installed, use the project's read-only prerequisite checker.

It identifies missing applications, reports installed versions, and highlights potential compatibility issues without modifying your system.

Check all components:

```powershell
.\scripts\check-prerequisites.ps1 -Cloud -Local -Voice
```

Check individual components:

**Cloud agents:**

```powershell
.\scripts\check-prerequisites.ps1 -Cloud
```

**Local agents:**

```powershell
.\scripts\check-prerequisites.ps1 -Local
```

**Text-to-speech:**

```powershell
.\scripts\check-prerequisites.ps1 -Voice
```

The checker reports:

- `PASS` — The prerequisite was detected successfully.
- `WARN` — A potential issue needs reviewing.
- `FAIL` — A required prerequisite is missing or a check failed.
- `INFO` — Additional setup or verification is required.

A successful prerequisite check does not guarantee that every software version or dependency combination is supported.

## Configuration

Configuration uses built-in defaults, so **no `config/config.json` file is required**.

The project loads settings from:

1. `config/defaults.json` — Built-in application defaults.
2. `config/config.json` — Optional user-defined overrides.

User configuration files only need to contain the settings you want to change. Everything else inherits its default value.

### Creating a configuration file

Copy the provided example:

```powershell
Copy-Item .\config\config.json.example .\config\config.json
```

Then edit `config/config.json` as needed.

For example, to change the TTS idle timeout:

```json
{
  "tts": {
    "idleTimeoutMinutes": 30
  }
}
```

An idle timeout of `0` is intended to disable automatic shutdown once the setting is integrated with the TTS service.

### Inspecting configuration

Display the effective configuration:

```powershell
.\scripts\config.ps1 -Show
```

Validate configuration:

```powershell
.\scripts\config.ps1 -Validate
```

You can also generate a complete configuration from the built-in defaults:

```powershell
.\scripts\config.ps1 -Init
```

The configuration system supports partial overrides, validates values, and rejects unknown settings.

The user-specific `config/config.json` file is excluded from Git.

**Note:** The installer uses configuration settings for selected components, installation directory, and agent models. TTS settings are validated but are not yet applied to a service.

## PowerShell execution policy

On a fresh Windows installation, PowerShell may block `.ps1` scripts with an error stating that script execution is disabled. The agent command installer creates a loader in the current user/current host Windows PowerShell profile. For the four functions to load in a normal new session, the execution policy must permit that profile to run.

For scripts you trust, enable execution in the current PowerShell session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

This applies only to the current session and does not permanently change your execution policy. It is useful for launching the installer, but **does not enable automatic profile loading in future sessions**.

Alternatively, run an individual script using:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\check-prerequisites.ps1"
```

During agent command installation, the installer checks persistent execution-policy settings. If normal profile loading would be blocked, it offers to set `RemoteSigned` for `CurrentUser`, and changes it **only with explicit confirmation**. It does not change the machine-wide policy or override Group Policy. If you decline, the profile loader may remain blocked.

`RemoteSigned` permits locally created scripts and imposes additional requirements on downloaded scripts; it is not a security boundary. Organisation-managed execution policies may prevent these overrides.

See [Troubleshooting](docs/troubleshooting.md) for additional information.

## Installation

> **Development status:** The installer configures cloud and local OpenCode agents, downloads selected Ollama models with confirmation, and installs four PowerShell agent commands. Chatterbox and voice support are not yet installed.

Before running the installer, follow the [prerequisite installation instructions](#installing-prerequisites) for your chosen components.

### Run the installer

From the repository root, open Windows PowerShell and run:

```powershell
.\install.ps1
```

The installer will prompt you to select cloud agents, local agents, text-to-speech, or a combination.

Alternatively, specify components directly:

```powershell
# Cloud agents only
.\install.ps1 -Cloud

# Local agents only
.\install.ps1 -Local

# Cloud and local agents
.\install.ps1 -Cloud -Local

# Select voice too (TTS setup is not yet implemented)
.\install.ps1 -Cloud -Local -Voice
```

To specify a custom installation directory:

```powershell
.\install.ps1 -Cloud -Local -InstallPath 'D:\AI\AgentStack'
```

If no installation directory is provided, the installer uses the configured directory or its built-in default.

### Current installer functionality

The installer currently:

- Loads `config/defaults.json` and optional `config/config.json` overrides.
- Allows interactive or command-line component selection.
- Resolves the installation directory and checks selected prerequisites.
- Stops when required prerequisites are missing, before configuring agents.
- Creates a stack-specific `opencode.json` for the chosen agent models.
- Checks for the selected Ollama model and asks before downloading it.
- Adds cloud or local agents to an existing stack configuration, preserving the other component and unrelated settings.
- Verifies that OpenCode lists the configured local model before saving changes.
- Backs up an existing OpenCode configuration when an update is needed; repeat runs leave unchanged configurations alone.
- Registers `ps-read` and `ps-write` with separate read-only and write-capable permissions and installs Windows PowerShell agent instructions.
- Copies agent command scripts and configuration into the chosen installation directory so the Git checkout is not needed for everyday command use.
- Adds an idempotent, marked loader to the current user/current host Windows PowerShell profile without removing unrelated profile content.
- Offers, with confirmation, to enable `RemoteSigned` for `CurrentUser` if normal profile loading is blocked.

OpenCode and Ollama must already be installed as external prerequisites. The installer **does not** install those applications, authenticate OpenAI, verify cloud inference, or install Chatterbox TTS. Selecting `-Voice` currently reports that TTS installation is not implemented.

### Using the stack-specific OpenCode configuration

The installer saves its OpenCode configuration at `opencode.json` inside the chosen installation directory. By default, this is:

```text
%USERPROFILE%\AI\WindowsHybridAgenticStack\opencode.json
```

To use it in the current PowerShell session:

```powershell
$env:OPENCODE_CONFIG = Join-Path $HOME 'AI\WindowsHybridAgenticStack\opencode.json'
opencode models
```

If you used `-InstallPath`, use the `opencode.json` in that directory instead.

This keeps the stack configuration separate from the user's global OpenCode configuration. The setting applies only to the current PowerShell session; the installed agent commands set `OPENCODE_CONFIG` while they run and restore its previous value afterwards.

`opencode models` confirms that OpenCode can load and list configured models. It does **not** guarantee successful inference or OpenAI authentication. Local inference also requires the Ollama service to be running.

### PowerShell agent commands

After installing cloud or local agents, open a **new Windows PowerShell 5.1 window**. The installer registers four functions in your PowerShell profile:

| Command | Model selection | OpenCode agent | Purpose |
|---|---|---|---|
| `agent` | Cloud | `ps-read` | Read-only cloud assistant |
| `agentdo` | Cloud | `ps-write` | Write-capable cloud assistant |
| `localagent` | Local (Ollama) | `ps-read` | Read-only local assistant |
| `localagentdo` | Local (Ollama) | `ps-write` | Write-capable local assistant |

The model defaults come from `config/config.json` (or built-in defaults) as copied into the installed runtime when the installer runs. Re-run the installer after changing the repository configuration to apply those overrides to the installed runtime. A command's provider must have been configured during installation; installing cloud-only does not download or configure a local model.

```powershell
agent "Explain the difference between RAM and storage"
agentdo "Create a notes.txt file in the current directory"
localagent "Explain this PowerShell script"
localagentdo "Create a summary.txt file in the current directory"
```

All four commands accept the same options:

| Option | Behaviour |
|---|---|
| `-m MODEL`, `--model MODEL` | Override the configured model for this invocation |
| `-l`, `--log` | Show full OpenCode execution output instead of only the final answer |
| `-h`, `--help` | Show usage and examples |
| `-v`, `--voice` | Reserved for future Chatterbox support; currently reports an error |

Examples:

```powershell
localagent -m qwen3:0.6b "What is 2 plus 2?"
agent --model openai/gpt-6-luna "Explain this error"
localagent --log "Explain this PowerShell command"
agentdo --help
```

By default the wrappers parse OpenCode JSON events and show the final text response. `--log` displays OpenCode's normal terminal output. The wrappers handle UTF-8 output and restore the prior console encoding after execution.

`ps-read` denies command execution and file editing; it can inspect supported files but cannot run PowerShell commands to retrieve live system information. `ps-write` permits execution and editing within OpenCode's other permission boundaries. Operations outside the working directory can still require permission and may be rejected during non-interactive runs. The agent instructions target Windows PowerShell 5.1 and do not depend on Git Bash, WSL, or PowerShell 7.

The installer uses the chosen installation directory for the runtime and adds a marked loader to the current user/current host PowerShell profile. It keeps unrelated profile content and avoids duplicate loaders on repeat installs. If a new PowerShell session doesn't recognise the commands, check the [execution-policy guidance](#powershell-execution-policy) and the current profile with `Get-Content $PROFILE`.

**Testing status:** Local inference, write operations, read-only restrictions, `--log`, Unicode output, repeat installation and profile loading have been tested in Windows Sandbox. Cloud authentication and inference are not yet verified by the installer.

If PowerShell blocks the installer, see [PowerShell execution policy](#powershell-execution-policy).

## Development

Development is carried out incrementally, with changes tested on an existing Windows installation and in a clean Windows Sandbox environment.

Actual GPU-accelerated TTS inference must also be tested on compatible hardware, as Windows Sandbox does not provide the same CUDA access as the host.

The project uses [Conventional Commits](https://www.conventionalcommits.org/) with scoped commit messages.

## License

See [LICENSE](LICENSE) for licensing information.
