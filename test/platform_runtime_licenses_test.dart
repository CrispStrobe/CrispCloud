import 'package:crisp_cloud/services/platform_runtime_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(LicenseRegistry.reset);
  tearDown(LicenseRegistry.reset);
  test(
    'Windows PDFium notice is readable through the real asset bundle',
    () async {
      registerPlatformRuntimeLicenses();
      final entries = await LicenseRegistry.licenses.toList();
      expect(entries.single.packages, contains('PDFium (Windows renderer)'));
      final text = entries.single.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('Copyright 2014 PDFium Authors'));
      expect(text, contains('4690'));
      expect(text, contains('Redistributions in binary form'));
    },
  );
}
