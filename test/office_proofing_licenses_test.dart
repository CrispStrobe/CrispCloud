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
        'American English hyphenation patterns (LicenseRef-Kuiken-permissive)':
            'hyphenation/ENGLISH_US_LICENSE',
        'British English hyphenation patterns (MIT)':
            'hyphenation/ENGLISH_GB_LICENSE',
        'Werners Wortliste (German spelling)': 'proofing/WORTLISTE_LICENSE',
        'Quds German word supplement': 'proofing/QUDS_WORDS_LICENSE',
        'Unicode Inflection (German morphology, Unicode-3.0)':
            'proofing/UNICODE_INFLECTION_NOTICE',
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
        if (notice.value == 'hyphenation/ENGLISH_US_LICENSE') {
          expect(text, contains('Gerard D.C. Kuiken'));
          expect(text, contains('Copying and distribution of this file'));
          expect(text, contains('are permitted in any medium without royalty'));
          expect(text, contains('notice and this notice are preserved'));
          expect(text, isNot(contains('name: MIT')));
        } else if (notice.value == 'proofing/UNICODE_INFLECTION_NOTICE') {
          expect(text, contains('Copyright 2016-2024 Apple Inc.'));
          expect(text, contains('Copyright 2024 Unicode, Inc.'));
          expect(text, contains('Permission is hereby granted'));
          expect(text, contains('THE DATA FILES AND SOFTWARE ARE PROVIDED'));
          expect(text, contains('SPDX-License-Identifier: Unicode-3.0'));
          final original = await File(
            '${prefix}proofing/UNICODE_INFLECTION_LICENSE',
          ).readAsString();
          expect(bundled, endsWith(original));
        } else {
          expect(text, contains('Permission is hereby granted'));
          expect(text, contains('THE SOFTWARE IS PROVIDED'));
        }
        if (notice.value == 'hyphenation/ENGLISH_GB_LICENSE') {
          expect(text, contains('Dominik Wujastyk, Graham Toal'));
          expect(text, contains('name: MIT'));
        }
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
    'hyphenation notices retain the complete upstream header text',
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
      for (final entry in const {
        'ENGLISH_US_LICENSE': 'hyph-en-us.tex',
        'ENGLISH_GB_LICENSE': 'hyph-en-gb.tex',
      }.entries) {
        final source = await File('$prefix${entry.value}').readAsString();
        final patterns = RegExp(
          r'^\\patterns\{',
          multiLine: true,
        ).firstMatch(source);
        expect(patterns, isNotNull);
        expect(
          await rootBundle.loadString('$prefix${entry.key}'),
          source.substring(0, patterns!.start),
        );
      }
    },
  );
}
