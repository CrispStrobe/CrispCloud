import 'dart:io';
import 'package:crisp_storage/src/smb_license.dart';
import 'package:test/test.dart';

void main() {
  test(
    'runtime and distributed SMB notices identify the same native source',
    () {
      final notice = File('NOTICE-LIBSMB2.txt').readAsStringSync();
      expect(smbLicense.trim(), notice.trim());
      expect(notice, contains('libsmb2-r10'));
      expect(notice, contains('4d9ce67863332462236d86bf76c85617a0b2897d'));
      expect(notice, contains('GNU LESSER GENERAL PUBLIC LICENSE'));
      expect(notice, contains('headerpad_max_install_names'));
    },
  );
}
