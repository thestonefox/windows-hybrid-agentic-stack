"""Piper package integrity and backend boundaries; no ML packages or network needed."""
import hashlib
import importlib.util
import io
import json
import ssl
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch
import wave

PACKAGE = Path(__file__).resolve().parents[1] / 'tts/strategies/piper-tts'


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, PACKAGE / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


DOWNLOAD = load('piper_models', 'prepare_model.py')
BACKEND = load('piper_backend', 'backend.py')


class ModelTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='whas-piper-tests-')
        self.root = Path(self.temp.name)
        self.models = self.root / 'models'
        self.manifest = self.root / 'manifest.json'
        self.data = json.loads((PACKAGE / 'manifest.json').read_text(encoding='utf-8-sig'))
        self.context = object()
        context_patch = patch.object(DOWNLOAD, 'download_context', return_value=self.context)
        context_patch.start()
        self.addCleanup(context_patch.stop)
        self.payloads = {name: ('fixture: ' + name).encode() for name in DOWNLOAD.FILES}
        for item in self.data['models']:
            name = Path(item['source']).name
            item['sha256'] = hashlib.sha256(self.payloads[name]).hexdigest()
        self.save()

    def tearDown(self):
        self.temp.cleanup()

    def save(self):
        self.manifest.write_text(json.dumps(self.data), encoding='utf-8')

    def request(self, url, timeout, context):
        self.assertIs(context, self.context)
        return io.BytesIO(self.payloads[Path(url).name])

    def test_verified_download_and_offline_repeat(self):
        with patch.object(DOWNLOAD, 'urlopen', side_effect=self.request):
            DOWNLOAD.prepare(self.models, self.manifest)
        self.assertEqual({p.name for p in self.models.iterdir()}, DOWNLOAD.FILES)
        with patch.object(DOWNLOAD, 'urlopen', side_effect=AssertionError('no repeat download')):
            DOWNLOAD.prepare(self.models, self.manifest)

    def test_corrupt_download_is_removed_and_not_installed(self):
        with patch.object(DOWNLOAD, 'urlopen', return_value=io.BytesIO(b'corrupted download')):
            with self.assertRaisesRegex(ValueError, 'SHA256 mismatch'):
                DOWNLOAD.prepare(self.models, self.manifest)
        self.assertEqual(list(self.models.iterdir()), [])

    def test_existing_modified_model_is_preserved(self):
        self.models.mkdir()
        model = self.models / Path(self.data['models'][0]['source']).name
        model.write_bytes(b'user modified model')
        with patch.object(DOWNLOAD, 'urlopen', side_effect=AssertionError('no network')):
            with self.assertRaisesRegex(ValueError, 'not overwritten'):
                DOWNLOAD.prepare(self.models, self.manifest)
        self.assertEqual(model.read_bytes(), b'user modified model')

    def test_existing_partial_file_is_preserved(self):
        self.models.mkdir()
        partial = self.models / (Path(self.data['models'][0]['source']).name + '.download')
        partial.write_bytes(b'existing partial file')
        with patch.object(DOWNLOAD, 'urlopen', side_effect=self.request):
            with self.assertRaises(FileExistsError):
                DOWNLOAD.prepare(self.models, self.manifest)
        self.assertEqual(partial.read_bytes(), b'existing partial file')

    def test_unpinned_source_rejected_before_network(self):
        self.data['models'][0]['source'] = self.data['models'][0]['source'].replace(
            self.data['models'][0]['revision'], 'main')
        self.save()
        with patch.object(DOWNLOAD, 'urlopen', side_effect=AssertionError('no network')):
            with self.assertRaisesRegex(ValueError, 'pinned public HTTPS'):
                DOWNLOAD.prepare(self.models, self.manifest)
        self.assertFalse(self.models.exists())

    def test_oversized_download_rejected_and_partial_removed(self):
        with patch.object(DOWNLOAD, 'MAX_ASSET_BYTES', 2), patch.object(
                DOWNLOAD, 'urlopen', return_value=io.BytesIO(b'oversized')):
            with self.assertRaisesRegex(ValueError, 'download limit'):
                DOWNLOAD.prepare(self.models, self.manifest)
        self.assertEqual(list(self.models.iterdir()), [])


class BackendTests(unittest.TestCase):
    def test_wav_alias_unknown_voice_and_close(self):
        class Voice:
            @staticmethod
            def load(*args, **kwargs):
                if kwargs['use_cuda']:
                    raise AssertionError('CPU strategy requested CUDA')
                return Voice()

            def synthesize_wav(self, text, wav):
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(22050)
                wav.writeframes(b'\x01\x00' * 2205)

        backend = BACKEND.create_backend({'device': 'cpu', 'models_directory': 'models'})
        with patch.dict('sys.modules', {'piper': types.SimpleNamespace(PiperVoice=Voice)}):
            backend.load()
        self.assertEqual(backend.list_voices(), ['default', BACKEND.VOICE])
        for name in backend.list_voices():
            with wave.open(io.BytesIO(backend.synthesise('test', name)), 'rb') as wav:
                self.assertEqual(wav.getnframes(), 2205)
        with self.assertRaises(FileNotFoundError):
            backend.synthesise('test', '../other')
        backend.close()
        with self.assertRaisesRegex(RuntimeError, 'not loaded'):
            backend.synthesise('test', 'default')

    def test_cuda_rejected_without_importing_piper(self):
        backend = BACKEND.create_backend({'device': 'cuda', 'models_directory': 'models'})
        with self.assertRaisesRegex(ValueError, 'CPU only'):
            backend.load()


class TlsTests(unittest.TestCase):
    def test_pinned_ca_bundle_keeps_certificate_and_hostname_verification(self):
        context = ssl.create_default_context()
        certifi = types.SimpleNamespace(where=lambda: 'private-pinned-ca-bundle.pem')
        with patch.dict('sys.modules', {'certifi': certifi}), patch.object(
                DOWNLOAD.ssl, 'create_default_context', return_value=context), patch.object(
                context, 'load_verify_locations') as load_roots:
            result = DOWNLOAD.download_context()
        load_roots.assert_called_once_with(cafile='private-pinned-ca-bundle.pem')
        self.assertTrue(result.check_hostname)
        self.assertEqual(result.verify_mode, ssl.CERT_REQUIRED)


if __name__ == '__main__':
    unittest.main()
