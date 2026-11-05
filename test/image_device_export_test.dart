import 'dart:typed_data';

import 'package:crisp_cloud/services/image_device_export.dart';
import 'package:crisp_cloud/services/image_edit_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/image_editor_fixture.dart';

void main() {
  test('passes an immutable snapshot and preserves the copy outcome', () async {
    final input = buildImageEditorFixture();
    Uint8List? captured;
    final exporter = ImageDeviceExport(
      exporter: (bytes, name, title, format) async {
        captured = bytes;
        expect(name, 'copy.png');
        expect(format, ImageFileFormat.png);
        return ImageSaveOutcome.downloadedCopy;
      },
    );
    final outcome = await exporter.exportCopy(
      input,
      'copy.png',
      'Export',
      ImageFileFormat.png,
    );
    input[0] = 0;
    expect(captured![0], 137);
    expect(() => captured![0] = 0, throwsUnsupportedError);
    expect(outcome, ImageSaveOutcome.downloadedCopy);
  });

  test('rejects mismatched output before requesting a destination', () async {
    var called = false;
    final exporter = ImageDeviceExport(
      exporter: (bytes, name, title, format) async {
        called = true;
        return ImageSaveOutcome.savedCopy;
      },
    );
    await expectLater(
      exporter.exportCopy(
        buildImageEditorFixture(),
        'copy.jpg',
        'Export',
        ImageFileFormat.jpeg,
      ),
      throwsA(isA<ImageEditException>()),
    );
    expect(called, isFalse);
  });
}
