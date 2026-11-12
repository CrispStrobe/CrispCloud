import 'package:crisp_storage/crisp_storage.dart';
import 'package:test/test.dart';

void main() {
  test('answers the usual password prompts', () {
    for (final prompt in [
      'Password: ',
      'password:',
      '  PASSWORD :  ',
      '(alice@example.com) Password: ',
      '(alice@203.0.113.7) Password:',
      "alice@example.com's password: ",
    ]) {
      expect(isPasswordPrompt(prompt), isTrue, reason: prompt);
    }
  });

  test('never answers other challenges with the saved password', () {
    for (final prompt in [
      'Verification code: ',
      'One-time password (OATH) for `alice`: ',
      'New password: ',
      'Retype new password: ',
      '(current) UNIX password: ',
      'Password for alice: ',
      'Enter passphrase for key: ',
      '',
    ]) {
      expect(isPasswordPrompt(prompt), isFalse, reason: prompt);
    }
  });
}
