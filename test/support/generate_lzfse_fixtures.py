#!/usr/bin/env python3
"""Reproduce LZFSE fixtures with the pinned, unmodified Apple reference.

Run from any directory:
  python3 test/support/generate_lzfse_fixtures.py --source /path/to/lzfse --check

Use --write to regenerate the committed Dart data and manifest. This builds a
temporary test-only shared library; it does not add a native app dependency.
The --work-dir option retains the generated .bin/.lzfse files for independent
container extraction checks. All fixture payloads are deterministic test data.
"""

from __future__ import annotations

import argparse
import base64
import ctypes
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import textwrap


PIN = "e634ca58b4821d9f3d560cdc6df5dec02ffc93fd"
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
DATA_FILE = HERE / "lzfse_reference_data.dart"
MANIFEST_FILE = ROOT / "test/fixtures/archives/lzfse-reference-manifest.json"


def noise(length: int) -> bytes:
    # Products remain below 2**53; the matching Dart generator is exact on JS.
    state = 173
    result = bytearray(length)
    for index in range(length):
        state = (state * 48271) % 2147483647
        result[index] = state % 256
    return bytes(result)


def blocks(data: bytes) -> list[dict]:
    """Read only reference framing; this is not an entropy decoder."""
    result = []
    offset = 0
    while offset + 4 <= len(data):
        magic = data[offset:offset + 4].decode("ascii")
        if magic == "bvx$":
            assert offset + 4 == len(data), "bytes after reference EOS"
            return result
        raw = struct.unpack_from("<I", data, offset + 4)[0]
        if magic == "bvx2":
            a, b, c = struct.unpack_from("<QQQ", data, offset + 8)
            header = c & 0xFFFFFFFF
            payload = ((a >> 20) & 0xFFFFF) + ((b >> 40) & 0xFFFFF)
        elif magic == "bvx1":
            header = 772
            payload = struct.unpack_from("<I", data, offset + 8)[0]
        elif magic == "bvxn":
            header = 12
            payload = struct.unpack_from("<I", data, offset + 8)[0]
        elif magic == "bvx-":
            header, payload = 8, raw
        else:
            raise AssertionError(f"unexpected magic {magic!r}")
        assert offset + header + payload <= len(data)
        result.append({"magic": magic, "offset": offset, "raw_bytes": raw,
                       "header_bytes": header, "payload_bytes": payload})
        offset += header + payload
    raise AssertionError("reference EOS missing")


class Reference:
    def __init__(self, source: Path, work: Path):
        actual = subprocess.check_output(
            ["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
        if actual != PIN:
            raise ValueError(f"expected reference {PIN}, got {actual}")
        subprocess.run(["git", "-C", str(source), "diff", "--exit-code", PIN,
                        "--", "src", "LICENSE"], check=True,
                       stdout=subprocess.DEVNULL)
        src = source / "src"
        library = work / "liblzfse_fixture_reference.so"
        subprocess.run([
            os.environ.get("CC", "cc"), "-std=c99", "-D_POSIX_C_SOURCE=200809L",
            "-O2", "-fPIC", "-shared", "-I", str(src),
            str(HERE / "lzfse_reference_helper.c"),
            *(str(src / name) for name in (
                "lzfse_encode.c", "lzfse_encode_base.c", "lzfse_fse.c",
                "lzvn_encode_base.c", "lzvn_decode_base.c")),
            "-o", str(library),
        ], check=True)
        self.lib = ctypes.CDLL(str(library))
        self.lib.lzfse_encode_buffer.argtypes = [
            ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t,
            ctypes.c_void_p]
        self.lib.lzfse_encode_buffer.restype = ctypes.c_size_t
        self.lib.fixture_v1_header.argtypes = [
            ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
        self.lib.fixture_v1_header.restype = ctypes.c_size_t
        self.lib.fixture_decode.argtypes = [
            ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t,
            ctypes.POINTER(ctypes.c_size_t), ctypes.POINTER(ctypes.c_size_t)]
        self.lib.fixture_decode.restype = ctypes.c_int

    def encode(self, plain: bytes) -> bytes:
        out = ctypes.create_string_buffer(len(plain) * 2 + 8192)
        size = self.lib.lzfse_encode_buffer(out, len(out), plain, len(plain), None)
        assert size > 0
        return out.raw[:size]

    def v1(self, packed: bytes) -> bytes:
        out = bytearray()
        for block in blocks(packed):
            start = block["offset"]
            header = block["header_bytes"]
            end = start + header + block["payload_bytes"]
            if block["magic"] == "bvx2":
                expanded = ctypes.create_string_buffer(1024)
                size = self.lib.fixture_v1_header(
                    packed[start:end], end - start, expanded, len(expanded))
                assert size == 772, size
                out.extend(expanded.raw[:size])
                out.extend(packed[start + header:end])
            else:
                out.extend(packed[start:end])
        return bytes(out) + b"bvx$"

    def decode(self, packed: bytes, expected: bytes) -> bool:
        # Spare capacity prevents a full output buffer from masking a missing
        # stream end. fixture_decode additionally requires the exact source end.
        out = ctypes.create_string_buffer(len(expected) + 64)
        written, consumed = ctypes.c_size_t(), ctypes.c_size_t()
        status = self.lib.fixture_decode(
            packed, len(packed), out, len(out), ctypes.byref(written),
            ctypes.byref(consumed))
        return (status == 0 and written.value == len(expected)
                and consumed.value == len(packed)
                and out.raw[:written.value] == expected)


def vectors(reference: Reference) -> dict[str, tuple[bytes, bytes]]:
    plain = {
        "empty": b"",
        "raw": bytes(range(7)),
        "lzvn": (b"CrispCloud archive LZVN reference. " * 40)[:1024],
        "v2": bytes((i * 17 + i // 251) % 256 for i in range(32768)),
        "v2_zero": bytes(8192),
        "distance": noise(8192) + b"Z" * 100000 + noise(8192),
        "multiblock": noise(50000) * 2,
    }
    result = {name: (data, reference.encode(data))
              for name, data in plain.items()}
    result["v1"] = (plain["v2"], reference.v1(result["v2"][1]))
    parts = [result[name] for name in ("raw", "lzvn", "v2", "v1")]
    result["mixed"] = (b"".join(p[0] for p in parts),
                       b"".join(p[1][:-4] for p in parts) + b"bvx$")
    v2 = result["v2"][1]
    header_size = blocks(v2)[0]["header_bytes"]
    reused_header = bytearray(v2[:32])
    struct.pack_into("<I", reused_header, 24, 32)
    # Apple's decoder retains FSE tables across other block types as well as
    # consecutive compressed blocks. A 32-byte v2 header omits new tables.
    bridge = b"bridge"
    result["v2_reused_tables"] = (
        plain["v2"] + bridge + plain["v2"],
        v2[:-4] + b"bvx-" + struct.pack("<I", len(bridge)) + bridge
        + bytes(reused_header) + v2[header_size:])
    result["v1_lzvn_reused_tables"] = (
        plain["v2"] + plain["lzvn"] + plain["v2"],
        result["v1"][1][:-4] + result["lzvn"][1][:-4]
        + bytes(reused_header) + v2[header_size:])
    # Hand-specified LZVN small-distance opcode: L=0, M=10, D=3. It must
    # copy from the preceding stored block and overlap its own new output.
    history = b"ABC"
    lzvn = bytes([0x38, 3, 6, 0, 0, 0, 0, 0, 0, 0])
    result["cross_block_lzvn"] = (
        b"ABCABCABCABCA",
        b"bvx-" + struct.pack("<I", len(history)) + history
        + b"bvxn" + struct.pack("<II", 10, len(lzvn)) + lzvn + b"bvx$")
    for name, (data, packed) in result.items():
        assert reference.decode(packed, data), f"Apple reference rejected {name}"
    multi = blocks(result["multiblock"][1])
    assert len(multi) >= 2 and all(b["magic"] == "bvx2" for b in multi)
    second = multi[1]
    # This proves the second compressed block needs earlier decoded history;
    # merely joining separately encoded streams would not test that contract.
    assert not reference.decode(
        result["multiblock"][1][second["offset"]:],
        plain["multiblock"][multi[0]["raw_bytes"]:])
    return result


def dart_data(fixtures: dict[str, tuple[bytes, bytes]]) -> str:
    lines = [
        "// Generated by test/support/generate_lzfse_fixtures.py; do not edit.",
        f"// Apple lzfse {PIN} (BSD-3-Clause).",
        "// Deterministic synthetic input; every stream independently decoded",
        "// to its exact bytes and terminal state by the original Apple decoder.",
        "const lzfseReferenceData = <String, String>{",
    ]
    for name, (_, packed) in fixtures.items():
        if name in ("mixed", "v2_reused_tables", "v1_lzvn_reused_tables"):
            continue  # The Dart helper joins the original constituent blocks.
        encoded = base64.b64encode(packed).decode("ascii")
        single = f"  '{name}': '{encoded}',"
        if len(single) <= 80:
            lines.append(single)
            continue
        lines.append(f"  '{name}':")
        chunks = textwrap.wrap(encoded, 76)
        for index, chunk in enumerate(chunks):
            lines.append(f"      '{chunk}'" + ("," if index == len(chunks) - 1 else ""))
    return "\n".join([*lines, "};", ""])


def manifest(fixtures: dict[str, tuple[bytes, bytes]], source: Path) -> str:
    records = []
    for name, (plain, packed) in fixtures.items():
        records.append({
            "name": name, "plain_bytes": len(plain), "packed_bytes": len(packed),
            "plain_sha256": hashlib.sha256(plain).hexdigest(),
            "packed_sha256": hashlib.sha256(packed).hexdigest(),
            "blocks": blocks(packed),
            "reference_exact_output_eos_and_consumption": True,
        })
    return json.dumps({
        "source": "https://github.com/lzfse/lzfse", "revision": PIN,
        "license": "BSD-3-Clause",
        "license_sha256": hashlib.sha256((source / "LICENSE").read_bytes()).hexdigest(),
        "generator": "test/support/generate_lzfse_fixtures.py",
        "v1_method": "Original Apple v2 header expansion; original coded payload retained",
        "multiblock_second_block_requires_history": True,
        "fixtures": records,
    }, indent=2) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    parser.add_argument("--work-dir", type=Path)
    args = parser.parse_args()
    source = args.source.resolve()
    with tempfile.TemporaryDirectory(prefix="lzfse-reference-") as tmp:
        work = args.work_dir.resolve() if args.work_dir else Path(tmp)
        work.mkdir(parents=True, exist_ok=True)
        reference = Reference(source, work)
        fixtures = vectors(reference)
        generated = {DATA_FILE: dart_data(fixtures),
                     MANIFEST_FILE: manifest(fixtures, source)}
        for path, contents in generated.items():
            if args.write:
                path.write_text(contents)
            else:
                if not path.exists() or path.read_text() != contents:
                    raise SystemExit(f"Fixture differs: {path}; regenerate with --write")
        if args.work_dir:
            for name, (plain, packed) in fixtures.items():
                (work / f"{name}.bin").write_bytes(plain)
                (work / f"{name}.lzfse").write_bytes(packed)
        print(json.dumps({
            "result": "generated" if args.write else "verified",
            "reference_revision": PIN,
            "fixture_count": len(fixtures),
            "strict_reference_decodes": len(fixtures),
            "multiblock_history_negative_control": "passed",
        }, indent=2))


if __name__ == "__main__":
    main()
