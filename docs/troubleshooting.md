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

If script execution is blocked, review [PowerShell execution policy](#powershell-execution-policy).
