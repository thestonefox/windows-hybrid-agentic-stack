# TTS strategy packages

Chatterbox Turbo, Piper TTS and F5-TTS are bundled. Additional trusted packages can be placed in `tts/strategies/<id>/`; source setup discovers them and standalone setup embeds them at build time. Adding a folder beside an already-built EXE does not change that EXE. Rebuild it to include new packages.

## User guides

- [Chatterbox Turbo](tts/chatterbox-turbo.md)
- [Piper TTS](tts/piper-tts.md)
- [F5-TTS and its required transcript](tts/f5-tts.md)

The remainder describes shared engine management and the package-authoring
contract. Custom strategy code is trusted code: review it before installing.

## Selecting an engine

```powershell
.\install.ps1 -Voice -TtsEngine chatterbox-turbo
.\install.ps1 -Voice -TtsEngine piper-tts
.\install.ps1 -Voice -TtsEngine f5-tts
```

The equivalent standalone options are `--install --voice --tts-engine chatterbox-turbo`. A selector requires the voice component. CLI selection overrides `tts.engine` in configuration. With no explicit selection, configuration wins; interactive setup offers discovered engines when no user configuration was supplied. With only the default engine, no extra menu is necessary. Unattended setup retains the configured/default engine and never asks an engine-selection question. Missing engines and unsupported devices fail instead of selecting a replacement.

Multiple engines can be installed, each with its own environment, models and
personal voice directory. Only one service runs at a time. Supply comma-separated
IDs during setup; the first becomes the saved default:

```powershell
.\install.ps1 -Voice -TtsEngine 'chatterbox-turbo,piper-tts,f5-tts'
```

The equivalent EXE option is
`--install --voice --tts-engine chatterbox-turbo,piper-tts,f5-tts`.
Interactive selection accepts comma-separated menu numbers, with the first as
default. Every selected engine's prerequisites and device support are checked.
Automatic package upgrades are still rejected; repeat installs reuse unchanged
owned packages and environments.

This also applies to recognized legacy Chatterbox installations. After a completed uninstall, a directory retaining personal voices or other user files can be reused: a new ownership session preserves those surviving files as pre-existing data. Modified package/environment files that collide with a new installation still require review or a different installation directory.

| Bundled strategy | Execution | Included voice | Reference-WAV cloning |
|---|---|---|---|
| `chatterbox-turbo` | CPU or CUDA | Chatterbox default | Supported |
| `piper-tts` | CPU | LJ Speech medium, US English | Unsupported |
| `f5-tts` | CPU or CUDA | Upstream English reference example | WAV plus transcript |

Chatterbox remains the configured default. Interactive setup offers all three engines; unattended setup uses the configured/default engine unless `-TtsEngine` / `--tts-engine` overrides it. All three packages currently require 64-bit Python 3.11 and the Visual C++ x64 runtime.

Per-engine setup device preferences can be supplied in source configuration:

```json
{"tts":{"deviceDefaults":{"chatterbox-turbo":"cuda","piper-tts":"cpu","f5-tts":"auto"}}}
```

These override `tts.device` for the named engine. `auto` is labelled Prefer GPU
in setup: it uses GPU when detected and otherwise reports CPU fallback.
The GUI presents independent
choices; selecting a CPU-only engine does not restrict another engine's GPU
choice. Runtime records store each installed engine's resolved device.

## Manage installed engines

```powershell
whas tts list
```

List shows available/installed engines and the saved default and active engine.
To add a catalog engine, stop speech first, then install it (with confirmation):

```powershell
whas tts stop
```

```powershell
whas tts install piper-tts
```

Use `--device cpu`, `--device cuda` or `--device auto` as supported by the
strategy; default is `auto`. `--yes` accepts the install confirmation.
The installed, ownership-checked catalog supplies the installer; no arbitrary
package URL is accepted. Adding an engine preserves the existing default.

```powershell
whas tts default piper-tts
```

The saved default lives in `tts/engines.json`. The `tts.engine` configuration
setting chooses the initial setup engine; this command does not rewrite it.

With no argument, this prints the saved default. Changing it does not switch
a running engine. Commands resolve explicit `--engine`, then the active engine,
then the saved default. GUI Assistant replies explicitly use the saved default,
so previewing another engine does not change subsequent Assistant speech.
For the full command/flag list use `whas tts --help`, `tts-help` or
the [speech reference](cli.md#speech-flags):

```powershell
whas tts start --engine f5-tts
```

```powershell
whas tts voice-add -Path 'C:\Voices\sample.wav' -Name myvoice --engine f5-tts
```

Selection is checked before switching. Unknown engines, known uninstalled
engines and unsupported operations have distinct errors. F5's manifest declares
its transcript requirement; missing/empty text is rejected before model startup.
Names are local to each engine. A single operation lock prevents competing
speech, setup and uninstall operations on the same installation.

Preview individual removal:

```powershell
whas tts uninstall f5-tts
```

Apply with confirmation:

```powershell
whas tts uninstall f5-tts --apply
```

When removing the default and other installed engines remain, choose the
replacement explicitly with `--default-engine ENGINE`. Removing the last engine
clears the default. Its active service is stopped before cleanup. Personal
voices and modified/unknown files remain; the shared catalog supports reinstall.
Full stack uninstall removes every installed engine's unchanged owned resources
and the catalog. Failed installs remain tracked for repair or cleanup.

## Piper package

Piper uses `piper-tts` 1.8.0 and CPU ONNX Runtime in its own environment. Its Windows x64 / Python 3.11 dependency lock pins all eight runtime wheels by version and SHA256; setup installs binary wheels only and rejects unverified artifacts. It does not install PyTorch or GPU packages. The ONNX model, JSON configuration and upstream model card are pinned to a repository revision and individually hash-verified. They download directly into the strategy-owned model directory; inference needs no network or account. Repeat model preparation verifies existing assets and avoids downloading them again.

Model HTTPS downloads retain the system's trusted roots and add a pinned private Certifi CA bundle for fresh Windows installations. Certificate and hostname verification remain enabled. Setup does not modify Windows certificate stores, profiles or execution policies.

`default` and `en_US-ljspeech-medium` select the same pre-trained voice. `whas tts voice-list` lists both. Reference-recording add/remove operations are unsupported, so Piper is not a voice-cloning substitute for Chatterbox. Other models, languages, arbitrary ONNX imports and GPU support are outside this first package.

Piper's engine is GPL-3.0-or-later. The voice's upstream model card identifies its LJ Speech dataset as public domain; the exact model card is retained with the model rather than assigning it a different licence. Read [the package notice](../tts/strategies/piper-tts/NOTICE.md) for upstream source and licensing links. The setup EXE contains the adapter and download metadata; runtime wheels and voice weights are downloaded at install time.

## F5 package

F5 uses the official [SWivid/F5-TTS](https://github.com/SWivid/F5-TTS) project and its published `f5-tts` 1.1.22 package, F5TTS_v1_Base and the Vocos mel-24kHz vocoder. Code is MIT licensed; **F5 pretrained weights are CC-BY-NC-4.0, for noncommercial use only**. Setup displays this restriction. See [the package notice](../tts/strategies/f5-tts/NOTICE.md) and the downloaded model cards.

CPU and NVIDIA CUDA 12.6 use separate PyTorch/Torchaudio 2.6.0 locks. The Windows x64 / Python 3.11 lock covers all declared runtime distributions, including upstream UI/training dependencies. The adapter starts only the shared loopback service. Three pinned source archives build with pinned private packaging tools; setup disables dependency resolution, build isolation and shared pip caching. Every downloaded runtime artifact has an explicit HTTPS URL and SHA256. The six model/card assets also have pinned repository revisions and individual SHA256 checks. Changed existing assets are preserved and rejected. Model downloads use the same private verified TLS approach as Piper.

`default` uses the upstream English reference WAV and transcript supplied in the verified F5 Python wheel. Output is 24 kHz PCM WAV. CPU generation is slower than Piper; CUDA requires a compatible NVIDIA driver. Inference uses installed local weights and does not download models, invoke automatic transcription or require FFmpeg.

For a custom voice, prepare a mono WAV lasting 3-12 seconds and a UTF-8 text file containing the exact spoken words. Give the two files the same base name in the same directory, for example `speaker.wav` and `speaker.txt`, then run:

```powershell
whas tts voice-add -Name speaker -Path 'C:\Voices\speaker.wav' --engine f5-tts
whas tts say -Text 'Testing my reference voice.' -Voice speaker --engine f5-tts
whas tts voice-list --engine f5-tts
whas tts voice-remove -Name speaker --engine f5-tts
```

The strategy validates and copies both files into its personal voice directory. Missing, empty or oversized transcripts and invalid/silent recordings are rejected; duplicate voices are preserved. Adding a voice does not download Whisper or create a Python pickle. Removing a voice deletes its installed WAV/text pair. The main uninstaller invokes the installed F5 hook, removes unchanged owned environment/models/package files, and preserves personal recordings and transcripts. Completed uninstall/reinstall follows the shared ownership rules.

## Package contents

Use `tts/strategy.schema.json` and the bundled Chatterbox manifest as the API v1 specification and example. Each package must contain:

- `manifest.json`: schema/API version, unique directory-matching ID, package version, description, platform/devices, prerequisites, capabilities, entry points, licence, model references pinned by revision or SHA256 and an explicit asset list.
- An install PowerShell script accepting `Context` and `PrepareOnly`.
- An uninstall PowerShell script accepting `Context`.
- A Python backend exposing `create_backend(context)`.
- Any additional declared source/dependency files.

The manifest itself is included automatically; do not put it in `files`. Paths must remain inside the package. Duplicate IDs, unsupported APIs, missing files, traversal, reparse points, oversized assets and private/runtime files are rejected. Discovery/build validation reads data only and does not execute hooks or import backends. API v1 supports Windows x64 and Python runtimes; a Python adapter can call a native engine. Other runtime/platform contracts require a future API version.

Do not put environments, model weights, recordings, credentials, logs or private configuration in a strategy package. The EXE embeds only validated, explicitly listed source assets, never a recursive copy of the folder. Source packages are trusted executable software: validation and hashes are integrity checks, not a security sandbox or publisher signature.

## Installation contract

`Context` supplies the resolved installation root, engine ID, selected CPU/CUDA device and relative environment, model and personal-voice directories. Use those paths; do not change global Python packages, PATH, execution policy, profiles or shared caches. Install only the selected engine. Return exit code zero on success and nonzero on failure; do not report success until dependency/model preparation is complete.

New engine environments and model copies live under `tts/engines/<id>/`; the installed package lives under `tts/strategies/<id>/`. Personal voices live under `voices/<id>/`. The root installer records partial and completed resources through `.whas-installation.json`. Strategy install scripts must tolerate safe retry, preserve existing user data and reject incompatible/unowned environments. `PrepareOnly` creates the Python environment without downloading dependencies or models and without declaring the engine ready for speech.

Chatterbox uses a pinned public model revision. Public Hugging Face cache entries may be reused for downloading, but the installation receives its own model copy. Shared download caches are not deleted during uninstall. Chatterbox's existing dependency pins and CPU/CUDA wheel selection remain inside its package.

When an installation helper imports files from its source package, launch Python with `-B`. Standalone setup removes only declared extracted assets and preserves unknown files; generated package bytecode would otherwise leave its temporary payload directory behind.

## Backend contract

The factory receives `device`, `voices_directory` and `models_directory`. It returns an object implementing:

| Method | Contract |
|---|---|
| `load()` | Load dependencies and model, or raise an actionable error |
| `synthesise(text, voice)` | Return complete WAV bytes |
| `list_voices()` | Return available voice names |
| `close()` | Release engine resources |
| `add_voice(name, path)` | Optional reference-WAV registration when `voiceCloning` is true |
| `remove_voice(name)` | Optional custom-voice removal when `voiceCloning` is true |

The shared service owns loopback HTTP, bounded requests, voice-name validation, error responses, idle shutdown and readiness identity. The strategy owns model-specific inference and voice storage. `default` is reserved. Unsupported reference-voice operations return an explicit unsupported response. Existing voice and agent commands remain compatible. Unified speech and voice commands
accept `--engine ID`. Installed management commands execute ownership-checked
application scripts through the native host without loading profiles or changing
execution policy. Enforced organisation restrictions still apply.

## Uninstall contract

Use the main `uninstall.ps1` or standalone `--uninstall`. Preview reads the installed ownership record and verifies the frozen strategy package; it never executes an uninstall hook, launches speech or downloads anything. The package must still be present and unchanged to execute its hook. Repair a missing/modified package before applying cleanup.

After approval, the shared coordinator verifies and stops installation-owned speech processes, executes the installed version's uninstall hook while dependencies still exist, revalidates ownership and removes unchanged owned files. A hook must be idempotent, avoid deleting files itself when shared ownership cleanup suffices, and exit nonzero on failure. Failure retains the installation for review/retry and creates an incomplete receipt. Do not run the source checkout's current hook against a different installed version.

Chatterbox has no external cleanup action; its hook reports that and leaves private-file removal to the coordinator. Personal voices, edited/unknown files, pre-existing resources and shared caches are preserved. Retained data can leave the installation directory present. Completed cleanup can be previewed again without requiring removed strategy files. This is scoped uninstall, not a whole-system rollback or a sandbox for arbitrary hook code.

Piper uses the same cleanup contract. Its hook leaves removal of its private environment, voice model and package files to the ownership coordinator. It has no external service registration or model cache to remove. Engine-specific uninstall logic does not require edits to the main uninstaller.

Ownership schema 1 remains readable. Upgrading a recognized, installer-owned legacy Chatterbox environment keeps its existing `.venv` and `voices` locations; environments are not relocated. An unowned legacy environment is not adopted or modified. Schema 2 records the installed strategy version, layout, package hashes and installation status. Never edit ownership hashes to force cleanup.

## Validation and private data

`tests/test-tts-strategies.ps1` creates a disposable second strategy outside the repo to exercise source/EXE packaging, install dispatch, repeat installation, preview, hook rejection/failure, source-independent uninstall and voice preservation. `tests/test-tts-service.py` checks runtime dispatch and HTTP behavior without ML packages or playback. The existing installer, registration and uninstall suites remain regression coverage.

Keep actual test results, recordings, models, compiled installers and local machine information outside the repo. Live speech and installation tests supplement the isolated checks; passing mock tests alone does not establish real synthesis compatibility for a new engine.

`tests/test-piper-strategy.py` exercises pinned downloads, TLS verification, hash failure, safe repeat preparation, preservation of modified/partial files, download bounds and backend voice/device boundaries without network access or ML dependencies.

`tests/test-f5-strategy.py` checks pinned nested asset downloads, offline repeat preparation, corruption/size failures, preservation of modified/partial files, transcript requirements and voice/device boundaries without network access or ML packages.

## Optional voice-reference requirements

A strategy supporting reference voices can declare:

```json
"voiceReference": {
  "transcriptRequired": true,
  "files": ["{name}.wav", "{name}.txt"]
}
```

This optional API-v1 field preserves existing manifests. It requests a matching
UTF-8 `.txt` alongside the WAV, checked before switching or loading an engine.
Without it, no transcript is required. The backend must still validate all
inputs independently. `files` declares the stored files required for a usable
voice. The first pattern discovers names; every listed file must exist.
Patterns start with literal `{name}` and end in `.wav`, `.pt` or `.txt`, with
no directory components. Chatterbox declares `{"files":["{name}_prompt.pt"]}`
inside its voiceReference object: the public name is `c3po`, even though the
cache is `c3po_prompt.pt`. F5 requires the WAV/text pair. Discovery and default
validation use these data-only patterns without loading an engine. Legacy
installed Chatterbox packages have a compatibility fallback; new strategies
must declare their storage layout rather than adding engine-ID conditionals.
Include a user guide with examples, supported operations, required input files,
licences, error remedies and uninstall behaviour when publishing a strategy.

## Runtime records

Installation ownership schema 2 accepts multiple unique strategy records,
including interrupted installations. Each engine has
`tts/engines/<id>/runtime.json`; `tts/engines.json` records the saved default
(or `null` when none is configured). The service is launched with an explicit
engine ID and validates its runtime against the installed ownership/package
records. Single-engine schema-2 layouts retain the legacy `tts/runtime.json`
fallback until updated; legacy schema-1 Chatterbox requires its existing
migration path before adding other engines.
