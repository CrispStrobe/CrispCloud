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
  });

  /// id API.
  final int id;

  /// kind API.
  final WmlRevisionKind kind;

  /// paragraphIndex API.
  int paragraphIndex;

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
    );
    document.revisions.add(revision);
    return revision;
  }

  /// accept API.
  static void accept(WmlDocument document, WmlRevision revision) {
    revision.accepted = true;
    if (revision.kind == WmlRevisionKind.delete) {
      final List<WmlParagraph> paras = document.paragraphs.toList();
      if (revision.paragraphIndex >= 0 &&
          revision.paragraphIndex < paras.length) {
        WmlRunEdit.replaceRange(
          paras[revision.paragraphIndex],
          revision.start,
          revision.end,
          '',
        );
      }
    }
    document.revisions.remove(revision);
  }

  /// reject API.
  static void reject(WmlDocument document, WmlRevision revision) {
    revision.accepted = false;
    if (revision.kind == WmlRevisionKind.insert) {
      final List<WmlParagraph> paras = document.paragraphs.toList();
      if (revision.paragraphIndex >= 0 &&
          revision.paragraphIndex < paras.length) {
        WmlRunEdit.replaceRange(
          paras[revision.paragraphIndex],
          revision.start,
          revision.end,
          '',
        );
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
