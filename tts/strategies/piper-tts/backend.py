"""Strategy API v1 adapter for Piper's pre-trained English voice."""
import io
import wave
from pathlib import Path

VOICE = 'en_US-ljspeech-medium'


class Backend:
    def __init__(self, context):
        self.context = context
        self.voice = None
        self.loaded_voice = 'default'

    def load(self):
        if self.context['device'] != 'cpu':
            raise ValueError('This Piper strategy supports CPU only')
        from piper import PiperVoice
        models = Path(self.context['models_directory'])
        self.voice = PiperVoice.load(
            str(models / (VOICE + '.onnx')),
            config_path=str(models / (VOICE + '.onnx.json')),
            use_cuda=False, download_dir=str(models))

    def list_voices(self):
        return ['default', VOICE]

    def synthesise(self, text, voice):
        if voice not in self.list_voices():
            raise FileNotFoundError('Unknown Piper voice; use default or ' + VOICE)
        if not isinstance(text, str) or not text.strip():
            raise ValueError('Text is required')
        if self.voice is None:
            raise RuntimeError('Piper is not loaded')
        output = io.BytesIO()
        with wave.open(output, 'wb') as wav:
            self.voice.synthesize_wav(text, wav)
        self.loaded_voice = voice
        return output.getvalue()

    def close(self):
        self.voice = None


def create_backend(context):
    return Backend(context)
