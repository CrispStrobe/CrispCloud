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
    this.supportsProgressSeeking = true,
    this.supportsNavigationHistory = false,
    bool supportsTextAppearance = true,
    bool supportsLayout = true,
    bool supportsPublisherStyles = true,
  })  : _supportsTextAppearance = supportsTextAppearance,
        _supportsLayout = supportsLayout,
        _supportsPublisherStyles = supportsPublisherStyles;
  final String title;
  final List<String> authors;
  final List<EbookTocItem> toc;
  final int sectionCount;
  final String sourceFormat;
  final String? language;
  final bool fixedLayout;
  final List<String> warnings;
  final bool supportsProgressSeeking;
  final bool supportsNavigationHistory;
  final bool _supportsTextAppearance;
  final bool _supportsLayout;
  final bool _supportsPublisherStyles;

  /// Fixed-layout pages retain their publisher-defined typography and layout.
  bool get supportsTextAppearance => !fixedLayout && _supportsTextAppearance;
  bool get supportsLayout => !fixedLayout && _supportsLayout;
  bool get supportsPublisherStyles => !fixedLayout && _supportsPublisherStyles;
  factory EbookBookInfo.fromJson(EbookJson json) => EbookBookInfo(
        title: json['title'] as String? ?? '',
        authors:
            (json['authors'] as List? ?? const []).map((e) => '$e').toList(),
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
        warnings:
            (json['warnings'] as List? ?? const []).map((e) => '$e').toList(),
        supportsProgressSeeking: json['supportsProgressSeeking'] != false,
        supportsNavigationHistory: json['supportsNavigationHistory'] == true,
        supportsTextAppearance: json['supportsTextAppearance'] != false,
        supportsLayout: json['supportsLayout'] != false,
        supportsPublisherStyles: json['supportsPublisherStyles'] != false,
      );
}

/// The renderer's actual navigation stack, separate from previous/next pages.
/// The pinned engine exposes this session state but no stack snapshot API.
class EbookNavigationHistory {
  const EbookNavigationHistory({
    this.canGoBack = false,
    this.canGoForward = false,
  });

  final bool canGoBack;
  final bool canGoForward;

  factory EbookNavigationHistory.fromJson(EbookJson json) =>
      EbookNavigationHistory(
        canGoBack: json['canGoBack'] == true,
        canGoForward: json['canGoForward'] == true,
      );

  EbookJson toJson() => {
        'canGoBack': canGoBack,
        'canGoForward': canGoForward,
      };
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
    this.maxColumnCount = 2,
    this.pageMargin = 24,
    this.pageWidth = 780,
    this.usePublisherStyles = true,
  });
  final double fontSize;
  final double lineHeight;

  /// light, sepia, dark. Arbitrary CSS is intentionally not a bridge argument.
  final String theme;
  final String flow;
  final String fontFamily;

  /// An upper bound; narrow and portrait viewports can use fewer columns.
  final int maxColumnCount;

  /// Outer margin along the text's block axis, in CSS pixels.
  final double pageMargin;

  /// Maximum inline width of one text column, in CSS pixels.
  final double pageWidth;

  /// Honor publication fonts and spacing. Disabling this applies reader
  /// typography overrides without removing publication nodes or stylesheets.
  final bool usePublisherStyles;

  static double _number(
    Object? value,
    double fallback,
    double minimum,
    double maximum,
  ) =>
      value is num && value.isFinite
          ? value.toDouble().clamp(minimum, maximum)
          : fallback;

  factory EbookAppearance.fromJson(EbookJson json) => EbookAppearance(
        fontSize: _number(json['fontSize'], 18, 10, 48),
        lineHeight: _number(json['lineHeight'], 1.6, 1, 2.5),
        theme: json['theme'] is String ? json['theme'] as String : 'light',
        flow: json['flow'] is String ? json['flow'] as String : 'paginated',
        fontFamily: json['fontFamily'] is String
            ? json['fontFamily'] as String
            : 'serif',
        maxColumnCount: _number(json['maxColumnCount'], 2, 1, 3).toInt(),
        pageMargin: _number(json['pageMargin'], 24, 0, 96),
        pageWidth: _number(json['pageWidth'], 780, 320, 1600),
        usePublisherStyles: json['usePublisherStyles'] is bool
            ? json['usePublisherStyles'] as bool
            : true,
      ).normalized;

  EbookAppearance get normalized => EbookAppearance(
        fontSize: _number(fontSize, 18, 10, 48),
        lineHeight: _number(lineHeight, 1.6, 1, 2.5),
        theme:
            const {'light', 'sepia', 'dark'}.contains(theme) ? theme : 'light',
        flow: flow == 'scrolled' ? 'scrolled' : 'paginated',
        fontFamily:
            const {'serif', 'sans-serif', 'monospace'}.contains(fontFamily)
                ? fontFamily
                : 'serif',
        maxColumnCount: maxColumnCount.clamp(1, 3),
        pageMargin: _number(pageMargin, 24, 0, 96),
        pageWidth: _number(pageWidth, 780, 320, 1600),
        usePublisherStyles: usePublisherStyles,
      );

  EbookAppearance copyWith({
    double? fontSize,
    double? lineHeight,
    String? theme,
    String? flow,
    String? fontFamily,
    int? maxColumnCount,
    double? pageMargin,
    double? pageWidth,
    bool? usePublisherStyles,
  }) =>
      EbookAppearance(
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        theme: theme ?? this.theme,
        flow: flow ?? this.flow,
        fontFamily: fontFamily ?? this.fontFamily,
        maxColumnCount: maxColumnCount ?? this.maxColumnCount,
        pageMargin: pageMargin ?? this.pageMargin,
        pageWidth: pageWidth ?? this.pageWidth,
        usePublisherStyles: usePublisherStyles ?? this.usePublisherStyles,
      ).normalized;

  EbookJson toJson() {
    final value = normalized;
    return {
      'fontSize': value.fontSize,
      'lineHeight': value.lineHeight,
      'theme': value.theme,
      'flow': value.flow,
      'fontFamily': value.fontFamily,
      'maxColumnCount': value.maxColumnCount,
      'pageMargin': value.pageMargin,
      'pageWidth': value.pageWidth,
      'usePublisherStyles': value.usePublisherStyles,
    };
  }
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
  /// Platforms with an immediately available embedded-browser integration.
  /// Linux requires a separate runtime probe and otherwise uses the chapter
  /// reader; this synchronous flag does not replace that probe's result.
  static bool get supportsEmbeddedReader =>
      kIsWeb ||
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
