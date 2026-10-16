# F5-TTS strategy dependencies and models

- Official project: <https://github.com/SWivid/F5-TTS>
- Published runtime: `f5-tts` 1.1.22, distributed separately under the
  [MIT licence](https://github.com/SWivid/F5-TTS/blob/2f866649b779881af8bd644e76b9a6d95053da29/LICENSE).
- F5TTS_v1_Base pretrained weights are **CC-BY-NC-4.0**: noncommercial use
  only. The code's MIT licence does not grant commercial use of the weights.
  See the pinned [model card](https://huggingface.co/SWivid/F5-TTS/blob/84e5a410d9cead4de2f847e7c9369a6440bdfaca/README.md)
  and <https://creativecommons.org/licenses/by-nc/4.0/>.
- Vocos mel-24kHz is MIT licensed; its pinned model card is downloaded
  separately beside its configuration and weights.
- The default reference WAV is the English example shipped by upstream in
  the hash-verified F5 Python wheel, with its supplied transcript. No reference
  recording or model weight is embedded in this repository or setup EXE.
- PyTorch, Torchaudio and all transitive packages retain their own licences
  in the installed private environment. CPU and CUDA 12.6 builds are selected
  explicitly. Certifi provides private CA roots without modifying Windows.

The Windows x64 / Python 3.11 locks include all declared runtime dependencies,
including upstream training and UI dependencies, although this adapter starts
neither a Gradio server nor training. Three upstream dependencies are supplied
as hash-pinned source archives; they build with the separately pinned private
packaging tools, dependency resolution and build isolation disabled.

The adapter performs local inference only. It never automatically downloads
an ASR model. Custom voices require a mono 3-12 second WAV and a matching UTF-8
`.txt` transcript. Users supply and retain their personal recordings/transcripts.
