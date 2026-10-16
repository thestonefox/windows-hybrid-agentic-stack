"""Download the declared F5 voice assets into the installation-owned model root."""
import hashlib
import json
import re
import ssl
import sys
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import urlopen

ASSETS = {
    'SWivid/F5-TTS/F5TTS_v1_Base/model_1250000.safetensors': 'f5/model_1250000.safetensors',
    'SWivid/F5-TTS/F5TTS_v1_Base/vocab.txt': 'f5/vocab.txt',
    'SWivid/F5-TTS/README.md': 'f5/README.md',
    'charactr/vocos-mel-24khz/config.yaml': 'vocos/config.yaml',
    'charactr/vocos-mel-24khz/pytorch_model.bin': 'vocos/pytorch_model.bin',
    'charactr/vocos-mel-24khz/README.md': 'vocos/README.md',
}


def asset_key(asset):
    parts = urlparse(asset['source']).path.strip('/').split('/')
    if len(parts) < 5 or parts[2] != 'resolve' or parts[3] != asset['revision']:
        raise ValueError('F5 models require pinned public HTTPS assets and SHA256')
    return '/'.join(parts[:2] + parts[4:])
MAX_ASSET_BYTES = 2 * 1024 * 1024 * 1024


def download_context():
    import certifi
    # Retain Windows/enterprise roots and add the pinned private Mozilla bundle.
    # This changes only this HTTPS context, never the system trust store.
    context = ssl.create_default_context()
    context.load_verify_locations(cafile=certifi.where())
    return context


def digest(path):
    sha = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            sha.update(block)
    return sha.hexdigest()


def prepare(destination, manifest=None):
    manifest = manifest or Path(__file__).with_name('manifest.json')
    assets = json.loads(Path(manifest).read_text(encoding='utf-8-sig'))['models']
    keys = [asset_key(asset) for asset in assets]
    names = [ASSETS.get(key) for key in keys]
    if len(keys) != len(ASSETS) or set(keys) != set(ASSETS):
        raise ValueError('Unexpected F5 model asset list')
    for asset in assets:
        uri = urlparse(asset['source'])
        if (uri.scheme != 'https' or uri.netloc != 'huggingface.co' or uri.query or uri.fragment
                or not re.fullmatch(r'[a-f0-9]{64}', asset['sha256'])
                or not re.fullmatch(r'[a-f0-9]{40}', asset['revision'])
                or '/resolve/' + asset['revision'] + '/' not in uri.path):
            raise ValueError('F5 models require pinned public HTTPS assets and SHA256')
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    for asset, name in zip(assets, names):
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            if digest(target) != asset['sha256']:
                raise ValueError('Existing model asset differs; it was not overwritten: ' + name)
            continue
        temporary = target.with_name(target.name + '.download')
        created = False
        try:
            with urlopen(asset['source'], timeout=60, context=download_context()) as source, temporary.open('xb') as output:
                created = True
                size = 0
                for block in iter(lambda: source.read(1024 * 1024), b''):
                    size += len(block)
                    if size > MAX_ASSET_BYTES:
                        raise ValueError('Model asset exceeds the download limit')
                    output.write(block)
            if digest(temporary) != asset['sha256']:
                raise ValueError('Model asset SHA256 mismatch: ' + name)
            temporary.replace(target)
        finally:
            if created:
                temporary.unlink(missing_ok=True)
        print('Verified F5 model asset:', name, flush=True)


if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[2] == '--verify-runtime':
        from backend import configure_cache
        configure_cache(sys.argv[1])
        import torch
        from f5_tts.api import F5TTS
        from importlib.metadata import version
        device = sys.argv[3]
        suffix = '+cu126' if device == 'cuda' else '+cpu'
        assert version('f5-tts') == '1.1.22'
        assert torch.__version__ == '2.6.0' + suffix
        assert version('torchaudio') == '2.6.0' + suffix
        if device == 'cuda' and not torch.cuda.is_available():
            raise RuntimeError('CUDA requested but unavailable')
        print('F5 imports and selected PyTorch runtime verified')
    else:
        prepare(sys.argv[1])
