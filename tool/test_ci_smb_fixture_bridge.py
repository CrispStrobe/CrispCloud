"""Pure admission controls; synthetic headers never claim native execution."""
import hashlib
from pathlib import Path
import tempfile
import unittest

from ci_smb_fixture_bridge import bridge_receipt


class SmbFixtureAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def library(self, parent=None):
        header = bytearray(64)
        header[:6] = b'\x7fELF\x02\x01'
        header[16:18] = (3).to_bytes(2, 'little')
        header[18:20] = (62).to_bytes(2, 'little')
        path = (parent or self.root) / 'libcrisp_smb_bridge.so'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(header)
        return path

    def test_exact_existing_asset_records_digest_without_mutating_bytes(self):
        path = self.library()
        before = path.read_bytes()
        receipt = bridge_receipt(self.root)
        self.assertEqual(receipt['bytes'], len(before))
        self.assertEqual(receipt['sha256'], hashlib.sha256(before).hexdigest())
        self.assertFalse(receipt['new_build_performed'])
        self.assertEqual(path.read_bytes(), before)

    def test_missing_or_ambiguous_assets_fail(self):
        with self.assertRaisesRegex(ValueError, 'found 0'):
            bridge_receipt(self.root)
        self.library(self.root / 'one')
        self.library(self.root / 'two')
        with self.assertRaisesRegex(ValueError, 'found 2'):
            bridge_receipt(self.root)

    def test_symlinked_asset_fails(self):
        path = self.library(self.root / 'actual')
        bundle = self.root / 'bundle'
        bundle.mkdir()
        (bundle / path.name).symlink_to(path)
        with self.assertRaisesRegex(ValueError, 'regular file'):
            bridge_receipt(bundle)

    def test_wrong_architecture_or_non_library_fails(self):
        path = self.library()
        original = path.read_bytes()
        for position, value in [(0, 0), (4, 1), (5, 2), (16, 2), (18, 183)]:
            changed = bytearray(original)
            changed[position] = value
            path.write_bytes(changed)
            with self.subTest(position=position), self.assertRaises(ValueError):
                bridge_receipt(self.root)
