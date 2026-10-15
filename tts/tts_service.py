"""Loopback-only Chatterbox Turbo server. Stops after ten minutes without requests."""
import io
import os
import json
import re
import shutil
import sys
import time
import traceback
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

# Native command launchers deliberately pass no inherited pipe handles.
# Open logs before importing dependencies so their startup warnings are retained.
if os.environ.get('AGENT_STACK_TTS_OWN_LOGS') == '1':
    log_dir = Path(__file__).resolve().parent
    sys.stdout = (log_dir / 'service.log').open('w', encoding='utf-8', buffering=1)
    sys.stderr = (log_dir / 'service-errors.log').open('w', encoding='utf-8', buffering=1)
    sys.stdin = open(os.devnull, 'r')

import torchaudio
from chatterbox.tts_turbo import ChatterboxTurboTTS, Conditionals

# Runtime values are supplied by the stack's PowerShell service launcher.
# Defaults preserve the behaviour of the original standalone service.
ROOT = Path(os.environ.get('AGENT_STACK_TTS_ROOT', str(Path(__file__).resolve().parent.parent))).resolve()
VOICES = ROOT / 'voices'
IDLE_SECONDS = int(os.environ.get('AGENT_STACK_TTS_IDLE_SECONDS', '600'))
PORT = int(os.environ.get('AGENT_STACK_TTS_PORT', '18765'))
DEVICE = os.environ.get('AGENT_STACK_TTS_DEVICE', 'cuda').strip().lower()
HOST = '127.0.0.1'

if IDLE_SECONDS < 0:
    raise ValueError('AGENT_STACK_TTS_IDLE_SECONDS must be zero or greater')
if not 1 <= PORT <= 65535:
    raise ValueError('AGENT_STACK_TTS_PORT must be between 1 and 65535')
if DEVICE not in ('cuda', 'cpu'):
    raise ValueError('AGENT_STACK_TTS_DEVICE must be cuda or cpu')
MAX_REQUEST = 128000
VOICE_NAME = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$')

print(f'Loading Chatterbox Turbo on {DEVICE}...', flush=True)
model = ChatterboxTurboTTS.from_pretrained(device=DEVICE)
VOICES.mkdir(parents=True, exist_ok=True)
# Bundled conditioning is the built-in voice. Retain it across custom voice switches.
default_conds = model.conds
if default_conds is None:
    raise RuntimeError('Chatterbox Turbo did not load its built-in voice conditioning (conds.pt).')
print(f'Listening on http://{HOST}:{PORT} (idle timeout {IDLE_SECONDS}s)', flush=True)
last_used = time.monotonic()
current_voice = 'default'


def voice_cache(name):
    return VOICES / (name + '_prompt.pt')


def voice_wav(name):
    return VOICES / (name + '_prompt.wav')


def valid_voice(name):
    return isinstance(name, str) and VOICE_NAME.fullmatch(name) is not None


def voice_names():
    return ['default'] + sorted(p.name[:-len('_prompt.pt')] for p in VOICES.glob('*_prompt.pt')
                  if valid_voice(p.name[:-len('_prompt.pt')]) and p.name != 'default_prompt.pt')


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
        global last_used
        if self.path == '/status':
            self.json_response(200, {'running': True, 'loaded_voice': current_voice,
                                     'idle_timeout_seconds': IDLE_SECONDS})
        elif self.path == '/voices':
            last_used = time.monotonic()
            self.json_response(200, {'voices': voice_names(), 'loaded_voice': current_voice})
        else:
            self.json_response(404, {'error': 'Not found'})

    def read_json(self):
        try:
            length = int(self.headers.get('Content-Length', '0'))
        except ValueError:
            raise ValueError('Invalid Content-Length')
        if not 0 < length <= MAX_REQUEST:
            raise ValueError('Invalid request length')
        data = json.loads(self.rfile.read(length).decode('utf-8'))
        if not isinstance(data, dict):
            raise ValueError('Expected a JSON object')
        return data

    def do_POST(self):
        global last_used, current_voice
        if self.path not in ('/speak', '/voices/add', '/voices/remove'):
            self.json_response(404, {'error': 'Not found'})
            return
        last_used = time.monotonic()
        try:
            data = self.read_json()
        except (ValueError, json.JSONDecodeError, UnicodeDecodeError) as exc:
            self.json_response(400, {'error': str(exc)})
            return
        try:
            if self.path == '/speak':
                phrase = data.get('text')
                voice = data.get('voice') or 'default'
                if not isinstance(phrase, str) or not phrase.strip() or len(phrase) > 10000:
                    self.json_response(400, {'error': 'Text must contain 1-10000 characters'})
                    return
                if not valid_voice(voice):
                    self.json_response(400, {'error': 'Invalid voice name'})
                    return
                if voice == 'default':
                    if current_voice != 'default':
                        model.conds = default_conds
                        current_voice = 'default'
                        print('Voice changed to built-in default', flush=True)
                else:
                    cache = voice_cache(voice)
                    if not cache.is_file():
                        self.json_response(404, {'error': f'Unknown voice: {voice}'})
                        return
                    if current_voice != voice:
                        model.conds = Conditionals.load(str(cache), map_location='cpu').to(DEVICE)
                        current_voice = voice
                        print(f'Voice changed to {voice}', flush=True)
                print(f'Generating {len(phrase)} characters ({voice})...', flush=True)
                audio = model.generate(phrase)
                buffer = io.BytesIO()
                torchaudio.save(buffer, audio.cpu(), model.sr, format='wav')
                self.respond(200, buffer.getvalue(), 'audio/wav')

            elif self.path == '/voices/add':
                name = data.get('name')
                source = data.get('path')
                if name == 'default':
                    self.json_response(400, {'error': 'The built-in default voice cannot be replaced or removed'})
                    return
                if not valid_voice(name):
                    self.json_response(400, {'error': 'Name must be 1-40 characters: letters, numbers, underscore or hyphen; start with letter/number'})
                    return
                if not isinstance(source, str) or not source.lower().endswith('.wav'):
                    self.json_response(400, {'error': 'Reference must be a WAV file'})
                    return
                src = Path(source).resolve()
                if not src.is_file():
                    self.json_response(404, {'error': f'Audio file not found: {src}'})
                    return
                cache = voice_cache(name)
                dest = voice_wav(name)
                if cache.exists() or dest.exists():
                    self.json_response(409, {'error': f'Voice {name} already exists; remove it first to replace it'})
                    return
                # Prepare in memory first. Any failure leaves the other voices unaffected.
                previous_conds = model.conds
                try:
                    model.prepare_conditionals(str(src))
                    temp = VOICES / (name + '_prompt.tmp.pt')
                    try:
                        model.conds.save(str(temp))
                        # Preserve original reference in the managed voices folder.
                        shutil.copy2(src, dest)
                        temp.replace(cache)
                    except Exception:
                        temp.unlink(missing_ok=True)
                        dest.unlink(missing_ok=True)
                        raise
                finally:
                    model.conds = previous_conds
                # Do not change current_voice: its cached conditionals remain resident.
                self.json_response(200, {'added': name, 'cache': str(cache)})
                print(f'Cached voice: {name}', flush=True)

            elif self.path == '/voices/remove':
                name = data.get('name')
                if name == 'default':
                    self.json_response(400, {'error': 'The built-in default voice cannot be replaced or removed'})
                    return
                if not valid_voice(name):
                    self.json_response(400, {'error': 'Invalid voice name'})
                    return
                cache = voice_cache(name)
                if not cache.is_file():
                    self.json_response(404, {'error': f'Unknown voice: {name}'})
                    return
                cache.unlink()
                # Only remove WAV owned by this voice profile (not other user files).
                voice_wav(name).unlink(missing_ok=True)
                if current_voice == name:
                    model.conds = default_conds
                    current_voice = 'default'
                self.json_response(200, {'removed': name})
                print(f'Removed voice: {name}', flush=True)
        except Exception as exc:
            traceback.print_exc()
            self.json_response(500, {'error': str(exc)})
        finally:
            last_used = time.monotonic()

    def log_message(self, fmt, *args):
        print('%s %s' % (self.address_string(), fmt % args), flush=True)


server = HTTPServer((HOST, PORT), Handler)
server.timeout = 1
try:
    while IDLE_SECONDS == 0 or time.monotonic() - last_used < IDLE_SECONDS:
        server.handle_request()
finally:
    server.server_close()
    print('Service stopped; releasing GPU memory.', flush=True)
