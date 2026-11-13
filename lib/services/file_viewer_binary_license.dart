import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The extracted parser is not a Pub dependency, so its upstream license must
/// be explicitly bundled and registered for the application's license screen.
void registerFileViewerBinaryLicense() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['File Viewer binary header parser (Dart adaptation)'],
      'Copyright 2026 Flyfish Viewer\n\n'
      'Adapted for CrispCloud from flyfish-dev/file-viewer at '
      'd264009ca6efb3daed79a39d1ae63133e0f25558.\n'
      'Modified: bounded Dart header inspection and additional malformed-input '
      'checks. See packages/file_viewer_binary/UPSTREAM.md in the source.\n\n'
      '${await rootBundle.loadString('packages/file_viewer_binary/LICENSE')}',
    );
  });
}
