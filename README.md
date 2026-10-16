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
| `whas ask`, `askl`, `askc` | Independent restricted questions; default, local or cloud |
| `whas perform`, `performl`, `performc` | Independent tool-enabled tasks |
| `whas chat`, `chatl`, `chatc` | Contextual conversations |
| `whas configure` | Shared CLI and GUI settings |
| `tts-say` | Generate and play speech locally |

Cloud commands inherit your OpenCode model selection by default. Add `-v` to an
agent command, or `--voice` to `whas ask`/`perform`, to speak its response.
The existing `agent`, `localagent`, `agentdo` and `localagentdo` commands remain
available. Open `whas-gui.exe` in the installation folder for graphical use;
opening `whas-setup.exe` without arguments starts graphical setup/uninstall.

## Documentation

- [Troubleshooting](docs/troubleshooting.md)
- [Unified commands and shared settings](docs/cli.md)
- [Graphical setup, usage and configuration](docs/gui.md)
- [Agent runtimes, sessions and strategy authoring](docs/agent-strategies.md)
- [TTS engine management and strategy authoring](docs/tts-strategies.md)
- Engine guides: [Chatterbox](docs/tts/chatterbox-turbo.md), [Piper](docs/tts/piper-tts.md), [F5](docs/tts/f5-tts.md)
- [Builds and releases](docs/releases.md)
- [Installation testing and rollback](docs/install-test-rollback.md)

## Development

Changes are tested locally and in Windows Sandbox. Commit messages use scoped
[Conventional Commits](https://www.conventionalcommits.org/), with every line
limited to 72 characters.

## License

See [LICENSE](LICENSE). Agent runtimes, TTS packages and models have their own licenses; see
[TTS strategies](docs/tts-strategies.md), including the noncommercial restriction
on F5 pretrained weights.
