import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import 'image_edit_session.dart';
import 'local_file_service.dart';

class ImageOverlay {
  ImageOverlay({required this.name, required Uint8List bytes})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    inspectEditableImage(this.bytes, fileName: name);
  }
  final String name;
  final Uint8List bytes;
}

typedef ImageOverlayPicker = Future<ImageOverlay?> Function(String dialogTitle);

Future<ImageOverlay?> pickImageOverlay(String dialogTitle) async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: dialogTitle,
    type: FileType.custom,
    allowedExtensions: const ['png', 'jpg', 'jpeg'],
    withData: kIsWeb,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  if (file.size > kImageEditorInputLimitBytes) {
    throw const ImageEditException(ImageEditFailure.inputTooLarge);
  }
  final path = file.path;
  final bytes =
      file.bytes ??
      (path == null
          ? throw StateError('The selected image is unavailable')
          : await LocalFileService().readFileForEdit(
              path,
              maxBytes: kImageEditorInputLimitBytes,
            ));
  return ImageOverlay(name: file.name, bytes: bytes);
}

WidgetLayer imageOverlayLayer(ImageOverlay overlay) => WidgetLayer(
  widget: Image.memory(overlay.bytes),
  exportConfigs: WidgetLayerExportConfigs(
    id: 'crispcloud.image-overlay.v1',
    meta: {'name': overlay.name, 'bytes': base64Encode(overlay.bytes)},
  ),
);

/// Restores only the self-contained widget types supported by CrispCloud.
Widget imageProjectWidgetLoader(String id, {Map<String, dynamic>? meta}) {
  if (id != 'crispcloud.image-overlay.v1' ||
      meta?['name'] is! String ||
      meta?['bytes'] is! String) {
    throw const FormatException('Unsupported image project layer');
  }
  final encoded = meta!['bytes'] as String;
  if (encoded.length > ((kImageEditorInputLimitBytes + 2) ~/ 3) * 4) {
    throw const ImageEditException(ImageEditFailure.inputTooLarge);
  }
  final overlay = ImageOverlay(
    name: meta['name'] as String,
    bytes: base64Decode(encoded),
  );
  return Image.memory(overlay.bytes);
}
