#!/usr/bin/env python3
"""Network-free signed artifact preflight tests; fixtures are never executed."""
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('verify', Path(__file__).resolve().parents[1] / 'scripts/verify-agent.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)


class Preflight(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.d = Path(self.tmp.name)
        key = self.d / 'private.pem'
        subprocess.run(['openssl', 'genpkey', '-algorithm', 'ed25519', '-out', str(key)], check=True, capture_output=True)
        public = subprocess.check_output(['openssl', 'pkey', '-in', str(key), '-pubout', '-outform', 'DER'])[-32:]
        self.keys = self.d / 'keys'
        self.keys.write_bytes(base64.b64encode(public))
        rows, artifacts = {}, {}
        for arch in ('x86_64', 'arm64', 'armv7'):
            name = 'letkite-agent-linux-' + arch
            data = ('test fixture ' + arch).encode()
            (self.d / name).write_bytes(data)
            (self.d / name).chmod(0o755)
            sha = hashlib.sha256(data).hexdigest()
            rows[arch] = (name, sha, len(data))
            artifacts['linux-' + arch] = dict(file=name, sha256=sha, size=len(data))
        manifest = json.dumps(dict(product='letkite-agent', version='2.0.0', artifacts=artifacts)).encode()
        (self.d / 'release.json').write_bytes(manifest)
        (self.d / 'msg').write_bytes(v.release.SIGNED_PREFIX + manifest)
        signature = subprocess.check_output(['openssl', 'pkeyutl', '-sign', '-inkey', str(key), '-rawin', '-in', str(self.d / 'msg')])
        (self.d / 'release.json.sig').write_bytes(base64.b64encode(signature))
        (self.d / 'SHA256SUMS').write_text(''.join(f'{sha}  {name}\n' for name, sha, _ in rows.values()))
        self.table = self.d / 'table'
        self.table.write_text(v.release.render('2.0.0', rows))
        self.binary = self.d / rows['x86_64'][0]

    def verify(self, arch='x86_64'):
        return v.verify(self.d, arch, self.table, self.keys)

    def test_happy(self):
        for arch in ('x86_64', 'aarch64'):
            self.assertFalse(self.verify(arch)['image_build_authorized'])
        # Diagnostics contain hashes and versions only, never fixture/key bytes.
        self.assertNotIn('test fixture', json.dumps(self.verify()))
        before = {p.name: p.read_bytes() for p in self.d.iterdir() if p.is_file()}
        self.verify()
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.d.iterdir() if p.is_file()})

    def test_wrong_sha(self):
        self.binary.write_bytes(b'tampered')
        with self.assertRaises(ValueError): self.verify()

    def test_wrong_arch(self):
        with self.assertRaises(ValueError): self.verify('mips')
        self.binary.write_bytes((self.d / 'letkite-agent-linux-arm64').read_bytes())
        with self.assertRaises(ValueError): self.verify()

    def test_missing_binary(self):
        self.binary.unlink()
        with self.assertRaises(ValueError): self.verify()

    def test_permissions(self):
        self.binary.chmod(0o777)
        with self.assertRaises(ValueError): self.verify()

    def test_old_claim(self):
        self.table.write_text(self.table.read_text().replace('2.0.0', '1.6.1'))
        with self.assertRaisesRegex(ValueError, 'claim-incompatible'): self.verify()

    def test_unsigned(self):
        (self.d / 'release.json.sig').write_text(base64.b64encode(bytes(64)).decode())
        with self.assertRaises(v.release.Untrusted): self.verify()

    def test_missing_metadata(self):
        (self.d / 'release.json').unlink()
        with self.assertRaises(OSError): self.verify()


if __name__ == '__main__':
    unittest.main()
