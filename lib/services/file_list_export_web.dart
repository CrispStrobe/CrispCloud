import 'dart:async';
import 'dart:convert';

import 'package:universal_html/html.dart' as html;

Future<String?> exportFileListText(String text) async {
  final blob = html.Blob([utf8.encode(text)], 'text/plain;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', 'file-list.txt')
    ..style.display = 'none';
  try {
    html.document.body?.children.add(anchor);
    anchor.click();
  } finally {
    anchor.remove();
    Timer(const Duration(seconds: 1), () => html.Url.revokeObjectUrl(url));
  }
  return 'File list download started.';
}
