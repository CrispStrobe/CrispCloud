import 'wml_document.dart';
import 'wml_run_edit.dart';

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
}

/// Track-changes helpers on [WmlDocument].
abstract final class WordRevisions {
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
    final WmlRevision revision = WmlRevision(
      id: id,
      kind: kind,
      paragraphIndex: paragraphIndex,
      start: start,
      end: end,
      text: text,
      author: author,
      dateIso: DateTime.now().toUtc().toIso8601String(),
      targetParagraph: paragraph ?? _bodyParagraph(document, paragraphIndex),
    );
    revision._targetCaptured = true;
    document.revisions.add(revision);
    return revision;
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
    revision.accepted = true;
    if (revision.kind == WmlRevisionKind.delete) {
      final WmlParagraph? paragraph = resolveParagraph(document, revision);
      if (paragraph != null) {
        WmlRunEdit.replaceRange(paragraph, revision.start, revision.end, '');
      }
    }
    document.revisions.remove(revision);
  }

  /// reject API.
  static void reject(WmlDocument document, WmlRevision revision) {
    revision.accepted = false;
    if (revision.kind == WmlRevisionKind.insert) {
      final WmlParagraph? paragraph = resolveParagraph(document, revision);
      if (paragraph != null) {
        WmlRunEdit.replaceRange(paragraph, revision.start, revision.end, '');
      }
    }
    document.revisions.remove(revision);
  }

  /// acceptAll API.
  static void acceptAll(WmlDocument document) {
    for (final WmlRevision revision in List<WmlRevision>.from(
      document.revisions,
    )) {
      accept(document, revision);
    }
  }

  /// rejectAll API.
  static void rejectAll(WmlDocument document) {
    for (final WmlRevision revision in List<WmlRevision>.from(
      document.revisions,
    )) {
      reject(document, revision);
    }
  }
}
