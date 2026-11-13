import 'package:crisp_cloud/services/file_viewer_binary_license.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(LicenseRegistry.reset);
  tearDown(LicenseRegistry.reset);

  test(
    'distributed inspector exposes original license and adaptation notice',
    () async {
      registerFileViewerBinaryLicense();
      final entries = await LicenseRegistry.licenses.toList();
      expect(entries, hasLength(1));
      expect(entries.single.packages, [
        'File Viewer binary header parser (Dart adaptation)',
      ]);
      final text = entries.single.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('Copyright 2026 Flyfish Viewer'));
      expect(text, contains('Apache License'));
      expect(text, contains('Version 2.0, January 2004'));
      expect(text, contains('Modified:'));
      expect(text, contains('d264009ca6efb3daed79a39d1ae63133e0f25558'));
    },
  );
}
