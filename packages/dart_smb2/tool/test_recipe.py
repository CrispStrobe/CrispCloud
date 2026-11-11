"""Verify the exact upstream recipe, allowing only the documented Crisp edits."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class RecipeTests(unittest.TestCase):
    def test_upstream_recipe_integrity(self):
        manifest = json.loads((ROOT / "UPSTREAM.json").read_text())
        for relative, expected in manifest["upstream_files"].items():
            with self.subTest(file=relative):
                data = (ROOT / "native" / relative).read_bytes()
                if relative in ("scripts/build_libsmb2_macos.sh", "scripts/build_libsmb2_ios.sh"):
                    self.assertEqual(data.count(b"-Wl,-headerpad_max_install_names"), 1)
                    data = data.replace(b"-dynamiclib -Wl,-headerpad_max_install_names", b"-dynamiclib")
                elif relative == "scripts/shared/_helpers.sh":
                    data = data.replace(b"curl --connect-timeout 30 --max-time 180 --retry 3 -fsSL", b"curl -fsSL")
                self.assertEqual(hashlib.sha256(data).hexdigest(), expected)

    def test_native_license_is_preserved(self):
        self.assertIn("GNU LESSER GENERAL PUBLIC LICENSE", (ROOT / "native/licenses/libsmb2/LICENCE-LGPL-2.1.txt").read_text())
        self.assertIn("Redistribution and use", (ROOT / "LICENSE").read_text())

if __name__ == "__main__":
    unittest.main()
