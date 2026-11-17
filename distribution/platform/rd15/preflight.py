#!/usr/bin/env python3
"""Evaluate sanitized, offline evidence. No device commands or build authorization."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROFILE = json.loads((ROOT / 'profiles/be3600-rd15.json').read_text())


def evaluate(snapshot, *, vendor=None, enable_agent=False, components=()):
    errors = []
    for key, expected in PROFILE['expected'].items():
        if snapshot.get(key) != expected:
            errors.append('unexpected or missing ' + key)
    for key in PROFILE['recovery_required']:
        if snapshot.get('recovery', {}).get(key) is not True:
            errors.append('recovery missing: ' + key)
    sizes = snapshot.get('sizes', {})
    for key, limit in PROFILE['limits'].items():
        if key == 'agent_writable_bytes':
            continue
        size = sizes.get(key)
        if type(size) is not int or not 0 < size <= limit:
            errors.append('missing or oversize ' + key)
    if vendor is None or Path(vendor).is_symlink() or not Path(vendor).is_file():
        errors.append('verified local vendor blob required')
    else:
        digest = hashlib.sha256()
        with Path(vendor).open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(block)
        if digest.hexdigest() != PROFILE['vendor_sha256']:
            errors.append('unverified vendor blob')
    if enable_agent:
        # Snapshot claims and environment variables cannot qualify a provider.
        errors.append('signed claim-compatible agent provider not qualified')
        if type(snapshot.get('writable_bytes')) is not int or snapshot['writable_bytes'] < PROFILE['limits']['agent_writable_bytes']:
            errors.append('insufficient two-copy agent storage')
    for component in components:
        if component in PROFILE['prohibited']:
            errors.append('prohibited component: ' + component)
    return {'adapter': PROFILE['id'], 'backend': PROFILE['backend'],
            'evidence_complete': not errors, 'errors': errors,
            'image_build_authorized': False, 'flash_authorized': False,
            'agent_integration_authorized': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot', type=Path)
    parser.add_argument('--vendor', type=Path)
    parser.add_argument('--enable-agent', action='store_true')
    parser.add_argument('--component', action='append', default=[])
    args = parser.parse_args()
    try:
        result = evaluate(json.loads(args.snapshot.read_text()), vendor=args.vendor,
                          enable_agent=args.enable_agent, components=args.component)
        print(json.dumps(result, indent=2))
        raise SystemExit(0 if result['evidence_complete'] else 1)
    except (OSError, ValueError, TypeError, AttributeError) as error:
        parser.exit(1, 'rd15 preflight refused: ' + str(error) + '\n')
