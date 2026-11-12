#!/usr/bin/env python3
"""Generate original PBZX fixtures and verify them with BIOSUtilities.

Requires a separate checkout of the pinned permissively licensed reference
decoder. No reference implementation is copied into the application. See
test/fixtures/archives/PBZX_REFERENCE.md for reproduction and licensing.
"""

import argparse
import contextlib
import hashlib
import importlib
import io
import lzma
from pathlib import Path
import struct
import subprocess
import sys
import tempfile


REFERENCE_COMMIT = "f799425af93264b62a2f3c3cc5bbabf8a2226114"
CPIO_SHA256 = "654f5817c061f00101f57a70e014c1762eb33d58a17923a3ccedfcd0907d4729"
FIXTURES = Path(__file__).resolve().parents[1] / "fixtures/archives"


def frame(block_size, chunks):
    output = bytearray(b"pbzx" + struct.pack(">Q", block_size))
    for plain, encoded in chunks:
        output.extend(struct.pack(">QQ", len(plain), len(encoded)))
        output.extend(encoded)
    return bytes(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference_checkout", type=Path)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    checkout = args.reference_checkout.resolve()
    commit = subprocess.check_output(
        ["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True
    ).strip()
    if commit != REFERENCE_COMMIT:
        raise SystemExit(f"Reference checkout must be {REFERENCE_COMMIT}, got {commit}")
    if subprocess.check_output(
        ["git", "-C", str(checkout), "status", "--porcelain", "--untracked-files=no"],
        text=True,
    ).strip():
        raise SystemExit("Reference checkout has modified tracked files")

    # Import the unchanged upstream parser. Its only external dependency is
    # the optional 7-Zip step after PBZX decoding has written a CPIO file.
    sys.path.insert(0, str(checkout))
    reference = importlib.import_module("biosutilities.apple_efi_pbzx")
    plain = (FIXTURES / "reference-odc.cpio").read_bytes()
    assert hashlib.sha256(plain).hexdigest() == CPIO_SHA256
    first = plain[:256]
    compressed = lzma.compress(
        first, format=lzma.FORMAT_XZ, check=lzma.CHECK_CRC64, preset=6
    )
    assert len(compressed) < len(first)
    fixtures = {
        # The file header and member body cross an XZ/raw chunk boundary.
        "reference-odc.pbzx": frame(
            256, [(first, compressed), (plain[256:], plain[256:])]
        ),
        # Apple's modern package payloads may omit XZ data checksums. Header,
        # index and footer validation still applies; publisher trust is separate.
        "reference-odc-unchecked.pbzx": frame(
            16 * 1024 * 1024,
            [(plain, lzma.compress(
                plain, format=lzma.FORMAT_XZ, check=lzma.CHECK_NONE, preset=6
            ))],
        ),
    }

    class CpioHandoff(Exception):
        """Stops after independent PBZX decoding and before optional 7-Zip."""

    captured = []

    def capture_cpio(in_path, args=None):
        assert args == ["-tCPIO"]
        captured.append(Path(in_path).read_bytes())
        raise CpioHandoff

    original_handoff = reference.is_szip_supported
    reference.is_szip_supported = capture_cpio
    try:
        with tempfile.TemporaryDirectory(prefix="pbzx-reference-") as temporary:
            for name, generated in fixtures.items():
                data = (FIXTURES / name).read_bytes() if args.check_only else generated
                assert data == generated, f"Fixture bytes changed: {name}"
                destination = Path(temporary) / name
                decoder = reference.AppleEfiPbzxExtract(
                    input_object=data, extract_path=str(destination)
                )
                assert decoder.check_format(), name
                before = len(captured)
                log = io.StringIO()
                try:
                    with contextlib.redirect_stdout(log):
                        decoder.parse_format()
                except CpioHandoff:
                    pass
                else:
                    raise AssertionError(f"Reference did not finish PBZX decode: {log.getvalue()}")
                assert len(captured) == before + 1
                assert captured[-1] == plain, name
                if not args.check_only:
                    (FIXTURES / name).write_bytes(data)
                print(f"{name}: {len(data)} bytes, SHA-256 {hashlib.sha256(data).hexdigest()}")
                print(f"  BIOSUtilities {commit}: exact {len(plain)}-byte CPIO readback passed")
    finally:
        reference.is_szip_supported = original_handoff


if __name__ == "__main__":
    main()
