// lib/services/office_document_service.dart
//
// Structured extraction for Office/EPUB documents used by the F3 viewer.
//
// Unlike a flat tag-strip, this produces:
//   * markdown  — headings, bold/italic runs, lists and tables (rendered by
//     flutter_markdown, so the result looks like a document)
//   * plainText — readable text for copying/search
//   * csv       — spreadsheet data rendered as a table
//   * rawXml    — the primary XML part, for inspection
//
// Parsing goes through the hardened archive layer (per-entry caps), so
// malformed or oversized documents cannot exhaust memory.

import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'archive_viewer_service.dart';
import 'legacy_word_document.dart';
import 'office_package_parts.dart';

const int _kOfficePartCap = 8 * 1024 * 1024;
const int _kOfficeRawCap = 4 * 1024 * 1024;
const String _wordNamespace =
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const String _officeRelationshipNamespace =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

enum OfficeDocumentKind { document, spreadsheet, presentation, ebook }

enum OfficePreviewFallback {
  legacyPresentation,
  extractionFailed,
  missingDocx,
  missingOds,
  missingOdp,
  missingOdt,
}

enum OfficeHeadingKind { sheet, slide }

class OfficeGeneratedHeading {
  final int start;
  final int end;
  final OfficeHeadingKind kind;
  final int number;
  const OfficeGeneratedHeading(this.start, this.end, this.kind, this.number);
}

class OfficeDocument {
  final OfficeDocumentKind kind;
  final String markdown;
  final String plainText;
  final String? csv;
  final String? rawXml;
  final String? note;
  final SlideDeck? deck;
  final OfficePreviewFallback? fallback;
  final List<OfficeGeneratedHeading> markdownHeadings;
  final List<OfficeGeneratedHeading> textHeadings;
  final List<OfficeGeneratedHeading> csvHeadings;

  const OfficeDocument({
    required this.kind,
    required this.markdown,
    required this.plainText,
    this.csv,
    this.rawXml,
    this.note,
    this.deck,
    this.fallback,
    this.markdownHeadings = const [],
    this.textHeadings = const [],
    this.csvHeadings = const [],
  });
}

/// A parsed presentation deck (currently PPTX) rendered approximately.
class SlideDeck {
  final int widthEmu;
  final int heightEmu;
  final List<SlidePage> slides;

  const SlideDeck({
    required this.widthEmu,
    required this.heightEmu,
    required this.slides,
  });
}

class SlidePage {
  final String? backgroundHex;
  final List<SlideShape> shapes;

  const SlidePage({this.backgroundHex, required this.shapes});
}

class SlideShape {
  final int x;
  final int y;
  final int width;
  final int height;
  final String? text;
  final double fontSizePt;
  final bool bold;
  final String? textColorHex;
  final String? fillColorHex;
  final Uint8List? image;

  const SlideShape({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.text,
    this.fontSizePt = 18,
    this.bold = false,
    this.textColorHex,
    this.fillColorHex,
    this.image,
  });
}

Future<OfficeDocument> parseOfficeDocument(
  Uint8List bytes,
  String filename,
) async {
  final ext = filename.split('.').last.toLowerCase();
  // Legacy binary PowerPoint is an OLE container, not a ZIP; give a clear
  // message instead of a generic extraction failure.
  if (ext == 'ppt' || ext == 'pps') {
    return const OfficeDocument(
      kind: OfficeDocumentKind.presentation,
      fallback: OfficePreviewFallback.legacyPresentation,
      markdown: '',
      plainText:
          '(Legacy PowerPoint (.ppt) files cannot be rendered inline. '
          'Use the system preview (Quick Look) button on macOS/iOS, '
          'or save the file as .pptx.)',
      note: 'Legacy .ppt format is not supported; Hex view is available.',
    );
  }
  ViewerArchive? archive;
  try {
    if (ext == 'doc' || ext == 'dot') {
      return OfficeDocument(
        kind: OfficeDocumentKind.document,
        markdown: '',
        plainText: extractLegacyWordText(bytes),
        note:
            'Word binary text preview. Formatting, images, headers, notes '
            'and tracked changes are not reproduced. Save as DOCX to edit.',
      );
    }
    archive = await openViewerArchive(bytes, name: filename);

    switch (ext) {
      case 'docx':
      case 'docm':
      case 'dotx':
      case 'dotm':
        return await _parseDocx(archive);
      case 'xlsx':
      case 'xlsm':
      case 'xltx':
        return await _parseSpreadsheet(archive, isOds: false);
      case 'pptx':
      case 'pptm':
      case 'potx':
        return await _parsePptx(archive);
      case 'odt':
        return await _parseOdt(archive);
      case 'ods':
        return await _parseSpreadsheet(archive, isOds: true);
      case 'odp':
        return await _parseOdp(archive);
      case 'epub':
        return await _parseEpub(archive);
      default:
        return await _parseDocx(archive);
    }
  } catch (e) {
    return OfficeDocument(
      kind: OfficeDocumentKind.document,
      markdown: '',
      plainText: '(Could not extract text from this document)',
      fallback: OfficePreviewFallback.extractionFailed,
      note: e.toString(),
    );
  } finally {
    await archive?.close();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<String?> _readPart(ViewerArchive archive, String path) async {
  final matches = archive.members
      .where((m) => m.isFile && m.name == path)
      .toList();
  if (matches.isEmpty) return null;
  final member = matches.first;
  if (member.size > _kOfficePartCap) return null;
  try {
    final data = await archive.readMember(member, maxBytes: _kOfficePartCap);
    return utf8.decode(data, allowMalformed: true);
  } on ArchiveViewException {
    return null;
  }
}

String _stripMarkdown(String markdown) {
  var text = markdown.replaceAll('  \n', '\n');
  text = text.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
  text = text.replaceAllMapped(
    RegExp(r'\*\*(.*?)\*\*'),
    (m) => m.group(1) ?? '',
  );
  text = text.replaceAllMapped(RegExp(r'\*(.*?)\*'), (m) => m.group(1) ?? '');
  text = text.replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ');
  // Table rows → tab-separated cells; drop separator rows.
  final lines = <String>[];
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (RegExp(r'^\|?\s*:?-{3,}').hasMatch(trimmed)) continue;
    if (trimmed.startsWith('|')) {
      final cells = trimmed
          .split('|')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .toList();
      if (cells.isNotEmpty) {
        lines.add(cells.join('  |  '));
        continue;
      }
    }
    lines.add(line);
  }
  return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

(String, List<OfficeGeneratedHeading>) _plainWithHeadings(
  String markdown,
  List<OfficeGeneratedHeading> headings,
) {
  var marker = '\uE000';
  while (markdown.contains(marker)) {
    marker += '\uE000';
  }
  var marked = markdown;
  for (var i = headings.length - 1; i >= 0; i--) {
    final h = headings[i];
    marked = marked.replaceRange(h.start, h.end, '$marker$i$marker');
  }
  final stripped = _stripMarkdown(marked);
  final result = StringBuffer();
  final mapped = <OfficeGeneratedHeading>[];
  var offset = 0;
  for (var i = 0; i < headings.length; i++) {
    final token = '$marker$i$marker';
    final start = stripped.indexOf(token, offset);
    result.write(stripped.substring(offset, start));
    final heading = headings[i];
    final label = markdown.substring(heading.start, heading.end);
    final newStart = result.length;
    result.write(label);
    mapped.add(
      OfficeGeneratedHeading(
        newStart,
        result.length,
        heading.kind,
        heading.number,
      ),
    );
    offset = start + token.length;
  }
  result.write(stripped.substring(offset));
  return (result.toString(), mapped);
}

void _writeHeading(
  StringBuffer buffer,
  String prefix,
  OfficeHeadingKind kind,
  int number,
  List<OfficeGeneratedHeading> headings, {
  String? name,
}) {
  if (name != null && name.isNotEmpty) {
    // Workbook sheet names are document content, never generated UI labels.
    buffer.writeln('$prefix$name');
    return;
  }
  final label =
      '${kind == OfficeHeadingKind.sheet ? 'Sheet' : 'Slide'} $number';
  final start = buffer.length + prefix.length;
  headings.add(
    OfficeGeneratedHeading(start, start + label.length, kind, number),
  );
  buffer.writeln('$prefix$label');
}

String _escapePipes(String value) => value.replaceAll('|', r'\|');

String _csvCell(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

int _columnIndex(String cellRef) {
  var value = 0;
  for (final code in cellRef.codeUnits) {
    if (code >= 65 && code <= 90) {
      value = value * 26 + (code - 64);
    } else if (code >= 97 && code <= 122) {
      value = value * 26 + (code - 96);
    } else {
      break;
    }
  }
  return value - 1;
}

int _sortedNumber(String path, String prefix) {
  final match = RegExp('$prefix(\\d+)\\.xml\$').firstMatch(path);
  return int.tryParse(match?.group(1) ?? '') ?? 0;
}

// ---------------------------------------------------------------------------
// DOCX
// ---------------------------------------------------------------------------

Future<List<OfficePartRelationship>> _officePartRelationships(
  ViewerArchive archive,
  String owner,
) =>
    OfficePackageParts((name) => _readPart(archive, name)).relationships(owner);

Future<String> _officeMainPart(ViewerArchive archive, String fallback) =>
    OfficePackageParts((name) => _readPart(archive, name)).mainPart(fallback);

Future<OfficeDocument> _parseDocx(ViewerArchive archive) async {
  final mainPart = await _officeMainPart(archive, 'word/document.xml');
  final xml = await _readPart(archive, mainPart);
  if (xml == null) {
    return const OfficeDocument(
      kind: OfficeDocumentKind.document,
      markdown: '',
      plainText: '(No document.xml found in this DOCX)',
      fallback: OfficePreviewFallback.missingDocx,
    );
  }

  final rels = await _officePartRelationships(archive, mainPart);
  final notes = <String, XmlElement>{};
  for (final kind in ['footnote', 'endnote']) {
    final path =
        rels.where((rel) => rel.type.endsWith('/${kind}s')).firstOrNull?.path ??
        p.posix.normalize(
          p.posix.join(p.posix.dirname(mainPart), '${kind}s.xml'),
        );
    final noteXml = await _readPart(archive, path);
    if (noteXml == null) continue;
    for (final note in XmlDocument.parse(
      noteXml,
    ).findAllElements(kind, namespace: _wordNamespace)) {
      final id = note.getAttribute('id', namespace: _wordNamespace);
      final type = note.getAttribute('type', namespace: _wordNamespace);
      if (id != null && (type == null || type == 'normal')) {
        notes['$kind:$id'] = note;
      }
    }
  }
  final markdown = _docxToMarkdown(xml, notes: notes);
  return OfficeDocument(
    kind: OfficeDocumentKind.document,
    markdown: markdown,
    plainText: _stripMarkdown(markdown),
    rawXml: _capRaw(xml, mainPart),
  );
}

String _docxToMarkdown(String xml, {Map<String, XmlElement> notes = const {}}) {
  final document = XmlDocument.parse(xml);
  final body = document
      .findAllElements('body', namespace: _wordNamespace)
      .firstOrNull;
  if (body == null) return '';
  final references = <String, int>{};
  String reference(String kind, String id) {
    final label = references.putIfAbsent(
      '$kind:$id',
      () => references.length + 1,
    );
    return '[$label]';
  }

  final blocks = _docxBlocks(body, reference: reference);
  for (final entry in references.entries) {
    final note = notes[entry.key];
    if (note == null) continue;
    final content = _docxBlocks(note).join('\n\n');
    if (content.isNotEmpty) blocks.add('[${entry.value}] $content');
  }
  return blocks.join('\n\n').trim();
}

List<String> _docxBlocks(
  XmlElement container, {
  String Function(String kind, String id)? reference,
}) {
  final blocks = <String>[];
  for (final element in container.childElements) {
    switch (element.localName) {
      case 'p':
        final block = _docxParagraph(element, reference: reference);
        if (block.isNotEmpty) blocks.add(block);
      case 'tbl':
        final table = _docxTable(element, reference: reference);
        if (table.isNotEmpty) blocks.add(table);
    }
  }
  return blocks;
}

String _docxParagraph(
  XmlElement paragraph, {
  String Function(String kind, String id)? reference,
}) {
  final style =
      paragraph
          .findAllElements('pStyle', namespace: _wordNamespace)
          .firstOrNull
          ?.getAttribute('val', namespace: _wordNamespace) ??
      '';
  final isList = paragraph
      .findAllElements('numPr', namespace: _wordNamespace)
      .any(
        (numbering) =>
            numbering
                .findElements('numId', namespace: _wordNamespace)
                .firstOrNull
                ?.getAttribute('val', namespace: _wordNamespace) !=
            '0',
      );

  final text = _docxRuns(paragraph, reference: reference).trim();
  if (text.isEmpty) return '';

  final lower = style.toLowerCase();
  if (lower == 'title') return '# $text';
  if (lower.startsWith('heading')) {
    final level = (int.tryParse(style.replaceAll(RegExp('[^0-9]'), '')) ?? 1)
        .clamp(1, 6);
    return '${'#' * level} $text';
  }
  if (isList) return '- $text';
  return text;
}

bool _docxEnabled(XmlElement? property) {
  if (property == null) return false;
  final value = property
      .getAttribute('val', namespace: _wordNamespace)
      ?.toLowerCase();
  return value != '0' && value != 'false' && value != 'off';
}

String _docxRuns(
  XmlElement paragraph, {
  String Function(String kind, String id)? reference,
}) {
  final runs = <String>[];
  for (final run in paragraph.findAllElements('r', namespace: _wordNamespace)) {
    final buffer = StringBuffer();
    for (final element in run.findAllElements('*', namespace: _wordNamespace)) {
      switch (element.localName) {
        case 't':
          buffer.write(element.innerText);
        case 'tab':
          buffer.write('\t');
        case 'br':
        case 'cr':
          buffer.write('\n');
        case 'noBreakHyphen':
          buffer.write('\u2011');
        case 'softHyphen':
          buffer.write('\u00ad');
        case 'footnoteReference':
        case 'endnoteReference':
          final id = element.getAttribute('id', namespace: _wordNamespace);
          if (id != null && reference != null) {
            buffer.write(
              reference(element.localName.replaceAll('Reference', ''), id),
            );
          }
      }
    }
    final text = buffer.toString();
    if (text.isEmpty) continue;
    final properties = run
        .findElements('rPr', namespace: _wordNamespace)
        .firstOrNull;
    final bold = _docxEnabled(
      properties?.findElements('b', namespace: _wordNamespace).firstOrNull,
    );
    final italic = _docxEnabled(
      properties?.findElements('i', namespace: _wordNamespace).firstOrNull,
    );
    runs.add(
      text
          .split('\n')
          .map((line) {
            if (line.isEmpty) return '';
            var value = line;
            if (bold) value = '**$value**';
            if (italic) value = '*$value*';
            return value;
          })
          .join('  \n'),
    );
  }
  return runs.join();
}

String _docxTable(
  XmlElement table, {
  String Function(String kind, String id)? reference,
}) {
  final rows = <List<String>>[];
  for (final row in table.findElements('tr', namespace: _wordNamespace)) {
    final cells = <String>[];
    for (final cell in row.findElements('tc', namespace: _wordNamespace)) {
      final text = cell
          .findAllElements('p', namespace: _wordNamespace)
          .map((element) => _docxRuns(element, reference: reference))
          .join(' ')
          .replaceAll('  \n', ' ')
          .trim();
      cells.add(_escapePipes(text));
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  return _markdownTable(rows);
}

String _markdownTable(List<List<String>> rows) {
  if (rows.isEmpty) return '';
  final width = rows.map((row) => row.length).reduce((a, b) => a > b ? a : b);
  final buffer = StringBuffer();
  for (var i = 0; i < rows.length; i++) {
    final cells = List<String>.from(rows[i])
      ..addAll(List<String>.filled(width - rows[i].length, ''));
    buffer.writeln('| ${cells.join(' | ')} |');
    if (i == 0) {
      buffer.writeln('| ${List<String>.filled(width, '---').join(' | ')} |');
    }
  }
  return buffer.toString().trim();
}

// ---------------------------------------------------------------------------
// XLSX / ODS
// ---------------------------------------------------------------------------

Future<OfficeDocument> _parseSpreadsheet(
  ViewerArchive archive, {
  required bool isOds,
}) async {
  if (isOds) return _parseOds(archive);

  final workbookPath = await _officeMainPart(archive, 'xl/workbook.xml');
  final workbookXml = await _readPart(archive, workbookPath);
  final rels = await _officePartRelationships(archive, workbookPath);
  final sharedPath =
      rels
          .where((rel) => rel.type.endsWith('/sharedStrings'))
          .firstOrNull
          ?.path ??
      p.posix.join(p.posix.dirname(workbookPath), 'sharedStrings.xml');
  final sharedXml = await _readPart(archive, sharedPath);
  final shared = <String>[];
  if (sharedXml != null) {
    final document = XmlDocument.parse(sharedXml);
    for (final item in document.findAllElements('si', namespace: '*')) {
      shared.add(
        item
            .findAllElements('t', namespace: '*')
            .map((e) => e.innerText)
            .join(),
      );
    }
  }

  final sheets = <({String path, String? name})>[];
  if (workbookXml != null) {
    final targets = <String, String>{
      for (final rel in rels)
        if (rel.type.endsWith('/worksheet')) rel.id: rel.path,
    };
    for (final sheet in XmlDocument.parse(
      workbookXml,
    ).findAllElements('sheet', namespace: '*')) {
      final id = sheet.getAttribute(
        'id',
        namespace: _officeRelationshipNamespace,
      );
      final path = targets[id];
      if (path != null) {
        sheets.add((path: path, name: sheet.getAttribute('name')));
      }
    }
  } else {
    // Minimal/legacy extraction fixtures may have no workbook part. In that
    // case only, retain the best-effort scan, with natural sheet-number order.
    final paths =
        archive.members
            .where(
              (m) =>
                  m.isFile &&
                  m.name.startsWith('xl/worksheets/') &&
                  m.name.endsWith('.xml'),
            )
            .map((m) => m.name)
            .toList()
          ..sort((a, b) {
            final first = _sortedNumber(a, 'sheet');
            final second = _sortedNumber(b, 'sheet');
            return first > 0 && second > 0
                ? first.compareTo(second)
                : a.compareTo(b);
          });
    sheets.addAll(paths.map((path) => (path: path, name: null)));
  }

  final markdown = StringBuffer();
  final csv = StringBuffer();
  final headings = <OfficeGeneratedHeading>[];
  final csvHeadings = <OfficeGeneratedHeading>[];
  var sheetNumber = 0;
  for (final sheet in sheets) {
    sheetNumber++;
    final xml = await _readPart(archive, sheet.path);
    if (xml == null) continue;
    final rows = _xlsxRows(xml, shared);
    if (rows.isEmpty && sheet.name == null) continue;
    _writeHeading(
      markdown,
      '## ',
      OfficeHeadingKind.sheet,
      sheetNumber,
      headings,
      name: sheet.name,
    );
    markdown.writeln();
    markdown.writeln(_markdownTable(rows));
    markdown.writeln();
    _writeHeading(
      csv,
      '# ',
      OfficeHeadingKind.sheet,
      sheetNumber,
      csvHeadings,
      name: sheet.name,
    );
    for (final row in rows) {
      csv.writeln(row.map(_csvCell).join(','));
    }
    csv.writeln();
  }

  final md = markdown.toString().trim();
  final (plain, textHeadings) = _plainWithHeadings(md, headings);
  return OfficeDocument(
    kind: OfficeDocumentKind.spreadsheet,
    markdown: md,
    plainText: plain,
    markdownHeadings: headings,
    textHeadings: textHeadings,
    csv: csv.toString().trim(),
    csvHeadings: csvHeadings,
    rawXml: await _rawPart(archive, sheets.firstOrNull?.path),
  );
}

List<List<String>> _xlsxRows(String xml, List<String> shared) {
  final document = XmlDocument.parse(xml);
  final rows = <List<String>>[];
  for (final row in document.findAllElements('row', namespace: '*')) {
    final cells = <int, String>{};
    for (final cell in row.findAllElements('c', namespace: '*')) {
      final ref = cell.getAttribute('r') ?? '';
      final type = cell.getAttribute('t');
      String value;
      if (type == 's') {
        final index = int.tryParse(
          cell.findAllElements('v', namespace: '*').firstOrNull?.innerText ??
              '',
        );
        value = (index != null && index >= 0 && index < shared.length)
            ? shared[index]
            : '';
      } else if (type == 'inlineStr') {
        value = cell
            .findAllElements('t', namespace: '*')
            .map((e) => e.innerText)
            .join();
      } else {
        value =
            cell.findAllElements('v', namespace: '*').firstOrNull?.innerText ??
            '';
      }
      final column = _columnIndex(ref);
      if (column >= 0 && value.isNotEmpty) cells[column] = value;
    }
    if (cells.isEmpty) continue;
    final width = cells.keys.reduce((a, b) => a > b ? a : b) + 1;
    rows.add(List<String>.generate(width, (i) => cells[i] ?? ''));
  }
  return rows;
}

Future<OfficeDocument> _parseOds(ViewerArchive archive) async {
  final xml = await _readPart(archive, 'content.xml');
  if (xml == null) {
    return const OfficeDocument(
      kind: OfficeDocumentKind.spreadsheet,
      markdown: '',
      plainText: '(No content.xml found in this ODS)',
      fallback: OfficePreviewFallback.missingOds,
    );
  }
  final document = XmlDocument.parse(xml);
  final markdown = StringBuffer();
  final csv = StringBuffer();
  final headings = <OfficeGeneratedHeading>[];
  var tableNumber = 0;
  for (final table in document.findAllElements('table:table')) {
    tableNumber++;
    final rows = <List<String>>[];
    for (final row in table.findAllElements('table:table-row')) {
      final cells = <String>[];
      for (final cell in row.findAllElements('table:table-cell')) {
        cells.add(
          cell
              .findAllElements('text:p')
              .map((p) => p.innerText)
              .join(' ')
              .trim(),
        );
      }
      if (cells.any((c) => c.isNotEmpty)) rows.add(cells);
    }
    if (rows.isEmpty) continue;
    _writeHeading(
      markdown,
      '## ',
      OfficeHeadingKind.sheet,
      tableNumber,
      headings,
    );
    markdown.writeln();
    markdown.writeln(_markdownTable(rows));
    markdown.writeln();
    for (final row in rows) {
      csv.writeln(row.map(_csvCell).join(','));
    }
    csv.writeln();
  }
  final md = markdown.toString().trim();
  final (plain, textHeadings) = _plainWithHeadings(md, headings);
  return OfficeDocument(
    kind: OfficeDocumentKind.spreadsheet,
    markdown: md,
    plainText: plain,
    markdownHeadings: headings,
    textHeadings: textHeadings,
    csv: csv.toString().trim(),
    rawXml: _capRaw(xml, 'content.xml'),
  );
}

// ---------------------------------------------------------------------------
// PPTX / ODP
// ---------------------------------------------------------------------------

Future<OfficeDocument> _parsePptx(ViewerArchive archive) async {
  final slides =
      archive.members
          .where(
            (m) =>
                m.isFile &&
                m.name.startsWith('ppt/slides/slide') &&
                m.name.endsWith('.xml'),
          )
          .map((m) => m.name)
          .toList()
        ..sort(
          (a, b) =>
              _sortedNumber(a, 'slide').compareTo(_sortedNumber(b, 'slide')),
        );

  // Slide size from presentation.xml (EMU); fall back to 4:3.
  var slideWidth = 9144000;
  var slideHeight = 6858000;
  final presentationXml = await _readPart(archive, 'ppt/presentation.xml');
  if (presentationXml != null) {
    try {
      final size = XmlDocument.parse(presentationXml)
          .findAllElements('p:sldSz')
          .firstOrNull;
      final cx = int.tryParse(size?.getAttribute('cx') ?? '');
      final cy = int.tryParse(size?.getAttribute('cy') ?? '');
      if (cx != null && cy != null && cx > 0 && cy > 0) {
        slideWidth = cx;
        slideHeight = cy;
      }
    } catch (_) {
      // Keep defaults.
    }
  }

  final pages = <SlidePage>[];
  final markdown = StringBuffer();
  final headings = <OfficeGeneratedHeading>[];
  var slideNumber = 0;
  for (final slidePath in slides) {
    if (pages.length >= 200) break;
    final xml = await _readPart(archive, slidePath);
    if (xml == null) continue;
    slideNumber++;
    final document = XmlDocument.parse(xml);
    final rels = await _readSlideRelationships(archive, slidePath);

    final background = document
        .findAllElements('p:bg')
        .firstOrNull
        ?.findAllElements('a:srgbClr')
        .firstOrNull
        ?.getAttribute('val');

    final shapes = <SlideShape>[];
    final textParagraphs = <String>[];

    for (final shape in document.findAllElements('p:sp')) {
      if (shapes.length >= 200) break;
      final text = _pptxShapeText(shape);
      final shapeProperties = shape.findElements('p:spPr').firstOrNull;
      final fill = shapeProperties
          ?.findAllElements('a:solidFill')
          .firstOrNull
          ?.findAllElements('a:srgbClr')
          .firstOrNull
          ?.getAttribute('val');
      // Keep text shapes and filled rectangles (background blocks).
      if (text.trim().isEmpty && fill == null) continue;
      if (text.trim().isNotEmpty) {
        textParagraphs.addAll(
          text.trim().split('\n').where((line) => line.trim().isNotEmpty),
        );
      }
      final box = _pptxShapeBox(shape);
      final runProps = shape.findAllElements('a:rPr').firstOrNull;
      final size = int.tryParse(runProps?.getAttribute('sz') ?? '');
      final bold = runProps?.getAttribute('b') == '1';
      final color = runProps
          ?.findAllElements('a:srgbClr')
          .firstOrNull
          ?.getAttribute('val');
      shapes.add(
        SlideShape(
          x: box?.$1 ?? 228600,
          y: box?.$2 ?? 228600,
          width: box?.$3 ?? slideWidth - 457200,
          height: box?.$4 ?? slideHeight - 457200,
          text: text.trim().isEmpty ? null : text.trim(),
          fontSizePt: ((size ?? 1800) / 100).clamp(6, 96).toDouble(),
          bold: bold,
          textColorHex: color,
          fillColorHex: fill,
        ),
      );
    }

    for (final picture in document.findAllElements('p:pic')) {
      if (shapes.length >= 200) break;
      final box = _pptxShapeBox(picture);
      if (box == null) continue;
      final embed = picture
          .findAllElements('a:blip')
          .firstOrNull
          ?.getAttribute('r:embed');
      if (embed == null) continue;
      final target = rels[embed];
      if (target == null) continue;
      final imagePath = p.posix.normalize(
        p.posix.join(p.posix.dirname(slidePath), target),
      );
      final image = await _readPartBytes(archive, imagePath);
      if (image == null) continue;
      shapes.add(
        SlideShape(
          x: box.$1,
          y: box.$2,
          width: box.$3,
          height: box.$4,
          image: image,
        ),
      );
    }

    pages.add(SlidePage(backgroundHex: background, shapes: shapes));

    _writeHeading(
      markdown,
      '## ',
      OfficeHeadingKind.slide,
      slideNumber,
      headings,
    );
    markdown.writeln();
    if (textParagraphs.isNotEmpty) {
      markdown.writeln(textParagraphs.first);
      markdown.writeln();
      for (final paragraph in textParagraphs.skip(1)) {
        markdown.writeln('- $paragraph');
      }
    }
    markdown.writeln();
  }

  final md = markdown.toString().trim();
  final (plain, textHeadings) = _plainWithHeadings(md, headings);
  return OfficeDocument(
    kind: OfficeDocumentKind.presentation,
    markdown: md,
    plainText: plain,
    markdownHeadings: headings,
    textHeadings: textHeadings,
    rawXml: await _rawPart(archive, slides.firstOrNull),
    deck: pages.isEmpty
        ? null
        : SlideDeck(
            widthEmu: slideWidth,
            heightEmu: slideHeight,
            slides: pages,
          ),
  );
}

Future<Map<String, String>> _readSlideRelationships(
  ViewerArchive archive,
  String slidePath,
) async {
  final relsPath =
      '${p.posix.dirname(slidePath)}/_rels/${p.posix.basename(slidePath)}.rels';
  final xml = await _readPart(archive, relsPath);
  final result = <String, String>{};
  if (xml == null) return result;
  try {
    final document = XmlDocument.parse(xml);
    for (final relationship in document.findAllElements('Relationship')) {
      final id = relationship.getAttribute('Id');
      final target = relationship.getAttribute('Target');
      if (id != null && target != null) result[id] = target;
    }
  } catch (_) {
    // Ignore malformed relationship files.
  }
  return result;
}

String _pptxShapeText(XmlElement shape) {
  final paragraphs = <String>[];
  for (final paragraph in shape.findAllElements('a:p')) {
    final text = paragraph
        .findAllElements('a:t')
        .map((e) => e.innerText)
        .join()
        .trim();
    if (text.isNotEmpty) paragraphs.add(text);
  }
  return paragraphs.join('\n');
}

/// Returns (x, y, width, height) in EMU for a shape or picture.
(int, int, int, int)? _pptxShapeBox(XmlElement element) {
  final xfrm = element.findAllElements('a:xfrm').firstOrNull;
  if (xfrm == null) return null;
  final off = xfrm.findAllElements('a:off').firstOrNull;
  final ext = xfrm.findAllElements('a:ext').firstOrNull;
  final x = int.tryParse(off?.getAttribute('x') ?? '');
  final y = int.tryParse(off?.getAttribute('y') ?? '');
  final cx = int.tryParse(ext?.getAttribute('cx') ?? '');
  final cy = int.tryParse(ext?.getAttribute('cy') ?? '');
  if (x == null || y == null || cx == null || cy == null) return null;
  return (x, y, cx, cy);
}

Future<Uint8List?> _readPartBytes(ViewerArchive archive, String path) async {
  final matches = archive.members
      .where((m) => m.isFile && m.name == path)
      .toList();
  if (matches.isEmpty) return null;
  final member = matches.first;
  if (member.size > _kOfficePartCap) return null;
  try {
    return await archive.readMember(member, maxBytes: _kOfficePartCap);
  } on ArchiveViewException {
    return null;
  }
}

Future<OfficeDocument> _parseOdp(ViewerArchive archive) async {
  final xml = await _readPart(archive, 'content.xml');
  if (xml == null) {
    return const OfficeDocument(
      kind: OfficeDocumentKind.presentation,
      markdown: '',
      plainText: '(No content.xml found in this ODP)',
      fallback: OfficePreviewFallback.missingOdp,
    );
  }
  final document = XmlDocument.parse(xml);
  final markdown = StringBuffer();
  final headings = <OfficeGeneratedHeading>[];
  var pageNumber = 0;
  for (final page in document.findAllElements('draw:page')) {
    pageNumber++;
    _writeHeading(
      markdown,
      '## ',
      OfficeHeadingKind.slide,
      pageNumber,
      headings,
    );
    markdown.writeln();
    for (final paragraph in page.findAllElements('text:p')) {
      final text = paragraph.innerText.trim();
      if (text.isNotEmpty) markdown.writeln('- $text');
    }
    markdown.writeln();
  }
  final md = markdown.toString().trim();
  final (plain, textHeadings) = _plainWithHeadings(md, headings);
  return OfficeDocument(
    kind: OfficeDocumentKind.presentation,
    markdown: md,
    plainText: plain,
    markdownHeadings: headings,
    textHeadings: textHeadings,
    rawXml: _capRaw(xml, 'content.xml'),
  );
}

// ---------------------------------------------------------------------------
// ODT
// ---------------------------------------------------------------------------

Future<OfficeDocument> _parseOdt(ViewerArchive archive) async {
  final xml = await _readPart(archive, 'content.xml');
  if (xml == null) {
    return const OfficeDocument(
      kind: OfficeDocumentKind.document,
      markdown: '',
      plainText: '(No content.xml found in this ODT)',
      fallback: OfficePreviewFallback.missingOdt,
    );
  }
  final document = XmlDocument.parse(xml);
  final blocks = <String>[];
  void visit(XmlElement element) {
    switch (element.localName) {
      case 'h':
        final level =
            int.tryParse(element.getAttribute('text:outline-level') ?? '') ?? 1;
        final text = element.innerText.trim();
        if (text.isNotEmpty) {
          blocks.add('${'#' * level.clamp(1, 6)} $text');
        }
      case 'p':
        final text = element.innerText.trim();
        if (text.isNotEmpty) blocks.add(text);
      case 'table':
        final rows = <List<String>>[];
        for (final row in element.findAllElements('table:table-row')) {
          final cells = <String>[];
          for (final cell in row.findAllElements('table:table-cell')) {
            cells.add(_escapePipes(cell.innerText.trim()));
          }
          if (cells.any((c) => c.isNotEmpty)) rows.add(cells);
        }
        final table = _markdownTable(rows);
        if (table.isNotEmpty) blocks.add(table);
      default:
        for (final child in element.childElements) {
          visit(child);
        }
    }
  }

  final body = document.findAllElements('office:body').firstOrNull;
  if (body != null) {
    for (final child in body.childElements) {
      visit(child);
    }
  }
  final markdown = blocks.join('\n\n').trim();
  return OfficeDocument(
    kind: OfficeDocumentKind.document,
    markdown: markdown,
    plainText: _stripMarkdown(markdown),
    rawXml: _capRaw(xml, 'content.xml'),
  );
}

// ---------------------------------------------------------------------------
// EPUB
// ---------------------------------------------------------------------------

Future<OfficeDocument> _parseEpub(ViewerArchive archive) async {
  var files =
      archive.members
          .where(
            (m) =>
                m.isFile &&
                (m.name.endsWith('.xhtml') ||
                    m.name.endsWith('.html') ||
                    m.name.endsWith('.htm')),
          )
          .map((m) => m.name)
          .toList()
        ..sort();

  // EPUB reading order belongs to the package spine, not archive filenames.
  // Retain the old extraction fallback for incomplete/legacy EPUB-like ZIPs.
  final container = await _readPart(archive, 'META-INF/container.xml');
  if (container != null) {
    try {
      final roots = XmlDocument.parse(container).descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'rootfile');
      final packagePath = roots.firstOrNull?.getAttribute('full-path');
      if (packagePath != null &&
          !p.posix.isAbsolute(packagePath) &&
          !p.posix.split(packagePath).contains('..')) {
        final source = await _readPart(archive, packagePath);
        if (source != null) {
          final package = XmlDocument.parse(source);
          final manifest = <String, String>{};
          for (final item in package.descendants.whereType<XmlElement>().where(
            (element) => element.name.local == 'item',
          )) {
            final id = item.getAttribute('id');
            final href = item.getAttribute('href');
            if (id == null || href == null) continue;
            final uri = Uri.tryParse(href);
            if (uri == null ||
                uri.hasScheme ||
                uri.hasAuthority ||
                uri.path.startsWith('/'))
              continue;
            final path = p.posix.normalize(
              p.posix.join(
                p.posix.dirname(packagePath),
                Uri.decodeComponent(uri.path),
              ),
            );
            if (path == '..' || path.startsWith('../')) continue;
            manifest[id] = path;
          }
          final ordered = package.descendants
              .whereType<XmlElement>()
              .where((element) => element.name.local == 'itemref')
              .map((element) => manifest[element.getAttribute('idref')])
              .whereType<String>()
              .where(files.contains)
              .toList();
          if (ordered.isNotEmpty) files = ordered;
        }
      }
    } on FormatException {
      /* Keep bounded extraction for malformed packages. */
    } on XmlException {
      /* Keep bounded extraction for malformed packages. */
    }
  }

  final markdown = StringBuffer();
  for (final path in files) {
    final html = await _readPart(archive, path);
    if (html == null) continue;
    final converted = _htmlToMarkdown(html);
    if (converted.isNotEmpty) {
      markdown.writeln(converted);
      markdown.writeln();
    }
  }
  final md = markdown.toString().trim();
  return OfficeDocument(
    kind: OfficeDocumentKind.ebook,
    markdown: md,
    plainText: _stripMarkdown(md),
    rawXml: await _rawPart(archive, files.firstOrNull),
  );
}

String _htmlToMarkdown(String html) {
  final document = html_parser.parse(html);
  final body = document.body;
  if (body == null) return '';

  final blocks = <String>[];
  void visit(dom.Element element) {
    final tag = element.localName?.toLowerCase() ?? '';
    if (RegExp(r'^h[1-6]$').hasMatch(tag)) {
      final level = int.parse(tag.substring(1));
      final text = element.text.trim();
      if (text.isNotEmpty) blocks.add('${'#' * level} $text');
      return;
    }
    switch (tag) {
      case 'p':
        final text = element.text.trim();
        if (text.isNotEmpty) blocks.add(text);
        return;
      case 'div':
        if (element.children.isEmpty) {
          final text = element.text.trim();
          if (text.isNotEmpty) blocks.add(text);
        } else {
          for (final child in element.children) {
            visit(child);
          }
        }
        return;
      case 'li':
        final text = element.text.trim();
        if (text.isNotEmpty) blocks.add('- $text');
        return;
      case 'table':
        final rows = <List<String>>[];
        for (final tr in element.querySelectorAll('tr')) {
          final cells = tr
              .querySelectorAll('th,td')
              .map((cell) => _escapePipes(cell.text.trim()))
              .toList();
          if (cells.any((c) => c.isNotEmpty)) rows.add(cells);
        }
        final table = _markdownTable(rows);
        if (table.isNotEmpty) blocks.add(table);
        return;
      case 'pre':
        final text = element.text.trimRight();
        if (text.isNotEmpty) blocks.add('```\n$text\n```');
        return;
      case 'script':
      case 'style':
        return;
      default:
        for (final child in element.children) {
          visit(child);
        }
    }
  }

  for (final child in body.children) {
    visit(child);
  }
  return blocks.join('\n\n');
}

// ---------------------------------------------------------------------------
// Raw XML helpers
// ---------------------------------------------------------------------------

String? _capRaw(String xml, String name) {
  final body = xml.length > _kOfficeRawCap
      ? xml.substring(0, _kOfficeRawCap)
      : xml;
  return '<!-- $name -->\n$body';
}

Future<String?> _rawPart(ViewerArchive archive, String? path) async {
  if (path == null) return null;
  final xml = await _readPart(archive, path);
  if (xml == null) return null;
  return _capRaw(xml, path);
}
