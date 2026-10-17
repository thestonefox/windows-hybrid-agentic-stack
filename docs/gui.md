# WHAS graphical application

`whas.exe` is the command-line interface. `whas-gui.exe` is the graphical
entry point for first-run configuration, everyday use and removal. Both
PowerShell and EXE installation provide the same command-line launchers and
`whas-gui.exe` in the installation folder. The built-in
WPF/.NET Framework presentation needs no separate UI runtime.
The executables are unsigned; read [verification and Windows warnings](installation.md#unsigned-exe-and-windows-warnings).

## First run and feature management

Double-click the included `whas-gui.exe` after extracting the repository ZIP.
It embeds setup and does not require a
separate installer EXE beside it. Before a complete installation exists, it
opens feature configuration. After installation it opens **Assistant**;
feature configuration and removal remain available in the same window.
An interrupted or malformed installation record opens configuration/recovery.

1. **Features:** cloud/local/speech components, destination and default route.
   Select all, or select none for the shared app without optional components.
   Choose **Cloud** or **This PC** under **Default processing**. Fresh setup
   shows Cloud; reconfiguring loads the saved choice from the selected folder.
   This location is used unless a request explicitly chooses the other route.
2. **Models & engines:** multiple selections with separate defaults. Custom
   Ollama model names are accepted; memory/download requirements vary.
   Local AI requires at least one selected model. Installed Ollama models are
   listed for reuse; if none are installed, the GUI preselects `qwen2.5:1.5b`
   as a small starter (about 1 GB). You can choose another model instead.
   **Refresh available models** checks Ollama again and preserves your choices.
   Missing selected models download only when you apply features. Cloud-only
   setup downloads no local models.
   Each selected speech engine has its own device setting. Chatterbox and F5
   offer CPU and Prefer GPU directly beneath their checked engine checkbox;
   Piper has no device control or extra device text. Prefer GPU uses GPU when
   detected, otherwise CPU, and setup reports the resolved device. Selecting
   Piper does not restrict the device chosen for another engine. Choices apply
   to that engine's installation and are saved in its runtime record.
3. **Prerequisites:** results with **Open download page** and **Install with WinGet**
   actions for missing Python 3.11, Visual C++ x64, OpenCode and Ollama.
   WinGet installs the selected package, shows output in the activity log and
   automatically checks prerequisites again after success. It accepts source
   and package agreements; Windows may request administrator approval. If
   WinGet is unavailable, its button is disabled with guidance to use the
   download page. After manual installation, select **Check Again**. NVIDIA
   drivers use the official download page.
4. **Apply features:** automatically reviews the checked selection and shows
   the installation folder, features, models and engine/device choices in cards.
   **Check Again** refreshes the review. The activity log stays closed for a
   successful review. Confirm installation with **Apply selected features**
   after reviewing the current plan.

The primary installer action stays fixed at the bottom right, outside the
scrolling page. Its width fits the longest action label and stays the same
on every step, so **Show activity log** stays in place to its left. The actions are
**Choose Models & Engines**, **Check Prerequisites**, **Go to Apply Features**, then
**Apply selected features**. The prerequisites action is disabled until the
current selection passes; installation requires a current review. Editing a
selection requires another prerequisite check and review.

Fresh setup has no **Remove WHAS** navigation entry. A tracked existing or
interrupted installation retains a recovery removal route; completed uninstall
records do not show it. Installed-app removal remains under Maintenance.

The wizard above is only for first installation. After installation,
**Configuration > Maintenance > Features** uses maintenance cards: **Add** for an absent
feature, **Repair** and **Remove** for a configured one. Configured routes do
not prove account access or model availability; speech status comes from
installed engine records. There are no setup steps or Continue buttons here.

Add or Repair opens relevant options on the same page. Run **Check readiness**,
**Review changes**, then **Apply changes**. The activity log shows the preview;
changing options requires a fresh check and review. Cloud/Local removal checks
shared app readiness, previews its update and asks for confirmation before
updating commands and removing that WHAS route. Provider accounts, external
prerequisites and local model files are retained. Add the feature again to
restore requests. Speech removal opens **Speech**, with per-engine preview and
removal actions; personal references are retained. The **Removal** section
under **Configuration > Maintenance** removes the
whole tracked WHAS installation. Preview opens the activity log and brings the
Uninstall action back into view. Successful removal returns to first-run setup
with the target path retained. Individual Ollama model removal is separate.

Changing a selection requires another passing prerequisite check. A base-only
installation with no optional components provides shared management and GUI
applications; install an agent runtime before issuing AI requests.

The first-run sidebar switches between setup pages. Default model and speech-engine selectors
are labelled separately from the download selections. Opening **Prerequisites**
runs the initial read-only check; **Check Again** reruns it after changes.

Each model and speech-engine name has a licence information icon. Hover or
focus it with the keyboard for a tooltip; select it for details and source
links. Engine/package terms and downloaded model/asset terms are identified
separately using strategy manifests. The built-in Qwen choices link to their
upstream licences and Ollama pages. Custom model licences are not inferred:
they show **Licence not verified**. No network lookup runs when hovering.

The main window uses WPF with reusable Fluent-style settings cards, switches
and controls. It follows the Microsoft WinUI Gallery patterns without requiring
the Windows App SDK runtime. Prerequisites use content-sized status rows on one
scroll surface. Supported missing components have **Open download page** and
**Install with WinGet** actions beneath their details. WinGet output appears in
the activity log and a successful install triggers another prerequisite check.
If WinGet is unavailable, its action is disabled and the page explains the
download-page fallback. NVIDIA drivers use the official download page.

Activity and status remain visible during operations. **Show activity log** expands
the compact diagnostic panel; execution errors expand it automatically.
When expanded, **Clear log** sits beside **Hide activity log**. Clearing removes
the displayed diagnostic history without clearing answers or cancelling work;
new output continues to appear. **Cancel** is
shown only for a submitted assistant request and its speech output. Cancellation
stops request-owned work where supported; it does not undo changes already made.
Interrupted installs retain ownership information where recording can complete.
Do not delete the ownership record as a way of retrying.

Progress occupies a permanently reserved strip at the bottom edge. Showing
progress does not shift the footer buttons or message composer. During a
request, Cancel replaces Send at the same width, including its speech output.
Loading settings or model choices shows a disabled Send until ready.
The activity log link stays
at the right edge; setup, model discovery and configuration work cannot be cancelled.
The bordered response area uses the main canvas colour in both themes.
Messages and replies are read-only selectable text: drag to select and use
Ctrl+C or the Copy context action. Selection does not add an input border.
Questions appear in padded blue bubbles above their replies; streaming updates
preserve text selection. New replies scroll into view automatically unless
you are actively selecting text. Available folder paths in Workspaces are
also selectable and copyable without editing the saved paths.

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

To update an existing installation, open the new repository EXE and use
**Configuration > Maintenance > Features > Repair shared app files**. Check readiness,
review changes and apply there. Optional engines/models remain installed. Close
other WHAS windows before applying the update. Opening a newer EXE alone does
not replace an older installed CLI backend. The repository EXE can use the
existing installation/configuration directly: model discovery queries Ollama
and OpenCode rather than requiring a newer WHAS backend command. Missing or
failed discovery keeps saved model choices and shows guidance in Models;
it does not turn opening Assistant into a failed installation operation.

Open `whas-gui.exe` from the installation folder or the repository. After setup,
Assistant fills the window. The top-right cog opens **Configuration** (also
identified by its tooltip); **Back to Assistant** appears in the same position.
There is no installed-app sidebar.

- **Assistant:** a large response area appears above the multiline composer.
  An empty response area greets you; the input has a placeholder that disappears
  when typing. Enter sends; Shift+Enter inserts a new line. Beneath the input, Run on and Speak the
  answer sit on the left; Operation and Send sit on the right. Run on offers
  just This PC and Cloud, with the saved default first and marked `(Default)`.
  Sending immediately adds your message to the response area with animated
  waiting dots underneath. The reply replaces those dots; cancellation or
  failure replaces them with a status message. New drafts are preserved when
  a reply arrives.
  **New chat** sits on the bottom-right edge of the response border. It clears
  displayed messages, the draft and local history, and resets the cloud session
  ID. It is unavailable while an operation is running. OpenCode's separately
  stored native transcripts and WHAS session associations remain.
  Operation defaults to Conversation, followed by Run a task and One-off
  question. One-off questions and tasks are independent; Conversation
  keeps this window's conversation history. Local chat calls Ollama directly
  and displays streamed reply text as it arrives, without starting OpenCode.
  Only Run a task uses file or system tools. Completed answers appear before
  optional playback; speech diagnostics stay in the activity log. A playback
  failure does not discard the answer.
- **Configuration:** tabs for General, Workspaces, Models, Speech,
  Conversations and Maintenance. Maintenance groups Features above Removal.

General contains headings for appearance and everyday request defaults.
**Appearance** offers **System theme**, **Light** and **Dark**. System theme
follows the Windows app theme, including changes while the window is open.
Workspaces shows every saved folder with an individual Remove action. All
listed folders and their subfolders are available to Run a task. The
**Starting folder** chooses where commands and relative paths begin; the other
folders stay available. Changing the list or starting folder starts a new
conversation. Removing an entry never deletes its folder or files. A missing
starting folder must be replaced before running a task. Ordinary chat does
not need workspace access.
Workspace and installation-folder pickers use the Windows file-browser dialog
in folder mode, with an address bar and **Select folder** button.

For OpenCode, each GUI task supplies directory grants through its
[inline configuration](https://opencode.ai/docs/config/#precedence-order),
using [external-directory rules](https://opencode.ai/docs/permissions/#external-directories).
Saved paths are also provided as request context so the model knows which
folders are available. This applies with an older installed WHAS backend too;
the installation's `opencode.json` and parent environment are not rewritten.
Task tool permissions still apply. This is runtime access
configuration, not an operating-system filesystem sandbox.

Appearance and workspace choices are saved automatically in the current user's
`%LOCALAPPDATA%\WindowsHybridAgenticStack\gui-preferences.json`. Repository
and installed EXE copies share these personal GUI preferences. They are
separate from shared CLI/provider/model settings and contain no credentials.
Concurrent conflicting saves are rejected with instructions to reopen the
window. Personal preferences are retained when WHAS is removed.

Models groups runtime choices, cloud models and local models under headings.
OpenCode is the supported runtime. Cloud and local models are selectors, populated from
OpenCode's configured-provider model list and Ollama's installed models.
OpenCode discovery uses its documented [models command](https://opencode.ai/docs/cli/#models).
Local tasks expose Ollama's discovered models through OpenCode's
[inline configuration](https://opencode.ai/docs/config/#precedence-order).
This also supports models selected after installation without rewriting saved
provider settings or replacing existing model definitions.
**Use OpenCode default** means WHAS does not override OpenCode's model choice;
it does not mean no cloud model exists. A catalogue entry does not guarantee
provider access. Shared settings dropdowns save automatically when changed;
failed saves restore the previous value and show the error in the activity log.
Loading, reloading and refreshing choices do not save settings. Reload shared
settings after CLI edits. Changes under Models save shared defaults for CLI
and GUI requests; the Assistant's Run on choice only overrides the current
window's requests. The selected runtime is used for tasks and cloud requests;
GUI plain local chat uses Ollama directly.

Speech groups startup/hardware defaults and engine/voice management.
**Stop speech engine after idle (minutes)** saves automatically. Zero disables
idle shutdown. A changed timeout applies when the engine next starts and does
not interrupt speech already running.
It loads its engine/voice inventory automatically when opened, and can be
refreshed explicitly. Available strategies remain visible with installation
status. Uninstalled engines cannot be previewed or set as default; unsupported
reference controls are hidden. Piper shows its packaged-voice information
and playback action, without unsupported import/default/deletion forms.
F5 shows its WAV plus matching UTF-8 transcript requirements before choosing a
recording. Its import form displays the expected `.txt` path and whether it
exists. Uninstalled engines show their requirements and installation action;
voice-management forms appear after installation. Engine removal stays beside the selected
engine; startup/hardware settings use a headed, themed card below voices.
The hardware selector is hidden for strategies that support only one device.

To add a custom voice on an engine that supports reference recordings:

1. Select the installed speech engine.
2. Under **Add a voice**, choose a WAV recording. This only stages the file;
   it does not submit or play it. The original recording is not changed.
3. Review the suggested **Voice name**, or enter another unique name using
   1–40 letters, numbers, hyphens or underscores, starting with a letter/number.
   `default` is reserved. Existing voices are never overwritten.
4. For F5, put a matching UTF-8 `.txt` transcript beside the WAV with the same
   filename. The form explains missing/invalid transcripts before saving.
5. Tick **Make this the default voice for this engine** if wanted, then select
   **Save voice**. This stores the reference and, only when ticked, saves its
   default. It does not train model weights or play audio. If saving the default
   fails, the voice remains available; retry **Set this as default voice**.

After saving, the new voice is selected under **Saved voices**. These actions
are separate:

- **Play test phrase** generates and plays a fixed sentence with the selected
  saved voice. It does not play the original recording or change defaults.
- **Set this as default voice** saves the selected voice for that
  engine. It does not change which engine is the default. A voice already saved
  as that engine's default does not need saving again.
- **Delete this voice** removes the stored reference/cache, after confirmation.
  The built-in voice cannot be deleted. Choose another default before deleting
  a voice currently used as the default. Your original imported WAV is retained.

Piper supports its packaged voice and does not support adding reference voices.
Each engine has its own voice list and saved default. The selected test voice
does not become the default merely by selecting it.

**Set default engine** saves which engine Assistant uses for future spoken
answers. Selecting an engine in Speech only opens its management panel.
Previewing a voice runs the selected engine for that preview, without changing
the default. The next Assistant answer switches back to the saved default if
necessary; you do not need to preview an engine to make a saved default take effect.

Older installed command layers misreported Chatterbox storage filenames as
voice names and validated defaults against the wrong filename. The new GUI
reads existing Chatterbox references correctly without renaming or recreating
them. Voice import/removal, default changes and GUI playback use bundled code, so
an older installed validator cannot reject a valid voice default. Defaults
remain in the shared configuration used by CLI speech commands.

Models includes **Manage OpenCode accounts** for provider sign-in. The temporary
loopback server uses a random password shown only in that window and stops when
the window closes. Conversations contains the cloud session ID, New
conversation and association management. Local conversation history stays in
the current window and is sent with each Ollama request. One-off questions
neither read nor alter that history. The New chat link beneath the replies clears
the screen, discards local conversation history and resets the current cloud
session ID so the next message starts fresh. It does not delete OpenCode's
separately stored native transcripts. New conversation, model or route changes,
or closing the window clears it. Cloud questions and conversation use a managed
OpenCode chat profile with tools denied. Forgetting an association does not
erase native history or credentials.

GUI playback reads a completed reply using the separate speech command,
including Conversation replies. Native interactive CLI chat speech remains
unsupported. Maintenance groups direct feature actions above whole-app removal.
The GUI does not answer native permission prompts automatically; unsupported
interactions fail or require OpenCode's native interface.

See [CLI settings](cli.md) and [agent sessions and memory](agent-strategies.md#sessions-and-memory)
for scope, routing and personal-data behaviour.
