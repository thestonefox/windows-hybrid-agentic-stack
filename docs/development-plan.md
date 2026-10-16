# Planned CLI, agent and graphical interface work

This records the agreed scope, decisions and acceptance checks. Checked items
have supporting implementation/tests; unchecked acceptance cases remain open.
Use the CLI, GUI and agent guides for commands available in this implementation.

## Work boundary and current status

### Agreed graphical entry point revision

Status: the revised GUI is bundled after eight focused guest suites, a ninth
bundle-verification suite and a successful explicit host Defender scan. Do not
treat earlier validation below as validation of this revision. A development
self-contained GUI build was blocked
by host Defender as `Trojan:Win32/Sabsik.FL.A!ml` before its launch completed.
The detection has not been classified as a false positive. Further builds and
product execution stayed in disposable background Sandboxes; no exclusions, quarantine
restores or protection disabling are permitted. Its WinDefend service is
inactive and could not be started, so guest functional tests cannot establish
Defender compatibility. Independent scanner results must retain that limit.

- [x] Pass focused guest regression suites for the new entry point and lifecycle.
- [x] Obtain a successful explicit Defender scan of the revised build before
  bundling it. The original detection's cause remains unconfirmed.
- [x] Bundle the exact scanned GUI EXE with source downloads, with a source
  fingerprint/checksum check to prevent stale binaries.
- [ ] Exercise the new Defender release gate on a supported build machine.

Revision validation: Windows PowerShell 5.1 guest runs passed GUI routing,
same-window rebuilding/navigation, temporary-copy cleanup under Restricted,
native setup/removal component cycles, prerequisite checks, tracked uninstall,
multiple-model ownership, model selection, unified CLI and release packaging.
These are eight suites across serial runs, with external dependencies mocked.
Ten implementation/test file hashes matched the host working tree. The source
secret scanner reported no leaks. No new product binary was executed on the
host after the detection. With explicit user authorization, a third guest's
unexecuted build was copied to a temporary host folder for an active Defender
file scan. The scan returned zero with no threats, no detection records for
that file and an unchanged hash; real-time protection remained enabled and
signatures were `1.461.53.0`. Those exact bytes are bundled at the repository
root with public hashes. No exclusions or quarantine restores were used.

The first guest's full Microsoft Safety Scanner run was incomplete: resource
exhaustion required discarding that guest. Do not report a clean malware scan.
The second, smaller guest completed the functional suites offline. Its disabled
WinDefend service rejected enabling with access denied, including in SYSTEM
context. Those guests were discarded after testing. The subsequent authorized
host scan is separate evidence and does not establish why the original build
was detected. Manual graphical acceptance is still outstanding. No host security exclusions or policy/profile
changes were made. The source fixture now mocks its Ollama inventory instead
of depending on a live host server, and the child-PID test retries a brief
file-sharing race.

The new bundle-verification suite rejects modified, stale and missing files
without compiling or executing the GUI. It also passed against the actual
bundled EXE. A follow-up native setup run passed after adding canonical LF/CRLF
source fingerprints, and the final rebuilt bytes passed another explicit
Defender scan before replacing the bundled candidate. CI checks source freshness and blocks artifact upload unless an
active Defender scan succeeds; the remote workflow has not been run or pushed.

- Keep `whas.exe` exclusively as the CLI and `whas-gui.exe` as the graphical
  entry point. Do not combine terminal commands and normal graphical launch.
- The graphical EXE must work before installation, with the reviewed setup
  payload embedded. A source ZIP must include the current built graphical EXE.
- First launch opens feature configuration and prerequisite checks. A complete
  installation opens usage/settings; interrupted state opens recovery/setup.
- Show feature setup, model/engine choices and complete removal in the same
  application. Run the graphical image outside its managed installation so it
  can update/remove owned files without locking its own executable.
- Keep existing per-engine/per-runtime removal controls and preserve personal
  data. Adding features must not silently remove unchecked existing components.
- Retain legacy console setup for compatibility/developers, without requiring
  it as a second graphical download or installed application.
- Validate fresh/configured/interrupted launch, embedded backend operations,
  screen rebuilding, cleanup and ZIP contents without desktop automation.
- Image/video generation and local/cloud shortcuts remain future discussion;
  no media providers or dependencies are included in this change.

- [x] Wait for the user to confirm their installation, testing and uninstallation
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

Implemented: unified commands, shared settings, the OpenCode strategy,
scoped sessions, multiple local models, graphical setup and voice management.

Additional runtime integrations remain deferred pending agreement.

The 10,000-entry ownership fixture measured 158 ms cold and 9 ms cached in the
final full suite. These measure ownership processing, not provider/model speed.
Source and full-history secret scans passed; commit identities use a GitHub
noreply address. Evidence and Sandbox files remain outside the repository.

Additional runtime integrations remain deferred pending agreement.

## 1. Fix the silent final installation stage first

### Confirmed defect

After printing `Runtime local model`, installation can remain silent while
`Complete-StackInstallationTracking` scans the installation tree and hashes its
files. This ownership record enables safe uninstallation. The function currently
calls `Get-StackInstallationTree` and `Get-StackFileSHA256` without passing progress.
Dependency output and uninstall progress do not cover this stage. The previous
claim that installation progress was complete was inaccurate.

### Required work

- [x] Announce finalisation before it starts, explaining that installed files are
  being recorded for safe uninstall.
- [x] Pass progress through tree enumeration and file hashing, including inside
  large individual files. Report phase, completed count, total when known and
  elapsed time. Use the existing progress helpers where suitable.
- [x] Cover initial ownership scans and repeat-install verification as well as
  successful finalisation and interrupted-install tracking.
- [ ] Review every lengthy install/uninstall phase for the same silence:
  dependency installation, model download/verification, strategy hooks, command
  compilation/registration, ownership checks, file removal and receipt writing.
- [ ] Give slow subprocess operations visible output or periodic activity with
  elapsed time. A phase announcement alone does not solve a long silent wait.
- [x] Throttle output to useful intervals, approximately every two seconds for
  long operations. Do not invent percentages or estimated completion times.
- [x] Preserve failure exit codes, interrupted-install recovery and ownership
  verification. Do not skip hashes to make installation look faster.

### Acceptance

- [ ] Exercise many small files and at least one large file; confirm the final
  tracking stage visibly updates throughout its work.
- [ ] Confirm both source setup and standalone console setup show the updates.
- [ ] Verify resulting ownership hashes and successful uninstall remain correct.
- [ ] Exercise failed and repeat installation paths, without changing profiles,
  saved policies or unrelated files.
- [ ] Recheck uninstall feedback, including the work immediately after approval.

## 1a. Make speech status fast and bounded

### Reported defect and investigation

During the manual test, `tts-status` took a long time before printing default
and active engine information, then appeared to wait again. Do not describe this
as normal model loading: status should not load a model or start a service.

Source inspection shows shared script loading before command output, an active
engine HTTP probe, runtime/ownership validation after the engine lines, and a
second HTTP probe in `Invoke-TtsStatusCore`. `Read-StackInstallationState`
deserializes the full ownership record and validates every recorded file path;
it can be called repeatedly during native helper loading and runtime selection.
Large ownership records are a plausible contributor, not yet a measured cause.
HTTP probes currently use a two-second timeout each; process checks can also
contribute. Measure the stages before claiming the root cause is proven.

- [ ] After the manual test finishes, time native startup, helper loading, state
  parsing/validation, HTTP probes, runtime selection and process checks separately.
- [ ] Reproduce with a realistic large ownership record as well as small fixtures.
- [x] Reuse one status result and validated state within an invocation where safe.
  Avoid repeatedly traversing the full installation record for a simple status.
- [x] Retain ownership, runtime identity, path and process checks; do not remove
  protections merely to improve timings. Define safe invalidation if using caches.
- [ ] Bound the total status wait, not just individual HTTP calls. Distinguish
  stopped, loading, responsive, unresponsive and conflicting service states.
- [ ] Return promptly when the service is absent or unresponsive. Give visible
  activity if a legitimate check exceeds the normal response interval.
- [x] Status must never load speech models, switch engines or start/stop services.
- [ ] Test fresh native commands, stopped/loading/ready/unresponsive services,
  stale PIDs, another installation on the port and explicit engine selection.
- [ ] Measure before/after timings and establish a practical automated latency
  bound with fixture services. Review other read-only commands for the same cost.

Suggested additional commit:
`fix(tts): bound status checks and avoid repeated ownership scans`

## 1b. Show activity throughout everyday use

### Reported defect

A question can appear to do nothing while the model is responding, then again
while speech is generated. The absence of feedback makes ordinary use look
broken. Installation and status feedback alone do not address this problem.
Apply this requirement to existing one-shot commands first and carry it into
the proposed unified CLI, contextual chat and graphical interfaces.

- [ ] Announce meaningful phases promptly: contacting the selected provider,
  waiting for the response, receiving the response, preparing the speech engine
  if necessary, generating speech and playing audio. Report only stages actually
  observed by the backend; do not invent fine-grained provider/model progress.
- [x] During long silent waits, show periodic activity with elapsed time, including
  first model/service startup and the gap between answer completion and audio.
- [ ] Identify the selected local/cloud route, model and speech engine where
  useful, without printing credentials, private prompts or internal event data.
- [ ] Distinguish model loading from generation only when the backend reports it.
  Otherwise describe the observable operation, such as waiting for the model.
- [ ] Display the answer as soon as available; do not hide it until speech finishes.
  Preserve existing answer extraction and avoid leaking provider control text.
- [x] Keep activity separate from answer content and raw machine-readable logs.
  Do not contaminate piped/redirected answer output or speak activity messages.
- [ ] Define terminal/noninteractive rendering deliberately. Use a transient
  indicator in an interactive terminal and explicit diagnostic output when
  requested; keep scripting and structured-output contracts stable.
- [ ] Stop indicators on success, failure, timeout and cancellation. Show useful
  errors and preserve failure exit codes; never leave a false busy state.
- [ ] Support cancellation through the full request/speech pipeline. Stop only
  request-owned work and clearly report any operation that cannot be cancelled.
- [ ] Use the shared structured event contract for terminal and GUI feedback.
  Do not require verbose/debug mode merely to know a request is still active.
- [ ] Review whether answers can stream through each supported runtime, while
  keeping speech synthesis and final-answer extraction correct. Streaming is
  an additional capability, not a replacement for silent-wait feedback.

### Diagnose actual latency as well as showing activity

The user reports unexpectedly slow cloud requests as well as local requests.
Do not assume a cloud-model delay, accept all latency as normal, or consider a
spinner a performance fix. Confirm the effective provider/model identifier;
do not infer it from the model used in this development chat.

Source inspection confirms the ordinary answer path stores text events and
prints the extracted answer only after `opencode run` exits, then calls speech
synchronously when requested. The native command host also loads TTS helpers
when present even for agent calls without speech. These are investigation
targets; their contribution to the observed delay has not been measured.

- [ ] Measure wrapper startup/helper validation, OpenCode startup, time to first
  answer event, completion, TTS readiness, synthesis and playback separately.
- [ ] Compare the wrapper with direct OpenCode using the same simple prompt,
  effective model/configuration and permissions, with speech disabled first.
- [ ] Compare cold and warm runs, then add speech and measure the extra cost.
- [x] Avoid expensive speech/helper initialization on text-only requests where
  feasible, while retaining required integrity and permission checks.
- [ ] Assess safe earlier answer display/streaming independently of model speed.
- [ ] Record measured results and fix avoidable overhead; distinguish provider
  wait, wrapper overhead and speech cost in user-facing diagnostics.

### Acceptance

- [ ] Exercise delayed local and cloud responses, cold/warm model startup, delayed
  speech generation and playback, both with and without voice output.
- [ ] Confirm prompt phase feedback and continuing activity during a deliberately
  delayed fake backend without requiring real cloud spending or audio listening.
- [ ] Test provider/TTS failures, unresponsive services and cancellation at each
  boundary; ensure the UI clears its activity state and exposes the outcome.
- [ ] Verify piped answers, redirected output, verbose/raw logs and synthesized
  speech contain no spinner frames or progress narration.
- [ ] Confirm the later GUI exposes the same phases and outcomes, including the
  wait before the first response token and between text and audible playback.

Suggested additional commit:
`feat(cli): show request and speech activity throughout execution`

## 2. Establish the unified command interface

### Agreed direction

Use a distinct `whas` namespace. Support readable flags and convenient shortcuts
through the same implementation:

| Command | Behaviour |
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

- [x] Implement one parser/dispatcher for long forms and shortcuts.
- [ ] Preserve model overrides and existing speech/output options; document their
  mapping instead of silently dropping them during the naming change.
- [x] Define `ask` restrictions and `perform` tool permissions explicitly.
  Preserve the existing restricted/task distinction; do not silently broaden it.
- [x] Keep `agent`, `localagent`, `agentdo` and `localagentdo` as compatibility
  commands with their existing one-shot and provider-selection behaviour.
- [x] Expose useful help, configuration inspection and clear exit codes.
- [x] Reject contradictory local/cloud options and ambiguous shortcut overrides.
- [ ] Never silently fall back from local to cloud or vice versa.

### Acceptance

- [x] Shortcuts and equivalent flags produce identical routing and permissions.
- [x] Existing command behaviour and argument quoting remain compatible.
- [ ] Missing defaults, unavailable models and unsupported options give actionable
  errors before invoking a provider or executing tools.
- [ ] Existing TTS command use remains functional during the transition.

## 3. Share configuration across every interface

- [x] Set initial defaults during installation. Allow them to change afterwards
  through `whas configure`, using a human-readable interactive menu.
- [x] Define precedence as explicit command choice, then saved configuration,
  then documented built-in defaults.
- [x] Support default local/cloud preference, runtime, cloud/local models, TTS
  engine, voice and speech-output preferences.
- [x] Decide whether `ask`, `perform` and `chat` share a runtime default or have
  per-operation overrides; settle this before fixing the schema.
- [x] Reconcile the existing TTS default registry with configuration access so
  there is one authority per setting. Do not introduce competing GUI defaults.
- [x] Define scope for per-installation, per-user and optional project settings.
  Explain which setting is effective when more than one scope exists.
- [ ] Validate settings and schema versions; migrate existing installations and
  retain unrelated user settings.
- [x] Use atomic writes and prevent concurrent CLI/GUI changes from losing data.
- [x] Changing settings must not silently install software. Explain missing
  components and offer a separate, explicit install operation.
- [x] Keep provider credentials in supported credential storage, separate from
  ordinary shared configuration and distributable build assets.
- [x] An open GUI must refresh settings changed by the CLI, or clearly identify
  changes that require restart. In-flight work must have defined behaviour.

### Configuration sections and voice management

Use separate GUI tabs with equivalent CLI configuration/menu access. Proposed
sections are General, Agents, Models, Voice, and Sessions & Memory where supported.
Final tab names can change without changing the shared configuration contract.

- [x] Provide a Voice tab for available/installed TTS strategies, explicit
  install/uninstall actions, default engine and supported device selection.
- [ ] List and preview an engine's voices; choose its default voice and expose
  speech-output/playback preferences where supported.
- [x] Add/remove personal voice references only when the engine supports those
  operations. Show why an unavailable operation is unsupported rather than
  displaying controls that silently fail.
- [x] Validate reference requirements before import. F5 needs a WAV and matching
  UTF-8 transcript; Chatterbox accepts supported WAV references; Piper's current
  strategy does not support reference-sample voice cloning.
- [x] Explain reference conditioning accurately; do not call adding a recording
  model training when no weights are trained.
- [x] Confirm removal of personal reference files, preserve unrelated samples,
  and reflect changes made through existing voice commands in the GUI.
- [x] Reuse strategy capability/validation declarations and management operations,
  rather than hard-coding engine-specific GUI behaviour wherever avoidable.

### Acceptance

- [ ] A change through CLI configuration appears in the GUI and vice versa.
- [ ] Concurrent writes cannot corrupt or silently overwrite configuration.
- [ ] Invalid configuration produces a useful recovery path, not partial setup.
- [ ] Command-line overrides do not unexpectedly rewrite saved defaults.

## 4. Add agent runtime strategies and contextual use

### Existing behaviour to preserve

Additional runtime integrations remain deferred pending agreement.

### Strategy contract

- [x] Extract OpenCode into the first strategy without changing current defaults.
- [x] Define a discoverable packaged strategy layout and validated manifest,
  following the useful lifecycle aspects of the TTS strategy design.
- [ ] Specify pinned versions/sources, prerequisites, platform support and owned
  files. Treat strategy hooks as trusted executable code, not sandboxed data.
- [ ] Define check, install, verify, configure, launch and uninstall operations.
- [ ] Declare one-shot, interactive, session continuation, local-provider,
  structured-output, permission-control, memory and background capabilities.
- [x] Expose each runtime's native CLI where needed; do not force all its native
  features into a falsely equivalent common interface.
- [ ] Validate unsupported operations and provider/runtime combinations before
  starting work. Existing authentication must not be assumed transferable.
- [x] Keep runtime selection independent of model provider and model selection.
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

- [x] Let setup select multiple models and choose the local default separately.
- [x] Distinguish existing models, original downloaded models and stack-created
  configured aliases. Track ownership of each appropriately.
- [ ] Show download sizes and hardware guidance when known, with clear uncertainty
  instead of assuming every model suits every machine.
- [ ] Maintain a small reviewed model catalogue without preventing supported
  explicit model overrides. Catalogue contents remain to be chosen.
- [ ] Reuse or retain pre-existing models, handle failed/repeated downloads and
  ensure uninstallation removes only verified installer-owned models by default.
- [x] Preserve the explicit retain-models option and changed-model protections.
- [x] Offer installed TTS engines as independent selections with a saved default,
  using the engine-management implementation already present.

## 6. Build graphical setup and uninstallation

Build this after CLI/configuration/strategy contracts are stable. Select the
Windows UI toolkit and source-install build/distribution approach deliberately;
Decision: Windows Forms, compiled by source and bundled setup alike. Continue
documenting unsigned executable behaviour.

### Application entry points

- `whas-setup.exe`: graphical installation, maintenance and uninstallation.
- `whas-gui.exe`: everyday use with Settings accessible from inside the app.
- `whas.exe`: full command-line use.

The three-entry-point layout is a proposal, not a requirement to maintain four
independent installer/uninstaller/configuration/usage applications. Start-menu
shortcuts can open setup, settings or uninstall screens directly.

### Shared backend requirements

- [x] Both source and EXE installation provide CLI and GUI capabilities. A source
  installation must build or obtain the GUI assets through a defined process.
- [x] Use the same installation identity, configuration, ownership records,
  strategy hooks and cleanup rules for both interfaces.
- [ ] Detect existing installations and offer maintenance instead of creating an
  accidental second copy. Handle explicitly requested custom roots deliberately.
- [x] Expose structured check results, phase/progress events, errors and receipts
  for both terminal and GUI consumers. Do not parse coloured console text.
- [x] Keep CLI automation, noninteractive flags and exit codes working.

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

- [x] Define cancellation and failure recovery; cancellation must not be labelled
  rollback if installed changes remain. Preserve recoverable ownership records.

### Uninstallation screens

- [x] Preview files, commands, models and services affected, plus preserved data.
- [x] Offer retain-managed-models and clearly distinguish personal data deletion.
- [x] Require confirmation before applying, with visible progress and final receipt.
- [ ] Test EXE install -> GUI uninstall, source install -> GUI uninstall,
  EXE install -> source uninstall and source install -> source uninstall.
- [ ] Verify service shutdown, command/PATH cleanup, changed-file preservation
  and repeated uninstall through both interfaces.

## 7. Add graphical everyday use and settings

- [ ] Provide one-shot questions, independent tasks and contextual conversations.
- [ ] Show effective runtime, provider and model with local/cloud selection.
- [ ] Provide session creation/resumption and clearly expose memory behaviour.
- [ ] Include TTS engine/voice selection and speech controls.
- [x] Open shared Settings from the usage app; never create a separate GUI config.
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
- [ ] Everyday requests show model/speech activity without contaminating answers,
  logs or audio, and always clear indicators on failure or cancellation.
- [ ] Fresh, repeat, failed, cancelled and interrupted operations are covered.
- [ ] Test installs leave the host at its original baseline after cleanup.
- [ ] Repository/history and distributable privacy checks pass. Report what was
  checked without claiming secret scans prove the absence of vulnerabilities.
- [ ] Build/test workflows package the intended GUI and CLI assets and notices.
- [ ] Guides describe available behaviour accurately, including unsigned warnings,
  provider data flow, memory retention and unsupported runtime capabilities.
