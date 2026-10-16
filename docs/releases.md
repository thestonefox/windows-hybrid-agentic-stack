# Builds and releases

The repository contains GitHub Actions workflows for unsigned Windows x64 setup.
They run only after the workflow files are pushed to GitHub. Adding these files
locally does not push code, start a cloud run or publish a release.

## Continuous builds

`Windows setup build` runs for main-branch pushes, pull requests and manual
dispatches. It uses Windows PowerShell 5.1 on a Windows runner, with Python 3.11
for dependency-free backend tests. It does not install speech models, invoke a
cloud AI provider or play audio.

The workflow:

1. Runs isolated PowerShell and Python suites.
2. Builds the standalone EXE from a clean, committed checkout.
3. Packages documentation, licence notices and source-commit metadata.
4. Creates SHA-256 checksums for the EXE and ZIP.
5. Uploads the explicit release files as `whas-windows-x64`, retained for 14 days.

After a successful run, open its **Actions** page and download the artifact from
the **Artifacts** section. GitHub artifact downloads may require signing in.
The versioned ZIP contains the installer, guides and notices. The loose EXE is
also included for copying to another PC. External prerequisites must still be
installed separately.

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

From the repository root in 64-bit Windows PowerShell 5.1:

```powershell
.\scripts\test.ps1
```

This runs isolated tests, cleans successful GUID-named temporary fixtures and
retains logs outside the repository. Failed fixtures remain for investigation.
Pass `-Python 'C:\Path\To\python.exe'` if Python is not on PATH.

Build only the standalone EXE:

```powershell
.\scripts\build-setup.ps1
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
Get-FileHash -LiteralPath .\whas-setup.exe -Algorithm SHA256
```

Compare with `SHA256SUMS.txt` from the same build/release. A checksum checks
agreement with the published bytes, not publisher identity or program safety.
The ZIP includes `build.json` with version, source commit, platform and unsigned
status. Keep the EXE outside the installation directory for later uninstall.

Continue with the [quickstart](quickstart.md) or
[detailed installation guide](installation.md).
