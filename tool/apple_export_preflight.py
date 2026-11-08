#!/usr/bin/env python3
"""Check the exact Apple artifact and read current App Store Connect evidence.

This tool never creates declarations, changes territories, submits a build, or
files anything with a government. The policy is a recorded release decision,
not a legal classification. --check-artifact works without credentials; it does
not approve distribution. Live preflight uses only authenticated GET requests.

Official API references:
https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-appavailabilityv2
https://developer.apple.com/documentation/appstoreconnectapi/get-v2-appavailabilities-_id_-territoryavailabilities
https://developer.apple.com/documentation/appstoreconnectapi/get-v1-appencryptiondeclarations
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import json
import os
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.parsers.expat
import zipfile
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = "docs/apple-export-policy.json"
API_ORIGIN = "https://api.appstoreconnect.apple.com"
MAX_PLIST_BYTES = 1024 * 1024
MAX_RESPONSE_BYTES = 8 * 1024 * 1024
SOURCE_PLISTS = {"ios": "ios/Runner/Info.plist", "macos": "macos/Runner/Info.plist"}
BUILT_PLATFORMS = {"ios": "iPhoneOS", "macos": "MacOSX"}
API_PLATFORMS = {"ios": "IOS", "macos": "MAC_OS"}
# These are Apple's documented restriction statuses, not proof of exclusion on
# their own. We require available=false separately. Active/pending and unknown
# statuses fail closed. An old release date is permitted after that check.
# https://developer.apple.com/documentation/appstoreconnectapi/territoryavailability/attributes-data.dictionary
RESTRICTED_TERRITORY_STATUSES = set("""
MISSING_RATING CANNOT_SELL_RESTRICTED_RATING BRAZIL_REQUIRED_TAX_ID
BRAZIL_GAMBLING_NOT_VERIFIED MISSING_GRN UNVERIFIED_GRN ICP_NUMBER_INVALID
ICP_NUMBER_MISSING TRADER_STATUS_NOT_PROVIDED TRADER_STATUS_VERIFICATION_FAILED
TRADER_STATUS_VERIFICATION_STATUS_MISSING CANNOT_SELL_SEVENTEEN_PLUS_APPS
CANNOT_SELL_SEXUALLY_EXPLICIT CANNOT_SELL_NON_IOS_GAMES
CANNOT_SELL_SEVENTEEN_PLUS_GAMES CANNOT_SELL_CASINO CANNOT_SELL_CASINO_WITHOUT_GRAC
CANNOT_SELL_CASINO_WITHOUT_AGE_VERIFICATION CANNOT_SELL_ADULT_ONLY
CANNOT_SELL_GAMBLING_CONTESTS CANNOT_SELL_GAMBLING CANNOT_SELL_CONTESTS
CANNOT_SELL_NINETEEN_PLUS_WITHOUT_GRAC CANNOT_SELL
CANNOT_SELL_FREQUENT_INTENSE_GAMBLING CANNOT_SELL_FREQUENT_INTENSE_ALCOHOL_TOBACCO_DRUGS
CANNOT_SELL_FREQUENT_INTENSE_VIOLENCE CANNOT_SELL_FREQUENT_INTENSE_SEXUAL_CONTENT_NUDITY
CANNOT_SELL_INFREQUENT_MILD_ALCOHOL_TOBACCO_DRUGS
CANNOT_SELL_INFREQUENT_MILD_SEXUAL_CONTENT_NUDITY CANNOT_SELL_FREQUENT_INTENSE
CANNOT_SELL_FREQUENT_INTENSE_WITHOUT_GRAC CANNOT_SELL_FREQUENT_GAMBLING
CANNOT_SELL_FREQUENT_ALCOHOL_TOBACCO_DRUGS CANNOT_SELL_FREQUENT_VIOLENCE
CANNOT_SELL_FREQUENT_SEXUAL_CONTENT_NUDITY CANNOT_SELL_INFREQUENT_ALCOHOL_TOBACCO_DRUGS
CANNOT_SELL_INFREQUENT_SEXUAL_CONTENT_NUDITY CANNOT_SELL_FREQUENT
CANNOT_SELL_FREQUENT_WITHOUT_GRAC
""".split())


class PreflightError(ValueError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise PreflightError(f"Duplicate JSON field: {key}")
        result[key] = value
    return result


def decode_json(data: bytes | str) -> dict:
    try:
        value = json.loads(data, object_pairs_hook=unique_object)
    except (ValueError, UnicodeError) as error:
        raise PreflightError("Invalid JSON evidence") from error
    if not isinstance(value, dict):
        raise PreflightError("JSON evidence must be an object")
    return value


def text_value(value) -> bool:
    return isinstance(value, str) and bool(value.strip()) and value == value.strip()


def source_file(root: Path, relative: str) -> Path:
    path = root / relative
    if (Path(relative).is_absolute() or not path.is_file() or path.is_symlink()
            or not path.resolve().is_relative_to(root.resolve())):
        raise PreflightError(f"Expected a regular repository file: {relative}")
    return path


def reviewed_source_sha256(root: Path) -> str:
    """Bind the inventory's reviewed paths to the actual reviewed file bytes."""
    inventory = decode_json(source_file(root, "docs/crypto-inventory.json").read_bytes())
    paths = inventory.get("reviewed_files")
    if (not isinstance(paths, list) or not paths or not all(text_value(path) for path in paths)
            or len(paths) != len(set(paths))):
        raise PreflightError("Crypto inventory needs a nonempty, unique reviewed_files list")
    hashes = {name: sha256(source_file(root, name)) for name in sorted(paths)}
    canonical = json.dumps(hashes, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def validate_policy(root: Path, submission: bool = False) -> dict:
    """Validate source facts separately from facts needed to submit a build."""
    policy = decode_json(source_file(root, POLICY_PATH).read_bytes())
    if type(policy.get("schema_version")) is not int or policy["schema_version"] != 1:
        raise PreflightError("Unsupported Apple export policy schema")
    try:
        reviewed = policy["reviewed_on"]
        if not isinstance(reviewed, str) or dt.date.fromisoformat(reviewed).isoformat() != reviewed:
            raise ValueError("invalid date")
    except (KeyError, ValueError, TypeError) as error:
        raise PreflightError("Apple export policy needs an ISO reviewed_on date") from error
    if not text_value(policy.get("bundle_id")):
        raise PreflightError("Apple export policy needs its exact bundle_id")
    if type(policy.get("uses_non_exempt_encryption")) is not bool:
        raise PreflightError("uses_non_exempt_encryption must be a Boolean")
    for field, relative in (("inventory_sha256", "docs/crypto-inventory.json"),
                            ("pubspec_lock_sha256", "pubspec.lock")):
        expected = policy.get(field)
        if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
            raise PreflightError(f"Apple export policy needs a SHA-256 value for {field}")
        if sha256(source_file(root, relative)) != expected:
            raise PreflightError(f"Apple export review is stale: {relative} changed; review and update the policy")
    expected_source = policy.get("reviewed_source_sha256")
    if not isinstance(expected_source, str) or not re.fullmatch(r"[0-9a-f]{64}", expected_source):
        raise PreflightError("Apple export policy needs a SHA-256 value for reviewed_source_sha256")
    if reviewed_source_sha256(root) != expected_source:
        raise PreflightError("Apple export review is stale: reviewed crypto source changed; review and update the policy")
    documentation = policy.get("documentation")
    france = policy.get("france")
    if not isinstance(documentation, dict) or not isinstance(france, dict):
        raise PreflightError("Apple export policy needs documentation and france objects")
    status = documentation.get("status")
    if status not in {"unreviewed", "not_required", "approved"}:
        raise PreflightError("Unsupported Apple documentation status")
    if status != "unreviewed" and not text_value(documentation.get("reference")):
        raise PreflightError("A reviewed Apple documentation decision needs an evidence reference")
    if france.get("store_availability") not in {"excluded", "included"}:
        raise PreflightError("France store availability must be excluded or included")
    history = france.get("prior_distribution_review")
    if history not in {"pending", "no_prior_distribution", "covered"}:
        raise PreflightError("Unsupported France prior_distribution_review status")
    if history != "pending" and not text_value(france.get("reference")):
        raise PreflightError("The France distribution review needs an evidence reference")
    non_exempt = policy["uses_non_exempt_encryption"]
    code = documentation.get("compliance_code")
    if non_exempt:
        if status == "not_required":
            raise PreflightError("A non-exempt declaration cannot use the no-documentation route")
        if status == "approved" and not text_value(code):
            raise PreflightError("An approved declaration needs the Apple-issued compliance_code")
    else:
        if status == "approved" or code is not None:
            raise PreflightError("The no-documentation answer must not carry an Apple compliance code")
        if france["store_availability"] != "excluded":
            raise PreflightError("This app's bundled encryption needs reviewed documentation before France inclusion")
    if submission:
        if status == "unreviewed":
            raise PreflightError("Complete the truthful Apple encryption questionnaire and record its result before upload")
        if history == "pending":
            raise PreflightError(
                "French distribution history is unverified. Confirm and record no prior French distribution "
                "or complete the French documentation and Apple-approved-code route; current territory "
                "exclusion alone does not stop updates to prior French users."
            )
        if not non_exempt and history != "no_prior_distribution":
            raise PreflightError("Prior French distribution requires the documented Apple-approved route, not this no-France shortcut")
    return policy


def validate_encryption_plist(plist: dict, policy: dict, label: str) -> None:
    expected = policy["uses_non_exempt_encryption"]
    if plist.get("ITSAppUsesNonExemptEncryption") is not expected:
        raise PreflightError(f"ITSAppUsesNonExemptEncryption in {label} disagrees with the reviewed policy")
    code = policy["documentation"].get("compliance_code")
    if expected:
        if not text_value(code) or plist.get("ITSEncryptionExportComplianceCode") != code:
            raise PreflightError(f"ITSEncryptionExportComplianceCode in {label} must match the reviewed Apple-issued code")
    elif "ITSEncryptionExportComplianceCode" in plist:
        raise PreflightError(f"The no-documentation answer in {label} must not contain ITSEncryptionExportComplianceCode")


def load_plist(data: bytes, label: str) -> dict:
    if not data or len(data) > MAX_PLIST_BYTES:
        raise PreflightError(f"Missing or oversized Info.plist: {label}")
    try:
        value = plistlib.loads(data)
    except (ValueError, TypeError, plistlib.InvalidFileException, OverflowError, xml.parsers.expat.ExpatError) as error:
        raise PreflightError(f"Invalid Info.plist: {label}") from error
    if not isinstance(value, dict):
        raise PreflightError(f"Info.plist must be a dictionary: {label}")
    return value


def validate_source_plist(root: Path, relative: str, policy: dict) -> dict:
    if relative not in SOURCE_PLISTS.values():
        raise PreflightError(f"Unexpected Apple source plist: {relative}")
    data = source_file(root, relative).read_bytes()
    plist = load_plist(data, relative)
    validate_encryption_plist(plist, policy, relative)
    return {"path": relative, "sha256": hashlib.sha256(data).hexdigest(),
            "uses_non_exempt_encryption": plist["ITSAppUsesNonExemptEncryption"],
            "compliance_code": plist.get("ITSEncryptionExportComplianceCode")}


def main_app_plist(name: str, platform: str, ipa: bool = False) -> bool:
    parts = PurePosixPath(name).parts
    if ipa:
        return len(parts) == 3 and parts[0] == "Payload" and parts[1].endswith(".app") and parts[2] == "Info.plist"
    suffix = ("Info.plist",) if platform == "ios" else ("Contents", "Info.plist")
    for index, component in enumerate(parts):
        if component.endswith(".app"):
            # Ignore nested watch/helper apps; there must be exactly one main app.
            return parts[index + 1:] == suffix
    return False


def plist_from_zip(artifact: Path, platform: str) -> tuple[bytes, str]:
    try:
        with zipfile.ZipFile(artifact) as archive:
            entries = archive.infolist()
            names = [entry.filename for entry in entries]
            if len(names) != len(set(names)):
                raise PreflightError("Apple archive contains duplicate member names")
            for name in names:
                if (name.startswith("/") or "\\" in name
                        or ".." in PurePosixPath(name).parts):
                    raise PreflightError("Apple archive contains an unsafe member path")
            matches = [entry for entry in entries
                       if main_app_plist(entry.filename, platform, artifact.suffix.lower() == ".ipa")]
            if len(matches) != 1:
                raise PreflightError("Apple archive must contain exactly one main application Info.plist")
            member = matches[0]
            if stat.S_ISLNK(member.external_attr >> 16) or member.is_dir() or member.file_size > MAX_PLIST_BYTES:
                raise PreflightError("Apple archive Info.plist must be a bounded regular file")
            with archive.open(member) as source:
                return source.read(MAX_PLIST_BYTES + 1), member.filename
    except (zipfile.BadZipFile, RuntimeError) as error:
        raise PreflightError("Cannot read the built Apple ZIP/IPA artifact") from error


def plist_from_pkg(artifact: Path) -> tuple[bytes, str]:
    # pkgutil expands the installer; it does not install it or execute its scripts.
    with tempfile.TemporaryDirectory(prefix="crispcloud-export-pkg-") as directory:
        expanded = Path(directory) / "expanded"
        try:
            subprocess.run(["/usr/sbin/pkgutil", "--expand-full", str(artifact.resolve()), str(expanded)],
                           check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
        except (OSError, subprocess.SubprocessError) as error:
            raise PreflightError("Cannot inspect the .pkg: run on macOS with a valid package and pkgutil") from error
        matches = [path for path in expanded.rglob("Info.plist")
                   if main_app_plist(path.relative_to(expanded).as_posix(), "macos")]
        if len(matches) != 1:
            raise PreflightError("Package must contain exactly one main application Info.plist")
        path = matches[0]
        relative = path.relative_to(expanded)
        if (not path.resolve().is_relative_to(expanded.resolve())
                or any(expanded.joinpath(*relative.parts[:end]).is_symlink()
                       for end in range(1, len(relative.parts) + 1))
                or not path.is_file() or path.stat().st_size > MAX_PLIST_BYTES):
            raise PreflightError("Package Info.plist must be a bounded regular file inside the package")
        return path.read_bytes(), relative.as_posix()


def release_version(root: Path) -> tuple[str, str]:
    matches = re.findall(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$",
                         source_file(root, "pubspec.yaml").read_text(), re.MULTILINE)
    if len(matches) != 1:
        raise PreflightError("Expected one explicit marketing version and build number in pubspec.yaml")
    return matches[0]


def verify_artifact(root: Path, platform: str, artifact: Path, policy: dict | None = None) -> dict:
    if platform not in SOURCE_PLISTS:
        raise PreflightError("Only iOS and macOS artifacts are supported")
    policy = validate_policy(root) if policy is None else policy
    validate_source_plist(root, SOURCE_PLISTS[platform], policy)
    if artifact.is_symlink() or not artifact.is_file() or artifact.stat().st_size == 0:
        raise PreflightError("Expected a nonempty regular Apple artifact")
    digest = sha256(artifact)
    if artifact.suffix.lower() == ".pkg" and platform == "macos":
        data, member = plist_from_pkg(artifact)
    elif artifact.suffix.lower() == ".zip" or (artifact.suffix.lower() == ".ipa" and platform == "ios"):
        data, member = plist_from_zip(artifact, platform)
    else:
        raise PreflightError("Expected an iOS .ipa, macOS .pkg, or an application .zip")
    plist = load_plist(data, member)
    validate_encryption_plist(plist, policy, member)
    version, build = release_version(root)
    expected = {"CFBundleIdentifier": policy["bundle_id"], "CFBundleShortVersionString": version,
                "CFBundleVersion": build, "CFBundlePackageType": "APPL"}
    for key, value in expected.items():
        if plist.get(key) != value:
            raise PreflightError(f"Built {key} does not match this release's reviewed {platform} application")
    if plist.get("CFBundleSupportedPlatforms") != [BUILT_PLATFORMS[platform]]:
        raise PreflightError(f"Built CFBundleSupportedPlatforms is not the expected {platform} device platform")
    if sha256(artifact) != digest:
        raise PreflightError("Apple artifact changed during inspection")
    return {"name": artifact.name, "bytes": artifact.stat().st_size, "sha256": digest,
            "info_plist_member": member, "info_plist_sha256": hashlib.sha256(data).hexdigest(),
            "bundle_id": policy["bundle_id"], "version": version, "build": build,
            "platform": platform, "uses_non_exempt_encryption": policy["uses_non_exempt_encryption"],
            "compliance_code": plist.get("ITSEncryptionExportComplianceCode")}


def api_url(value: str, expected_path: str | None = None) -> str:
    if not isinstance(value, str) or not value or value != value.strip() or "\\" in value:
        raise PreflightError("Invalid App Store Connect URL")
    url = urllib.parse.urljoin(API_ORIGIN + "/", value)
    parsed = urllib.parse.urlsplit(url)
    if (parsed.scheme != "https" or parsed.netloc != "api.appstoreconnect.apple.com"
            or parsed.fragment or not parsed.path.startswith(("/v1/", "/v2/"))
            or any(ord(char) < 32 for char in value)):
        raise PreflightError("Refusing an App Store Connect URL outside the exact HTTPS API origin")
    if expected_path is not None and parsed.path != expected_path:
        raise PreflightError("Refusing pagination to a different App Store Connect endpoint")
    return url


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward a bearer token to a redirect, even within the same host.
        raise PreflightError("App Store Connect redirected a request; no release approval recorded")


def base64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def raw_ecdsa_signature(der: bytes) -> bytes:
    """Convert OpenSSL's bounded DER P-256 signature to JWT's fixed-width r||s."""
    if len(der) < 8 or der[0] != 0x30 or der[1] != len(der) - 2 or der[1] >= 128:
        raise PreflightError("OpenSSL returned an invalid ES256 signature")
    offset, result = 2, bytearray()
    for _ in range(2):
        if offset + 2 > len(der) or der[offset] != 2:
            raise PreflightError("OpenSSL returned an invalid ES256 integer")
        length = der[offset + 1]
        offset += 2
        value = der[offset:offset + length]
        if (not 1 <= length <= 33 or len(value) != length or value[0] & 0x80
                or (length > 1 and value[0] == 0 and value[1] < 0x80)):
            raise PreflightError("OpenSSL returned a noncanonical ES256 integer")
        number = int.from_bytes(value, "big")
        if not 0 < number < 2 ** 256:
            raise PreflightError("OpenSSL signature is not an ES256 value")
        result.extend(number.to_bytes(32, "big"))
        offset += length
    if offset != len(der):
        raise PreflightError("OpenSSL returned trailing ES256 signature bytes")
    return bytes(result)


class AppStoreConnect:
    """Small GET-only client. Tokens and document download URLs are never saved."""

    def __init__(self, key_id: str, issuer_id: str, key_path: Path, opener=None):
        if not text_value(key_id) or not text_value(issuer_id):
            raise PreflightError("ASC_KEY_ID and ASC_ISSUER_ID are required for live preflight")
        self.key_id, self.issuer_id, self.key_path = key_id, issuer_id, key_path
        self.opener = opener or urllib.request.build_opener(NoRedirect())

    def jwt(self) -> str:
        now = int(time.time())
        header = base64url(json.dumps({"alg": "ES256", "kid": self.key_id, "typ": "JWT"}).encode())
        claims = base64url(json.dumps({"iss": self.issuer_id, "iat": now - 20, "exp": now + 600,
                                       "aud": "appstoreconnect-v1"}).encode())
        payload = f"{header}.{claims}"
        try:
            result = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(self.key_path),
                                     "-passin", "pass:"], input=payload.encode("ascii"),
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=20)
        except (OSError, subprocess.SubprocessError) as error:
            raise PreflightError("Could not sign App Store Connect authentication with the configured .p8 key") from error
        return f"{payload}.{base64url(raw_ecdsa_signature(result.stdout))}"

    def get(self, path: str, query: dict | None = None) -> dict:
        url = api_url(path)
        if query:
            if urllib.parse.urlsplit(url).query:
                raise PreflightError("Cannot combine an existing API query with new parameters")
            url += "?" + urllib.parse.urlencode(query)
        request = urllib.request.Request(url, headers={"Authorization": f"Bearer {self.jwt()}",
                                                      "Accept": "application/json"}, method="GET")
        try:
            with self.opener.open(request, timeout=30) as response:
                data = response.read(MAX_RESPONSE_BYTES + 1)
        except urllib.error.HTTPError as error:
            raise PreflightError(f"App Store Connect GET {urllib.parse.urlsplit(url).path} failed (HTTP {error.code})") from error
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            raise PreflightError("App Store Connect could not be read; no release approval recorded") from error
        if len(data) > MAX_RESPONSE_BYTES:
            raise PreflightError("App Store Connect response exceeded the evidence size limit")
        return decode_json(data)

    def all_pages(self, path: str, query: dict | None = None) -> list[dict]:
        url = api_url(path)
        if query:
            url += "?" + urllib.parse.urlencode(query)
        expected_path = urllib.parse.urlsplit(url).path
        seen_urls, seen_ids, records = set(), set(), []
        reported_total = None
        for _ in range(100):
            url = api_url(url, expected_path)
            if url in seen_urls:
                raise PreflightError("App Store Connect pagination repeated a page")
            seen_urls.add(url)
            page = self.get(url)
            data, links = page.get("data"), page.get("links")
            if not isinstance(data, list) or not isinstance(links, dict):
                raise PreflightError("App Store Connect returned an incomplete paginated response")
            total = page.get("meta", {}).get("paging", {}).get("total")
            if total is not None:
                if type(total) is not int or total < 0 or (reported_total is not None and total != reported_total):
                    raise PreflightError("App Store Connect pagination changed its total")
                reported_total = total
            for item in data:
                if not isinstance(item, dict) or not text_value(item.get("id")) or not text_value(item.get("type")):
                    raise PreflightError("App Store Connect returned an invalid resource")
                identity = (item["type"], item["id"])
                if identity in seen_ids:
                    raise PreflightError("App Store Connect returned duplicate resources across pages")
                seen_ids.add(identity)
                records.append(item)
            next_page = links.get("next")
            if next_page is None:
                if reported_total is not None and len(records) != reported_total:
                    raise PreflightError("App Store Connect pagination did not return every resource")
                return records
            if not isinstance(next_page, str) or not next_page:
                raise PreflightError("App Store Connect returned an invalid pagination link")
            url = next_page
        raise PreflightError("App Store Connect pagination exceeded the evidence page limit")


def verify_france_exclusion(attributes: dict) -> None:
    """Require explicit current exclusion without an active or pending release."""
    if attributes.get("available") is not False:
        raise PreflightError("France does not have explicit current store exclusion")
    preorder = attributes.get("preOrderEnabled")
    statuses = attributes.get("contentStatuses")
    if (preorder is not None and preorder is not False) or (statuses is not None and (
            not isinstance(statuses, list) or not all(isinstance(item, str) and item in RESTRICTED_TERRITORY_STATUSES
                                                     for item in statuses))):
        raise PreflightError("France has scheduled, preorder, or unresolved availability; verify exclusion before upload")
    now = dt.datetime.now(dt.timezone.utc)
    for field in ("releaseDate", "preOrderPublishDate"):
        value = attributes.get(field)
        if value is None:
            continue
        try:
            if not isinstance(value, str) or not value:
                raise ValueError("invalid date")
            if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
                future = dt.date.fromisoformat(value) > now.date()
            else:
                parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
                if parsed.tzinfo is None:
                    raise ValueError("date-time needs a timezone")
                future = parsed > now
        except (ValueError, TypeError) as error:
            raise PreflightError(f"France has an unrecognized {field}; verify availability before upload") from error
        if future:
            raise PreflightError("France has scheduled, preorder, or unresolved availability; verify exclusion before upload")


def live_store_evidence(client: AppStoreConnect, platform: str, policy: dict,
                        expected_app_id: str | None = None) -> dict:
    apps = client.all_pages("/v1/apps", {"filter[bundleId]": policy["bundle_id"],
                                        "fields[apps]": "bundleId", "limit": 2})
    if (len(apps) != 1 or apps[0].get("type") != "apps"
            or apps[0].get("attributes", {}).get("bundleId") != policy["bundle_id"]):
        raise PreflightError("App Store Connect must resolve exactly the reviewed bundle ID")
    app_id = apps[0]["id"]
    if expected_app_id and app_id != expected_app_id:
        raise PreflightError("Resolved App Store Connect app ID differs from ASC_APP_ID; verify the workflow's app identity")
    availability = client.get(f"/v1/apps/{urllib.parse.quote(app_id, safe='')}/appAvailabilityV2").get("data")
    if not isinstance(availability, dict) or availability.get("type") != "appAvailabilities" or not text_value(availability.get("id")):
        raise PreflightError("App Store Connect has no verifiable app availability record")
    availability_id = availability["id"]
    territories = client.all_pages(
        f"/v2/appAvailabilities/{urllib.parse.quote(availability_id, safe='')}/territoryAvailabilities",
        {"include": "territory", "fields[territoryAvailabilities]":
         "available,releaseDate,preOrderEnabled,preOrderPublishDate,contentStatuses,territory", "limit": 200},
    )
    france_records = []
    territory_ids = set()
    for item in territories:
        relation = item.get("relationships", {}).get("territory", {}).get("data")
        if (item.get("type") != "territoryAvailabilities" or not isinstance(relation, dict)
                or relation.get("type") != "territories" or not text_value(relation.get("id"))):
            raise PreflightError("App Store Connect returned an unidentifiable territory availability")
        territory = relation["id"]
        if territory in territory_ids:
            raise PreflightError("App Store Connect returned duplicate territory availability")
        territory_ids.add(territory)
        if territory == "FRA":
            france_records.append(item)
    if len(france_records) != 1:
        raise PreflightError("France must have one explicit availability record; absence is not evidence of exclusion")
    attributes = france_records[0].get("attributes", {})
    expected_available = policy["france"]["store_availability"] == "included"
    if attributes.get("available") is not expected_available:
        raise PreflightError("Live French App Store availability disagrees with the reviewed release policy")
    if not expected_available:
        verify_france_exclusion(attributes)
    declaration_evidence = None
    if policy["uses_non_exempt_encryption"]:
        declarations = client.all_pages("/v1/appEncryptionDeclarations", {
            "filter[app]": app_id, "include": "app", "fields[apps]": "bundleId", "limit": 200,
            "fields[appEncryptionDeclarations]":
            "codeValue,appEncryptionDeclarationState,availableOnFrenchStore,platform,usesEncryption,exempt,app",
        })
        matches = [item for item in declarations if item.get("attributes", {}).get("codeValue")
                   == policy["documentation"]["compliance_code"]]
        if len(matches) != 1:
            raise PreflightError("The built Apple compliance code does not identify one declaration for this app")
        declaration = matches[0]
        attrs = declaration.get("attributes", {})
        app_relation = declaration.get("relationships", {}).get("app", {}).get("data", {})
        if (declaration.get("type") != "appEncryptionDeclarations" or app_relation.get("type") != "apps"
                or app_relation.get("id") != app_id or attrs.get("appEncryptionDeclarationState") != "APPROVED"
                or attrs.get("usesEncryption") is not True or attrs.get("exempt") is not False):
            raise PreflightError("The code must reference an APPROVED non-exempt declaration for the same app")
        declared_platform = attrs.get("platform")
        # Apple's platform field/filter is deprecated. Absent means the
        # app-level declaration; a present platform must still match the build.
        if declared_platform is not None and str(declared_platform).upper() != API_PLATFORMS[platform]:
            raise PreflightError("Apple declaration platform does not match the built application")
        french_coverage_needed = expected_available or policy["france"]["prior_distribution_review"] == "covered"
        if french_coverage_needed and attrs.get("availableOnFrenchStore") is not True:
            raise PreflightError("Apple declaration does not cover the reviewed French distribution")
        declaration_evidence = {"id": declaration["id"], "state": attrs["appEncryptionDeclarationState"],
                                "platform": declared_platform, "available_on_french_store": attrs.get("availableOnFrenchStore"),
                                "code": attrs["codeValue"]}
    return {"app_id": app_id, "bundle_id": policy["bundle_id"], "availability_id": availability_id,
            "territories_read": len(territories), "france": {name: attributes.get(name) for name in
            ("available", "preOrderEnabled", "releaseDate", "preOrderPublishDate", "contentStatuses")},
            "approved_declaration": declaration_evidence}


def preflight(root: Path, platform: str, artifact: Path, client: AppStoreConnect,
              expected_app_id: str | None = None) -> dict:
    policy = validate_policy(root, submission=True)
    policy_hash = sha256(source_file(root, POLICY_PATH))
    built = verify_artifact(root, platform, artifact, policy)
    store = live_store_evidence(client, platform, policy, expected_app_id)
    if sha256(artifact) != built["sha256"] or sha256(source_file(root, POLICY_PATH)) != policy_hash:
        raise PreflightError("Artifact or release policy changed during live preflight")
    validate_policy(root, submission=True)
    return {"schema_version": 1, "purpose": "Engineering release preflight; not a legal classification or filing",
            "live_store_checked": True, "checked_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            "policy_sha256": policy_hash, "inventory_sha256": policy["inventory_sha256"],
            "pubspec_lock_sha256": policy["pubspec_lock_sha256"],
            "reviewed_source_sha256": policy["reviewed_source_sha256"], "artifact": built, "app_store_connect": store}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=sorted(SOURCE_PLISTS), required=True)
    parser.add_argument("--artifact", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("build/export-compliance/apple-export-preflight.json"))
    parser.add_argument("--expected-app-id", default=os.environ.get("ASC_APP_ID"))
    parser.add_argument("--check-artifact", action="store_true", help="Offline artifact check; does not approve distribution")
    args = parser.parse_args(argv)
    try:
        if args.check_artifact:
            result = {"schema_version": 1, "purpose": "Offline artifact verification only; not distribution approval",
                      "live_store_checked": False, "checked_at": dt.datetime.now(dt.timezone.utc).isoformat(),
                      "artifact": verify_artifact(ROOT, args.platform, args.artifact)}
        else:
            # Check the decision before reading credentials or making any request.
            validate_policy(ROOT, submission=True)
            key_path = os.environ.get("ASC_KEY_PATH")
            if not key_path:
                raise PreflightError("ASC_KEY_PATH is required for live preflight")
            client = AppStoreConnect(os.environ.get("ASC_KEY_ID", ""), os.environ.get("ASC_ISSUER_ID", ""), Path(key_path))
            result = preflight(ROOT, args.platform, args.artifact, client, args.expected_app_id)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"Apple {'artifact checked (offline only)' if args.check_artifact else 'live preflight passed'}; evidence: {args.output}")
        return 0
    except (PreflightError, OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        print(f"Apple export preflight failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
