"""Record or verify exact permissive Cargo grants and their shipped notices."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
# The selected branch of an OR expression is the distribution grant.
# MPL/GPL/AGPL are intentionally not accepted as sole grants.
GRANTS = {
    "MIT": "MIT", "MIT OR Apache-2.0": "MIT", "Apache-2.0 OR MIT": "MIT",
    "MIT/Apache-2.0": "MIT", "Apache-2.0/MIT": "MIT",
    "Apache-2.0": "Apache-2.0", "BSD-2-Clause": "BSD-2-Clause",
    "BSD-3-Clause": "BSD-3-Clause", "ISC": "ISC",
    "Unlicense OR MIT": "MIT", "CC0-1.0 OR Apache-2.0": "Apache-2.0",
    "MIT OR Apache-2.0 OR Zlib": "MIT", "MIT OR Zlib OR Apache-2.0": "MIT",
    "Zlib OR Apache-2.0 OR MIT": "MIT",
    "BSD-3-Clause OR Apache-2.0": "BSD-3-Clause",
    "BSD-2-Clause OR Apache-2.0 OR MIT": "MIT",
    "0BSD OR MIT OR Apache-2.0": "MIT",
    "MIT OR Apache-2.0 OR LGPL-2.1-or-later": "MIT",
    "Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT": "MIT",
    "(MIT OR Apache-2.0) AND NCSA": "MIT AND NCSA",
    "(MIT OR Apache-2.0) AND Unicode-3.0": "MIT AND Unicode-3.0",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory():
    cargo = os.environ.get("CARGO", "cargo")
    data = json.loads(subprocess.check_output([
        cargo, "metadata", "--locked", "--format-version", "1",
        "--manifest-path", str(ROOT / "native/Cargo.toml"),
    ]))
    resolved = {node["id"] for node in data["resolve"]["nodes"]}
    packages = []
    notices = []
    for package in sorted(data["packages"], key=lambda p: (p["name"], p["version"])):
        if package["id"] not in resolved:
            continue
        expression = package.get("license")
        if expression not in GRANTS:
            raise SystemExit(f"Unreviewed license: {package['name']} {package['version']} {expression}")
        base = Path(package["manifest_path"]).parent
        files = sorted(p for p in base.rglob("*") if p.is_file()
            and not any(part in {"target", ".git"} for part in p.relative_to(base).parts)
            and p.name.upper().startswith(("LICENSE", "LICENCE", "COPYING", "NOTICE", "COPYRIGHT")))
        # A bridge root includes a vendored crate; only its own license belongs
        # to this row. The vendored crate has a separate row.
        if package["name"] == "crisp_kindling_bridge":
            files = [ROOT / "LICENSE"]
        if not files and package["name"] == "r-efi":
            files = [base / "AUTHORS"]
        if not files:
            raise SystemExit(f"Missing license text/evidence: {package['name']}")
        evidence = []
        for path in files:
            name = path.name if package["name"] == "crisp_kindling_bridge" else str(path.relative_to(base))
            evidence.append({"path": name, "sha256": digest(path)})
            content = path.read_text(errors="replace")
            notices.append(f"===== {package['name']} {package['version']} / {name} =====\n"
                           f"SPDX: {expression}; selected grant: {GRANTS[expression]}\n\n{content}\n")
        packages.append({
            "name": package["name"], "version": package["version"],
            "source": package["source"] or "vendored/local",
            "license_expression": expression, "selected_grant": GRANTS[expression],
            "evidence": evidence,
        })
    return {
        "schema": 1,
        "scope": "Every resolved native Cargo dependency, including platform and build dependencies.",
        "cargo_lock_sha256": digest(ROOT / "native/Cargo.lock"),
        "packages": packages,
    }, "\n".join(notices)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--record", action="store_true")
    args = parser.parse_args()
    data, text = inventory()
    report = ROOT / "licensing/cargo_licenses.json"
    notices = ROOT / "licensing/THIRD_PARTY_LICENSES.txt"
    if args.record:
        report.parent.mkdir(exist_ok=True)
        report.write_text(json.dumps(data, indent=2) + "\n")
        notices.write_text(text)
    elif json.loads(report.read_text()) != data or notices.read_text() != text:
        raise SystemExit("License inventory/notices changed. Review and record before shipping.")
    print(f"Verified permissive grants for {len(data['packages'])} resolved native packages.")

