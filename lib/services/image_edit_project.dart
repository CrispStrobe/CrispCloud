import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'image_edit_session.dart';

/// A self-contained editable project retains the untouched original raster and
/// the engine's serialized history. Versioning allows future migrations.
class ImageEditProject {
  ImageEditProject({
    required this.sourceName,
    required Uint8List sourceBytes,
    required this.history,
  }) : sourceBytes = Uint8List.fromList(sourceBytes).asUnmodifiableView() {
    inspectEditableImage(this.sourceBytes, fileName: sourceName);
  }

  final String sourceName;
  final Uint8List sourceBytes;
  final Map<String, dynamic> history;
  static const maxBytes = 64 * 1024 * 1024;

  Uint8List encode() {
    final result = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'type': 'crispcloud-image-project',
          'version': 1,
          'sourceName': sourceName,
          'sourceSha256': sha256.convert(sourceBytes).toString(),
          'source': base64Encode(sourceBytes),
          'history': history,
        }),
      ),
    );
    if (result.length > maxBytes)
      throw const ImageEditException(ImageEditFailure.outputTooLarge);
    return result;
  }

  static ImageEditProject decode(Uint8List bytes) {
    if (bytes.length > maxBytes)
      throw const ImageEditException(ImageEditFailure.inputTooLarge);
    try {
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic> ||
          value['type'] != 'crispcloud-image-project' ||
          value['version'] != 1 ||
          value['sourceName'] is! String ||
          value['source'] is! String ||
          value['sourceSha256'] is! String ||
          value['history'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid image project');
      }
      final name = value['sourceName'] as String;
      if (name.isEmpty ||
          name.contains('/') ||
          name.contains('\\') ||
          name == '.' ||
          name == '..') {
        throw const FormatException('Invalid source name');
      }
      final source = base64Decode(value['source'] as String);
      if (sha256.convert(source).toString() != value['sourceSha256'])
        throw const FormatException('Source checksum mismatch');
      return ImageEditProject(
        sourceName: name,
        sourceBytes: source,
        history: value['history'] as Map<String, dynamic>,
      );
    } on ImageEditException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid image project');
    }
  }
}
