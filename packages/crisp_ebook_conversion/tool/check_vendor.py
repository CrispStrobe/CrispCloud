"""Verify the reviewed vendored Kindling source set without network access."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    provenance = json.loads((ROOT / "UPSTREAM.json").read_text())
    vendor = ROOT / provenance["vendor_path"]
    expected = provenance["local_file_sha256"]
    actual = {
        str(path.relative_to(vendor)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in vendor.rglob("*")
        if path.is_file()
        and not any(part in {"target", ".git"} for part in path.relative_to(vendor).parts)
    }
    changed = sorted(path for path in actual.keys() | expected.keys()
                     if actual.get(path) != expected.get(path))
    if changed:
        raise SystemExit("Unreviewed Kindling files: " + ", ".join(changed))
    print(f"Verified {len(actual)} Kindling files at {provenance['commit']} plus recorded patches.")


if __name__ == "__main__":
    main()
