# Troubleshooting

## Local chat gives unrelated answers or feels slow

Current GUI Conversation and One-off question on This PC call Ollama directly.
Conversation resends completed message history; one-off questions send only
their current question. Neither receives workspace prompts or file tools.
Older GUI builds routed conversation through OpenCode and supplied folder
instructions, which could distract smaller models and added startup work.
Close the older window and open the updated repository EXE; a copy you made
in the installation folder does not update itself. Start a new conversation
to discard old context. Compare the same model and a fresh conversation when
checking timing; model loading, history length and model parameters also affect it.

## Local request returns no completed answer

For GUI local chat, check that Ollama is running and the selected model appears
in `ollama list`. The GUI displays Ollama connection, model and stream errors
in the reply/activity log. It does not need OpenCode's model catalog for chat.

CLI local requests and GUI Run a task still use OpenCode. WHAS adds selected
Ollama models to each request's inline configuration without replacing saved
provider/model definitions. Their failures include the runtime error or
provider/model ID when OpenCode returns one. Opening a newer GUI alone does
not replace an old installed backend; use [shared app repair](gui.md#use-and-configure).

## A task mangles a folder path containing spaces

An older command layer passed quoted prompts through Windows PowerShell 5.1's
native argument binder. A message containing `"D:\Work\Web Projects\voices"`
could arrive at OpenCode split into two arguments with its quotes removed.
The current command layer encodes native arguments explicitly and preserves
the full message, including quotes, spaces, backslashes and newlines.
Update the installed command layer through [shared app repair](gui.md#use-and-configure).
Opening a newer repository GUI alone does not replace old installed scripts.

If an `external_directory` rejection contains a mangled path, compare it with
the saved workspace; do not add the malformed path or grant a broader parent
directory to work around it. Workspace permissions remain limited to the
folders you saved and their subfolders.

## Windows blocks the unsigned EXE

The setup EXE and installed command launchers are unsigned. SmartScreen may
show an unrecognized-app warning; Smart App Control or organisation policy may
block execution entirely. See [unsigned EXE verification and Windows warnings](installation.md#unsigned-exe-and-windows-warnings)
for checksum checks and what the warning means. Do not disable Windows
protections or change execution policy to make the EXE run.

## Unsupported speech device during setup

Piper is CPU-only. Set device choices per engine under **Models & engines**:
Chatterbox and F5 can use CUDA while Piper uses CPU. In source configuration,
use `tts.deviceDefaults` to override the legacy `tts.device` fallback for
individual engines. The EXE supports `--tts-devices chatterbox-turbo=cuda,piper-tts=cpu`.
Unsupported per-engine choices fail before installation.

## Piper TTS

Select Piper with `install.ps1 -Voice -TtsEngine piper-tts` or standalone
`--install --voice --tts-engine piper-tts`. The initial package supports CPU only;
set `tts.device` to `cpu` or `auto`. An explicit CUDA setting is rejected.
Both Python 3.11 x64 and the Visual C++ x64 runtime are required.
The model downloader includes a pinned private CA bundle for fresh Windows
installations while retaining the system's trusted roots and full HTTPS
verification. No Windows certificate-store change is required.

The Piper voice is `default` (also named `en_US-ljspeech-medium`). It is a
pre-trained English voice. `whas tts voice-add` and `whas tts voice-remove` are reference-WAV
cloning operations and are unsupported by this package.

Dependency hash failures, unavailable pinned wheels or model SHA256 mismatches
stop installation. Check network access to PyPI, files.pythonhosted.org and
huggingface.co and retry. Do not remove hash checks or replace pinned assets
with unrelated versions. Modified installed model files are preserved and
rejected on repeat install. Use the main uninstaller and review its preservation
receipt before reinstalling. Runtime paths are recorded in
`tts/engines/ENGINE/runtime.json` (older single-engine installs may use `tts/runtime.json`);
the shared speech service writes diagnostics under the installation's `tts`
directory. See [TTS strategy packages](tts-strategies.md) for the package notice
and current limitations.

## PowerShell scripts are disabled

Installed stack commands are native executables and require no PowerShell profile or execution-policy change. They host application command code internally, and isolated runtime tests pass under Restricted. Source installer and maintenance `.ps1` scripts still require a context permitted to run scripts; use the standalone setup EXE when policy blocks source scripts. Enforced restrictive organisation policy causes the command host to stop with an administrator-policy message.

For an ordinary user/machine restriction on a personal PC, see
[temporary permission for the source installer](installation.md#run-the-source-installer-with-temporary-permission).
It describes a child-process-only option for reviewed source, without saving
a policy change. It does not override Group Policy or Windows app controls.

### Missing stack commands

The executable directory is `%USERPROFILE%\.windows-hybrid-agentic-stack\bin`. An earlier development version used AppData, where a packaged host could redirect files into its private cache. That caused `agent` to be missing in ordinary PowerShell even with the expected PATH entry. The current installer uses the user-directory location instead.

Close and reopen the terminal application after installation. A new tab in an existing terminal may still inherit its old PATH. Inspect:

```powershell
Get-Command whas -CommandType Application
Get-Content -LiteralPath (Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack\commands.json')
Get-Content -LiteralPath (Join-Path $env:USERPROFILE '.windows-hybrid-agentic-stack\bin\install-root.txt')
[Environment]::GetEnvironmentVariable('Path', 'User')
```

Each PC needs its own local registration. Restore it from the repository in a context permitted to run maintenance scripts:

```powershell
. .\scripts\command-registration.ps1
Install-StackCommandRegistration -InstallPath 'D:\AI\AgentStack'
```

Use the actual installation directory. This only registers commands; it cannot supply missing runtime files or dependencies. Continue passing the correct installation path on future installer runs, or configure `installation.directory`.

To remove local registration, stop TTS and run `Unregister-StackCommands` using the same helper. Installation files and models are retained. See [Remove command registration](installation.md#remove-command-registration-on-one-pc).

### Errors from an older synced profile

Fresh installation writes no profile. Upgrading removes only recognised legacy stack blocks, with exact backups; unrelated profile code is preserved. Malformed, nested or duplicate markers stop migration for review. If startup still names a profile `.ps1`, inspect that file and its backups; it may contain unrelated scripts or blocks from an older installation. Do not change execution policy merely to suppress an obsolete stack loader error. Even an empty profile script can be rejected under Restricted.

A missing local installation now produces an error only when a stack command is invoked. The second PC should remain free of stack startup code when the stack has never been registered there.

### Uninstall rejects a registration backup name

An older uninstall helper omitted `whas` from its list of permitted command
backup names. After an app repair/update, a valid `whas.exe.bak.<32 hex digits>`
record could therefore fail with **Invalid registration backup name** after
ownership verification. This error occurs during preview/plan creation, before
removal. Current code derives allowed names from the shared command registry,
including `tts-help`, while retaining exact filename and hash verification.
Use the updated repository GUI for removal, or the repository's `uninstall.ps1`
with the existing installation path. Do not delete backups or ownership records
to bypass the check. The ownership scan will run again.

### Uninstall preserves files or refuses removal

Run `uninstall.ps1 -Verbose` to preview the per-file plan. Edited files, unknown files, custom voices and pre-existing Python environments are preserved. Their presence can leave the installation directory and ownership record behind; the uninstall receipt lists retained files.

An installation without `.whas-installation.json` has no recorded ownership, so the uninstaller refuses to delete its files. Reparse points, changed command executables, mismatched ownership or a PID belonging to another process also stop cleanup for review. Do not delete the ownership record to resolve these errors. Normal interrupted installations retain a record that can be previewed; an abruptly terminated installer may leave additional unverified files, which are preserved.

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
Get-Command whas -CommandType Application
whas tts status
```

If commands are missing, follow [Missing stack commands](#missing-stack-commands) above.

### CUDA is unavailable

Check your NVIDIA GPU:

```powershell
nvidia-smi
```

For Chatterbox, check CUDA availability using its installed strategy environment.
Adjust `$root` for a custom installation. Older single-engine installations may
use `tts/runtime.json`; still older Chatterbox installations use the root `.venv`:

```powershell
$root = Join-Path $HOME 'AI\WindowsHybridAgenticStack'
$runtimePath = Join-Path $root 'tts/engines/chatterbox-turbo/runtime.json'
if (-not (Test-Path -LiteralPath $runtimePath)) { $runtimePath = Join-Path $root 'tts/runtime.json' }
$environmentPath = '.venv'
if (Test-Path -LiteralPath $runtimePath) { $environmentPath = (Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json).environmentPath }
$python = Join-Path (Join-Path $root $environmentPath) 'Scripts/python.exe'
& $python -c "import torch; print('CUDA available:', torch.cuda.is_available())"
```

If CUDA is unavailable, verify your driver and installed PyTorch build.

### OpenCode or agent commands are not recognised

Open a new PowerShell window and check:

```powershell
Get-Command whas,opencode -CommandType Application -ErrorAction SilentlyContinue
```

If `whas` is missing, follow [Missing stack commands](#missing-stack-commands).
If `opencode` is missing, install that separate prerequisite and refresh PATH;
WHAS registration does not install it. GUI plain local chat uses Ollama directly.

### Perth watermarking fails during TTS startup

The published `resemble-perth==1.0.1` package requires `pkg_resources`. In the reference-machine investigation, setuptools 84.0.0 failed to supply it, while setuptools 80.9.0 allowed the Perth import to succeed. A failed import may surface as `ModuleNotFoundError: No module named 'pkg_resources'` or later as `TypeError: 'NoneType' object is not callable`.

The TTS installer constrains setuptools to `<81` inside its isolated virtual environment and verifies the actual Perth watermarking implementation. Keep this compatibility constraint when maintaining dependencies. Global Python and Whisper do not need modification. Check the stack's `tts\service-errors.log` for the underlying import error before diagnosing another cause.

## F5-TTS strategy

Select `f5-tts` explicitly; Chatterbox remains the default. Use Python 3.11 x64 and the Visual C++ x64 runtime. F5 weights are CC-BY-NC-4.0, so this bundled model is for noncommercial use only. CPU installation uses CPU PyTorch; CUDA uses the pinned CUDA 12.6 build and needs a compatible NVIDIA driver. Do not change global Python packages or execution policy to repair an installation.

Custom voices require a mono 3-12 second WAV and a matching UTF-8 `.txt` transcript beside it. The transcript must contain the words actually spoken. Missing transcripts are rejected rather than automatically downloading an ASR model. List/remove commands manage the installed WAV/text pair. Main uninstall preserves personal voices.

A model hash mismatch preserves the existing file and stops installation. Review it or choose a fresh installation directory; do not edit ownership hashes or disable certificate verification. Runtime inference uses local models only. CPU generation can take substantially longer than Piper. The native speech command waits up to 180 seconds per request; use shorter text or CUDA for long responses. Inspect the private service logs for an actual failure before treating slow inference as an install failure.

## Unified commands and graphical operations

Speech help is `whas tts --help` or `tts-help`; there is no bare `tts` launcher.
If new commands are missing, update installed files using shared app repair;
opening a newer repository GUI alone does not update the registered CLI.


`whas --help` lists the unified commands. A base-only installation has no default
runtime until one is installed/selected. Use `whas agent list` to inspect runtime
availability, then `whas configure --set runtime ID`. External OpenCode remains
a separately installed prerequisite and manages provider authentication.

An interactive native command shows activity during model waits, speech and
large ownership operations. Piped answer output deliberately stays plain.
Progress reports work actually observed; it cannot estimate a provider's time
to first answer. Large Python/Node environments may contain tens of thousands
of files. Scanning, hashing and removing those files can take several minutes.

If a GUI operation fails, read the details and preserve the ownership record.
Only submitted assistant requests and their speech expose Cancel. Setup,
maintenance and model discovery cannot be cancelled through the GUI.
Cancellation is not rollback. A forcibly interrupted installation/removal may leave files
for a repeat operation or reviewed cleanup. Do not change execution policy,
delete metadata, disable integrity checks or remove unrelated Python/Ollama
installations to repair it.

CLI/cloud session continuation requires the same runtime, user, workspace and local/cloud
route as its WHAS association. Start a new conversation when switching these.
For external native sessions use the runtime's own session interface. Forgetting
a WHAS association leaves native history and memory intact. See
[agent strategy guidance](agent-strategies.md#sessions-and-memory).

The GUI reads shared settings when opened and through **Reload shared settings**.
Reload after CLI edits before saving a conflicting edit. Voice lists also have
an explicit refresh action; unsupported cloning panels are hidden.

If a saved Chatterbox voice previews with HTTP 404, older inventories may have
exposed `c3po_prompt` for a voice actually named `c3po`. Storage files such as
`c3po_prompt.pt` do not make `_prompt` part of the public voice name. Reopen
the updated GUI and refresh engines/voices. Existing recordings and caches
remain usable; do not rename or recreate them to work around this mismatch.
The GUI uses bundled maintenance code to save defaults and play speech even
with an older installed command layer. The current CLI reports the service's error (such as Unknown voice)
instead of only an HTTP status. A failed save keeps the staged file/name for
correction; it does not automatically retry or overwrite an existing voice.

If an older native CLI plays audio successfully but exits 1, update shared app
files through **Configuration > Maintenance > Features > Repair shared app files**. Readiness
probe errors that were caught internally previously counted as command errors.
Current hosts distinguish handled probes from errors escaping the command.
Real failures still open the activity log and include the exit code there.
