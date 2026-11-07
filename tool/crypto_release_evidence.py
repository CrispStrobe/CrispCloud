#!/usr/bin/env python3
"""Record the source/dependency/artifact identity for an export review.

This is evidence collection, not an ECCN classifier or a cryptographic audit.
It makes no network calls, submits no forms, and never reads signing secrets.
Run after dependency resolution; use --require-clean on release builds.
The optional --record-generated-metadata flag records exact native resolution
and registration changes, plus verified iOS project reserialization, without
permitting changes to authored build settings or code.
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
# Flutter dependency resolution can regenerate Android's registrant even when
# building an Apple target. Native dependency locks remain target-specific.
COMMON_GENERATED_METADATA = {
    "android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java",
}
GENERATED_METADATA = {
    "ios": COMMON_GENERATED_METADATA | {"ios/Podfile.lock"},
    "macos": COMMON_GENERATED_METADATA | {"macos/Podfile.lock"},
    "android": COMMON_GENERATED_METADATA,
}
# CocoaPods may serialize this project differently without changing its parsed
# data. All other authored project files remain subject to the clean-source gate.
XCODE_RESERIALIZATION = {"ios": "ios/Runner.xcodeproj/project.pbxproj"}
XCODE_COMPARISON_METHOD = (
    "/usr/bin/plutil -convert json -o - -- -; canonical JSON with sorted dictionary "
    "keys, preserving array order and scalar types/values"
)


class EvidenceError(ValueError):
    pass


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(root), *args], text=True, encoding="utf-8"
    ).strip()


def git_bytes(root: Path, *args: str) -> bytes:
    return subprocess.check_output(["git", "-C", str(root), *args])


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


def canonical_xcode_project(data: bytes, relative: str, version: str) -> bytes:
    """Parse exact bytes with Apple's parser; never approximate OpenStep syntax."""
    try:
        result = subprocess.run(
            ["/usr/bin/plutil", "-convert", "json", "-o", "-", "--", "-"],
            input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            check=True, timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise EvidenceError(
            f"Cannot verify Xcode project data: /usr/bin/plutil unavailable or failed "
            f"for {version} {relative}: {error}"
        ) from error

    def unique_object(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise ValueError("duplicate JSON dictionary key")
            value[key] = item
        return value

    def reject_constant(value):
        raise ValueError(f"non-JSON numeric constant: {value}")

    try:
        parsed = json.loads(result.stdout, object_pairs_hook=unique_object,
                            parse_constant=reject_constant)
        if not isinstance(parsed, dict):
            raise ValueError("Xcode project must parse to a dictionary")
        # Comparing Python objects directly would equate True with 1. Canonical
        # JSON ignores only dictionary order, retaining scalar types and arrays.
        return json.dumps(parsed, sort_keys=True, separators=(",", ":"),
                          allow_nan=False).encode("utf-8")
    except (ValueError, TypeError, UnicodeError) as error:
        raise EvidenceError(
            f"Malformed /usr/bin/plutil JSON output for {version} {relative}: {error}"
        ) from error


def generated_metadata_record(root: Path, relative: str,
                              verify_xcode_data: bool = False) -> dict:
    """Record an existing generated file, never a missing or redirected input."""
    path = repository_file(root, relative)
    # repository_file checks the final file and repository boundary. A link in
    # a parent directory must not redirect a recorded generated input either.
    parts = Path(relative).parts
    if any(root.joinpath(*parts[:end]).is_symlink()
           for end in range(1, len(parts) + 1)):
        raise EvidenceError(f"Generated metadata cannot contain symlinks: {relative}")
    entry = git(root, "ls-tree", "HEAD", "--", relative)
    baseline = re.fullmatch(r"(100644|100755) blob ([0-9a-f]{40})\t" + re.escape(relative), entry)
    if not baseline:
        raise EvidenceError(f"Generated metadata must be a tracked regular file at HEAD: {relative}")
    head_mode, head_blob = baseline.groups()
    raw = git(root, "diff", "--raw", "--no-renames", "HEAD", "--", relative)
    fields = raw.split("\t", 1)[0].split()
    if (len(fields) != 5 or fields[0] != f":{head_mode}"
            or fields[1] != head_mode or fields[4] != "M"):
        raise EvidenceError(f"Generated metadata must preserve its tracked type and mode: {relative}")
    built_bytes = path.read_bytes()
    if not built_bytes:
        raise EvidenceError(f"Generated metadata must not be empty: {relative}")
    semantic_record = {}
    if verify_xcode_data:
        head_bytes = git_bytes(root, "cat-file", "blob", head_blob)
        baseline_data = canonical_xcode_project(head_bytes, relative, "HEAD")
        built_data = canonical_xcode_project(built_bytes, relative, "built")
        if baseline_data != built_data:
            raise EvidenceError(
                f"Xcode project parsed data differs from HEAD; review and commit this input: {relative}"
            )
        semantic_record = {
            "record_reason": "Parsed Xcode project data unchanged; serialization-only for this build",
            "comparison_method": XCODE_COMPARISON_METHOD,
            "canonical_json_sha256": hashlib.sha256(baseline_data).hexdigest(),
        }
    diff = git_bytes(root, "diff", "--no-ext-diff", "--no-textconv", "--binary",
                     "--no-renames", "HEAD", "--", relative)
    return {
        "head_blob": head_blob,
        "head_mode": head_mode,
        "built_sha256": hashlib.sha256(built_bytes).hexdigest(),
        "built_bytes": len(built_bytes),
        "head_file": f"generated/head/{relative}",
        "built_file": f"generated/actual/{relative}",
        "diff_file": f"generated/diff/{relative}.patch",
        "diff_sha256": hashlib.sha256(diff).hexdigest(),
        "diff": diff.decode("utf-8"),
        **semantic_record,
    }


def collect(root: Path, platform: str, artifacts: list[Path],
            dependencies: Path | None, require_clean: bool,
            record_generated_metadata: bool = False) -> dict:
    if record_generated_metadata and (not require_clean or platform not in GENERATED_METADATA):
        raise EvidenceError("Generated metadata recording requires --require-clean and a target platform")
    inventory = validate(root)
    commit = git(root, "rev-parse", "HEAD")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise EvidenceError("A full Git commit is required")
    dirty = git(root, "diff", "--name-only", "HEAD", "--")
    # Build outputs/signing material are not source inputs and are never read.
    untracked = git(root, "ls-files", "--others", "--exclude-standard", "--",
                    "lib", "packages", "ios", "macos", "android", "tool",
                    "docs", "test", ".github", "pubspec.yaml", "pubspec.lock", ".fvmrc")
    dirty_paths = set(dirty.splitlines())
    untracked_paths = set(untracked.splitlines())
    allowed_generated = set(GENERATED_METADATA.get(platform, set())) if record_generated_metadata else set()
    xcode_project = XCODE_RESERIALIZATION.get(platform) if record_generated_metadata else None
    if xcode_project:
        allowed_generated.add(xcode_project)
    generated_paths = dirty_paths & allowed_generated
    authored_changes = dirty_paths - generated_paths
    if require_clean and (authored_changes or untracked_paths):
        changed = sorted(authored_changes | untracked_paths)
        raise EvidenceError(
            "Release source differs from HEAD; review and commit these inputs: "
            + ", ".join(changed)
        )
    generated_records = {
        name: generated_metadata_record(root, name, verify_xcode_data=name == xcode_project)
        for name in sorted(generated_paths)
    }
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
        "source_checkout_clean": not (dirty_paths or untracked_paths),
        "authored_source_changes": sorted(authored_changes),
        "generated_metadata_recording_enabled": record_generated_metadata,
        "generated_metadata_changes": generated_records,
        "generated_metadata_review_note": (
            "Generated native dependency locks and plugin registration describe the actual build. "
            "Recorded iOS project reserialization must preserve its parsed Xcode data. "
            "Review their resolved dependencies and corresponding sources before release; "
            "recording these changes is not approval or a legal classification."
        ),
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


def write_generated_metadata(root: Path, output: Path, evidence: dict) -> None:
    """Keep full baseline/built files and exact patches alongside their hashes."""
    for relative, record in evidence["generated_metadata_changes"].items():
        actual = repository_file(root, relative).read_bytes()
        if hashlib.sha256(actual).hexdigest() != record["built_sha256"]:
            raise EvidenceError(f"Generated metadata changed during evidence collection: {relative}")
        contents = {
            "head_file": git_bytes(root, "cat-file", "blob", record["head_blob"]),
            "built_file": actual,
            "diff_file": record["diff"].encode("utf-8"),
        }
        for field, data in contents.items():
            target = output / record[field]
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate reviewed build inputs only")
    parser.add_argument("--platform", choices=["source", "ios", "macos", "android"], default="source")
    parser.add_argument("--output-dir", type=Path, default=Path("build/export-compliance"))
    parser.add_argument("--artifact", type=Path, action="append", default=[])
    parser.add_argument("--dependencies", type=Path, help="Output of dart pub deps --json")
    parser.add_argument("--require-clean", action="store_true")
    parser.add_argument(
        "--record-generated-metadata", action="store_true",
        help="With --require-clean, retain exact generated native metadata changes for review",
    )
    args = parser.parse_args(argv)
    try:
        if args.check:
            validate(ROOT)
            print("Crypto release inputs checked; Filen and Internxt dependencies present.")
            return 0
        evidence = collect(ROOT, args.platform, args.artifact, args.dependencies, args.require_clean,
                           record_generated_metadata=args.record_generated_metadata)
        args.output_dir.mkdir(parents=True, exist_ok=True)
        for name in ("pubspec.lock", "docs/crypto-inventory.json", "docs/export-compliance.md"):
            shutil.copyfile(ROOT / name, args.output_dir / Path(name).name)
        for name in evidence["native_evidence_sha256"]:
            target = args.output_dir / "native" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        write_generated_metadata(ROOT, args.output_dir, evidence)
        (args.output_dir / "crypto-evidence.json").write_text(
            json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        print(f"Crypto release evidence written to {args.output_dir}")
        return 0
    except (EvidenceError, OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print(f"Crypto release evidence failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
