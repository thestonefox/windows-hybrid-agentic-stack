"""Download the declared Piper voice assets into the installation-owned model root."""
import hashlib
import json
import re
import ssl
import sys
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import urlopen

FILES = {'en_US-ljspeech-medium.onnx', 'en_US-ljspeech-medium.onnx.json', 'MODEL_CARD'}
MAX_ASSET_BYTES = 128 * 1024 * 1024


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
    names = [Path(urlparse(asset['source']).path).name for asset in assets]
    if len(names) != len(FILES) or set(names) != FILES:
        raise ValueError('Unexpected Piper model asset list')
    for asset in assets:
        uri = urlparse(asset['source'])
        if (uri.scheme != 'https' or uri.netloc != 'huggingface.co' or uri.query or uri.fragment
                or not re.fullmatch(r'[a-f0-9]{64}', asset['sha256'])
                or not re.fullmatch(r'[a-f0-9]{40}', asset['revision'])
                or '/resolve/' + asset['revision'] + '/' not in uri.path):
            raise ValueError('Piper models require pinned public HTTPS assets and SHA256')
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    for asset, name in zip(assets, names):
        target = destination / name
        if target.exists():
            if digest(target) != asset['sha256']:
                raise ValueError('Existing model asset differs; it was not overwritten: ' + name)
            continue
        temporary = target.with_name(name + '.download')
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
        print('Verified Piper model asset:', name, flush=True)


if __name__ == '__main__':
    prepare(sys.argv[1])
