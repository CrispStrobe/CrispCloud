#!/usr/bin/env python3
"""Independent, read-only byte evidence for three pinned Apache POI DOCs.

Requires olefile==0.47. This does not import the Dart parser under test, resolve
document links, or execute embedded objects. It inspects only the three exact
SHA-256 inputs below. Offsets in the report are relative to named CFB streams.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct

import olefile

HASHES = {
    "56880.doc": "447fb46ea0d0d374f8f10f99c4ec92d0c9f694427b5d17ae02574a4b17bce224",
    "57603-seven_columns.doc": "1e37dac76f3690f88674b44558a73ff447946264250ed41ccb1a25e33b9988ef",
    "Bug51834.doc": "fb570d42bc0bdea8df147549a8b662a013bfb61b953c9c058138caf65af64907",
}


def u16(data: bytes, at: int) -> int:
    return struct.unpack_from("<H", data, at)[0]


def selected_style_properties(data: bytes, origin: int) -> list[dict]:
    count, base = u16(data, 2), u16(data, 4)
    at = 2 + u16(data, 0)
    wanted = {40, 41, 42, 43, 53}
    output = []
    for index in range(count):
        size = u16(data, at)
        at += 2
        record_at = at
        record = data[at:at + size]
        at += size
        if not size or index not in wanted:
            continue
        assert (u16(record, 2) & 15) == 1
        name_size = u16(record, base)
        name = record[base + 2:base + 2 + 2 * name_size].decode("utf-16le")
        upx = base + 4 + 2 * name_size
        papx_size = u16(record, upx)
        papx = record[upx + 4:upx + 2 + papx_size]
        properties = []
        cursor = 0
        while cursor < len(papx):
            code = u16(papx, cursor)
            cursor += 2
            spra = code >> 13
            if spra == 6:
                length = papx[cursor]
                cursor += 1
            else:
                length = (1, 1, 2, 4, 2, 2, 0, 3)[spra]
            value = papx[cursor:cursor + length]
            assert len(value) == length
            if code in (0x260A, 0x460B, 0xC63E):
                item = {"sprm": f"0x{code:04X}", "operandHex": value.hex()}
                if code == 0x460B:
                    item["signedValue"] = struct.unpack("<h", value)[0]
                elif code == 0x260A:
                    item["value"] = value[0]
                else:
                    item["operandBytes"] = len(value)
                properties.append(item)
            cursor += length
        assert cursor == len(papx)
        output.append({
            "styleIndex": index,
            "name": name,
            "parentIndex": u16(record, 2) >> 4,
            "recordOffset": origin + record_at,
            "numberingProperties": properties,
        })
    assert {item["styleIndex"] for item in output} == wanted
    return output


def inspect(corpus: Path) -> dict:
    assert olefile.__version__ == "0.47", "Use the recorded olefile version."
    sources = []
    for name, expected in HASHES.items():
        path = corpus / name
        raw = path.read_bytes()
        actual = hashlib.sha256(raw).hexdigest()
        assert actual == expected, f"Source hash mismatch: {name}"
        with olefile.OleFileIO(raw) as ole:
            word = ole.openstream("WordDocument").read()
            table_name = "1Table" if u16(word, 10) & 0x200 else "0Table"
            table = ole.openstream(table_name).read()
            cslw_at = 34 + u16(word, 32) * 2
            pairs_at = cslw_at + 4 + u16(word, cslw_at) * 4

            def pair(index: int) -> tuple[int, int]:
                return struct.unpack_from("<II", word, pairs_at + 8 * index)

            result = {"file": name, "sha256": actual, "bytes": len(raw),
                      "tableStream": table_name, "nFib": f"0x{u16(word, 2):04X}"}
            if name == "56880.doc":
                offset, size = pair(51)
                value = table[offset:offset + size]
                assert size == 22 and value == bytes(22)
                result["revisionAuthorTable"] = {
                    "fibPair": 51, "offset": offset, "bytes": size,
                    "hex": value.hex(), "allZero": True,
                }
            elif name == "57603-seven_columns.doc":
                offset, size = pair(1)
                result["styles"] = selected_style_properties(table[offset:offset + size], offset)
            else:
                needle = bytes.fromhex("ffffffffffffe0ff")
                occurrences = []
                for parts in ole.listdir(streams=True, storages=False):
                    data = ole.openstream(parts).read()
                    start = 0
                    while (found := data.find(needle, start)) != -1:
                        occurrences.append({"stream": "/".join(parts), "offset": found})
                        start = found + 1
                assert occurrences
                result["ignoredBorderOperand"] = {
                    "hex": needle.hex(), "type": 255,
                    "lastFourBytes": needle[4:].hex(),
                    "isModernNil": needle[4:] == b"\xff" * 4,
                    "exactByteOccurrences": occurrences,
                }
            sources.append(result)
        assert hashlib.sha256(path.read_bytes()).hexdigest() == expected
    return {"version": 1, "containerReader": "olefile 0.47", "sources": sources}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, default=Path(__file__).resolve().parents[3] /
                        "test/fixtures/external/poi-20261114/poi/doc")
    args = parser.parse_args()
    print(json.dumps(inspect(args.corpus), indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
