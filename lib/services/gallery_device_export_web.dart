import 'dart:async';
import 'dart:typed_data';

import 'package:universal_html/html.dart' as html;

import 'gallery_device_export_types.dart';

Future<GalleryExportResult?> exportGalleryFile(
  Uint8List bytes,
  String suggestedName, {
  String? mimeType,
  String? dialogTitle,
}) async {
  final body = html.document.body;
  if (body == null) throw StateError('The browser download is unavailable.');
  final blob = html.Blob([bytes], mimeType ?? 'application/octet-stream');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', suggestedName)
    ..style.display = 'none';
  try {
    body.children.add(anchor);
    anchor.click();
  } finally {
    anchor.remove();
    // Leave the object URL alive until the browser starts consuming it.
    Timer(const Duration(seconds: 1), () => html.Url.revokeObjectUrl(url));
  }
  return GalleryExportResult.downloadedCopy;
}
