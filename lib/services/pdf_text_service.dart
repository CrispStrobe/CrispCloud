// lib/services/pdf_text_service.dart
//
// Extract the text layer of a PDF using the platform PDF engine.
//
// macOS: PDFKit (system framework) through a MethodChannel implemented in
// macos/Runner/MainFlutterWindow.swift. Scanned PDFs have no text layer and
// return an empty string. Windows uses the PDFium renderer already bundled
// with pdfx. Other platforms share the portable Office engine.

import 'dart:io';

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quds_office_engine/pdf_file.dart';

class PdfTextService {
  static const MethodChannel _channel = MethodChannel('crispcloud/pdf_text');

  /// Returns the available text layer, up to the preview's output budget.
  Future<String> extractText(Uint8List bytes) async {
    if (!kIsWeb) {
      try {
        if (Platform.isWindows) {
          final text = await _channel.invokeMethod<String>(
            'extractText',
            bytes,
          );
          if (text != null) return text;
        } else if (Platform.isMacOS || Platform.isIOS) {
          final text = await _extractApple(bytes);
          if (text != null) return text;
        }
      } on MissingPluginException {
        // The portable engine also covers builds without a native adapter.
      } on PlatformException {
        // Older native parsers may refuse a file the portable engine can open.
      }
    }
    return compute(_extractPortable, bytes, debugLabel: 'pdf-text-layer');
  }

  Future<String?> _extractApple(Uint8List bytes) async {
    final directory = await getApplicationSupportDirectory();
    final path =
        '${directory.path}/viewer_pdf_text_${DateTime.now().microsecondsSinceEpoch}.pdf';
    final file = File(path);
    try {
      await file.writeAsBytes(bytes, flush: true);
      return await _channel.invokeMethod<String>('extractText', {'path': path});
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best effort cleanup.
      }
    }
  }
}

String _extractPortable(Uint8List bytes) {
  const limit = 2 * 1024 * 1024;
  final file = PdfFile.open(bytes);
  final result = StringBuffer();
  for (var page = 0; page < file.pageCount && result.length < limit; page++) {
    final text = file.displayList(page).plainText;
    if (text.isEmpty) continue;
    if (result.isNotEmpty && result.length <= limit - 2) result.write('\n\n');
    final remaining = limit - result.length;
    result.write(
      text.length <= remaining ? text : text.substring(0, remaining),
    );
  }
  return result.toString();
}

class PdfTextException implements Exception {
  final String message;
  final String? code;
  const PdfTextException(this.message, {this.code});

  @override
  String toString() => message;
}
