import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Flutter collects Dart package LICENSE files. These notices belong to the
/// bundled JavaScript/native sources and must also be available in About.
void registerEbookLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final entry in const {
      'foliate-js':
          'packages/crisp_ebook_reader/assets/licenses/foliate-js-LICENSE.txt',
      'zip.js':
          'packages/crisp_ebook_reader/assets/licenses/zip-js-LICENSE.txt',
      'SJCL (bundled in zip.js)':
          'packages/crisp_ebook_reader/assets/licenses/sjcl-LICENSE.txt',
      'fflate':
          'packages/crisp_ebook_reader/assets/licenses/fflate-LICENSE.txt',
      'Kindling and converter dependencies':
          'packages/crisp_ebook_conversion/licensing/THIRD_PARTY_LICENSES.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString(entry.value));
    }
  });
}
