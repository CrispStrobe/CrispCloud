import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ship the original notices with the embedded German dictionaries and patterns.
void registerOfficeProofingLicenses() {
  LicenseRegistry.addLicense(() async* {
    const prefix = 'packages/quds_office_engine/third_party/';
    for (final entry in const {
      'German hyphenation patterns': 'hyphenation/LICENSE',
      'Werners Wortliste (German spelling)': 'proofing/WORTLISTE_LICENSE',
      'Quds German word supplement': 'proofing/QUDS_WORDS_LICENSE',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString('$prefix${entry.value}'));
    }
  });
}
