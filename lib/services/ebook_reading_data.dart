import 'dart:convert';

import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:crypto/crypto.dart';

/// Locator formats are deliberately distinct even for the same publication.
enum EbookReaderRenderer {
  foliate('foliate-v1'),
  portable('portable-v1');

  const EbookReaderRenderer(this.wireName);
  final String wireName;
}

enum EbookReadingDataMergeMode {
  mergeKeepExisting,
  mergePreferImported,
  replace,
}

enum EbookReadingDataError {
  invalid,
  tooLarge,
  unsupportedVersion,
  contentMismatch,
  rendererMismatch,
  stale,
  limitExceeded,
  writeFailed,
}

class EbookReadingDataException implements Exception {
  const EbookReadingDataException(this.code, this.message);
  final EbookReadingDataError code;
  final String message;
  @override
  String toString() => message;
}

/// A portable sidecar contains no account, path, credential or file-access grant.
/// Every locator belongs to one exact publication and one renderer contract.
class EbookReadingData {
  EbookReadingData._({
    required this.contentSha256,
    required this.contentByteLength,
    required this.renderer,
    required this.location,
    required this.appearance,
    required List<EbookLocation> bookmarks,
    required List<EbookHighlight> highlights,
  }) : bookmarks = List.unmodifiable(bookmarks),
       highlights = List.unmodifiable(highlights);

  static const format = 'crispcloud-ebook-reading-data';
  static const version = 1;
  static const maximumJsonBytes = 2 * 1024 * 1024;
  static const maximumItems = 500;
  static const maximumBookBytes = 128 * 1024 * 1024;
  final String contentSha256;
  final int contentByteLength;
  final EbookReaderRenderer renderer;
  final EbookLocation? location;
  final EbookAppearance appearance;
  final List<EbookLocation> bookmarks;
  final List<EbookHighlight> highlights;

  factory EbookReadingData.capture({
    required String contentSha256,
    required int contentByteLength,
    required EbookReaderRenderer renderer,
    EbookLocation? location,
    required EbookAppearance appearance,
    required Iterable<EbookLocation> bookmarks,
    required Iterable<EbookHighlight> highlights,
  }) => EbookReadingData.fromJson({
    'format': format,
    'version': version,
    'publication': {'sha256': contentSha256, 'byteLength': contentByteLength},
    'renderer': renderer.wireName,
    'location': location?.toJson(),
    'appearance': appearance.toJson(),
    'bookmarks': bookmarks
        .take(maximumItems + 1)
        .map((item) => item.toJson())
        .toList(),
    'highlights': highlights
        .take(maximumItems + 1)
        .map((item) => item.toJson())
        .toList(),
  });

  factory EbookReadingData.decode(String encoded) {
    checkEbookJsonBounds(encoded, maximumBytes: maximumJsonBytes);
    Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      throw const EbookReadingDataException(
        EbookReadingDataError.invalid,
        'The reading-data file is not valid JSON.',
      );
    }
    return EbookReadingData.fromJson(_map(decoded, 'reading data'));
  }

  factory EbookReadingData.fromJson(Map<String, dynamic> json) {
    if (json['format'] != format || json['version'] != version) {
      throw const EbookReadingDataException(
        EbookReadingDataError.unsupportedVersion,
        'This reading-data format or version is not supported.',
      );
    }
    _keys(json, const {
      'format',
      'version',
      'publication',
      'renderer',
      'location',
      'appearance',
      'bookmarks',
      'highlights',
    });
    final publication = _map(json['publication'], 'publication');
    _keys(publication, const {'sha256', 'byteLength'});
    final hash = publication['sha256'];
    final length = publication['byteLength'];
    if (hash is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        length is! int ||
        length < 0 ||
        length > maximumBookBytes) {
      _invalid('The publication identity is invalid.');
    }
    final renderer = EbookReaderRenderer.values
        .where((item) => item.wireName == json['renderer'])
        .firstOrNull;
    if (renderer == null) {
      throw const EbookReadingDataException(
        EbookReadingDataError.rendererMismatch,
        'This reading-data renderer is not supported.',
      );
    }
    final rawBookmarks = _items(json['bookmarks'], 'bookmarks');
    final rawHighlights = _items(json['highlights'], 'highlights');
    if (renderer == EbookReaderRenderer.portable && rawHighlights.isNotEmpty) {
      _invalid('The portable renderer does not support highlight locators.');
    }
    final bookmarks = <EbookLocation>[];
    final bookmarkIds = <String>{};
    for (final value in rawBookmarks) {
      final item = _location(value, renderer);
      if (!bookmarkIds.add(item.cfi)) _invalid('Duplicate bookmark locator.');
      bookmarks.add(item);
    }
    final highlights = <EbookHighlight>[];
    final highlightIds = <String>{};
    for (final value in rawHighlights) {
      final item = _map(value, 'highlight');
      _keys(item, const {'id', 'cfi', 'color', 'note'});
      final id = _string(item['id'], 'highlight ID', 256);
      if (id.isEmpty || !highlightIds.add(id)) {
        _invalid('Duplicate or empty highlight ID.');
      }
      final cfi = _locator(item['cfi'], renderer);
      final color = _string(item['color'], 'highlight color', 7);
      if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
        _invalid('Invalid highlight color.');
      }
      highlights.add(
        EbookHighlight(
          id: id,
          cfi: cfi,
          color: color.toLowerCase(),
          note: _string(item['note'], 'note', 16384, multiline: true),
        ),
      );
    }
    bookmarks.sort((a, b) => a.cfi.compareTo(b.cfi));
    highlights.sort((a, b) => a.id.compareTo(b.id));
    final result = EbookReadingData._(
      contentSha256: hash,
      contentByteLength: length,
      renderer: renderer,
      location: json['location'] == null
          ? null
          : _location(json['location'], renderer),
      appearance: _appearance(json['appearance']),
      bookmarks: bookmarks,
      highlights: highlights,
    );
    if (utf8.encode(jsonEncode(result.toJson())).length > maximumJsonBytes) {
      throw const EbookReadingDataException(
        EbookReadingDataError.tooLarge,
        'The reading-data file exceeds the 2 MiB limit.',
      );
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
    'format': format,
    'version': version,
    'publication': {'sha256': contentSha256, 'byteLength': contentByteLength},
    'renderer': renderer.wireName,
    'location': location?.toJson(),
    'appearance': appearance.toJson(),
    'bookmarks': bookmarks.map((item) => item.toJson()).toList(),
    'highlights': highlights.map((item) => item.toJson()).toList(),
  };

  String encode() {
    final result = const JsonEncoder.withIndent('  ').convert(toJson());
    checkEbookJsonBounds(result, maximumBytes: maximumJsonBytes);
    return result;
  }

  String get fingerprint =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();
  int get noteCount => highlights.where((item) => item.note.isNotEmpty).length;

  void requireCompatible(EbookReadingData other) {
    if (contentSha256 != other.contentSha256 ||
        contentByteLength != other.contentByteLength) {
      throw const EbookReadingDataException(
        EbookReadingDataError.contentMismatch,
        'The reading data belongs to different book bytes. Open the exact book version.',
      );
    }
    if (renderer != other.renderer) {
      throw const EbookReadingDataException(
        EbookReadingDataError.rendererMismatch,
        'The reading data uses a different reader. Its locations cannot be converted safely.',
      );
    }
  }
}

/// An immutable, reviewable merge. Repeated imports have deterministic results.
/// Bookmark conflicts use the locator; highlight conflicts use their stable ID.
class EbookReadingDataImportPlan {
  EbookReadingDataImportPlan._({
    required this.bindingKey,
    required this.localFingerprint,
    required this.mode,
    required this.imported,
    required this.result,
    required this.bookmarkConflicts,
    required this.highlightConflicts,
    required this.addedBookmarks,
    required this.addedHighlights,
    required this.progressChanged,
    required this.appearanceChanged,
  });
  final String bindingKey;
  final String localFingerprint;
  final EbookReadingDataMergeMode mode;
  final EbookReadingData imported;
  final EbookReadingData result;
  final int bookmarkConflicts;
  final int highlightConflicts;
  final int addedBookmarks;
  final int addedHighlights;
  final bool progressChanged;
  final bool appearanceChanged;
  int get conflictCount => bookmarkConflicts + highlightConflicts;
  bool get hasChanges => result.fingerprint != localFingerprint;

  factory EbookReadingDataImportPlan.prepare({
    required String bindingKey,
    required EbookReadingData local,
    required EbookReadingData imported,
    EbookReadingDataMergeMode mode =
        EbookReadingDataMergeMode.mergeKeepExisting,
  }) {
    local.requireCompatible(imported);
    final bookmarks = {for (final item in local.bookmarks) item.cfi: item};
    final highlights = {for (final item in local.highlights) item.id: item};
    var bookmarkConflicts = 0;
    var highlightConflicts = 0;
    var addedBookmarks = 0;
    var addedHighlights = 0;
    for (final item in imported.bookmarks) {
      final old = bookmarks[item.cfi];
      if (old == null) {
        addedBookmarks++;
      } else if (jsonEncode(old.toJson()) != jsonEncode(item.toJson())) {
        bookmarkConflicts++;
      }
      if (old == null || mode != EbookReadingDataMergeMode.mergeKeepExisting) {
        bookmarks[item.cfi] = item;
      }
    }
    for (final item in imported.highlights) {
      final old = highlights[item.id];
      if (old == null) {
        addedHighlights++;
      } else if (jsonEncode(old.toJson()) != jsonEncode(item.toJson())) {
        highlightConflicts++;
      }
      if (old == null || mode != EbookReadingDataMergeMode.mergeKeepExisting) {
        highlights[item.id] = item;
      }
    }
    final preferLocal = mode == EbookReadingDataMergeMode.mergeKeepExisting;
    final result = mode == EbookReadingDataMergeMode.replace
        ? imported
        : EbookReadingData.capture(
            contentSha256: local.contentSha256,
            contentByteLength: local.contentByteLength,
            renderer: local.renderer,
            location: preferLocal
                ? local.location ?? imported.location
                : imported.location ?? local.location,
            appearance: preferLocal ? local.appearance : imported.appearance,
            bookmarks: bookmarks.values,
            highlights: highlights.values,
          );
    return EbookReadingDataImportPlan._(
      bindingKey: bindingKey,
      localFingerprint: local.fingerprint,
      mode: mode,
      imported: imported,
      result: result,
      bookmarkConflicts: bookmarkConflicts,
      highlightConflicts: highlightConflicts,
      addedBookmarks: addedBookmarks,
      addedHighlights: addedHighlights,
      progressChanged:
          jsonEncode(local.location?.toJson()) !=
          jsonEncode(result.location?.toJson()),
      appearanceChanged:
          jsonEncode(local.appearance.toJson()) !=
          jsonEncode(result.appearance.toJson()),
    );
  }
}

/// Check the byte and nesting budget before JSON decoding can allocate a tree.
void checkEbookJsonBounds(String encoded, {required int maximumBytes}) {
  if (encoded.length > maximumBytes ||
      utf8.encode(encoded).length > maximumBytes) {
    throw const EbookReadingDataException(
      EbookReadingDataError.tooLarge,
      'The reading-data size limit was exceeded.',
    );
  }
  var depth = 0;
  var quoted = false;
  var escaped = false;
  for (final unit in encoded.codeUnits) {
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (unit == 92) {
        escaped = true;
      } else if (unit == 34) {
        quoted = false;
      }
    } else if (unit == 34) {
      quoted = true;
    } else if (unit == 91 || unit == 123) {
      if (++depth > 16) _invalid('The JSON nesting limit was exceeded.');
    } else if (unit == 93 || unit == 125) {
      if (--depth < 0) _invalid('The JSON structure is invalid.');
    }
  }
  if (quoted || depth != 0) _invalid('The JSON structure is invalid.');
}

Map<String, dynamic> _map(Object? value, String field) {
  if (value is! Map<String, dynamic>) _invalid('Invalid $field object.');
  return value;
}

void _keys(Map<String, dynamic> value, Set<String> expected) {
  if (value.keys.any((key) => !expected.contains(key)) ||
      expected.any((key) => !value.containsKey(key))) {
    _invalid('Missing or unsupported reading-data fields.');
  }
}

List<dynamic> _items(Object? value, String name) {
  if (value is! List) _invalid('Invalid $name list.');
  final items = value;
  if (items.length > EbookReadingData.maximumItems) {
    throw const EbookReadingDataException(
      EbookReadingDataError.limitExceeded,
      'A book can contain at most 500 bookmarks and 500 highlights.',
    );
  }
  return items;
}

String _string(
  Object? value,
  String field,
  int maximum, {
  bool multiline = false,
}) {
  if (value is! String || value.length > maximum) _invalid('Invalid $field.');
  final text = value;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit < 32 && !(multiline && const {9, 10, 13}.contains(unit)) ||
        unit == 127) {
      _invalid('Invalid control character in $field.');
    }
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= text.length ||
          text.codeUnitAt(i) < 0xdc00 ||
          text.codeUnitAt(i) > 0xdfff) {
        _invalid('Invalid Unicode in $field.');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      _invalid('Invalid Unicode in $field.');
    }
  }
  return text;
}

EbookLocation _location(Object? value, EbookReaderRenderer renderer) {
  final json = _map(value, 'location');
  _keys(json, const {'cfi', 'fraction', 'chapterTitle', 'sectionIndex'});
  final fraction = json['fraction'];
  final section = json['sectionIndex'];
  if (fraction is! num ||
      !fraction.isFinite ||
      fraction < 0 ||
      fraction > 1 ||
      section is! int ||
      section < 0 ||
      section > 100000) {
    _invalid('Invalid reading progress.');
  }
  return EbookLocation(
    cfi: _locator(json['cfi'], renderer),
    fraction: fraction.toDouble(),
    chapterTitle: _string(json['chapterTitle'], 'chapter title', 1024),
    sectionIndex: section,
  );
}

String _locator(Object? value, EbookReaderRenderer renderer) {
  final cfi = _string(value, 'reading location', 16384);
  if (renderer == EbookReaderRenderer.foliate) {
    if (!cfi.startsWith('epubcfi(') || !cfi.endsWith(')') || cfi.length < 11) {
      _invalid('This location is not a Foliate EPUB CFI.');
    }
    // CFI escapes apply to assertion text; reject extra unescaped envelopes.
    var escaped = false;
    for (var i = 8; i < cfi.length - 1; i++) {
      if (escaped) {
        escaped = false;
      } else if (cfi[i] == '^') {
        escaped = true;
      } else if (cfi[i] == '(' || cfi[i] == ')') {
        _invalid('The CFI envelope is invalid.');
      }
    }
    if (escaped || !cfi.substring(8).startsWith('/')) {
      _invalid('The CFI is invalid.');
    }
  } else {
    const prefix = 'crisp-reader:v1:';
    if (RegExp(r'^crisp-section:(0|[1-9][0-9]{0,4})$').hasMatch(cfi)) {
      return cfi;
    }
    if (!cfi.startsWith(prefix)) {
      _invalid('This location is not a portable reader locator.');
    }
    try {
      final raw = utf8.decode(
        base64Url.decode(base64Url.normalize(cfi.substring(prefix.length))),
      );
      checkEbookJsonBounds(raw, maximumBytes: 12288);
      final target = _map(jsonDecode(raw), 'portable location');
      final expected = {
        'path',
        'progress',
        if (target.containsKey('fragment')) 'fragment',
      };
      _keys(target, expected);
      final path = _string(target['path'], 'chapter path', 4096);
      if (path.isEmpty ||
          path.startsWith('/') ||
          path.contains('\\') ||
          path
              .split('/')
              .any((part) => part.isEmpty || part == '.' || part == '..') ||
          RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(path)) {
        _invalid('Invalid portable chapter path.');
      }
      if (target.containsKey('fragment')) {
        _string(target['fragment'], 'chapter anchor', 4096);
      }
      final progress = target['progress'];
      if (progress is! num ||
          !progress.isFinite ||
          progress < 0 ||
          progress > 1) {
        _invalid('Invalid portable chapter progress.');
      }
    } on FormatException {
      _invalid('The portable reader locator is malformed.');
    } on ArgumentError {
      _invalid('The portable reader locator is malformed.');
    }
  }
  return cfi;
}

EbookAppearance _appearance(Object? value) {
  final json = _map(value, 'appearance');
  _keys(json, const {
    'fontSize',
    'lineHeight',
    'theme',
    'flow',
    'fontFamily',
    'maxColumnCount',
    'pageMargin',
    'pageWidth',
    'usePublisherStyles',
  });
  for (final entry in const {
    'fontSize': (10, 48),
    'lineHeight': (1, 2.5),
    'pageMargin': (0, 96),
    'pageWidth': (320, 1600),
  }.entries) {
    final number = json[entry.key];
    if (number is! num ||
        !number.isFinite ||
        number < entry.value.$1 ||
        number > entry.value.$2) {
      _invalid('Invalid reading appearance.');
    }
  }
  final columns = json['maxColumnCount'];
  if (columns is! int ||
      columns < 1 ||
      columns > 3 ||
      json['usePublisherStyles'] is! bool ||
      !const {'light', 'sepia', 'dark'}.contains(json['theme']) ||
      !const {'paginated', 'scrolled'}.contains(json['flow']) ||
      !const {
        'serif',
        'sans-serif',
        'monospace',
      }.contains(json['fontFamily'])) {
    _invalid('Invalid reading appearance.');
  }
  return EbookAppearance.fromJson(json);
}

Never _invalid(String message) =>
    throw EbookReadingDataException(EbookReadingDataError.invalid, message);
