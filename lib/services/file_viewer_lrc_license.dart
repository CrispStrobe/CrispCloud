import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Register the selected Apache source because the Dart adaptation is not a
/// separately published Pub dependency with an automatically collected license.
void registerFileViewerLrcLicense() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['File Viewer LRC parser (Dart adaptation)'],
      'Copyright 2026 Flyfish Viewer\n\n'
      'Adapted for CrispCloud from flyfish-dev/file-viewer at '
      'd264009ca6efb3daed79a39d1ae63133e0f25558.\n'
      'Modified: bounded Dart parsing, immutable models, preserved source text '
      'and stable timing. See packages/file_viewer_lrc/UPSTREAM.md in the '
      'source.\n\n'
      '${await rootBundle.loadString('packages/file_viewer_lrc/LICENSE')}',
    );
  });
}
