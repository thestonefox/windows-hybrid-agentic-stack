"""F5 download integrity and voice boundaries; no models or network needed."""
import hashlib
import importlib.util
import io
import json
import ssl
import types
import wave
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

PACKAGE = Path(__file__).resolve().parents[1] / 'tts/strategies/f5-tts'


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, PACKAGE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


DOWNLOAD = load('f5_models', 'prepare_model.py')
BACKEND = load('f5_backend', 'backend.py')


class ModelTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='whas-f5-tests-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.models = self.root / 'models'
        self.manifest = self.root / 'manifest.json'
        self.data = json.loads((PACKAGE / 'manifest.json').read_text(encoding='utf-8-sig'))
        self.payloads = {}
        for asset in self.data['models']:
            key = DOWNLOAD.asset_key(asset)
            self.payloads[asset['source']] = key.encode()
            asset['sha256'] = hashlib.sha256(key.encode()).hexdigest()
        self.save()
        context = patch.object(DOWNLOAD, 'download_context', return_value=object())
        self.context_patch = context
        context.start()
        self.addCleanup(context.stop)

    def save(self):
        self.manifest.write_text(json.dumps(self.data), encoding='utf-8')

    def request(self, url, **kwargs):
        return io.BytesIO(self.payloads[url])

    def test_verified_nested_assets_and_offline_repeat(self):
        with patch.object(DOWNLOAD, 'urlopen', side_effect=self.request):
            DOWNLOAD.prepare(self.models, self.manifest)
        actual = {p.relative_to(self.models).as_posix() for p in self.models.rglob('*') if p.is_file()}
        self.assertEqual(actual, set(DOWNLOAD.ASSETS.values()))
        with patch.object(DOWNLOAD, 'urlopen', side_effect=AssertionError('network')):
            DOWNLOAD.prepare(self.models, self.manifest)

    def test_corruption_not_installed(self):
        with patch.object(DOWNLOAD, 'urlopen', return_value=io.BytesIO(b'wrong')):
            with self.assertRaisesRegex(ValueError, 'SHA256 mismatch'):
                DOWNLOAD.prepare(self.models, self.manifest)
        self.assertFalse(any(p.is_file() for p in self.models.rglob('*')))

    def test_modified_model_and_partial_preserved(self):
        relative = next(iter(DOWNLOAD.ASSETS.values()))
        target = self.models / relative
        target.parent.mkdir(parents=True)
        target.write_bytes(b'user changes')
        with self.assertRaisesRegex(ValueError, 'not overwritten'):
            DOWNLOAD.prepare(self.models, self.manifest)
        self.assertEqual(target.read_bytes(), b'user changes')
        target.unlink()
        partial = target.with_name(target.name + '.download')
        partial.write_bytes(b'original partial')
        with patch.object(DOWNLOAD, 'urlopen', side_effect=self.request):
            with self.assertRaises(FileExistsError):
                DOWNLOAD.prepare(self.models, self.manifest)
        self.assertEqual(partial.read_bytes(), b'original partial')

    def test_unpinned_and_unexpected_asset_rejected(self):
        for source in ('https://huggingface.co/SWivid/F5-TTS/resolve/main/README.md',
                       'https://huggingface.co/SWivid/F5-TTS/resolve/' + 'a' * 40 + '/extra.bin'):
            self.data['models'][0]['source'] = source
            self.save()
            with patch.object(DOWNLOAD, 'urlopen', side_effect=AssertionError('network')):
                with self.assertRaises(ValueError):
                    DOWNLOAD.prepare(self.models, self.manifest)
        self.assertFalse(self.models.exists())

    def test_oversized_download_removed(self):
        with patch.object(DOWNLOAD, 'MAX_ASSET_BYTES', 1), patch.object(
                DOWNLOAD, 'urlopen', side_effect=self.request):
            with self.assertRaisesRegex(ValueError, 'download limit'):
                DOWNLOAD.prepare(self.models, self.manifest)
        self.assertFalse(any(p.is_file() for p in self.models.rglob('*')))

    def test_tls_keeps_certificate_and_hostname_verification(self):
        self.context_patch.stop()
        context = ssl.create_default_context()
        with patch.dict('sys.modules', {'certifi': types.SimpleNamespace(where=lambda: 'private-ca.pem')}), patch.object(
                DOWNLOAD.ssl, 'create_default_context', return_value=context), patch.object(
                context, 'load_verify_locations') as roots:
            self.assertIs(DOWNLOAD.download_context(), context)
        roots.assert_called_once_with(cafile='private-ca.pem')
        self.assertTrue(context.check_hostname)
        self.assertEqual(context.verify_mode, ssl.CERT_REQUIRED)


class VoiceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='whas-f5-voices-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.backend = BACKEND.create_backend({'device': 'cpu',
            'voices_directory': str(self.root / 'voices'), 'models_directory': str(self.root / 'models')})
        self.backend.voices.mkdir()

    def test_reserved_and_traversal_names(self):
        for name in ('default', '../escape', 'a/b', '', 'a' * 41):
            with self.assertRaises(ValueError):
                self.backend.paths(name)

    def test_missing_transcript_does_not_create_voice_or_transcribe(self):
        self.backend.model = object()
        recording = self.root / 'sample.wav'
        recording.write_bytes(b'fixture')
        with self.assertRaisesRegex(ValueError, 'matching UTF-8 .txt transcript'):
            self.backend.add_voice('speaker', recording)
        self.assertEqual(list(self.backend.voices.iterdir()), [])

    def test_list_remove_and_close(self):
        recording, transcript = self.backend.paths('speaker')
        recording.write_bytes(b'fixture')
        self.assertEqual(self.backend.list_voices(), ['default'])
        transcript.write_text('Example transcript.', encoding='utf-8')
        self.assertEqual(self.backend.list_voices(), ['default', 'speaker'])
        self.backend.loaded_voice = 'speaker'
        self.backend.remove_voice('speaker')
        self.assertEqual(self.backend.loaded_voice, 'default')
        self.assertFalse(recording.exists())
        self.assertFalse(transcript.exists())
        self.backend.close()
        with self.assertRaisesRegex(RuntimeError, 'not loaded'):
            self.backend.synthesise('test', 'default')

    def test_unknown_voice_and_empty_text(self):
        self.backend.model = object()
        with self.assertRaises(FileNotFoundError):
            self.backend.synthesise('test', 'missing')
        with self.assertRaises(ValueError):
            self.backend.synthesise(' ', 'default')

    def test_duplicate_voice_preserves_files(self):
        self.backend.model = object()
        recording, transcript = self.backend.paths('speaker')
        recording.write_bytes(b'original audio')
        transcript.write_text('Original transcript.', encoding='utf-8')
        with self.assertRaises(FileExistsError):
            self.backend.add_voice('speaker', self.root / 'missing.wav')
        self.assertEqual(recording.read_bytes(), b'original audio')
        self.assertEqual(transcript.read_text(encoding='utf-8'), 'Original transcript.')

    def test_synthesis_supplies_transcript_and_returns_pcm(self):
        calls = []

        def infer(*args, **kwargs):
            calls.append((args, kwargs))
            return [0.1], 24000, None

        def write(output, samples, rate, **kwargs):
            self.assertEqual(kwargs, {'format': 'WAV', 'subtype': 'PCM_16'})
            with wave.open(output, 'wb') as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(rate)
                wav.writeframes(b'\x01\x00' * 2400)

        self.backend.model = types.SimpleNamespace(ema_model=object(), vocoder=object())
        self.backend.infer_process = infer
        self.backend.soundfile = types.SimpleNamespace(write=write)
        self.backend.default_reference = self.root / 'upstream.wav'
        recording, transcript = self.backend.paths('speaker')
        recording.write_bytes(b'fixture')
        transcript.write_text('Custom transcript', encoding='utf-8')
        for voice, expected in [('default', BACKEND.DEFAULT_TEXT + ' '), ('speaker', 'Custom transcript. ')]:
            with wave.open(io.BytesIO(self.backend.synthesise('Hello.', voice)), 'rb') as wav:
                self.assertEqual(wav.getframerate(), 24000)
                self.assertEqual(wav.getnframes(), 2400)
            self.assertEqual(calls[-1][0][1], expected)
            self.assertEqual(calls[-1][1]['device'], 'cpu')
            self.assertEqual(self.backend.loaded_voice, voice)

    def test_invalid_device_rejected_before_dependencies(self):
        self.backend.context['device'] = 'auto'
        with self.assertRaisesRegex(ValueError, 'CPU or CUDA'):
            self.backend.load()


if __name__ == '__main__':
    unittest.main()
