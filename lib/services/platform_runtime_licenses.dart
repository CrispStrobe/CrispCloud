import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform runtime notices not collected from the Dart wrapper's LICENSE.
void registerPlatformRuntimeLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['PDFium (Windows renderer)'],
      'PDFium 97.0.4690.0, as selected by pdfx 2.9.2 on Windows.\n'
      'Source and build: https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium/4690\n'
      'The original archive licence follows. Other platforms use their own PDF backends.\n\n'
      '${await rootBundle.loadString('assets/licenses/pdfium/LICENSE.txt')}',
    );
  });
}
