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

The installer command above will work once the installer is added.

**Note:** Organisation-enforced execution policies may prevent
these overrides. Only run scripts from sources you trust.
