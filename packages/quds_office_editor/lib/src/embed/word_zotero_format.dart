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
  final unique = <String, Map<String, dynamic>>{};
  for (final item in items) {
    final data = item.itemData;
    final address = item.uris
        .map(ZoteroSourceAddress.parse)
        .whereType<ZoteroSourceAddress>()
        .firstOrNull;
    if (data != null) {
      unique.putIfAbsent(
        address != null
            ? address.library.itemUri(address.key).toString()
            : item.uris.isEmpty
            ? 'csl:${item.id}'
            : item.uris.first,
        () => data,
      );
    }
  }
  final records = unique.values.toList()
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

/// Only canonical remote library/item identifiers can be refreshed online.
class ZoteroSourceAddress {
  const ZoteroSourceAddress(this.library, this.key);
  final ZoteroLibrary library;
  final String key;
  static ZoteroSourceAddress? parse(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme) ||
        !const ['zotero.org', 'www.zotero.org'].contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final parts = uri.pathSegments;
    if (parts.length != 4 ||
        parts[2] != 'items' ||
        !RegExp(r'^[A-Z0-9]{8}$').hasMatch(parts[3])) {
      return null;
    }
    final id = int.tryParse(parts[1]);
    if (id == null || id <= 0) return null;
    final library = switch (parts[0]) {
      'users' => ZoteroLibrary.user(id),
      'groups' => ZoteroLibrary.group(id),
      _ => null,
    };
    return library == null ? null : ZoteroSourceAddress(library, parts[3]);
  }
}
