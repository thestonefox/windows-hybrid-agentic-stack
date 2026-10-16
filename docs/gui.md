# Graphical setup and everyday use

Both PowerShell and EXE installation provide the same command-line launchers,
`whas-gui.exe` and `whas-setup.exe` in the installation folder. The built-in
Windows Forms/.NET Framework interface needs no separate UI runtime.
The executables are unsigned; read [verification and Windows warnings](installation.md#unsigned-exe-and-windows-warnings).

## Install and uninstall

Double-click `whas-setup.exe`, or run it without arguments. Its screens are:

1. **Choose:** cloud/local/speech components, destination and default route.
2. **Models & engines:** multiple selections with separate defaults. Custom
   Ollama model names are accepted; memory/download requirements vary.
3. **Check:** read-only prerequisite results and official installation links.
   Install missing external prerequisites yourself, then select **Check again**.
4. **Review & install:** inspect the backend plan, then confirm installation.
5. **Uninstall:** preview cleanup, optionally retain managed models, then confirm.

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

Opening maintenance closes the usage window and runs setup from a temporary
copy outside the installation. This lets Windows remove the installed EXEs.
Close any other WHAS windows before uninstalling. The temporary setup copy
cleans itself up after its window closes. For console uninstall, keep the EXE
outside the installation directory, as described in the installation guide.

Explicit console options remain supported, such as `--check`, `--plan`,
`--install --yes` and `--uninstall --apply`. `--help` lists them. Opening setup
without options chooses the GUI; it does not start installing automatically.

## Use and configure

Open `whas-gui.exe` from the installation folder. The main tabs provide:

Additional runtime integrations remain deferred pending agreement.

Additional runtime integrations remain deferred pending agreement.

See [CLI settings](cli.md) and [agent sessions and memory](agent-strategies.md#sessions-and-memory)
for scope, routing and personal-data behaviour.
