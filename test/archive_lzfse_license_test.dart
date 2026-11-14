import 'package:crisp_cloud/services/archive_lzfse_license.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(LicenseRegistry.reset);
  tearDown(LicenseRegistry.reset);

  test(
    'distributed LZFSE decoder exposes its BSD license and provenance',
    () async {
      registerArchiveLzfseLicense();
      final entries = await LicenseRegistry.licenses.toList();
      expect(entries, hasLength(1));
      expect(entries.single.packages, [
        'Apple LZFSE decoder (bounded Dart adaptation)',
      ]);
      final text = entries.single.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('Copyright (c) 2015-2016, Apple Inc.'));
      expect(
        text,
        contains('Redistribution and use in source and binary forms'),
      );
      expect(text, contains('Neither the name of the copyright holder(s)'));
      expect(text, contains('THIS SOFTWARE IS PROVIDED'));
      expect(text, contains('Modified:'));
      expect(text, contains('e634ca58b4821d9f3d560cdc6df5dec02ffc93fd'));
    },
  );
}
