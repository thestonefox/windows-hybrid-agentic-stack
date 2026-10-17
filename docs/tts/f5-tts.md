# F5-TTS

F5 supports CPU or NVIDIA CUDA speech with reference WAVs and exact transcripts.
The default is the male English reference `basic_ref_en.wav` bundled in the
verified F5 package, with its supplied transcript. No separate reference
download or automatic transcription model is required.

**Pretrained F5 weights are CC-BY-NC-4.0, for noncommercial use.** Code is MIT.
See the [package notice](../../tts/strategies/f5-tts/NOTICE.md).

## Install

Requires Python 3.11 x64 and the Visual C++ x64 runtime. The private environment
contains F5, PyTorch and Vocos, with pinned dependencies and verified models.
CUDA requires a compatible NVIDIA GPU and driver. CPU speech is slower.

From the repository root:

```powershell
.\install.ps1 -Voice -TtsEngine f5-tts
```

If speech management is already installed:

```powershell
whas tts stop
```

```powershell
whas tts install f5-tts
```

See [installation](../installation.md) for prerequisites, temporary source-script
permission and the EXE route.

## Start and speak

```powershell
whas tts start --engine f5-tts
```

```powershell
whas tts say -Text 'Hello from F5.' --engine f5-tts
```

Only one engine runs at a time. Selecting F5 stops another active engine;
it does not change the saved default. The first request loads its models.
Keep CPU requests short; the speech request timeout is 180 seconds.

## Add a reference voice

Prepare two files together, with the same base name:

```text
C:\Voices\sample.wav
C:\Voices\sample.txt
```

The WAV must be a nonsilent mono recording lasting 3-12 seconds, no larger than
32 MiB. Use a recording you have permission to use. The UTF-8 text file must
contain the exact words spoken in that WAV: 1-4000 characters, at most 16,000
bytes. A text file describing the speaker or the desired output is not the
transcript.

```powershell
whas tts voice-add -Path 'C:\Voices\sample.wav' -Name myvoice --engine f5-tts
```

A missing transcript is rejected with the expected `.txt` path before model
startup or switching. Empty, invalid or oversized transcripts are rejected too;
the backend additionally validates the recording. Existing profiles are not
overwritten. Adding a profile stores the reference pair; it does not train
new model weights or download Whisper.

```powershell
whas tts voice-test myvoice --engine f5-tts
```

```powershell
whas tts voice-list --engine f5-tts
```

Adding or testing a voice does not change the saved default. To use this
voice for future F5 speech:

```powershell
whas configure --set speech.voice myvoice --engine f5-tts
```

Choose F5 as the default engine separately with `whas tts default f5-tts`.

Names contain letters, digits, underscores or hyphens, starting with a letter
or digit, up to 40 characters. `default` is reserved. Remove a custom pair
with confirmation:

```powershell
whas tts voice-remove myvoice --engine f5-tts
```

## Remove the engine

Preview:

```powershell
whas tts uninstall f5-tts
```

Apply:

```powershell
whas tts uninstall f5-tts --apply
```

If it is the default and other engines remain, add `--default-engine ENGINE`
with an installed replacement. Removing the last engine clears the default.
Personal WAV/transcript pairs are preserved. Full
[stack uninstall](../installation.md#uninstallation) removes all engines'
unchanged tracked environments, models and catalog files.

See [F5 troubleshooting](../troubleshooting.md#f5-tts-strategy) for diagnostics.
