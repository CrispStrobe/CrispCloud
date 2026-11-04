import 'dart:convert';
import 'dart:typed_data';

import '../builders/docx_builder.dart';
import '../builders/xlsx_io.dart';
import '../opc/opc_archive.dart';
import '../opc/package_part.dart';
import '../opc/relationships.dart';
import '../opc/zip/zip_reader.dart';
import '../pdf/file/model/pdf_file.dart';
import '../pdf/file/text/pdf_extract.dart';
import '../xml/namespaces.dart';
import '../xml/xml_reader.dart';

/// Enum OfficeExtractKind.
enum OfficeExtractKind {
  word,
  sheet,
  slide,
  opendocumentText,
  opendocumentSheet,
  opendocumentPresentation,
  pdf,
  unknown,
}

/// Class OfficeExtractSlide.
class OfficeExtractSlide {
  /// OfficeExtractSlide API.
  const OfficeExtractSlide({
    required this.title,
    required this.body,
    this.notes = '',
    this.tables = const <List<List<String>>>[],
  });

  /// title API.
  final String title;

  /// body API.
  final List<String> body;

  /// notes API.
  final String notes;

  /// tables API.
  final List<List<List<String>>> tables;
}

/// Class OfficeExtractSheet.
class OfficeExtractSheet {
  /// OfficeExtractSheet API.
  const OfficeExtractSheet({required this.name, required this.rows});

  /// name API.
  final String name;

  /// rows API.
  final List<List<String>> rows;

  /// tsv API.
  String get tsv {
    return rows.map((List<String> r) => r.join('\t')).join('\n');
  }
}

/// Class OfficeTextExtract.
class OfficeTextExtract {
  /// OfficeTextExtract API.
  const OfficeTextExtract({
    required this.kind,
    this.paragraphs = const <String>[],
    this.tables = const <List<List<String>>>[],
    this.slides = const <OfficeExtractSlide>[],
    this.sheets = const <OfficeExtractSheet>[],
    this.clipped = false,
  });

  /// kind API.
  final OfficeExtractKind kind;

  /// paragraphs API.
  final List<String> paragraphs;

  /// tables API.
  final List<List<List<String>>> tables;

  /// slides API.
  final List<OfficeExtractSlide> slides;

  /// sheets API.
  final List<OfficeExtractSheet> sheets;

  /// clipped API.
  final bool clipped;

  /// plainString API.
  String get plainString {
    final StringBuffer buf = StringBuffer();
    for (final String p in paragraphs) {
      if (p.isNotEmpty) {
        buf.writeln(p);
      }
    }
    for (final OfficeExtractSheet sheet in sheets) {
      if (buf.isNotEmpty) {
        buf.writeln();
      }
      buf.writeln(sheet.name);
      buf.writeln(sheet.tsv);
    }
    for (final OfficeExtractSlide slide in slides) {
      if (buf.isNotEmpty) {
        buf.writeln();
      }
      if (slide.title.isNotEmpty) {
        buf.writeln(slide.title);
      }
      for (final String line in slide.body) {
        buf.writeln(line);
      }
      if (slide.notes.isNotEmpty) {
        buf.writeln(slide.notes);
      }
    }
    return buf.toString();
  }
}

/// Format-generic plain-text facade for RAG / search. No prompt logic.
///
/// Format-generic plain-text facade for RAG / search.
abstract final class OfficeTextExtractor {
  /// extract API.
  static OfficeTextExtract extract(
    Uint8List bytes, {
    String? name,
    String? mime,
    String? password,
    int? maxChars,
  }) {
    final OfficeExtractKind kind = _detect(bytes, name: name, mime: mime);
    final OfficeTextExtract raw = switch (kind) {
      OfficeExtractKind.word => _docx(bytes, password: password),
      OfficeExtractKind.sheet => _xlsx(bytes, password: password),
      OfficeExtractKind.slide => _pptx(bytes, password: password),
      OfficeExtractKind.opendocumentText ||
      OfficeExtractKind.opendocumentSheet ||
      OfficeExtractKind.opendocumentPresentation => _odf(bytes, kind),
      OfficeExtractKind.pdf => _pdf(bytes, password: password),
      OfficeExtractKind.unknown => const OfficeTextExtract(
        kind: OfficeExtractKind.unknown,
      ),
    };
    if (maxChars == null || maxChars <= 0) {
      return raw;
    }
    return _clip(raw, maxChars);
  }

  static OfficeExtractKind _detect(
    Uint8List bytes, {
    String? name,
    String? mime,
  }) {
    final String lowerName = (name ?? '').toLowerCase();
    final String lowerMime = (mime ?? '').toLowerCase();
    if (lowerName.endsWith('.pdf') || lowerMime.contains('pdf')) {
      return OfficeExtractKind.pdf;
    }
    if (lowerName.endsWith('.odt') || lowerMime.contains('opendocument.text')) {
      return OfficeExtractKind.opendocumentText;
    }
    if (lowerName.endsWith('.ods') ||
        lowerMime.contains('opendocument.spreadsheet')) {
      return OfficeExtractKind.opendocumentSheet;
    }
    if (lowerName.endsWith('.odp') ||
        lowerMime.contains('opendocument.presentation')) {
      return OfficeExtractKind.opendocumentPresentation;
    }
    if (lowerName.endsWith('.docx') || lowerMime.contains('wordprocessingml')) {
      return OfficeExtractKind.word;
    }
    if (lowerName.endsWith('.xlsx') ||
        lowerName.endsWith('.xlsm') ||
        lowerMime.contains('spreadsheetml')) {
      return OfficeExtractKind.sheet;
    }
    if (lowerName.endsWith('.pptx') || lowerMime.contains('presentationml')) {
      return OfficeExtractKind.slide;
    }
    if (bytes.length >= 5 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return OfficeExtractKind.pdf;
    }
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      try {
        final ZipReader zip = ZipReader.fromBytes(bytes);
        if (zip.contains('word/document.xml')) {
          return OfficeExtractKind.word;
        }
        if (zip.contains('xl/workbook.xml')) {
          return OfficeExtractKind.sheet;
        }
        if (zip.contains('ppt/presentation.xml')) {
          return OfficeExtractKind.slide;
        }
        if (zip.contains('content.xml') && zip.contains('mimetype')) {
          final String mt = utf8.decode(zip.read('mimetype'));
          if (mt.contains('text')) {
            return OfficeExtractKind.opendocumentText;
          }
          if (mt.contains('spreadsheet')) {
            return OfficeExtractKind.opendocumentSheet;
          }
          if (mt.contains('presentation')) {
            return OfficeExtractKind.opendocumentPresentation;
          }
        }
      } catch (_) {
        return OfficeExtractKind.unknown;
      }
    }
    return OfficeExtractKind.unknown;
  }

  static OfficeTextExtract _docx(Uint8List bytes, {String? password}) {
    final extracted = DocxPlainReader.read(bytes, password: password);
    return OfficeTextExtract(
      kind: OfficeExtractKind.word,
      paragraphs: extracted.paragraphs,
      tables: extracted.tables,
    );
  }

  static OfficeTextExtract _xlsx(Uint8List bytes, {String? password}) {
    final List<XlsxNamedSheet> all = XlsxGridReader.readAll(
      bytes,
      password: password,
    );
    return OfficeTextExtract(
      kind: OfficeExtractKind.sheet,
      sheets: <OfficeExtractSheet>[
        for (final XlsxNamedSheet s in all)
          OfficeExtractSheet(name: s.name, rows: s.rows),
      ],
    );
  }

  static OfficeTextExtract _pdf(Uint8List bytes, {String? password}) {
    final PdfFile file = PdfFile.open(bytes, password: password);
    return OfficeTextExtract(
      kind: OfficeExtractKind.pdf,
      paragraphs: PdfExtract.paragraphs(file),
    );
  }

  static OfficeTextExtract _pptx(Uint8List bytes, {String? password}) {
    final OpcPackage package = OpcPackage.openBytes(bytes, password: password);
    final List<OfficeExtractSlide> slides = <OfficeExtractSlide>[];
    final List<String> names =
        package.partNames
            .where(
              (String n) =>
                  n.startsWith('/ppt/slides/slide') && n.endsWith('.xml'),
            )
            .toList()
          ..sort();
    for (final String uri in names) {
      final PackagePart? part = package.getPart(uri);
      if (part == null) {
        continue;
      }
      final String xml = part.readText();
      final List<String> texts = _drawingTexts(xml);
      final List<List<List<String>>> tables = _drawingTables(xml);
      String notes = '';
      final RelationshipCollection rels = package.relationshipsFor(uri);
      final PackageRelationship? notesRel = rels.firstByType(
        RelationshipTypes.notesSlide,
      );
      if (notesRel != null) {
        final PackagePart? notesPart = package.getPart(rels.resolve(notesRel));
        if (notesPart != null) {
          notes = _drawingTexts(notesPart.readText()).join('\n');
        }
      }
      slides.add(
        OfficeExtractSlide(
          title: texts.isEmpty ? '' : texts.first,
          body: texts.length <= 1 ? const <String>[] : texts.sublist(1),
          notes: notes,
          tables: tables,
        ),
      );
    }
    return OfficeTextExtract(kind: OfficeExtractKind.slide, slides: slides);
  }

  static OfficeTextExtract _odf(Uint8List bytes, OfficeExtractKind kind) {
    final ZipReader zip = ZipReader.fromBytes(bytes);
    if (!zip.contains('content.xml')) {
      return OfficeTextExtract(kind: kind);
    }
    final String xml = utf8.decode(zip.read('content.xml'));
    final List<String> paragraphs = <String>[];
    final List<List<List<String>>> tables = <List<List<String>>>[];
    final XmlPullReader reader = XmlPullReader(xml);
    List<List<String>>? table;
    List<String>? row;
    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (reader.localName == 'table') {
        table = <List<String>>[];
        tables.add(table);
      } else if (reader.localName == 'table-row' && table != null) {
        row = <String>[];
        table.add(row);
      } else if (reader.localName == 'table-cell' && row != null) {
        row.add(_odfPlain(reader));
      } else if (reader.localName == 'p' || reader.localName == 'h') {
        final String text = _odfPlain(reader);
        if (text.trim().isNotEmpty) {
          paragraphs.add(text);
        }
      }
    }
    if (kind == OfficeExtractKind.opendocumentSheet) {
      return OfficeTextExtract(
        kind: kind,
        sheets: <OfficeExtractSheet>[
          OfficeExtractSheet(
            name: 'Sheet1',
            rows: tables.isEmpty ? const <List<String>>[] : tables.first,
          ),
        ],
        tables: tables,
      );
    }
    if (kind == OfficeExtractKind.opendocumentPresentation) {
      return OfficeTextExtract(
        kind: kind,
        slides: <OfficeExtractSlide>[
          OfficeExtractSlide(
            title: paragraphs.isEmpty ? '' : paragraphs.first,
            body: paragraphs.length <= 1
                ? const <String>[]
                : paragraphs.sublist(1),
            tables: tables,
          ),
        ],
      );
    }
    return OfficeTextExtract(
      kind: kind,
      paragraphs: paragraphs,
      tables: tables,
    );
  }

  static String _odfPlain(XmlPullReader reader) {
    if (reader.isEmptyElement) {
      return '';
    }
    final StringBuffer buf = StringBuffer();
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType == XmlEventType.characters) {
        buf.write(reader.text);
      }
    }
    return buf.toString();
  }

  static List<String> _drawingTexts(String xml) {
    final List<String> out = <String>[];
    final XmlPullReader reader = XmlPullReader(xml);
    while (reader.next()) {
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 't' &&
          !reader.isEmptyElement) {
        final int depth = reader.depth;
        final StringBuffer buf = StringBuffer();
        while (reader.next() && reader.depth >= depth) {
          if (reader.eventType == XmlEventType.characters) {
            buf.write(reader.text);
          }
        }
        final String text = buf.toString().trim();
        if (text.isNotEmpty) {
          out.add(text);
        }
      }
    }
    return out;
  }

  static List<List<List<String>>> _drawingTables(String xml) {
    final List<List<List<String>>> tables = <List<List<String>>>[];
    final XmlPullReader reader = XmlPullReader(xml);
    List<List<String>>? table;
    List<String>? row;
    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (reader.localName == 'tbl') {
        table = <List<String>>[];
        tables.add(table);
      } else if (reader.localName == 'tr' && table != null) {
        row = <String>[];
        table.add(row);
      } else if (reader.localName == 'tc' && row != null) {
        row.add(_odfPlain(reader));
      }
    }
    return tables;
  }

  static OfficeTextExtract _clip(OfficeTextExtract src, int maxChars) {
    final List<String> paragraphs = <String>[];
    var used = 0;
    var clipped = false;
    void takeLine(String line, void Function(String) add) {
      if (clipped) {
        return;
      }
      final int next = used + line.length + 1;
      if (next > maxChars) {
        clipped = true;
        return;
      }
      add(line);
      used = next;
    }

    for (final String p in src.paragraphs) {
      takeLine(p, paragraphs.add);
    }
    final List<OfficeExtractSheet> sheets = <OfficeExtractSheet>[];
    for (final OfficeExtractSheet sheet in src.sheets) {
      if (clipped) {
        break;
      }
      takeLine(sheet.name, (_) {});
      final List<List<String>> rows = <List<String>>[];
      for (final List<String> row in sheet.rows) {
        final String line = row.join('\t');
        if (clipped) {
          break;
        }
        if (used + line.length + 1 > maxChars) {
          clipped = true;
          break;
        }
        rows.add(row);
        used += line.length + 1;
      }
      sheets.add(OfficeExtractSheet(name: sheet.name, rows: rows));
    }
    final List<OfficeExtractSlide> slides = <OfficeExtractSlide>[];
    for (final OfficeExtractSlide slide in src.slides) {
      if (clipped) {
        break;
      }
      takeLine(slide.title, (_) {});
      final List<String> body = <String>[];
      for (final String line in slide.body) {
        takeLine(line, body.add);
      }
      var notes = '';
      if (!clipped && slide.notes.isNotEmpty) {
        if (used + slide.notes.length + 1 <= maxChars) {
          notes = slide.notes;
          used += slide.notes.length + 1;
        } else {
          clipped = true;
        }
      }
      slides.add(
        OfficeExtractSlide(
          title: slide.title,
          body: body,
          notes: notes,
          tables: slide.tables,
        ),
      );
    }
    return OfficeTextExtract(
      kind: src.kind,
      paragraphs: paragraphs,
      tables: src.tables,
      slides: slides,
      sheets: sheets,
      clipped: clipped,
    );
  }
}
