import 'dart:io';
import 'package:crisp_storage/src/smb_license.dart';
import 'package:test/test.dart';

void main() {
  test('SMB dependency and runtime policy cannot bundle libsmb2', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      isNot(contains('dart_smb2:')),
    );
    expect(
      File('lib/src/smb_session.dart').readAsStringSync(),
      isNot(contains('Libsmb2Session')),
    );
    expect(smbLicense, contains('MIT selected'));
    expect(
      File('NOTICES').readAsStringSync(),
      contains('smb2 0.43.0'),
    );
  });
}
