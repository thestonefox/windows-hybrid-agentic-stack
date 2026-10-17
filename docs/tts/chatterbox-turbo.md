# Chatterbox Turbo

Chatterbox supports CPU or NVIDIA CUDA speech, a built-in default voice and
custom voices from reference WAV recordings. Adding a voice conditions speech
on a reference; it does not train new model weights.

## Install

Requires Python 3.11 x64 and the Visual C++ x64 runtime. See the
[installation guide](../installation.md) for prerequisites and script permission.
From the repository root, install speech with this engine:

```powershell
.\install.ps1 -Voice -TtsEngine chatterbox-turbo
```

If speech is already installed with the engine-management commands, stop it
and add Chatterbox from the installed catalog:

```powershell
whas tts stop
```

```powershell
whas tts install chatterbox-turbo
```

The installer uses a private Python environment and model directory. Automatic
device selection uses CUDA when detected, otherwise CPU; an explicit device
must be supported on the target machine.

## Start and speak

```powershell
whas tts start --engine chatterbox-turbo
```

```powershell
whas tts say -Text 'Hello from Chatterbox.' --engine chatterbox-turbo
```

Only one engine runs at a time. Selecting another installed engine stops the
previous one. An explicit engine does not change the saved default.

## Add a reference voice

Use a clear WAV recording of one speaker that you have permission to use.
A transcript is not required. Replace the example path with your actual file:

```powershell
whas tts voice-add -Path 'C:\Voices\sample.wav' -Name myvoice --engine chatterbox-turbo
```

```powershell
whas tts voice-test myvoice --engine chatterbox-turbo
```

```powershell
whas tts voice-list --engine chatterbox-turbo
```

Adding or testing a voice does not make it the default. To use it for future
Chatterbox speech:

```powershell
whas configure --set speech.voice myvoice --engine chatterbox-turbo
```

Set the default engine separately with `whas tts default chatterbox-turbo`.

Names use letters, digits, underscores or hyphens, starting with a letter or
digit, up to 40 characters. `default` is reserved. Existing voices are not
overwritten. A Chatterbox profile is separate from a same-named F5 profile.

To remove a custom profile, confirm the deletion prompt:

```powershell
whas tts voice-remove myvoice --engine chatterbox-turbo
```

## Remove the engine

Preview:

```powershell
whas tts uninstall chatterbox-turbo
```

Apply:

```powershell
whas tts uninstall chatterbox-turbo --apply
```

If it is the default and other engines remain, supply an installed replacement
with `--default-engine ENGINE`. Removing the last engine clears the default.
Personal voices are preserved. Full [stack uninstall](../installation.md#uninstallation)
removes all engines' unchanged tracked files.

See [strategy licensing](../tts-strategies.md) and
[troubleshooting](../troubleshooting.md) for limitations and diagnostics.
