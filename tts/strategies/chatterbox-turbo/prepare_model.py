"""Install a pinned public model into the strategy-owned model directory."""
import sys
import shutil
from pathlib import Path
from huggingface_hub import snapshot_download

snapshot = Path(snapshot_download(
    repo_id="ResembleAI/chatterbox-turbo",
    revision="749d1c1a46eb10492095d68fbcf55691ccf137cd",
    allow_patterns=["*.safetensors", "*.json", "*.txt", "*.pt", "*.model"],
))
destination = Path(sys.argv[1])
destination.mkdir(parents=True, exist_ok=True)
for source in snapshot.iterdir():
    if source.is_file() and source.suffix in ('.safetensors', '.json', '.txt', '.pt', '.model'):
        target = destination / source.name
        if target.exists() and target.stat().st_size == source.stat().st_size:
            # Snapshot revision and existing ownership hashes are checked by the installer.
            continue
        temporary = target.with_suffix(target.suffix + '.download')
        shutil.copyfile(source, temporary)
        temporary.replace(target)
