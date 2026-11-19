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
    final address = resolver.addressOf(item);
    final key = address == null
        ? 'stored:${jsonEncode(_orderedJson(zoteroReusableCitationItem(item).toJson()))}'
        : 'linked:${address.canonicalUri}';
    groups.putIfAbsent(key, () => []).add(item);
  }
  return List.unmodifiable([
    for (final entry in groups.entries) _documentReference(entry),
  ]);
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
