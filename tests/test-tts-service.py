"""Exercise strategy dispatch and HTTP behavior without ML packages or audio playback."""
import hashlib
import http.client
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('tts_service', REPO / 'tts/tts_service.py')
SERVICE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SERVICE)
FAKE_BACKEND = '''
import io, wave
class Backend:
    loaded_voice = 'default'
    def load(self): pass
    def close(self): pass
    def list_voices(self): return ['default']
    def synthesise(self, text, voice):
        if voice != 'default': raise FileNotFoundError('Unknown voice')
        output=io.BytesIO()
        with wave.open(output, 'wb') as wav:
            wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(24000)
            wav.writeframes(b'\\x01\\x00' * 2400)
        return output.getvalue()
def create_backend(context): return Backend()
'''


class StrategyServiceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='whas-service-tests-')
        self.root = Path(self.temp.name)
        package = self.root / 'tts/strategies/test-engine'
        package.mkdir(parents=True)
        manifest = {'capabilities': {'builtinVoice': True, 'voiceCloning': False},
                    'devices': ['cpu'], 'entrypoints': {'backend': 'backend.py'}}
        (package / 'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
        (package / 'backend.py').write_text(FAKE_BACKEND, encoding='utf-8')
        self.runtime = {'schemaVersion': 1, 'engine': 'test-engine',
            'environmentPath': 'tts/engines/test-engine/.venv', 'voicesPath': 'voices/test-engine',
            'modelsPath': 'tts/engines/test-engine/models', 'device': 'cpu',
            'backendPath': 'tts/strategies/test-engine/backend.py', 'capabilities': manifest['capabilities']}
        self.write_runtime()
        files = [{'Path': str(path.relative_to(self.root)).replace('\\', '/'),
                  'SHA256': hashlib.sha256(path.read_bytes()).hexdigest().upper()}
                 for path in [package / 'manifest.json', package / 'backend.py']]
        state = {'TtsStrategies': [{'Id': 'test-engine', 'Status': 'Installed', 'PackageFiles': files,
            'Context': {'EnvironmentPath': self.runtime['environmentPath'], 'VoicesPath': self.runtime['voicesPath'],
                        'ModelsPath': self.runtime['modelsPath'], 'Device': 'cpu'}}]}
        (self.root / '.whas-installation.json').write_text(json.dumps(state), encoding='utf-8')
        self.process = None

    def tearDown(self):
        if self.process is not None:
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                self.process.wait(timeout=5)
            self.process.stderr.close()
        self.temp.cleanup()

    def write_runtime(self):
        (self.root / 'tts/runtime.json').write_text(json.dumps(self.runtime), encoding='utf-8')

    def test_backend_contract(self):
        backend, runtime = SERVICE.load_backend(self.root)
        self.assertEqual(backend.list_voices(), ['default'])
        self.assertTrue(backend.synthesise('test', 'default').startswith(b'RIFF'))
        backend.close()

    def test_modified_package_rejected_before_import(self):
        (self.root / self.runtime['backendPath']).write_text("raise AssertionError('must not execute')", encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'package changed'):
            SERVICE.load_backend(self.root)

    def test_changed_layout_and_capabilities_rejected(self):
        self.runtime['modelsPath'] = 'different-models'
        self.write_runtime()
        with self.assertRaisesRegex(ValueError, 'layout differs'):
            SERVICE.load_backend(self.root)

    def test_path_escape_rejected(self):
        with self.assertRaises(ValueError):
            SERVICE.owned_path(self.root, '../outside')

    def test_http_voice_capabilities_errors_and_idle_shutdown(self):
        with socket.socket() as reserved:
            reserved.bind(('127.0.0.1', 0))
            port = reserved.getsockname()[1]
        environment = dict(os.environ, AGENT_STACK_TTS_ROOT=str(self.root),
            AGENT_STACK_TTS_PORT=str(port), AGENT_STACK_TTS_IDLE_SECONDS='1', PYTHONDONTWRITEBYTECODE='1')
        self.process = subprocess.Popen([sys.executable, str(REPO / 'tts/tts_service.py')],
            env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        deadline = time.monotonic() + 8
        while True:
            try:
                connection = http.client.HTTPConnection('127.0.0.1', port, timeout=2)
                connection.request('GET', '/status')
                response = connection.getresponse()
                status = json.loads(response.read())
                connection.close()
                break
            except OSError:
                if time.monotonic() >= deadline:
                    self.fail('Service did not become ready')
                time.sleep(0.05)
        self.assertEqual(status['engine'], 'test-engine')
        self.assertEqual(Path(status['installation_root']), self.root)

        def request(path, payload):
            connection = http.client.HTTPConnection('127.0.0.1', port, timeout=2)
            connection.request('POST', path, json.dumps(payload), {'Content-Type': 'application/json'})
            response = connection.getresponse()
            result = response.status, response.read()
            connection.close()
            return result

        code, audio = request('/speak', {'text': 'Test', 'voice': 'default'})
        self.assertEqual(code, 200)
        self.assertTrue(audio.startswith(b'RIFF'))
        self.assertEqual(request('/voices/add', {'name': 'custom', 'path': 'sample.wav'})[0], 501)
        self.assertEqual(request('/speak', {'text': '', 'voice': 'default'})[0], 400)
        self.assertEqual(request('/speak', {'text': 'Test', 'voice': '../escape'})[0], 400)
        self.assertEqual(request('/speak', {'text': 'Test', 'voice': 'missing'})[0], 404)
        self.assertEqual(self.process.wait(timeout=4), 0)


if __name__ == '__main__':
    unittest.main()
