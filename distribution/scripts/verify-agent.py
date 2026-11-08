#!/usr/bin/env python3
"""Offline preflight only; never executes an artifact or authorizes a package feed."""
import hashlib
import importlib.util
import json
from pathlib import Path
import stat
import sys

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('release_table', ROOT / 'scripts/release-table.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


def verify(bundle, architecture, table=None, keys=None):
    # Explicit dependency injection for offline tests; CLI always uses repository pins.
    arch = {'x86_64': 'x86_64', 'aarch64': 'arm64'}.get(architecture)
    if arch is None:
        raise ValueError('unsupported architecture')
    table = table or ROOT / 'packages/letkite-agent/files/release'
    text = Path(table).read_text()
    import re
    match = re.search(r'^AGENT_VERSION=(\d+\.\d+\.\d+)$', text, re.M)
    if not match:
        raise ValueError('missing pinned version')
    version = match[1]
    if tuple(map(int, version.split('.'))) <= (1, 9, 1):
        raise ValueError('claim-incompatible agent; manual pairing required')
    # Reuse the existing signature verifier and table renderer without network or
    # environment-controlled trust roots. Only expected release metadata is read.
    old_fetch, old_keys = release.fetch, release.KEYS
    def local_fetch(url, limit=1 << 20):
        name = url.rsplit('/', 1)[-1]
        if name not in ('release.json', 'release.json.sig', 'SHA256SUMS'):
            raise ValueError('unexpected metadata request')
        data = (Path(bundle) / name).read_bytes()
        if len(data) > limit:
            raise ValueError('oversize metadata')
        return data
    release.fetch = local_fetch
    release.KEYS = str(keys or ROOT / 'keys/agent-release-keys.txt')
    try:
        _, rows = release.table_for(version)
    finally:
        release.fetch, release.KEYS = old_fetch, old_keys
    if text != release.render(version, rows):
        raise ValueError('table differs from signed release')
    filename, sha, size = rows[arch]
    program = Path(bundle) / filename
    if program.is_symlink() or not program.is_file():
        raise ValueError('missing regular binary')
    if stat.S_IMODE(program.stat().st_mode) != 0o755:
        raise ValueError('binary permissions must be 0755')
    data = program.read_bytes()
    if len(data) != size or hashlib.sha256(data).hexdigest() != sha:
        raise ValueError('binary SHA-256 or size mismatch')
    return {'version': version, 'architecture': architecture, 'sha256': sha,
            'packages_authenticated': False, 'image_build_authorized': False}


if __name__ == '__main__':
    try:
        if len(sys.argv) != 3:
            raise ValueError('usage: verify-agent.py BUNDLE x86_64|aarch64')
        print(json.dumps(verify(sys.argv[1], sys.argv[2]), sort_keys=True))
    except (ValueError, OSError, release.Untrusted) as error:
        sys.exit(f'verify-agent: {error}')
