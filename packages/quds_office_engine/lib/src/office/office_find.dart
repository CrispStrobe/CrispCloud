import '../pdf/file/model/pdf_file.dart';
import '../pdf/file/text/pdf_extract.dart';
import '../sheet/model/sml_workbook.dart';
import '../slide/model/pml_presentation.dart';
import '../word/model/wml_document.dart';
import '../word/model/wml_run_edit.dart';
import '../word/model/word_content_controls.dart';
import '../word/model/word_revision.dart';

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
/// Word replacement requires a bound hit returned by [OfficeFind.inWord].
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
  }) : _wordTarget = null;

  OfficeFindHit._word({
    required this.preview,
    required this.paragraphIndex,
    required this.start,
    required this.end,
    required _WordFindTarget target,
  }) : kind = OpcPackageKindHint.word,
       _wordTarget = target,
       sheetName = null,
       a1 = null,
       slideIndex = null,
       shapeId = null,
       pageIndex = null;

  // Word replacement requires a hit returned by inWord, with its original
  // document, paragraph and inline shape. An index alone can name another
  // paragraph after an insertion, deletion or reorder.
  final _WordFindTarget? _wordTarget;

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

const _staleWordReplacement =
    'The document changed after finding or preparing replacements. '
    'Find the matches again before replacing them.';

/// Text and typed range structure, independent of mutable inline identities.
/// Rich undo restores cloned runs and boundary tokens with this same shape.
final class _WordParagraphSnapshot {
  _WordParagraphSnapshot(WmlParagraph paragraph)
    : text = paragraph.text,
      wrappers = List.of(paragraph.contentControlWrappers),
      shape = [for (final inline in paragraph.inlines) _inlineShape(inline)];

  final String text;
  final List<WmlContentControlData> wrappers;
  final List<Object> shape;

  bool matches(WmlParagraph paragraph) {
    if (paragraph.text != text ||
        paragraph.inlines.length != shape.length ||
        paragraph.contentControlWrappers.length != wrappers.length) {
      return false;
    }
    for (var index = 0; index < wrappers.length; index++) {
      if (!identical(
        paragraph.contentControlWrappers[index],
        wrappers[index],
      )) {
        return false;
      }
    }
    for (var index = 0; index < shape.length; index++) {
      if (_inlineShape(paragraph.inlines[index]) != shape[index]) return false;
    }
    return true;
  }

  static Object _inlineShape(WmlInline inline) => switch (inline) {
    WmlRun() => (
      WmlRun,
      inline.text.length,
      inline.noteRefId,
      inline.noteRefEndnote,
      inline.fieldInstruction,
      inline.fieldLocked,
      inline.fieldDirty,
    ),
    WmlContentControlBoundary() => (
      WmlContentControlBoundary,
      inline.control,
      inline.start,
    ),
    WmlBookmarkBoundary() => (
      WmlBookmarkBoundary,
      inline.id,
      inline.isStart,
      inline.name,
      inline.sourceXml,
    ),
    WmlNoteMarker() => (WmlNoteMarker, inline.endnote),
    WmlBreak() => (WmlBreak, inline.type),
    WmlObject() => (
      WmlObject,
      inline.relationshipId,
      inline.embedded,
      inline.width,
      inline.height,
    ),
  };
}

final class _WordFindTarget {
  _WordFindTarget(this.document, this.paragraph)
    : snapshot = _WordParagraphSnapshot(paragraph);

  final WmlDocument document;
  final WmlParagraph paragraph;
  final _WordParagraphSnapshot snapshot;
}

/// A validated replacement operation whose paragraph identities stay stable.
///
/// Hosts can capture rich paragraph contents and revision metadata after
/// preparing a plan, then execute it as one undoable command. All affected
/// paragraphs and their typed inline ranges are checked before the first text
/// mutation, including on replay.
class OfficeWordReplacePlan {
  OfficeWordReplacePlan._(this._document, this._replacement, this._edits)
    : _before = <WmlParagraph, _WordParagraphSnapshot>{
        for (final paragraph in _edits.map((edit) => edit.paragraph).toSet())
          paragraph: _WordParagraphSnapshot(paragraph),
      };

  final WmlDocument _document;
  final String _replacement;
  final List<({WmlParagraph paragraph, int start, int end})> _edits;
  final Map<WmlParagraph, _WordParagraphSnapshot> _before;

  /// Distinct live paragraphs affected by this operation.
  Iterable<WmlParagraph> get paragraphs => _before.keys;

  /// Number of distinct, atomic replacement ranges.
  int get count => _edits.length;

  void _validate() {
    final live = _document.paragraphs.toSet();
    for (final entry in _before.entries) {
      if (!live.contains(entry.key) || !entry.value.matches(entry.key)) {
        throw StateError(_staleWordReplacement);
      }
    }
    for (final edit in _edits) {
      final range = WmlRunEdit.normalizeRange(
        edit.paragraph,
        edit.start,
        edit.end,
      );
      if (range.start != edit.start || range.end != edit.end) {
        throw StateError(_staleWordReplacement);
      }
      WordContentControls.assertCanEdit(edit.paragraph, edit.start, edit.end);
    }
  }

  /// Applies preflighted replacements from right to left in each paragraph.
  int apply() {
    _validate();
    for (final edit in _edits) {
      WordRevisions.rebaseEdit(
        _document,
        edit.paragraph,
        start: edit.start,
        end: edit.end,
        insertedLength: _replacement.length,
      );
      WmlRunEdit.replaceRange(
        edit.paragraph,
        edit.start,
        edit.end,
        _replacement,
      );
    }
    return count;
  }
}

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
      _WordFindTarget? target;
      for (final (int start, int end) in _spans(text, options)) {
        hits.add(
          OfficeFindHit._word(
            preview: text,
            paragraphIndex: i,
            start: start,
            end: end,
            target: target ??= _WordFindTarget(document, paras[i]),
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
    return prepareWordReplace(document, options, only: only).apply();
  }

  /// Collects and validates every replacement before any live text changes.
  static OfficeWordReplacePlan prepareWordReplace(
    WmlDocument document,
    OfficeFindOptions options, {
    OfficeFindHit? only,
  }) {
    final List<WmlParagraph> paras = document.paragraphs.toList();
    if (only != null) {
      final target = only._wordTarget;
      final index = only.paragraphIndex;
      if (target == null ||
          !identical(target.document, document) ||
          index == null ||
          index < 0 ||
          index >= paras.length ||
          !identical(paras[index], target.paragraph) ||
          !target.snapshot.matches(target.paragraph)) {
        throw StateError(_staleWordReplacement);
      }
    }
    final edits = <({WmlParagraph paragraph, int start, int end})>[];
    if (options.query.isNotEmpty) {
      for (var index = 0; index < paras.length; index++) {
        if (only != null && only.paragraphIndex != index) continue;
        final paragraph = paras[index];
        final ranges = <({int start, int end})>{};
        for (final (start, end) in _spans(paragraph.text, options)) {
          if (only != null && (only.start != start || only.end != end)) {
            continue;
          }
          ranges.add(WmlRunEdit.normalizeRange(paragraph, start, end));
        }
        final ordered = ranges.toList()
          ..sort((a, b) => b.start.compareTo(a.start));
        int? nextStart;
        for (final range in ordered) {
          if (nextStart != null && range.end > nextStart) {
            throw UnsupportedError(
              'Replacement matches overlap an atomic '
              'field or note reference. Replace that object as one range.',
            );
          }
          edits.add((paragraph: paragraph, start: range.start, end: range.end));
          nextStart = range.start;
        }
      }
    }
    final plan = OfficeWordReplacePlan._(document, options.replaceWith, edits);
    plan._validate();
    return plan;
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
