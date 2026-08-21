#!/usr/bin/env python3
"""Probe and synchronize CrispCloud through the Google Play Publishing API."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any
from urllib.parse import quote

from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account


PACKAGE = "com.crispstrobe.cloud"
API = "https://androidpublisher.googleapis.com/androidpublisher/v3"
UPLOAD_API = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3"
ROOT = Path(__file__).resolve().parents[1]
STORE = ROOT / "store" / "google_play"


class PlayApi:
    def __init__(self, credential_file: str) -> None:
        credentials = service_account.Credentials.from_service_account_file(
            credential_file,
            scopes=["https://www.googleapis.com/auth/androidpublisher"],
        )
        self.session = AuthorizedSession(credentials)

    def request(self, method: str, url: str, **kwargs: Any) -> Any:
        response = self.session.request(method, url, timeout=180, **kwargs)
        if not response.ok:
            detail = response.text[:2000]
            raise RuntimeError(f"Play API {method} failed ({response.status_code}): {detail}")
        if not response.content:
            return None
        return response.json()

    def edit_url(self, edit_id: str, suffix: str = "") -> str:
        return f"{API}/applications/{PACKAGE}/edits/{edit_id}{suffix}"

    def create_edit(self) -> str:
        result = self.request("POST", f"{API}/applications/{PACKAGE}/edits", json={})
        return str(result["id"])

    def delete_edit(self, edit_id: str) -> None:
        self.request("DELETE", self.edit_url(edit_id))

    def commit_edit(self, edit_id: str) -> None:
        self.request("POST", self.edit_url(edit_id, ":commit"), json={})

    def validate_edit(self, edit_id: str) -> None:
        self.request("POST", self.edit_url(edit_id, ":validate"), json={})


def read_text(relative: str) -> str:
    return (STORE / relative).read_text(encoding="utf-8").strip()


def probe(api: PlayApi) -> None:
    edit_id = api.create_edit()
    try:
        bundles = api.request("GET", api.edit_url(edit_id, "/bundles")) or {}
        tracks = api.request("GET", api.edit_url(edit_id, "/tracks")) or {}
        listings = api.request("GET", api.edit_url(edit_id, "/listings")) or {}
        details = api.request("GET", api.edit_url(edit_id, "/details")) or {}
        summary = {
            "package": PACKAGE,
            "bundles": [
                {
                    "versionCode": item.get("versionCode"),
                    "sha256": item.get("sha256", "")[:16] + "…",
                }
                for item in bundles.get("bundles", [])
            ],
            "tracks": [
                {
                    "track": item.get("track"),
                    "releases": [
                        {
                            "name": release.get("name"),
                            "status": release.get("status"),
                            "versionCodes": release.get("versionCodes", []),
                        }
                        for release in item.get("releases", [])
                    ],
                }
                for item in tracks.get("tracks", [])
            ],
            "listingLanguages": [
                item.get("language") for item in listings.get("listings", [])
            ],
            "details": details,
        }
        print(json.dumps(summary, indent=2, sort_keys=True))
    finally:
        api.delete_edit(edit_id)


def upload_image(api: PlayApi, edit_id: str, language: str, image_type: str, path: Path) -> None:
    encoded_language = quote(language, safe="")
    encoded_type = quote(image_type, safe="")
    url = (
        f"{UPLOAD_API}/applications/{PACKAGE}/edits/{edit_id}/listings/"
        f"{encoded_language}/{encoded_type}?uploadType=media"
    )
    api.request(
        "POST",
        url,
        data=path.read_bytes(),
        headers={"Content-Type": "image/png"},
    )


def sync_listing(api: PlayApi) -> None:
    edit_id = api.create_edit()
    committed = False
    try:
        api.request(
            "PUT",
            api.edit_url(edit_id, "/details"),
            json={
                "defaultLanguage": "en-US",
                "contactWebsite": "https://www.crispstro.be",
                "contactEmail": "cstr+privacy@mailbox.org",
            },
        )
        for language in ("en-US", "de-DE"):
            base = f"metadata/{language}"
            api.request(
                "PUT",
                api.edit_url(edit_id, f"/listings/{language}"),
                json={
                    "language": language,
                    "title": read_text(f"{base}/title.txt"),
                    "shortDescription": read_text(f"{base}/short-description.txt"),
                    "fullDescription": read_text(f"{base}/full-description.txt"),
                },
            )
            image_sets = {
                "icon": [STORE / "assets" / "icon-512.png"],
                "featureGraphic": [STORE / "assets" / "feature-graphic-1024x500.png"],
                "phoneScreenshots": sorted((STORE / "assets" / "phone").glob("*.png")),
            }
            for image_type, paths in image_sets.items():
                api.request(
                    "DELETE",
                    api.edit_url(edit_id, f"/listings/{language}/{image_type}"),
                )
                for path in paths:
                    upload_image(api, edit_id, language, image_type, path)
        api.validate_edit(edit_id)
        api.commit_edit(edit_id)
        committed = True
        print("Committed localized listings, contact details, and graphics.")
    finally:
        if not committed:
            api.delete_edit(edit_id)


def configure_closed(api: PlayApi, track: str, version_code: str, status: str) -> None:
    edit_id = api.create_edit()
    committed = False
    try:
        release_notes = [
            {"language": language, "text": read_text(f"metadata/{language}/release-notes.txt")}
            for language in ("en-US", "de-DE")
        ]
        api.request(
            "PUT",
            api.edit_url(edit_id, f"/tracks/{quote(track, safe='')}"),
            json={
                "track": track,
                "releases": [
                    {
                        "name": "CrispCloud 1.0.0 closed beta",
                        "versionCodes": [version_code],
                        "releaseNotes": release_notes,
                        "status": status,
                    }
                ],
            },
        )
        api.validate_edit(edit_id)
        api.commit_edit(edit_id)
        committed = True
        print(f"Configured version {version_code} on closed track {track} with status {status}.")
    finally:
        if not committed:
            api.delete_edit(edit_id)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("probe", "sync-listing", "configure-closed"))
    parser.add_argument("--credentials", required=True)
    parser.add_argument("--track", default="alpha")
    parser.add_argument("--version-code", default="7")
    parser.add_argument("--status", choices=("draft", "completed"), default="draft")
    args = parser.parse_args()

    api = PlayApi(args.credentials)
    if args.command == "probe":
        probe(api)
    elif args.command == "sync-listing":
        sync_listing(api)
    else:
        configure_closed(api, args.track, args.version_code, args.status)


if __name__ == "__main__":
    main()
