"""Verify TAR writer data/metadata with Python tarfile and GNU tar."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile


def inspect(path):
    records = []
    with tarfile.open(path, "r:") as archive:
        for member in archive:
            assert member.isfile() or member.isdir(), (path, member.name)
            stream = archive.extractfile(member) if member.isfile() else None
            content = stream.read() if stream else b""
            records.append({
                "path": member.name, "size": member.size, "mode": member.mode,
                "uid": member.uid, "gid": member.gid, "uname": member.uname,
                "gname": member.gname, "mtime": str(member.mtime),
                "pax": member.pax_headers, "sha256": hashlib.sha256(content).hexdigest(),
            })
            if member.isfile():
                extracted = subprocess.run(
                    ["tar", "--extract", "--to-stdout", "--file", str(path), "--", member.name],
                    check=True, capture_output=True,
                ).stdout
                assert extracted == content, (path, member.name, "GNU extraction differs")
    subprocess.run(["tar", "--list", "--file", str(path)], check=True, capture_output=True)
    return records


def main():
    directory = Path(sys.argv[1])
    print(subprocess.run(["tar", "--version"], check=True, capture_output=True, text=True).stdout.splitlines()[0])
    for case in json.loads((directory / "manifest.json").read_text()):
        records = inspect(directory / case["file"])
        if "source" in case:
            assert records == inspect(directory / case["source"]), (case, records)
        else:
            expected = case["expected"]
            assert len(records) == 1
            record = records[0]
            for field in ("path", "uid", "gid", "uname", "gname", "mode"):
                assert record[field] == expected[field], (case, field, record[field])
            assert record["pax"]["mtime"] == expected["mtime"]
            assert record["sha256"] == hashlib.sha256(expected["content"].encode()).hexdigest()
        print(f"PASS {case['file']}: {len(records)} members, native data and owner/time metadata")
    print("All independent TAR writer checks passed.")


if __name__ == "__main__":
    main()
