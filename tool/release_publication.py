#!/usr/bin/env python3
"""Stage release uploads privately; publish only a complete binary inventory."""

import argparse
import json
import os
import re
import subprocess
from urllib.parse import quote


REQUIRED_ASSETS = frozenset({
    "crispcloud-web.tar.gz",
    "crispcloud-linux-x64.tar.gz",
    "crispcloud-macos.zip",
    "crispcloud-macos.dmg",
    "crispcloud-windows-x64.zip",
    "crispcloud-android.apk",
    "crispcloud-ios-nosign.zip",
    "crispcloud-cli-ubuntu-latest.zip",
    "crispcloud-cli-macos-15.zip",
    "crispcloud-cli-macos-15-intel.zip",
    "crispcloud-cli-windows-latest.zip",
})


def release_info(repo, tag):
    result = subprocess.run(
        ["gh", "api", f"repos/{repo}/releases/tags/{quote(tag, safe='')}"],
        capture_output=True, text=True,
    )
    if result.returncode:
        if "(HTTP 404)" in result.stderr:
            return None
        raise RuntimeError(f"Could not inspect release: {result.stderr.strip()}")
    info = json.loads(result.stdout)
    if info.get("tag_name") != tag:
        raise RuntimeError("Release metadata does not match the requested tag.")
    return info


def prepare(repo, tag, title, notes_file, prerelease=False):
    existing = release_info(repo, tag)
    if existing is not None:
        # Reruns must never delete existing assets or unpublish a release.
        print(f"Keeping existing release {tag} and its assets.")
        return
    command = ["gh", "release", "create", tag, "--repo", repo,
               "--verify-tag", "--draft", "--title", title,
               "--notes-file", notes_file]
    if prerelease:
        command.append("--prerelease")
    subprocess.run(command, check=True)


def publish(repo, tag):
    info = release_info(repo, tag)
    if info is None:
        raise RuntimeError("Release draft is missing; no release was published.")
    sizes = {asset.get("name"): asset.get("size")
             for asset in info.get("assets", [])}
    missing = sorted(name for name in REQUIRED_ASSETS
                     if type(sizes.get(name)) is not int or sizes[name] <= 0)
    if missing:
        raise RuntimeError("Release binaries are missing or empty: " + ", ".join(missing))
    if info.get("draft") is not True:
        print(f"Release {tag} is already published; binary inventory verified.")
        return
    command = ["gh", "release", "edit", tag, "--repo", repo,
               "--verify-tag", "--draft=false"]
    if info.get("prerelease") is not True:
        command.append("--latest")
    subprocess.run(command, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "publish"])
    parser.add_argument("tag")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--title")
    parser.add_argument("--notes-file")
    parser.add_argument("--prerelease", choices=["true", "false"], default="false")
    args = parser.parse_args()
    if not args.repo or not re.fullmatch(r"[\w.-]+/[\w.-]+", args.repo):
        parser.error("Set GITHUB_REPOSITORY or pass --repo owner/name.")
    try:
        if args.action == "prepare":
            if not args.title or not args.notes_file:
                parser.error("prepare requires --title and --notes-file.")
            prepare(args.repo, args.tag, args.title, args.notes_file,
                    args.prerelease == "true")
        else:
            publish(args.repo, args.tag)
    except (RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
