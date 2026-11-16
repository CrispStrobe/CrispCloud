import 'dart:io';

import 'package:crisp_cloud/services/macos_application_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'live Launch Services opens a temporary background app bundle',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'crispcloud-app-launch-live-',
      );
      addTearDown(() => root.delete(recursive: true));
      final bundle = Directory('${root.path}/Launch Probe.app');
      final executable = File('${bundle.path}/Contents/MacOS/probe');
      executable.parent.createSync(recursive: true);
      final marker = File('${root.path}/launched.txt');
      final source = File('${root.path}/probe.c')
        ..writeAsStringSync('''
#include <stdio.h>
int main(void) {
  FILE *file = fopen("${marker.path}", "w");
  if (!file) return 2;
  fputs("launched", file);
  fclose(file);
  return 0;
}
''');
      File('${bundle.path}/Contents/Info.plist').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.crispcloud.tests.launchprobe.v${DateTime.now().microsecondsSinceEpoch}</string>
<key>CFBundleName</key><string>CrispCloud Launch Probe</string>
<key>CFBundleExecutable</key><string>probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSBackgroundOnly</key><true/>
</dict></plist>
''');
      final compiled = await Process.run('/usr/bin/clang', [
        source.path,
        '-o',
        executable.path,
      ]);
      expect(compiled.exitCode, 0, reason: compiled.stderr.toString());
      await MacApplicationLauncher(supported: Platform.isMacOS)
          .launch(bundle.path);
      final elapsed = Stopwatch()..start();
      while (!marker.existsSync() &&
          elapsed.elapsed < const Duration(seconds: 15)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(
        marker.existsSync(),
        isTrue,
        reason: 'Launch Services must execute the selected bundle.',
      );
      expect(marker.readAsStringSync(), 'launched');
    },
    skip: !Platform.isMacOS || Platform.environment['MACOS_APP_LIVE'] != '1',
  );
}
