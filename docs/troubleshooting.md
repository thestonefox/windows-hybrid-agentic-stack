# Troubleshooting

## Piper TTS

Select Piper with `install.ps1 -Voice -TtsEngine piper-tts` or standalone
`--install --voice --tts-engine piper-tts`. The initial package supports CPU only;
set `tts.device` to `cpu` or `auto`. An explicit CUDA setting is rejected.
Both Python 3.11 x64 and the Visual C++ x64 runtime are required.
The model downloader includes a pinned private CA bundle for fresh Windows
installations while retaining the system's trusted roots and full HTTPS
verification. No Windows certificate-store change is required.

The Piper voice is `default` (also named `en_US-ljspeech-medium`). It is a
pre-trained English voice. `tts-voice-add` and `tts-voice-remove` are reference-WAV
cloning operations and are unsupported by this package.

Dependency hash failures, unavailable pinned wheels or model SHA256 mismatches
stop installation. Check network access to PyPI, files.pythonhosted.org and
huggingface.co and retry. Do not remove hash checks or replace pinned assets
with unrelated versions. Modified installed model files are preserved and
rejected on repeat install. Use the main uninstaller and review its preservation
receipt before reinstalling. Runtime paths are recorded in `tts/runtime.json`;
the shared speech service writes diagnostics under the installation's `tts`
directory. See [TTS strategy packages](tts-strategies.md) for the package notice
and current limitations.

## PowerShell scripts are disabled

Installed stack commands are native executables and require no PowerShell profile or execution-policy change. They host application command code internally, and isolated runtime tests pass under Restricted. Source installer and maintenance `.ps1` scripts still require a context permitted to run scripts; use the standalone setup EXE when policy blocks source scripts. Enforced restrictive organisation policy causes the command host to stop with an administrator-policy message.

### Missing stack commands

The executable directory is `%USERPROFILE%\.windows-hybrid-agentic-stack\bin`. An earlier development version used AppData, where a packaged host could redirect files into its private cache. That caused `agent` to be missing in ordinary PowerShell even with the expected PATH entry. The current installer uses the user-directory location instead.

Close and reopen the terminal application after installation. A new tab in an existing terminal may still inherit its old PATH. Inspect:

```powershell
Get-Command agent,localagent,tts-start -CommandType Application
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

To remove local registration, stop TTS and run `Unregister-StackCommands` using the same helper. Installation files and models are retained. See [Remove command registration](../README.md#remove-command-registration-on-one-pc).

### Errors from an older synced profile

Fresh installation writes no profile. Upgrading removes only recognised legacy stack blocks, with exact backups; unrelated profile code is preserved. Malformed, nested or duplicate markers stop migration for review. If startup still names a profile `.ps1`, inspect that file and its backups; it may contain unrelated scripts or blocks from an older installation. Do not change execution policy merely to suppress an obsolete stack loader error. Even an empty profile script can be rejected under Restricted.

A missing local installation now produces an error only when a stack command is invoked. The second PC should remain free of stack startup code when the stack has never been registered there.

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
Get-Command tts-start,tts-stop,tts-status,tts-say
```

If commands are missing, follow [Missing stack commands](#missing-stack-commands) above.

### CUDA is unavailable

Check your NVIDIA GPU:

```powershell
nvidia-smi
```

For Chatterbox, check CUDA availability using the installed strategy environment (adjust `$root` for a custom installation; older installations without `runtime.json` use the legacy root `.venv`):

```powershell
$root = Join-Path $HOME 'AI\WindowsHybridAgenticStack'
$runtime = Get-Content -LiteralPath (Join-Path $root 'tts/runtime.json') -Raw | ConvertFrom-Json
$python = Join-Path (Join-Path $root $runtime.environmentPath) 'Scripts/python.exe'
& $python -c "import torch; print('CUDA available:', torch.cuda.is_available())"
```

If CUDA is unavailable, verify your driver and installed PyTorch build.

### OpenCode commands are not recognised

Open a new PowerShell window and check:

```powershell
Get-Command agent,agentdo,localagent,localagentdo
```

Follow [Missing stack commands](#missing-stack-commands) above to inspect the local executable registration and PATH.

### Perth watermarking fails during TTS startup

The published `resemble-perth==1.0.1` package requires `pkg_resources`. In the reference-machine investigation, setuptools 84.0.0 failed to supply it, while setuptools 80.9.0 allowed the Perth import to succeed. A failed import may surface as `ModuleNotFoundError: No module named 'pkg_resources'` or later as `TypeError: 'NoneType' object is not callable`.

The TTS installer constrains setuptools to `<81` inside its isolated virtual environment and verifies the actual Perth watermarking implementation. Keep this compatibility constraint when maintaining dependencies. Global Python and Whisper do not need modification. Check the stack's `tts\service-errors.log` for the underlying import error before diagnosing another cause.

## F5-TTS strategy

Select `f5-tts` explicitly; Chatterbox remains the default. Use Python 3.11 x64 and the Visual C++ x64 runtime. F5 weights are CC-BY-NC-4.0, so this bundled model is for noncommercial use only. CPU installation uses CPU PyTorch; CUDA uses the pinned CUDA 12.6 build and needs a compatible NVIDIA driver. Do not change global Python packages or execution policy to repair an installation.

Custom voices require a mono 3-12 second WAV and a matching UTF-8 `.txt` transcript beside it. The transcript must contain the words actually spoken. Missing transcripts are rejected rather than automatically downloading an ASR model. List/remove commands manage the installed WAV/text pair. Main uninstall preserves personal voices.

A model hash mismatch preserves the existing file and stops installation. Review it or choose a fresh installation directory; do not edit ownership hashes or disable certificate verification. Runtime inference uses local models only. CPU generation can take substantially longer than Piper. The native speech command waits up to 180 seconds per request; use shorter text or CUDA for long responses. Inspect the private service logs for an actual failure before treating slow inference as an install failure.
