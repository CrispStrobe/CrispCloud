// lib/services/pdf_text_service.dart
//
// Extract the text layer of a PDF using the platform PDF engine.
//
// macOS: PDFKit (system framework) through a MethodChannel implemented in
// macos/Runner/MainFlutterWindow.swift. Scanned PDFs have no text layer and
// return an empty string. Other platforms currently return null (the page
// rendering view is still available everywhere).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class PdfTextService {
  static const MethodChannel _channel = MethodChannel('crispcloud/pdf_text');

  /// Returns the extracted text, or null when text extraction is not
  /// supported on this platform.
  Future<String?> extractText(Uint8List bytes) async {
    if (!Platform.isMacOS && !Platform.isIOS) return null;

    final directory = await getApplicationSupportDirectory();
    final path =
        '${directory.path}/viewer_pdf_text_${DateTime.now().microsecondsSinceEpoch}.pdf';
    final file = File(path);
    try {
      await file.writeAsBytes(bytes, flush: true);
      return await _channel.invokeMethod<String>('extractText', {
        'path': path,
      });
    } on PlatformException catch (e) {
      throw PdfTextException(e.message ?? 'PDF text extraction failed',
          code: e.message == null ? 'pdf_generic' : e.code);
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best effort cleanup.
      }
    }
  }
}

class PdfTextException implements Exception {
  final String message;
  final String? code;
  const PdfTextException(this.message, {this.code});

  @override
  String toString() => message;
}
