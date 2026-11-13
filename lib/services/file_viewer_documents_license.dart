import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Includes the selected browser engines and their native/WASM grants.
void registerFileViewerDocumentsLicenses() {
  LicenseRegistry.addLicense(() async* {
    const prefix = 'packages/file_viewer_documents/assets/licenses/';
    yield LicenseEntryWithLineBreaks(const [
      'File Viewer selected document engines',
    ], await rootBundle.loadString('${prefix}THIRD_PARTY.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'CrisperBooks browser host (adapted for document previews)',
    ], await rootBundle.loadString('${prefix}crisperbooks-host-MIT.txt'));
  });
}
