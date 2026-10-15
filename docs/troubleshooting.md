# Troubleshooting

## PowerShell scripts are disabled

Installed stack commands are native executables and require no PowerShell profile or execution-policy change. They host application command code internally, and isolated runtime tests pass under Restricted. Source installer and maintenance `.ps1` scripts still require a context permitted to run scripts; a native installer is not yet available. Enforced restrictive organisation policy causes the command host to stop with an administrator-policy message.

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

Check CUDA availability using the installed Python environment:

```powershell
& "$HOME\AI\WindowsHybridAgenticStack\.venv\Scripts\python.exe" -c "import torch; print('CUDA available:', torch.cuda.is_available())"
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
