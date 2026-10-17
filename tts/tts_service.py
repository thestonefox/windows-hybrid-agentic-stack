"""Loopback-only, engine-independent strategy API v1 speech service."""
import importlib.util
import json
import os
import re
import sys
import time
import traceback
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

if os.environ.get('AGENT_STACK_TTS_OWN_LOGS') == '1':
    logs = Path(__file__).resolve().parent
    sys.stdout = (logs / 'service.log').open('w', encoding='utf-8', buffering=1)
    sys.stderr = (logs / 'service-errors.log').open('w', encoding='utf-8', buffering=1)
    sys.stdin = open(os.devnull, 'r')

VOICE_NAME = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$')
MAX_REQUEST = 128000


def owned_path(root, relative):
    candidate = Path(relative)
    if candidate.is_absolute() or '..' in candidate.parts or ':' in relative:
        raise ValueError('Invalid runtime-relative path')
    path = (root / candidate).resolve()
    if not path.is_relative_to(root):
        raise ValueError('Runtime path escapes installation')
    current = root / candidate
    while current != root.parent:
        if current.is_symlink() or (hasattr(current, 'is_junction') and current.is_junction()):
            raise ValueError('Runtime links are not supported')
        if current == root:
            break
        current = current.parent
    return path


def load_backend(root):
    selected = os.environ.get('AGENT_STACK_TTS_ENGINE')
    if selected and not re.fullmatch(r'[a-z][a-z0-9-]{0,47}', selected):
        raise ValueError('Invalid engine selection')
    runtime_path = owned_path(root, f'tts/engines/{selected}/runtime.json') if selected else root / 'tts/runtime.json'
    runtime = json.loads(runtime_path.read_text(encoding='utf-8-sig'))
    if selected and runtime.get('engine') != selected:
        raise ValueError('Selected engine differs from its runtime')
    if runtime.get('schemaVersion') != 1:
        raise ValueError('Unsupported TTS runtime schema')
    state = json.loads((root / '.whas-installation.json').read_text(encoding='utf-8-sig'))
    records = [r for r in state.get('TtsStrategies', []) if r['Id'] == runtime['engine']]
    if len(records) != 1 or records[0]['Status'] != 'Installed':
        raise ValueError('TTS strategy is not fully installed')
    for asset in records[0]['PackageFiles']:
        path = owned_path(root, asset['Path'])
        if hashlib.sha256(path.read_bytes()).hexdigest().upper() != asset['SHA256']:
            raise ValueError(f'Installed strategy package changed: {asset["Path"]}')
    backend_path = owned_path(root, runtime['backendPath'])
    recorded = {asset['Path'] for asset in records[0]['PackageFiles']}
    if runtime['backendPath'] not in recorded:
        raise ValueError('Backend is not in the installed strategy package')
    manifest = json.loads(owned_path(root, 'tts/strategies/' + runtime['engine'] + '/manifest.json').read_text(encoding='utf-8-sig'))
    context_record = records[0]['Context']
    for runtime_key, context_key in [('environmentPath', 'EnvironmentPath'), ('voicesPath', 'VoicesPath'), ('modelsPath', 'ModelsPath'), ('device', 'Device')]:
        if runtime[runtime_key] != context_record[context_key]:
            raise ValueError('Runtime layout differs from installed strategy record')
    if runtime['capabilities'] != manifest['capabilities'] or runtime['device'] not in manifest['devices']:
        raise ValueError('Runtime capabilities/device differ from installed package')
    if runtime['backendPath'] != 'tts/strategies/' + runtime['engine'] + '/' + manifest['entrypoints']['backend']:
        raise ValueError('Runtime backend differs from installed package')
    spec = importlib.util.spec_from_file_location('whas_tts_backend', backend_path,
        submodule_search_locations=[str(backend_path.parent)])
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    context = {'device': runtime['device'], 'voices_directory': str(owned_path(root, runtime['voicesPath'])),
               'models_directory': str(owned_path(root, runtime['modelsPath']))}
    backend = module.create_backend(context)
    for method in ('load', 'synthesise', 'list_voices', 'close'):
        if not callable(getattr(backend, method, None)):
            raise ValueError('Backend does not implement strategy API v1: ' + method)
    if runtime['capabilities'].get('voiceCloning'):
        for method in ('add_voice', 'remove_voice'):
            if not callable(getattr(backend, method, None)):
                raise ValueError('Backend does not implement declared voice capability: ' + method)
    backend.load()
    return backend, runtime


def serve(root, backend, runtime, port, idle_seconds):
    last_used = time.monotonic()

    class Handler(BaseHTTPRequestHandler):
        def respond(self, status, payload, content_type='application/json'):
            self.send_response(status)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def json_response(self, status, data):
            self.respond(status, json.dumps(data).encode('utf-8'))

        def do_GET(self):
            nonlocal last_used
            if self.path == '/status':
                self.json_response(200, {'running': True, 'loaded_voice': getattr(backend, 'loaded_voice', 'default'),
                    'idle_timeout_seconds': idle_seconds, 'engine': runtime['engine'], 'installation_root': str(root),
                    'capabilities': runtime['capabilities']})
            elif self.path == '/voices':
                last_used = time.monotonic()
                self.json_response(200, {'voices': backend.list_voices(), 'loaded_voice': getattr(backend, 'loaded_voice', 'default')})
            else:
                self.json_response(404, {'error': 'Not found'})

        def read_json(self):
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= MAX_REQUEST:
                raise ValueError('Invalid request length')
            data = json.loads(self.rfile.read(length).decode('utf-8'))
            if not isinstance(data, dict):
                raise ValueError('Expected a JSON object')
            return data

        def do_POST(self):
            nonlocal last_used
            if self.path not in ('/speak', '/voices/add', '/voices/remove'):
                self.json_response(404, {'error': 'Not found'})
                return
            last_used = time.monotonic()
            try:
                data = self.read_json()
                name = data.get('voice', 'default') if self.path == '/speak' else data.get('name')
                if not isinstance(name, str) or not VOICE_NAME.fullmatch(name):
                    raise ValueError('Invalid voice name')
                if self.path == '/speak':
                    text = data.get('text')
                    if not isinstance(text, str) or not text.strip() or len(text) > 10000:
                        raise ValueError('Text must contain 1-10000 characters')
                    self.respond(200, backend.synthesise(text, name), 'audio/wav')
                else:
                    if name == 'default':
                        raise ValueError('The built-in default voice is reserved')
                    if not runtime['capabilities'].get('voiceCloning', False):
                        raise NotImplementedError('This engine does not support reference-recording voices')
                    if self.path == '/voices/add':
                        source = data.get('path')
                        if not isinstance(source, str):
                            raise ValueError('A reference WAV path is required')
                        backend.add_voice(name, source)
                        self.json_response(200, {'added': name})
                    else:
                        backend.remove_voice(name)
                        self.json_response(200, {'removed': name})
            except (ValueError, UnicodeDecodeError) as exc:
                self.json_response(400, {'error': str(exc)})
            except FileNotFoundError as exc:
                self.json_response(404, {'error': str(exc)})
            except FileExistsError as exc:
                self.json_response(409, {'error': str(exc)})
            except NotImplementedError as exc:
                self.json_response(501, {'error': str(exc)})
            except Exception:
                traceback.print_exc()
                self.json_response(500, {'error': 'Speech operation failed; check the local service log'})
            finally:
                last_used = time.monotonic()

        def log_message(self, fmt, *args):
            print('%s %s' % (self.address_string(), fmt % args), flush=True)

    server = None
    try:
        server = HTTPServer(('127.0.0.1', port), Handler)
        server.timeout = 1
        print(f"Speech engine {runtime['engine']} ready on port {port}", flush=True)
        while idle_seconds == 0 or time.monotonic() - last_used < idle_seconds:
            server.handle_request()
    finally:
        if server is not None:
            server.server_close()
        backend.close()


def main():
    root = Path(os.environ.get('AGENT_STACK_TTS_ROOT', str(Path(__file__).resolve().parent.parent))).resolve()
    port = int(os.environ.get('AGENT_STACK_TTS_PORT', '18765'))
    idle_seconds = int(os.environ.get('AGENT_STACK_TTS_IDLE_SECONDS', '600'))
    if not 1 <= port <= 65535 or idle_seconds < 0:
        raise ValueError('Invalid speech port or idle timeout')
    backend, runtime = load_backend(root)
    serve(root, backend, runtime, port, idle_seconds)


if __name__ == '__main__':
    main()
