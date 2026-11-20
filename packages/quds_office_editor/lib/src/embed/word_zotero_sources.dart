import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';

import 'word_zotero_format.dart';

/// Reuses source metadata without carrying an earlier citation's page number,
/// affixes, author mode or processor position into a new occurrence.
/// Unrecognized source metadata and all URI aliases remain untouched.
ZoteroCitationItem zoteroReusableCitationItem(ZoteroCitationItem item) {
  final json = Map<String, dynamic>.of(item.toJson());
  for (final key in const [
    'locator',
    'label',
    'prefix',
    'suffix',
    'suppress-author',
    'author-only',
    'position',
    'near-note',
    'first-reference-note-number',
    'locator-date',
    'locator-extra',
  ]) {
    json.remove(key);
  }
  return ZoteroCitationItem.fromJson(json);
}

/// A stored source in first-cited order, ready to cite again. A linked source
/// uses its first available embedded snapshot and retains every declared alias.
final class ZoteroDocumentReference {
  const ZoteroDocumentReference({
    required this.selectionKey,
    required this.item,
    required this.occurrences,
  });

  final String selectionKey;
  final ZoteroCitationItem item;
  final int occurrences;
}

/// Groups only explicitly linked Zotero identities. Equal bare IDs or keys in
/// different libraries never merge. Offline records with different stored data
/// remain separate, even when an imported document reused their CSL IDs.
List<ZoteroDocumentReference> zoteroDocumentReferences(
  Iterable<ZoteroCitationItem> sources,
) {
  final items = sources.toList(growable: false);
  final resolver = ZoteroSourceResolver(items, local: false);
  final groups = <String, List<ZoteroCitationItem>>{};
  for (final item in items) {
    final key = _documentSourceKey(item, resolver);
    groups.putIfAbsent(key, () => []).add(item);
  }
  return List.unmodifiable([
    for (final entry in groups.entries) _documentReference(entry),
  ]);
}

String _documentSourceKey(
  ZoteroCitationItem item,
  ZoteroSourceResolver resolver,
) {
  final address = resolver.addressOf(item);
  return address == null
      ? 'stored:${jsonEncode(_orderedJson(zoteroReusableCitationItem(item).toJson()))}'
      : 'linked:${address.canonicalUri}';
}

/// One distinct citation field using a stored source. The field is a live
/// snapshot: hosts must revalidate it before moving the document selection.
final class ZoteroDocumentOccurrence {
  const ZoteroDocumentOccurrence({required this.field, required this.location});

  final WmlZoteroField field;
  final String location;
}

/// Indexes citation fields using the same full-document source aliases and
/// offline snapshot identity as [zoteroDocumentReferences]. A source appearing
/// more than once inside a citation contributes only one navigation entry.
///
/// The input field order is retained. Unsupported stories remain inspectable;
/// navigation availability is decided by the host, never inferred here.
Map<String, List<ZoteroDocumentOccurrence>> zoteroDocumentCitationOccurrences(
  WmlDocument document,
  Iterable<WmlZoteroField> fields,
) {
  final citations = fields
      .where((field) => field.kind == ZoteroFieldKind.citation)
      .toList(growable: false);
  final items = [for (final field in citations) ...?field.citation?.items];
  final resolver = ZoteroSourceResolver(items, local: false);
  final groups = <String, List<ZoteroCitationItem>>{};
  final members = <String, List<WmlZoteroField>>{};
  final seenFields = <(WmlParagraph, WmlRun?, int, int, String)>{};
  for (final field in citations) {
    if (!seenFields.add((
      field.paragraph,
      field.run,
      field.start,
      field.end,
      field.instruction,
    ))) {
      continue;
    }
    final fieldKeys = <String>{};
    for (final item in field.citation?.items ?? <ZoteroCitationItem>[]) {
      final key = _documentSourceKey(item, resolver);
      groups.putIfAbsent(key, () => []).add(item);
      if (fieldKeys.add(key)) {
        members.putIfAbsent(key, () => []).add(field);
      }
    }
  }
  final locations = _documentParagraphLocations(document);
  return Map.unmodifiable({
    for (final group in groups.entries)
      _documentReference(
        group,
      ).selectionKey: List<ZoteroDocumentOccurrence>.unmodifiable([
        for (final field in members[group.key]!)
          ZoteroDocumentOccurrence(
            field: field,
            location: locations[field.paragraph] ?? 'Unlocated story',
          ),
      ]),
  });
}

Map<WmlParagraph, String> _documentParagraphLocations(WmlDocument document) {
  final locations = Map<WmlParagraph, String>.identity();
  void add(Iterable<WmlParagraph> paragraphs, String story) {
    var index = 0;
    for (final paragraph in paragraphs) {
      locations[paragraph] = '$story · paragraph ${++index}';
    }
  }

  for (final (index, section) in document.sections.indexed) {
    final suffix = 'section ${index + 1}';
    add(WordTree.paragraphs(section.blocks), 'Body · $suffix');
    add(section.header, 'Header · $suffix');
    add(section.footer, 'Footer · $suffix');
    add(section.firstHeader, 'First-page header · $suffix');
    add(section.firstFooter, 'First-page footer · $suffix');
    add(section.evenHeader, 'Even-page header · $suffix');
    add(section.evenFooter, 'Even-page footer · $suffix');
  }
  final numbering = WordNoteNumbering(document);
  for (final note in [...document.footnotes, ...document.endnotes]) {
    final kind = note.endnote ? 'Endnote' : 'Footnote';
    final label = numbering.labelFor(note);
    final story = !numbering.hasExactLabel(note)
        ? '$kind (source ID ${note.id})'
        : label.isEmpty
        ? '$kind (custom mark)'
        : '$kind $label';
    add(WordTree.paragraphs(note.blocks), story);
  }
  for (final comment in document.comments) {
    add(comment.paragraphs, 'Comment ${comment.id}');
  }
  return locations;
}

ZoteroDocumentReference _documentReference(
  MapEntry<String, List<ZoteroCitationItem>> group,
) {
  final items = group.value;
  final chosen = items.firstWhere(
    (item) => item.itemData != null && item.itemData!.isNotEmpty,
    orElse: () => items.first,
  );
  final uris = <String>{for (final item in items) ...item.uris};
  final canonicalUris =
      uris
          .map(ZoteroSourceAddress.parse)
          .whereType<ZoteroSourceAddress>()
          .map((address) => address.canonicalUri.toString())
          .toSet()
          .toList()
        ..sort();
  final identity = canonicalUris.isEmpty
      ? group.key
      : 'linked:${canonicalUris.first}';
  final reusable = zoteroReusableCitationItem(chosen);
  return ZoteroDocumentReference(
    selectionKey: 'document:$identity',
    item: ZoteroCitationItem.fromJson({
      ...reusable.toJson(),
      if (uris.isNotEmpty) 'uris': uris.toList(),
    }),
    occurrences: items.length,
  );
}

Object? _orderedJson(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _orderedJson(value[key])};
  }
  if (value is List) return value.map(_orderedJson).toList();
  return value;
}

/// Resolves explicitly declared Zotero URI aliases before a connected operation.
///
/// A later citation can connect earlier source identities, even without its own
/// embedded snapshot. Only validated Zotero URIs join groups; item keys and CSL
/// IDs alone never establish a relationship. Original citation data stays intact.
/// Each group has one deterministic request address: its first numeric identity
/// online, or its first declared identity on the desktop. Missing remote sources
/// are not retried through another alias.
final class ZoteroSourceResolver {
  factory ZoteroSourceResolver(
    Iterable<ZoteroCitationItem> sources, {
    required bool local,
  }) {
    final addresses = <ZoteroSourceAddress>[];
    final indexes = <String, int>{};
    final parents = <int>[];
    final ranks = <int>[];

    int root(int index) {
      while (parents[index] != index) {
        parents[index] = parents[parents[index]];
        index = parents[index];
      }
      return index;
    }

    int add(ZoteroSourceAddress address) {
      final key = address.canonicalUri.toString();
      final existing = indexes[key];
      if (existing != null) return existing;
      if (addresses.length >= 10000) {
        throw const FormatException(
          'Resolve at most 10,000 Zotero source aliases at once.',
        );
      }
      final index = addresses.length;
      addresses.add(address);
      indexes[key] = index;
      parents.add(index);
      ranks.add(0);
      return index;
    }

    void join(int first, int second) {
      final firstRoot = root(first);
      final secondRoot = root(second);
      if (firstRoot == secondRoot) return;
      if (ranks[firstRoot] < ranks[secondRoot]) {
        parents[firstRoot] = secondRoot;
      } else {
        parents[secondRoot] = firstRoot;
        if (ranks[firstRoot] == ranks[secondRoot]) ranks[firstRoot]++;
      }
    }

    for (final item in sources) {
      int? first;
      for (final uri in item.uris) {
        final address = ZoteroSourceAddress.parse(uri);
        if (address == null) continue;
        final index = add(address);
        if (first == null) {
          first = index;
        } else {
          join(first, index);
        }
      }
    }

    final firstAddresses = <int, ZoteroSourceAddress>{};
    final onlineAddresses = <int, ZoteroSourceAddress>{};
    for (var index = 0; index < addresses.length; index++) {
      final group = root(index);
      final address = addresses[index];
      firstAddresses.putIfAbsent(group, () => address);
      if (!address.isLocal) {
        onlineAddresses.putIfAbsent(group, () => address);
      }
    }
    return ZoteroSourceResolver._({
      for (final entry in indexes.entries)
        entry.key:
            (local ? null : onlineAddresses[root(entry.value)]) ??
            firstAddresses[root(entry.value)]!,
    });
  }

  ZoteroSourceResolver._(Map<String, ZoteroSourceAddress> addresses)
    : _addresses = Map.unmodifiable(addresses);

  final Map<String, ZoteroSourceAddress> _addresses;

  /// The shared request identity for a source declared in this resolver.
  /// Unlinked or wholly unrecognized URI metadata stays offline.
  ZoteroSourceAddress? addressOf(ZoteroCitationItem item) {
    for (final uri in item.uris) {
      final address = ZoteroSourceAddress.parse(uri);
      if (address == null) continue;
      final resolved = _addresses[address.canonicalUri.toString()];
      if (resolved != null) return resolved;
    }
    return null;
  }
}
