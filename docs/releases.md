# Builds and releases

The repository contains GitHub Actions workflows for unsigned Windows x64 setup.
They run only after the workflow files are pushed to GitHub. Adding these files
locally does not push code, start a cloud run or publish a release.

## Continuous builds

`Windows setup build` runs for main-branch pushes, pull requests and manual
dispatches. It uses Windows PowerShell 5.1 on a Windows runner, with Python 3.11
for dependency-free backend tests. It does not install speech models, invoke a
cloud AI provider or play audio.

The workflow definition:

1. Runs isolated PowerShell and Python suites, and checks the bundled GUI's
   source fingerprint and checksum without executing it.
2. Builds the standalone EXE from a clean, committed checkout.
3. Packages documentation, licence notices and source-commit metadata.
4. Creates SHA-256 checksums for the EXE and ZIP.
5. Requires an active Defender engine, updates its signatures and scans both
   the bundled source-download EXE and the newly built release EXE.
   An unavailable scanner, detection, removal or changed hash blocks upload.
6. Uploads the explicit release files as `whas-windows-x64`, retained for 14 days.

A development GUI build triggered a host Defender detection during this change.
The revised build uses ordinary .NET resources and passed an explicit host
Defender file scan with signatures `1.461.53.0`, real-time protection enabled,
zero detections and an unchanged hash. It was not executed on the host. This
does not establish the cause of the earlier detection or guarantee safety.
Do not disable protection, add exclusions or restore a blocked build to test it.

Eight suites require Windows Sandbox and are guarded by
`WHAS_SANDBOX_TEST=1`. GitHub-hosted runners do not provide that guest, so the
workflow runs `scripts/test.ps1 -SkipSandboxOnly` and prints every skipped
suite. Run the full suite in a disposable Windows Sandbox before publishing a
release. A passing GitHub build does not cover those eight suites.

After a successful run, open its **Actions** page and download the artifact from
the **Artifacts** section. GitHub artifact downloads may require signing in.
The versioned ZIP contains the installer, guides, GUI screenshots and notices.
The loose EXE is
also included for copying to another PC. External prerequisites must still be
installed separately.

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

## Versioned draft releases

Pushing a version tag such as `v1.0.0` runs `Draft Windows release`. It calls the
same build/test workflow, downloads that run's assets, verifies their checksums
and creates a **draft** GitHub Release. Nothing is published publicly until a
maintainer reviews and publishes the draft in GitHub.

Only the draft-release job receives repository write permission. Build jobs use
read permission, checkout does not persist credentials, and external actions
are pinned to full commit SHAs. No signing certificate or long-lived token is
required; the draft job uses GitHub's short-lived workflow token.

Do not create or push a tag until the source and release are ready. Rerunning
against an existing release fails rather than silently replacing published
assets. Review the draft and resolve an interrupted release deliberately.

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
