#!/usr/bin/env python3
"""Offline synthetic fixture tests; no router, network or package dependencies."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

PLATFORM = Path(__file__).resolve().parents[1] / 'platform'
spec = importlib.util.spec_from_file_location('platform_detect', PLATFORM / 'detect.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
FIXTURES = json.loads((PLATFORM / 'fixtures.json').read_text())


class DetectionTests(unittest.TestCase):
    def fixture(self, files):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        for name, value in files.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(value)
        return root

    def test_examples_and_no_mutation(self):
        for name, files in FIXTURES.items():
            with self.subTest(name=name):
                root = self.fixture(files)
                before = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob('*') if p.is_file()}
                result = module.detect(root, commands=True)
                expected = 'agent-only' if name.startswith('openwrt-') else 'research-only'
                self.assertEqual(result['classification'], expected)
                self.assertFalse(result['capabilities']['flash_authorized'])
                self.assertFalse(result['capabilities']['full_firmware_imagebuilder'])
                self.assertIsNone(result['facts']['machine'])
                self.assertEqual(before, {str(p.relative_to(root)): p.read_bytes() for p in root.rglob('*') if p.is_file()})
                if name == 'rd08-oem-opkg':
                    self.assertEqual(result['adapter']['id'], 'qsdk')
                    self.assertTrue(result['facts']['rd08_oem_signature'])
                    self.assertEqual(len(result['facts']['partitions']), 2)
                if 'immortalwrt' in name:
                    self.assertEqual(result['adapter']['id'], 'immortalwrt')

    def test_rd08_requires_combined_evidence(self):
        for key in ('proc/cpuinfo', 'proc/sys/kernel/osrelease', 'etc/board.json'):
            files = dict(FIXTURES['rd08-oem-opkg'])
            del files[key]
            result = module.detect(self.fixture(files))
            self.assertFalse(result['facts']['rd08_oem_signature'])
            self.assertEqual(result['classification'], 'research-only')

    def test_missing_corrupt_and_symlinks(self):
        self.assertEqual(module.detect(self.fixture({}))['classification'], 'research-only')
        for content in ('[]', '{bad', '[' * 2000):
            files = dict(FIXTURES['openwrt-x86-apk'], **{'etc/board.json': content})
            self.assertEqual(module.detect(self.fixture(files))['classification'], 'research-only')
        root = self.fixture(FIXTURES['openwrt-x86-apk'])
        (root / 'etc/board.json').unlink()
        (root / 'etc/board.json').symlink_to('/etc/passwd')
        self.assertTrue(module.detect(root)['warnings'])
        (root / 'proc/cpuinfo').write_bytes(b'\xff\0')
        self.assertEqual(module.detect(root)['classification'], 'research-only')
        (root / 'proc/cpuinfo').write_text('x' * (module.LIMIT + 1))
        self.assertTrue(module.detect(root)['warnings'])

    def test_conflicts_and_shell_content(self):
        for extra in ({'etc/opkg/distfeeds.conf': 'src/gz test'},
                      {'etc/openwrt_release': "DISTRIB_ARCH=$(touch /tmp/never-execute)\n"},
                      {'etc/os-release': 'ID=immortalwrt\n'},
                      {'etc/openwrt_release': "DISTRIB_ID='OpenWrt'\nDISTRIB_RELEASE='25.12.6'\nDISTRIB_ARCH='mips_24kc'\n"}):
            result = module.detect(self.fixture(dict(FIXTURES['openwrt-x86-apk'], **extra)))
            self.assertEqual(result['classification'], 'research-only')

    def test_registry_and_policy_contract(self):
        registry = json.loads((PLATFORM / 'adapters.json').read_text())
        required = {'id', 'family', 'packaging_backends', 'builder_availability', 'package_trust_requirements', 'flash_safety_status', 'bsp_dependency', 'minimum_resources', 'integration_tier'}
        for adapter in registry['adapters']:
            self.assertTrue(required <= adapter.keys())
        policy = json.loads((PLATFORM / 'policy.json').read_text())
        self.assertFalse(policy['tiers']['full-firmware-imagebuilder']['enabled'])
        self.assertFalse(policy['tiers']['vendor-bsp-source-build']['enabled'])

    def test_uname_unavailable_and_version_conflict(self):
        with mock.patch.object(module.os, 'uname', side_effect=OSError('unavailable')), mock.patch.object(Path, 'lstat', side_effect=FileNotFoundError):
            result = module.detect('/', commands=True)
            self.assertIn('uname unavailable', result['warnings'])
            self.assertFalse(result['capabilities']['flash_authorized'])
        files = dict(FIXTURES['openwrt-x86-apk'])
        files['etc/os-release'] = 'ID=openwrt\nVERSION_ID=24.10.0\n'
        self.assertEqual(module.detect(self.fixture(files))['classification'], 'research-only')
        root = self.fixture(FIXTURES['openwrt-x86-apk'])
        link = root / 'linked-root'
        link.symlink_to(root, target_is_directory=True)
        self.assertEqual(module.detect(link)['classification'], 'research-only')

    def test_json_cli(self):
        root = self.fixture(FIXTURES['openwrt-x86-apk'])
        output = subprocess.check_output([sys.executable, '-B', str(PLATFORM / 'detect.py'), '--root', str(root)])
        self.assertEqual(json.loads(output)['facts']['package_backend'], 'apk')


if __name__ == '__main__':
    unittest.main()
