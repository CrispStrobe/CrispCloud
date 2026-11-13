import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Preserve the parser's matching-source location and retained third-party grants.
void registerLegacyDocLicenses() {
  LicenseRegistry.addLicense(() async* {
    const prefix = 'packages/legacy_doc_parser/';
    final upstream = jsonDecode(
      await rootBundle.loadString('${prefix}UPSTREAM.json'),
    ) as Map<String, dynamic>;
    yield LicenseEntryWithLineBreaks(
      const ['legacy_doc_parser source and notices'],
      'Matching source: https://github.com/${upstream['repository']}/tree/'
      '${upstream['commit']}\n\n'
      '${await rootBundle.loadString('${prefix}NOTICE')}',
    );
    for (final entry in const {
      'WPF ISF reference algorithms': 'wpf-isf/LICENSE.txt',
      'Quds compound-file helpers': 'quds_office_engine-MIT.txt',
      'JSDoc formatting reader reference': 'JSDoc-0BSD.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString('${prefix}third_party/${entry.value}'));
    }
  });
}
