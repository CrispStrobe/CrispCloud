import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ship the original notices for embedded Office dictionaries and font data.
void registerOfficeProofingLicenses() {
  LicenseRegistry.addLicense(() async* {
    const prefix = 'packages/quds_office_engine/third_party/';
    for (final entry in const {
      'German hyphenation patterns': 'hyphenation/LICENSE',
      'American English hyphenation patterns (LicenseRef-Kuiken-permissive)':
          'hyphenation/ENGLISH_US_LICENSE',
      'British English hyphenation patterns (MIT)':
          'hyphenation/ENGLISH_GB_LICENSE',
      'Werners Wortliste (German spelling)': 'proofing/WORTLISTE_LICENSE',
      'Quds German word supplement': 'proofing/QUDS_WORDS_LICENSE',
      'FontTools (Unicode range data)': 'fonttools/LICENSE',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString('$prefix${entry.value}'));
    }
  });
}
