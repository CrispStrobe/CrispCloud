import 'wml_document.dart';
import 'wml_run_edit.dart';
import 'word_content_controls.dart';

/// Insert or delete tracked as a Word revision.
enum WmlRevisionKind { insert, delete }

/// One tracked change that can be accepted or rejected.
class WmlRevision {
  /// WmlRevision API.
  WmlRevision({
    required this.id,
    required this.kind,
    required this.paragraphIndex,
    required this.start,
    required this.end,
    required this.text,
    this.author = 'Quds Office',
    this.dateIso = '',
    this.accepted,
    this.targetParagraph,
    this.conflict,
  }) : _targetCaptured = targetParagraph != null;

  /// id API.
  final int id;

  /// kind API.
  final WmlRevisionKind kind;

  /// Legacy body index retained for callers that create revisions by index.
  /// Resolution captures the actual paragraph so structural edits cannot
  /// redirect the change into another paragraph or another document story.
  int paragraphIndex;

  /// Actual paragraph containing this change, including auxiliary stories.
  WmlParagraph? targetParagraph;

  bool _targetCaptured;

  /// start API.
  int start;

  /// end API.
  int end;

  /// text API.
  String text;

  /// author API.
  String author;

  /// dateIso API.
  String dateIso;

  /// `null` while pending.
  bool? accepted;

  /// Why this pending span cannot safely be resolved or exported.
  ///
  /// Edits that intersect an existing change remain editable, but attribution
  /// cannot be inferred. Undo restores the previous range and this diagnostic.
  String? conflict;
}

/// An identity-preserving history snapshot of pending changes and metadata.
class WmlRevisionSnapshot {
  WmlRevisionSnapshot._(WmlDocument document)
    : _tracking = document.trackRevisions,
      _states = <_RevisionState>[
        for (final revision in document.revisions) _RevisionState(revision),
      ];

  final bool _tracking;
  final List<_RevisionState> _states;

  /// Whether pending objects and every captured metadata value still match.
  bool matches(WmlDocument document) =>
      document.trackRevisions == _tracking &&
      document.revisions.length == _states.length &&
      _states.indexed.every(
        (entry) =>
            identical(document.revisions[entry.$1], entry.$2.revision) &&
            entry.$2.matches(),
      );

  /// Restores the original change objects as well as their mutable ranges.
  void restore(WmlDocument document) {
    document.trackRevisions = _tracking;
    document.revisions
      ..clear()
      ..addAll(_states.map((state) => state.revision));
    for (final state in _states) {
      state.restore();
    }
  }
}

class _RevisionState {
  _RevisionState(this.revision)
    : paragraphIndex = revision.paragraphIndex,
      targetParagraph = revision.targetParagraph,
      targetCaptured = revision._targetCaptured,
      start = revision.start,
      end = revision.end,
      text = revision.text,
      author = revision.author,
      dateIso = revision.dateIso,
      accepted = revision.accepted,
      conflict = revision.conflict;

  final WmlRevision revision;
  final int paragraphIndex;
  final WmlParagraph? targetParagraph;
  final bool targetCaptured;
  final int start;
  final int end;
  final String text;
  final String author;
  final String dateIso;
  final bool? accepted;
  final String? conflict;

  bool matches() =>
      revision.paragraphIndex == paragraphIndex &&
      identical(revision.targetParagraph, targetParagraph) &&
      revision._targetCaptured == targetCaptured &&
      revision.start == start &&
      revision.end == end &&
      revision.text == text &&
      revision.author == author &&
      revision.dateIso == dateIso &&
      revision.accepted == accepted &&
      revision.conflict == conflict;

  void restore() {
    revision
      ..paragraphIndex = paragraphIndex
      ..targetParagraph = targetParagraph
      .._targetCaptured = targetCaptured
      ..start = start
      ..end = end
      ..text = text
      ..author = author
      ..dateIso = dateIso
      ..accepted = accepted
      ..conflict = conflict;
  }
}

/// Track-changes helpers on [WmlDocument].
abstract final class WordRevisions {
  /// Captures changes before an editor command mutates text or structure.
  static WmlRevisionSnapshot capture(WmlDocument document) {
    for (final revision in document.revisions) {
      resolveParagraph(document, revision);
    }
    return WmlRevisionSnapshot._(document);
  }

  /// record API.
  static WmlRevision record(
    WmlDocument document, {
    required WmlRevisionKind kind,
    required int paragraphIndex,
    required int start,
    required int end,
    required String text,
    String author = 'Quds Office',
    WmlParagraph? paragraph,
  }) {
    document.trackRevisions = true;
    var id = 1;
    for (final WmlRevision revision in document.revisions) {
      if (revision.id >= id) {
        id = revision.id + 1;
      }
    }
    final WmlParagraph? target =
        paragraph ?? _bodyParagraph(document, paragraphIndex);
    // A field or note reference is indivisible. Expand a valid partial
    // request at creation, so its stored text and native bounds agree.
    if (target != null &&
        start >= 0 &&
        end >= start &&
        end <= target.text.length &&
        target.text.substring(start, end) == text) {
      final range = WmlRunEdit.normalizeRange(target, start, end);
      start = range.start;
      end = range.end;
      text = target.text.substring(start, end);
    }
    final WmlRevision revision = WmlRevision(
      id: id,
      kind: kind,
      paragraphIndex: paragraphIndex,
      start: start,
      end: end,
      text: text,
      author: author,
      dateIso: DateTime.now().toUtc().toIso8601String(),
      targetParagraph: target,
    );
    revision._targetCaptured = true;
    for (final other in document.revisions) {
      if (target != null &&
          identical(resolveParagraph(document, other), target) &&
          start < other.end &&
          other.start < end) {
        const problem =
            'Tracked changes overlap. Undo the overlapping '
            'edit before resolving or saving their attribution.';
        revision.conflict = problem;
        other.conflict ??= problem;
      }
    }
    document.revisions.add(revision);
    return revision;
  }

  /// Rebase pending ranges for one exact replacement in [paragraph].
  ///
  /// Call before changing the text, or supply [previousText] when a host has
  /// already applied its edit. Boundary insertions belong outside a pending
  /// change. Intersecting edits are retained and explicitly conflict instead
  /// of silently changing another author's span.
  static void rebaseEdit(
    WmlDocument document,
    WmlParagraph paragraph, {
    required int start,
    required int end,
    required int insertedLength,
    String? previousText,
    WmlRevision? excluding,
  }) {
    final oldText = previousText ?? paragraph.text;
    RangeError.checkValidRange(start, end, oldText.length);
    RangeError.checkNotNegative(insertedLength, 'insertedLength');
    final delta = insertedLength - (end - start);
    if (start == end && insertedLength == 0) return;
    for (final revision in document.revisions) {
      if (identical(revision, excluding) ||
          !identical(resolveParagraph(document, revision), paragraph)) {
        continue;
      }
      final problem = _textProblem(revision, oldText);
      if (problem != null) {
        revision.conflict ??= problem;
        continue;
      }
      if (end <= revision.start) {
        revision.start += delta;
        revision.end += delta;
      } else if (start < revision.end) {
        revision.conflict ??=
            'An edit intersects the pending tracked text. Undo that edit '
            'before resolving or saving this change.';
      }
    }
  }

  /// Rebase the minimal text replacement made by an external text editor.
  static void rebaseTextChange(
    WmlDocument document,
    WmlParagraph paragraph,
    String previousText,
  ) {
    final text = paragraph.text;
    if (previousText == text) return;
    var start = 0;
    while (start < previousText.length &&
        start < text.length &&
        previousText.codeUnitAt(start) == text.codeUnitAt(start)) {
      start++;
    }
    var end = previousText.length;
    var newEnd = text.length;
    while (end > start &&
        newEnd > start &&
        previousText.codeUnitAt(end - 1) == text.codeUnitAt(newEnd - 1)) {
      end--;
      newEnd--;
    }
    rebaseEdit(
      document,
      paragraph,
      start: start,
      end: end,
      insertedLength: newEnd - start,
      previousText: previousText,
    );
  }

  /// Transfer whole ranges to the tail of a paragraph before splitting it.
  static void splitParagraph(
    WmlDocument document,
    WmlParagraph paragraph,
    WmlParagraph tail,
    int offset,
  ) {
    RangeError.checkValueInInterval(offset, 0, paragraph.text.length);
    for (final revision in document.revisions) {
      if (!identical(resolveParagraph(document, revision), paragraph)) {
        continue;
      }
      final problem = _textProblem(revision, paragraph.text);
      if (problem != null) {
        revision.conflict ??= problem;
      } else if (offset <= revision.start) {
        revision
          ..targetParagraph = tail
          .._targetCaptured = true
          ..start -= offset
          ..end -= offset;
      } else if (offset < revision.end) {
        revision.conflict ??=
            'A paragraph split intersects the pending tracked text. Undo '
            'the split before resolving or saving this change.';
      }
    }
  }

  /// Transfer ranges from an appended paragraph before removing its identity.
  static void joinParagraphs(
    WmlDocument document,
    WmlParagraph first,
    WmlParagraph second,
  ) {
    final offset = first.text.length;
    for (final revision in document.revisions) {
      if (!identical(resolveParagraph(document, revision), second)) {
        continue;
      }
      final problem = _textProblem(revision, second.text);
      if (problem != null) revision.conflict ??= problem;
      revision
        ..targetParagraph = first
        .._targetCaptured = true
        ..start += offset
        ..end += offset;
    }
  }

  /// Keep a diagnostic when an edit removes a paragraph with pending changes.
  static void markDetached(WmlDocument document) {
    for (final revision in document.revisions) {
      if (resolveParagraph(document, revision) == null) {
        revision.conflict ??=
            'An edit removed its target paragraph. Undo that edit before '
            'resolving or saving this change.';
      }
    }
  }

  static String? _textProblem(WmlRevision revision, String text) {
    if (revision.conflict != null) return revision.conflict;
    if (revision.start < 0 ||
        revision.end < revision.start ||
        revision.end > text.length) {
      return 'Its recorded range no longer exists in the target paragraph.';
    }
    if (text.substring(revision.start, revision.end) != revision.text) {
      return 'Its recorded text no longer matches the target paragraph.';
    }
    return null;
  }

  /// Checks every pending change before any native package is mutated.
  ///
  /// Hosts may keep editing after an ambiguous edit. They must undo or resolve
  /// its attribution before export; emitting stale bounds would lose text.
  static void validate(WmlDocument document) {
    for (final revision in document.revisions) {
      validateRevision(document, revision);
    }
  }

  /// Verifies a change and any overlapping pending ranges before resolution.
  static void validateRevision(WmlDocument document, WmlRevision revision) {
    final paragraph = resolveParagraph(document, revision);
    final problem = paragraph == null
        ? 'Its target paragraph is no longer in the document.'
        : _textProblem(revision, paragraph.text);
    if (problem != null) {
      throw StateError(
        'Tracked change ${revision.id} cannot be resolved or '
        'saved: $problem',
      );
    }
    final range = WmlRunEdit.normalizeRange(
      paragraph!,
      revision.start,
      revision.end,
    );
    WordContentControls.assertCanEdit(paragraph, range.start, range.end);
    for (final other in document.revisions) {
      if (identical(revision, other) ||
          !identical(resolveParagraph(document, other), paragraph)) {
        continue;
      }
      if (range.start < other.end && other.start < range.end) {
        throw StateError(
          'Tracked changes ${revision.id} and ${other.id} '
          'overlap. Resolve their attribution before resolving or saving.',
        );
      }
    }
  }

  /// Finds the captured paragraph while it still belongs to the document.
  ///
  /// Older callers that construct [WmlRevision] directly bind their body index
  /// once. A detached captured paragraph never falls back to a body index.
  static WmlParagraph? resolveParagraph(
    WmlDocument document,
    WmlRevision revision,
  ) {
    if (!revision._targetCaptured && revision.targetParagraph == null) {
      revision.targetParagraph = _bodyParagraph(
        document,
        revision.paragraphIndex,
      );
    }
    revision._targetCaptured = true;
    final WmlParagraph? target = revision.targetParagraph;
    if (target == null) return null;
    for (final WmlParagraph paragraph in _allParagraphs(document)) {
      if (identical(paragraph, target)) return target;
    }
    return null;
  }

  static WmlParagraph? _bodyParagraph(WmlDocument document, int index) {
    if (index < 0) return null;
    var position = 0;
    for (final WmlParagraph paragraph in document.paragraphs) {
      if (position++ == index) return paragraph;
    }
    return null;
  }

  static Iterable<WmlParagraph> _allParagraphs(WmlDocument document) sync* {
    yield* document.paragraphs;
    for (final WmlSection section in document.sections) {
      yield* section.header;
      yield* section.footer;
      yield* section.firstHeader;
      yield* section.firstFooter;
      yield* section.evenHeader;
      yield* section.evenFooter;
    }
    for (final note in [...document.footnotes, ...document.endnotes]) {
      yield* note.allParagraphs;
    }
    for (final WmlComment comment in document.comments) {
      yield* comment.paragraphs;
    }
  }

  /// accept API.
  static void accept(WmlDocument document, WmlRevision revision) {
    _resolve(document, revision, accept: true);
  }

  /// reject API.
  static void reject(WmlDocument document, WmlRevision revision) {
    _resolve(document, revision, accept: false);
  }

  static void _resolve(
    WmlDocument document,
    WmlRevision revision, {
    required bool accept,
  }) {
    validateRevision(document, revision);
    if (accept == (revision.kind == WmlRevisionKind.delete)) {
      final paragraph = resolveParagraph(document, revision)!;
      final range = WmlRunEdit.normalizeRange(
        paragraph,
        revision.start,
        revision.end,
      );
      rebaseEdit(
        document,
        paragraph,
        start: range.start,
        end: range.end,
        insertedLength: 0,
        excluding: revision,
      );
      WmlRunEdit.replaceRange(paragraph, range.start, range.end, '');
    }
    revision.accepted = accept;
    document.revisions.remove(revision);
  }

  /// acceptAll API.
  static void acceptAll(WmlDocument document) {
    validate(document);
    for (final WmlRevision revision in List<WmlRevision>.from(
      document.revisions,
    )) {
      accept(document, revision);
    }
  }

  /// rejectAll API.
  static void rejectAll(WmlDocument document) {
    validate(document);
    for (final WmlRevision revision in List<WmlRevision>.from(
      document.revisions,
    )) {
      reject(document, revision);
    }
  }
}
