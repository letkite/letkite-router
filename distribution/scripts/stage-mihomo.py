#!/usr/bin/env python3
"""Pinned provider and explicit target adapter. Never executes downloaded code."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'addons/mihomo/manifest.json'


def select(target):
    manifest = json.loads(MANIFEST.read_text())
    item = manifest['targets'][target]
    expected = f"mihomo-linux-{'amd64-v1' if target == 'x86-full' else 'arm64'}-{manifest['version']}.gz"
    if item['asset'] != expected or not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', manifest['version']):
        raise ValueError('invalid provider asset path')
    if not re.fullmatch(r'[0-9a-f]{64}', item['sha256']):
        raise ValueError('missing SHA256 pin')
    return manifest, item


def verify(archive, output, item):
    """Local verification primitive; fixtures use this without any network path."""
    with archive.open('rb') as source:
        if hashlib.file_digest(source, 'sha256').hexdigest() != item['sha256']:
            raise ValueError('compressed SHA256 mismatch')
    try:
        with gzip.open(archive, 'rb') as source, output.open('xb') as dest:
            count = 0
            while chunk := source.read(1024 * 1024):
                count += len(chunk)
                if count > item['max_installed_bytes']:
                    raise ValueError('installed size exceeds target limit')
                dest.write(chunk)
        with output.open('rb') as source:
            header = source.read(64)
        if len(header) < 64 or header[:4] != b'\x7fELF' or header[4] != item['elf_class'] or header[5] != 1 or struct.unpack_from('<H', header, 18)[0] != item['elf_machine']:
            raise ValueError('wrong ELF architecture/class/endianness')
        output.chmod(0o755)
        return count
    except Exception:
        output.unlink(missing_ok=True)
        raise


def stage(target, overlay, budget):
    manifest, item = select(target)
    # Only accept a new, empty directory; never follow an overlay symlink.
    if overlay.is_symlink() or not overlay.is_dir() or any(overlay.iterdir()):
        raise ValueError('overlay must be an empty real directory')
    if target == 'ax3000t' and budget < 80:
        raise ValueError('AX3000T requires MIHOMO_STORAGE_BUDGET_MB >= 80 after base image/storage reservation')
    with tempfile.TemporaryDirectory(prefix='mihomo-download-') as work:
        archive = Path(work) / item['asset']
        url = f"https://github.com/MetaCubeX/mihomo/releases/download/{manifest['version']}/{item['asset']}"
        subprocess.run(['curl', '--proto', '=https', '--proto-redir', '=https', '-fsSL', '--retry', '3', '--max-time', '180', url, '-o', str(archive)], check=True)
        executable = Path(work) / 'mihomo'
        size = verify(archive, executable, item)
        if target == 'ax3000t' and size + 16*1024*1024 > budget*1024*1024:
            raise ValueError('binary plus 16 MiB reserve exceeds declared storage budget')
        shutil.copytree(ROOT / 'files', overlay, dirs_exist_ok=True)
        shutil.copytree(ROOT / 'addons/mihomo/files', overlay, dirs_exist_ok=True)
        dest = overlay / 'opt/letkite-router/mihomo/mihomo'
        dest.parent.mkdir(parents=True)
        shutil.copy2(executable, dest)
        print(f"Mihomo verified: {item['asset']} sha256={item['sha256']} installed_bytes={size}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--target', choices=['x86-full', 'ax3000t'], required=True)
    parser.add_argument('--overlay', type=Path)
    parser.add_argument('--storage-budget-mb', type=int, default=0)
    args = parser.parse_args()
    try:
        if args.overlay:
            stage(args.target, args.overlay, args.storage_budget_mb)
        else:
            print(json.dumps(select(args.target)[1], sort_keys=True))
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'mihomo: {error}\n')
