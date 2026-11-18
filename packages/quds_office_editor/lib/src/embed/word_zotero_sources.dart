import 'package:quds_office_engine/quds_office_engine.dart';

import 'word_zotero_format.dart';

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
