# Planned CLI, agent and graphical interface work

This is the implementation checklist for the agreed direction. Items below are
planned unless explicitly marked complete. Examples describe proposed commands;
they must not be presented as commands available in the current release.

## Work boundary and current status

- [ ] Wait for the user to confirm their installation, testing and uninstallation
  are complete before changing installation or runtime code or running installs.
- Documentation of this plan can proceed during that wait.
- Keep changes local. Do not push, publish releases or create tags without an
  explicit request.
- Commit completed work in cohesive commits using Conventional Commits with a
  scope. Keep every subject and body line at or below 72 characters.
- Use isolated tests first. Any local or Sandbox installation test must restore
  the state that existed before that test. Keep evidence and fixtures outside
  the repository; remove installed test components and stop test services.
- Mark checklist items complete only after their acceptance checks pass. Record
  actual validation and limitations in the relevant commit descriptions.
- Update this document when a decision changes or a missing case is discovered.

Already implemented: prerequisite checks through `install.ps1 -Check`, improved
uninstall progress, multiple TTS engines and their management commands, and
unsigned console setup/release packaging. The current EXE is a console installer.
The unified CLI and graphical interfaces below are not implemented.

## 1. Fix the silent final installation stage first

### Confirmed defect

After printing `Runtime local model`, installation can remain silent while
`Complete-StackInstallationTracking` scans the installation tree and hashes its
files. This ownership record enables safe uninstallation. The function currently
calls `Get-StackInstallationTree` and `Get-StackFileSHA256` without passing progress.
Dependency output and uninstall progress do not cover this stage. The previous
claim that installation progress was complete was inaccurate.

### Required work

- [ ] Announce finalisation before it starts, explaining that installed files are
  being recorded for safe uninstall.
- [ ] Pass progress through tree enumeration and file hashing, including inside
  large individual files. Report phase, completed count, total when known and
  elapsed time. Use the existing progress helpers where suitable.
- [ ] Cover initial ownership scans and repeat-install verification as well as
  successful finalisation and interrupted-install tracking.
- [ ] Review every lengthy install/uninstall phase for the same silence:
  dependency installation, model download/verification, strategy hooks, command
  compilation/registration, ownership checks, file removal and receipt writing.
- [ ] Give slow subprocess operations visible output or periodic activity with
  elapsed time. A phase announcement alone does not solve a long silent wait.
- [ ] Throttle output to useful intervals, approximately every two seconds for
  long operations. Do not invent percentages or estimated completion times.
- [ ] Preserve failure exit codes, interrupted-install recovery and ownership
  verification. Do not skip hashes to make installation look faster.

### Acceptance

- [ ] Exercise many small files and at least one large file; confirm the final
  tracking stage visibly updates throughout its work.
- [ ] Confirm both source setup and standalone console setup show the updates.
- [ ] Verify resulting ownership hashes and successful uninstall remain correct.
- [ ] Exercise failed and repeat installation paths, without changing profiles,
  saved policies or unrelated files.
- [ ] Recheck uninstall feedback, including the work immediately after approval.

## 2. Establish the unified command interface

### Agreed direction

Use a distinct `whas` namespace. Support readable flags and convenient shortcuts
through the same implementation:

| Proposed command | Behaviour |
|---|---|
| `whas ask` | Independent question using saved defaults |
| `whas askl` | Equivalent to `whas ask --local` |
| `whas askc` | Equivalent to `whas ask --cloud` |
| `whas perform` | Independent task using saved defaults |
| `whas performl` | Equivalent to `whas perform --local` |
| `whas performc` | Equivalent to `whas perform --cloud` |
| `whas chat` | Contextual conversation using saved defaults |
| `whas chatl` | Equivalent to `whas chat --local` |
| `whas chatc` | Equivalent to `whas chat --cloud` |
| `whas configure` | Change configuration after installation |

A one-shot invocation is independent of earlier invocations. A task may still
involve multiple model/tool steps within that invocation. Conversation history,
memory across conversations and background autonomy are separate capabilities.

- [ ] Implement one parser/dispatcher for long forms and shortcuts.
- [ ] Preserve model overrides and existing speech/output options; document their
  mapping instead of silently dropping them during the naming change.
- [ ] Define `ask` restrictions and `perform` tool permissions explicitly.
  Preserve the existing restricted/task distinction; do not silently broaden it.
- [ ] Keep `agent`, `localagent`, `agentdo` and `localagentdo` as compatibility
  commands with their existing one-shot and provider-selection behaviour.
- [ ] Expose useful help, configuration inspection and clear exit codes.
- [ ] Reject contradictory local/cloud options and ambiguous shortcut overrides.
- [ ] Never silently fall back from local to cloud or vice versa.

### Acceptance

- [ ] Shortcuts and equivalent flags produce identical routing and permissions.
- [ ] Existing command behaviour and argument quoting remain compatible.
- [ ] Missing defaults, unavailable models and unsupported options give actionable
  errors before invoking a provider or executing tools.
- [ ] Existing TTS command use remains functional during the transition.

## 3. Share configuration across every interface

- [ ] Set initial defaults during installation. Allow them to change afterwards
  through `whas configure`, using a human-readable interactive menu.
- [ ] Define precedence as explicit command choice, then saved configuration,
  then documented built-in defaults.
- [ ] Support default local/cloud preference, runtime, cloud/local models, TTS
  engine, voice and speech-output preferences.
- [ ] Decide whether `ask`, `perform` and `chat` share a runtime default or have
  per-operation overrides; settle this before fixing the schema.
- [ ] Reconcile the existing TTS default registry with configuration access so
  there is one authority per setting. Do not introduce competing GUI defaults.
- [ ] Define scope for per-installation, per-user and optional project settings.
  Explain which setting is effective when more than one scope exists.
- [ ] Validate settings and schema versions; migrate existing installations and
  retain unrelated user settings.
- [ ] Use atomic writes and prevent concurrent CLI/GUI changes from losing data.
- [ ] Changing settings must not silently install software. Explain missing
  components and offer a separate, explicit install operation.
- [ ] Keep provider credentials in supported credential storage, separate from
  ordinary shared configuration and distributable build assets.
- [ ] An open GUI must refresh settings changed by the CLI, or clearly identify
  changes that require restart. In-flight work must have defined behaviour.

### Acceptance

- [ ] A change through CLI configuration appears in the GUI and vice versa.
- [ ] Concurrent writes cannot corrupt or silently overwrite configuration.
- [ ] Invalid configuration produces a useful recovery path, not partial setup.
- [ ] Command-line overrides do not unexpectedly rewrite saved defaults.

## 4. Add agent runtime strategies and contextual use

### Existing behaviour to preserve

Additional runtime integrations remain deferred pending agreement.

### Strategy contract

- [ ] Extract OpenCode into the first strategy without changing current defaults.
- [ ] Define a discoverable packaged strategy layout and validated manifest,
  following the useful lifecycle aspects of the TTS strategy design.
- [ ] Specify pinned versions/sources, prerequisites, platform support and owned
  files. Treat strategy hooks as trusted executable code, not sandboxed data.
- [ ] Define check, install, verify, configure, launch and uninstall operations.
- [ ] Declare one-shot, interactive, session continuation, local-provider,
  structured-output, permission-control, memory and background capabilities.
- [ ] Expose each runtime's native CLI where needed; do not force all its native
  features into a falsely equivalent common interface.
- [ ] Validate unsupported operations and provider/runtime combinations before
  starting work. Existing authentication must not be assumed transferable.
- [ ] Keep runtime selection independent of model provider and model selection.
- [ ] Allow multiple agent runtimes to be installed and run concurrently where
  supported. Do not copy TTS's single-active-service restriction blindly.
- [ ] Own and stop only services/processes created for this installation. Keep
  background services opt-in rather than an implicit consequence of installation.
- [ ] Integrate each strategy into the main uninstaller and interrupted-install
  recovery. Preserve unrelated pre-existing installations and shared software.

### Sessions and memory

Additional runtime integrations remain deferred pending agreement.

## 5. Expand installer model selection

Ollama already supports multiple installed models. Our wrappers can override the
configured model; setup currently establishes one default managed model. There
is no need to invent a new model-switching system.

- [ ] Let setup select multiple models and choose the local default separately.
- [ ] Distinguish existing models, original downloaded models and stack-created
  configured aliases. Track ownership of each appropriately.
- [ ] Show download sizes and hardware guidance when known, with clear uncertainty
  instead of assuming every model suits every machine.
- [ ] Maintain a small reviewed model catalogue without preventing supported
  explicit model overrides. Catalogue contents remain to be chosen.
- [ ] Reuse or retain pre-existing models, handle failed/repeated downloads and
  ensure uninstallation removes only verified installer-owned models by default.
- [ ] Preserve the explicit retain-models option and changed-model protections.
- [ ] Offer installed TTS engines as independent selections with a saved default,
  using the engine-management implementation already present.

## 6. Build graphical setup and uninstallation

Build this after CLI/configuration/strategy contracts are stable. Select the
Windows UI toolkit and source-install build/distribution approach deliberately;
neither is decided yet. Continue documenting unsigned executable behaviour.

### Proposed application entry points

- `whas-setup.exe`: graphical installation, maintenance and uninstallation.
- `whas-gui.exe`: everyday use with Settings accessible from inside the app.
- `whas.exe`: full command-line use.

The three-entry-point layout is a proposal, not a requirement to maintain four
independent installer/uninstaller/configuration/usage applications. Start-menu
shortcuts can open setup, settings or uninstall screens directly.

### Shared backend requirements

- [ ] Both source and EXE installation provide CLI and GUI capabilities. A source
  installation must build or obtain the GUI assets through a defined process.
- [ ] Use the same installation identity, configuration, ownership records,
  strategy hooks and cleanup rules for both interfaces.
- [ ] Detect existing installations and offer maintenance instead of creating an
  accidental second copy. Handle explicitly requested custom roots deliberately.
- [ ] Expose structured check results, phase/progress events, errors and receipts
  for both terminal and GUI consumers. Do not parse coloured console text.
- [ ] Keep CLI automation, noninteractive flags and exit codes working.

### Installation screens

1. Components: cloud, local and speech, plus optional agent runtimes.
2. Models/engines: multiple selections, default choices and relevant download,
   hardware and licence information.
3. Prerequisites for those selections: installed, missing or incompatible.
   Explain manual prerequisite installation with official links and a **Check
   again** action. Do not silently install missing external prerequisites.
4. Review: destination, downloads, defaults and proposed system changes.
5. Installation: current operation, real progress/activity and useful errors.
6. Completion: authentication/setup steps and ways to launch CLI or GUI use.

- [ ] Define cancellation and failure recovery; cancellation must not be labelled
  rollback if installed changes remain. Preserve recoverable ownership records.

### Uninstallation screens

- [ ] Preview files, commands, models and services affected, plus preserved data.
- [ ] Offer retain-managed-models and clearly distinguish personal data deletion.
- [ ] Require confirmation before applying, with visible progress and final receipt.
- [ ] Test EXE install -> GUI uninstall, source install -> GUI uninstall,
  EXE install -> source uninstall and source install -> source uninstall.
- [ ] Verify service shutdown, command/PATH cleanup, changed-file preservation
  and repeated uninstall through both interfaces.

## 7. Add graphical everyday use and settings

- [ ] Provide one-shot questions, independent tasks and contextual conversations.
- [ ] Show effective runtime, provider and model with local/cloud selection.
- [ ] Provide session creation/resumption and clearly expose memory behaviour.
- [ ] Include TTS engine/voice selection and speech controls.
- [ ] Open shared Settings from the usage app; never create a separate GUI config.
- [ ] Present tool permission requests and failures faithfully. The GUI must not
  bypass permissions or claim a task completed when the backend failed.
- [ ] Provide a complete first-use path without requiring a terminal, including
  authentication guidance, prerequisite recovery, settings and uninstall access.

## Suggested commit sequence

These are commit boundaries, not pre-approved implementation details. Split
further when needed; keep dependencies and tests in the appropriate commit.

1. `fix(install): show progress during ownership finalisation`
2. `refactor(core): expose structured operation status and progress`
3. `feat(cli): add unified commands and local cloud shortcuts`
4. `feat(config): add shared defaults and interactive configuration`
5. `refactor(agents): package OpenCode as a runtime strategy`
6. `feat(agents): add explicit contextual session commands`
7. `feat(agents): add the first optional assistant runtime`
8. `feat(models): install and track multiple selected Ollama models`
9. `feat(gui): add shared graphical installation and maintenance`
10. `feat(gui): add graphical cleanup with ownership previews`
11. `feat(gui): add conversations and shared settings`
12. `docs(usage): document unified CLI and graphical workflows`

Runtime-specific commits must name the selected runtime in their final subject.
Document each feature alongside implementation; the final documentation pass
checks the complete flow rather than postponing all guides until the end.

## Completion checks for the overall work

- [ ] Source/EXE and CLI/GUI use the same defaults and installation records.
- [ ] Existing commands remain compatible and new shortcuts behave identically.
- [ ] One-shot calls remain independent; contextual sessions resume intentionally.
- [ ] Progress covers lengthy preparation, execution and finalisation phases.
- [ ] Fresh, repeat, failed, cancelled and interrupted operations are covered.
- [ ] Test installs leave the host at its original baseline after cleanup.
- [ ] Repository/history and distributable privacy checks pass. Report what was
  checked without claiming secret scans prove the absence of vulnerabilities.
- [ ] Build/test workflows package the intended GUI and CLI assets and notices.
- [ ] Guides describe available behaviour accurately, including unsigned warnings,
  provider data flow, memory retention and unsupported runtime capabilities.
