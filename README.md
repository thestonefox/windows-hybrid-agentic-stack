# Windows Hybrid Agentic Stack

A configurable Windows AI agent toolkit combining local language models, cloud AI models, agent orchestration, and GPU-accelerated text-to-speech.

The goal is to provide a straightforward way to set up a hybrid AI environment on Windows, with PowerShell commands for interacting with local and cloud models and optional spoken responses.

> **Development status:** This project is under active development. Prerequisite detection, configuration management, and the installer preflight workflow are implemented. Automated component installation and agent/TTS integration are still being developed.

## Features

The project is designed around four main components:

- **Local AI — [Ollama](https://ollama.com/)**: Run language models locally on your machine.
- **Cloud AI — [OpenAI](https://openai.com/)**: Access cloud-hosted AI models.
- **Agent orchestration — [OpenCode](https://opencode.ai/)**: Manage AI interactions, coding tasks, and tool execution.
- **Text-to-speech — [Chatterbox](https://github.com/resemble-ai/chatterbox)**: Generate speech locally, with support for custom voice profiles.

### Planned capabilities

- Independent installation of cloud agents, local agents, and TTS.
- Configurable model selection and TTS behaviour.
- PowerShell commands for AI agents and spoken responses.
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

The installer will manage the project's own dependencies, including Python virtual environments, PyTorch, Chatterbox packages, and service configuration.

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

There is no need to install Chatterbox, PyTorch, or CUDA-enabled Python packages manually. The project installer will handle those dependencies in an isolated virtual environment.

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

Qwen3 8B is an example model, not a mandatory dependency. Model selection will be configurable.

You can skip Ollama if you only intend to use cloud agents.

### 5. Configure OpenAI access (cloud agents only)

Cloud agents use OpenCode to access remote AI models.

You will need an OpenAI account and a supported authentication method with access to your chosen model.

After installing OpenCode, launch it:

```powershell
opencode
```

Follow OpenCode's provider connection and authentication instructions.

Model selection will eventually be managed through this project's configuration.

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

A separately installed CUDA Toolkit is not necessarily required. The project installer will manage the appropriate CUDA-enabled PyTorch packages where supported.

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

Configuration uses built-in defaults, so **no `config.json` file is required**.

The project loads settings from:

1. `config/defaults.json` — Built-in application defaults.
2. `config.json` — Optional user-defined overrides.

User configuration files only need to contain the settings you want to change. Everything else inherits its default value.

### Creating a configuration file

Copy the provided example:

```powershell
Copy-Item .\config\config.json.example .\config.json
```

Then edit `config.json` as needed.

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

User-specific `config.json` files are excluded from Git.

**Note:** Configuration loading and validation are implemented. The installer, agent commands, and TTS service do not yet consume these settings.

## PowerShell execution policy

On a fresh Windows installation, PowerShell may block `.ps1` scripts with an error stating that script execution is disabled.

For scripts you trust, enable execution in the current PowerShell session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

This applies only to the current session and does not permanently change your execution policy.

Alternatively, run an individual script using:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\check-prerequisites.ps1"
```

Organisation-managed execution policies may prevent these overrides.

See [Troubleshooting](docs/troubleshooting.md) for additional information.

## Installation

> **Development status:** The installer currently supports component selection, configuration loading, and prerequisite checks. Actual installation of AI agents and text-to-speech is not yet implemented.

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

# Cloud and local agents with TTS
.\install.ps1 -Cloud -Local -Voice
```

To specify a custom installation directory:

```powershell
.\install.ps1 -Cloud -Local -InstallPath 'D:\AI\AgentStack'
```

If no installation directory is provided, the installer uses the configured directory or its built-in default.

### Current installer functionality

The installer currently:

- Loads built-in defaults and optional user configuration.
- Allows interactive or command-line component selection.
- Resolves the installation directory.
- Checks prerequisites for selected components.
- Reports missing dependencies and exits without modifying the system.

**The installer does not yet install or configure OpenCode, Ollama models, Chatterbox, or PowerShell agent commands.**

These features will be added as development progresses.

If PowerShell blocks the installer, see [PowerShell execution policy](#powershell-execution-policy).

## Development

Development is carried out incrementally, with changes tested on an existing Windows installation and in a clean Windows Sandbox environment.

Actual GPU-accelerated TTS inference must also be tested on compatible hardware, as Windows Sandbox does not provide the same CUDA access as the host.

The project uses [Conventional Commits](https://www.conventionalcommits.org/) with scoped commit messages.

## License

See [LICENSE](LICENSE) for licensing information.
