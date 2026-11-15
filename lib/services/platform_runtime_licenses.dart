import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform runtime notices not collected from the Dart wrapper's LICENSE.
void registerPlatformRuntimeLicenses() {
  LicenseRegistry.addLicense(() async* {
    if (const bool.fromEnvironment('CRISP_ENABLE_FUSE')) {
      yield LicenseEntryWithLineBreaks(
        const ['Optional macFUSE/FUSE-T libfuse API headers'],
        'Included only when the native mount helper is enabled at compile time. '
        'The separately installed runtimes have independent commercial-use terms; '
        'no runtime licence is granted by this header notice.\n'
        'https://github.com/macfuse/macfuse/wiki/Open-Source-Status\n'
        'https://github.com/macos-fuse-t/fuse-t/blob/main/License.txt\n\n'
        '${await rootBundle.loadString('macos/vendor/fuse/COPYING.LIB')}',
      );
    }

    yield LicenseEntryWithLineBreaks(
      const ['PDFium (Windows renderer)'],
      'PDFium 97.0.4690.0, as selected by pdfx 2.9.2 on Windows.\n'
      'Source and build: https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium/4690\n'
      'The original archive licence follows. Other platforms use their own PDF backends.\n\n'
      '${await rootBundle.loadString('assets/licenses/pdfium/LICENSE.txt')}',
    );
  });
}
