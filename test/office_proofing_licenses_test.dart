import 'dart:io';

import 'package:crisp_cloud/services/office_proofing_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(LicenseRegistry.reset);
  tearDown(LicenseRegistry.reset);

  test(
    'Embedded Office notices are bundled unchanged and exposed in licenses',
    () async {
      const prefix = 'packages/quds_office_engine/third_party/';
      const notices = {
        'German hyphenation patterns': 'hyphenation/LICENSE',
        'Werners Wortliste (German spelling)': 'proofing/WORTLISTE_LICENSE',
        'Quds German word supplement': 'proofing/QUDS_WORDS_LICENSE',
        'FontTools (Unicode range data)': 'fonttools/LICENSE',
      };
      registerOfficeProofingLicenses();
      final entries = await LicenseRegistry.licenses.toList();
      expect(entries, hasLength(notices.length));
      for (final notice in notices.entries) {
        final asset = '$prefix${notice.value}';
        final bundled = await rootBundle.loadString(asset);
        expect(bundled, await File(asset).readAsString());
        final entry = entries.singleWhere(
          (entry) => entry.packages.contains(notice.key),
        );
        final text = entry.paragraphs
            .map((paragraph) => paragraph.text)
            .join('\n');
        expect(text, contains('Copyright'));
        expect(text, contains('Permission is hereby granted'));
        expect(text, contains('THE SOFTWARE IS PROVIDED'));
      }
      final hyphenation = entries.first.paragraphs
          .map((paragraph) => paragraph.text)
          .join('\n');
      expect(hyphenation, contains('Copyright (c) 2013-2024'));
      expect(hyphenation, contains('Keno Wehr'));
      final fontTools = entries
          .singleWhere(
            (entry) =>
                entry.packages.contains('FontTools (Unicode range data)'),
          )
          .paragraphs
          .map((paragraph) => paragraph.text)
          .join('\n');
      expect(fontTools, contains('FontTools 4.61.1'));
      expect(fontTools, contains('Copyright (c) 2017 Just van Rossum'));
    },
  );

  test(
    'hyphenation notice retains the complete upstream header text',
    () async {
      const prefix = 'packages/quds_office_engine/third_party/hyphenation/';
      final original = await File('${prefix}hyph-de-1996.tex').readAsString();
      final header = original.split('% source:').first;
      final notice = header
          .split('\n')
          .map((line) {
            if (line.startsWith('% ')) return line.substring(2);
            if (line.startsWith('%')) return line.substring(1);
            return line;
          })
          .join('\n')
          .trimRight();
      expect(await rootBundle.loadString('${prefix}LICENSE'), '$notice\n');
    },
  );
}
