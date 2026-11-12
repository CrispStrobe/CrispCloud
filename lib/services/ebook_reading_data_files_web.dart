import 'dart:async';
import 'dart:typed_data';

import 'package:universal_html/html.dart' as html;

import 'ebook_edit_session.dart';

Future<EbookSaveOutcome?> exportReadingData(
  Uint8List bytes,
  String name,
) async {
  final url = html.Url.createObjectUrlFromBlob(
    html.Blob([bytes], 'application/json;charset=utf-8'),
  );
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', name)
    ..style.display = 'none';
  try {
    html.document.body?.children.add(anchor);
    anchor.click();
  } finally {
    anchor.remove();
    Timer(const Duration(seconds: 1), () => html.Url.revokeObjectUrl(url));
  }
  return EbookSaveOutcome.downloadedCopy;
}
