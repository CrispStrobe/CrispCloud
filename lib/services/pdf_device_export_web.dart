import 'dart:async';
import 'dart:typed_data';

import 'package:universal_html/html.dart' as html;

import 'pdf_edit_session.dart';

Future<PdfSaveOutcome?> exportPdfCopy(
  Uint8List bytes,
  String suggestedName,
) async {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', suggestedName)
    ..style.display = 'none';
  try {
    html.document.body?.children.add(anchor);
    anchor.click();
  } finally {
    anchor.remove();
    // Keep the URL alive while the browser starts consuming the download.
    Timer(const Duration(seconds: 1), () => html.Url.revokeObjectUrl(url));
  }
  return PdfSaveOutcome.downloadedCopy;
}
