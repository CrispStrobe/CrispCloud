import 'dart:convert';
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';

import '../../visual/office_visual.dart';
import '../properties/wml_properties.dart';
import 'wml_document.dart';
import 'word_revision.dart';

/// Which pending revision text participates in a comparison.
enum WordComparisonRevisionView { finalText, originalText, markup }

/// A paragraph or modeled structural difference.
enum WordComparisonKind {
  unchanged,
  inserted,
  deleted,
  modified,
  formatting,
  structure,
}

/// Inline redline operation; grapheme clusters are never split.
enum WordComparisonSpanKind { equal, insert, delete }

/// Bounded, read-only comparison settings. Whitespace normalization collapses
/// runs of whitespace and ignores leading/trailing whitespace. Case folding is
/// Dart's locale-independent [String.toLowerCase], not linguistic collation.
class WordComparisonOptions {
  const WordComparisonOptions({
    this.ignoreCase = false,
    this.ignoreWhitespace = false,
    this.includeFormatting = true,
    this.revisionView = WordComparisonRevisionView.finalText,
    this.maxParagraphs = 20000,
    this.maxTextLength = 4000000,
    this.maxDiffWork = 2000000,
  });

  final bool ignoreCase;
  final bool ignoreWhitespace;
  final bool includeFormatting;
  final WordComparisonRevisionView revisionView;

  /// Maximum paragraphs per input, including auxiliary stories.
  final int maxParagraphs;

  /// Maximum UTF-16 units in text, preserved XML and comparison metadata per
  /// input. Metadata is counted too, so heavily formatted documents may reach
  /// this limit before plain text reaches this length.
  final int maxTextLength;

  /// Shared maximum dynamic-programming cells across paragraph/inline diffs.
  final int maxDiffWork;

  Map<String, Object?> toJson() => <String, Object?>{
    'ignoreCase': ignoreCase,
    'ignoreWhitespace': ignoreWhitespace,
    'includeFormatting': includeFormatting,
    'revisionView': revisionView.name,
    'maxParagraphs': maxParagraphs,
    'maxTextLength': maxTextLength,
    'maxDiffWork': maxDiffWork,
  };
}

/// Stable report location, with no references back to the mutable input model.
class WordComparisonLocation {
  const WordComparisonLocation({
    required this.story,
    required this.label,
    required this.paragraphIndex,
    required this.path,
    this.sectionIndex,
  });

  /// Story identity, e.g. `body:0`, `header:0`, `footnote:0`.
  final String story;
  final String label;

  /// Zero-based paragraph number in this story; -1 for structural entries.
  final int paragraphIndex;
  final String path;
  final int? sectionIndex;

  Map<String, Object?> toJson() => <String, Object?>{
    'story': story,
    'label': label,
    'paragraphIndex': paragraphIndex,
    'path': path,
    if (sectionIndex != null) 'sectionIndex': sectionIndex,
  };
}

class WordComparisonSpan {
  const WordComparisonSpan({
    required this.kind,
    required this.text,
    this.originalText = '',
  });

  final WordComparisonSpanKind kind;

  /// Revised text for equal/insert spans; original text for delete spans.
  final String text;

  /// Original text for equal/delete spans, empty for insert spans. It can
  /// differ from [text] when case/whitespace differences are ignored.
  final String originalText;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'text': text,
    'originalText': originalText,
  };
}

class WordComparisonEntry {
  WordComparisonEntry({
    required this.id,
    required this.kind,
    required this.originalText,
    required this.revisedText,
    this.originalLocation,
    this.revisedLocation,
    Iterable<WordComparisonSpan> spans = const <WordComparisonSpan>[],
    Iterable<String> formattingChanges = const <String>[],
    Iterable<String> details = const <String>[],
  }) : spans = List<WordComparisonSpan>.unmodifiable(spans),
       formattingChanges = List<String>.unmodifiable(formattingChanges),
       details = List<String>.unmodifiable(details);

  final int id;
  final WordComparisonKind kind;
  final String originalText;
  final String revisedText;
  final WordComparisonLocation? originalLocation;
  final WordComparisonLocation? revisedLocation;
  final List<WordComparisonSpan> spans;
  final List<String> formattingChanges;
  final List<String> details;
  bool get isChange => kind != WordComparisonKind.unchanged;
  String get label => revisedLocation?.label ?? originalLocation?.label ?? '';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind.name,
    'originalText': originalText,
    'revisedText': revisedText,
    'originalLocation': originalLocation?.toJson(),
    'revisedLocation': revisedLocation?.toJson(),
    'spans': spans.map((span) => span.toJson()).toList(),
    'formattingChanges': formattingChanges,
    'details': details,
  };
}

class WordComparisonResult {
  WordComparisonResult._({
    required Iterable<WordComparisonEntry> entries,
    required Iterable<String> warnings,
    required this.options,
    required this.usedCoarseDiff,
  }) : entries = List<WordComparisonEntry>.unmodifiable(entries),
       warnings = List<String>.unmodifiable(warnings);

  final List<WordComparisonEntry> entries;
  final List<String> warnings;
  final WordComparisonOptions options;

  /// Stable report scope: equality of compared content is not proof of whole
  /// package equivalence or identical rendering in another office application.
  Map<String, List<String>> get scope => const <String, List<String>>{
    'compared': <String>[
      'Modeled text in body, tables, frames, TOC title/results, headers, footers, notes and comments.',
      'Optional direct paragraph/run formatting, modeled styles and section/table/frame layout.',
      'Modeled links, field instructions, bookmarks, comment metadata and content controls.',
      'Preserved content XML digests/relationships and selected visual geometry/labels.',
    ],
    'limits': <String>[
      'Not exhaustive: numbering definitions, document/package settings and metadata, protection, themes and unmodeled native properties.',
      'No rendered-page comparison, image pixel/chart/diagram internals or embedded-object payload comparison.',
      'Formatting within rewritten paragraphs is summarized by the styles used; exact formatting alignment is available for unchanged or normalized-equal text.',
      'Revision projection applies to text. It does not resolve pending changes or compare revision attribution/history.',
      'Sections, tables, notes and comments use ordered locations; moved content is not classified as a native move revision.',
    ],
  };

  /// True when difficult regions used a complete, less precise replacement
  /// instead of spending unbounded time searching for a minimal edit script.
  final bool usedCoarseDiff;
  Iterable<WordComparisonEntry> get changes => entries.where((e) => e.isChange);
  bool get hasChanges => entries.any((e) => e.isChange);
  int get changeCount => changes.length;
  int get insertedCount => _count(WordComparisonKind.inserted);
  int get deletedCount => _count(WordComparisonKind.deleted);
  int get modifiedCount => _count(WordComparisonKind.modified);
  int get formattingCount => _count(WordComparisonKind.formatting);
  int get structureCount => _count(WordComparisonKind.structure);
  int get unchangedCount => _count(WordComparisonKind.unchanged);
  int _count(WordComparisonKind kind) =>
      entries.where((e) => e.kind == kind).length;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'scope': scope,
    'options': options.toJson(),
    'usedCoarseDiff': usedCoarseDiff,
    'summary': <String, int>{
      'changes': changeCount,
      'inserted': insertedCount,
      'deleted': deletedCount,
      'modified': modifiedCount,
      'formatting': formattingCount,
      'structure': structureCount,
      'unchanged': unchangedCount,
    },
    'warnings': warnings,
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };

  String toJsonString({bool pretty = true}) =>
      (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
          .convert(toJson());
}

/// Compares modeled Word content without accepting/rejecting revisions,
/// changing source ranges, serializing packages, or mutating either input.
///
/// Text includes body/tables/frames, six header/footer variants, notes and
/// comments. Section/table/frame geometry and modeled paragraph/run formatting
/// are reported separately. This is not a binary or rendered-page comparison;
/// unsupported visual and opaque native content is explicitly disclosed.
abstract final class WordDocumentComparison {
  static WordComparisonResult compare(
    WmlDocument original,
    WmlDocument revised, {
    WordComparisonOptions options = const WordComparisonOptions(),
  }) => _Comparison(options).compare(original, revised);
}

class _Comparison {
  _Comparison(this.options) : budget = _DiffBudget(options.maxDiffWork);

  final WordComparisonOptions options;
  final _DiffBudget budget;
  final List<WordComparisonEntry> entries = <WordComparisonEntry>[];
  final Set<String> warnings = <String>{};

  String normalize(String text) {
    var result = text;
    if (options.ignoreWhitespace) {
      result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return options.ignoreCase ? result.toLowerCase() : result;
  }

  WordComparisonResult compare(WmlDocument original, WmlDocument revised) {
    warnings.add(
      'This report compares modeled content. Numbering definitions, '
      'document/package settings and metadata, protection, themes, binary payloads '
      'and rendered layout are not exhaustively compared.',
    );
    for (final entry in <String, int>{
      'maxParagraphs': options.maxParagraphs,
      'maxTextLength': options.maxTextLength,
      'maxDiffWork': options.maxDiffWork,
    }.entries) {
      if (entry.value <= 0) {
        throw ArgumentError.value(entry.value, entry.key, 'Must be positive');
      }
    }
    final left = _Collector(options, warnings).collect(original);
    final right = _Collector(options, warnings).collect(revised);
    final structureKeys = <String>{
      ...left.structure.keys,
      ...right.structure.keys,
    };
    for (final key in structureKeys) {
      final a = left.structure[key];
      final b = right.structure[key];
      if (a?.signature == b?.signature) continue;
      entries.add(
        WordComparisonEntry(
          id: entries.length,
          kind: a != null && b != null && a.formatting && b.formatting
              ? WordComparisonKind.formatting
              : WordComparisonKind.structure,
          originalText: a?.description ?? '',
          revisedText: b?.description ?? '',
          originalLocation: a?.location,
          revisedLocation: b?.location,
          formattingChanges:
              a != null && b != null && a.formatting && b.formatting
              ? _differentProperties(a.values, b.values)
              : const <String>[],
          details: a == null
              ? const <String>['Modeled structure added.']
              : b == null
              ? const <String>['Modeled structure removed.']
              : _differentProperties(a.values, b.values),
        ),
      );
    }
    final storyKeys = <String>{...left.stories.keys, ...right.stories.keys};
    for (final key in storyKeys) {
      final a = left.stories[key] ?? const <_ParagraphRecord>[];
      final b = right.stories[key] ?? const <_ParagraphRecord>[];
      final matches = _matchSequences(
        a.map((p) => normalize(p.text)).toList(),
        b.map((p) => normalize(p.text)).toList(),
        budget,
      );
      var ai = 0;
      var bi = 0;
      for (final pair in <_Match>[...matches, _Match(a.length, b.length)]) {
        while (ai < pair.a && bi < pair.b) {
          _paragraph(a[ai++], b[bi++]);
        }
        while (ai < pair.a) {
          _paragraph(a[ai++], null);
        }
        while (bi < pair.b) {
          _paragraph(null, b[bi++]);
        }
        if (pair.a < a.length) {
          _paragraph(a[ai++], b[bi++]);
        }
      }
    }
    if (budget.coarse) {
      warnings.add(
        'Some dense differences exceeded the alignment work budget. '
        'Their complete text is shown as a coarser replacement; no input text was truncated.',
      );
    }
    return WordComparisonResult._(
      entries: entries,
      warnings: warnings,
      options: options,
      usedCoarseDiff: budget.coarse,
    );
  }

  void _paragraph(_ParagraphRecord? a, _ParagraphRecord? b) {
    final before = a?.text ?? '';
    final after = b?.text ?? '';
    final sameText =
        a != null && b != null && normalize(before) == normalize(after);
    final formatting = <String>[];
    final details = <String>[];
    if (a != null && b != null) {
      if (options.includeFormatting) {
        formatting.addAll(_differentProperties(a.properties, b.properties));
        if (before == after && a.runFormatting != b.runFormatting) {
          formatting.add('Direct character formatting changed.');
        } else if (sameText &&
            a.normalizedRunFormatting != b.normalizedRunFormatting) {
          formatting.add('Direct character formatting changed.');
        } else if (before != after && a.runStyleSet != b.runStyleSet) {
          formatting.add(
            'The direct character styles used in this paragraph changed.',
          );
        }
      }
      if (a.semantics != b.semantics) {
        details.add(
          'Fields, links, breaks, bookmarks, or other inline structure changed.',
        );
      }
      if (a.context != b.context) {
        details.add(
          'Paragraph container changed (${a.context} → ${b.context}).',
        );
      }
    }
    final kind = a == null
        ? WordComparisonKind.inserted
        : b == null
        ? WordComparisonKind.deleted
        : !sameText
        ? WordComparisonKind.modified
        : details.isNotEmpty
        ? WordComparisonKind.structure
        : formatting.isNotEmpty
        ? WordComparisonKind.formatting
        : WordComparisonKind.unchanged;
    final spans = <WordComparisonSpan>[];
    if (a == null) {
      if (after.isNotEmpty) {
        spans.add(
          WordComparisonSpan(kind: WordComparisonSpanKind.insert, text: after),
        );
      }
    } else if (b == null) {
      if (before.isNotEmpty) {
        spans.add(
          WordComparisonSpan(
            kind: WordComparisonSpanKind.delete,
            text: before,
            originalText: before,
          ),
        );
      }
    } else if (sameText) {
      if (before.isNotEmpty || after.isNotEmpty) {
        spans.add(
          WordComparisonSpan(
            kind: WordComparisonSpanKind.equal,
            text: after,
            originalText: before,
          ),
        );
      }
    } else {
      spans.addAll(_inlineDiff(before, after));
    }
    entries.add(
      WordComparisonEntry(
        id: entries.length,
        kind: kind,
        originalText: before,
        revisedText: after,
        originalLocation: a?.location,
        revisedLocation: b?.location,
        spans: spans,
        formattingChanges: formatting,
        details: details,
      ),
    );
  }

  List<WordComparisonSpan> _inlineDiff(String before, String after) {
    final a = _tokens(before);
    final b = _tokens(after);
    String key(String s) {
      final value = options.ignoreWhitespace && s.trim().isEmpty ? ' ' : s;
      return options.ignoreCase ? value.toLowerCase() : value;
    }

    final matches = _matchSequences(
      a.map(key).toList(),
      b.map(key).toList(),
      budget,
    );
    final result = <WordComparisonSpan>[];
    WordComparisonSpanKind? bufferedKind;
    var bufferedText = StringBuffer();
    var bufferedOriginal = StringBuffer();
    void flush() {
      if (bufferedKind == null) return;
      result.add(
        WordComparisonSpan(
          kind: bufferedKind!,
          text: bufferedText.toString(),
          originalText: bufferedOriginal.toString(),
        ),
      );
      bufferedText = StringBuffer();
      bufferedOriginal = StringBuffer();
    }

    void append(WordComparisonSpanKind kind, String text, String old) {
      if (text.isEmpty && old.isEmpty) return;
      if (bufferedKind != kind) {
        flush();
        bufferedKind = kind;
      }
      bufferedText.write(text);
      bufferedOriginal.write(old);
    }

    var ai = 0;
    var bi = 0;
    for (final pair in <_Match>[...matches, _Match(a.length, b.length)]) {
      final deleted = a.sublist(ai, pair.a).join();
      final inserted = b.sublist(bi, pair.b).join();
      append(WordComparisonSpanKind.delete, deleted, deleted);
      append(WordComparisonSpanKind.insert, inserted, '');
      if (pair.a < a.length) {
        append(WordComparisonSpanKind.equal, b[pair.b], a[pair.a]);
      }
      ai = pair.a + 1;
      bi = pair.b + 1;
    }
    flush();
    return result;
  }
}

class _DiffBudget {
  _DiffBudget(this.remaining);
  int remaining;
  bool coarse = false;
}

class _Match {
  const _Match(this.a, this.b);
  final int a;
  final int b;
}

/// Exact LCS in affordable gaps, unique patience anchors in large regions.
/// Prefix/suffix stripping keeps an edit in a large otherwise equal document
/// linear. No quadratic matrix is allocated without reserving its budget.
List<_Match> _matchSequences(
  List<String> a,
  List<String> b,
  _DiffBudget budget,
) {
  final result = <_Match>[];
  void align(int a0, int a1, int b0, int b1, int depth) {
    while (a0 < a1 && b0 < b1 && a[a0] == b[b0]) {
      result.add(_Match(a0++, b0++));
    }
    var suffix = 0;
    while (a0 < a1 && b0 < b1 && a[a1 - 1] == b[b1 - 1]) {
      a1--;
      b1--;
      suffix++;
    }
    final n = a1 - a0;
    final m = b1 - b0;
    if (n > 0 && m > 0) {
      final cells = (n + 1) * (m + 1);
      if (cells <= budget.remaining) {
        budget.remaining -= cells;
        final width = m + 1;
        final matrix = Uint32List(cells);
        for (var i = n - 1; i >= 0; i--) {
          for (var j = m - 1; j >= 0; j--) {
            final at = i * width + j;
            if (a[a0 + i] == b[b0 + j]) {
              matrix[at] = matrix[at + width + 1] + 1;
            } else {
              final down = matrix[at + width];
              final right = matrix[at + 1];
              matrix[at] = down > right ? down : right;
            }
          }
        }
        var i = 0;
        var j = 0;
        while (i < n && j < m) {
          if (a[a0 + i] == b[b0 + j]) {
            result.add(_Match(a0 + i++, b0 + j++));
          } else if (matrix[(i + 1) * width + j] >= matrix[i * width + j + 1]) {
            i++;
          } else {
            j++;
          }
        }
      } else if (depth < 32) {
        final ac = <String, int>{};
        final bc = <String, int>{};
        for (var i = a0; i < a1; i++) {
          ac[a[i]] = ac.containsKey(a[i]) ? -1 : i;
        }
        for (var i = b0; i < b1; i++) {
          bc[b[i]] = bc.containsKey(b[i]) ? -1 : i;
        }
        final candidates = <_Match>[];
        for (var i = a0; i < a1; i++) {
          final j = bc[a[i]];
          if (ac[a[i]] == i && j != null && j >= 0) {
            candidates.add(_Match(i, j));
          }
        }
        final anchors = _increasing(candidates);
        if (anchors.isEmpty) {
          budget.coarse = true;
        } else {
          var ai = a0;
          var bi = b0;
          for (final anchor in anchors) {
            align(ai, anchor.a, bi, anchor.b, depth + 1);
            result.add(anchor);
            ai = anchor.a + 1;
            bi = anchor.b + 1;
          }
          align(ai, a1, bi, b1, depth + 1);
        }
      } else {
        budget.coarse = true;
      }
    }
    for (var i = 0; i < suffix; i++) {
      result.add(_Match(a1 + i, b1 + i));
    }
  }

  align(0, a.length, 0, b.length, 0);
  return result;
}

List<_Match> _increasing(List<_Match> candidates) {
  if (candidates.isEmpty) return const <_Match>[];
  final tails = <int>[];
  final previous = List<int>.filled(candidates.length, -1);
  for (var i = 0; i < candidates.length; i++) {
    var lo = 0;
    var hi = tails.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (candidates[tails[mid]].b < candidates[i].b) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0) previous[i] = tails[lo - 1];
    if (lo == tails.length) {
      tails.add(i);
    } else {
      tails[lo] = i;
    }
  }
  final result = <_Match>[];
  var at = tails.last;
  while (at >= 0) {
    result.add(candidates[at]);
    at = previous[at];
  }
  return result.reversed.toList();
}

List<String> _tokens(String text) {
  final result = <String>[];
  final wordStart = RegExp(
    r'^[A-Za-z0-9_\u00c0-\u02ff\u0370-\u052f\u0590-\u08ff\u0900-\u1fff]',
  );
  var current = StringBuffer();
  var previousKind = -1;
  for (final grapheme in text.characters) {
    final kind = grapheme.trim().isEmpty
        ? 0
        : wordStart.hasMatch(grapheme)
        ? 1
        : 2;
    if (current.isNotEmpty && (kind != previousKind || kind == 2)) {
      result.add(current.toString());
      current = StringBuffer();
    }
    current.write(grapheme);
    previousKind = kind;
  }
  if (current.isNotEmpty) result.add(current.toString());
  return result;
}

List<String> _differentProperties(
  Map<String, Object?> a,
  Map<String, Object?> b,
) => <String>[
  for (final key in <String>{...a.keys, ...b.keys})
    if (jsonEncode(a[key]) != jsonEncode(b[key]))
      '$key: ${a[key] ?? 'unset'} → ${b[key] ?? 'unset'}',
];

class _ParagraphRecord {
  _ParagraphRecord(
    this.paragraph,
    this.location,
    this.context,
    this.rawText,
    this.bookmarkStory,
  );
  final WmlParagraph paragraph;
  final WordComparisonLocation location;
  final String context;
  final String rawText;
  final String bookmarkStory;
  String text = '';
  Map<String, Object?> properties = <String, Object?>{};
  String runFormatting = '';
  String normalizedRunFormatting = '';
  String runStyleSet = '';
  String semantics = '';
}

class _StructureRecord {
  _StructureRecord(this.location, this.values, {this.formatting = false});
  final WordComparisonLocation location;
  final Map<String, Object?> values;
  final bool formatting;
  String get signature => jsonEncode(values);
  String get description =>
      values.entries.map((e) => '${e.key}: ${e.value ?? 'unset'}').join('\n');
}

class _Collected {
  final Map<String, List<_ParagraphRecord>> stories =
      <String, List<_ParagraphRecord>>{};
  final Map<String, _StructureRecord> structure = <String, _StructureRecord>{};
}

class _Collector {
  _Collector(this.options, this.warnings);
  final WordComparisonOptions options;
  final Set<String> warnings;
  final _Collected output = _Collected();
  final List<_ParagraphRecord> records = <_ParagraphRecord>[];
  final List<WmlParagraph> body = <WmlParagraph>[];
  var textUnits = 0;
  var nodes = 0;

  Never _limit(String limit) => throw StateError(
    'Document comparison exceeds $limit. Increase the explicit comparison '
    'limit or compare a smaller document; no partial result was produced.',
  );

  void _node() {
    nodes++;
    if (nodes > options.maxParagraphs * 20) _limit('the model-node limit');
  }

  void _charge(int count) {
    textUnits += count;
    if (textUnits > options.maxTextLength) {
      _limit('maxTextLength (${options.maxTextLength})');
    }
  }

  _Collected collect(WmlDocument document) {
    for (var s = 0; s < document.sections.length; s++) {
      _node();
      final section = document.sections[s];
      final label = 'Section ${s + 1}';
      _structure('section:$s', label, <String, Object?>{
        'Section': s + 1,
      }, section: s);
      if (options.includeFormatting) {
        _structure(
          'section-layout:$s',
          '$label · Page layout',
          <String, Object?>{
            'Page width': section.pageSize.width,
            'Page height': section.pageSize.height,
            'Margins': <double>[
              section.margins.top,
              section.margins.bottom,
              section.margins.left,
              section.margins.right,
              section.margins.header,
              section.margins.footer,
            ],
            'Columns': section.columnCount,
            'Column spacing': section.columnSpace,
            'Column separator': section.columnSep,
            'Section break': section.breakKind.name,
            'Different first page': section.differentFirstPage,
            'Different odd/even pages': section.differentOddEven,
            'Linked to previous': section.linkToPrevious,
            'Line numbers': section.lineNumbers,
          },
          section: s,
          formatting: true,
        );
        if (section.sourceProperties != null) _nativePropertiesWarning();
      }
      _blocks(
        section.blocks,
        'body:$s',
        '$label · Body',
        '',
        section: s,
        isBody: true,
      );
      final stories = <String, List<WmlParagraph>>{
        'header': section.header,
        'footer': section.footer,
        'firstHeader': section.firstHeader,
        'firstFooter': section.firstFooter,
        'evenHeader': section.evenHeader,
        'evenFooter': section.evenFooter,
      };
      for (final story in stories.entries) {
        _blocks(
          story.value,
          '${story.key}:$s',
          '$label · ${story.key}',
          '',
          section: s,
        );
      }
      for (final story in section.preservedStories.entries) {
        _opaque(
          story.value,
          'preserved-${story.key}:$s',
          '$label · Preserved ${story.key}',
          section: s,
        );
      }
      final visualStories = <String, List<WmlVisual>>{
        'header': section.headerVisuals,
        'footer': section.footerVisuals,
        'firstHeader': section.firstHeaderVisuals,
        'firstFooter': section.firstFooterVisuals,
        'evenHeader': section.evenHeaderVisuals,
        'evenFooter': section.evenFooterVisuals,
      };
      for (final story in visualStories.entries) {
        for (var i = 0; i < story.value.length; i++) {
          _node();
          _visual(
            story.value[i].visual,
            '${story.key}:$s:visual:$i',
            '$label · ${story.key} · Visual ${i + 1}',
            section: s,
          );
        }
      }
    }
    for (var i = 0; i < document.footnotes.length; i++) {
      final note = document.footnotes[i];
      _blocks(
        note.blocks,
        'footnote:$i',
        'Footnote ${i + 1} (source ${note.id})',
        '',
      );
    }
    for (var i = 0; i < document.endnotes.length; i++) {
      final note = document.endnotes[i];
      _blocks(
        note.blocks,
        'endnote:$i',
        'Endnote ${i + 1} (source ${note.id})',
        '',
      );
    }
    for (var i = 0; i < document.comments.length; i++) {
      _node();
      final comment = document.comments[i];
      final label = 'Comment ${i + 1}';
      _blocks(comment.paragraphs, 'comment:$i', label, '');
      _structure(
        'comment:$i:metadata',
        '$label · Review metadata',
        <String, Object?>{
          'Author': comment.author,
          'Initials': comment.initials,
          'Date': comment.dateIso,
          'Resolved': comment.resolved,
          'Parent ID': comment.parentId,
        },
      );
      for (var j = 0; j < comment.visuals.length; j++) {
        _node();
        _visual(
          comment.visuals[j].visual,
          'comment:$i:visual:$j',
          '$label · Visual ${j + 1}',
        );
      }
    }
    if (options.includeFormatting) {
      final styles = document.styles.toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      for (final style in styles) {
        _node();
        _structure(
          'style:${style.id}',
          'Style ${style.name}',
          <String, Object?>{
            'ID': style.id,
            'Name': style.name,
            'Based on': style.basedOn,
            'Heading level': style.headingLevel,
            'Alignment': style.justification.name,
            'Bold': style.bold,
            'Italic': style.italic,
            'Font size': style.fontSizePoints,
            'Color': style.color,
            'Font': style.font,
            'Complex-script font': style.csFont,
            'Before spacing': style.spacingBefore,
            'After spacing': style.spacingAfter,
            'Numbering ID': style.numId,
            'Numbering level': style.ilvl,
            'Indent': style.indent == null
                ? null
                : <double>[
                    style.indent!.left,
                    style.indent!.right,
                    style.indent!.firstLine,
                    style.indent!.hanging,
                  ],
          },
          formatting: true,
        );
      }
    }
    final attached = Set<WmlParagraph>.identity()
      ..addAll(records.map((r) => r.paragraph));
    final revisions = Map<WmlParagraph, List<WmlRevision>>.identity();
    for (final revision in document.revisions) {
      _node();
      if (revision.accepted != null) continue;
      final target =
          revision.targetParagraph ??
          (!revision.hasCapturedTarget &&
                  revision.paragraphIndex >= 0 &&
                  revision.paragraphIndex < body.length
              ? body[revision.paragraphIndex]
              : null);
      if (target == null || !attached.contains(target)) {
        if (options.revisionView != WordComparisonRevisionView.markup) {
          throw StateError(
            'Cannot project tracked change ${revision.id}: its paragraph is detached.',
          );
        }
        warnings.add(
          'Markup view contains unresolved tracked changes; their original/final text cannot be projected safely.',
        );
        continue;
      }
      revisions.putIfAbsent(target, () => <WmlRevision>[]).add(revision);
    }
    final bookmarkIds = <String, Map<String, int>>{};
    for (final record in records) {
      final storyIds = bookmarkIds.putIfAbsent(
        record.bookmarkStory,
        () => <String, int>{},
      );
      for (final boundary
          in record.paragraph.inlines.whereType<WmlBookmarkBoundary>()) {
        storyIds.putIfAbsent(boundary.id, () => storyIds.length);
      }
    }
    final commentIds = <int, int>{
      for (var i = 0; i < document.comments.length; i++)
        document.comments[i].id: i,
    };
    for (final record in records) {
      final pending = revisions[record.paragraph] ?? const <WmlRevision>[];
      final removed = _removedRanges(record.rawText, pending);
      _snapshot(
        record,
        removed,
        bookmarkIds[record.bookmarkStory]!,
        commentIds,
      );
    }
    return output;
  }

  void _nativePropertiesWarning() => warnings.add(
    'Comparison covers modeled formatting. Unmodeled native property XML, '
    'package themes and rendered layout are outside this report.',
  );

  void _structure(
    String key,
    String label,
    Map<String, Object?> values, {
    int? section,
    bool formatting = false,
  }) {
    _charge(jsonEncode(values).length);
    output.structure[key] = _StructureRecord(
      WordComparisonLocation(
        story: key,
        label: label,
        paragraphIndex: -1,
        path: key,
        sectionIndex: section,
      ),
      values,
      formatting: formatting,
    );
  }

  void _opaque(
    WmlOpaqueBlock block,
    String key,
    String label, {
    int? section,
    int? textOffset,
    int? afterParagraph,
  }) {
    _charge(block.xml.length);
    _structure(key, label, <String, Object?>{
      'Text offset': ?textOffset,
      'After paragraph': ?afterParagraph,
      'Preserved XML digest': sha256.convert(utf8.encode(block.xml)).toString(),
      'Relationships': <Object?>[
        for (final r in block.relationships)
          <String, Object?>{
            'id': r.id,
            'type': r.type,
            'target': r.target,
            'mode': r.targetMode.name,
            'contentType': r.contentType,
            'sha256': r.sha256,
          },
      ],
    }, section: section);
    warnings.add(
      'Preserved native XML is compared by content digest and relationships, '
      'not interpreted or visually rendered. Equivalent XML encodings can differ.',
    );
  }

  void _visual(
    OfficeVisual visual,
    String key,
    String label, {
    int? section,
    int? textOffset,
    int? afterParagraph,
  }) {
    final picture = visual.picture;
    _structure(key, label, <String, Object?>{
      'Text offset': ?textOffset,
      'After paragraph': ?afterParagraph,
      'Kind': visual.kind.name,
      'Title': visual.title,
      'Width': visual.width,
      'Height': visual.height,
      'X': visual.offsetX,
      'Y': visual.offsetY,
      'Image bytes': visual.imageBytes?.length,
      'Crop': <double>[
        picture.cropLeft,
        picture.cropTop,
        picture.cropRight,
        picture.cropBottom,
      ],
      'Rotation': picture.rotationDeg,
      'Wrap': picture.wrap.name,
      'Flip horizontal': picture.flipH,
      'Flip vertical': picture.flipV,
      'Alt title': picture.altTitle,
      'Alt description': picture.altDescription,
    }, section: section);
    warnings.add(
      'Visual geometry and labels are compared; image pixels, chart data, '
      'diagram internals and embedded-object payloads are outside this report.',
    );
  }

  void _blocks(
    Iterable<WmlBlock> blocks,
    String story,
    String label,
    String context, {
    int? section,
    bool isBody = false,
    int depth = 0,
    String? bookmarkStory,
  }) {
    if (depth > 128) _limit('the nesting-depth limit (128)');
    var paragraph = 0;
    var table = 0;
    var frame = 0;
    var control = 0;
    var contents = 0;
    var other = 0;
    for (final block in blocks) {
      _node();
      final blockOffset = output.stories[story]?.length ?? 0;
      if (block is WmlParagraph) {
        final list = output.stories.putIfAbsent(
          story,
          () => <_ParagraphRecord>[],
        );
        paragraph++;
        final prefix = context.isEmpty ? label : '$label · $context';
        final location = WordComparisonLocation(
          story: story,
          label: '$prefix · Paragraph $paragraph',
          paragraphIndex: list.length,
          path: '$story/$context/paragraph:$paragraph',
          sectionIndex: section,
        );
        if (records.length >= options.maxParagraphs) {
          _limit('maxParagraphs (${options.maxParagraphs})');
        }
        final buffer = StringBuffer();
        for (final inline in block.inlines) {
          _node();
          if (inline is WmlRun) {
            _charge(inline.text.length);
            buffer.write(inline.text);
          }
        }
        final record = _ParagraphRecord(
          block,
          location,
          context,
          buffer.toString(),
          bookmarkStory ?? (isBody ? 'body' : story),
        );
        list.add(record);
        records.add(record);
        if (isBody) body.add(block);
        if (options.includeFormatting &&
            block.properties.sourcePropertiesXml != null) {
          _nativePropertiesWarning();
        }
      } else if (block is WmlTable) {
        table++;
        final path = '${context.isEmpty ? '' : '$context · '}Table $table';
        final rows = <Object?>[];
        for (var r = 0; r < block.rows.length; r++) {
          _node();
          final row = block.rows[r];
          final cells = <Object?>[];
          for (var c = 0; c < row.cells.length; c++) {
            _node();
            final cell = row.cells[c];
            cells.add(<String, Object?>{
              'span': cell.gridSpan,
              'merge': cell.vMerge.name,
              if (options.includeFormatting) ...<String, Object?>{
                'width': cell.width,
                'fill': cell.fillColor,
                'borders': <bool?>[
                  cell.borderTop,
                  cell.borderBottom,
                  cell.borderLeft,
                  cell.borderRight,
                ],
              },
            });
            _blocks(
              cell.blocks,
              story,
              label,
              '$path · Row ${r + 1}, Cell ${c + 1}',
              section: section,
              isBody: isBody,
              depth: depth + 1,
              bookmarkStory: bookmarkStory,
            );
          }
          rows.add(<String, Object?>{
            'gridBefore': row.gridBefore,
            'gridAfter': row.gridAfter,
            'cells': cells,
            if (options.includeFormatting) ...<String, Object?>{
              'height': row.height,
              'keepTogether': row.cantSplit,
            },
          });
        }
        _structure('$story/$path', '$label · $path', <String, Object?>{
          'After paragraph': blockOffset,
          'Grid columns': block.grid.length,
          if (options.includeFormatting) 'Grid widths': block.grid,
          'Rows': rows,
          if (options.includeFormatting) ...<String, Object?>{
            'Alignment': block.properties.alignment.name,
            'Floating': block.properties.floating,
            'Cell margin': block.properties.cellMargin,
            'Right to left': block.properties.rightToLeft,
            'Borders': block.properties.borders,
            'Border color': block.properties.borderColor,
            'Border width': block.properties.borderWidth,
            'Style': block.properties.styleId,
          },
        }, section: section);
      } else if (block is WmlFrame) {
        frame++;
        final path = '${context.isEmpty ? '' : '$context · '}Frame $frame';
        _structure('$story/$path', '$label · $path', <String, Object?>{
          'After paragraph': blockOffset,
          'Text box': block.hasTextBox,
          if (options.includeFormatting) ...<String, Object?>{
            'X': block.x,
            'Y': block.y,
            'Width': block.width,
            'Height': block.height,
            'Anchor': block.anchor.name,
            'Wrap': block.wrap.name,
            'Fill': block.fillColor,
            'Stroke': block.strokeColor,
            'Insets': <double>[
              block.insetLeft,
              block.insetTop,
              block.insetRight,
              block.insetBottom,
            ],
          },
        }, section: section);
        _blocks(
          block.blocks,
          story,
          label,
          path,
          section: section,
          isBody: isBody,
          depth: depth + 1,
          bookmarkStory: '$story/$path',
        );
      } else if (block is WmlToc) {
        contents++;
        final path =
            '${context.isEmpty ? '' : '$context · '}Contents $contents';
        final cachedEntries = <Object?>[];
        for (final entry in block.entries) {
          _node();
          cachedEntries.add(<Object?>[
            entry.text,
            entry.level,
            entry.pageNumber,
          ]);
        }
        _structure('$story/$path', '$label · $path', <String, Object?>{
          'After paragraph': blockOffset,
          'Minimum level': block.minLevel,
          'Maximum level': block.maxLevel,
          'Page numbers': block.showPageNumbers,
          'Omit numbers from': block.omitPageNumbersFromLevel,
          'Omit numbers through': block.omitPageNumbersThroughLevel,
          'Caption label': block.captionLabel,
          'Cached entries': cachedEntries,
        }, section: section);
        // This order must match WordTree.paragraphs: legacy tracked-change
        // indices count a TOC's title and live cached result paragraphs.
        _blocks(
          <WmlParagraph>[block.titleParagraph, ...block.itemParagraphs],
          story,
          label,
          path,
          section: section,
          isBody: isBody,
          depth: depth + 1,
          bookmarkStory: bookmarkStory,
        );
      } else if (block is WmlContentControlBlock) {
        control++;
        final path = '${context.isEmpty ? '' : '$context · '}Control $control';
        _charge(block.control.xml.length);
        _structure('$story/$path', '$label · $path', <String, Object?>{
          'After paragraph': blockOffset,
          'Alias': block.control.alias,
          'Tag': block.control.tag,
          'Control XML digest': sha256
              .convert(utf8.encode(block.control.xml))
              .toString(),
        }, section: section);
        _blocks(
          block.blocks,
          story,
          label,
          path,
          section: section,
          isBody: isBody,
          depth: depth + 1,
          bookmarkStory: bookmarkStory,
        );
      } else {
        other++;
        final path = '$story/$context/object:$other';
        if (block is WmlOpaqueBlock) {
          _opaque(
            block,
            path,
            '$label · Preserved content $other',
            section: section,
            afterParagraph: blockOffset,
          );
        } else if (block is WmlVisual) {
          _visual(
            block.visual,
            path,
            '$label · Visual $other',
            section: section,
            afterParagraph: blockOffset,
          );
        } else {
          _structure(path, '$label · Object $other', <String, Object?>{
            'After paragraph': blockOffset,
            'Type': block.runtimeType.toString(),
          }, section: section);
          warnings.add('Equation internals are outside this text report.');
        }
      }
    }
  }

  List<(int, int)> _removedRanges(String text, List<WmlRevision> pending) {
    if (pending.isEmpty) return const <(int, int)>[];
    final ordered = pending.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    var end = -1;
    var invalid = false;
    for (final revision in ordered) {
      if (revision.conflict != null ||
          revision.start < 0 ||
          revision.end < revision.start ||
          revision.end > text.length ||
          revision.start < end ||
          !_codePointBoundary(text, revision.start) ||
          !_codePointBoundary(text, revision.end) ||
          text.substring(revision.start, revision.end) != revision.text) {
        invalid = true;
        if (options.revisionView != WordComparisonRevisionView.markup) {
          throw StateError(
            'Cannot project tracked change ${revision.id}: '
            'its range, text, or overlap is unresolved. Use markup view or resolve the conflict first.',
          );
        }
      }
      end = revision.end;
    }
    if (invalid) {
      warnings.add(
        'Markup view contains unresolved tracked changes; their original/final text cannot be projected safely.',
      );
    }
    if (options.revisionView == WordComparisonRevisionView.markup) {
      return const <(int, int)>[];
    }
    final removedKind =
        options.revisionView == WordComparisonRevisionView.finalText
        ? WmlRevisionKind.delete
        : WmlRevisionKind.insert;
    return <(int, int)>[
      for (final revision in ordered)
        if (revision.kind == removedKind && revision.end > revision.start)
          (revision.start, revision.end),
    ];
  }

  void _snapshot(
    _ParagraphRecord record,
    List<(int, int)> removed,
    Map<String, int> bookmarkIds,
    Map<int, int> commentIds,
  ) {
    final paragraph = record.paragraph;
    record.properties = _paragraphProperties(paragraph.properties);
    _charge(jsonEncode(record.properties).length);
    final text = StringBuffer();
    final formatting = <_FormatSegment>[];
    final styleSet = <String>{};
    final semantic = <Object?>[];
    if (paragraph.properties.fieldInstruction != null) {
      semantic.add(<String, Object?>{
        'paragraphField': paragraph.properties.fieldInstruction,
      });
    }
    var offset = 0;
    var projectedOffset = 0;
    var removedIndex = 0;
    var opaqueIndex = 0;
    var visualIndex = 0;
    Map<String, Object?>? previousLink;
    for (final inline in paragraph.inlines) {
      if (inline is! WmlRun) previousLink = null;
      if (inline is WmlRun) {
        final runEnd = offset + inline.text.length;
        var cursor = offset;
        final runText = StringBuffer();
        while (removedIndex < removed.length &&
            removed[removedIndex].$2 <= offset) {
          removedIndex++;
        }
        var scan = removedIndex;
        while (scan < removed.length) {
          final range = removed[scan];
          if (range.$1 >= runEnd) break;
          if (range.$1 > cursor) {
            runText.write(record.rawText.substring(cursor, range.$1));
          }
          cursor = range.$2 < runEnd ? range.$2 : runEnd;
          if (range.$2 >= runEnd) break;
          scan++;
        }
        if (cursor < runEnd) {
          runText.write(record.rawText.substring(cursor, runEnd));
        }
        final retained = runText.toString();
        text.write(retained);
        if (retained.isNotEmpty) {
          final props = jsonEncode(_runProperties(inline.properties));
          _charge(props.length);
          styleSet.add(props);
          if (formatting.isNotEmpty && formatting.last.properties == props) {
            formatting.last.length += retained.length;
          } else {
            formatting.add(_FormatSegment(retained.length, props));
          }
        }
        if (retained.isNotEmpty || inline.text.isEmpty) {
          if (inline.hyperlink != null ||
              inline.fieldInstruction != null ||
              inline.noteRefId != null ||
              inline.commentIds.isNotEmpty) {
            final anchorIds =
                inline.commentIds
                    .map((id) => commentIds[id]?.toString() ?? 'unresolved:$id')
                    .toList()
                  ..sort();
            final item = <String, Object?>{
              'offset': projectedOffset,
              'length': retained.length,
              'link': inline.hyperlink?.displayTarget,
              'field': inline.fieldInstruction,
              if (inline.fieldInstruction != null) ...<String, Object?>{
                'fieldLocked': inline.fieldLocked,
                'fieldDirty': inline.fieldDirty,
              },
              'note': inline.noteRefId,
              'endnote': inline.noteRefEndnote,
              'commentAnchors': jsonEncode(anchorIds),
            };
            final mergeableLink =
                (inline.hyperlink != null || inline.commentIds.isNotEmpty) &&
                inline.fieldInstruction == null &&
                inline.noteRefId == null;
            if (mergeableLink &&
                previousLink != null &&
                previousLink['link'] == item['link'] &&
                previousLink['commentAnchors'] == item['commentAnchors'] &&
                (previousLink['offset']! as int) +
                        (previousLink['length']! as int) ==
                    projectedOffset) {
              previousLink['length'] =
                  (previousLink['length']! as int) + retained.length;
            } else {
              semantic.add(item);
              previousLink = mergeableLink ? item : null;
            }
          } else if (retained.isNotEmpty) {
            previousLink = null;
          }
          if (inline.inlineVisual != null) {
            visualIndex++;
            _visual(
              inline.inlineVisual!.visual,
              '${record.location.path}/inline:$visualIndex',
              '${record.location.label} · Inline visual',
              section: record.location.sectionIndex,
              textOffset: projectedOffset,
            );
          }
        }
        if (options.includeFormatting &&
            inline.properties.sourcePropertiesXml != null) {
          _nativePropertiesWarning();
        }
        projectedOffset += retained.length;
        offset = runEnd;
      } else if (inline is WmlBreak) {
        semantic.add(<String, Object?>{
          'offset': projectedOffset,
          'break': inline.type.name,
        });
      } else if (inline is WmlFieldBoundary) {
        semantic.add(<String, Object?>{
          'offset': projectedOffset,
          'fieldBoundary': inline.kind.name,
          'instruction': inline.text,
        });
      } else if (inline is WmlBookmarkBoundary) {
        semantic.add(<String, Object?>{
          'offset': projectedOffset,
          'bookmark': inline.name,
          'bookmarkPair': bookmarkIds[inline.id],
          'start': inline.isStart,
        });
      } else if (inline is WmlContentControlBoundary) {
        _charge(inline.control.xml.length);
        semantic.add(<String, Object?>{
          'offset': projectedOffset,
          'control': sha256.convert(utf8.encode(inline.control.xml)).toString(),
          'start': inline.start,
        });
      } else if (inline is WmlOpaqueInline) {
        opaqueIndex++;
        _opaque(
          inline.content,
          '${record.location.path}/opaque:$opaqueIndex',
          '${record.location.label} · Preserved inline content',
          section: record.location.sectionIndex,
          textOffset: projectedOffset,
        );
      } else if (inline is WmlObject) {
        semantic.add(<String, Object?>{
          'offset': projectedOffset,
          'embeddedObject': true,
          'width': inline.width,
          'height': inline.height,
        });
        warnings.add('Embedded-object payloads are outside this report.');
      } else if (inline is WmlNoteMarker) {
        semantic.add(<String, Object?>{
          'offset': projectedOffset,
          'noteMarker': true,
          'endnote': inline.endnote,
        });
      }
    }
    record.text = text.toString();
    record.runFormatting = jsonEncode(<Object?>[
      for (final segment in formatting)
        <Object?>[segment.length, segment.properties],
    ]);
    record.normalizedRunFormatting = _normalizedFormatting(
      record.text,
      formatting,
      options,
    );
    record.runStyleSet = jsonEncode(styleSet.toList()..sort());
    record.semantics = jsonEncode(semantic);
    _charge(record.semantics.length);
  }
}

bool _codePointBoundary(String text, int offset) {
  if (offset < 0 || offset > text.length) return false;
  if (offset == 0 || offset == text.length) return true;
  final before = text.codeUnitAt(offset - 1);
  final after = text.codeUnitAt(offset);
  return !(before >= 0xd800 &&
      before <= 0xdbff &&
      after >= 0xdc00 &&
      after <= 0xdfff);
}

class _FormatSegment {
  _FormatSegment(this.length, this.properties);
  int length;
  final String properties;
}

String _normalizedFormatting(
  String text,
  List<_FormatSegment> segments,
  WordComparisonOptions options,
) {
  if (!options.ignoreCase && !options.ignoreWhitespace) {
    return jsonEncode(<Object?>[
      for (final segment in segments)
        <Object?>[segment.length, segment.properties],
    ]);
  }
  final normalized = <_FormatSegment>[];
  void append(int length, String properties) {
    if (length == 0) return;
    if (normalized.isNotEmpty && normalized.last.properties == properties) {
      normalized.last.length += length;
    } else {
      normalized.add(_FormatSegment(length, properties));
    }
  }

  var offset = 0;
  var pendingSpace = false;
  for (final segment in segments) {
    final part = text.substring(offset, offset + segment.length);
    offset += segment.length;
    for (final grapheme in part.characters) {
      if (options.ignoreWhitespace && grapheme.trim().isEmpty) {
        pendingSpace = true;
        continue;
      }
      if (pendingSpace && normalized.isNotEmpty) {
        append(1, 'normalized whitespace');
      }
      pendingSpace = false;
      append(
        options.ignoreCase ? grapheme.toLowerCase().length : grapheme.length,
        segment.properties,
      );
    }
  }
  return jsonEncode(<Object?>[
    for (final segment in normalized)
      <Object?>[segment.length, segment.properties],
  ]);
}

Map<String, Object?> _paragraphProperties(WmlParagraphProps p) =>
    <String, Object?>{
      'Alignment': p.justification.name,
      'Line spacing': p.lineSpacing,
      'Line spacing rule': p.lineSpacingRule.name,
      'Before spacing': p.spacingBefore,
      'After spacing': p.spacingAfter,
      'Indent': <double>[
        p.indent.left,
        p.indent.right,
        p.indent.firstLine,
        p.indent.hanging,
      ],
      'Tabs': <Object?>[
        for (final tab in p.tabs)
          <Object?>[tab.position, tab.alignment.name, tab.leader.name],
      ],
      'Keep together': p.keepTogether,
      'Page break before': p.pageBreakBefore,
      'Column break before': p.columnBreakBefore,
      'Numbering ID': p.numId,
      'Numbering suppressed': p.numberingSuppressed,
      'List level': p.ilvl,
      'List label': p.listLabel,
      'List restart': p.listRestart,
      'Heading level': p.headingLevel,
      'Paragraph style': p.styleId,
      'Right to left': p.rightToLeft,
      'Language': p.proofingLanguage,
      'Suppress hyphenation': p.suppressAutoHyphens,
      'Drop cap lines': p.dropCapLines,
      'Shading': p.shadingFill,
      'Border color': p.borderColor,
    };

Map<String, Object?> _runProperties(WmlRunProps p) => <String, Object?>{
  'style': p.styleId,
  'bold': p.bold,
  'italic': p.italic,
  'underline': p.underline.name,
  'strike': p.strike,
  'smallCaps': p.smallCaps,
  'color': p.color,
  'highlight': p.highlight,
  'halfPointSize': p.fontSizeHalfPoints,
  'font': p.asciiFont,
  'complexScriptFont': p.csFont,
  'verticalAlignment': p.vertAlign.name,
  'language': p.proofingLanguage,
  'noProof': p.noProof,
};
