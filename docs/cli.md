# Unified commands and configuration

Install from [Quickstart](quickstart.md) first. Commands require the active
installation's registration directory on PATH. No profile or saved execution
policy change is needed for installed native launchers.

## Start here: ask, chat or perform

These are the three everyday commands. They use your saved This PC or Cloud
default unless you choose a route for that request.

| Command | Use it for | Example |
|---|---|---|
| `whas ask "QUESTION"` | One-off answer without file or system tools | `whas ask "What is 2 + 2?"` |
| `whas chat` | Interactive conversation that remembers the session | `whas chat --no-voice` |
| `whas perform "TASK"` | Independent task that can read or change files and use system tools | `whas perform "Create notes.txt here"` |

Run a task from the folder you want it to use. `whas perform` uses the current
PowerShell folder; `ask` and `chat` do not have file tools. CLI chat uses
OpenCode sessions, including for local models. It cannot speak replies, so
`--no-voice` is needed if speech is enabled in your saved defaults.

For a spoken answer, install a speech engine and add `--voice` to an ask or
perform request. To speak text without asking an AI model, use `whas tts say`:

```powershell
whas ask --voice "Explain gravity in one sentence"
whas tts say "Hello from WHAS"
```

Append `l` for This PC (`whas askl`, `whas chatl`, `whas performl`) or `c`
for Cloud (`whas askc`, `whas chatc`, `whas performc`). These are shortcuts
for `--local` and `--cloud`. See [request details](#questions-tasks-and-conversations)
for models, sessions and tool permissions.

## Complete command and flag reference

Installed help:

```powershell
whas --help
whas tts --help
tts-help
```

`whas -h` and `whas help` are aliases for the first command. Speech help also
accepts `whas tts -h`, `whas tts help` or just `whas tts`. There is no bare
`tts` launcher: use `tts-help`, not `tts --help`. The new speech-help entry
points require the updated installed command layer; opening a newer GUI alone
does not install them. Use [shared app repair](gui.md#use-and-configure).
Help lists WHAS options; native provider options belong to OpenCode/Ollama.

### Request flags

Use `whas ask [FLAGS] "QUESTION"`, `whas perform [FLAGS] "TASK"` or
`whas chat [FLAGS]`. The `l` and `c` command suffixes select local and cloud.
Quote each message as one argument; quote paths containing spaces inside it.

| Flag | Applies to | Meaning |
|---|---|---|
| `--local`, `--cloud` | All requests | Override the saved route; conflicting route choices fail |
| `--runtime ID` | All requests | Override the saved runtime (`opencode` is the shipped runtime) |
| `-m ID`, `--model ID` | All requests | Override the selected model for this request |
| `--voice`, `--no-voice` | All requests | Override saved speech; CLI chat rejects enabled speech, including `--message` |
| `-l`, `--log` | Ask/perform | Print raw OpenCode output instead of extracting its final answer |
| `--new` | Chat | Start fresh (the default); cannot combine with `--session` |
| `--session ID` | Chat | Resume a WHAS-associated session in the same route/workspace/user |
| `--message TEXT` | Chat | Make one machine-readable turn rather than opening interactive chat |

Use top-level `whas --help` for unified request help. `ask/perform --help`
currently reaches compatibility help; `chat --help` is not supported.
The legacy `-v [VOICE]` syntax belongs to older agent launchers; prefer the
unified speech switches and saved voice configuration above.

### Settings, models, runtimes and sessions

| Command | Flags/arguments |
|---|---|
| `whas configure` | Interactive settings; no flags |
| `whas configure --show` | Effective settings as JSON |
| `whas configure --set KEY VALUE` | Save one setting; `--engine ID` only for `speech.voice` |
| `whas model list` | Installed Ollama models; no flags |
| `whas model catalog --local` | Installed local model IDs as JSON |
| `whas model catalog --cloud` | OpenCode cloud model IDs as JSON |
| `whas agent list` | Runtime capability/availability records; no flags |
| `whas agent check ID` | Run the runtime's version check |
| `whas agent native ID [ARGS]` | Pass arguments to its native interface |
| `whas agent install ID [--yes]` | Managed-install strategies only; OpenCode is an external prerequisite |
| `whas agent uninstall ID [--apply] [--yes]` | Preview/remove owned managed-runtime files; retains personal data |
| `whas session list` | WHAS associations; no flags |
| `whas session forget RUNTIME SESSION --yes` | Remove an association, retaining native history |

Settings keys and accepted values:

| Key | Value |
|---|---|
| `location` | `local` or `cloud` |
| `runtime` | Available runtime ID, or `none` to clear |
| `cloud.model` | Provider/model ID; empty string clears the override |
| `local.model` | Existing local model ID |
| `cloud.enabled`, `local.enabled` | `true` or `false`; request availability only, does not install/remove files |
| `speech.enabled`, `speech.autoStart` | `true` or `false` |
| `speech.voice` | Existing voice name or `default`; add `--engine ID` for its per-engine default |
| `speech.device` | Legacy `auto`, `cpu` or `cuda` fallback for engines without `tts.deviceDefaults`; applies to subsequent setup |
| `speech.idleTimeoutMinutes` | Non-negative whole minutes; `0` disables idle shutdown; next engine start |

### Speech flags

| Command after `whas tts` | All supported arguments/flags |
|---|---|
| `list` | None |
| `inventory` | None; JSON capabilities, installation state and voice names |
| `install ID` | `--engine ID` instead of positional ID; `--device auto\|cpu\|cuda`, `--yes` |
| `uninstall ID` | `--engine ID` instead of positional ID; `--default-engine ID`, `--apply`, `--yes` |
| `default [ID]` | `--engine ID` instead of positional ID; omit to inspect |
| `start`, `stop`, `status` | `--engine ID` |
| `say TEXT` | `--text TEXT` instead of positional TEXT; `--voice NAME`, `--engine ID` |
| `voice-list` | `--engine ID` |
| `voice-add` | Required `--path FILE --name NAME` (FILE may be positional); optional `--engine ID` |
| `voice-test NAME` | `--name NAME` instead of positional NAME; `--engine ID` |
| `voice-remove NAME` | `--name NAME` instead of positional NAME; `--engine ID`, `--yes` |

Speech named options are case-insensitive and accept one or two leading
hyphens: `-Text`, `--text`, `-DefaultEngine` and `--default-engine`, for example.
Switches `--apply`/`--yes` take no value. Do not supply both positional and named
forms of the same argument. Engine removal previews unless `--apply` is given;
`--yes` skips confirmation but does not enable removal by itself. When removing
the default engine while others remain, choose its replacement explicitly.
`--engine` resolution is described [below](#speech-commands).

### Installation and removal flags

These are separate from the installed `whas` request commands. Use the
[installation guide](installation.md) for prerequisites, execution permission,
configuration-file options and detailed examples.

| `install.ps1` parameter | Meaning |
|---|---|
| `-Check` | Read-only prerequisite check |
| `-Core` | Shared app only, without optional components |
| `-Cloud`, `-Local`, `-Voice` | Select optional components |
| `-TtsEngine IDS` | Comma-separated speech engines; first is default; requires Voice |
| `-LocalModels IDS` | Comma-separated local models |
| `-DefaultLocalModel ID` | Default from the selected local models |
| `-DefaultLocation cloud\|local` | Initial route |
| `-Yes` | Accept installer confirmations |
| `-InstallPath PATH` | Installation destination |
| `-PersistCommandPath $false` | Avoid persistent PATH changes for isolated tests (default true) |

`uninstall.ps1` accepts `-InstallPath PATH`, `-Apply`,
`-RetainManagedModels`, legacy `-RemoveManagedModels` (already the default),
and `-PersistCommandPath $false`. Preview is the default. Retain/remove model
switches conflict. These advanced scripts also support standard PowerShell
common parameters, such as `-Verbose` and `-ErrorAction`; uninstall exposes
`-WhatIf` and `-Confirm` through `SupportsShouldProcess`.

The graphical EXE accepts these explicit console modes (without arguments it
opens the GUI):

| `whas-gui.exe` flag | Meaning |
|---|---|
| `--help`, `-h` | Setup help |
| `--plan`, `--check`, `--install`, `--uninstall` | Select one setup/removal mode |
| `--core` | Shared app only |
| `--cloud`, `--local`, `--voice` | Select optional components |
| `--tts-engine IDS` | Speech engine IDs, first as default |
| `--tts-devices ID=DEVICE,...` | Per-engine choices, e.g. `chatterbox-turbo=cuda,piper-tts=cpu`; requires `--voice`; engine IDs must be selected |
| `--tts-device auto\|cpu\|cuda` | Legacy fallback device; requires `--voice`; cannot combine with `--tts-devices` |
| `--local-models IDS`, `--default-local-model ID` | Downloads and default model |
| `--default-location cloud\|local` | Initial route |
| `--config PATH` | JSON setup overrides |
| `--install-path PATH` | Destination/target installation |
| `--apply` | Apply uninstall rather than preview |
| `--retain-managed-models` | Preserve installer-created models |
| `--remove-managed-models` | Legacy explicit removal flag; already the default |
| `--yes` | Accept confirmation |
| `--no-path` | Leave persistent user PATH unchanged |

See [standalone executable setup](installation.md#standalone-executable-setup)
for prerequisites and examples. Developer `whas-setup.exe` uses the same
console flags; it is not a separate installed GUI.

## Questions, tasks and conversations

| Command | Operation |
|---|---|
| `whas ask` | Independent question without tools, using saved defaults |
| `whas askl`, `whas askc` | The same operation with explicit local/cloud routing |
| `whas perform`, `whas performl`, `whas performc` | Independent tool-enabled task |
| `whas chat`, `whas chatl`, `whas chatc` | Interactive contextual conversation |

Suffixes are shortcuts for `--local` and `--cloud`. Conflicting choices fail.
`--runtime ID` overrides the saved runtime for one request; `--model ID` selects
a model. Explicit request options do not change saved defaults. File and
system tools are only available to tasks. They operate in the current
working directory; choose it deliberately. CLI chat uses OpenCode even for
local models. With speech enabled by default, pass `--no-voice` to CLI chat;
interactive CLI speech is unsupported. GUI conversation speech is supported.

```powershell
whas askl "Explain RAM in one sentence"
```

```powershell
whas performc "Create a short README for this folder"
```

```powershell
whas askc --voice "Explain gravity in one sentence"
```

OpenCode implements plain `ask`/`chat` using a managed conversation profile
with tools denied, and tool-enabled `perform`. Restrictions are its tool
permissions, not an operating-system sandbox. The GUI uses Ollama directly
for local conversation and one-off questions. CLI chat can run interactively;
machine-readable turns can return session IDs for WHAS association and resumption.
Unsupported operations fail before launching the runtime. Interactive CLI chat
uses OpenCode's native session handling; machine-readable `--message` turns
return a session ID that WHAS can associate and resume with `--session`.

Native OpenCode calls preserve each argument directly, including embedded
quotes, spaces, backslashes and multiline messages. They require the native
Windows `opencode.exe` on PATH; shell-script shims are not used for this handoff.

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
`speech.voice`, `speech.device`, `speech.autoStart` and
`speech.idleTimeoutMinutes`. The idle timeout takes non-negative whole minutes;
zero keeps the speech engine running. It applies on the next engine start.
Boolean values are
`true`/`false`. `runtime none` clears the default. Saving a setting does not
install software. Install a runtime before selecting it as the default.

Settings live in the installation's `config/config.json`, merged with
`config/defaults.json`. CLI and GUI use the same file. Changes affect new
requests; running services and conversations are not silently switched.
Writes use an installation lock and atomic replacement. The GUI saves one
setting at a time; reload it after CLI edits before saving a conflicting edit.

TTS engine selection has one authority: `tts/engines.json`, managed through
`whas tts default ID`. Per-engine voice preferences
are saved with:

```powershell
whas configure --set speech.voice sample --engine chatterbox-turbo
```

The sample must already exist for that engine. `default` selects its bundled
voice. Device changes apply to subsequent engine installations; they do not
convert an existing environment or restart its service.

Provider credentials stay in the runtime's supported authentication storage.
Do not put keys in ordinary WHAS configuration. Cloud OpenCode model selection
is inherited when no cloud override is set; signing in alone does not select
a model.

## Local model selection

Ollama can retain multiple models. Choose downloads and a default independently:

```powershell
.\install.ps1 -Local -LocalModels 'qwen3:8b,qwen2.5:1.5b' -DefaultLocalModel qwen3:8b
```

```powershell
.\whas-gui.exe --install --local --local-models qwen3:8b,qwen2.5:1.5b --default-local-model qwen3:8b
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

GUI Cancel replaces Send only during a submitted request and its speech
output. Direct Ollama chat cancellation aborts its HTTP request. Command-backed
requests stop their owned process tree when Windows permits assignment to its
job; otherwise cancellation is disabled. Loading settings, discovering models,
setup and maintenance do not expose Cancel. Cancellation does not undo file
changes already made by a task. An interrupted installation or removal still
requires reviewing its receipt; closing or forcibly terminating it is not rollback.

## Speech commands

| Command | Purpose |
|---|---|
| `whas tts list` | List available, installed, default and active engines |
| `whas tts install ID` | Add an engine from the installed catalog |
| `whas tts uninstall ID` | Preview engine removal; add `--apply` to remove |
| `whas tts default ID` | Save the default engine; omit ID to inspect it |
| `whas tts start`, `whas tts stop`, `whas tts status` | Manage/probe the service |
| `whas tts say "Text"` | Generate and play speech |
| `whas tts voice-list` | List voices for the selected engine |
| `whas tts voice-add -Path FILE -Name NAME` | Add a custom reference voice |
| `whas tts voice-test NAME` | Speak a test phrase with a saved voice |
| `whas tts voice-remove NAME` | Delete a custom voice with confirmation |

Speech/voice commands accept `--engine ID`; see [engine resolution and
management](tts-strategies.md#manage-installed-engines). Piper does not support
custom reference voices. F5 needs a matching WAV and UTF-8 transcript. Adding
a voice does not make it the default: save `speech.voice` with `--engine ID`
as shown above. Default engine and default voice are separate settings.

## Compatibility commands

The older launchers remain supported; `tts-help` supplies their speech reference.
New examples use the unified `whas` interface.

| Standalone launcher | Unified command | Difference |
|---|---|---|
| `agent` | `whas askc` | Older `ps-read` profile can read files; `ask` has no tools |
| `localagent` | `whas askl` | Same permission distinction, with Ollama models |
| `agentdo` | `whas performc` | Both use the write-capable task profile |
| `localagentdo` | `whas performl` | Both use the local task profile |
| `tts-start`, `tts-stop`, `tts-status`, `tts-say` | `whas tts start`, `stop`, `status`, `say` | Same speech operations |
| `tts-help` | `whas tts --help` | Speech command and flag reference |
| `tts-voice-*` | `whas tts voice-*` | Same voice operations |
| `tts-engine-list/install/uninstall/default` | `whas tts list/install/uninstall/default` | Engine operations omit the `engine-` prefix |

For one-off questions and tasks, `-m`/`--model` and `-l`/`--log` remain
supported. Older agent launchers also accept `-v [VOICE] PROMPT`; the unified
`--voice` flag is a switch, not a voice-name argument. Choose a saved voice
through configuration or use `whas tts say -Text TEXT -Voice NAME` directly.
The CLI has no universal per-request help parser: use `whas --help` for the
unified interface. Compatibility help may describe the older launcher options.

The older agent launchers accept `-m`/`--model ID`, `-l`/`--log`,
`-v`/`--voice [VOICE]` and `-h`/`--help`. `-v` speaks the final answer;
the optional voice name comes before the prompt. For example:

```powershell
agent -v myvoice "Explain gravity in one sentence"
```

`agent` and `localagent` retain their older read-only file access, while
`agentdo` and `localagentdo` can make changes. Use `whas ask` for questions
without file tools and `whas perform` for tool-enabled tasks. The compatibility
`tts-*` launchers accept the corresponding speech command arguments listed in
[Speech flags](#speech-flags), including `-Engine ID`; `tts-help` prints that
reference directly.
