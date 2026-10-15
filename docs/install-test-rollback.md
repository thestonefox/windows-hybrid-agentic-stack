# Controlled installation test and rollback

This procedure covers a fresh test installation whose target directory does not yet exist. It restores the stack-owned files, command registration and managed Ollama model to their recorded state. It is not a complete Windows snapshot or a general uninstaller.

## Before installation

Run the baseline capture from Windows PowerShell 5.1 under the normal user account. A sandbox account can resolve a different Documents/profile directory even when it inherits the same `HOME` and `LOCALAPPDATA`. Confirm the account and profile path printed by the capture.

From the repository root:

```powershell
.\tests\save-install-test-baseline.ps1
```

For a custom installation directory, use the same explicit path for baseline capture and the later installation:

```powershell
.\tests\save-install-test-baseline.ps1 -InstallPath 'D:\AI\AgentStack'
```

The script reads effective project configuration, requires an absent installation target and absent native command registration, and inventories Ollama before writing a new snapshot directory under `%USERPROFILE%\WHAS-TestEvidence`. This avoids AppData redirection by packaged hosts. It copies existing profile and local-loader bytes, verifies their SHA-256 hashes, and records their paths, existing backups, parent-directory existence, execution policies, account identity, model names/digests and the original user PATH registry value, type and existence. Keep the printed snapshot directory outside the installation. It does not read or copy authentication credentials, install software, change policies, or perform cleanup.

If a target installation already exists, stop. Preserve it separately or agree on a different test directory; do not use this fresh-install procedure to overwrite it. Refresh the baseline immediately before the approved installation if the machine or configuration has changed.

Review the proposed installation with the user before running it. Keep the existing execution policy; the installer no longer offers to change it. Source test/installation scripts require an allowed script-running context. The package installer and inference can leave caches, logs and authentication token refreshes outside the stack directory; those are not guaranteed to roll back. A VM or machine snapshot is required for exact system restoration.

Run baseline capture without introducing an execution-policy override. The installed native command host does not set execution policy or load profiles. Live user PATH propagation and audible cloud/local CUDA speech now pass with registration outside AppData; controlled rollback of that revised test installation has also passed.

## After installation, before cleanup

Record the exact installation directory, generated model name/digest, native command/state hashes, user PATH, any migrated profile hashes, installer-created backup filenames, and any live TTS process. Compare against `baseline.json`. Keep the original snapshot unchanged.

Before writing or removing a synced file, verify it still matches the known post-install copy. If another PC, OneDrive or the user has edited it, stop and reconcile those changes instead of restoring the entire old file. The same rule applies to an existing local loader and any newly created model whose digest has changed.

## Cleanup sequence after explicit approval

1. Stop only the TTS service started by this installation, using its installed `tts-stop` command after verifying the saved PID, executable and command line belong to this installation. Do not stop unrelated Python processes. Unload the test model from Ollama if it is still resident.
2. Restore the original profile and local-loader bytes from the verified baseline copies when those files existed. If a registration file did not exist before the test, remove only that test-created file. Restoring the exact shared profile also restores its pre-test behaviour on other PCs; coordinate this with the user. For the new command registration, use `Unregister-StackCommands` from `scripts/command-registration.ps1` before removing installation files. Compare the remaining user PATH against the recorded raw value and registry kind; restore the exact baseline only after checking for concurrent changes. Remove only test-created local registration files and preserve unrelated contents and backups.
3. Resolve and inspect the full installation path. Check it is the exact recorded test target, did not exist at baseline, is not a drive root, repository, home directory, or shared parent, and has no unexpected files or reparse-point targets. Remove only that verified test directory. An interrupted installation can still leave a partial directory requiring the same checks.
4. Remove the exact installer-managed Ollama model only if it was absent at baseline and still matches the model created by the test. Preserve every baseline model and digest. Never remove the source `qwen3:8b` or blanket-delete Ollama storage.
5. Compare the profile/local-loader directories against the baseline's backup list. Remove only backup files confirmed to have been created by this test, after retaining needed evidence with the snapshot. Preserve all earlier backups. Remove a newly created parent directory only if the baseline says it was absent and it is now empty.
6. Verify execution policies match the baseline. This test should not change persistent policy. If an approved test did change it, restore only that recorded scope/value, after checking for concurrent changes.
7. Verify original file hashes or original absence, target-directory and native-registration absence, the exact user PATH value/type/existence, original model names/digests and execution policies. Check a new Windows PowerShell session loads the pre-test profile without startup errors. Keep the baseline and test evidence until the user accepts the result.

All recursive file operations must use native PowerShell with checked absolute literal paths. No generic recursive deletion command is provided: the concrete paths and post-install state must be reviewed before cleanup. Installation or cleanup approval does not authorise deleting caches, credentials, the repository, unrelated files, existing models, or external applications.
