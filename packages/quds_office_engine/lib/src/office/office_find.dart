import '../pdf/file/model/pdf_file.dart';
import '../pdf/file/text/pdf_extract.dart';
import '../sheet/model/sml_workbook.dart';
import '../slide/model/pml_presentation.dart';
import '../word/model/wml_document.dart';
import '../word/model/wml_run_edit.dart';

/// Options shared by find / replace across Word, sheets, and slides.
class OfficeFindOptions {
  /// OfficeFindOptions API.
  const OfficeFindOptions({
    required this.query,
    this.replaceWith = '',
    this.matchCase = false,
    this.wholeWord = false,
    this.wildcards = false,
    this.matchPrefix = false,
    this.matchSuffix = false,
  });

  /// query API.
  final String query;

  /// replaceWith API.
  final String replaceWith;

  /// matchCase API.
  final bool matchCase;

  /// wholeWord API.
  final bool wholeWord;

  /// `*` any run, `?` one character (Office-style).
  final bool wildcards;

  /// matchPrefix API.
  final bool matchPrefix;

  /// matchSuffix API.
  final bool matchSuffix;

  /// copyWith API.
  OfficeFindOptions copyWith({
    String? query,
    String? replaceWith,
    bool? matchCase,
    bool? wholeWord,
    bool? wildcards,
    bool? matchPrefix,
    bool? matchSuffix,
  }) {
    return OfficeFindOptions(
      query: query ?? this.query,
      replaceWith: replaceWith ?? this.replaceWith,
      matchCase: matchCase ?? this.matchCase,
      wholeWord: wholeWord ?? this.wholeWord,
      wildcards: wildcards ?? this.wildcards,
      matchPrefix: matchPrefix ?? this.matchPrefix,
      matchSuffix: matchSuffix ?? this.matchSuffix,
    );
  }
}

/// One hit inside a document, workbook, or deck.
class OfficeFindHit {
  /// OfficeFindHit API.
  const OfficeFindHit({
    required this.kind,
    required this.preview,
    this.paragraphIndex,
    this.start = 0,
    this.end = 0,
    this.sheetName,
    this.a1,
    this.slideIndex,
    this.shapeId,
    this.pageIndex,
  });

  /// kind API.
  final OpcPackageKindHint kind;

  /// preview API.
  final String preview;

  /// paragraphIndex API.
  final int? paragraphIndex;

  /// start API.
  final int start;

  /// end API.
  final int end;

  /// sheetName API.
  final String? sheetName;

  /// a1 API.
  final String? a1;

  /// slideIndex API.
  final int? slideIndex;

  /// shapeId API.
  final int? shapeId;

  /// PDF page index when [kind] is [OpcPackageKindHint.pdf].
  final int? pageIndex;
}

/// Discriminator that does not import OPC.
enum OpcPackageKindHint { word, sheet, slide, pdf }

/// Model-level find and replace. Hosts drive caret / selection from hits.
abstract final class OfficeFind {
  /// inWord API.
  static List<OfficeFindHit> inWord(
    WmlDocument document,
    OfficeFindOptions options,
  ) {
    if (options.query.isEmpty) {
      return const <OfficeFindHit>[];
    }
    final List<OfficeFindHit> hits = <OfficeFindHit>[];
    final List<WmlParagraph> paras = document.paragraphs.toList();
    for (int i = 0; i < paras.length; i++) {
      final String text = paras[i].text;
      for (final (int start, int end) in _spans(text, options)) {
        hits.add(
          OfficeFindHit(
            kind: OpcPackageKindHint.word,
            preview: text,
            paragraphIndex: i,
            start: start,
            end: end,
          ),
        );
      }
    }
    return hits;
  }

  /// replaceWord API.
  static int replaceWord(
    WmlDocument document,
    OfficeFindOptions options, {
    OfficeFindHit? only,
  }) {
    if (options.query.isEmpty) {
      return 0;
    }
    final List<WmlParagraph> paras = document.paragraphs.toList();
    var count = 0;
    if (only != null) {
      final int index = only.paragraphIndex ?? -1;
      if (index < 0 || index >= paras.length) {
        return 0;
      }
      WmlRunEdit.replaceRange(
        paras[index],
        only.start,
        only.end,
        options.replaceWith,
      );
      return 1;
    }
    for (final WmlParagraph paragraph in paras) {
      final String text = paragraph.text;
      final List<(int, int)> spans = _spans(text, options).toList();
      for (int i = spans.length - 1; i >= 0; i--) {
        final (int start, int end) = spans[i];
        WmlRunEdit.replaceRange(paragraph, start, end, options.replaceWith);
        count++;
      }
    }
    return count;
  }

  /// inWorkbook API.
  static List<OfficeFindHit> inWorkbook(
    SmlWorkbook workbook,
    OfficeFindOptions options,
  ) {
    if (options.query.isEmpty) {
      return const <OfficeFindHit>[];
    }
    final List<OfficeFindHit> hits = <OfficeFindHit>[];
    for (final SmlWorksheet sheet in workbook.sheets) {
      for (final SmlCell cell in sheet.allCells) {
        final String text = cell.asString;
        if (_contains(text, options)) {
          hits.add(
            OfficeFindHit(
              kind: OpcPackageKindHint.sheet,
              preview: text,
              sheetName: sheet.name,
              a1: cell.ref.a1,
              start: 0,
              end: text.length,
            ),
          );
        }
      }
    }
    return hits;
  }

  /// replaceWorkbook API.
  static int replaceWorkbook(
    SmlWorkbook workbook,
    OfficeFindOptions options, {
    OfficeFindHit? only,
  }) {
    if (options.query.isEmpty) {
      return 0;
    }
    var count = 0;
    for (final SmlWorksheet sheet in workbook.sheets) {
      if (only != null && only.sheetName != sheet.name) {
        continue;
      }
      for (final SmlCell cell in sheet.allCells) {
        if (only != null && only.a1 != cell.ref.a1) {
          continue;
        }
        final String text = cell.asString;
        if (!_contains(text, options)) {
          continue;
        }
        cell.value = _replaceAll(text, options);
        cell.type = SmlCellType.string;
        count++;
      }
    }
    return count;
  }

  /// inPresentation API.
  static List<OfficeFindHit> inPresentation(
    PmlPresentation presentation,
    OfficeFindOptions options,
  ) {
    if (options.query.isEmpty) {
      return const <OfficeFindHit>[];
    }
    final List<OfficeFindHit> hits = <OfficeFindHit>[];
    for (int s = 0; s < presentation.slides.length; s++) {
      final PmlSlide slide = presentation.slides[s];
      if (_contains(slide.notes, options)) {
        hits.add(
          OfficeFindHit(
            kind: OpcPackageKindHint.slide,
            preview: slide.notes,
            slideIndex: s,
            start: 0,
            end: slide.notes.length,
          ),
        );
      }
      for (final PmlShape shape in slide.shapes) {
        if (_contains(shape.text, options)) {
          hits.add(
            OfficeFindHit(
              kind: OpcPackageKindHint.slide,
              preview: shape.text,
              slideIndex: s,
              shapeId: shape.id,
              start: 0,
              end: shape.text.length,
            ),
          );
        }
        final PmlTable? table = shape.table;
        if (table == null) {
          continue;
        }
        for (final List<PmlTableCell> row in table.rows) {
          for (final PmlTableCell cell in row) {
            if (_contains(cell.text, options)) {
              hits.add(
                OfficeFindHit(
                  kind: OpcPackageKindHint.slide,
                  preview: cell.text,
                  slideIndex: s,
                  shapeId: shape.id,
                  start: 0,
                  end: cell.text.length,
                ),
              );
            }
          }
        }
      }
    }
    return hits;
  }

  /// replacePresentation API.
  static int replacePresentation(
    PmlPresentation presentation,
    OfficeFindOptions options, {
    OfficeFindHit? only,
  }) {
    if (options.query.isEmpty) {
      return 0;
    }
    var count = 0;
    for (int s = 0; s < presentation.slides.length; s++) {
      if (only != null && only.slideIndex != s) {
        continue;
      }
      final PmlSlide slide = presentation.slides[s];
      if (only == null || only.shapeId == null) {
        if (_contains(slide.notes, options)) {
          slide.notes = _replaceAll(slide.notes, options);
          count++;
        }
      }
      for (final PmlShape shape in slide.shapes) {
        if (only != null && only.shapeId != null && only.shapeId != shape.id) {
          continue;
        }
        if (_contains(shape.text, options)) {
          shape.text = _replaceAll(shape.text, options);
          count++;
        }
        final PmlTable? table = shape.table;
        if (table == null) {
          continue;
        }
        for (final List<PmlTableCell> row in table.rows) {
          for (final PmlTableCell cell in row) {
            if (_contains(cell.text, options)) {
              cell.text = _replaceAll(cell.text, options);
              count++;
            }
          }
        }
      }
    }
    return count;
  }

  /// inPdf API.
  static List<OfficeFindHit> inPdf(PdfFile file, OfficeFindOptions options) {
    if (options.query.isEmpty) {
      return const <OfficeFindHit>[];
    }
    final List<OfficeFindHit> hits = <OfficeFindHit>[];
    for (int i = 0; i < file.pageCount; i++) {
      final String text = PdfExtract.pageText(file, i);
      for (final (int start, int end) in _spans(text, options)) {
        hits.add(
          OfficeFindHit(
            kind: OpcPackageKindHint.pdf,
            preview: text,
            pageIndex: i,
            start: start,
            end: end,
          ),
        );
      }
    }
    return hits;
  }

  static Iterable<(int, int)> _spans(String text, OfficeFindOptions options) {
    if (options.query.isEmpty) {
      return const <(int, int)>[];
    }
    if (options.wildcards || options.matchPrefix || options.matchSuffix) {
      return _regexSpans(text, options);
    }
    final String hay = options.matchCase ? text : text.toLowerCase();
    final String needle = options.matchCase
        ? options.query
        : options.query.toLowerCase();
    final List<(int, int)> spans = <(int, int)>[];
    var from = 0;
    while (from <= hay.length - needle.length) {
      final int at = hay.indexOf(needle, from);
      if (at < 0) {
        break;
      }
      final int end = at + needle.length;
      if (!options.wholeWord || _isWholeWord(text, at, end)) {
        spans.add((at, end));
      }
      from = at + needle.length;
    }
    return spans;
  }

  static Iterable<(int, int)> _regexSpans(
    String text,
    OfficeFindOptions options,
  ) {
    final String body = options.wildcards
        ? _wildcardPattern(options.query)
        : RegExp.escape(options.query);
    final String pattern;
    if (options.wholeWord) {
      pattern = '(?<![\\p{L}\\p{N}_])$body(?![\\p{L}\\p{N}_])';
    } else if (options.matchPrefix) {
      pattern = '(?<![\\p{L}\\p{N}_])$body';
    } else if (options.matchSuffix) {
      pattern = '$body(?![\\p{L}\\p{N}_])';
    } else {
      pattern = body;
    }
    final RegExp re = RegExp(
      pattern,
      caseSensitive: options.matchCase,
      unicode: true,
    );
    return <(int, int)>[
      for (final Match match in re.allMatches(text)) (match.start, match.end),
    ];
  }

  static String _wildcardPattern(String query) {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < query.length; i++) {
      final String ch = query[i];
      if (ch == '*') {
        // Token-scoped, like Office filename / Navigation-pane wildcards.
        buffer.write('[^\\s]*');
      } else if (ch == '?') {
        buffer.write(r'\S');
      } else {
        buffer.write(RegExp.escape(ch));
      }
    }
    return buffer.toString();
  }

  static bool _contains(String text, OfficeFindOptions options) {
    return _spans(text, options).isNotEmpty;
  }

  static String _replaceAll(String text, OfficeFindOptions options) {
    if (!options.matchCase &&
        !options.wholeWord &&
        !options.wildcards &&
        !options.matchPrefix &&
        !options.matchSuffix) {
      return text.replaceAll(
        RegExp(RegExp.escape(options.query), caseSensitive: false),
        options.replaceWith,
      );
    }
    final StringBuffer buffer = StringBuffer();
    var cursor = 0;
    for (final (int start, int end) in _spans(text, options)) {
      buffer
        ..write(text.substring(cursor, start))
        ..write(options.replaceWith);
      cursor = end;
    }
    buffer.write(text.substring(cursor));
    return buffer.toString();
  }

  static bool _isWholeWord(String text, int start, int end) {
    final bool left = start == 0 || !_isWordChar(text.codeUnitAt(start - 1));
    final bool right = end >= text.length || !_isWordChar(text.codeUnitAt(end));
    return left && right;
  }

  static bool _isWordChar(int cu) {
    return (cu >= 48 && cu <= 57) ||
        (cu >= 65 && cu <= 90) ||
        (cu >= 97 && cu <= 122) ||
        cu == 95 ||
        (cu >= 0x0600 && cu <= 0x06FF);
  }
}
