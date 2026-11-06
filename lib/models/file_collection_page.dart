import 'file_collection.dart';

/// Lightweight catalog data. No file rows, credentials, or live capabilities.
class FileCollectionSummary {
  const FileCollectionSummary({
    required this.id,
    required this.name,
    required this.revision,
    required this.updatedAt,
    required this.itemCount,
    required this.selectedCount,
    required this.sourceCount,
    required this.unavailableCount,
    required this.hasSearch,
  });
  final String id;
  final String name;
  final String revision;
  final DateTime updatedAt;
  final int itemCount;
  final int selectedCount;
  final int sourceCount;
  final int unavailableCount;
  final bool hasSearch;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'revision': revision,
    'updatedAt': updatedAt.toIso8601String(),
    'itemCount': itemCount,
    'selectedCount': selectedCount,
    'sourceCount': sourceCount,
    'unavailableCount': unavailableCount,
    'hasSearch': hasSearch,
  };
  factory FileCollectionSummary.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final revision = json['revision'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 256 ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 256 ||
        revision is! String ||
        revision.isEmpty ||
        revision.length > 64) {
      throw const FormatException('Invalid saved collection metadata.');
    }
    int count(String key) {
      final value = json[key];
      if (value is! int || value < 0 || value > 100000) {
        throw const FormatException('Invalid saved collection item count.');
      }
      return value;
    }

    final total = count('itemCount');
    final selected = count('selectedCount');
    final unavailable = count('unavailableCount');
    final sources = count('sourceCount');
    if (selected > total ||
        unavailable > total ||
        sources > total ||
        (total > 0 && sources == 0)) {
      throw const FormatException('Inconsistent saved collection counts.');
    }
    return FileCollectionSummary(
      id: id,
      name: name,
      revision: revision,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      itemCount: total,
      selectedCount: selected,
      sourceCount: sources,
      unavailableCount: unavailable,
      hasSearch: json['hasSearch'] == true,
    );
  }
}

class CollectionPageDescriptor {
  const CollectionPageDescriptor({
    required this.key,
    required this.count,
    required this.selectedCount,
    required this.bytes,
    required this.digest,
    required this.unavailableCount,
    required this.sources,
  });
  final String key;
  final int count;
  final int selectedCount;
  final int bytes;
  final String digest;
  final int unavailableCount;
  final Set<String> sources;
  Map<String, dynamic> toJson() => {
    'key': key,
    'count': count,
    'selected': selectedCount,
    'bytes': bytes,
    'digest': digest,
    'unavailable': unavailableCount,
    'sources': sources.toList(),
  };
  factory CollectionPageDescriptor.fromJson(Map<String, dynamic> json) {
    final key = json['key'];
    final count = json['count'];
    final selected = json['selected'];
    final bytes = json['bytes'];
    final unavailable = json['unavailable'];
    final digest = json['digest'];
    final sources = json['sources'];
    if (key is! String ||
        key.isEmpty ||
        key.length > 400 ||
        count is! int ||
        count < 1 ||
        count > 500 ||
        selected is! int ||
        selected < 0 ||
        selected > count ||
        bytes is! int ||
        bytes < 1 ||
        bytes > 512 * 1024 ||
        unavailable is! int ||
        unavailable < 0 ||
        unavailable > count ||
        digest is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        sources is! List ||
        sources.isEmpty ||
        sources.length > count ||
        sources.any((source) => source is! String || source.isEmpty) ||
        sources.toSet().length != sources.length) {
      throw const FormatException('Invalid saved collection page.');
    }
    return CollectionPageDescriptor(
      key: key,
      count: count,
      selectedCount: selected,
      bytes: bytes,
      digest: digest,
      unavailableCount: unavailable,
      sources: Set.unmodifiable(Set<String>.from(sources)),
    );
  }
}

class FileCollectionManifest {
  const FileCollectionManifest({
    required this.summary,
    required this.pages,
    this.search,
  });
  final FileCollectionSummary summary;
  final List<CollectionPageDescriptor> pages;
  final CollectionSearch? search;
  Map<String, dynamic> toJson() => {
    'version': 2,
    'summary': summary.toJson(),
    'pages': pages.map((page) => page.toJson()).toList(),
    if (search != null) 'search': search!.toJson(),
  };
  factory FileCollectionManifest.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 2) {
      throw const FormatException('Unsupported collection page version.');
    }
    final summary = FileCollectionSummary.fromJson(
      Map<String, dynamic>.from(json['summary'] as Map),
    );
    final pages = (json['pages'] as List)
        .map(
          (page) => CollectionPageDescriptor.fromJson(
            Map<String, dynamic>.from(page as Map),
          ),
        )
        .toList();
    if (pages.length > 100000 ||
        pages.fold<int>(0, (sum, page) => sum + page.bytes) >
            32 * 1024 * 1024 ||
        pages.fold<int>(0, (sum, page) => sum + page.count) !=
            summary.itemCount ||
        pages.fold<int>(0, (sum, page) => sum + page.selectedCount) !=
            summary.selectedCount ||
        pages.fold<int>(0, (sum, page) => sum + page.unavailableCount) !=
            summary.unavailableCount ||
        pages.expand((page) => page.sources).toSet().length !=
            summary.sourceCount ||
        pages.map((page) => page.key).toSet().length != pages.length) {
      throw const FormatException('Inconsistent collection page manifest.');
    }
    final search = json['search'] == null
        ? null
        : CollectionSearch.fromJson(
            Map<String, dynamic>.from(json['search'] as Map),
          );
    if (summary.hasSearch != (search != null)) {
      throw const FormatException('Invalid collection search metadata.');
    }
    return FileCollectionManifest(
      summary: summary,
      pages: List.unmodifiable(pages),
      search: search,
    );
  }
}

class FileCollectionPage {
  const FileCollectionPage({
    required this.manifest,
    required this.index,
    required this.collection,
  });
  final FileCollectionManifest manifest;
  final int index;
  final FileCollection collection;
  FileCollectionSummary get summary => manifest.summary;
  int get pageCount => manifest.pages.isEmpty ? 1 : manifest.pages.length;
  int get startIndex =>
      manifest.pages.take(index).fold(0, (sum, page) => sum + page.count);
  String? get pageKey =>
      manifest.pages.isEmpty ? null : manifest.pages[index].key;
}
