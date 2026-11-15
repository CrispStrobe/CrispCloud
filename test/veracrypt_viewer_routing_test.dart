import 'dart:typed_data';

import 'package:crisp_cloud/services/internal_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const viewer = InternalViewerService();

  test('F3 routes supported container hints to credential-backed browsing', () {
    for (final name in ['vault.vc', 'vault.HC', 'legacy.TC']) {
      expect(viewer.detectMode(name), ViewerMode.archive, reason: name);
      // A container has no unencrypted signature. An accidental header magic
      // must not bypass the explicit credentials/format route.
      expect(
        viewer.detectMode(name, header: Uint8List.fromList('%PDF-'.codeUnits)),
        ViewerMode.archive,
        reason: name,
      );
      expect(isVeraCryptViewerName(name), isTrue);
    }
    expect(
      viewer.getSupportedExtensions()[ViewerMode.archive],
      containsAll(['.vc', '.hc', '.tc']),
    );
  });

  test('ordinary unknown files are not guessed to be encrypted containers', () {
    for (final name in ['vault.vc.bak', 'notes.txt', 'archive.zip', 'vault']) {
      expect(isVeraCryptViewerName(name), isFalse, reason: name);
    }
    expect(viewer.detectMode('notes.txt'), ViewerMode.text);
    expect(viewer.detectMode('archive.zip'), ViewerMode.archive);
  });
}
