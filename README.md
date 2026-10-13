# Windows Hybrid Agentic Stack

A configurable Windows AI agent toolkit combining local language models, cloud AI models, agent orchestration, and GPU-accelerated text-to-speech.

The goal is to provide a straightforward way to set up a hybrid AI environment on Windows, with PowerShell commands for interacting with local and cloud models and optional spoken responses.

> **Development status:** This project is under active development. Prerequisite detection and configuration management are implemented. Automated installation, agent integration, and text-to-speech integration are still being developed.

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

Depending on the components you choose, you may also need:

| Component | Dependency |
|---|---|
| Cloud agents | OpenCode and an OpenAI account |
| Local agents | OpenCode and Ollama |
| Text-to-speech | Compatible Python installation and Chatterbox dependencies |
| GPU-accelerated TTS | Compatible NVIDIA GPU, driver, and CUDA-enabled PyTorch |

Python compatibility and GPU requirements will be documented more precisely as the TTS installer is developed and tested.

You do not need to install every component.

## Prerequisite checks

The project includes a read-only PowerShell checker to identify installed software and missing dependencies.

Check everything:

```powershell
.\scripts\check-prerequisites.ps1 -Cloud -Local -Voice
```

Check individual components:

```powershell
.\scripts\check-prerequisites.ps1 -Cloud
.\scripts\check-prerequisites.ps1 -Local
.\scripts\check-prerequisites.ps1 -Voice
```

The checker reports missing dependencies and compatibility warnings without modifying your system.

A successful detection check does not guarantee that every software version or dependency combination is supported.

## Configuration

Configuration uses built-in defaults, so **no `config.json` file is required**.

The project loads settings from:

1. `config/defaults.json` — Built-in application defaults.
2. `config.json` — Optional user-defined overrides.

User configuration files can contain only the settings you want to change. Everything else inherits its default value.

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

**Note:** Configuration loading and validation are implemented. The installer, agent commands, and TTS service do not yet consume these settings.

## PowerShell execution policy

On a fresh Windows installation, PowerShell may block `.ps1` scripts with an error stating that script execution is disabled.

For scripts you trust, enable execution in the current PowerShell session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

This does not permanently change your execution policy.

Alternatively, run an individual script using:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\check-prerequisites.ps1"
```

Organisation-managed execution policies may prevent these overrides.

See [Troubleshooting](docs/troubleshooting.md) for additional information.

## Installation

Automated installation is not yet available.

The planned installer will validate prerequisites, guide users through required software installation, configure selected components, and register PowerShell commands without overwriting existing user configuration.

Installation locations will be configurable rather than tied to a particular Windows user directory.

## Development

Development is being carried out incrementally, with changes tested on a configured Windows machine and in a clean Windows Sandbox environment.

The project uses [Conventional Commits](https://www.conventionalcommits.org/) with scoped commit messages.

## License

See [LICENSE](LICENSE) for licensing information.
