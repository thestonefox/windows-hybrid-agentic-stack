# Piper TTS

Piper is the lightweight CPU option. This strategy uses the pretrained
`en_US-ljspeech-medium` English voice. `default` selects that voice.
It does not support adding reference-recording voices or training voices.

## Install

Requires Python 3.11 x64 and the Visual C++ x64 runtime. It installs private
ONNX Runtime dependencies and verified model assets; it does not need PyTorch,
an NVIDIA driver or CUDA. Use `auto` or `cpu`; explicit CUDA is rejected.

From the repository root:

```powershell
.\install.ps1 -Voice -TtsEngine piper-tts
```

If speech management is already installed:

```powershell
whas tts stop
```

```powershell
whas tts install piper-tts
```

See [installation](../installation.md) for prerequisites, source-script
permission and the equivalent EXE route.

## Start and speak

```powershell
whas tts start --engine piper-tts
```

```powershell
whas tts say -Text 'Hello from Piper.' --engine piper-tts
```

```powershell
whas tts voice-list --engine piper-tts
```

`whas tts voice-add` and `whas tts voice-remove` return an explicit unsupported-operation
error for Piper. Switching to Piper does not convert another engine's custom
voice profiles. Use `default` or `en_US-ljspeech-medium` when selecting a voice.

Only one engine runs at a time. Selecting Piper stops a different active engine
but does not change the saved default. To save it as default:

```powershell
whas tts default piper-tts
```

## Remove the engine

Preview:

```powershell
whas tts uninstall piper-tts
```

Apply:

```powershell
whas tts uninstall piper-tts --apply
```

When removing the default while another engine remains, add
`--default-engine ENGINE` with the replacement's ID. Removing the last engine
clears the default. The shared catalog stays available for later reinstall;
full [stack uninstall](../installation.md#uninstallation) removes it.

Piper code and voice assets have their own licences. See the
[package notice](../../tts/strategies/piper-tts/NOTICE.md) and
[troubleshooting](../troubleshooting.md#piper-tts).
