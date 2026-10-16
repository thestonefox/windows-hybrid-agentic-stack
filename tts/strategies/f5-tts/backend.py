"""F5-TTS v1 strategy: local weights and WAV/transcript reference voices."""
import io
import os
import re
from pathlib import Path

VOICE_NAME = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$')
DEFAULT_TEXT = 'Some call me nature, others call me mother nature.'


def configure_cache(models):
    # These settings affect only the private installer/service Python process.
    cache = Path(models) / '.cache'
    os.environ['HF_HOME'] = str(cache / 'huggingface')
    os.environ['HF_HUB_OFFLINE'] = '1'
    os.environ['TRANSFORMERS_OFFLINE'] = '1'
    os.environ['MPLCONFIGDIR'] = str(cache / 'matplotlib')
    os.environ['XDG_CACHE_HOME'] = str(cache)


class Backend:
    def __init__(self, context):
        self.context = context
        self.voices = Path(context['voices_directory'])
        self.models = Path(context['models_directory'])
        self.model = None
        self.loaded_voice = 'default'

    def load(self):
        if self.context['device'] not in ('cpu', 'cuda'):
            raise ValueError('F5 requires CPU or CUDA')
        configure_cache(self.models)
        import torch
        import soundfile
        from importlib.resources import files
        from f5_tts.api import F5TTS
        from f5_tts.infer.utils_infer import infer_process
        if self.context['device'] == 'cuda' and not torch.cuda.is_available():
            raise RuntimeError('CUDA requested but unavailable in the F5 environment')
        self.soundfile = soundfile
        self.infer_process = infer_process
        self.model = F5TTS(
            model='F5TTS_v1_Base', device=self.context['device'],
            ckpt_file=str(self.models / 'f5/model_1250000.safetensors'),
            vocab_file=str(self.models / 'f5/vocab.txt'),
            vocoder_local_path=str(self.models / 'vocos'))
        self.default_reference = Path(str(files('f5_tts').joinpath(
            'infer/examples/basic/basic_ref_en.wav')))
        if not self.default_reference.is_file():
            raise RuntimeError('F5 package is missing its default reference recording')
        self.voices.mkdir(parents=True, exist_ok=True)

    def paths(self, name):
        if not isinstance(name, str) or not VOICE_NAME.fullmatch(name) or name == 'default':
            raise ValueError('Invalid or reserved voice name')
        paths = (self.voices / (name + '.wav'), self.voices / (name + '.txt'))
        if any(p.is_symlink() or p.resolve().parent != self.voices.resolve() for p in paths):
            raise ValueError('Voice links are unsupported')
        return paths

    def list_voices(self):
        return ['default'] + sorted(p.stem for p in self.voices.glob('*.wav')
                                   if VOICE_NAME.fullmatch(p.stem) and p.stem != 'default'
                                   and not p.is_symlink() and p.with_suffix('.txt').is_file()
                                   and not p.with_suffix('.txt').is_symlink())

    def synthesise(self, text, voice):
        if self.model is None:
            raise RuntimeError('F5 is not loaded')
        if not isinstance(text, str) or not text.strip():
            raise ValueError('Speech text is empty')
        if voice == 'default':
            reference, transcript = self.default_reference, DEFAULT_TEXT
        else:
            reference, sidecar = self.paths(voice)
            if not reference.is_file() or not sidecar.is_file():
                raise FileNotFoundError('Unknown voice')
            transcript = sidecar.read_text(encoding='utf-8-sig').strip()
        if not transcript or len(transcript) > 4000:
            raise ValueError('Reference transcript must contain 1-4000 characters')
        # Supplying the transcript avoids automatic ASR downloads. Call the
        # upstream inference function directly: no ffmpeg or temporary WAVs.
        if not transcript.endswith(('.', '!', '?', '。')):
            transcript += '.'
        wav, rate, _ = self.infer_process(
            str(reference), transcript + ' ', text, self.model.ema_model,
            self.model.vocoder, device=self.context['device'],
            nfe_step=32, show_info=lambda *args: None, progress=None)
        output = io.BytesIO()
        self.soundfile.write(output, wav, rate, format='WAV', subtype='PCM_16')
        self.loaded_voice = voice
        return output.getvalue()

    def add_voice(self, name, source):
        if self.model is None:
            raise RuntimeError('F5 is not loaded')
        dest, transcript_dest = self.paths(name)
        if dest.exists() or transcript_dest.exists():
            raise FileExistsError('Voice already exists')
        source = Path(source)
        transcript_path = source.with_suffix('.txt')
        if source.suffix.lower() != '.wav' or not source.is_file():
            raise ValueError('Reference must be an existing WAV file')
        if not transcript_path.is_file():
            raise ValueError('F5 needs a matching UTF-8 .txt transcript beside the reference WAV')
        if transcript_path.stat().st_size > 16000 or source.stat().st_size > 32 * 1024 * 1024:
            raise ValueError('Reference recording or transcript exceeds the size limit')
        transcript = transcript_path.read_text(encoding='utf-8-sig').strip()
        if not transcript or len(transcript) > 4000:
            raise ValueError('Reference transcript must contain 1-4000 characters')
        info = self.soundfile.info(str(source))
        if info.format != 'WAV' or not 3 <= info.duration <= 12 or info.channels != 1:
            raise ValueError('F5 reference must be a mono WAV lasting 3-12 seconds')
        audio, rate = self.soundfile.read(str(source), dtype='float32')
        import numpy as np
        if not np.isfinite(audio).all() or np.max(np.abs(audio)) < 0.001:
            raise ValueError('Reference audio is silent or invalid')
        created = []
        try:
            with dest.open('xb') as stream:
                created.append(dest)
                self.soundfile.write(stream, audio, rate, format='WAV', subtype='PCM_16')
            with transcript_dest.open('x', encoding='utf-8') as stream:
                created.append(transcript_dest)
                stream.write(transcript)
        except Exception:
            for path in created:
                path.unlink(missing_ok=True)
            raise

    def remove_voice(self, name):
        recording, transcript = self.paths(name)
        if not recording.is_file() or not transcript.is_file():
            raise FileNotFoundError('Unknown voice')
        recording.unlink()
        transcript.unlink()
        if self.loaded_voice == name:
            self.loaded_voice = 'default'

    def close(self):
        self.model = None


def create_backend(context):
    return Backend(context)
