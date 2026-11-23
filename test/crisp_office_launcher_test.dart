import 'dart:io';

import 'package:crisp_cloud/services/crisp_office_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'launches the installed CrispOffice bundle with the exact path',
    () async {
      var executable = '';
      List<String>? arguments;
      final launcher = CrispOfficeLauncher(
        supported: true,
        run: (value, args) async {
          executable = value;
          arguments = args;
          return ProcessResult(0, 0, '', '');
        },
      );
      expect(await launcher.open('/Users/example/Report.doc'), isTrue);
      expect(executable, '/usr/bin/open');
      expect(arguments, [
        '-b',
        CrispOfficeLauncher.bundleIdentifier,
        '/Users/example/Report.doc',
      ]);
    },
  );

  test(
    'refuses relative, NUL and unsupported paths without launching',
    () async {
      var calls = 0;
      final launcher = CrispOfficeLauncher(
        supported: true,
        run: (_, _) async {
          calls++;
          return ProcessResult(0, 0, '', '');
        },
      );
      expect(await launcher.open('Report.doc'), isFalse);
      expect(await launcher.open('/tmp/Bad\u0000.doc'), isFalse);
      expect(
        await CrispOfficeLauncher(supported: false).open('/tmp/Report.doc'),
        isFalse,
      );
      expect(calls, 0);
    },
  );
}
