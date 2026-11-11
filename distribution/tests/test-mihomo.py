#!/usr/bin/env python3
"""Offline verification fixtures: no release downloads or executable invocation."""
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('mihomo', ROOT / 'scripts/stage-mihomo.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class MihomoTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.archive = self.root / 'fixture.gz'
        self.output = self.root / 'mihomo'
        self.item = dict(m.select('x86-full')[1])
        data = bytearray(64)
        data[:6] = b'\x7fELF\x02\x01'
        struct.pack_into('<H', data, 18, 62)
        self.archive.write_bytes(gzip.compress(data))
        self.item['sha256'] = hashlib.sha256(self.archive.read_bytes()).hexdigest()

    def test_verified_executable(self):
        self.assertEqual(m.verify(self.archive, self.output, self.item), 64)
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o755)

    def test_wrong_sha_missing_asset_and_architecture(self):
        bad = dict(self.item, sha256='0'*64)
        with self.assertRaises(ValueError):
            m.verify(self.archive, self.output, bad)
        self.assertFalse(self.output.exists())
        with self.assertRaises(FileNotFoundError):
            m.verify(self.root/'absent', self.output, self.item)
        for field, value in [('elf_machine', 183), ('elf_class', 1), ('max_installed_bytes', 1)]:
            with self.assertRaises(ValueError):
                m.verify(self.archive, self.output, dict(self.item, **{field: value}))
            self.assertFalse(self.output.exists())

    def test_path_traversal_rejected_before_network(self):
        manifest = json.loads(m.MANIFEST.read_text())
        for asset in ['../../escape.gz', '/tmp/escape.gz', 'https://evil/asset.gz']:
            manifest['targets']['x86-full']['asset'] = asset
            with patch.object(Path, 'read_text', return_value=json.dumps(manifest)), patch.object(m.subprocess, 'run') as network:
                with self.assertRaises(ValueError):
                    m.select('x86-full')
                network.assert_not_called()

    def test_overlay_and_storage_guards_before_network(self):
        overlay = self.root/'overlay'
        overlay.mkdir()
        with patch.object(m.subprocess, 'run') as network:
            with self.assertRaises(ValueError):
                m.stage('ax3000t', overlay, 0)
            (overlay/'existing').touch()
            with self.assertRaises(ValueError):
                m.stage('x86-full', overlay, 0)
            link = self.root/'linked-overlay'
            link.symlink_to(overlay, target_is_directory=True)
            with self.assertRaises(ValueError):
                m.stage('x86-full', link, 0)
            network.assert_not_called()

    def test_unavailable_release_fails_without_staging(self):
        overlay = self.root/'overlay'
        overlay.mkdir()
        with patch.object(m.subprocess, 'run', side_effect=subprocess.CalledProcessError(22, 'curl')):
            with self.assertRaises(subprocess.CalledProcessError):
                m.stage('x86-full', overlay, 0)
        self.assertEqual(list(overlay.iterdir()), [])

    def test_stage_preserves_defaults_and_executable(self):
        overlay = self.root/'overlay'
        overlay.mkdir()
        manifest, item = m.select('x86-full')
        item = dict(item, sha256=self.item['sha256'])
        def local_download(args, **kwargs):
            Path(args[-1]).write_bytes(self.archive.read_bytes())
        with patch.object(m, 'select', return_value=(manifest,item)), patch.object(m.subprocess, 'run', side_effect=local_download) as download:
            m.stage('x86-full', overlay, 0)
        self.assertEqual(download.call_count, 1)
        self.assertEqual((overlay/'etc/uci-defaults/95-letkite-os').read_bytes(), (ROOT/'files/etc/uci-defaults/95-letkite-os').read_bytes())
        for name in ['opt/letkite-router/mihomo/mihomo','etc/init.d/mihomo','etc/uci-defaults/96-letkite-mihomo']:
            self.assertTrue((overlay/name).stat().st_mode & 0o111)
        self.assertFalse((overlay/'etc/mihomo/config.yaml').exists())

    def test_service_disabled_without_operator_config(self):
        service = ROOT / 'addons/mihomo/files/etc/init.d/mihomo'
        script = 'config_load() { :; }; config_get_bool() { eval "$1=$4"; }; . "$1"; start_service'
        subprocess.run(['sh', '-c', script, 'fixture', str(service)], check=True)
        defaults = (ROOT/'addons/mihomo/files/etc/uci-defaults/96-letkite-mihomo').read_text()
        self.assertIn('/etc/init.d/mihomo disable', defaults)
        self.assertIn('/etc/init.d/mihomo stop', defaults)

    def test_offline_dry_runs_and_default(self):
        poison = self.root/'bin'
        poison.mkdir()
        for name in ['curl', 'make']:
            p = poison/name
            p.write_text('#!/bin/sh\necho NETWORK-LEAK >&2\nexit 99\n')
            p.chmod(0o755)
        import os
        env = dict(os.environ, PATH=str(poison)+':'+os.environ['PATH'])
        env.pop('ENABLE_MIHOMO', None)
        command = ['bash', str(ROOT/'scripts/build-image.sh'), '--profile','x86-full','--dry-run']
        default = subprocess.check_output(command, env=env)
        self.assertEqual(default, subprocess.check_output(command, env=dict(env,ENABLE_MIHOMO='0')))
        self.assertNotIn(b'mihomo',default)
        for proxy, flavor in [('0','base-mihomo'),('1','proxy-mihomo')]:
            output = subprocess.check_output(command, env=dict(env,ENABLE_MIHOMO='1',ENABLE_PROXY=proxy))
            self.assertIn(flavor.encode(),output)
            self.assertNotIn(b'NETWORK-LEAK',output)
        result = subprocess.run(command, env=dict(env,ENABLE_MIHOMO='bad'),capture_output=True)
        self.assertNotEqual(result.returncode,0)


if __name__ == '__main__':
    unittest.main()
