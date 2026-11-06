import 'file_item.dart';
import 'file_search_query.dart';
import 'storage_reference.dart';

enum CollectionItemState { ready, changed, missing, offline }

/// A saved row is a reference and display snapshot, never an I/O capability.
class FileCollectionEntry {
  const FileCollectionEntry({
    required this.reference,
    required this.file,
    this.state = CollectionItemState.ready,
    this.detail,
    this.replacement = false,
  });
  final FileReference reference;
  final FileItem file;
  final CollectionItemState state;
  final String? detail;
  final bool replacement;
  String get key => '${reference.storage.id}\u0000${reference.path}';

  Map<String, dynamic> toJson() => {
    'reference': reference.toJson(),
    'file': {
      'name': file.name,
      'isFolder': file.isFolder,
      'size': file.size,
      'updatedAt': file.updatedAt?.toIso8601String(),
      'isSymlink': file.isSymlink,
      'symlinkTarget': file.symlinkTarget,
    },
    'state': state.name,
    'detail': detail,
    'replacement': replacement,
  };

  factory FileCollectionEntry.fromJson(Map<String, dynamic> json) {
    final reference = FileReference.fromJson(
      Map<String, dynamic>.from(json['reference'] as Map),
    );
    final data = Map<String, dynamic>.from(json['file'] as Map);
    if (data['name'] is! String || data['isFolder'] is! bool) {
      throw const FormatException('Invalid collection item.');
    }
    return FileCollectionEntry(
      reference: reference,
      file: FileItem(
        name: data['name'] as String,
        path: reference.path,
        uuid: reference.objectId,
        storageId: reference.storage.id,
        isFolder: data['isFolder'] as bool,
        size: data['size'] as int?,
        updatedAt: data['updatedAt'] == null
            ? null
            : DateTime.parse(data['updatedAt'] as String),
        isSymlink: data['isSymlink'] as bool?,
        symlinkTarget: data['symlinkTarget'] as String?,
      ),
      state: CollectionItemState.values.byName(
        json['state'] as String? ?? 'offline',
      ),
      detail: json['detail'] as String?,
      replacement: json['replacement'] == true,
    );
  }
}

/// Keeping this separate makes refresh-items and rerun-query different actions.
class CollectionSearch {
  const CollectionSearch({
    required this.storage,
    required this.directory,
    required this.query,
  });
  final StorageReference storage;
  final String directory;
  final FileSearchQuery query;
  Map<String, dynamic> toJson() => {
    'storage': storage.toJson(),
    'directory': directory,
    'query': query.toJson(),
  };
  factory CollectionSearch.fromJson(Map<String, dynamic> json) {
    final query = FileSearchQuery.fromJson(
      Map<String, dynamic>.from(json['query'] as Map),
    );
    query.validate();
    return CollectionSearch(
      storage: StorageReference.fromJson(
        Map<String, dynamic>.from(json['storage'] as Map),
      ),
      directory: json['directory'] as String,
      query: query,
    );
  }
}

class FileCollection {
  FileCollection({
    required this.id,
    required this.name,
    required List<FileCollectionEntry> entries,
    Set<String> selectedKeys = const {},
    this.search,
    DateTime? updatedAt,
  }) : entries = List.unmodifiable(entries),
       selectedKeys = Set.unmodifiable(selectedKeys),
       updatedAt = updatedAt ?? DateTime.now() {
    if (id.isEmpty || name.trim().isEmpty || name.length > 256) {
      throw const FormatException(
        'Enter a collection name (up to 256 characters).',
      );
    }
    if (entries.length > 100000) {
      throw const FormatException('A collection can hold up to 100,000 items.');
    }
    if (entries.map((entry) => entry.key).toSet().length != entries.length) {
      throw const FormatException(
        'A collection contains duplicate source paths.',
      );
    }
  }
  final String id;
  final String name;
  final List<FileCollectionEntry> entries;
  final Set<String> selectedKeys;
  final CollectionSearch? search;
  final DateTime updatedAt;

  FileCollection copyWith({
    String? name,
    List<FileCollectionEntry>? entries,
    Set<String>? selectedKeys,
    CollectionSearch? search,
    bool clearSearch = false,
  }) => FileCollection(
    id: id,
    name: name ?? this.name,
    entries: entries ?? this.entries,
    selectedKeys: selectedKeys ?? this.selectedKeys,
    search: clearSearch ? null : search ?? this.search,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'id': id,
    'name': name,
    'updatedAt': updatedAt.toIso8601String(),
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'selectedKeys': selectedKeys.toList(),
    if (search != null) 'search': search!.toJson(),
  };

  factory FileCollection.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported collection version.');
    }
    return FileCollection(
      id: json['id'] as String,
      name: json['name'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      entries: (json['entries'] as List)
          .map(
            (entry) => FileCollectionEntry.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(),
      selectedKeys: Set<String>.from(json['selectedKeys'] as List? ?? []),
      search: json['search'] == null
          ? null
          : CollectionSearch.fromJson(
              Map<String, dynamic>.from(json['search'] as Map),
            ),
    );
  }
}
