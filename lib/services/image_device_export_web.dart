import 'dart:async';
import 'dart:typed_data';

import 'package:universal_html/html.dart' as html;

import 'image_edit_session.dart';

Future<ImageSaveOutcome?> exportImageCopy(
  Uint8List bytes,
  String suggestedName,
  String dialogTitle,
  ImageFileFormat format,
) async {
  return _exportCopy(
    bytes,
    suggestedName,
    format == ImageFileFormat.png ? 'image/png' : 'image/jpeg',
  );
}

Future<ImageSaveOutcome?> exportProjectCopy(
  Uint8List bytes,
  String suggestedName,
  String dialogTitle,
) => _exportCopy(bytes, suggestedName, 'application/json');

Future<ImageSaveOutcome?> _exportCopy(
  Uint8List bytes,
  String suggestedName,
  String mimeType,
) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', suggestedName)
    ..style.display = 'none';
  try {
    html.document.body?.children.add(anchor);
    anchor.click();
  } finally {
    anchor.remove();
    Timer(const Duration(seconds: 1), () => html.Url.revokeObjectUrl(url));
  }
  return ImageSaveOutcome.downloadedCopy;
}
