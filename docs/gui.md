# WHAS graphical application

`whas.exe` is the command-line interface. `whas-gui.exe` is the graphical
entry point for first-run configuration, everyday use and removal. Both
PowerShell and EXE installation provide the same command-line launchers and
`whas-gui.exe` in the installation folder. The built-in
Windows Forms/.NET Framework interface needs no separate UI runtime.
The executables are unsigned; read [verification and Windows warnings](installation.md#unsigned-exe-and-windows-warnings).

## First run and feature management

Double-click the included `whas-gui.exe` after extracting the repository ZIP.
It embeds setup and does not require a
separate installer EXE beside it. Before a complete installation exists, it
opens feature configuration. After installation it opens **Ask & chat**;
feature configuration and removal remain available in the same window.
An interrupted or malformed installation record opens configuration/recovery.

1. **Features:** cloud/local/speech components, destination and default route.
   Select all, or select none for the shared app without optional components.
2. **Models & engines:** multiple selections with separate defaults. Custom
   Ollama model names are accepted; memory/download requirements vary.
3. **Prerequisites:** read-only results and official installation links.
   Install missing external prerequisites yourself, then select **Check again**.
4. **Apply features:** inspect the backend plan, then confirm changes.
5. **Remove WHAS:** preview cleanup, optionally retain managed models, then confirm.

Additional runtime integrations remain deferred pending agreement.

Changing a selection requires another passing prerequisite check. A base-only
installation with no optional components provides shared management and GUI
applications; install an agent runtime before issuing AI requests.

Progress and diagnostic output remain visible during operations. Cancellation
stops request-owned work where supported; it does not undo changes already made.
Interrupted installs retain ownership information where recording can complete.
Do not delete the ownership record as a way of retrying.

Maintenance uses the same installation root, hooks, file verification and
receipts as source uninstall. Personal references, agent data and modified
files are retained. Refresh PATH or reopen existing terminal applications after
install/uninstall; an already-running terminal cannot be updated by a child.

Normal graphical launch runs the same application from a temporary copy outside
the installation. This lets Windows update/remove its installed EXE while the
window stays open. Successful setup switches to usage; successful removal
returns to first-run configuration. Close other installed WHAS windows before
removal. The temporary copy cleans itself up after its window closes.

The PowerShell scripts remain the documented terminal setup/removal route.
The legacy `whas-setup.exe` developer build still supports explicit console
options; it is not required by the graphical application and is not installed
as a second GUI. Opening the graphical application never applies changes
automatically.

## Use and configure

Open `whas-gui.exe` from the installation folder. The main tabs provide:

Additional runtime integrations remain deferred pending agreement.

Additional runtime integrations remain deferred pending agreement.

See [CLI settings](cli.md) and [agent sessions and memory](agent-strategies.md#sessions-and-memory)
for scope, routing and personal-data behaviour.
