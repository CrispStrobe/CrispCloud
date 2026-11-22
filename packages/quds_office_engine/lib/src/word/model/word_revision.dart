import '../../xml/namespaces.dart';
import '../serial/word_deserializer.dart';
import 'wml_document.dart';
import 'wml_run_edit.dart';
import 'word_content_controls.dart';
import 'word_tree.dart';

/// Native Word text, move and direct-formatting revisions.
enum WmlRevisionKind {
  insert,
  delete,
  moveFrom,
  moveTo,
  runFormat,
  paragraphFormat,
}

extension WmlRevisionKindSemantics on WmlRevisionKind {
  bool get isFormatting =>
      this == WmlRevisionKind.runFormat ||
      this == WmlRevisionKind.paragraphFormat;
  bool get isInsertion =>
      this == WmlRevisionKind.insert || this == WmlRevisionKind.moveTo;
  bool get isDeletion =>
      this == WmlRevisionKind.delete || this == WmlRevisionKind.moveFrom;
  bool get isMove =>
      this == WmlRevisionKind.moveFrom || this == WmlRevisionKind.moveTo;
  String get label => switch (this) {
    WmlRevisionKind.insert => 'Inserted',
    WmlRevisionKind.delete => 'Deleted',
    WmlRevisionKind.moveFrom => 'Moved from',
    WmlRevisionKind.moveTo => 'Moved to',
    WmlRevisionKind.runFormat => 'Text formatting',
    WmlRevisionKind.paragraphFormat => 'Paragraph formatting',
  };
}

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
    this.author = 'CrispOffice',
    this.dateIso = '',
    this.accepted,
    this.targetParagraph,
    this.conflict,
    this.previousPropertiesXml,
    this.propertyChangeXml,
    this.moveName,
    this.moveStory,
    this.moveStartXml,
    this.moveEndXml,
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

  /// Whether target identity was already captured, including a missing target.
  /// Read-only consumers must not redirect a captured-null target through the
  /// legacy paragraph index after later structural changes.
  bool get hasCapturedTarget => _targetCaptured;

  /// start API.
  int start;

  /// end API.
  int end;

  /// text API.
  String text;

  /// Current affected text; formatting revisions do not own text attribution.
  String get displayText {
    final paragraph = targetParagraph;
    if (paragraph == null || !kind.isFormatting) return text;
    if (kind == WmlRevisionKind.paragraphFormat) return paragraph.text;
    return paragraph.text.substring(
      start.clamp(0, paragraph.text.length),
      end.clamp(start.clamp(0, paragraph.text.length), paragraph.text.length),
    );
  }

  /// author API.
  String author;

  /// dateIso API.
  String dateIso;

  /// `null` while pending.
  bool? accepted;

  /// Complete native direct properties before a formatting revision. An empty
  /// property set means inherit, not an explicit reset to editor defaults.
  final String? previousPropertiesXml;
  final String? propertyChangeXml;

  /// Native paired move identity, scoped to the owning document part.
  final String? moveName;
  final String? moveStory;
  String? moveStartXml;
  String? moveEndXml;

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
      conflict = revision.conflict,
      moveStartXml = revision.moveStartXml,
      moveEndXml = revision.moveEndXml;

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
  final String? moveStartXml;
  final String? moveEndXml;

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
      revision.conflict == conflict &&
      revision.moveStartXml == moveStartXml &&
      revision.moveEndXml == moveEndXml;

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
      ..conflict = conflict
      ..moveStartXml = moveStartXml
      ..moveEndXml = moveEndXml;
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
    String author = 'CrispOffice',
    WmlParagraph? paragraph,
    bool preserveSourceRange = false,
    String? previousPropertiesXml,
    String? propertyChangeXml,
    String? moveName,
    String? moveStory,
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
    if (!preserveSourceRange &&
        target != null &&
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
      previousPropertiesXml: previousPropertiesXml,
      propertyChangeXml: propertyChangeXml,
      moveName: moveName,
      moveStory: moveStory,
    );
    revision._targetCaptured = true;
    for (final other in document.revisions) {
      // Only a revision on the same paragraph can overlap. Checking the
      // captured target first avoids resolveParagraph's whole-document
      // attachment scan for every other revision, which made importing
      // documents with many tracked changes quadratic (minutes for a few
      // hundred revisions). The result is unchanged: a different captured
      // target can never resolve to [target].
      if (kind == other.kind && kind.isFormatting ||
          !kind.isFormatting && !other.kind.isFormatting) {
        if (target != null &&
            !(other._targetCaptured &&
                !identical(other.targetParagraph, target)) &&
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
    for (final revision in document.revisions.toList()) {
      if (identical(revision, excluding) ||
          !identical(resolveParagraph(document, revision), paragraph)) {
        continue;
      }
      if (revision.kind == WmlRevisionKind.paragraphFormat) {
        revision.start = 0;
        revision.end = oldText.length + delta;
        continue;
      }
      if (revision.kind == WmlRevisionKind.runFormat &&
          revision.conflict == null) {
        final from = revision.start;
        final to = revision.end;
        revision.start = from < start
            ? from
            : from >= end
            ? from + delta
            : start;
        revision.end = to <= start
            ? to
            : to >= end
            ? to + delta
            : start + insertedLength;
        if (revision.end <= revision.start) document.revisions.remove(revision);
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
    if (!revision.kind.isFormatting &&
        text.substring(revision.start, revision.end) != revision.text) {
      return 'Its recorded text no longer matches the target paragraph.';
    }
    return null;
  }

  /// Checks every pending change before any native package is mutated.
  ///
  /// Hosts may keep editing after an ambiguous edit. They must undo or resolve
  /// its attribution before export; emitting stale bounds would lose text.
  static void validate(WmlDocument document) {
    // Resolve every revision once against one attachment set: validating
    // pairwise with resolveParagraph rescanned the whole document per pair
    // (minutes to save a document with a few hundred tracked changes).
    final attached = Set<WmlParagraph>.identity()
      ..addAll(_allParagraphs(document));
    final resolved = Map<WmlRevision, WmlParagraph?>.identity();
    for (final revision in document.revisions) {
      resolved[revision] = _resolveIn(document, revision, attached);
    }
    for (final revision in document.revisions) {
      validateRevision(document, revision, resolved: resolved, forExport: true);
    }
  }

  /// Verifies a change and any overlapping pending ranges before resolution.
  ///
  /// [resolved] may carry precomputed targets (see [validate]).
  static void validateRevision(
    WmlDocument document,
    WmlRevision revision, {
    Map<WmlRevision, WmlParagraph?>? resolved,
    bool forExport = false,
  }) {
    WmlParagraph? targetOf(WmlRevision r) =>
        resolved != null ? resolved[r] : resolveParagraph(document, r);
    if (revision.accepted != null) {
      throw StateError('The tracked change is no longer pending.');
    }
    if (revision.kind.isFormatting && revision.previousPropertiesXml == null) {
      throw StateError('The previous formatting is missing.');
    }
    if (revision.kind.isMove) {
      final group = related(document, revision);
      for (final kind in [WmlRevisionKind.moveFrom, WmlRevisionKind.moveTo]) {
        final side = group.where((r) => r.kind == kind).toList();
        if (revision.moveName == null ||
            side.isEmpty ||
            side.where((r) => r.moveStartXml != null).length != 1 ||
            side.where((r) => r.moveEndXml != null).length != 1) {
          throw StateError('The move source/destination range is incomplete.');
        }
      }
    }
    final paragraph = targetOf(revision);
    final problem = paragraph == null
        ? 'Its target paragraph is no longer in the document.'
        : _textProblem(revision, paragraph.text);
    if (problem != null) {
      throw StateError(
        'Tracked change ${revision.id} cannot be resolved or '
        'saved: $problem',
      );
    }
    if (revision.kind == WmlRevisionKind.runFormat &&
        revision.start == revision.end) {
      var offset = 0;
      var emptyRuns = 0;
      for (final run in paragraph!.inlines.whereType<WmlRun>()) {
        if (offset == revision.start && run.text.isEmpty) {
          emptyRuns++;
        }
        offset += run.text.length;
      }
      if (emptyRuns != 1) {
        throw StateError(
          'The empty formatting run no longer has an unambiguous target.',
        );
      }
    }
    final range = WmlRunEdit.normalizeRange(
      paragraph!,
      revision.kind == WmlRevisionKind.paragraphFormat ? 0 : revision.start,
      revision.kind == WmlRevisionKind.paragraphFormat
          ? paragraph.text.length
          : revision.end,
      // Native tracked caches may legitimately have several independent
      // revision ranges inside one complex citation. Export preserves those
      // exact ranges; resolving a revision still uses whole-field edit bounds.
      protectZoteroCitations: !forExport,
    );
    WordContentControls.assertCanEdit(paragraph, range.start, range.end);
    if (!forExport) {
      void check(WmlContentControlData control) {
        final lock = WordContentControls.template(control)
            .firstChild('sdtPr', namespaceUri: OfficeNamespaces.w)
            ?.firstChild('lock', namespaceUri: OfficeNamespaces.w)
            ?.getAttribute('val', namespaceUri: OfficeNamespaces.w);
        if (lock == 'contentLocked' || lock == 'sdtContentLocked') {
          throw StateError(
            'This tracked change is inside a locked content control.',
          );
        }
      }

      for (final control in paragraph.contentControlWrappers) {
        check(control);
      }
      for (final span in WordContentControls.spans(paragraph)) {
        if (range.start < span.end && span.start < range.end ||
            range.start == range.end &&
                span.start <= range.start &&
                range.start <= span.end) {
          check(span.control);
        }
      }
      for (final blocks in [
        for (final section in document.sections) section.blocks,
        for (final note in [...document.footnotes, ...document.endnotes])
          note.blocks,
      ]) {
        for (final block in WordTree.descendants(
          blocks,
        ).whereType<WmlContentControlBlock>()) {
          if (WordTree.paragraphs(
            block.blocks,
          ).any((p) => identical(p, paragraph))) {
            check(block.control);
          }
        }
      }
    }
    for (final other in document.revisions) {
      if (identical(revision, other) ||
          (revision.kind.isFormatting != other.kind.isFormatting) ||
          (revision.kind.isFormatting && revision.kind != other.kind) ||
          !identical(targetOf(other), paragraph)) {
        continue;
      }
      if (range.start < other.end && other.start < range.end ||
          revision.kind == WmlRevisionKind.runFormat &&
              revision.start == revision.end &&
              other.start == other.end &&
              revision.start == other.start) {
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

  /// [resolveParagraph] with a precomputed attachment set.
  static WmlParagraph? _resolveIn(
    WmlDocument document,
    WmlRevision revision,
    Set<WmlParagraph> attached,
  ) {
    if (!revision._targetCaptured && revision.targetParagraph == null) {
      revision.targetParagraph = _bodyParagraph(
        document,
        revision.paragraphIndex,
      );
    }
    revision._targetCaptured = true;
    final WmlParagraph? target = revision.targetParagraph;
    return target != null && attached.contains(target) ? target : null;
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
    final group = related(document, revision);
    // A paired move is one transaction. Preflight every source/destination
    // (including locked controls) before removing either side.
    for (final item in group) {
      validateRevision(document, item);
    }
    group.sort((a, b) => b.start.compareTo(a.start));
    for (final item in group) {
      if (!document.revisions.contains(item) && !identical(item, revision)) {
        continue;
      }
      if (item.kind.isFormatting) {
        if (!accept) {
          WordDeserializer().restoreRevisionFormatting(document, item);
        } else if (item.kind == WmlRevisionKind.runFormat &&
            item.start == item.end) {
          // validateRevision proved this zero-width revision has exactly one
          // empty run. Its paragraph-only source guard ends with acceptance;
          // the full revision history remains solely in the revision model.
          final paragraph = resolveParagraph(document, item)!;
          var offset = 0;
          for (final run in paragraph.inlines.whereType<WmlRun>()) {
            if (offset == item.start && run.text.isEmpty) {
              run.properties.hasEmptyFormattingRevision = false;
            }
            offset += run.text.length;
          }
        }
      } else if (accept == item.kind.isDeletion) {
        final paragraph = resolveParagraph(document, item)!;
        final range = WmlRunEdit.normalizeRange(
          paragraph,
          item.start,
          item.end,
        );
        // Formatting over removed text has no remaining subject. Formatting
        // crossing a deletion keeps the surviving part and its attribution.
        final formats = document.revisions
            .where(
              (other) =>
                  other.kind == WmlRevisionKind.runFormat &&
                  identical(resolveParagraph(document, other), paragraph),
            )
            .toList();
        for (final other in formats) {
          document.revisions.remove(other);
        }
        rebaseEdit(
          document,
          paragraph,
          start: range.start,
          end: range.end,
          insertedLength: 0,
          excluding: item,
        );
        WmlRunEdit.replaceRange(paragraph, range.start, range.end, '');
        final removed = range.end - range.start;
        for (final other in formats) {
          int shifted(int at) => at <= range.start
              ? at
              : at >= range.end
              ? at - removed
              : range.start;
          other.start = shifted(other.start);
          other.end = shifted(other.end);
          if (other.end > other.start) {
            other.text = paragraph.text.substring(other.start, other.end);
            document.revisions.add(other);
          }
        }
      }
      item.accepted = accept;
      document.revisions.remove(item);
    }
  }

  /// Both sides (and every paragraph fragment) of a named native move.
  static List<WmlRevision> related(
    WmlDocument document,
    WmlRevision revision,
  ) => revision.kind.isMove && revision.moveName != null
      ? document.revisions
            .where(
              (r) =>
                  r.kind.isMove &&
                  r.moveName == revision.moveName &&
                  r.moveStory == revision.moveStory,
            )
            .toList()
      : [revision];

  /// acceptAll API.
  static void acceptAll(WmlDocument document) {
    validate(document);
    for (final WmlRevision revision in List<WmlRevision>.from(
      document.revisions,
    )) {
      if (document.revisions.contains(revision)) accept(document, revision);
    }
  }

  /// rejectAll API.
  static void rejectAll(WmlDocument document) {
    validate(document);
    for (final WmlRevision revision in List<WmlRevision>.from(
      document.revisions,
    )) {
      if (document.revisions.contains(revision)) reject(document, revision);
    }
  }
}
