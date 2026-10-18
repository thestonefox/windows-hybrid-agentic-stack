# Builds and releases

The repository contains GitHub Actions workflows for unsigned Windows x64 setup.
They run after the workflow files are pushed to GitHub. Every successful update
to `main`, including a merged PR, automatically publishes a versioned release.
Adding files locally does not push code, start a cloud run or publish a release.

## Continuous builds

`Windows setup build` runs for main-branch pushes, pull requests and manual
dispatches. It uses Windows PowerShell 5.1 on a Windows runner, with Python 3.11
for dependency-free backend tests. It does not install speech models, invoke a
cloud AI provider or play audio.

The workflow definition:

1. Plans the next version and grouped release notes for `main`, using complete
   Git history and the original commits of merged PRs.
2. Runs isolated PowerShell and Python suites, and checks the bundled GUI's
   source fingerprint and checksum without executing it.
3. Builds the versioned standalone EXE and ZIP from the exact workflow commit,
   including documentation, licence notices and source-commit metadata.
4. Creates SHA-256 checksums for the EXE and ZIP.
5. Requires an active Defender engine, updates its signatures and scans both
   the bundled source-download EXE and the newly built release EXE.
   An unavailable scanner, detection, removal or changed hash blocks upload.
6. Uploads the explicit release files as `whas-windows-x64`, retained for 14 days.
7. On `main`, verifies the downloaded packages against the tested release plan,
   tags that exact commit and publishes the release with its packages and notes.

A development GUI build triggered a host Defender detection during this change.
The revised build uses ordinary .NET resources and passed an explicit host
Defender file scan with signatures `1.461.53.0`, real-time protection enabled,
zero detections and an unchanged hash. It was not executed on the host. This
does not establish the cause of the earlier detection or guarantee safety.
Do not disable protection, add exclusions or restore a blocked build to test it.

Eight suites require Windows Sandbox and are guarded by
`WHAS_SANDBOX_TEST=1`. GitHub-hosted runners do not provide that guest, so the
workflow runs `scripts/test.ps1 -SkipSandboxOnly` and prints every skipped
suite. Run the full suite in a disposable Windows Sandbox before merging changes
that require those tests. Automatic releases cover the CI selection; a passing
GitHub build does not cover those eight Sandbox suites.

After a successful `main` run, download the EXE, ZIP and `SHA256SUMS.txt` from
**Releases**. Release assets remain available after the Actions artifacts expire.
The ZIP contains the installer, guides, interface previews and notices.
External prerequisites must still be installed separately.

PR builds and manual runs on other branches build `development` packages and
upload Actions artifacts without publishing a tag or release. Open the run's
**Artifacts** section to download them; GitHub may require signing in.

## Bundled executable in source downloads

The repository tracks `whas-gui.exe` and `whas-gui.manifest.json`, so Git clones
and **Code > Download ZIP** include the graphical entry point. It provides
first-run feature setup and later usage, settings and removal. `whas.exe`
remains the installed CLI. No separate graphical setup EXE is required.

Keep the bundled file current whenever its embedded inputs change. Build a
candidate with `scripts/build-gui.ps1`, scan it with active Defender without
launching it, then copy those exact bytes to the repository root. Update
`inputsSHA256` in the manifest from `scripts/build-setup.ps1 -Fingerprint -Force`
and `executableSHA256` from `Get-FileHash .\whas-gui.exe`. Do not change hashes
just to silence a mismatch. Then verify in Windows PowerShell 5.1:

```powershell
.\scripts\check-bundled-gui.ps1
```

This check neither compiles nor launches the GUI. A source change, modified
EXE or missing file fails verification and the continuous-build gate. The
manifest is public build metadata, containing no personal paths or settings.
Text inputs use canonical LF endings so Git ZIPs and CRLF Windows clones have
the same source fingerprint; the EXE checksum always covers its exact bytes.

## Automatic semantic releases

Pushes to `main` and PRs merged into `main` use the strongest change since the
latest published stable release. If none exists, start at `v1.0.0`.
Otherwise:

| Commits included | Bump | Example from `v1.2.3` |
|---|---|---|
| Any breaking change | Major | `v2.0.0` |
| Any `feat`, without a breaking change | Minor | `v1.3.0` |
| Maintenance changes only | Patch | `v1.2.4` |

Use scoped Conventional Commits, with every line at most 72 characters:

```text
feat(speech): add another engine
fix(gui): align the send button
refactor(config)!: replace the configuration format
```

The `!` immediately before `:` marks a breaking change. A `BREAKING CHANGE:`
or `BREAKING-CHANGE:` footer also marks a major bump, regardless of commit type.
Ordinary mentions of "breaking changes" do not mark a breaking change.

`fix`, `chore`, `refactor`, `docs`, `perf`, `test`, `build`, `ci`, `style` and
`revert` receive a patch bump unless another commit requires a larger bump.
Unrecognized commit types and messages also receive a patch bump and appear
under **Other Changes**. Merge wrappers are omitted when their original PR
commits supply the changes. Original PR commits are read with paginated GitHub
API calls, so a squash merge cannot conceal a feature or breaking change.
Failure to read that history blocks the release instead of guessing a bump.

Notes group changes in this order: **Breaking Changes**, **Features**, **Fixes**,
**Performance**, **Refactoring**, **Documentation**, **Maintenance**, **Build**,
**CI**, **Tests**, **Style**, **Reverts**, then **Other Changes**. Empty groups
are omitted. Entries link to commits; later releases include a comparison link.

The next version is built into the package's `build.json`. A separate publish
job downloads those same scanned assets, verifies their checksums, version and
commit, creates the `vX.Y.Z` Git tag and uploads the EXE, ZIP and checksums.
The release stays a draft while assets upload and becomes public only when all
uploads succeed. Failed tests, builds or scans create no tag or release.

Main runs share a concurrency queue so version planning and publishing cannot
race. GitHub queues up to 100 pending runs. An older run that is already covered
by a published release skips publication rather than releasing old code as a
new version. Release history must remain ancestral to `main`; force-pushing
unrelated history blocks automatic versioning.

Only the publish job receives repository write permission. The build reads
contents and PR history; publishing uses GitHub's short-lived workflow token.
Checkouts do not persist credentials, and external actions use full commit SHAs.
Both workflows run Windows PowerShell 5.1, with Python 3.11 for the release helper.
No personal token, signing certificate, PowerShell 7 or Node package is needed.

### Retry an interrupted release

Use **Actions > failed run > Re-run failed jobs** to reuse the tested packages
and release plan. A partial draft owned by that plan resumes missing uploads;
an already published release is left unchanged. Conflicting tags, foreign drafts
or draft assets with different hashes stop publication for manual review.
Do not overwrite or move a published tag to repair a failed run.

Running **Windows setup build** manually on `main` can retry planning and building
an unreleased commit. It skips publication if that commit is already released.
Rebuilding all jobs can change unsigned EXE bytes, so use **Re-run failed jobs**
when recovering a partial upload. Manually pushing a tag no longer starts a
second release build; the successful `main` workflow creates its own tag.

## Build locally

Run the full suite from a disposable Windows Sandbox guest with an unused
WHAS registration, a writable source copy, Python 3.11 and 64-bit Windows
PowerShell 5.1. Inside that guest, from the source root:

```powershell
$env:WHAS_SANDBOX_TEST = '1'
.\scripts\test.ps1
```

Set that marker only in the guest; it is a guard, not a sandboxing mechanism.
The runner itself does not create a Sandbox. It runs isolated tests, cleans successful GUID-named temporary fixtures and
retains logs outside the repository. Failed fixtures remain for investigation.
Pass `-Python 'C:\Path\To\python.exe'` if Python is not on PATH.

Build only the standalone EXE:

```powershell
.\scripts\build-gui.ps1
```

To build release assets, use a clean committed checkout with Git installed:

```powershell
.\scripts\build-release.ps1 -Version v1.0.0
```

The default release output is `dist/release`, ignored by Git. Existing release
output is preserved; choose a new directory with `-OutputPath` for another build.
The build includes only committed documentation and declared, committed strategy
assets. It does not include personal configuration, credentials, voice samples,
installed dependencies or model weights. No .NET SDK is required.

Source scripts require permission to run; see
[temporary script permission](installation.md#powershell-execution-policy).
The build itself does not change saved execution policy.

## Verify and run

The EXE and installed command launchers are unsigned. Windows may display an
unrecognized-app/unknown-publisher warning or block execution under application
control. Read [unsigned EXE guidance](installation.md#unsigned-exe-and-windows-warnings).

Calculate the downloaded EXE's checksum:

```powershell
Get-FileHash -LiteralPath .\whas-gui.exe -Algorithm SHA256
```

Compare with `SHA256SUMS.txt` from the same build/release. A checksum checks
agreement with the published bytes, not publisher identity or program safety.
The ZIP includes `build.json` with version, source commit, platform and unsigned
status. The graphical application handles feature setup, usage, configuration and removal.

Continue with the [quickstart](quickstart.md) or
[detailed installation guide](installation.md).
