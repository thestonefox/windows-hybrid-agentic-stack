"""Strategy API v1 adapter for Chatterbox Turbo. Dependencies load only on load()."""
import io
import shutil
from pathlib import Path


class Backend:
    def __init__(self, context):
        self.context = context
        self.voices = Path(context['voices_directory'])
        self.loaded_voice = 'default'
        self.model = None

    def load(self):
        import torchaudio
        from chatterbox.tts_turbo import ChatterboxTurboTTS, Conditionals
        self.torchaudio = torchaudio
        self.conditionals = Conditionals
        self.model = ChatterboxTurboTTS.from_local(
            self.context['models_directory'], device=self.context['device'])
        self.default_conds = self.model.conds
        if self.default_conds is None:
            raise RuntimeError('Built-in Chatterbox voice conditioning is missing')
        self.voices.mkdir(parents=True, exist_ok=True)

    def cache(self, name):
        return self.voices / (name + '_prompt.pt')

    def recording(self, name):
        return self.voices / (name + '_prompt.wav')

    def list_voices(self):
        return ['default'] + sorted(p.name[:-len('_prompt.pt')] for p in self.voices.glob('*_prompt.pt')
                                    if p.name != 'default_prompt.pt')

    def synthesise(self, text, voice):
        if voice != self.loaded_voice:
            if voice == 'default':
                self.model.conds = self.default_conds
            else:
                if not self.cache(voice).is_file():
                    raise FileNotFoundError('Unknown voice')
                self.model.conds = self.conditionals.load(str(self.cache(voice)), map_location='cpu').to(self.context['device'])
            self.loaded_voice = voice
        audio = self.model.generate(text)
        buffer = io.BytesIO()
        self.torchaudio.save(buffer, audio.cpu(), self.model.sr, format='wav')
        return buffer.getvalue()

    def add_voice(self, name, source):
        if name == 'default':
            raise ValueError('The built-in default voice is reserved')
        source = Path(source).resolve()
        if source.suffix.lower() != '.wav' or not source.is_file():
            raise ValueError('Reference must be an existing WAV file')
        cache, dest = self.cache(name), self.recording(name)
        if cache.exists() or dest.exists():
            raise FileExistsError('Voice already exists')
        previous = self.model.conds
        temporary = cache.with_suffix('.tmp.pt')
        try:
            self.model.prepare_conditionals(str(source))
            self.model.conds.save(str(temporary))
            shutil.copy2(source, dest)
            temporary.replace(cache)
        except Exception:
            temporary.unlink(missing_ok=True)
            dest.unlink(missing_ok=True)
            raise
        finally:
            self.model.conds = previous

    def remove_voice(self, name):
        if name == 'default':
            raise ValueError('The built-in default voice is reserved')
        if not self.cache(name).is_file():
            raise FileNotFoundError('Unknown voice')
        self.cache(name).unlink()
        self.recording(name).unlink(missing_ok=True)
        if self.loaded_voice == name:
            self.model.conds = self.default_conds
            self.loaded_voice = 'default'

    def close(self):
        self.model = None


def create_backend(context):
    return Backend(context)
