#!/usr/bin/env python3
"""Read-only pinned source audit; emits a preparation receipt, never builds images."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

lock = json.loads((Path(__file__).resolve().parents[1] / 'platform/rd15/source-lock.json').read_text())
try:
    root = Path(sys.argv[1]).resolve()
    head = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    if head != lock['reference_commit']:
        raise ValueError('reference commit mismatch')
    for name, digest in lock['files'].items():
        path = root / name
        if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError('source mismatch: ' + name)
    if subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain'], text=True).strip():
        raise ValueError('reference tree must be clean, including untracked files')
    print(json.dumps({'source_audit': 'passed', **lock, 'build_executed': False,
                      'vendor_staged': False, 'image_build_authorized': False}, indent=2))
except (IndexError, OSError, ValueError, subprocess.CalledProcessError) as error:
    sys.exit('source preparation refused: ' + str(error))
