// lib/services/office_pdf_service.dart
//
// Renders Office documents (DOCX / XLSX / PPTX) to a paginated PDF using the
// pure-Dart `quds_office_engine` (MIT, no native code, all platforms).
//
// The resulting PDF is displayed with the existing pdfx page viewer, so slides
// keep their real layout and the PDF text layer remains extractable.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:quds_office_engine/quds_office_engine.dart';

import 'document_font_catalog.dart';
import 'document_fonts.dart';

const int kOfficePdfInputCap = 64 * 1024 * 1024;

class OfficePdfException implements Exception {
  final String message;
  final int? sizeBytes;
  final Object? cause;

  const OfficePdfException(this.message, {this.sizeBytes, this.cause});

  @override
  String toString() => message;
}

/// Bounded facts from emitted glyphs, separate from the complete PDF buffer.
class OfficePdfFontReport {
  const OfficePdfFontReport({
    required this.missingCodePoints,
    required this.substitutions,
    required this.diagnosticsTruncated,
  });

  final List<int> missingCodePoints;
  final List<OfficeFontSubstitution> substitutions;
  final bool diagnosticsTruncated;
  bool get hasFontNotice =>
      missingCodePoints.isNotEmpty ||
      substitutions.isNotEmpty ||
      diagnosticsTruncated;
}

class OfficePdfResult {
  const OfficePdfResult({required this.bytes, required this.fonts});
  final Uint8List bytes;
  final OfficePdfFontReport fonts;
}

/// Convert [bytes] (DOCX/XLSX/PPTX) to PDF bytes.
///
/// Runs on a background isolate on native platforms. Throws
/// [OfficePdfException] for unsupported/corrupt input or when conversion
/// exceeds the input cap.
Future<Uint8List> convertOfficeToPdf(
  Uint8List bytes, {
  String? password,
}) async => (await convertOfficeToPdfResult(bytes, password: password)).bytes;

Future<OfficePdfResult> convertOfficeToPdfResult(
  Uint8List bytes, {
  String? password,
}) async {
  if (bytes.length > kOfficePdfInputCap) {
    throw OfficePdfException(
      'This document is too large to lay out safely '
      '(${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB).',
      sizeBytes: bytes.length,
    );
  }

  try {
    final fontBytes = await DocumentFonts.loadExportFaces();
    OfficePdfResult render() {
      final diagnostics = OfficeFontDiagnostics();
      final fonts = OfficeFontSet(
        defaultFamily: 'Liberation Sans',
        diagnostics: diagnostics,
        faces: [
          for (var index = 0; index < documentFontAssets.length; index++)
            OfficeFontFace(
              font: SfntFont.parse(fontBytes[index]),
              family: documentFontAssets[index].family,
              aliases: documentFontAliases(documentFontAssets[index].family),
              weight: documentFontAssets[index].weight,
              italic: documentFontAssets[index].italic,
            ),
        ],
      );
      final pdf = OfficePdfExport.fromBytes(
        bytes,
        fonts: fonts,
        password: password,
      );
      return OfficePdfResult(
        bytes: pdf,
        fonts: OfficePdfFontReport(
          missingCodePoints: diagnostics.missingCodePoints.toList(
            growable: false,
          ),
          substitutions: diagnostics.substitutions,
          diagnosticsTruncated: diagnostics.truncated,
        ),
      );
    }

    if (kIsWeb) {
      // Isolates are unavailable on the web; run inline.
      return render();
    }
    return await Isolate.run(render);
  } catch (e) {
    throw OfficePdfException('Could not lay out this document: $e', cause: e);
  }
}
