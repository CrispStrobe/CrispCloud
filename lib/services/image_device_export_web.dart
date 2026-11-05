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
  final blob = html.Blob([
    bytes,
  ], format == ImageFileFormat.png ? 'image/png' : 'image/jpeg');
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
