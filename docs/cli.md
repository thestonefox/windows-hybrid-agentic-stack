# Unified commands and configuration

Install from [Quickstart](quickstart.md) first. Commands require the active
installation's registration directory on PATH. No profile or saved execution
policy change is needed for installed native launchers.

## Questions, tasks and conversations

| Command | Operation |
|---|---|
| `whas ask` | Independent restricted question, using saved defaults |
| `whas askl`, `whas askc` | The same operation with explicit local/cloud routing |
| `whas perform`, `performl`, `performc` | Independent tool-enabled task |
| `whas chat`, `chatl`, `chatc` | Interactive contextual conversation |

Suffixes are shortcuts for `--local` and `--cloud`. Conflicting choices fail.
`--runtime ID` overrides the saved runtime for one request; `--model ID` selects
a model. Explicit request options do not change saved defaults. Each agent's
tools operate in the current working directory. Choose that directory deliberately.

```powershell
whas askl "Explain RAM in one sentence"
```

```powershell
whas performc "Create a short README for this folder"
```

```powershell
whas askc --voice "Explain gravity in one sentence"
```

Additional runtime integrations remain deferred pending agreement.

The compatibility commands `agent`, `localagent`, `agentdo`, `localagentdo` and
all `tts-*` commands remain available with their existing options.

## Shared settings

```powershell
whas configure
```

```powershell
whas configure --show
```

```powershell
whas configure --set location local
```

```powershell
whas configure --set runtime opencode
```

Other supported keys are `cloud.model`, `local.model`, `speech.enabled`,
`speech.voice`, `speech.device` and `speech.autoStart`. Boolean values are
`true`/`false`. `runtime none` clears the default. Saving a setting does not
install software. Install a runtime before selecting it as the default.

Settings live in the installation's `config/config.json`, merged with
`config/defaults.json`. CLI and GUI use the same file. Changes affect new
requests; running services and conversations are not silently switched.
Writes use an installation lock and atomic replacement. The GUI saves one
setting at a time; reload it after CLI edits before saving a conflicting edit.

TTS engine selection has one authority: `tts/engines.json`, managed through
`whas tts default ID` or `tts-engine-default ID`. Per-engine voice preferences
are saved with:

```powershell
whas configure --set speech.voice sample --engine chatterbox-turbo
```

The sample must already exist for that engine. `default` selects its bundled
voice. Device changes apply to subsequent engine installations; they do not
convert an existing environment or restart its service.

Additional runtime integrations remain deferred pending agreement.

## Local model selection

Ollama can retain multiple models. Choose downloads and a default independently:

```powershell
.\install.ps1 -Local -LocalModels 'qwen3:8b,qwen2.5:1.5b' -DefaultLocalModel qwen3:8b
```

```powershell
.\whas-setup.exe --install --local --local-models qwen3:8b,qwen2.5:1.5b --default-local-model qwen3:8b
```

Setup reuses existing source models and creates context-configured aliases.
Only models it created, whose identity still matches, are removed by default
on uninstall. `-RetainManagedModels` / `--retain-managed-models` preserves them.
Changing `local.model` later selects an existing model; it does not download it
or create a new context alias. Use setup for downloads and alias preparation.

```powershell
whas model list
```

```powershell
whas askl --model ollama/qwen2.5:1.5b "What is two plus two?"
```

`-DefaultLocation local` / `--default-location local` sets the initial request
route during installation. Local-only installs choose local automatically;
otherwise the configured default applies. An explicit runtime/provider error
is returned rather than retrying the request through another runtime.

## Activity and cancellation

Native interactive commands report meaningful phases and elapsed activity on
stderr. Piped answers remain plain. Speech preparation, synthesis and playback
have their own phases; ownership scanning and cleanup show file counts.
Status probes do not load a speech model. GUI operations consume structured
events rather than parsing console colours.

GUI cancellation stops the process tree owned by that request when Windows
permits assignment to its job. If Windows cannot provide this, cancellation is
disabled. Cancellation is not rollback: review interrupted setup and uninstall
receipts before retrying. Existing external prerequisites are preserved.
