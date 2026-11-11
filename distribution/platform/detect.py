#!/usr/bin/env python3
"""Read-only inventory. Fixture data is never sourced or executed; no writes/network."""
import argparse
import json
import os
from pathlib import Path
import re
import stat

HERE = Path(__file__).resolve().parent
LIMIT = 262144


def detect(root, commands=False):
    root = Path(root).absolute()
    warnings = []
    policy = json.loads((HERE / 'policy.json').read_text())

    def read(name):
        # Reject every symlink component, including links that stay inside root.
        path = root
        try:
            if any(parent.is_symlink() for parent in (root, *root.parents)):
                raise ValueError('symlink fixture root refused')
            for part in Path(name).parts:
                path = path / part
                if stat.S_ISLNK(path.lstat().st_mode):
                    raise ValueError('symlink refused')
            if not stat.S_ISREG(path.stat().st_mode):
                raise ValueError('not a regular file')
            with path.open('rb') as stream:
                raw = stream.read(LIMIT + 1)
            if len(raw) > LIMIT or b'\0' in raw:
                raise ValueError('oversize or NUL content')
            return raw.decode('utf-8', errors='strict')
        except FileNotFoundError:
            return ''
        except (OSError, ValueError, UnicodeError) as error:
            warnings.append(name + ': ' + str(error))
            return ''

    def env(text):
        result = {}
        for line in text.splitlines():
            match = re.fullmatch(r'([A-Z_][A-Z_0-9]*)=(?:"([^"\n]*)"|\x27([^\x27\n]*)\x27|([A-Za-z0-9_./+-]+))', line)
            if match:
                result[match[1]] = next(v for v in match.groups()[1:] if v is not None)
            elif line.strip() and not line.startswith('#'):
                warnings.append('ignored malformed release assignment')
        return result

    release = env(read('etc/openwrt_release'))
    osrelease = env(read('etc/os-release'))
    cpu = read('proc/cpuinfo')
    kernel = read('proc/sys/kernel/osrelease').strip()
    machine = None
    if commands and root == Path('/'):
        # os.uname is optional; never shell out to fixture-provided executables.
        try:
            uname = os.uname()
            kernel = kernel or uname.release
            machine = uname.machine
        except (AttributeError, OSError):
            warnings.append('uname unavailable')
    board = {}
    raw_board = read('etc/board.json')
    try:
        board = json.loads(raw_board) if raw_board else {}
        if not isinstance(board, dict):
            raise ValueError('expected object')
    except (ValueError, RecursionError):
        warnings.append('invalid board.json')
        board = {}
    model = board.get('model', {})
    model = model if isinstance(model, dict) else {}
    compatible = model.get('id') if isinstance(model.get('id'), str) else None
    mtd = read('proc/mtd')
    partitions = []
    for line in mtd.splitlines():
        match = re.fullmatch(r'mtd(\d+):\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+"([^"\n]+)"', line)
        if match:
            partitions.append(dict(index=int(match[1]), size=int(match[2], 16), erase_size=int(match[3], 16), name=match[4]))
        elif line.strip() and line.strip() != 'dev:    size   erasesize  name':
            warnings.append('unparsed MTD line')
    mounts = read('proc/mounts').splitlines()
    apk = bool(read('lib/apk/db/installed') or read('etc/apk/repositories') or read('etc/apk/repositories.d/distfeeds.list'))
    opkg = bool(read('usr/lib/opkg/status') or read('etc/opkg/distfeeds.conf'))
    backend = 'conflict' if apk and opkg else 'apk' if apk else 'opkg' if opkg else 'unknown'
    identity = osrelease.get('ID', '').lower()
    dist = release.get('DISTRIB_ID', '').lower()
    version = release.get('DISTRIB_RELEASE') or osrelease.get('VERSION_ID')
    if release.get('DISTRIB_RELEASE') and osrelease.get('VERSION_ID') and release['DISTRIB_RELEASE'] != osrelease['VERSION_ID']:
        warnings.append('release version metadata conflict')
    arch = release.get('DISTRIB_ARCH')
    target = release.get('DISTRIB_TARGET')
    family = 'openwrt' if dist == identity == 'openwrt' else 'immortalwrt' if dist == identity == 'immortalwrt' else 'unknown'
    devices = json.loads((HERE / 'devices.json').read_text())['devices']
    device = next((d for d in devices if compatible in d['board_names']), None)
    rd08_match = bool(device and device['id'] == 'rd08' and version and version.startswith(device['release_prefix']) and kernel == device['kernel'] and re.search(device['soc_pattern'], cpu, re.I))
    if rd08_match:
        family = 'qsdk'
    adapter = next(a for a in json.loads((HERE / 'adapters.json').read_text())['adapters'] if a['id'] == family)
    arch_supported = arch == 'x86_64' or bool(arch and arch.startswith('aarch64_')) or bool(arch and arch.startswith('arm_') and re.search(r'\b(vfpv3|vfpv4)\b', cpu))
    expected = 'apk' if version and re.fullmatch(r'25\.12(?:\.\d+)?', version) else 'opkg' if version and re.fullmatch(r'24\.10(?:\.\d+)?', version) else None
    tier = 'agent-only' if family == 'openwrt' and backend == expected and arch_supported and not warnings else policy['default_classification']
    reasons = ['Local inventory cannot verify provenance, ABI, resources, exact board revision or partition safety.']
    if tier == 'agent-only':
        reasons.append('Known release/backend and CPU candidate; agent installation still requires signed packages, executable ABI and resource checks.')
    else:
        reasons.append('Unknown, inconsistent, vendor or fork evidence requires manual compatibility review.')
    if rd08_match:
        reasons.append('RD08 observed OEM signature: OpenWrt 18.06, IPQ5332, kernel 5.4.213; OEM build version and actual layout remain unverified. Generic ImageBuilder is unsuitable.')
    return {'schema_version': 1, 'adapter': adapter, 'classification': tier,
            'facts': {'release_family': family, 'release_version': version, 'os_id': identity,
                      'package_backend': backend, 'package_architecture': arch, 'target': target,
                      'machine': machine, 'abi': {'status': 'unverified', 'package_architecture': arch, 'libc': 'unknown', 'float_abi': 'unknown'},
                      'kernel_version': kernel or None, 'board_compatible': compatible,
                      'device_candidate': device, 'rd08_oem_signature': rd08_match,
                      'partitions': partitions, 'mounts': mounts, 'flash_layout_confidence': 'observed-unverified' if partitions or mounts else 'unknown'},
            'capabilities': {'agent_package_candidate': tier == 'agent-only', 'full_firmware_imagebuilder': policy['tiers']['full-firmware-imagebuilder']['enabled'],
                             'vendor_bsp_source_build': policy['tiers']['vendor-bsp-source-build']['enabled'], 'flash_authorized': False},
            'protected_partition_patterns': ['ART', 'WIFIFW', 'boot', 'calibration', 'factory'],
            'reasons': reasons, 'warnings': warnings,
            'next_steps': ['Verify firmware provenance, package signatures, architecture/libc ABI and available RAM/storage.',
                           'For firmware builds, review exact board revision, release, partition map, recovery and builder/BSP provenance independently.',
                           'Preserve ART, WIFIFW, boot and calibration; detection never authorizes partition writes.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default='/', help='injected filesystem root; no host command fallback')
    parser.add_argument('--allow-uname', action='store_true', help='allow os.uname only for live root /')
    args = parser.parse_args()
    print(json.dumps(detect(args.root, args.allow_uname), indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
