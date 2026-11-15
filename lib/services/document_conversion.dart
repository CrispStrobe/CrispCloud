import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as image;
import 'package:quds_office_engine/quds_office_engine.dart';

import 'csv_spreadsheet_import.dart';
import 'new_document.dart';
import 'editor_document.dart';
import 'office_pdf_service.dart';

class DocumentConversionResult {
  const DocumentConversionResult(
    this.bytes,
    this.extension, {
    this.notices = const [],
    this.pages = 0,
    this.tables = 0,
  });
  final Uint8List bytes;
  final String extension;
  final List<String> notices;
  final int pages, tables;
  NewDocumentKind get kind => NewDocumentKind.values.firstWhere(
    (v) => v.extension == extension,
    orElse: () => NewDocumentKind.text,
  );
}

const documentConversionInputLimit = 64 * 1024 * 1024;
String _sourceKind(String name, Uint8List bytes) {
  if (bytes.length >= 5 &&
      ascii.decode(bytes.take(5).toList(), allowInvalid: true) == '%PDF-') {
    return 'pdf';
  }
  return name.toLowerCase().split('.').last;
}

List<String> documentConversionFormats(String name, Uint8List bytes) =>
    switch (_sourceKind(name, bytes)) {
      'pdf' => ['docx', 'xlsx', 'pptx', 'txt'],
      'docx' ||
      'docm' ||
      'xlsx' ||
      'xltx' ||
      'xlsm' ||
      'pptx' ||
      'pptm' => ['pdf'],
      'xls' || 'xlt' => ['xlsx', 'pdf'],
      'doc' || 'dot' => ['docx', 'pdf'],
      'csv' || 'tsv' => ['xlsx', 'docx', 'pdf', 'txt'],
      'png' ||
      'jpg' ||
      'jpeg' ||
      'webp' ||
      'bmp' ||
      'tif' ||
      'tiff' ||
      'gif' => ['png', 'jpg'],
      'txt' ||
      'md' ||
      'dart' ||
      'py' ||
      'json' ||
      'xml' ||
      'bas' ||
      'nxc' ||
      'strings' => ['docx', 'pdf'],
      _ => const [],
    };

Future<DocumentConversionResult> convertDocument(
  Uint8List bytes, {
  required String sourceName,
  required String extension,
  String? password,
}) async {
  if (bytes.length > documentConversionInputLimit) {
    throw const FormatException('Conversion is limited to 64 MiB input.');
  }
  if (!documentConversionFormats(sourceName, bytes).contains(extension)) {
    throw const FormatException(
      'This conversion is unavailable for the selected source.',
    );
  }
  final result = await compute(_convert, (
    bytes: bytes,
    name: sourceName,
    extension: extension,
    password: password,
  ));
  if (extension != 'pdf') return result;
  // Font assets must be loaded on the host isolate by the established PDF service.
  final pdf = await convertOfficeToPdfResult(result.bytes, password: password);
  final notes = [
    ...result.notices,
    'PDF is an exported rendering; unsupported source layout or interactive features may differ. The new copy is unencrypted and does not retain source signatures or macros.',
  ];
  if (pdf.fonts.hasFontNotice) {
    notes.add(
      'Font substitutions or missing glyphs were reported. Review the PDF before use.',
    );
  }
  return _bounded(DocumentConversionResult(pdf.bytes, 'pdf', notices: notes));
}

Future<DocumentConversionResult> _convert(
  ({Uint8List bytes, String name, String extension, String? password}) input,
) async {
  var bytes = input.bytes;
  final source = _sourceKind(input.name, bytes), target = input.extension;
  final notes = <String>[];
  if (source == 'pdf') {
    final file = PdfFile.open(bytes, password: input.password);
    if (file.pageCount > 300) {
      throw const FormatException('PDF conversion is limited to 300 pages.');
    }
    final recovery = PdfToOffice.recover(file);
    final tables = recovery.pages.fold(0, (n, p) => n + p.tables.length);
    notes.add(
      'PDF layout reconstruction is approximate. Review reading order, fonts, tables and images in the result. Converted copies do not retain PDF signatures or encryption.',
    );
    for (final notice in recovery.notices) {
      notes.add(
        '${notice.pageIndex == null ? '' : 'Page ${notice.pageIndex! + 1}: '}${notice.message}',
      );
    }
    if (recovery.pages.any((p) => p.lines.isEmpty)) {
      notes.add(
        'Some pages have no extractable text. OCR is unavailable; scanned text cannot become editable text here.',
      );
    }
    if (target == 'xlsx' && tables == 0) {
      notes.add(
        'No ruled tables were detected. Extracted prose is placed in a Text worksheet.',
      );
    }
    if (target == 'pptx' &&
        recovery.pages.any((p) => p.images.any((i) => !i.isPng))) {
      notes.add(
        'This PPTX converter omits images that are not PNG. DOCX conversion supports JPEG and PNG images.',
      );
    }
    final output = switch (target) {
      'docx' => PdfToOffice.docxFrom(recovery),
      'xlsx' => PdfToOffice.xlsxFrom(recovery),
      'pptx' => PdfToOffice.pptxFrom(recovery),
      'txt' => Uint8List.fromList(
        utf8.encode(
          recovery.pages
              .map((p) => p.lines.map((l) => l.text).join('\n'))
              .join('\n\n'),
        ),
      ),
      _ => throw StateError('Unsupported PDF target'),
    };
    return _bounded(
      DocumentConversionResult(
        output,
        target,
        notices: notes,
        pages: file.pageCount,
        tables: tables,
      ),
    );
  }
  if (const [
    'png',
    'jpg',
    'jpeg',
    'webp',
    'bmp',
    'tif',
    'tiff',
    'gif',
  ].contains(source)) {
    final decoder = image.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null || info.width * info.height > 40000000) {
      throw const FormatException(
        'Choose a supported image up to 40 million pixels.',
      );
    }
    final decoded = decoder!.decodeFrame(0);
    if (decoded == null) {
      throw const FormatException('The image could not be decoded.');
    }
    if (info.numFrames > 1) {
      notes.add('Only the first image frame is converted.');
    }
    if (target == 'png') {
      return _bounded(
        DocumentConversionResult(
          Uint8List.fromList(image.encodePng(decoded)),
          target,
          notices: notes,
        ),
      );
    }
    final canvas = image.Image(width: decoded.width, height: decoded.height);
    image.fill(canvas, color: image.ColorRgb8(255, 255, 255));
    image.compositeImage(canvas, decoded);
    notes.add(
      'JPEG has no transparency. The image is flattened onto white at quality 95.',
    );
    return _bounded(
      DocumentConversionResult(
        Uint8List.fromList(image.encodeJpg(canvas, quality: 95)),
        target,
        notices: notes,
      ),
    );
  }
  if (source == 'xls' || source == 'xlt') {
    bytes = await OfficeIsolateSave.workbook(
      LegacySheetReader.readBytes(bytes),
      recalculate: false,
    );
    notes.add(
      'Legacy spreadsheet content is imported into a separate OOXML copy; unsupported BIFF features may not survive.',
    );
    if (target == 'xlsx') {
      return _bounded(DocumentConversionResult(bytes, target, notices: notes));
    }
  } else if (source == 'doc' || source == 'dot') {
    final result = convertLegacyWord(
      bytes,
      format: LegacyWordOutputFormat.docx,
      recover: true,
    );
    bytes = result.bytes;
    notes.addAll(
      result.limitations.map((v) => 'Legacy Word limitation: ${v.name}'),
    );
    if (target == 'docx') {
      return _bounded(DocumentConversionResult(bytes, target, notices: notes));
    }
  } else if (source == 'csv' || source == 'tsv') {
    final text = EditorDocument.decode(bytes).text;
    if (target == 'xlsx') {
      return _bounded(
        DocumentConversionResult(
          buildSpreadsheetCopy((parseSpreadsheetText(text), false)),
          target,
        ),
      );
    }
    if (target == 'txt') {
      return _bounded(
        DocumentConversionResult(Uint8List.fromList(utf8.encode(text)), target),
      );
    }
    bytes = await _textWord(text);
    notes.add(
      'Delimited text is preserved as text; choose XLSX for an editable table.',
    );
  } else if (!const [
    'docx',
    'docm',
    'xlsx',
    'xlsm',
    'xltx',
    'pptx',
    'pptm',
  ].contains(source)) {
    bytes = await _textWord(EditorDocument.decode(bytes).text);
  }
  if (target == 'docx') {
    return _bounded(DocumentConversionResult(bytes, target, notices: notes));
  }
  return DocumentConversionResult(bytes, 'pdf-input', notices: notes);
}

Future<Uint8List> _textWord(String text) async {
  if (utf8.encode(text).length > 8 * 1024 * 1024) {
    throw const FormatException('Text conversion is limited to 8 MiB.');
  }
  final lines = const LineSplitter().convert(text);
  if (lines.length > 100000) {
    throw const FormatException('Text conversion is limited to 100,000 lines.');
  }
  final document = WmlDocument.empty();
  document.sections.first.blocks
    ..clear()
    ..addAll(lines.map((line) => WmlParagraph(inlines: [WmlRun(text: line)])));
  if (document.sections.first.blocks.isEmpty) {
    document.sections.first.blocks.add(
      WmlParagraph(inlines: [WmlRun(text: '')]),
    );
  }
  return OfficeIsolateSave.word(document);
}

DocumentConversionResult _bounded(DocumentConversionResult result) {
  if (result.bytes.length > 128 * 1024 * 1024) {
    throw const FormatException('Converted output exceeds 128 MiB.');
  }
  return result;
}
