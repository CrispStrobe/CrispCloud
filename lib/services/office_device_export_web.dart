import 'dart:async';
import 'dart:typed_data';

import 'package:universal_html/html.dart' as html;

import 'office_device_export_types.dart';

Future<OfficeCopyOutcome?> exportOfficeCopy(
  Uint8List bytes,
  String name,
  String dialogTitle,
) async {
  final url = html.Url.createObjectUrlFromBlob(
    html.Blob([bytes], 'application/octet-stream'),
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
  return OfficeCopyOutcome.downloadedCopy;
}
