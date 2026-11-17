#!/usr/bin/env python3
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('rd15', ROOT / 'platform/rd15/preflight.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class RD15Tests(unittest.TestCase):
    def setUp(self):
        self.s = copy.deepcopy(m.PROFILE['expected'])
        self.s['recovery'] = dict.fromkeys(m.PROFILE['recovery_required'], True)
        self.s['sizes'] = {k: v for k, v in m.PROFILE['limits'].items() if k != 'agent_writable_bytes'}

    def errors(self, **kwargs):
        return m.evaluate(self.s, **kwargs)['errors']

    def test_board_and_hardware(self):
        for board in ('RD16', 'RD08'):
            self.s['model'] = board
            self.assertIn('unexpected or missing model', self.errors())
        self.setUp()
        for key in ('nand', 'mdio', 'slots'):
            original = self.s[key]
            self.s[key] = {}
            self.assertIn('unexpected or missing ' + key, self.errors())
            self.s[key] = original

    def test_sizes_and_recovery(self):
        self.s['sizes']['filesystem_bytes'] += 1
        self.assertIn('missing or oversize filesystem_bytes', self.errors())
        for key in m.PROFILE['recovery_required']:
            self.s['recovery'][key] = False
            self.assertIn('recovery missing: ' + key, self.errors())

    def test_unverified_vendor_and_agent(self):
        with tempfile.TemporaryDirectory() as tmp:
            vendor = Path(tmp) / 'vendor.bin'
            vendor.write_bytes(b'not verified')
            self.assertIn('unverified vendor blob', self.errors(vendor=vendor))
        self.s['agent_provider_qualified'] = True
        self.assertTrue(any('not qualified' in x for x in self.errors(enable_agent=True)))
        result = m.evaluate(self.s, components=['mihomo', 'docker'])
        self.assertEqual(sum('prohibited component' in x for x in result['errors']), 2)
        self.assertFalse(result['flash_authorized'])
        self.assertFalse(result['image_build_authorized'])

    def test_no_embedded_credentials_or_device_dumps(self):
        paths = [ROOT / 'profiles/be3600-rd15.json',
                 ROOT / 'platform/snapshots/rd15-reference.json',
                 ROOT / 'platform/rd15/source-lock.json']
        forbidden = ('BEGIN ' + 'PRIVATE KEY', 'BEGIN OPENSSH ' + 'PRIVATE KEY',
                     'ssh-' + 'ed25519 ', 'password' + '=', 'token' + '=')
        for path in paths:
            data = path.read_text()
            for value in forbidden:
                self.assertNotIn(value, data)
        snapshot = json.loads(paths[1].read_text())
        self.assertEqual(set(snapshot), set(m.PROFILE['expected']) |
                         {'provenance', 'recovery', 'sizes'})

    def test_snapshot_is_offline_and_incomplete(self):
        path = ROOT / 'platform/snapshots/rd15-reference.json'
        before = path.read_bytes()
        result = m.evaluate(json.loads(before))
        self.assertFalse(result['evidence_complete'])
        self.assertEqual(path.read_bytes(), before)
        self.assertFalse(m.PROFILE['official_imagebuilder_allowed'])


if __name__ == '__main__':
    unittest.main()
