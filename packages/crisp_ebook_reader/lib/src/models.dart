import 'dart:convert';

import 'package:flutter/foundation.dart';

typedef EbookJson = Map<String, dynamic>;

/// A renderer location. CFIs belong to this exact version of a publication;
/// after editing, callers should re-anchor annotations or retain the old copy.
class EbookLocation {
  const EbookLocation({
    required this.cfi,
    required this.fraction,
    this.chapterTitle = '',
    this.sectionIndex = 0,
  });
  final String cfi;
  final double fraction;
  final String chapterTitle;
  final int sectionIndex;
  factory EbookLocation.fromJson(EbookJson json) => EbookLocation(
    cfi: json['cfi'] as String? ?? '',
    fraction: (json['fraction'] as num?)?.toDouble() ?? 0,
    chapterTitle: json['chapterTitle'] as String? ?? '',
    sectionIndex: (json['sectionIndex'] as num?)?.toInt() ?? 0,
  );
  EbookJson toJson() => {
    'cfi': cfi,
    'fraction': fraction,
    'chapterTitle': chapterTitle,
    'sectionIndex': sectionIndex,
  };
}

class EbookTocItem {
  const EbookTocItem({
    required this.label,
    required this.href,
    this.children = const [],
  });
  final String label;
  final String href;
  final List<EbookTocItem> children;
  factory EbookTocItem.fromJson(EbookJson json) => EbookTocItem(
    label: json['label'] as String? ?? '',
    href: '${json['href'] ?? ''}',
    children: (json['children'] as List? ?? const [])
        .map(
          (item) =>
              EbookTocItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );
  EbookJson toJson() => {
    'label': label,
    'href': href,
    'children': children.map((item) => item.toJson()).toList(),
  };
}

class EbookBookInfo {
  const EbookBookInfo({
    required this.title,
    required this.authors,
    required this.toc,
    required this.sectionCount,
    required this.sourceFormat,
    this.language,
    this.fixedLayout = false,
    this.warnings = const [],
  });
  final String title;
  final List<String> authors;
  final List<EbookTocItem> toc;
  final int sectionCount;
  final String sourceFormat;
  final String? language;
  final bool fixedLayout;
  final List<String> warnings;
  factory EbookBookInfo.fromJson(EbookJson json) => EbookBookInfo(
    title: json['title'] as String? ?? '',
    authors: (json['authors'] as List? ?? const []).map((e) => '$e').toList(),
    toc: (json['toc'] as List? ?? const [])
        .map(
          (item) =>
              EbookTocItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    sectionCount: (json['sectionCount'] as num?)?.toInt() ?? 0,
    sourceFormat: json['sourceFormat'] as String? ?? '',
    language: json['language'] as String?,
    fixedLayout: json['fixedLayout'] == true,
    warnings: (json['warnings'] as List? ?? const []).map((e) => '$e').toList(),
  );
}

class EbookSelection {
  const EbookSelection({
    required this.text,
    required this.cfi,
    required this.sectionIndex,
  });
  final String text;
  final String cfi;
  final int sectionIndex;
  factory EbookSelection.fromJson(EbookJson json) => EbookSelection(
    text: json['text'] as String? ?? '',
    cfi: json['cfi'] as String? ?? '',
    sectionIndex: (json['sectionIndex'] as num?)?.toInt() ?? 0,
  );
}

class EbookSearchHit {
  const EbookSearchHit({
    required this.cfi,
    required this.excerpt,
    required this.sectionIndex,
  });
  final String cfi;
  final String excerpt;
  final int sectionIndex;
  factory EbookSearchHit.fromJson(EbookJson json) => EbookSearchHit(
    cfi: json['cfi'] as String? ?? '',
    excerpt: json['excerpt'] as String? ?? '',
    sectionIndex: (json['sectionIndex'] as num?)?.toInt() ?? 0,
  );
}

class EbookAppearance {
  const EbookAppearance({
    this.fontSize = 18,
    this.lineHeight = 1.6,
    this.theme = 'light',
    this.flow = 'paginated',
    this.fontFamily = 'serif',
  });
  final double fontSize;
  final double lineHeight;

  /// light, sepia, dark. Arbitrary CSS is intentionally not a bridge argument.
  final String theme;
  final String flow;
  final String fontFamily;
  EbookJson toJson() => {
    'fontSize': fontSize.clamp(10, 48),
    'lineHeight': lineHeight.clamp(1, 2.5),
    'theme': theme,
    'flow': flow,
    'fontFamily': fontFamily,
  };
}

class EbookHighlight {
  const EbookHighlight({
    required this.id,
    required this.cfi,
    this.color = '#f9d66b',
    this.note = '',
  });
  final String id;
  final String cfi;
  final String color;
  final String note;
  EbookJson toJson() => {'id': id, 'cfi': cfi, 'color': color, 'note': note};
}

/// A converted copy, not a lossless representation of the original archive.
/// Package with the core EPUB writer; never overwrite the original using this.
class EbookImportPayload {
  EbookImportPayload.fromJson(EbookJson json) : json = Map.unmodifiable(json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported ebook import schema');
    }
  }
  final EbookJson json;
  EbookJson toJson() => Map<String, dynamic>.from(json);
  String get sourceFormat => json['sourceFormat'] as String;
  List<EbookJson> get resources => (json['resources'] as List)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  Uint8List resourceBytes(EbookJson resource) {
    if (resource['encoding'] != 'base64') {
      throw const FormatException('Unsupported ebook resource encoding');
    }
    return base64Decode(resource['data'] as String);
  }

  List<String> get warnings =>
      (json['warnings'] as List? ?? const []).map((e) => '$e').toList();
}

/// Explicit capabilities, including scope limits that the host should expose.
class EbookReaderCapabilities {
  /// Linux uses the application's Flutter chapter reader. An embedded browser
  /// runtime is deliberately not bundled by this permissively licensed package.
  static bool get supportsEmbeddedReader => kIsWeb ||
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }.contains(defaultTargetPlatform);

  static const supportedExtensions = {
    'epub',
    'mobi',
    'azw',
    'azw3',
    'fb2',
    'fbz',
    'cbz',
  };
  static const maximumInputBytes = 128 * 1024 * 1024;
  static const supportsDrm = false;
  static const supportsKfx = false;
  static const supportsOriginalMobiSave = false;
}
