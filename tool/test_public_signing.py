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
        return 'Signer #1 certificate DN: CN=CrispCloud Release\nSigner #1 certificate SHA-256 digest: ' + (fingerprint or self.fingerprint) + '\n'

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
        for report in ['', self.report() + self.report().replace('#1', '#2')]:
            with self.subTest(report=report), self.assertRaisesRegex(ValueError, 'exactly one'):
                android.check_report(report, self.fingerprint)

    def test_invalid_expected_fingerprint_is_refused(self):
        with self.assertRaisesRegex(ValueError, 'invalid'):
            android.check_report(self.report(), 'not-a-certificate-digest')


if __name__ == '__main__':
    unittest.main()
