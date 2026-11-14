// SDK-only browser entry point for the real Office recovery-copy service.
// Compile and exercise it with verify_office_device_export_web.py; the browser
// driver independently captures the download and observes URL/anchor lifetime.
// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_html/html.dart' as html;

import '../../lib/services/office_device_export.dart';

void main() {
  final button = html.ButtonElement()
    ..id = 'export-copy'
    ..text = 'Download Office recovery copy';
  final status = html.PreElement()..id = 'result';
  html.document.body!.children.addAll([button, status]);
  button.onClick.listen((_) async {
    button.disabled = true;
    try {
      final bytes = Uint8List.fromList(
        List<int>.generate(256, (index) => index),
      );
      final export = exportOfficeCopy(
        bytes,
        r'../drafts\Recovery: budget?.xlsx',
        'Save Office recovery copy',
      );
      bytes[0] = 127;
      final outcome = await export;
      if (outcome != OfficeCopyOutcome.downloadedCopy) {
        throw StateError('The browser did not report a downloaded copy.');
      }
      status.text = jsonEncode({
        'outcome': outcome!.name,
        'caller_mutation': bytes.first,
      });
      status.attributes['data-complete'] = 'true';
    } catch (error) {
      status.text = error.toString();
      status.attributes['data-error'] = 'true';
    }
  });
}
