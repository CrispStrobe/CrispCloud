"""Record or verify reviewed Cargo grants and their shipped notices."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
# The selected branch of an OR expression is the distribution grant.
# MPL-2.0 is approved for this feature. GPL/AGPL-only dependencies remain
# outside its selected grants; preserve all required upstream notices.
GRANTS = {
    "MIT": "MIT", "MIT OR Apache-2.0": "MIT", "Apache-2.0 OR MIT": "MIT",
    "MIT/Apache-2.0": "MIT", "Apache-2.0/MIT": "MIT",
    "Apache-2.0": "Apache-2.0", "BSD-2-Clause": "BSD-2-Clause",
    "BSD-3-Clause": "BSD-3-Clause", "ISC": "ISC", "MPL-2.0": "MPL-2.0",
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

# These published subcrates omit their workspace-root license. Keep the text
# from each crate's exact .cargo_vcs_info.json revision, with an auditable URL.
UPSTREAM_LICENSES = {
    ("const-str", "0.3.2"): (
        "const-str-0.3.2-LICENSE", "a80a942800cbf0b3cb656a4e4a4b7b6b63da15a6",
        "https://github.com/Nugine/const-str/blob/a80a942800cbf0b3cb656a4e4a4b7b6b63da15a6/LICENSE",
    ),
    ("const-str-proc-macro", "0.3.2"): (
        "const-str-0.3.2-LICENSE", "a80a942800cbf0b3cb656a4e4a4b7b6b63da15a6",
        "https://github.com/Nugine/const-str/blob/a80a942800cbf0b3cb656a4e4a4b7b6b63da15a6/LICENSE",
    ),
    ("cssparser-color", "0.1.0"): (
        "cssparser-color-0.1.0-LICENSE", "cab31ead1cded6a6c48967953298861e914739ad",
        "https://github.com/servo/rust-cssparser/blob/cab31ead1cded6a6c48967953298861e914739ad/LICENSE",
    ),
    ("lightningcss-derive", "1.0.0-alpha.43"): (
        "lightningcss-derive-alpha.43-LICENSE", "c7fc5a10120b1a98c603855dd319a6747e6b9409",
        "https://github.com/parcel-bundler/lightningcss/blob/c7fc5a10120b1a98c603855dd319a6747e6b9409/LICENSE",
    ),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory():
    cargo = os.environ.get("CARGO", "cargo")
    dependencies = {}
    for manifest in ["native/Cargo.toml", "wasm/Cargo.toml"]:
        data = json.loads(subprocess.check_output([
            cargo, "metadata", "--locked", "--format-version", "1",
            "--manifest-path", str(ROOT / manifest),
        ]))
        resolved = {node["id"] for node in data["resolve"]["nodes"]}
        dependencies.update((package["id"], package) for package in data["packages"]
                            if package["id"] in resolved)
    packages = []
    notices = []
    local_bridges = {"crisp_kindling_bridge", "crisp_kindling_metadata_wasm"}
    for package in sorted(dependencies.values(), key=lambda p: (p["name"], p["version"])):
        expression = package.get("license")
        if expression not in GRANTS:
            raise SystemExit(f"Unreviewed license: {package['name']} {package['version']} {expression}")
        base = Path(package["manifest_path"]).parent
        files = sorted(p for p in base.rglob("*") if p.is_file()
            and not any(part in {"target", ".git"} for part in p.relative_to(base).parts)
            and p.name.upper().startswith(("LICENSE", "LICENCE", "COPYING", "NOTICE", "COPYRIGHT")))
        # A bridge root includes a vendored crate; only its own license belongs
        # to this row. The vendored crate has a separate row.
        if package["name"] in local_bridges:
            files = [ROOT / "LICENSE"]
        if not files and package["name"] == "r-efi":
            files = [base / "AUTHORS"]
        upstream_notice = None
        if not files and (package["name"], package["version"]) in UPSTREAM_LICENSES:
            filename, revision, upstream_notice = UPSTREAM_LICENSES[(package["name"], package["version"])]
            vcs = json.loads((base / ".cargo_vcs_info.json").read_text())
            if vcs["git"]["sha1"] != revision:
                raise SystemExit(f"Unreviewed license source revision: {package['name']}")
            files = [ROOT / "licensing/upstream" / filename]
        if not files:
            raise SystemExit(f"Missing license text/evidence: {package['name']}")
        source_url = (
            f"https://crates.io/api/v1/crates/{package['name']}/{package['version']}/download"
            if package["source"] else
            "https://github.com/CrispStrobe/CrispCloud/tree/feature/ebook-reader-editor/packages/crisp_ebook_conversion"
        )
        evidence = []
        for path in files:
            name = (str(path.relative_to(ROOT)) if upstream_notice else
                path.name if package["name"] in local_bridges else str(path.relative_to(base)))
            evidence.append({"path": name, "sha256": digest(path),
                **({"upstream_url": upstream_notice} if upstream_notice else {})})
            # Normalize only trailing layout whitespace in the combined notice;
            # the evidence hash above still identifies the complete source file.
            content = "\n".join(line.rstrip() for line in path.read_text(errors="replace").splitlines())
            notices.append(f"===== {package['name']} {package['version']} / {name} =====\n"
                           f"SPDX: {expression}; selected grant: {GRANTS[expression]}\n"
                           f"Source code: {source_url}\n\n{content}\n")
        packages.append({
            "name": package["name"], "version": package["version"],
            "source": package["source"] or "vendored/local",
            "source_url": source_url,
            "license_expression": expression, "selected_grant": GRANTS[expression],
            "evidence": evidence,
        })
    return {
        "schema": 1,
        "scope": "Every resolved native and metadata-Wasm Cargo dependency, including platform and build dependencies.",
        "cargo_lock_sha256": digest(ROOT / "native/Cargo.lock"),
        "wasm_cargo_lock_sha256": digest(ROOT / "wasm/Cargo.lock"),
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
    print(f"Verified reviewed grants for {len(data['packages'])} resolved native/Wasm packages.")

