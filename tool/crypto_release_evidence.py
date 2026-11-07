#!/usr/bin/env python3
"""Record the source/dependency/artifact identity for an export review.

This is evidence collection, not an ECCN classifier or a cryptographic audit.
It makes no network calls, submits no forms, and never reads signing secrets.
Run after dependency resolution; use --require-clean on release builds.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INVENTORY = Path("docs/crypto-inventory.json")
REQUIRED_PROVIDERS = {"filen_client", "internxt_client"}
NATIVE_EVIDENCE = (
    "ios/Podfile.lock", "macos/Podfile.lock",
    "packages/crisp_ios_shell/ios/Resources/BuildProvenance.json",
)


class EvidenceError(ValueError):
    pass


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(root), *args], text=True, encoding="utf-8"
    ).strip()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def repository_file(root: Path, relative: str) -> Path:
    """Only permit real, in-repository files from the reviewed inventory."""
    candidate = root / relative
    resolved = candidate.resolve()
    if Path(relative).is_absolute() or not resolved.is_relative_to(root.resolve()):
        raise EvidenceError(f"Inventory path escapes the repository: {relative}")
    if candidate.is_symlink() or not candidate.is_file():
        raise EvidenceError(f"Missing or non-regular inventory file: {relative}")
    return candidate


def validate(root: Path) -> dict:
    inventory = json.loads(repository_file(root, str(INVENTORY)).read_text())
    if inventory.get("schema_version") != 1:
        raise EvidenceError("Unsupported crypto inventory schema")
    if set(inventory.get("required_providers", [])) != REQUIRED_PROVIDERS:
        raise EvidenceError("The release must retain both Filen and Internxt")
    files = inventory.get("reviewed_files", [])
    if not files or len(files) != len(set(files)):
        raise EvidenceError("reviewed_files must be a nonempty, unique list")
    for relative in files:
        repository_file(root, relative)
    # Pub's committed lockfile is retained verbatim, not parsed as general YAML.
    # These exact top-level package entries also ensure providers were resolved.
    lock = repository_file(root, "pubspec.lock").read_text()
    for name in REQUIRED_PROVIDERS | set(inventory["crypto_packages"]):
        if not re.search(r"^  " + re.escape(name) + r":\s*$", lock, re.MULTILINE):
            raise EvidenceError(f"Reviewed dependency missing from lockfile: {name}")
    pubspec = repository_file(root, "pubspec.yaml").read_text()
    if re.search(r"^\s+libsmb2:\s*\S", pubspec, re.MULTILINE):
        raise EvidenceError("A custom libsmb2 binary needs separate source and checksum review")
    # A developer override can redirect a public dependency to unpublished code.
    overrides = list(root.rglob("pubspec_overrides.yaml"))
    overrides = [p for p in overrides if ".dart_tool" not in p.parts and "build" not in p.parts]
    if overrides:
        names = ", ".join(str(p.relative_to(root)) for p in overrides)
        raise EvidenceError(f"Remove local dependency overrides for release evidence: {names}")
    for relative in ("ios/Runner/Info.plist", "macos/Runner/Info.plist"):
        with repository_file(root, relative).open("rb") as source:
            plist = plistlib.load(source)
        # Current reviewed policy. A future questionnaire-based exemption must
        # update this policy and its evidence, not silently flip the Boolean.
        if plist.get("ITSAppUsesNonExemptEncryption") is not True:
            raise EvidenceError(f"Keep the reviewed Apple questionnaire setting in {relative}")
    return inventory


def collect(root: Path, platform: str, artifacts: list[Path],
            dependencies: Path | None, require_clean: bool) -> dict:
    inventory = validate(root)
    commit = git(root, "rev-parse", "HEAD")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise EvidenceError("A full Git commit is required")
    dirty = git(root, "diff", "--name-only", "HEAD", "--")
    # Build outputs/signing material are not source inputs and are never read.
    untracked = git(root, "ls-files", "--others", "--exclude-standard", "--",
                    "lib", "packages", "ios", "macos", "android", "tool",
                    "docs", "test", ".github", "pubspec.yaml", "pubspec.lock", ".fvmrc")
    if require_clean and (dirty or untracked):
        changed = sorted(set(dirty.splitlines() + untracked.splitlines()))
        raise EvidenceError(
            "Release source differs from HEAD; review and commit these inputs: "
            + ", ".join(changed)
        )
    resolved_dependencies = None
    if dependencies:
        resolved_dependencies = json.loads(dependencies.read_text())
        packages = resolved_dependencies.get("packages", [])
        names = {p.get("name") for p in packages}
        if not REQUIRED_PROVIDERS <= names:
            raise EvidenceError("Resolved dependency graph omits Filen or Internxt")
    artifact_records = []
    for artifact in artifacts:
        if artifact.is_symlink() or not artifact.is_file() or artifact.stat().st_size == 0:
            raise EvidenceError(f"Expected a nonempty built artifact: {artifact.name}")
        artifact_records.append({
            "name": artifact.name,
            "bytes": artifact.stat().st_size,
            "sha256": sha256(artifact),
        })
    if require_clean and platform != "source":
        if not artifact_records:
            raise EvidenceError("Platform release evidence requires a built artifact")
        if resolved_dependencies is None:
            raise EvidenceError("Platform release evidence requires the resolved dependency graph")
    reviewed_files = {
        name: sha256(repository_file(root, name))
        for name in sorted(set(inventory["reviewed_files"]) | {
            str(INVENTORY), "pubspec.yaml", "pubspec.lock", ".fvmrc",
            "ios/Runner/Info.plist", "macos/Runner/Info.plist",
        })
    }
    return {
        "schema_version": 1,
        "purpose": "Engineering evidence; not a legal classification or filing",
        "platform": platform,
        "git_commit": commit,
        "git_tree": git(root, "rev-parse", "HEAD^{tree}"),
        "public_source_url": f"{inventory['repository']}/tree/{commit}",
        "source_archive_url": f"{inventory['repository']}/archive/{commit}.tar.gz",
        "source_publication_note": "Verify public access and corresponding dependency sources before release",
        "tracked_changes": dirty.splitlines(),
        "untracked_files": untracked.splitlines(),
        "required_providers": sorted(REQUIRED_PROVIDERS),
        "apple_source_questionnaire_enabled": True,
        "inventory_sha256": sha256(root / INVENTORY),
        "reviewed_files_sha256": reviewed_files,
        "native_evidence_sha256": {
            name: sha256(repository_file(root, name))
            for name in NATIVE_EVIDENCE if (root / name).is_file()
        },
        "artifacts": artifact_records,
        "resolved_dependencies": resolved_dependencies,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate reviewed build inputs only")
    parser.add_argument("--platform", choices=["source", "ios", "macos", "android"], default="source")
    parser.add_argument("--output-dir", type=Path, default=Path("build/export-compliance"))
    parser.add_argument("--artifact", type=Path, action="append", default=[])
    parser.add_argument("--dependencies", type=Path, help="Output of dart pub deps --json")
    parser.add_argument("--require-clean", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.check:
            validate(ROOT)
            print("Crypto release inputs checked; Filen and Internxt dependencies present.")
            return 0
        evidence = collect(ROOT, args.platform, args.artifact, args.dependencies, args.require_clean)
        args.output_dir.mkdir(parents=True, exist_ok=True)
        (args.output_dir / "crypto-evidence.json").write_text(
            json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        for name in ("pubspec.lock", "docs/crypto-inventory.json", "docs/export-compliance.md"):
            shutil.copyfile(ROOT / name, args.output_dir / Path(name).name)
        for name in evidence["native_evidence_sha256"]:
            target = args.output_dir / "native" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        print(f"Crypto release evidence written to {args.output_dir}")
        return 0
    except (EvidenceError, OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print(f"Crypto release evidence failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
