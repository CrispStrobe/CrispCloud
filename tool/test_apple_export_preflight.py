"""Release-policy, artifact and live-response failure tests; no Apple account used."""

import base64
import copy
import datetime as dt
import hashlib
import io
import json
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

import apple_export_preflight as preflight


def territory(territory_id="FRA", **attributes):
    return {"type": "territoryAvailabilities", "id": "availability-" + territory_id,
            "attributes": {"available": False, "preOrderEnabled": False, "releaseDate": None,
                           "preOrderPublishDate": None, "contentStatuses": [], **attributes},
            "relationships": {"territory": {"data": {"type": "territories", "id": territory_id}}}}


class FakeStore:
    def __init__(self):
        self.calls = []
        self.apps = [{"id": "123", "type": "apps", "attributes": {"bundleId": "com.example.cloud"}}]
        self.availability = {"data": {"id": "availability", "type": "appAvailabilities"}}
        self.territories = [territory("USA", available=True), territory()]
        self.declarations = []

    def get(self, path, query=None):
        self.calls.append(path)
        if path == "/v1/apps/123/appAvailabilityV2":
            return copy.deepcopy(self.availability)
        raise AssertionError(f"Unexpected GET: {path}")

    def all_pages(self, path, query=None):
        self.calls.append(path)
        if path == "/v1/apps":
            return copy.deepcopy(self.apps)
        if path == "/v2/appAvailabilities/availability/territoryAvailabilities":
            return copy.deepcopy(self.territories)
        if path == "/v1/appEncryptionDeclarations":
            return copy.deepcopy(self.declarations)
        raise AssertionError(f"Unexpected list GET: {path}")


class ExportFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write("pubspec.yaml", "name: fixture\nversion: 1.2.3+7\n")
        self.write("pubspec.lock", "packages: {}\n")
        self.write("lib/reviewed_crypto.dart", "// reviewed test fixture\n")
        self.write("docs/crypto-inventory.json", '{"reviewed_files":["lib/reviewed_crypto.dart"]}\n')
        self.policy = {"schema_version": 1, "reviewed_on": "2026-11-08", "bundle_id": "com.example.cloud",
                       "uses_non_exempt_encryption": False,
                       "documentation": {"status": "not_required", "reference": "Fixture questionnaire result",
                                         "compliance_code": None},
                       "france": {"store_availability": "excluded", "prior_distribution_review": "no_prior_distribution",
                                  "reference": "Fixture owner review of all prior distribution"},
                       "inventory_sha256": preflight.sha256(self.root / "docs/crypto-inventory.json"),
                       "pubspec_lock_sha256": preflight.sha256(self.root / "pubspec.lock"),
                       "reviewed_source_sha256": preflight.reviewed_source_sha256(self.root)}
        self.save_policy()
        self.sync_source_plists()
        self.store = FakeStore()

    def write(self, relative, data):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data.encode() if isinstance(data, str) else data)
        return path

    def save_policy(self):
        self.write(preflight.POLICY_PATH, json.dumps(self.policy))

    def sync_source_plists(self):
        data = {"ITSAppUsesNonExemptEncryption": self.policy["uses_non_exempt_encryption"]}
        if self.policy["documentation"]["compliance_code"] is not None:
            data["ITSEncryptionExportComplianceCode"] = self.policy["documentation"]["compliance_code"]
        for path in preflight.SOURCE_PLISTS.values():
            self.write(path, plistlib.dumps(data))

    def built_plist(self, platform="ios", **changes):
        data = {"CFBundleIdentifier": "com.example.cloud", "CFBundleShortVersionString": "1.2.3",
                "CFBundleVersion": "7", "CFBundlePackageType": "APPL",
                "CFBundleSupportedPlatforms": [preflight.BUILT_PLATFORMS[platform]],
                "ITSAppUsesNonExemptEncryption": self.policy["uses_non_exempt_encryption"]}
        if self.policy["documentation"]["compliance_code"] is not None:
            data["ITSEncryptionExportComplianceCode"] = self.policy["documentation"]["compliance_code"]
        return {**data, **changes}

    def artifact(self, plist=None, platform="ios", extra=None):
        data = self.built_plist(platform) if plist is None else plist
        path = self.root / ("build/app.ipa" if platform == "ios" else "build/app.zip")
        path.parent.mkdir(parents=True, exist_ok=True)
        member = "Payload/Runner.app/Info.plist" if platform == "ios" else "CrispCloud.app/Contents/Info.plist"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr(member, plistlib.dumps(data, fmt=plistlib.FMT_BINARY))
            archive.writestr("metadata.txt", "fixture")
            for name, content in (extra or {}).items():
                archive.writestr(name, content)
        return path

    def approve(self):
        self.policy["uses_non_exempt_encryption"] = True
        self.policy["documentation"] = {"status": "approved", "reference": "Fixture Apple approval",
                                        "compliance_code": "fixture-issued-code"}
        self.policy["france"] = {"store_availability": "included", "prior_distribution_review": "covered",
                                 "reference": "Fixture French declaration and distribution review"}
        self.save_policy()
        self.sync_source_plists()
        self.store.territories[-1]["attributes"]["available"] = True
        self.store.declarations = [{"type": "appEncryptionDeclarations", "id": "declaration-1",
                                    "attributes": {"codeValue": "fixture-issued-code", "appEncryptionDeclarationState": "APPROVED",
                                                   "usesEncryption": True, "exempt": False, "platform": "IOS",
                                                   "availableOnFrenchStore": True,
                                                   "documentUrl": "https://example.invalid/private?token=never-save"},
                                    "relationships": {"app": {"data": {"type": "apps", "id": "123"}}}}]


class PolicyAndArtifactTests(ExportFixture):
    def test_pending_history_can_be_reviewed_in_source_but_cannot_be_submitted(self):
        self.policy["france"]["prior_distribution_review"] = "pending"
        self.policy["france"]["reference"] = None
        self.save_policy()
        preflight.validate_policy(self.root)
        with self.assertRaisesRegex(preflight.PreflightError, "history is unverified"):
            preflight.preflight(self.root, "ios", self.artifact(), self.store)
        self.assertEqual(self.store.calls, [])

    def test_inventory_and_dependency_changes_invalidate_review(self):
        for path in ("docs/crypto-inventory.json", "pubspec.lock"):
            with self.subTest(path=path):
                original = (self.root / path).read_bytes()
                self.write(path, original + b"\n")
                with self.assertRaisesRegex(preflight.PreflightError, "review is stale"):
                    preflight.validate_policy(self.root)
                self.write(path, original)

    def test_prose_tokens_cannot_replace_structured_policy(self):
        self.write("docs/export-compliance.md", "availableOnFrenchStore=false ITSAppUsesNonExemptEncryption=false")
        (self.root / preflight.POLICY_PATH).unlink()
        with self.assertRaisesRegex(preflight.PreflightError, "repository file"):
            preflight.validate_policy(self.root)

    def test_changed_crypto_source_invalidates_an_unchanged_inventory_and_lock(self):
        self.write("lib/reviewed_crypto.dart", "// changed algorithm or protocol\n")
        with self.assertRaisesRegex(preflight.PreflightError, "reviewed crypto source changed"):
            preflight.validate_policy(self.root)

    def test_duplicate_policy_fields_and_integer_booleans_are_rejected(self):
        self.write(preflight.POLICY_PATH, '{"schema_version":1,"schema_version":1}')
        with self.assertRaises(preflight.PreflightError):
            preflight.validate_policy(self.root)
        self.policy["uses_non_exempt_encryption"] = 0
        self.save_policy()
        with self.assertRaisesRegex(preflight.PreflightError, "Boolean"):
            preflight.validate_policy(self.root)

    def test_confirmed_history_requires_its_evidence(self):
        self.policy["france"]["reference"] = None
        self.save_policy()
        with self.assertRaisesRegex(preflight.PreflightError, "evidence reference"):
            preflight.validate_policy(self.root)

    def test_prior_france_coverage_does_not_authorize_false_shortcut(self):
        self.policy["france"]["prior_distribution_review"] = "covered"
        self.save_policy()
        with self.assertRaisesRegex(preflight.PreflightError, "approved route"):
            preflight.validate_policy(self.root, submission=True)

    def test_false_policy_cannot_enable_france_or_include_a_code(self):
        self.policy["france"]["store_availability"] = "included"
        self.save_policy()
        with self.assertRaisesRegex(preflight.PreflightError, "France inclusion"):
            preflight.validate_policy(self.root)
        self.policy["france"]["store_availability"] = "excluded"
        self.policy["documentation"]["compliance_code"] = "made-up"
        self.save_policy()
        with self.assertRaisesRegex(preflight.PreflightError, "must not carry"):
            preflight.validate_policy(self.root)

    def test_source_plist_must_match_policy_even_with_prose_evidence(self):
        self.write("ios/Runner/Info.plist", plistlib.dumps({"ITSAppUsesNonExemptEncryption": True}))
        with self.assertRaisesRegex(preflight.PreflightError, "disagrees"):
            preflight.validate_source_plist(self.root, "ios/Runner/Info.plist", self.policy)

    def test_signed_binary_plist_is_checked_independently_from_source(self):
        artifact = self.artifact(self.built_plist(ITSAppUsesNonExemptEncryption=True))
        with self.assertRaisesRegex(preflight.PreflightError, "disagrees"):
            preflight.verify_artifact(self.root, "ios", artifact)

    def test_release_identity_and_actual_platform_are_required(self):
        cases = {"CFBundleIdentifier": "com.someone.else", "CFBundleVersion": "8",
                 "CFBundleShortVersionString": "1.0.0", "CFBundlePackageType": "FMWK",
                 "CFBundleSupportedPlatforms": ["iPhoneSimulator"]}
        for key, value in cases.items():
            with self.subTest(key=key):
                with self.assertRaisesRegex(preflight.PreflightError, key):
                    preflight.verify_artifact(self.root, "ios", self.artifact(self.built_plist(**{key: value})))

    def test_ipa_binary_plist_and_macos_zip_are_hashed_exactly(self):
        for platform in ("ios", "macos"):
            with self.subTest(platform=platform):
                artifact = self.artifact(platform=platform)
                record = preflight.verify_artifact(self.root, platform, artifact)
                self.assertEqual(record["sha256"], hashlib.sha256(artifact.read_bytes()).hexdigest())
                self.assertEqual(record["platform"], platform)
                self.assertEqual(record["build"], "7")

    def test_wrong_bundle_and_multiple_main_apps_cannot_hide_in_zip(self):
        extra = {"Payload/Other.app/Info.plist": plistlib.dumps(self.built_plist())}
        with self.assertRaisesRegex(preflight.PreflightError, "exactly one"):
            preflight.verify_artifact(self.root, "ios", self.artifact(extra=extra))

    def test_zip_traversal_and_plist_symlink_are_rejected(self):
        with self.assertRaisesRegex(preflight.PreflightError, "unsafe member"):
            preflight.verify_artifact(self.root, "ios", self.artifact(extra={"../outside": b"bad"}))
        artifact = self.root / "bad.ipa"
        with zipfile.ZipFile(artifact, "w") as archive:
            member = zipfile.ZipInfo("Payload/Runner.app/Info.plist")
            member.create_system = 3
            member.external_attr = 0o120777 << 16
            archive.writestr(member, "elsewhere")
        with self.assertRaisesRegex(preflight.PreflightError, "regular file"):
            preflight.verify_artifact(self.root, "ios", artifact)

    def test_archive_plain_text_and_malformed_plist_fail_cleanly(self):
        artifact = self.write("bad.ipa", "not a ZIP")
        with self.assertRaises(preflight.PreflightError):
            preflight.verify_artifact(self.root, "ios", artifact)
        with self.assertRaises(preflight.PreflightError):
            preflight.load_plist(b"<?xml version='1.0'?><plist><dict><key>bad", "broken")

    def test_pkg_reads_the_expanded_package_not_an_unrelated_build_directory(self):
        artifact = self.write("build/app.pkg", b"package fixture")

        def expand(args, **kwargs):
            self.assertEqual(args[:2], ["/usr/sbin/pkgutil", "--expand-full"])
            path = Path(args[-1]) / "component.pkg/Payload/CrispCloud.app/Contents/Info.plist"
            path.parent.mkdir(parents=True)
            path.write_bytes(plistlib.dumps(self.built_plist("macos")))
            return subprocess.CompletedProcess(args, 0, b"", b"")

        with patch.object(preflight.subprocess, "run", side_effect=expand):
            record = preflight.verify_artifact(self.root, "macos", artifact)
        self.assertIn("component.pkg/Payload", record["info_plist_member"])
        self.assertEqual(record["sha256"], hashlib.sha256(b"package fixture").hexdigest())

    def test_pkg_expansion_failure_does_not_fall_back_to_source_plist(self):
        artifact = self.write("build/app.pkg", b"package fixture")
        with patch.object(preflight.subprocess, "run", side_effect=FileNotFoundError):
            with self.assertRaisesRegex(preflight.PreflightError, "pkgutil"):
                preflight.verify_artifact(self.root, "macos", artifact)


class LiveStoreTests(ExportFixture):
    def test_explicit_france_exclusion_with_verified_history_passes_and_binds_artifact(self):
        artifact = self.artifact()
        result = preflight.preflight(self.root, "ios", artifact, self.store, "123")
        self.assertTrue(result["live_store_checked"])
        self.assertEqual(result["app_store_connect"]["app_id"], "123")
        self.assertEqual(result["artifact"]["sha256"], preflight.sha256(artifact))
        self.assertEqual(result["policy_sha256"], preflight.sha256(self.root / preflight.POLICY_PATH))

    def test_wrong_app_bundle_or_expected_app_id_fails(self):
        with self.assertRaisesRegex(preflight.PreflightError, "differs from ASC_APP_ID"):
            preflight.live_store_evidence(self.store, "ios", self.policy, "different-id")
        self.store.apps[0]["attributes"]["bundleId"] = "com.someone.else"
        with self.assertRaisesRegex(preflight.PreflightError, "exactly the reviewed"):
            preflight.live_store_evidence(self.store, "ios", self.policy)

    def test_absent_or_duplicate_france_record_is_not_exclusion(self):
        self.store.territories = [territory("USA", available=True)]
        with self.assertRaisesRegex(preflight.PreflightError, "one explicit"):
            preflight.live_store_evidence(self.store, "ios", self.policy)
        self.store.territories = [territory(), territory()]
        with self.assertRaisesRegex(preflight.PreflightError, "duplicate territory"):
            preflight.live_store_evidence(self.store, "ios", self.policy)

    def test_enabled_unknown_or_numeric_france_availability_fails(self):
        for available in (True, None, 0, "false"):
            with self.subTest(available=available):
                self.store.territories[-1]["attributes"]["available"] = available
                with self.assertRaisesRegex(preflight.PreflightError, "Live French"):
                    preflight.live_store_evidence(self.store, "ios", self.policy)

    def test_preorders_release_dates_and_transitional_states_do_not_count_as_excluded(self):
        future = (dt.date.today() + dt.timedelta(days=30)).isoformat()
        cases = [{"preOrderEnabled": True}, {"preOrderEnabled": 0}, {"releaseDate": future},
                 {"preOrderPublishDate": future}, {"contentStatuses": ["PROCESSING_TO_NOT_AVAILABLE"]},
                 {"contentStatuses": ["AVAILABLE_FOR_SALE_UNRELEASED_APP"]}, {"contentStatuses": ["UNKNOWN"]}]
        for changes in cases:
            with self.subTest(changes=changes):
                self.store.territories[-1] = territory(**changes)
                with self.assertRaisesRegex(preflight.PreflightError, "scheduled, preorder, or unresolved"):
                    preflight.live_store_evidence(self.store, "ios", self.policy)

    def test_past_dates_and_known_restrictions_do_not_override_explicit_exclusion(self):
        self.store.territories[-1] = territory(releaseDate="2000-01-01", preOrderPublishDate="2000-01-01T00:00:00Z",
                                              contentStatuses=["CANNOT_SELL", "MISSING_RATING"])
        preflight.live_store_evidence(self.store, "ios", self.policy)
        self.store.territories[-1]["attributes"]["available"] = True
        with self.assertRaisesRegex(preflight.PreflightError, "Live French"):
            preflight.live_store_evidence(self.store, "ios", self.policy)

    def test_approved_declaration_must_match_app_platform_status_and_code(self):
        self.approve()
        original = copy.deepcopy(self.store.declarations[0])
        mutations = [("appEncryptionDeclarationState", "IN_REVIEW"), ("codeValue", "different-code"),
                     ("platform", "MAC_OS"), ("availableOnFrenchStore", False),
                     ("usesEncryption", False), ("exempt", True)]
        for field, value in mutations:
            with self.subTest(field=field):
                self.store.declarations[0] = copy.deepcopy(original)
                self.store.declarations[0]["attributes"][field] = value
                with self.assertRaises(preflight.PreflightError):
                    preflight.preflight(self.root, "ios", self.artifact(), self.store)
        self.store.declarations[0] = copy.deepcopy(original)
        self.store.declarations[0]["relationships"]["app"]["data"]["id"] = "another-app"
        with self.assertRaisesRegex(preflight.PreflightError, "same app"):
            preflight.preflight(self.root, "ios", self.artifact(), self.store)

    def test_approved_declaration_evidence_omits_private_document_urls(self):
        self.approve()
        result = preflight.preflight(self.root, "ios", self.artifact(), self.store)
        self.assertEqual(result["app_store_connect"]["approved_declaration"]["state"], "APPROVED")
        self.assertNotIn("never-save", json.dumps(result))
        self.assertNotIn("documentUrl", json.dumps(result))

    def test_app_level_approval_with_deprecated_platform_absent_is_accepted(self):
        self.approve()
        del self.store.declarations[0]["attributes"]["platform"]
        preflight.preflight(self.root, "ios", self.artifact(), self.store)

    def test_artifact_cannot_change_while_live_responses_are_collected(self):
        artifact = self.artifact()
        original = self.store.get

        def change_artifact(path, query=None):
            artifact.write_bytes(artifact.read_bytes() + b"changed")
            return original(path, query)

        self.store.get = change_artifact
        with self.assertRaisesRegex(preflight.PreflightError, "changed during live"):
            preflight.preflight(self.root, "ios", artifact, self.store)

    def test_offline_cli_never_initializes_credentials_or_claims_live_review(self):
        output = self.root / "evidence.json"
        with patch.object(preflight, "ROOT", self.root), patch.object(preflight, "AppStoreConnect", side_effect=AssertionError):
            with patch("sys.stdout", new_callable=io.StringIO):
                result = preflight.main(["--platform", "ios", "--artifact", str(self.artifact()),
                                         "--output", str(output), "--check-artifact"])
        self.assertEqual(result, 0)
        self.assertFalse(json.loads(output.read_text())["live_store_checked"])


class HttpClientTests(unittest.TestCase):
    def client(self):
        return preflight.AppStoreConnect("fixture-key", "fixture-issuer", Path("unused.p8"))

    def page(self, records, next_page=None, total=None):
        result = {"data": records, "links": {"next": next_page}}
        if total is not None:
            result["meta"] = {"paging": {"total": total}}
        return result

    def test_cross_origin_requests_fail_before_signing_or_sending(self):
        bad = ["http://api.appstoreconnect.apple.com/v1/apps", "https://attacker.invalid/v1/apps",
               "https://api.appstoreconnect.apple.com.attacker.invalid/v1/apps", "//attacker.invalid/v1/apps",
               "https://user@api.appstoreconnect.apple.com/v1/apps", "https://api.appstoreconnect.apple.com:443/v1/apps",
               "https://api.appstoreconnect.apple.com/v1/apps#fragment"]
        client = self.client()
        with patch.object(client, "jwt", side_effect=AssertionError("must not read signing key")):
            for url in bad:
                with self.subTest(url=url), self.assertRaises(preflight.PreflightError):
                    client.get(url)

    def test_redirects_never_forward_credentials(self):
        with self.assertRaisesRegex(preflight.PreflightError, "redirected"):
            preflight.NoRedirect().redirect_request(None, None, 302, "redirect", {}, "https://attacker.invalid")

    def test_requests_use_get_and_default_verified_https_opener(self):
        client = self.client()
        response = io.BytesIO(b'{"data":[],"links":{"next":null}}')
        with patch.object(client, "jwt", return_value="fixture-token"), patch.object(client.opener, "open", return_value=response) as request:
            client.get("/v1/apps", {"filter[bundleId]": "com.example.cloud"})
        sent = request.call_args.args[0]
        self.assertEqual(sent.get_method(), "GET")
        self.assertTrue(sent.full_url.startswith(preflight.API_ORIGIN + "/v1/apps?"))
        self.assertEqual(sent.get_header("Authorization"), "Bearer fixture-token")

    def test_pagination_reads_later_france_record(self):
        client = self.client()
        path = "/v2/appAvailabilities/fixture/territoryAvailabilities"
        records = [self.page([territory("USA", available=True)], preflight.API_ORIGIN + path + "?cursor=second", 2),
                   self.page([territory()], None, 2)]
        with patch.object(client, "get", side_effect=records) as get:
            result = client.all_pages(path, {"limit": 1})
        self.assertEqual(len(result), 2)
        self.assertEqual(result[1]["relationships"]["territory"]["data"]["id"], "FRA")
        self.assertEqual(get.call_count, 2)

    def test_pagination_rejects_cross_origin_and_cross_endpoint_before_request(self):
        for url in ("https://attacker.invalid/v1/apps?cursor=x", preflight.API_ORIGIN + "/v1/builds?cursor=x"):
            with self.subTest(url=url):
                client = self.client()
                with patch.object(client, "get", return_value=self.page([], url)) as get:
                    with self.assertRaises(preflight.PreflightError):
                        client.all_pages("/v1/apps")
                self.assertEqual(get.call_count, 1)

    def test_pagination_rejects_cycles_duplicates_and_incomplete_totals(self):
        item = {"type": "apps", "id": "1"}
        cases = [[self.page([], preflight.API_ORIGIN + "/v1/apps")],
                 [self.page([item], preflight.API_ORIGIN + "/v1/apps?cursor=2"), self.page([item])],
                 [self.page([item], None, 2)],
                 [self.page([item], preflight.API_ORIGIN + "/v1/apps?cursor=2", 2), self.page([], None, 1)]]
        for pages in cases:
            with self.subTest(pages=pages):
                client = self.client()
                with patch.object(client, "get", side_effect=pages):
                    with self.assertRaises(preflight.PreflightError):
                        client.all_pages("/v1/apps")

    def test_authentication_failure_does_not_become_empty_territories(self):
        import urllib.error
        client = self.client()
        with patch.object(client, "jwt", return_value="fixture-token"), patch.object(
                client.opener, "open", side_effect=urllib.error.HTTPError(preflight.API_ORIGIN, 403, "forbidden", {}, None)):
            with self.assertRaisesRegex(preflight.PreflightError, "HTTP 403"):
                client.get("/v1/apps")

    @unittest.skipUnless(shutil.which("openssl"), "OpenSSL needed for an independent JWT signature check")
    def test_es256_jwt_signature_verifies_with_openssl_using_ephemeral_key(self):
        with tempfile.TemporaryDirectory() as directory:
            private, public = Path(directory) / "private.p8", Path(directory) / "public.pem"
            subprocess.run(["openssl", "genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256", "-out", str(private)],
                           check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            subprocess.run(["openssl", "pkey", "-in", str(private), "-pubout", "-out", str(public)],
                           check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            token = preflight.AppStoreConnect("key", "issuer", private).jwt()
            header, claims, signature = token.split(".")
            decoded = json.loads(base64.urlsafe_b64decode(claims + "=="))
            self.assertEqual(decoded["aud"], "appstoreconnect-v1")
            self.assertLessEqual(decoded["exp"] - decoded["iat"], 1200)
            raw = base64.urlsafe_b64decode(signature + "==")
            self.assertEqual(len(raw), 64)
            integers = []
            for value in (raw[:32], raw[32:]):
                value = value.lstrip(b"\0") or b"\0"
                if value[0] & 128:
                    value = b"\0" + value
                integers.append(bytes([2, len(value)]) + value)
            contents = b"".join(integers)
            signature_file = Path(directory) / "signature.der"
            signature_file.write_bytes(bytes([0x30, len(contents)]) + contents)
            result = subprocess.run(["openssl", "dgst", "-sha256", "-verify", str(public), "-signature", str(signature_file)],
                                    input=f"{header}.{claims}".encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_malformed_der_signature_is_rejected(self):
        for data in (b"", b"\x30\x00", b"\x30\x06\x02\x01\x00\x02\x01\x01",
                     b"\x30\x06\x02\x01\x80\x02\x01\x01"):
            with self.subTest(data=data), self.assertRaises(preflight.PreflightError):
                preflight.raw_ecdsa_signature(data)


if __name__ == "__main__":
    unittest.main()
