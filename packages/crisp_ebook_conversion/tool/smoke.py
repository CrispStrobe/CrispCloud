"""Round-trip original EPUBs through the real, pinned converter.

Uses Python's standard library only. PDB/EXTH/PalmDOC parsing below is independent
of Kindling; reader package tests additionally use the foliate-js parser.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "test/fixtures"
LIMITS = {
    "input_bytes": 64 * 1024 * 1024, "output_bytes": 128 * 1024 * 1024,
    "expanded_bytes": 192 * 1024 * 1024, "entry_bytes": 32 * 1024 * 1024,
    "entries": 10000, "image_pixels": 50000000,
}


def records(data):
    assert data[60:68] == b"BOOKMOBI"
    count = struct.unpack_from(">H", data, 76)[0]
    offsets = [struct.unpack_from(">I", data, 78 + i * 8)[0] for i in range(count)]
    assert offsets == sorted(offsets) and offsets[0] >= 78 + count * 8
    return [data[a:b] for a, b in zip(offsets, offsets[1:] + [len(data)])]


def palmdoc(data):
    output = bytearray()
    pos = 0
    while pos < len(data):
        byte = data[pos]
        pos += 1
        if 1 <= byte <= 8:
            output.extend(data[pos:pos + byte])
            pos += byte
        elif byte <= 127:
            output.append(byte)
        elif byte >= 192:
            output.extend((32, byte ^ 128))
        else:
            assert pos < len(data)
            pair = (byte << 8) | data[pos]
            pos += 1
            distance = (pair & 0x3FFF) >> 3
            length = (pair & 7) + 3
            assert 0 < distance <= len(output)
            for _ in range(length):
                output.append(output[-distance])
    return bytes(output)


def inspect(data, expected_version):
    parts = records(data)
    first = parts[0]
    assert first[16:20] == b"MOBI"
    assert struct.unpack_from(">I", first, 36)[0] == expected_version
    assert struct.unpack_from(">H", first, 12)[0] == 0
    compression, count = struct.unpack_from(">H", first, 0)[0], struct.unpack_from(">H", first, 8)[0]
    assert compression in (1, 2) and count > 0
    flags = struct.unpack_from(">I", first, 240)[0]
    bodies = []
    for record in parts[1:count + 1]:
        for _ in range((flags >> 1).bit_count()):
            length = 0
            for index, byte in enumerate(reversed(record[-4:])):
                length |= (byte & 127) << (index * 7)
                if byte & 128:
                    break
            assert 0 < length <= len(record)
            record = record[:-length]
        if flags & 1:
            record = record[:-((record[-1] & 3) + 1)]
        bodies.append(palmdoc(record) if compression == 2 else record)
    text = b"".join(bodies)
    assert b"First Chapter" in text and b"Second Chapter" in text, text[:400]
    assert "café".encode() in text
    header_length = struct.unpack_from(">I", first, 20)[0]
    start = 16 + header_length
    assert first[start:start + 4] == b"EXTH"
    result = {}
    pos = start + 12
    for _ in range(struct.unpack_from(">I", first, start + 8)[0]):
        key, length = struct.unpack_from(">II", first, pos)
        assert length >= 8
        result.setdefault(key, []).append(first[pos + 8:pos + length])
        pos += length
    return result


def invoke(executable, source, *, operation="export", format="azw3", patch=None, limits=None):
    with tempfile.TemporaryDirectory(prefix="crisp_kindling_smoke_") as directory:
        work = Path(directory)
        baseline = source if isinstance(source, bytes) else source.read_bytes()
        input_file = work / ("input.epub" if operation == "export" else "input.mobi")
        input_file.write_bytes(baseline)
        request = {"work_dir": str(work), "operation": operation, "format": format,
                   "metadata": patch or {}, "cover": False, "limits": limits or LIMITS}
        run = subprocess.run([str(executable)], input=json.dumps(request), text=True,
                             capture_output=True, timeout=60, check=True)
        response = json.loads([line for line in run.stdout.splitlines() if line.startswith("{")][-1])
        assert input_file.read_bytes() == baseline, "Source snapshot was modified"
        output = work / ("output." + format)
        return response, output.read_bytes() if output.exists() else None


def legacy_only(data):
    """Make an original MOBI6 parser fixture from the dual book's first half.

    This is test-fixture surgery, not a supported converter/export operation.
    Retains every KF7 record and its resources, removes the boundary/KF8 tail,
    rebuilds the PDB table, and sets EXTH121 to its no-KF8 sentinel.
    """
    parts = records(data)
    first = bytearray(parts[0])
    exth = 16 + struct.unpack_from(">I", first, 20)[0]
    cursor = exth + 12
    boundary = None
    for _ in range(struct.unpack_from(">I", first, exth + 8)[0]):
        key, size = struct.unpack_from(">II", first, cursor)
        if key == 121:
            boundary = struct.unpack_from(">I", first, cursor + 8)[0]
            struct.pack_into(">I", first, cursor + 8, 0xFFFFFFFF)
        cursor += size
    assert boundary is not None and parts[boundary - 1] == b"BOUNDARY"
    parts = [bytes(first)] + parts[1:boundary - 1]
    header = bytearray(data[:78])
    struct.pack_into(">H", header, 76, len(parts))
    offset = 78 + 8 * len(parts) + 2
    table = bytearray()
    for index, part in enumerate(parts):
        table.extend(struct.pack(">I", offset) + data[82 + index * 8:86 + index * 8])
        offset += len(part)
    return bytes(header + table + b"\0\0") + b"".join(parts)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--executable", type=Path,
                        default=ROOT / "native/target/release/crisp-kindling")
    args = parser.parse_args()
    executable = args.executable.resolve()
    output_dir = FIXTURES / "generated"
    output_dir.mkdir(exist_ok=True)
    report = {"engine": subprocess.check_output([str(executable), "--version"], text=True).strip(),
              "tests": [], "outputs": {}}
    assert report["engine"] == "crisp-kindling 1 (Kindling 0.46.2)"
    for extension, version in (("azw3", 8), ("mobi", 6)):
        response, data = invoke(executable, FIXTURES / "book.epub", format=extension)
        assert response["ok"], response
        info = inspect(data, version)
        assert info[100] == [b"Test Author"], info.get(100)
        path = output_dir / ("book." + extension)
        path.write_bytes(data)
        if extension == "mobi":
            legacy = legacy_only(data)
            inspect(legacy, 6)
            (output_dir / "legacy.mobi").write_bytes(legacy)
        title = "Updated café $(touch should-not-exist); literal"
        response, rewritten = invoke(executable, data, operation="metadata", format=extension,
                                     patch={"title": title, "authors": ["First Author", "Second Author"]})
        assert response["ok"] and response["changes"], response
        updated = inspect(rewritten, version)
        assert updated[503] == [title.encode()] and updated[100] == [b"First Author", b"Second Author"]
        old_parts, new_parts = records(data), records(rewritten)
        assert len(old_parts) == len(new_parts)
        for old, new in zip(old_parts, new_parts):
            if old[16:20] == b"MOBI":
                # Both KF7 and KF8 metadata headers must receive the update.
                assert title.encode() in new
            else:
                assert old == new, "Metadata rewrite changed a content/resource record"
        (output_dir / ("updated." + extension)).write_bytes(rewritten)
        response, unchanged = invoke(executable, rewritten, operation="metadata", format=extension)
        assert response["ok"] and response["noOp"] and unchanged == rewritten, response
        encrypted = bytearray(data)
        first_record = struct.unpack_from(">I", encrypted, 78)[0]
        struct.pack_into(">H", encrypted, first_record + 12, 2)
        response, blocked = invoke(executable, bytes(encrypted), operation="metadata", format=extension,
                                   patch={"title": "Must not update"})
        assert not response["ok"] and response["code"] == "drmProtected" and blocked is None, response
        report["tests"].append(f"{extension}: text/Unicode/metadata/no-op/source-preservation/DRM")
        report["outputs"][extension] = {"path": str(path), "bytes": len(data),
                                       "sha256": hashlib.sha256(data).hexdigest()}
    for fixture, expected in (("traversal.epub", "invalidInput"),
                              ("external_resource.epub", "invalidInput"),
                              ("protected.epub", "drmProtected")):
        response, blocked = invoke(executable, FIXTURES / fixture)
        assert not response["ok"] and response["code"] == expected and blocked is None, response
        report["tests"].append(f"{fixture}: rejected")
    for field, value in (("entries", 1), ("expanded_bytes", 100), ("image_pixels", 1)):
        limits = {**LIMITS, field: value}
        response, blocked = invoke(executable, FIXTURES / "book.epub", limits=limits)
        assert not response["ok"] and response["code"] == "limitExceeded" and blocked is None, response
        report["tests"].append(f"{field}: enforced")
    (output_dir / "smoke_report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
