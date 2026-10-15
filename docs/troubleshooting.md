# Troubleshooting

## PowerShell scripts are disabled

On a fresh Windows installation, PowerShell may refuse to run
`.ps1` files with an error similar to:

```text
File cannot be loaded because running scripts is disabled on
this system.
```

### Temporary solution (recommended)

Open PowerShell and run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

Then rerun the installation or configuration script.

This applies only to the current PowerShell session. It does
not permanently modify the system's execution policy.

Alternatively, launch a script directly with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\install.ps1"
```

The command above runs the installer without changing your persistent execution policy.

**Note:** Organisation-enforced execution policies may prevent
these overrides. Only run scripts from sources you trust.

### Synced profiles and missing stack commands

The current profile bootstrap loads `%LOCALAPPDATA%\WindowsHybridAgenticStack\profile.ps1`. This machine-local loader contains the installation path; the synced profile does not. Each PC needs its own local registration. A PC without registration, or whose installed command scripts are missing, should start silently without loading stack commands.

Inspect the profile and local registration:

```powershell
Get-Content -LiteralPath $PROFILE.CurrentUserCurrentHost
```

```powershell
Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'WindowsHybridAgenticStack\profile.ps1') -PathType Leaf
```

If the second command returns `True`, inspect that file:

```powershell
Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'WindowsHybridAgenticStack\profile.ps1')
```

If the local loader is disabled or points to an old directory, restore registration from the repository root without reinstalling dependencies:

```powershell
. .\scripts\profile-loader.ps1
```

```powershell
Install-StackProfileLoader -InstallPath 'D:\AI\AgentStack'
```

Replace the example with the actual installation directory, then open a new Windows PowerShell window. Registration loads only the components present in that directory. If you change the installation directory, pass that directory again on future installer runs or configure `installation.directory`; the installer does not use local registration to choose its destination.

For local-only cleanup, load the helper above and run `Disable-StackProfileLoader`, then open a new window. This keeps the shared bootstrap for other PCs and does not remove software or stop a running TTS service. See [Disable command loading on one PC](../README.md#disable-command-loading-on-one-pc).

Older versions wrote separate agent and TTS blocks with absolute paths. Registration migrates these blocks and creates backups when changing files. If it reports incomplete, nested or duplicate markers, inspect the marked sections and their backups before retrying; the helper leaves both registration files unchanged when marker validation fails.

An absolute path in an old loader is not, by itself, proof of a startup error: the old loaders checked whether their target script existed. Capture the exact PowerShell error before attributing a failure to profile sync. If script execution is blocked, review [PowerShell scripts are disabled](#powershell-scripts-are-disabled); execution policy is specific to each machine.

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

If commands are missing, check the current PowerShell profile and execution policy:

```powershell
Get-Content $PROFILE.CurrentUserCurrentHost
```

```powershell
Get-ExecutionPolicy -List
```

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

Check your profile configuration:

```powershell
Get-Content $PROFILE.CurrentUserCurrentHost
```

If script execution is blocked, review [PowerShell scripts are disabled](#powershell-scripts-are-disabled).

### Perth watermarking fails during TTS startup

The published `resemble-perth==1.0.1` package requires `pkg_resources`. In the reference-machine investigation, setuptools 84.0.0 failed to supply it, while setuptools 80.9.0 allowed the Perth import to succeed. A failed import may surface as `ModuleNotFoundError: No module named 'pkg_resources'` or later as `TypeError: 'NoneType' object is not callable`.

The TTS installer constrains setuptools to `<81` inside its isolated virtual environment and verifies the actual Perth watermarking implementation. Keep this compatibility constraint when maintaining dependencies. Global Python and Whisper do not need modification. Check the stack's `tts\service-errors.log` for the underlying import error before diagnosing another cause.
