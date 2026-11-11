#!/usr/bin/env python3
"""Offline RD08 snapshot inspector and deterministic local bundle preparer. No network."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import struct
import sys

MAX = 128 * 1024 * 1024
FIELDS = ('etc/openwrt_release', 'usr/share/xiaoqiang/xiaoqiang_version',
          'proc/sys/kernel/osrelease', 'proc/cpuinfo', 'tmp/sysinfo/board_name')


def regular(path, limit=MAX):
    path = Path(os.path.abspath(path))
    for part in (path, *path.parents):
        if part.is_symlink():
            raise ValueError('symlink refused: ' + str(part))
    if not stat.S_ISREG(path.stat().st_mode) or path.stat().st_size > limit:
        raise ValueError('not a bounded regular file: ' + str(path))
    data = path.read_bytes()
    if len(data) > limit:
        raise ValueError('file grew beyond limit')
    return data


def inspect(root):
    files = {name: regular(Path(root) / name, 262144) for name in FIELDS}
    text = {name: raw.decode('utf-8') for name, raw in files.items()}
    release = text[FIELDS[0]]
    for key, value in {'DISTRIB_ID': 'OpenWrt', 'DISTRIB_RELEASE': '18.06-SNAPSHOT',
                       'DISTRIB_TARGET': 'ipq53xx/generic',
                       'DISTRIB_ARCH': 'aarch64_cortex-a53_neon-vfpv4'}.items():
        if re.findall(r'^' + key + r"='([^'\n]*)'$", release, re.M) != [value]:
            raise ValueError('OEM release fingerprint mismatch: ' + key)
    version = text[FIELDS[1]]
    def option(key):
        values = re.findall(r"^\s*option " + key + r" '([^'\n]*)'\s*$", version, re.M)
        if len(values) != 1:
            raise ValueError('ambiguous OEM option: ' + key)
        return values[0]
    rom = option('ROM')
    if rom not in ('1.1.96', '1.1.123') or option('HARDWARE') != 'RD08':
        raise ValueError('unknown OEM hardware/version')
    if text[FIELDS[2]].strip() != '5.4.213':
        raise ValueError('wrong OEM kernel')
    if not re.search(r'\bIPQ5332\b', text[FIELDS[3]], re.I):
        raise ValueError('missing IPQ5332 fingerprint')
    if text[FIELDS[4]].strip() not in ('RD08', 'xiaomi,rd08'):
        raise ValueError('unverified board fingerprint')
    return {'hardware': 'RD08', 'soc': 'IPQ5332', 'rom': rom, 'kernel': '5.4.213',
            'snapshot_hashes': {n: hashlib.sha256(d).hexdigest() for n, d in files.items()},
            'activation': 'manual', 'abi_verified': False, 'unattended_claim': False}


def binary(path, expected):
    if not re.fullmatch('[0-9a-fA-F]{64}', expected):
        raise ValueError('expected SHA256 must be 64 hex characters')
    data = regular(path)
    if hashlib.sha256(data).hexdigest() != expected.lower():
        raise ValueError('SHA256 mismatch')
    # ELF64 little-endian, current version, executable or PIE, AArch64, valid header.
    if (len(data) < 64 or data[:7] != b'\x7fELF\x02\x01\x01'
            or struct.unpack_from('<HHI', data, 16) not in ((2, 183, 1), (3, 183, 1))
            or struct.unpack_from('<H', data, 52)[0] != 64):
        raise ValueError('expected an ARM64 ELF executable (ABI still unverified)')
    return data


def prepare(root, agent, sha, output, dry_run=False, mihomo=None, mihomo_sha=None):
    facts = inspect(root)
    payload = {'letkite-agent': binary(agent, sha)}
    if bool(mihomo) != bool(mihomo_sha):
        raise ValueError('Mihomo needs both local binary and expected SHA256')
    if mihomo:
        payload['mihomo'] = binary(mihomo, mihomo_sha)
    manifest = {'schema': 1, 'platform': facts, 'mihomo_enabled': False,
                'files': {n: {'sha256': hashlib.sha256(d).hexdigest(), 'size': len(d)}
                          for n, d in payload.items()}}
    payload['manifest.json'] = (json.dumps(manifest, sort_keys=True, indent=2) + '\n').encode()
    payload['SHA256SUMS'] = ''.join(f'{hashlib.sha256(d).hexdigest()}  {n}\n' for n, d in sorted(payload.items())).encode()
    payload['SIZES'] = ''.join(f'{len(d)} {n}\n' for n, d in sorted(payload.items()) if n != 'SHA256SUMS').encode()
    # Output is a new directory only. Never merge into an existing tree.
    dest = Path(os.path.abspath(output))
    for part in (dest, *dest.parents):
        if part.is_symlink():
            raise ValueError('symlink output refused')
    if dest.exists():
        raise ValueError('output already exists')
    if not dest.parent.is_dir():
        raise ValueError('output parent must exist')
    if not dry_run:
        dest.mkdir(mode=0o700)
        for name, data in payload.items():
            with (dest / name).open('xb') as stream:
                stream.write(data)
            (dest / name).chmod(0o700 if name in ('letkite-agent', 'mihomo') else 0o600)
    return manifest


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='command', required=True)
    i = sub.add_parser('inspect'); i.add_argument('--snapshot', required=True)
    b = sub.add_parser('prepare'); b.add_argument('--snapshot', required=True)
    b.add_argument('--agent', required=True); b.add_argument('--sha256', required=True)
    b.add_argument('--output', required=True); b.add_argument('--dry-run', action='store_true')
    b.add_argument('--mihomo'); b.add_argument('--mihomo-sha256')
    a = p.parse_args()
    try:
        result = inspect(a.snapshot) if a.command == 'inspect' else prepare(
            a.snapshot, a.agent, a.sha256, a.output, a.dry_run, a.mihomo, a.mihomo_sha256)
        print(json.dumps(result, indent=2, sort_keys=True))
    except (OSError, ValueError, UnicodeError) as e:
        p.exit(1, f'rd08: {e}\n')


if __name__ == '__main__':
    main()
