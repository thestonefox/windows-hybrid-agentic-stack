# Agent runtimes and strategy authoring

WHAS separates runtime selection from model selection. OpenCode is the default
adapter for questions without tools, tool-enabled tasks and CLI sessions.
OpenCode is the only shipped runtime. Additional integrations require a
separate agreed scope. Authentication stays in OpenCode's own storage.

GUI Conversation and One-off question on This PC use Ollama's chat API
directly, without an agent runtime or file tools. The GUI sends completed
user/assistant turns as message history for Conversation; one-off questions
send only their current message. This history lasts for the current window
and does not use an OpenCode session ID. Run a task still uses OpenCode.

## OpenCode

Install the external OpenCode prerequisite through the
[installation guide](installation.md#5-install-opencode-cloud-or-local-agents).
WHAS installs the compatibility read agent and task agent without replacing
your global config. Unified questions and CLI/cloud conversations use a
per-request `whas-chat` profile with tools denied.
It preserves OpenCode's native provider/model selection unless overridden.

```powershell
whas agent list
```

```powershell
whas agent check opencode
```

```powershell
whas chatc --runtime opencode --no-voice
```

This opens the native interactive CLI in the current terminal. One-shot
`ask`/`perform` calls do not automatically continue earlier sessions.
WHAS uninstall does not remove this external prerequisite or its account data.

## Sessions and memory

Native interactive chat starts a new conversation unless a registered session
is explicitly selected. WHAS does not use a global "continue most recent" flag.
For a machine-readable turn, also used by cloud chat in the GUI:

```powershell
whas chatl --runtime opencode --message "Remember this number: 42"
```

The JSON response contains `answer`, `sessionId`, `runtime` and `location`.
Use the returned ID from the same workspace and route:

```powershell
whas chatl --runtime opencode --session RETURNED_SESSION_ID --message "What number?"
```

WHAS records only session association metadata beneath `agents/data/whas`:
native ID, runtime, local/cloud route, workspace, user SID and creation time.
It rejects continuation through another route, runtime, workspace or user.
Unknown/external IDs must be inspected through the native runtime; there is no
automatic adoption. Native interactive sessions that do not return an ID cannot
be registered by WHAS automatically. Their native history remains available.

Resuming a native session, or sending the next local GUI conversation message,
sends its previous messages to the selected provider. One-off questions do
not use or update the GUI conversation history. Changing the GUI route/model,
starting a new conversation or closing the window clears its local context.
Persistent memory across conversations is a separate native feature. OpenCode
keeps its own native storage; WHAS does not provide a shared memory service.

```powershell
whas session list
```

```powershell
whas session forget opencode RETURNED_SESSION_ID --yes
```

Forgetting removes only the WHAS association. Native transcripts, memory,
skills and credentials remain. Inspect/reset/delete those using the runtime's
documented tools; WHAS has no generic memory-erasure command. Uninstall retains
personal agent storage. Delete retained personal data only after reviewing it
and backing up anything needed. Routine diagnostics/builds never include it.

## Creating a strategy

Strategies are trusted executable code, not a sandbox or a plugin permission
boundary. Review third-party packages before installing them. A source package
lives at `agents/strategies/ID/` and declares every shipped asset in
`manifest.json`. Rebuild/reinstall the stack after adding a package; dropping
unrecorded scripts into an installed application does not bypass ownership
verification.

The manifest declares schema version `1`, a lower-case `id` matching the folder,
`name`, `version`, `executable`, `documentation`, `files`, `entrypoints` and
boolean capabilities `ask`, `perform`, `chat`, `local`, `sessionResume`,
`managedInstall`. Only promise operations the adapter can actually enforce.
IDs and executable names accept lower-case letters/digits/hyphens, start with
a letter and have at most 48 characters. Asset paths must stay inside the
strategy directory; missing assets and reparse points are rejected.

`entrypoints.adapter` names a declared `.ps1` accepting:

```powershell
param([string]$Action,[string]$Location,[string[]]$Arguments,
      [string]$Session,[bool]$Voice,[string]$Root)
```

Use `Get-StackConfiguration $Root`, preserve literal arguments and reject
unsupported options before launching. Chat `--message` must produce one JSON
response with the fields above and the actual native session ID. Keep prompts,
credentials and internal provider events out of diagnostics. Never implement
silent cross-provider fallback.

`managedInstall` requires declared `install` and `uninstall` entrypoints.
Install receives `Root`; uninstall receives `Context` containing `InstallPath`
and `RuntimeId`. Pin/check upstream code, isolate dependencies under
`agents/runtime/ID`, use ownership tracking, record interrupted installs where
possible and keep personal data under `agents/data` or an excluded native
`home/profiles` tree. Restore process variables
and any temporary PATH effects. Do not install services implicitly.

Hooks execute through the verified script loader. Native hosts parse scripts
with their real file identity, so script-relative paths work without changing
saved execution policy. The main uninstaller verifies the manifest/package
hashes before running the declared hook, then revalidates tracked files.
Uninstall hooks stop only proven owned processes; common cleanup removes only
unchanged owned files and records hook completion in its receipt.

Test capability rejection, quoting, explicit routes, fresh/resumed sessions,
failed installation, modified/unowned files, process cleanup and main uninstall
in isolated fixtures and a fresh Windows environment before shipping a strategy.
