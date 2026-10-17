# Development decisions and validation backlog

This records decisions, earlier reviews and acceptance checks. Earlier review
notes preserve the design and validation state at that time; they are not
current usage instructions. Use the CLI, GUI and agent guides for current commands.

## Current agreed behaviour: 17 October 2026

- The user approved the GUI on 17 October 2026. The agreed GUI, CLI, setup and
  documentation work is recorded in repository commits. No release or remote
  update is claimed.
- Use `whas ask`, `whas perform`, `whas chat` and `whas tts` in current guides.
  Legacy launchers remain compatibility interfaces with their older permissions.
- Conversation is the first GUI operation, Run a task second, One-off question
  last. Only tasks get file/system tools and saved workspace folder context.
- GUI local chat goes directly to Ollama and streams replies. Conversation
  sends completed history from the current window; one-off questions do not
  read or update it. CLI/cloud chat uses OpenCode and native session IDs.
  Real Qwen latency against Ollama's GUI has not been benchmarked in this run.
- OpenCode is the only shipped agent runtime; additional integrations are deferred.
- Use a top-right Configuration cog and Back control, with no installed sidebar.
  Configuration tabs are General, Workspaces, Models, Speech, Conversations and
  Maintenance. Maintenance contains Features and whole-app Removal.
- Shared dropdown settings autosave. Engine/voice selection has explicit
  default actions. Panels follow the selected speech engine's capabilities.
- Run on contains two choices, with the saved route marked `(Default)`.
  User bubbles align right, replies left, and submitted messages appear
  immediately with waiting dots until reply text arrives.
- Send is disabled while preparing, enabled when ready, and becomes Cancel
  only for a submitted request and its speech. Setup, maintenance and model
  discovery do not expose Cancel. The bottom progress strip keeps a fixed place.
- Direct-chat, GUI-workflow, native-CLI and answer-extraction checks passed in
  background Sandbox with simulated providers. The exact bundle passed Defender
  scanning and source/hash verification. This is not live model/audio validation.
- The CI workflow still needs to accommodate the Sandbox-only test guards;
  see [build status](releases.md#continuous-builds). No remote run is claimed.

## Documentation and help review: 17 October 2026

The README links to the complete CLI command/flag reference. Speech help is
available through `whas tts --help` and the standalone `tts-help` launcher.
Older 17-command registrations remain recognized for repair/removal. The new
launcher is supplied by updated installation/registration; opening a newer GUI
alone does not install it. New chat clears the displayed chat and current
context, preserving OpenCode native transcripts and WHAS associations.

## Work boundary and current status

### Repository GUI compatibility with existing installations

The newer GUI called model catalog on an older installed WHAS CLI, producing
Unknown command: model during startup. Discover models through the installed
Ollama list and OpenCode models commands directly, with the selected root's
OpenCode configuration passed only to that child. Keep shared settings and
requests bound to the registered installation. Discovery is optional: retain
saved choices and show configuration guidance on failure or missing tools,
without automatically opening a fatal-operation log on Assistant. Test against
a deliberately older backend that rejects every model command. No component
reinstall or host configuration change is needed to view the new GUI.

Validation: the isolated installed-workflow suite passed with a backend that
rejects model commands, direct provider fixtures, child-only configuration,
failed discovery and a missing provider executable. Saved choices survived and
optional discovery did not open the fatal activity panel. Existing GUI backend
and WPF suites also passed in Sandbox. Real host providers were not invoked.

### Installed-state detection with large ownership records

Manual launch of the repository GUI opened first-run setup despite a valid
Installed record. The ownership record exceeded JavaScriptSerializer's default
2 MB limit; IsConfigured caught the parser exception and returned false. Allow
the full record size used by private speech environments and test records with
tens of thousands of file entries. A large Installed record must open Assistant;
large Interrupted and malformed records must still open recovery/setup. Do not
modify the user's installation or ask for a reinstall to work around this bug.

### Earlier installed workflow review: Assistant and Configuration

The layout and Save-button proposal in this review was superseded by the
current behaviour above and the later refinements in section 7.

The accepted setup design did not validate the installed workflow. Manual
testing found unlabelled message/response boxes, raw configuration keys,
optional runtimes appearing available, unloaded speech choices, duplicate
maintenance navigation and CLI chat/speech errors in everyday use.

- Use two installed navigation entries: Assistant and Configuration. Group
  General, Workspaces, Models, Speech, Conversations and Maintenance in
  Configuration; retain the first-run setup flow. Provide one removal page.
- Assistant order: operation; labelled message input and Send; location and
  Speak the answer; labelled responses. Move workspace/runtime/session tools
  to Configuration. Do not render these pages using a generic form dump.
- Show friendly settings labels and adjacent Save actions. Use model selectors
  populated from Ollama/OpenCode; explicitly label the OpenCode default option.
  Speech voices belong in the engine-specific Speech section, not a raw key.
- Load available runtimes and speech inventory automatically. Offer only
  discovered available runtimes. Keep unavailable engine actions disabled and
  show installation/error guidance instead of empty unexplained controls.
- Explain OpenCode setup before applying features. Additional runtime
  integrations require explicit agreement.
- Display completed answers before playback. Run GUI speech separately from
  model generation, including completed conversation turns. Keep diagnostics
  in the activity log and preserve an answer if playback fails.
- Test installed navigation and ordering, real redirected mocked CLI requests,
  automatic inventory/defaults, unavailable runtimes, model choices, speech
  capability checks and answer/speech separation in background Sandbox.

Subsequent terminology decision: use Run on for requests, with This PC, Cloud
and Default followed by the actual saved choice. Use Default processing in
configuration/setup. Keep internal local/cloud values and CLI flags compatible;
an unsaved feature selection must not change the displayed saved default.

Validation: installed-workflow, GUI backend, WPF presenter and native CLI
suites passed in the offline Sandbox. Checks cover automatic choices, saved
defaults, unavailable runtimes/engines, per-engine capability guards, navigation
to feature application, Run on labels and effective-default binding. Mocked
conversation generation/playback verifies that speech diagnostics stay out of
answers and a playback failure preserves the answer. Provider/audio calls were
mocked; live audio and full manual installed-flow acceptance remain pending.

### Explicit request location

The Features selector offers Cloud and Local only. Fresh setup visibly selects
Cloud. Load the saved interaction location from the chosen installation folder
when reconfiguring or changing destination; never label it Automatic. Always
pass the displayed location to setup, and reject an empty/invalid selection.
Reloading shared settings also updates the feature default. Test both routes,
saved defaults, destination changes, invalid values and the WPF binding.

### Accepted WPF design: align model and engine choices

Licence information belongs beside each model/engine name as a compact info
action, replacing the selected-engine licence line. Hover and keyboard focus
show scoped licence terms; activation opens details and explicit source links.
Read speech terms from each strategy manifest, including model assets. Only
the exact built-in Qwen choices have verified local model metadata; arbitrary
Ollama IDs must say Licence not verified. Do not fetch metadata on hover or
change download selections when opening details. Validate the controls and
rebuild/scan the bundled GUI in the background Sandbox workflow.

Built-in model licence sources (checked 2026-10-16):
[Qwen3-8B](https://huggingface.co/Qwen/Qwen3-8B/blob/main/LICENSE) and
[Qwen2.5-1.5B](https://huggingface.co/Qwen/Qwen2.5-1.5B/blob/main/LICENSE).

The user accepted the new design and requested defaults first in both cards,
with their dropdowns aligned even when descriptions wrap. Download checkboxes
follow the defaults. The additional Ollama model input and compact Add button
share one row below the model choices. Use common WPF grid rows for alignment.

### Second manual GUI review: replace the visible Forms presentation

The user confirmed the checks work but rejected the Forms presentation. The
fixed-height prerequisite grid hid results while leaving unused space below;
the wrapping external-link strip and vertically stacked setup actions also
failed visual acceptance. Recolouring those controls was insufficient.

- Present the main application with WPF using reusable Fluent-style templates
  in `scripts/gui-theme.xaml`, following Microsoft WinUI Gallery settings cards.
  This is WPF, not WinUI 3; no Windows App SDK runtime is installed.
- Keep the existing action/state controller hidden. Do not host Forms controls
  in the main window or duplicate installation/configuration backend logic.
- Use feature cards with switches, a single-row folder picker and aligned
  default selectors. Keep model/engine selections and defaults distinct.
- Replace the fixed-height prerequisite grid and standalone link strip with
  content-sized status rows, wrapped details and missing-component actions
  attached to their corresponding row. Use one page scroll surface.
- Keep activity logs collapsed, status visible and Cancel hidden while idle.
- Validate switch/default bindings, real initial/repeated prerequisite checks,
  missing-component actions, same-window lifecycle and all first-run renders.
- Build/test in background Sandbox, scan exact candidate bytes before bundling,
  retain the manifest freshness check and leave host prerequisites unchanged.
- Manual visual acceptance remains open until the user reviews this replacement.

Reference: [Microsoft WinUI Gallery](https://github.com/microsoft/WinUI-Gallery).

Validation: the WPF presenter suite passed feature bindings, populated defaults,
native window-handle creation, all first-run/configured renders, same-window
state rebuilding, initial/repeated real prerequisite actions and row-scoped
download actions. Existing GUI backend, native setup and profile integration
suites passed in Sandbox with external dependencies mocked. The rebuilt EXE
passed active Defender scanning with signatures `1.461.53.0`, no matching
detections and an unchanged hash; it was not launched on the host. Manual
acceptance of the revised appearance remains pending.

### Manual GUI feedback: layout and prerequisite checks

The first manual acceptance pass identified cramped content, an oversized log,
an unclear Cancel operation button, unlabelled default selectors and a crash
on Check again (`Console.OutputEncoding`: invalid console handle). Acceptance
of the earlier offscreen render did not cover that real graphical child path.

- Replace the crowded tab strip with sidebar navigation and page headings.
- Keep diagnostics collapsed by default, with a bounded expandable panel;
  keep status, activity and a clearly styled Cancel operation button visible.
- Label default local model, default speech engine and custom model input.
- Run the initial prerequisite check when its page is opened; retry on demand.
- Write UTF-8 directly to redirected streams without requiring console handles,
  in both setup and installed command launchers.
- Honour the prerequisite script's explicit exit status. Hosted PowerShell can
  report HadErrors after a handled probe even when the checker explicitly
  exits successfully; do not turn passing rows into a failed prerequisite gate.
- Test real WinExe children with redirected streams, success/failure results
  and repeat checks; inspect every first-run page offscreen at normal size.
- Follow Microsoft's layout/spacing guidance, then rebuild in Sandbox, scan
  the exact exported candidate with active Defender and update the manifest.
- Keep manual visual acceptance open until the user reviews the revised build.

The render helper now creates child control handles; the old file-size-only
assertion could accept an almost blank image. Tests sample rendered colours
and drive the real WinExe check through the UI event queue. Offscreen images
support layout review; they do not replace manual visual/interaction acceptance.

Design reference: [Microsoft content layout and spacing](https://learn.microsoft.com/en-us/windows/apps/design/basics/content-basics).

Revision validation passed GUI backend, native setup and unified CLI suites in
the offline Sandbox, plus bundle-verification tests and the actual source/hash
check. Real WinExe initial/repeated checks populated the grid and enabled the
passing gate. Native checks covered handled discovery errors with explicit
success, prerequisite failure, no-console launchers and install/remove cycles
under Restricted policy; external install dependencies were mocked.

The exact rebuilt bundle passed active host Defender scanning with signatures
`1.461.53.0`, no matching detections and an unchanged checksum. It was not
launched on the host. No host prerequisites, saved policies, profiles or PATH
were changed. Manual acceptance of the revised appearance remains pending.

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
was detected. The user reviewed and approved the GUI on 17 October 2026; this
records visual acceptance, not a live installation or speech test. No host
security exclusions or policy/profile changes were made. The source fixture now mocks its Ollama inventory instead
of depending on a live host server, and the child-PID test retries a brief
file-sharing race.

The new bundle-verification suite rejects modified, stale and missing files
without compiling or executing the GUI. It also passed against the actual
bundled EXE. A follow-up native setup run passed after adding canonical LF/CRLF
source fingerprints, and the final rebuilt bytes passed another explicit
Defender scan before replacing the bundled candidate. CI checks source freshness and blocks artifact upload unless an
active Defender scan succeeds; the remote workflow has not been run or pushed.

The committed Git source ZIP was extracted in the guest: all 126 entries passed
the public-file check, the 595,968-byte GUI retained its exact scanned checksum,
and source-fingerprint verification passed with Git-normalized line endings.
The extracted source-secret scan found no leaks. The final guest was discarded;
the GUI was never launched on the host and no host stack was installed.

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
- After GUI approval, use cohesive Conventional Commits with a scope. Keep
  every subject and body line at or below 72 characters. Do not commit pending review work.
- Use isolated tests first. Any local or Sandbox installation test must restore
  the state that existed before that test. Keep evidence and fixtures outside
  the repository; remove installed test components and stop test services.
- Mark checklist items complete only after their acceptance checks pass. Record
  actual validation and limitations in the relevant commit descriptions.
- Update this document when a decision changes or a missing case is discovered.

Implemented in this working change: native `whas` commands and shortcuts,
shared settings, the OpenCode strategy, scoped contextual sessions,
multiple local model selection, WPF setup/uninstall/use/configuration
and voice management. Compatibility commands remain available. Opening setup
without arguments shows its GUI; explicit console actions remain supported.

Earlier validation: all 23 isolated suites passed. Focused follow-up tests passed for
hidden-directory cleanup and GUI maintenance outside the installed directory.
Runtime checks cover OpenCode routing, session separation and lifecycle
validation. Sandbox evidence remains outside the repository.

The 10,000-entry ownership fixture measured 158 ms cold and 9 ms cached in the
final full suite. These measure ownership processing, not provider/model speed.
Source and full-history secret scans passed; commit identities use a GitHub
noreply address. Evidence and Sandbox files remain outside the repository.

Decisions: use built-in WPF for the visible application and one shared runtime
default. Settings
are per installation with explicit request overrides, without an additional
project configuration layer. Additional runtime integrations are deferred. Native history/memory management remains native; forgetting
a WHAS association does not erase it. Real-provider latency comparisons and
manual interactive GUI acceptance have not been performed in this run.

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
sections are General, Workspaces, Models, Speech, Conversations and Maintenance.
Engine defaults and voice management belong in Speech.

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

The compatibility wrappers invoke `opencode run` without continuing a session.
They provide one-shot use. Unified CLI chat supports native sessions and
continuation. GUI local chat keeps its own Ollama message history.
Additional runtime integrations require a separate agreed scope.

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

- [x] Define new-chat, resume and explicit session selection semantics. Never
  attach an unrelated conversation merely because it was the most recent one.
- [x] Define session ownership and separation between users, projects, runtimes
  and local/cloud use. Explain when previous messages will reach a provider.
- [x] Separate saved transcripts from persistent memory across conversations.
- [x] Make memory enablement, inspection, reset and deletion behaviour explicit.
- [x] Define what uninstall preserves and what explicit personal-data deletion
  removes. Include conversations, memories, skills and credentials as applicable.
- [x] Keep private conversations, memory stores and credentials out of Git,
  packaged setup assets, CI artifacts and routine diagnostic output.
- [ ] Prove the contract with one additional runtime before implementing every
  integration. The next runtime remains to be agreed.
- [x] Write strategy authoring and per-runtime user guides.

## 5. Expand installer model selection

Ollama already supports multiple installed models. Our wrappers can override the
configured model; setup now prepares multiple selected models and saves one default. There
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
Decision: WPF presentation over the shared action controller, compiled by source
and bundled setup alike. Continue
documenting unsigned executable behaviour.

### Application entry points

- `whas-gui.exe`: feature setup, everyday use, Settings and removal in one app.
- `whas.exe`: full command-line use.
- `whas-setup.exe`: optional legacy developer console build.

The graphical app provides setup, settings, usage and removal in one window.
The console build is optional and is not installed as a second graphical app.
Start-menu shortcuts remain future work.

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

1. Components: cloud, local and speech. Additional agent runtimes are deferred.
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

### Configuration follow-up: 16 October 2026

The installation wizard only serves first installation. The installed app
uses direct maintenance actions rather than Continue/Next navigation:

- [x] Show configured Cloud/Local routes and installed speech engines separately
  from pending actions. Offer Add when absent, Repair and Remove when present.
- [x] Keep each maintenance operation, its options, readiness results, preview
  and Apply control together. Require a current check and preview before Apply.
- [x] Explain removal boundaries: shared prerequisites, accounts, model files and
  personal voice references are retained unless their own removal is requested.
- [x] Give newly saved voices an explicit Make default option, plus a plainly
  labelled Set this as default voice action and visible current default.
- [x] Use bundled maintenance code for defaults so an older installed validator
  cannot reject valid Chatterbox reference IDs.
- [x] Replace the unstyled speech expander with themed, headed settings cards.
- [x] Investigate successful speech returning exit 1; cover handled probe errors
  and genuine speech errors separately. Every failed process must leave a
  diagnostic in the activity log as well as its footer status.
- [x] Test with isolated fixtures and build in background Sandbox; preserve the
  user's installation and personal data. Scan the exact distributable and
  clean up the owned Sandbox before committing.

Implemented GUI refinements:

Current follow-up acceptance checks:

- [x] Shared settings dropdowns save once per user change; initial load, reload,
  model/runtime discovery and failure rollback never submit extra writes.
- [x] A failed save retains the previously saved value and reports the failure.
- [x] Workspace and installation folder selection use the Windows Common Item
  Dialog in folder mode, with a Select folder button and filesystem results.
- [x] Speech panels follow strategy capabilities. Piper hides custom-reference
  forms; F5 explains the required matching UTF-8 transcript before file choice
  and displays its expected path and presence after choosing a WAV.
- [x] Engine and saved-voice selection remain explicit default actions, labelled
  Set default engine, Set this as default voice and Delete this voice.
- [x] Progress stays in a permanently reserved bottom row. Cancel replaces Send
  at the same width during requests; the activity log stays at the right edge.
  Setup and configuration do not expose cancellation.
- [x] Enter sends once; Shift+Enter inserts a line. Empty, busy and held-key Enter
  events do not submit. Responses keep their border and use the canvas colour.

- [x] System/Light/Dark appearance under General, with live system-theme updates.
- [x] Compact multiline message input; Enter sends, Shift+Enter inserts a line.
- [x] Current feature configuration shown with Add/Repair/Remove actions and
  in-place maintenance options, checks, preview and apply controls.
- [x] Show/Hide activity log with Clear log, preserving answers and running work.
- [x] Saved workspaces all available to tasks, including subfolders, with
  one starting folder for commands. Add/remove or change the starting folder
  to start a new conversation; removing an entry never deletes files.
- [x] Pass scoped OpenCode directory grants only in the task child, retain
  task tool restrictions and existing provider/model settings, and
  include saved folder paths in task context. Do not rewrite installed
  configuration or use a common ancestor that grants unrelated siblings.
- [x] Replace the installed sidebar with a top-right Configuration cog and a
  Back control in the same position. Let responses fill the available window,
  with a multiline placeholder composer and left/right control groups below.
- [x] Split General, Workspaces and Models into separate tabs with headings;
  group speech startup/hardware settings with engine and voice management,
  using themed headings rather than an unstyled native expander.
- [x] Stage custom voices as recording -> editable unique name -> Save voice.
  File selection never submits, plays audio or changes a default. Keep failed
  forms for correction and explain unsupported engines/transcript requirements.
- [x] Separate saved-voice testing, per-engine default selection and deletion.
  Guard built-in/current-default deletion and explain what each action changes.
- [x] Use strategy-declared stored-file patterns for public voice IDs and default
  validation. Handle legacy Chatterbox caches without renaming personal files;
  use bundled maintenance code for compatible default changes and playback.
- [x] Report service JSON errors rather than hiding them behind HTTP status text.
- [x] Persist personal appearance/workspace preferences outside installation
  records; retain shared CLI/provider/model configuration and reject stale saves.

These refinements have isolated GUI workflow, backend and rendering coverage.
They do not complete the broader installation/removal matrix below.

- [x] Provide one-shot questions, independent tasks and contextual conversations.
- [ ] Show effective runtime, provider and model with local/cloud selection.
- [x] Provide session creation/resumption and clearly expose memory behaviour.
- [x] Include TTS engine/voice selection and speech controls.
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
