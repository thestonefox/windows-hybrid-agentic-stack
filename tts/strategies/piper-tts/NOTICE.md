# Piper TTS strategy dependencies

The strategy installs Piper 1.8.0 from PyPI into its private Python environment.
Piper is licensed under **GPL-3.0-or-later**. Its upstream source and licence are:

- https://github.com/OHF-Voice/piper1-gpl/tree/v1.8.0
- https://github.com/OHF-Voice/piper1-gpl/blob/v1.8.0/COPYING
- https://pypi.org/project/piper-tts/1.8.0/

The setup EXE packages this adapter and download metadata. Piper's wheel and
voice weights are downloaded during installation. Dependencies retain their own
licences in the installed Python environment.

The pinned Certifi package supplies Mozilla's CA bundle for verified HTTPS
model downloads without changing the Windows trust store:
https://github.com/certifi/python-certifi

The default voice is `en_US-ljspeech-medium` from `rhasspy/piper-voices`, pinned
to revision `c10ece1aade47bb51c153c893d14e5bf8e5b7117`. Its upstream model card
identifies the LJ Speech dataset as public domain. This describes the dataset;
it does not assign a new licence to the model. The exact upstream `MODEL_CARD`
is downloaded and hash-verified alongside the ONNX model and configuration.

- https://huggingface.co/rhasspy/piper-voices/blob/c10ece1aade47bb51c153c893d14e5bf8e5b7117/en/en_US/ljspeech/medium/MODEL_CARD
- https://keithito.com/LJ-Speech-Dataset/

This package supports CPU inference and one pre-trained English voice, exposed
as `default` and `en_US-ljspeech-medium`. It does not clone a voice from a WAV
recording. Adding other models, languages or GPU execution requires a tested
package update; dropping arbitrary weights into the model directory does not
register a voice.
