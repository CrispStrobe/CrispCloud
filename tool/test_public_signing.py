import datetime as dt
import hashlib
from pathlib import Path
import subprocess
import unittest
from unittest import mock

import macos_public_signing as signing
import verify_android_signing as android


class DeveloperIDTests(unittest.TestCase):
    def setUp(self):
        self.certificate = b'public certificate fixture'
        self.fingerprint = hashlib.sha1(self.certificate).hexdigest().upper()
        self.team = 'N9XSJ4M3GT'
        self.payload = {'ProvisionsAllDevices': True,
                        'DeveloperCertificates': [self.certificate],
                        'ExpirationDate': dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=1),
                        'Entitlements': {'com.apple.application-identifier': self.team + '.' + signing.BUNDLE}}

    def test_app_requirement_accepts_only_the_exact_team_and_bundle(self):
        requirement = signing.app_requirement(self.team)
        self.assertIn(f'identifier "{signing.BUNDLE}"', requirement)
        self.assertIn(f'certificate leaf[subject.OU] = "{self.team}"', requirement)
        self.assertIn('anchor apple generic', requirement)
        for team in ('', self.team + ' or true', '" or true', 'another-team'):
            with self.subTest(team=team), self.assertRaises(ValueError):
                signing.app_requirement(team)

    def test_local_and_appstore_shell_requirements_match_public_signing(self):
        for relative in ('tool/sign_macos_local.sh', '.github/workflows/macos-release.yml'):
            with self.subTest(source=relative):
                source = (signing.ROOT / relative).read_text()
                assignment = next(line.strip() for line in source.splitlines() if line.strip().startswith('APP_REQUIREMENT='))
                assignment = assignment.replace('${{ env.BUNDLE_ID }}', signing.BUNDLE)
                script = f'TEAM={self.team}\nBUNDLE_ID={signing.BUNDLE}\n' + assignment + '\nprintf "%s" "$APP_REQUIREMENT"'
                actual = subprocess.check_output(['bash', '-c', script], text=True)
                self.assertEqual(actual, signing.app_requirement(self.team))

    def test_existing_developer_id_profile_is_accepted(self):
        signing.validate_profile(self.payload, signing.BUNDLE, self.fingerprint, self.team)

    def test_store_and_device_limited_profiles_are_refused(self):
        for change in [{'ProvisionsAllDevices': False}, {'ProvisionedDevices': ['fixture-device']}]:
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, 'Developer ID profile'):
                signing.validate_profile(dict(self.payload, **change), signing.BUNDLE, self.fingerprint, self.team)

    def test_profile_for_another_app_or_certificate_is_refused(self):
        with self.assertRaisesRegex(ValueError, 'identifier'):
            signing.validate_profile(self.payload, signing.EXTENSION, self.fingerprint, self.team)
        with self.assertRaisesRegex(ValueError, 'certificate'):
            signing.validate_profile(self.payload, signing.BUNDLE, 'A' * 40, self.team)

    def test_expired_profile_is_refused(self):
        self.payload['ExpirationDate'] = dt.datetime(2000, 1, 1)
        with self.assertRaisesRegex(ValueError, 'expired'):
            signing.validate_profile(self.payload, signing.BUNDLE, self.fingerprint, self.team)

    def test_vault_keychain_group_requires_profile_authorization(self):
        group = signing.vault_keychain_group(self.team)
        self.assertEqual(group, self.team + '.' + signing.BUNDLE)
        self.assertFalse(signing.profile_allows_keychain_group(self.payload, group))
        for allowed in ([self.team + '.*'], [group]):
            payload = dict(self.payload, Entitlements={'keychain-access-groups': allowed})
            self.assertTrue(signing.profile_allows_keychain_group(payload, group))
        for allowed in (['OTHERTEAM.*'], [self.team + '.other.app'], 'not-a-list'):
            payload = dict(self.payload, Entitlements={'keychain-access-groups': allowed})
            self.assertFalse(signing.profile_allows_keychain_group(payload, group))

    def test_signing_entitlements_expand_prefixes_and_add_keychain_group(self):
        import plistlib
        import tempfile
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'source.plist'
            source.write_bytes(plistlib.dumps({
                'com.apple.security.application-groups': ['$(TeamIdentifierPrefix)crispcloud'],
                'example': '$(AppIdentifierPrefix)x'}))
            target = Path(folder) / 'target.plist'
            signing.entitlements(source, signing.BUNDLE, self.team, target,
                                 keychain_group=signing.vault_keychain_group(self.team))
            values = plistlib.loads(target.read_bytes())
            self.assertEqual(values['com.apple.security.application-groups'], [self.team + '.crispcloud'])
            self.assertEqual(values['example'], self.team + '.x')
            self.assertEqual(values['keychain-access-groups'], [self.team + '.' + signing.BUNDLE])
            signing.entitlements(source, signing.BUNDLE, self.team, target)
            self.assertNotIn('keychain-access-groups', plistlib.loads(target.read_bytes()))
            with mock.patch.object(signing, 'profile_payload', return_value=self.payload):
                self.assertFalse(signing.add_keychain_group(target, Path('unused'), self.team))
            self.assertNotIn('keychain-access-groups', plistlib.loads(target.read_bytes()))
            allowed = dict(self.payload, Entitlements={'keychain-access-groups': [self.team + '.*']})
            with mock.patch.object(signing, 'profile_payload', return_value=allowed):
                self.assertTrue(signing.add_keychain_group(target, Path('unused'), self.team))
            self.assertEqual(plistlib.loads(target.read_bytes())['keychain-access-groups'],
                             [self.team + '.' + signing.BUNDLE])

    def test_restricted_keychain_group_stays_out_of_committed_entitlements(self):
        # Unsigned/ad-hoc launches (CI smoke test, local builds) are killed if
        # the committed entitlements carry keychain-access-groups (2e823d73).
        for name in ('Release', 'Direct', 'DebugProfile'):
            text = (signing.ROOT / 'macos/Runner' / f'{name}.entitlements').read_text()
            self.assertNotIn('keychain-access-groups', text, name)
        for relative in ('tool/sign_macos_local.sh', '.github/workflows/macos-release.yml'):
            source = (signing.ROOT / relative).read_text()
            self.assertIn('macos_public_signing.py keychain-group', source, relative)
            self.assertIn('$(AppIdentifierPrefix)', source, relative)

    def test_native_tool_error_does_not_echo_password_arguments(self):
        command = ['security', 'import', '-P', 'fixture-secret-must-not-be-shown']
        with mock.patch.object(subprocess, 'run', side_effect=subprocess.CalledProcessError(1, command)):
            with self.assertRaises(ValueError) as error:
                signing.run(*command)
        self.assertNotIn(command[-1], str(error.exception))

    def test_cleanup_preserves_keychains_added_by_other_work(self):
        current = '"/tmp/login.keychain-db" "/tmp/ours.keychain-db" "/tmp/another-new-keychain"'
        with mock.patch.object(subprocess, 'check_output', return_value=current), mock.patch.object(signing, 'run') as run:
            signing.update_search_list(Path('/tmp/ours.keychain-db'), add=False)
        self.assertEqual(run.call_args.args, ('security', 'list-keychains', '-d', 'user', '-s',
                                             '/tmp/login.keychain-db', '/tmp/another-new-keychain'))

    def test_notary_rejection_is_not_reported_as_success(self):
        import tempfile
        environment = {'APPLE_NOTARY_KEY_PATH': '/fixture/key.p8', 'APPLE_NOTARY_KEY_ID': 'fixture', 'APPLE_NOTARY_ISSUER_ID': 'fixture'}
        with tempfile.TemporaryDirectory() as d, mock.patch.dict(signing.os.environ, environment), \
                mock.patch.object(subprocess, 'check_output', return_value=b'{"id":"fixture","status":"Invalid"}'), \
                mock.patch.object(signing, 'run'):
            with self.assertRaisesRegex(ValueError, 'not accepted'):
                signing.notarize(Path('fixture.zip'), Path(d) / 'result.json')


class AndroidSignerTests(unittest.TestCase):
    fingerprint = 'ab' * 32

    def report(self, fingerprint=None):
        return ('Verifies\nNumber of signers: 1\nSigner #1 certificate DN: CN=CrispCloud Release\n'
                'Signer #1 certificate SHA-256 digest: ' + (fingerprint or self.fingerprint) + '\n')

    def v2_report(self, fingerprint=None):
        # build-tools 36.1+ format, observed on ubuntu-latest 2026-11-23.
        return ('Verifies\nNumber of signers: 1\nV2 Signer: certificate DN: CN=CrispCloud Release\n'
                'V2 Signer: certificate SHA-256 digest: ' + (fingerprint or self.fingerprint) + '\n'
                'V2 Signer: public key SHA-256 digest: ' + 'ef' * 32 + '\n')

    def test_current_apksigner_format_is_accepted(self):
        self.assertEqual(android.check_report(self.v2_report(), self.fingerprint), self.fingerprint)

    def test_current_apksigner_format_refuses_other_or_extra_signers(self):
        with self.assertRaisesRegex(ValueError, 'incompatible update'):
            android.check_report(self.v2_report('cd' * 32), self.fingerprint)
        for report in [self.v2_report().replace('signers: 1', 'signers: 2'),
                       self.v2_report() + 'V3 Signer: certificate SHA-256 digest: ' + 'cd' * 32 + '\n']:
            with self.subTest(report=report), self.assertRaisesRegex(ValueError, 'exactly one'):
                android.check_report(report, self.fingerprint)

    def test_keystore_substitution_is_refused_before_building(self):
        with self.assertRaisesRegex(ValueError, 'previously published'):
            android.expected_certificate(b'a different keystore certificate', self.fingerprint)

    def test_exact_retained_key_is_accepted(self):
        self.assertEqual(android.check_report(self.report(), self.fingerprint.upper()), self.fingerprint)

    def test_debug_certificate_is_refused_even_when_it_is_the_expected_key(self):
        with self.assertRaisesRegex(ValueError, 'debug-signed'):
            android.check_report(self.report().replace('CrispCloud Release', 'Android Debug'), self.fingerprint)

    def test_another_valid_signer_is_refused(self):
        with self.assertRaisesRegex(ValueError, 'incompatible update'):
            android.check_report(self.report('cd' * 32), self.fingerprint)

    def test_multiple_signers_or_missing_signer_are_refused(self):
        for report in ['', self.report() + self.report().replace('#1', '#2').replace('Verifies\nNumber of signers: 1\n', '')]:
            with self.subTest(report=report), self.assertRaisesRegex(ValueError, 'exactly one'):
                android.check_report(report, self.fingerprint)

    def test_invalid_expected_fingerprint_is_refused(self):
        with self.assertRaisesRegex(ValueError, 'invalid'):
            android.check_report(self.report(), 'not-a-certificate-digest')


if __name__ == '__main__':
    unittest.main()
