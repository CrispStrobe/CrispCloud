import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_pdf_printing/dart_pdf_printing.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as image;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as md;
import 'package:pdf_document/pdf_document.dart' as pdf;
import 'package:quds_office_engine/quds_office_engine.dart' as office;

import 'csv_spreadsheet_import.dart';
import 'editor_document.dart';
import 'office_pdf_service.dart';

const printInputLimit = 64 * 1024 * 1024;

Future<void> printPdfSnapshot(
  BuildContext context,
  Uint8List bytes,
  String title, {
  String? password,
  int currentPage = 0,
}) async {
  if (bytes.length > printInputLimit) {
    throw const FormatException('Document exceeds the 64 MiB print limit.');
  }
  final document = pdf.PdfDocument.open(
    Uint8List.fromList(bytes),
    password: password ?? '',
  );
  if (!context.mounted) return;
  await printPdfWithPreview(
    context,
    document: document,
    title: title,
    currentPage: currentPage,
  );
}

Future<Uint8List> textPrintPdf(String text, String title) async {
  if (utf8.encode(text).length > 8 * 1024 * 1024) {
    throw const FormatException('Text printing is limited to 8 MiB.');
  }
  final lines = const LineSplitter().convert(text);
  if (lines.length > 100000) {
    throw const FormatException('Text printing is limited to 100,000 lines.');
  }
  final document = office.WmlDocument.empty();
  document.sections.first.blocks
    ..clear()
    ..addAll(
      (lines.isEmpty ? [''] : lines).map(
        (line) => office.WmlParagraph(
          inlines: [
            office.WmlRun(
              text: line,
              properties: office.WmlRunProps(
                asciiFont: 'Liberation Mono',
                csFont: 'Liberation Mono',
                fontSizeHalfPoints: 18,
              ),
            ),
          ],
          properties: office.WmlParagraphProps(spacingAfter: 0),
        ),
      ),
    );
  return officePrintPdf(await office.OfficeIsolateSave.word(document));
}

Future<Uint8List> officePrintPdf(Uint8List bytes) async =>
    (await convertOfficeToPdfResult(bytes)).bytes;

Uint8List imagePrintPdf(Uint8List bytes, String title) {
  if (bytes.length > printInputLimit) {
    throw const FormatException('Image exceeds the print limit.');
  }
  final decoder = image.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width > 16384 ||
      info.height > 16384 ||
      info.width > 40000000 ~/ info.height) {
    throw const FormatException('Image cannot be printed safely.');
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) {
    throw const FormatException('Image could not be decoded.');
  }
  final png = Uint8List.fromList(image.encodePng(decoded));
  if (png.length > printInputLimit) {
    throw const FormatException('Decoded image exceeds the print size limit.');
  }
  final raster = office.PdfImageCodec.decode(png);
  if (raster == null) {
    throw const FormatException('Image could not be prepared for printing.');
  }
  const pageWidth = 595.28, pageHeight = 841.89, margin = 28.35;
  final scale = math.min(
    (pageWidth - margin * 2) / raster.width,
    (pageHeight - margin * 2) / raster.height,
  );
  final w = raster.width * scale, h = raster.height * scale;
  final x = (pageWidth - w) / 2, y = (pageHeight - h) / 2;
  final document = office.PdfDocument(title: title);
  document.pages.add(
    office.PdfPage(
      width: pageWidth,
      height: pageHeight,
      content: Uint8List.fromList(
        utf8.encode('q $w 0 0 $h $x $y cm /Im0 Do Q'),
      ),
      images: [
        office.PdfEmbeddedImage(
          name: 'Im0',
          width: raster.width,
          height: raster.height,
          bytes: raster.rgb,
          maskBytes: raster.alpha,
        ),
      ],
    ),
  );
  return document.save();
}

Future<void> printPdfDocumentSnapshot(
  BuildContext context,
  pdf.PdfDocument document,
  String title, {
  int currentPage = 0,
}) async {
  await printPdfWithPreview(
    context,
    document: document,
    title: title,
    currentPage: currentPage,
  );
}

Future<Uint8List> csvPrintPdf(Uint8List source, String name) async {
  if (source.length > csvSpreadsheetInputLimit) {
    throw const FormatException('CSV printing is limited to 8 MiB.');
  }
  final rows = parseSpreadsheetText(
    EditorDocument.decode(source).text,
    delimiter: name.toLowerCase().endsWith('.tsv') ? '\t' : null,
  );
  return officePrintPdf(buildSpreadsheetCopy((rows, false)));
}

/// A readable reflowed print layout, without executing HTML or fetching remote
/// images/styles. Missing pictures are labelled rather than silently omitted.
Future<Uint8List> richTextPrintPdf(
  String source,
  String title, {
  bool markdown = false,
}) async {
  if (utf8.encode(source).length > 8 * 1024 * 1024) {
    throw const FormatException('Rich-text printing is limited to 8 MiB.');
  }
  final fragment = html.parseFragment(
    markdown
        ? md.markdownToHtml(
            source,
            extensionSet: md.ExtensionSet.gitHubFlavored,
          )
        : source,
  );
  final document = office.WmlDocument.empty();
  final blocks = document.sections.first.blocks..clear();
  var runs = <office.WmlInline>[];
  var nodes = 0;
  void flush() {
    if (runs.isEmpty) return;
    blocks.add(office.WmlParagraph(inlines: runs));
    runs = [];
  }

  void walk(
    dom.Node node,
    int depth, {
    bool bold = false,
    bool italic = false,
    bool code = false,
    int size = 22,
  }) {
    if (++nodes > 100000 || depth > 128) {
      throw const FormatException(
        'Rich-text structure exceeds the print limit.',
      );
    }
    if (node is dom.Text) {
      var text = node.data;
      if (!code) text = text.replaceAll(RegExp(r'\s+'), ' ');
      if (runs.isEmpty && text.trim().isEmpty) return;
      runs.add(
        office.WmlRun(
          text: text,
          properties: office.WmlRunProps(
            bold: bold,
            italic: italic,
            asciiFont: code ? 'Liberation Mono' : 'Liberation Sans',
            csFont: 'Liberation Sans',
            fontSizeHalfPoints: size,
          ),
        ),
      );
      return;
    }
    final tag = node is dom.Element ? (node.localName ?? '') : '';
    if (const {
      'script',
      'style',
      'head',
      'noscript',
      'template',
    }.contains(tag)) {
      return;
    }
    final block = const {
      'p',
      'div',
      'section',
      'article',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'li',
      'tr',
      'pre',
      'blockquote',
      'hr',
    }.contains(tag);
    if (block) flush();
    if (tag == 'br') {
      runs.add(office.WmlRun(text: '\n'));
    } else if (tag == 'img') {
      final alt = (node as dom.Element).attributes['alt'] ?? '';
      runs.add(office.WmlRun(text: '[Image${alt.isEmpty ? '' : ': $alt'}]'));
    } else {
      if (tag == 'li') runs.add(office.WmlRun(text: '• '));
      final heading = RegExp(r'^h[1-6]$').hasMatch(tag);
      for (final child in node.nodes) {
        walk(
          child,
          depth + 1,
          bold: bold || heading || tag == 'strong' || tag == 'b',
          italic: italic || tag == 'em' || tag == 'i',
          code: code || tag == 'pre' || tag == 'code',
          size: heading ? 34 - (int.parse(tag.substring(1)) - 1) * 2 : size,
        );
      }
      if (tag == 'td' || tag == 'th') runs.add(office.WmlRun(text: '\t'));
    }
    if (block) flush();
  }

  for (final node in fragment.nodes) {
    walk(node, 0);
  }
  flush();
  if (blocks.isEmpty) blocks.add(office.WmlParagraph());
  return officePrintPdf(await office.OfficeIsolateSave.word(document));
}
