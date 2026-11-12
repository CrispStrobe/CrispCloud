#!/usr/bin/env python3
"""Validate bundled help, or explicitly acknowledge reviewed source changes."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "docs/help/manifest.json"
ASSETS = {
    "en": "docs/USER_GUIDE.md",
    "de": "docs/help/USER_GUIDE.de.md",
    "fr": "docs/help/USER_GUIDE.fr.md",
}
ANCHOR = re.compile(r'^<a id="([a-z][a-z0-9-]{0,79})"></a>\n## ([^\n]+)\n', re.M)


def inspect_guides():
    guides = {}
    for language, asset in ASSETS.items():
        raw = (ROOT / asset).read_bytes()
        if len(raw) > 256 * 1024:
            raise ValueError(f"{language}: guide exceeds 256 KiB")
        markdown = raw.decode("utf-8")
        anchors = ANCHOR.findall(markdown)
        ids = [item[0] for item in anchors]
        if not 1 <= len(ids) <= 64 or len(ids) != len(set(ids)):
            raise ValueError(f"{language}: missing, duplicate or excessive topics")
        if len(re.findall(r"^## ", markdown, re.M)) != len(ids):
            raise ValueError(f"{language}: every topic heading needs a stable anchor")
        for target in re.findall(r"\]\(([^)]+)\)", markdown):
            if target.startswith("#") and target[1:] not in ids:
                raise ValueError(f"{language}: unresolved internal link {target}")
        guides[language] = {"sha256": hashlib.sha256(raw).hexdigest(), "ids": ids}
    for language, guide in guides.items():
        if guide["ids"] != guides["en"]["ids"]:
            raise ValueError(f"{language}: topic IDs/order differ from English")
    return guides


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh-source", action="store_true",
                        help="Update only English's digest; old translations remain stale")
    parser.add_argument("--approve-translation", action="append", choices=["de", "fr"], default=[],
                        help="After content review, update this translation and its source digest")
    args = parser.parse_args()
    guides = inspect_guides()
    manifest = json.loads(MANIFEST.read_text("utf-8")) if MANIFEST.exists() else {
        "version": 1, "sourceLanguage": "en", "guides": {},
    }
    if manifest.get("version") != 1 or manifest.get("sourceLanguage") != "en":
        raise ValueError("Unsupported help manifest")
    entries = manifest["guides"]
    if args.refresh_source:
        entries["en"] = {"asset": ASSETS["en"], "sha256": guides["en"]["sha256"]}
    for language in args.approve_translation:
        if entries.get("en", {}).get("sha256") != guides["en"]["sha256"]:
            raise ValueError("Refresh the English source digest before approving a translation")
        entries[language] = {"asset": ASSETS[language], "sha256": guides[language]["sha256"],
                             "sourceSha256": guides["en"]["sha256"]}
    if args.refresh_source or args.approve_translation:
        MANIFEST.parent.mkdir(parents=True, exist_ok=True)
        MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", "utf-8")
    issues = []
    for language, guide in guides.items():
        entry = entries.get(language, {})
        if entry.get("asset") != ASSETS[language] or entry.get("sha256") != guide["sha256"]:
            issues.append(f"{language}: missing or unreviewed guide bytes")
        if language != "en" and entry.get("sourceSha256") != guides["en"]["sha256"]:
            issues.append(f"{language}: translation is stale against the English source")
    if issues:
        raise ValueError("\n".join(issues))
    print(f"Verified {len(guides)} offline guides with {len(guides['en']['ids'])} matching topics each.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Help validation failed: {error}", file=sys.stderr)
        sys.exit(1)
