part of '../crisp_ebook.dart';

/// Limits apply before ZIP inflation and again to edited/imported resources.
class EpubLimits {
  final int maxArchiveBytes;
  final int maxExpandedBytes;
  final int maxEntryBytes;
  final int maxTextBytes;
  final int maxEntries;
  final int maxXmlDepth;
  final int maxXmlNodes;

  const EpubLimits({
    this.maxArchiveBytes = 128 * 1024 * 1024,
    this.maxExpandedBytes = 256 * 1024 * 1024,
    this.maxEntryBytes = 64 * 1024 * 1024,
    this.maxTextBytes = 8 * 1024 * 1024,
    this.maxEntries = 10000,
    this.maxXmlDepth = 128,
    this.maxXmlNodes = 250000,
  });
}

class EpubException implements Exception {
  final String code;
  final String message;
  final String? path;
  const EpubException(this.code, this.message, {this.path});

  @override
  String toString() => path == null ? message : '$message ($path)';
}

enum EpubProtection { none, fontObfuscation, drm, signed }

enum EpubIssueSeverity { info, warning, error }

class EpubIssue {
  final EpubIssueSeverity severity;
  final String code;
  final String message;
  final String? path;

  const EpubIssue(this.severity, this.code, this.message, {this.path});
  bool get isError => severity == EpubIssueSeverity.error;

  @override
  String toString() =>
      '${severity.name}: $message${path == null ? '' : ' ($path)'}';
}

class EpubResource {
  final String path;
  final String mediaType;
  final int size;
  final bool isEncrypted;
  final bool isDirty;
  final String? id;
  final Set<String> properties;

  const EpubResource({
    required this.path,
    required this.mediaType,
    required this.size,
    this.isEncrypted = false,
    this.isDirty = false,
    this.id,
    this.properties = const {},
  });

  bool get isText =>
      mediaType.startsWith('text/') ||
      mediaType.endsWith('+xml') ||
      mediaType == 'application/xml' ||
      mediaType == 'application/javascript' ||
      mediaType == 'application/json';
}

class EpubChapter {
  final String id;
  final String path;
  final String title;
  final bool linear;

  const EpubChapter({
    required this.id,
    required this.path,
    required this.title,
    this.linear = true,
  });
}

class EpubTocEntry {
  final String label;

  /// An archive-relative path, optionally followed by an encoded fragment.
  final String href;
  final List<EpubTocEntry> children;

  const EpubTocEntry({
    required this.label,
    required this.href,
    this.children = const [],
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    'href': href,
    if (children.isNotEmpty)
      'children': children.map((e) => e.toJson()).toList(),
  };
}

/// A deliberately small visual editing surface. A block is editable only when
/// it contains text and line breaks, with no nested inline markup to flatten.
class EpubProseBlock {
  final int index;
  final String tag;
  final String text;
  final bool editable;
  final String? id;

  const EpubProseBlock({
    required this.index,
    required this.tag,
    required this.text,
    required this.editable,
    this.id,
  });
}

/// Recognized display hints. The original XML, including all attributes and
/// unrecognized styling, remains authoritative when a text run is corrected.
enum EpubProseMark {
  bold,
  italic,
  underline,
  strikethrough,
  code,
  link,
  superscript,
  subscript,
}

enum EpubProseSegmentKind { text, lineBreak, protectedContent }

/// One original XML text node or an opaque item between text nodes. Segment
/// indices are valid only with their block's exact resource fingerprint.
class EpubProseSegment {
  final int index;
  final String text;
  final EpubProseSegmentKind kind;
  final bool editable;
  final Set<EpubProseMark> marks;
  final String? tag;
  final String? href;

  EpubProseSegment({
    required this.index,
    required this.text,
    required this.kind,
    required this.editable,
    Set<EpubProseMark> marks = const {},
    this.tag,
    this.href,
  }) : marks = Set.unmodifiable(marks);
}

/// An immutable view of an innermost supported XHTML prose block. It never
/// carries editable XML nodes; applying edits re-resolves and checks the source.
class EpubStructuredProseBlock {
  final String resourcePath;
  final String resourceFingerprint;
  final int index;
  final String tag;
  final String? id;
  final List<EpubProseSegment> segments;

  EpubStructuredProseBlock({
    required this.resourcePath,
    required this.resourceFingerprint,
    required this.index,
    required this.tag,
    this.id,
    required List<EpubProseSegment> segments,
  }) : segments = List.unmodifiable(segments);

  bool get editable => segments.any((segment) => segment.editable);
  String get text => segments.map((segment) => segment.text).join();
}

class _ManifestItem {
  final String id;
  final String href;
  final String? resourcePath;
  final String mediaType;
  final Set<String> properties;
  final XmlElement element;

  _ManifestItem(
    this.id,
    this.href,
    this.resourcePath,
    this.mediaType,
    this.properties,
    this.element,
  );
}
