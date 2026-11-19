import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';

/// Copies the selected embedded CSL snapshots without contacting Zotero.
///
/// Selection order and repeated records are retained. Citation-specific
/// locators and affixes are not reference metadata. Item URI aliases are
/// included so importing the result can recover the same linked identities.
/// The result fits the existing CSL import's 500-record / 1 MiB limits.
String zoteroSelectionCslJson(Iterable<ZoteroCitationItem> items) {
  final records = <Map<String, Object?>>[];
  for (final item in items) {
    if (records.length == 500) {
      throw const FormatException(
        'Copy at most 500 stored references at a time.',
      );
    }
    final data = item.itemData;
    if (data == null || data['type'] is! String || data['title'] is! String) {
      throw const FormatException(
        'A selected reference has incomplete stored CSL metadata. '
        'Reload that reference before copying.',
      );
    }
    final record = <String, Object?>{...data};
    final id = record['id'];
    if (id == null) {
      record['id'] = item.id;
    } else if (id is! String && id is! num) {
      throw const FormatException('A stored CSL reference has an invalid ID.');
    }
    if (item.uris.isNotEmpty) {
      final storedUris = record['uris'];
      if (storedUris != null &&
          (storedUris is! List || storedUris.any((uri) => uri is! String))) {
        throw const FormatException(
          'A stored reference has malformed URI metadata. '
          'Reload that reference before copying.',
        );
      }
      final uris = <String>[
        if (storedUris is List) ...storedUris.cast<String>(),
      ];
      for (final uri in item.uris) {
        if (!uris.contains(uri)) uris.add(uri);
      }
      record['uris'] = uris;
    }
    records.add(record);
  }
  if (records.isEmpty) {
    throw const FormatException('Select at least one reference to copy.');
  }
  final text = const JsonEncoder.withIndent('  ').convert(records);
  if (utf8.encode(text).length > 1024 * 1024) {
    throw const FormatException(
      'Stored CSL JSON exceeds the 1 MB import limit. '
      'Select fewer references to copy.',
    );
  }
  return text;
}
