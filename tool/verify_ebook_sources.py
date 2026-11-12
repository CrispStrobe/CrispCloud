#!/usr/bin/env python3
"""Verify the immutable ebook Git dependency and the bytes Pub actually uses.

No network access or dependency rewriting. The committed manifest covers every
tracked file, including native sources, browser assets, build hooks and notices.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path, PurePosixPath
from urllib.parse import urljoin, urlsplit
from urllib.request import url2pathname

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = "docs/ebook-source-manifest.json"
REPOSITORY = "https://github.com/CrispStrobe/crisperbooks.git"
PACKAGES = {
    "crisperbooks": ".",
    "crisp_ebook": "packages/crisp_ebook",
    "crisp_ebook_reader": "packages/crisp_ebook_reader",
    "crisp_ebook_conversion": "packages/crisp_ebook_conversion",
}


class SourceError(ValueError):
    pass


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise SourceError(f"Duplicate JSON field: {key}")
        result[key] = value
    return result


def read_json(path):
    try:
        return json.loads(path.read_bytes(), object_pairs_hook=unique_object)
    except (OSError, ValueError, UnicodeError) as error:
        raise SourceError(f"Cannot read {path.name}: {error}") from error


def regular_file(root, relative):
    parts = PurePosixPath(relative).parts
    if (not parts or PurePosixPath(relative).is_absolute()
            or any(part in {".", ".."} for part in parts)
            or "\\" in relative or "/".join(parts) != relative):
        raise SourceError(f"Invalid source path: {relative}")
    path = root.joinpath(*parts)
    if (not path.is_file() or any(root.joinpath(*parts[:end]).is_symlink()
                                 for end in range(1, len(parts) + 1))):
        raise SourceError(f"Missing or redirected source file: {relative}")
    return path


def git(root, *args):
    try:
        return subprocess.check_output(
            ["git", "-C", str(root), *args], stderr=subprocess.PIPE)
    except (OSError, subprocess.CalledProcessError) as error:
        raise SourceError(f"Cannot inspect ebook Git checkout: {error}") from error


def tree_entries(checkout, revision):
    entries = {}
    for item in git(checkout, "ls-tree", "-rz", "--full-tree", revision).split(b"\0"):
        if not item:
            continue
        info, raw_path = item.split(b"\t", 1)
        mode, kind, blob = info.decode().split()
        path = raw_path.decode("utf-8")
        if kind != "blob" or mode not in {"100644", "100755"}:
            raise SourceError(f"Unexpected source type or mode: {path}")
        entries[path] = {"mode": mode, "git_blob": blob}
    return entries


def yaml_block(text, key, indent):
    """Read only the ordinary mappings generated/used by Pub, without YAML deps."""
    prefix = " " * indent
    matches = list(re.finditer(r"^" + prefix + re.escape(key) + r":[ \t]*$",
                               text, re.MULTILINE))
    if len(matches) != 1:
        raise SourceError(f"Expected one dependency mapping for {key}")
    remaining = text[matches[0].end():].lstrip("\r\n")
    lines = []
    for line in remaining.splitlines():
        if line.strip() and not line.lstrip().startswith("#"):
            if len(line) - len(line.lstrip()) <= indent:
                break
        lines.append(line)
    return "\n".join(lines)


def yaml_scalar(block, key, default=None):
    matches = re.findall(r"^[ ]+" + re.escape(key) + r":[ \t]*(.*?)[ \t]*$",
                         block, re.MULTILINE)
    if not matches and default is not None:
        return default
    if len(matches) != 1:
        raise SourceError(f"Expected one dependency value for {key}")
    value = matches[0]
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    return value


def validate_pins(root, manifest):
    pubspec = regular_file(root, "pubspec.yaml").read_text()
    lock = regular_file(root, "pubspec.lock").read_text()
    for name, path in PACKAGES.items():
        section = "dependencies" if name == "crisperbooks" else "dependency_overrides"
        declared = yaml_block(yaml_block(pubspec, section, 0), name, 2)
        declared_git = yaml_block(declared, "git", 4)
        resolved = yaml_block(yaml_block(lock, "packages", 0), name, 2)
        for label, block in (("pubspec", declared_git), ("lockfile", resolved)):
            if (yaml_scalar(block, "url") != REPOSITORY
                    or yaml_scalar(block, "ref") != manifest["revision"]
                    or yaml_scalar(block, "path", ".") != path):
                raise SourceError(f"{name} {label} differs from the reviewed source pin")
        if (yaml_scalar(resolved, "source") != "git"
                or yaml_scalar(resolved, "resolved-ref") != manifest["revision"]):
            raise SourceError(f"{name} does not resolve to the reviewed Git revision")


def resolved_checkout(root):
    config_file = regular_file(root, ".dart_tool/package_config.json")
    config = read_json(config_file)
    packages = config.get("packages", [])
    roots = {}
    for name in PACKAGES:
        matches = [p for p in packages if p.get("name") == name]
        if len(matches) != 1 or not isinstance(matches[0].get("rootUri"), str):
            raise SourceError(f"Resolve {name} with flutter pub get first")
        uri = urlsplit(urljoin(config_file.as_uri(), matches[0]["rootUri"]))
        if uri.scheme != "file" or uri.netloc not in {"", "localhost"} or uri.query or uri.fragment:
            raise SourceError(f"Non-local package root for {name}")
        roots[name] = Path(url2pathname(uri.path)).resolve()
    checkout = roots["crisperbooks"]
    for name, path in PACKAGES.items():
        if roots[name] != (checkout / path).resolve():
            raise SourceError(f"{name} is redirected outside the shared checkout")
    return checkout


def verify(root=ROOT, *, resolve=True):
    root = root.resolve()
    manifest = read_json(regular_file(root, MANIFEST))
    if (manifest.get("schema_version") != 1 or manifest.get("repository") != REPOSITORY
            or manifest.get("packages") != PACKAGES
            or not re.fullmatch(r"[0-9a-f]{40}", manifest.get("revision", ""))
            or not re.fullmatch(r"[0-9a-f]{40}", manifest.get("git_tree", ""))
            or not isinstance(manifest.get("files"), dict) or not manifest["files"]):
        raise SourceError("Invalid ebook source manifest")
    validate_pins(root, manifest)
    if not resolve:
        return {"revision": manifest["revision"], "resolved_bytes_verified": False}
    if (root / "pubspec_overrides.yaml").exists():
        raise SourceError("Remove local dependency overrides before source verification")
    checkout = resolved_checkout(root)
    revision = manifest["revision"]
    if git(checkout, "rev-parse", "HEAD").decode().strip() != revision:
        raise SourceError("Resolved ebook checkout is not at the reviewed revision")
    if git(checkout, "rev-parse", "HEAD^{tree}").decode().strip() != manifest["git_tree"]:
        raise SourceError("Resolved ebook Git tree differs from the manifest")
    entries = tree_entries(checkout, revision)
    if set(entries) != set(manifest["files"]):
        raise SourceError("Ebook source manifest does not cover the complete Git tree")
    for name, expected in manifest["files"].items():
        if any(expected.get(key) != value for key, value in entries[name].items()):
            raise SourceError(f"Ebook Git identity differs: {name}")
        data = regular_file(checkout, name).read_bytes()
        blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data,
                            usedforsecurity=False).hexdigest()
        if (len(data) != expected.get("bytes") or blob != expected["git_blob"]
                or hashlib.sha256(data).hexdigest() != expected.get("sha256")):
            raise SourceError(f"Ebook source bytes differ: {name}")
    untracked = git(checkout, "ls-files", "--others", "--exclude-standard").decode().strip()
    if untracked:
        raise SourceError(f"Unreviewed files in the resolved ebook checkout: {untracked}")
    return {"repository": REPOSITORY, "revision": revision,
            "git_tree": manifest["git_tree"], "files_verified": len(entries),
            "resolved_bytes_verified": True,
            "manifest_sha256": hashlib.sha256((root / MANIFEST).read_bytes()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--pins-only", action="store_true",
                        help="Check committed pins before Pub resolution; not a release byte check")
    args = parser.parse_args()
    try:
        result = verify(args.root, resolve=not args.pins_only)
    except (SourceError, KeyError, TypeError) as error:
        parser.exit(1, f"Ebook source verification failed: {error}\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
