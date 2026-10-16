# Windows Hybrid Agentic Stack

A Windows AI toolkit for cloud and local agents, with optional local speech.
Use OpenCode with your chosen cloud provider, Ollama for local models, and
Chatterbox Turbo, Piper TTS or F5-TTS for text-to-speech.

Targets **Windows 10/11 and Windows PowerShell 5.1**. Install only the components
you need. Installed commands use native launchers and require no PowerShell
profile or execution-policy changes.

## Get started

- [Quickstart](docs/quickstart.md) — get the project, check prerequisites and run your first commands.
- [Installation guide](docs/installation.md) — detailed setup, configuration, usage and uninstall instructions.

Install from source with `install.ps1`, or use the standalone `whas-setup.exe`.
The EXE is currently built from source; a prebuilt release is not yet published.
It is unsigned, so Windows may display an unrecognized-app or unknown-publisher
warning. See [EXE setup and verification](docs/installation.md#standalone-executable-setup).

## Commands

| Command | Purpose |
|---|---|
| `agent` | Cloud agent with read-only permissions |
| `agentdo` | Cloud agent with write-capable permissions |
| `localagent` | Local Ollama agent with read-only permissions |
| `localagentdo` | Local Ollama agent with write-capable permissions |
| `tts-say` | Generate and play speech locally |

Cloud commands inherit your OpenCode model selection by default. Add `-v` to an
agent command to speak its response when speech is installed.

## Documentation

- [Troubleshooting](docs/troubleshooting.md)
- [TTS engines and strategy authoring](docs/tts-strategies.md)
- [Installation testing and rollback](docs/install-test-rollback.md)

## Development

Changes are tested locally and in Windows Sandbox. Commit messages use scoped
[Conventional Commits](https://www.conventionalcommits.org/), with every line
limited to 72 characters.

## License

See [LICENSE](LICENSE). TTS packages and models have their own licenses; see
[TTS strategies](docs/tts-strategies.md), including the noncommercial restriction
on F5 pretrained weights.
