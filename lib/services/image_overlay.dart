import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import 'image_edit_session.dart';
import 'image_export_options.dart';
import 'image_gif_codec.dart';
import 'local_file_service.dart';

class ImageOverlay {
  ImageOverlay({required this.name, required Uint8List bytes})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (this.bytes.length > kImageEditorInputLimitBytes) {
      throw const ImageEditException(ImageEditFailure.inputTooLarge);
    }
    final lower = name.toLowerCase();
    if (lower.endsWith('.webp')) {
      validateImageExport(this.bytes, ImageExportFormat.webp);
    } else if (lower.endsWith('.gif')) {
      decodeStaticGif(this.bytes);
    } else {
      inspectEditableImage(this.bytes, fileName: name);
    }
    displayBytes = Uint8List.fromList(this.bytes);
  }
  final String name;
  final Uint8List bytes;
  late final Uint8List displayBytes;
}

typedef ImageOverlayPicker = Future<ImageOverlay?> Function(String dialogTitle);

Future<ImageOverlay?> pickImageOverlay(String dialogTitle) async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: dialogTitle,
    type: FileType.custom,
    allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
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
  widget: Image.memory(overlay.displayBytes),
  exportConfigs: WidgetLayerExportConfigs(
    id: 'crispcloud.image-overlay.v1',
    meta: {'name': overlay.name, 'bytes': base64Encode(overlay.bytes)},
  ),
);

/// Decodes each embedded overlay once and keeps the same byte identity for the
/// image cache and the restored widget, so capture cannot race image loading.
class ImageProjectOverlayCache {
  final Map<String, ImageOverlay> _overlays = {};

  ImageOverlay _overlay(String id, Map<String, dynamic>? meta) {
    if (id != 'crispcloud.image-overlay.v1' ||
        meta?['name'] is! String ||
        meta?['bytes'] is! String) {
      throw const FormatException('Unsupported image project layer');
    }
    final encoded = meta!['bytes'] as String;
    if (encoded.length > ((kImageEditorInputLimitBytes + 2) ~/ 3) * 4) {
      throw const ImageEditException(ImageEditFailure.inputTooLarge);
    }
    return _overlays.putIfAbsent(
      encoded,
      () => ImageOverlay(
        name: meta['name'] as String,
        bytes: base64Decode(encoded),
      ),
    );
  }

  Widget load(String id, {Map<String, dynamic>? meta}) =>
      Image.memory(_overlay(id, meta).displayBytes);

  Future<void> precache(BuildContext context, Object? value) async {
    final found = <ImageOverlay>[];
    void collect(Object? item) {
      if (item is Map) {
        if (item['id'] == 'crispcloud.image-overlay.v1') {
          final rawMeta = item['meta'];
          if (rawMeta is! Map<String, dynamic>)
            throw const FormatException('Invalid image overlay');
          found.add(_overlay(item['id'] as String, rawMeta));
        }
        for (final child in item.values) {
          collect(child);
        }
      } else if (item is List) {
        for (final child in item) {
          collect(child);
        }
      }
    }

    collect(value);
    for (final overlay in found.toSet()) {
      Object? imageError;
      await precacheImage(
        MemoryImage(overlay.displayBytes),
        context,
        onError: (error, _) => imageError = error,
      );
      if (imageError != null)
        throw const ImageEditException(ImageEditFailure.invalidImage);
    }
  }
}
