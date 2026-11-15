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
      final allEntries = await LicenseRegistry.licenses.toList();
      final entries = allEntries
          .where((e) => e.packages.contains('PDFium (Windows renderer)'))
          .toList();
      final optional = allEntries.where(
        (e) =>
            e.packages.contains('Optional macFUSE/FUSE-T libfuse API headers'),
      );
      if (const bool.fromEnvironment('CRISP_ENABLE_FUSE')) {
        expect(
          optional.single.paragraphs.map((p) => p.text).join('\n'),
          contains('GNU LESSER GENERAL PUBLIC LICENSE'),
        );
      } else {
        expect(optional, isEmpty);
      }
      expect(entries.single.packages, contains('PDFium (Windows renderer)'));
      final text = entries.single.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('Copyright 2014 PDFium Authors'));
      expect(text, contains('4690'));
      expect(text, contains('Redistributions in binary form'));
    },
  );
}
