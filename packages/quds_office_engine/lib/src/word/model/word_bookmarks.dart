import 'wml_document.dart';

/// A native bookmark endpoint at an exact text boundary. Bookmarks may overlap
/// and span paragraphs; their source IDs and endpoint order remain independent
/// of the paragraph-wide bookmarks generated for newly created headings.
sealed class WmlBookmarkMarker extends WmlZeroWidthInline {
  WmlBookmarkMarker({required this.id, this.sourceXml});

  final String id;

  /// Self-contained original markup, including optional column/displacement
  /// attributes. Null denotes a newly created marker.
  final String? sourceXml;
}

final class WmlBookmarkStart extends WmlBookmarkMarker {
  WmlBookmarkStart({required super.id, required this.name, super.sourceXml});

  final String name;

  @override
  bool get isStart => true;

  @override
  WmlBookmarkStart copy() =>
      WmlBookmarkStart(id: id, name: name, sourceXml: sourceXml);
}

final class WmlBookmarkEnd extends WmlBookmarkMarker {
  WmlBookmarkEnd({required super.id, super.sourceXml});

  @override
  bool get isStart => false;

  @override
  WmlBookmarkEnd copy() => WmlBookmarkEnd(id: id, sourceXml: sourceXml);
}
