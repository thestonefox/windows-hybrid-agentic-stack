# WHAS repository guide

This is a Windows 10/11 toolkit built with Windows PowerShell 5.1, C# and Python.
Use PowerShell 5.1-compatible syntax in project scripts. `config/AGENTS.md` is
the installed OpenCode assistant's prompt, not this repository's Codex guide.

Find the relevant files with `rg --files` and scoped `rg -n` searches. Read only
the source, documentation and tests needed for the task. Avoid dumping entire
directories or the full installation guide into context for a small edit.

- Assistant and CLI: `scripts/whas.ps1`, `scripts/agent-commands.ps1`,
  `scripts/agent-strategies.ps1`; user reference: `docs/cli.md`.
- GUI: `scripts/fluent-gui.cs`, `scripts/gui-host.cs`,
  `scripts/gui-maintenance.ps1`, `scripts/gui-theme.xaml`; user guide: `docs/gui.md`.
- Setup and removal: `install.ps1`, `uninstall.ps1`, `scripts/setup-*.ps1`,
  `scripts/installation-state.ps1`; guides: `docs/installation.md` and
  `docs/install-test-rollback.md`.
- Speech: `tts/`; engine guides are under `docs/tts/`.
- Tests: `tests/`. Run the focused test for changed behavior. Expand testing
  when changes cross components or a focused test reveals a risk.
- Builds and releases: `.github/workflows/`, `scripts/build-release.ps1`,
  `scripts/release.py`; release rules and retries: `docs/releases.md`.

Keep private runtime data out of source. `.gitignore` lists the generated
models, audio, logs, settings and agent data that should stay local.
