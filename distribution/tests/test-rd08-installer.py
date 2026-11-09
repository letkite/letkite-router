#!/usr/bin/env python3
"""Offline fixtures only; no router access or execution of supplied artifacts."""
import hashlib
import importlib.util
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('rd08', HERE / 'installers/rd08/rd08.py')
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)
SCRIPT = HERE / 'installers/rd08/router.sh'


class Installer(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.snapshot = self.root / 'snapshot'
        values = ["DISTRIB_ID='OpenWrt'\nDISTRIB_RELEASE='18.06-SNAPSHOT'\nDISTRIB_TARGET='ipq53xx/generic'\nDISTRIB_ARCH='aarch64_cortex-a53_neon-vfpv4'\n",
                  "config core 'version'\n option ROM '1.1.123'\n option HARDWARE 'RD08'\n",
                  '5.4.213\n', 'Hardware: Qualcomm IPQ5332\n', 'xiaomi,rd08\n']
        for name, value in zip(m.FIELDS, values):
            p = self.snapshot / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(value)
        data = bytearray(64)
        data[:7] = b'\x7fELF\x02\x01\x01'
        struct.pack_into('<HHI', data, 16, 2, 183, 1)
        struct.pack_into('<H', data, 52, 64)
        self.agent = self.root / 'agent'
        self.agent.write_bytes(data)
        self.sha = hashlib.sha256(data).hexdigest()
        self.bundle = self.root / 'bundle'

    def prepare(self, **kw):
        return m.prepare(self.snapshot, self.agent, self.sha, self.bundle, **kw)

    def shell(self, *args, script=SCRIPT):
        return subprocess.run(['sh', str(script), *map(str, args)], capture_output=True, text=True)

    def test_good_and_researched_versions(self):
        for version in ('1.1.96', '1.1.123'):
            (self.snapshot / m.FIELDS[1]).write_text(f" option ROM '{version}'\n option HARDWARE 'RD08'\n")
            self.assertEqual(m.inspect(self.snapshot)['rom'], version)
        self.prepare()
        result = self.shell('--check', self.bundle, '--snapshot', self.snapshot)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_false_rd08_and_wrong_kernel(self):
        for name, value in [(m.FIELDS[3], 'Hardware: IPQ8072 RD08'),
                            (m.FIELDS[2], '6.6.1'), (m.FIELDS[4], 'generic,rd08'),
                            (m.FIELDS[1], " option ROM '1.0.46'\n option HARDWARE 'RD08'\n")]:
            with self.subTest(name=name):
                p = self.snapshot / name; old = p.read_text(); p.write_text(value)
                with self.assertRaises(ValueError): self.prepare()
                p.write_text(old)

    def test_shell_wrong_fingerprints_and_optional_mihomo(self):
        manifest = self.prepare(mihomo=self.agent, mihomo_sha=self.sha)
        self.assertFalse(manifest['mihomo_enabled'])
        for name, value in [(m.FIELDS[2], '5.4.214'),
                            (m.FIELDS[3], 'RD08 IPQ53320'),
                            (m.FIELDS[4], 'RD08-lookalike'),
                            (m.FIELDS[0], "DISTRIB_ID='OpenWrt'\n")]:
            p = self.snapshot / name; old = p.read_text(); p.write_text(value)
            result = self.shell('--check', self.bundle, '--snapshot', self.snapshot)
            self.assertNotEqual(result.returncode, 0, name)
            p.write_text(old)
        result = self.shell('--check', self.bundle, '--snapshot', self.snapshot)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_hash_architecture_symlink(self):
        with self.assertRaises(ValueError): m.binary(self.agent, '0' * 64)
        data = bytearray(self.agent.read_bytes()); data[18] = 62
        self.agent.write_bytes(data)
        with self.assertRaises(ValueError): m.binary(self.agent, hashlib.sha256(data).hexdigest())
        link = self.root / 'link'; link.symlink_to(self.agent)
        with self.assertRaises(ValueError): m.binary(link, self.sha)
        p = self.snapshot / m.FIELDS[4]; p.unlink(); p.symlink_to(self.agent)
        with self.assertRaises(ValueError): m.inspect(self.snapshot)

    def inventory(self):
        return sorted((str(p.relative_to(self.root)), p.lstat().st_mode,
                       p.read_bytes() if p.is_file() else b'') for p in self.root.rglob('*'))

    def test_dry_run_no_writes(self):
        before = self.inventory(); self.prepare(dry_run=True)
        self.assertEqual(before, self.inventory())
        self.prepare(); before = self.inventory()
        result = self.shell('--dry-run', self.bundle, '--snapshot', self.snapshot)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, self.inventory())
        with self.assertRaises(ValueError): self.prepare()

    def test_shell_rejects_tamper_symlink_traversal(self):
        self.prepare()
        checksum = self.bundle / 'SHA256SUMS'; original = checksum.read_text()
        for bad in [original.replace('letkite-agent', '../agent'), original + original,
                    original.replace(self.sha, '0' * 64)]:
            checksum.write_text(bad)
            self.assertNotEqual(self.shell('--check', self.bundle, '--snapshot', self.snapshot).returncode, 0)
        checksum.write_text(original)
        (self.bundle / 'secret').symlink_to(self.agent)
        self.assertNotEqual(self.shell('--check', self.bundle, '--snapshot', self.snapshot).returncode, 0)

    def test_apply_idempotency_backup_rollback(self):
        # Test-only rewritten script. Production CLI has no writable fixture-root option.
        script = self.root / 'fixture.sh'
        base = self.root / 'storage'
        source = SCRIPT.read_text().replace('ROOT=/\n', f'ROOT={self.snapshot}\n').replace(
            'BASE=/data/letkite-rd08', f'BASE={base}')
        source = source.replace('[ "$(id -u)" = 0 ]', 'true')
        source = source.replace('[ -d /data ]', 'true')
        source = source.replace("awk '$2 == \"/data\" && $4 ~ /(^|,)rw(,|$)/ {ok=1} END {exit !ok}' /proc/mounts", 'true')
        script.write_text(source)
        self.prepare()
        for _ in range(2):
            r = self.shell('--apply', self.bundle, script=script)
            self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse((base / 'previous').exists())
        old = (base / 'current/letkite-agent').read_bytes()
        self.agent.write_bytes(old + b'new')
        self.sha = hashlib.sha256(self.agent.read_bytes()).hexdigest()
        self.bundle = self.root / 'bundle2'; self.prepare()
        r = self.shell('--apply', self.bundle, script=script)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((base / 'previous/letkite-agent').read_bytes(), old)
        r = self.shell('--rollback', script=script)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((base / 'current/letkite-agent').read_bytes(), old)
        r = self.shell('--apply', self.bundle, '--snapshot', self.snapshot)
        self.assertNotEqual(r.returncode, 0)


if __name__ == '__main__':
    unittest.main()
