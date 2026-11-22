import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';

/// Converts Zotero's formatted XHTML to inert, readable plain text. No markup,
/// external resource, or script is ever evaluated by the Office editor.
String zoteroHtmlToPlainText(String html) {
  if (html.length > 8 * 1024 * 1024) {
    throw const FormatException('The formatted reference is too large.');
  }
  var text = html
      .replaceAll(
        RegExp(
          r'<(script|style)\b[^>]*>[\s\S]*?</\1\s*>',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(?:div|p|li)\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '');
  text = text.replaceAllMapped(
    RegExp(r'&(#x[0-9a-f]+|#[0-9]+|[a-z]+);', caseSensitive: false),
    (match) {
      final entity = match[1]!;
      if (entity.startsWith('#')) {
        final hex = entity.length > 2 && entity[1].toLowerCase() == 'x';
        final value = int.tryParse(
          entity.substring(hex ? 2 : 1),
          radix: hex ? 16 : 10,
        );
        if (value != null &&
            value > 0 &&
            value <= 0x10ffff &&
            (value < 0xd800 || value > 0xdfff)) {
          return String.fromCharCode(value);
        }
        return '\uFFFD';
      }
      return const {
            'amp': '&',
            'lt': '<',
            'gt': '>',
            'quot': '"',
            'apos': "'",
            'nbsp': ' ',
            'ndash': '–',
            'mdash': '—',
            'lsquo': '‘',
            'rsquo': '’',
            'ldquo': '“',
            'rdquo': '”',
          }[entity.toLowerCase()] ??
          match[0]!;
    },
  );
  return text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join('\n');
}

/// Deliberately basic author–year text, with no claim to a specific CSL style.
String zoteroBasicCitation(List<ZoteroCitationItem> items) {
  final parts = <String>[];
  for (final item in items) {
    final data = item.itemData ?? const <String, dynamic>{};
    final author = _authors(data, short: true);
    final year = _year(data);
    var text = item.authorOnly
        ? author
        : item.suppressAuthor
        ? year
        : '$author, $year';
    if (item.locator.isNotEmpty) {
      final label = switch (item.label) {
        '' || 'page' => 'p.',
        'chapter' => 'chap.',
        'section' => 'sec.',
        'paragraph' => 'para.',
        final other => other,
      };
      text += ', $label ${item.locator}';
    }
    if (item.prefix.isNotEmpty) text = '${item.prefix} $text';
    if (item.suffix.isNotEmpty) text = '$text ${item.suffix}';
    parts.add(text);
  }
  return '(${parts.join('; ')})';
}

/// A portable fallback bibliography from embedded data. This is not APA,
/// Chicago, numeric numbering, or any other complete CSL implementation.
String zoteroBasicBibliography(List<ZoteroCitationItem> items) {
  final records = WordZotero.distinctEmbeddedItems(items)
    ..sort(
      (a, b) => '${_authors(a)} ${a['title'] ?? ''}'.toLowerCase().compareTo(
        '${_authors(b)} ${b['title'] ?? ''}'.toLowerCase(),
      ),
    );
  return records
      .map((data) {
        final title = zoteroHtmlToPlainText('${data['title'] ?? 'Untitled'}');
        final container = data['container-title'] ?? data['publisher'];
        final doi = data['DOI'];
        return [
          '${_authors(data)} (${_year(data)}).',
          '$title.',
          if (container is String && container.isNotEmpty) '$container.',
          if (doi is String && doi.isNotEmpty) 'https://doi.org/$doi',
        ].join(' ');
      })
      .join('\n\n');
}

String _authors(Map<String, dynamic> data, {bool short = false}) {
  final authors = data['author'] ?? data['editor'];
  if (authors is! List || authors.isEmpty) {
    return zoteroHtmlToPlainText('${data['title'] ?? 'Untitled'}');
  }
  final names = <String>[];
  for (final author in authors.whereType<Map<dynamic, dynamic>>()) {
    final literal = author['literal'];
    final family = author['family'];
    final given = author['given'];
    final name = literal is String
        ? literal
        : [
            if (family is String) family,
            if (!short && given is String) given,
          ].join(', ');
    if (name.isNotEmpty) names.add(name);
  }
  if (names.isEmpty) return 'Anonymous';
  if (short && names.length > 2) return '${names.first} et al.';
  return names.join(short ? ' & ' : '; ');
}

String _year(Map<String, dynamic> data) {
  final issued = data['issued'];
  if (issued is Map) {
    final parts = issued['date-parts'];
    if (parts is List &&
        parts.isNotEmpty &&
        parts.first is List &&
        (parts.first as List).isNotEmpty) {
      return '${(parts.first as List).first}';
    }
    final literal = issued['literal'] ?? issued['raw'];
    if (literal is String) {
      return RegExp(r'\b\d{4}\b').firstMatch(literal)?[0] ?? literal;
    }
  }
  return 'n.d.';
}

/// Bounded import of Zotero's CSL JSON export, with snapshots kept offline.
/// Records without a canonical Zotero URI remain explicitly unlinked sources.
List<ZoteroCitationItem> zoteroImportCslJson(String input) {
  if (utf8.encode(input).length > 1024 * 1024) {
    throw const FormatException('Import at most 1 MB of CSL JSON at a time.');
  }
  dynamic decoded;
  try {
    decoded = jsonDecode(input);
  } on FormatException {
    throw const FormatException('Paste a valid CSL JSON object or array.');
  }
  final records = decoded is List
      ? decoded
      : decoded is Map && decoded['items'] is List
      ? decoded['items'] as List
      : <dynamic>[decoded];
  if (records.isEmpty || records.length > 500) {
    throw const FormatException('Import between 1 and 500 CSL references.');
  }
  final result = <ZoteroCitationItem>[];
  for (var i = 0; i < records.length; i++) {
    final record = records[i];
    if (record is! Map<String, dynamic> ||
        record['type'] is! String ||
        record['title'] is! String) {
      throw const FormatException('Each CSL reference needs a type and title.');
    }
    final id =
        record['id'] ?? 'quds-csl-${DateTime.now().microsecondsSinceEpoch}-$i';
    final data = <String, dynamic>{...record, 'id': id};
    final candidates = [
      record['id'],
      record['uri'],
      if (record['uris'] is List) ...(record['uris'] as List),
    ];
    final uris = candidates
        .whereType<String>()
        .where((value) => ZoteroSourceAddress.parse(value) != null)
        .toSet()
        .toList();
    result.add(
      uris.isEmpty
          ? ZoteroCitationItem.fromJson({
              'id': id,
              'itemData': data,
              'uris': <String>[],
            })
          : ZoteroCitationItem.fromCsl(itemData: data, uris: uris),
    );
  }
  return result;
}

/// A persistent source identity and its API route are deliberately separate.
/// Desktop local-user identities route through /users/0, while their original
/// local user key remains part of the identity used for verification and dedupe.
class ZoteroSourceAddress {
  const ZoteroSourceAddress(this.library, this.key) : _localUserKey = null;

  const ZoteroSourceAddress._local(this.library, this.key, this._localUserKey);

  final ZoteroLibrary library;
  final String key;
  final String? _localUserKey;

  bool get isLocal => _localUserKey != null;

  /// Unlike [ZoteroLibrary.apiPath], this distinguishes different local profiles.
  String get scope => isLocal ? '/users/local/$_localUserKey' : library.apiPath;

  /// Used for comparison only. Imported citation URIs are never rewritten.
  Uri get canonicalUri => isLocal
      ? Uri.parse('http://zotero.org$scope/items/$key')
      : library.itemUri(key);

  static bool isLocalItemUri(String value) => parse(value)?.isLocal == true;

  static ZoteroSourceAddress? parse(String value) {
    // Check the original authority before Uri normalizes explicit default ports.
    // Validate the raw path too, so escapes and dot segments cannot become IDs.
    final authority = RegExp(
      r'^https?://(?:www\.)?zotero\.org/',
      caseSensitive: false,
    ).matchAsPrefix(value);
    if (authority == null) return null;
    final path = value.substring(authority.end - 1);
    final local = RegExp(
      r'^/users/local/([A-Za-z0-9]{8})/items/([A-Z0-9]{8})$',
    ).matchAsPrefix(path);
    if (local != null && local.end == path.length) {
      return ZoteroSourceAddress._local(
        ZoteroLibrary.localUser(),
        local[2]!,
        local[1]!,
      );
    }
    final remote = RegExp(
      r'^/(users|groups)/([1-9][0-9]*)/items/([A-Z0-9]{8})$',
    ).matchAsPrefix(path);
    if (remote == null || remote.end != path.length) return null;
    final id = int.tryParse(remote[2]!);
    if (id == null || id <= 0) return null;
    final library = remote[1] == 'users'
        ? ZoteroLibrary.user(id)
        : ZoteroLibrary.group(id);
    return ZoteroSourceAddress(library, remote[3]!);
  }
}

/// A trusted Zotero desktop selection URL for a currently loaded catalog item.
///
/// Personal web-library IDs cannot be assumed to identify the open desktop
/// profile. Unsynced items from the active local catalog are safe to select by
/// their local key; group libraries have an explicit, stable group ID.
Uri? zoteroCatalogItemSelectionUri(ZoteroItem item) {
  if (item.library.isLocalUser) {
    return Uri.parse('zotero://select/library/items/${item.key}');
  }
  if (item.library.type == ZoteroLibraryType.group) {
    return Uri.parse(
      'zotero://select/groups/${item.library.id}/items/${item.key}',
    );
  }
  return null;
}

/// A desktop selection URL derived only from canonical Zotero source links.
///
/// An offline CSL ID or arbitrary stored URL is never opened. When a citation
/// contains conflicting local profiles or group identities, do not guess which
/// source should be selected. A remote personal-library URI is not sufficient
/// to prove that the user's currently running Zotero profile owns the item.
Uri? zoteroStoredItemSelectionUri(ZoteroCitationItem item) {
  final identities = <String>{};
  final selections = <String>{};
  for (final rawUri in item.uris) {
    final source = ZoteroSourceAddress.parse(rawUri);
    if (source == null) continue;
    final selection = source.isLocal
        ? Uri.parse('zotero://select/library/items/${source.key}')
        : source.library.type == ZoteroLibraryType.group
        ? Uri.parse(
            'zotero://select/groups/${source.library.id}/items/${source.key}',
          )
        : null;
    if (selection == null) continue;
    identities.add('${source.scope}/items/${source.key}');
    selections.add(selection.toString());
  }
  return identities.length == 1 && selections.length == 1
      ? Uri.parse(selections.single)
      : null;
}
