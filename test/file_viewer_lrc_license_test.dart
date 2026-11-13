import 'package:crisp_cloud/services/file_viewer_lrc_license.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Apache LRC license asset is available in the app license registry',
    () async {
      LicenseRegistry.reset();
      addTearDown(LicenseRegistry.reset);
      registerFileViewerLrcLicense();
      final entries = await LicenseRegistry.licenses.toList();
      final entry = entries.singleWhere(
        (entry) =>
            entry.packages.contains('File Viewer LRC parser (Dart adaptation)'),
      );
      final text = entry.paragraphs
          .map((paragraph) => paragraph.text)
          .join('\n');
      expect(text, contains('Copyright 2026 Flyfish Viewer'));
      expect(text, contains('Apache License'));
      expect(text, contains('Version 2.0, January 2004'));
      expect(text, contains('Modified: bounded Dart parsing'));
      expect(text, contains('d264009ca6efb3daed79a39d1ae63133e0f25558'));
    },
  );
}
