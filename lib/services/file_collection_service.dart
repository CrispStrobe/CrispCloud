import '../models/file_collection.dart';
import '../models/file_item.dart';
import '../models/storage_reference.dart';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'file_operation_service.dart';
import 'recursive_search_service.dart';

typedef CollectionBackendResolver = FileOperationBackend? Function(
  StorageReference storage,
  String path,
);

class CollectionRefreshResult {
  const CollectionRefreshResult(
    this.collection,
    this.verifiedKeys, {
    this.warnings = const [],
  });
  final FileCollection collection;
  final Set<String> verifiedKeys;
  final List<String> warnings;
}

/// Restats saved paths without rerunning a search or trusting persisted metadata.
class FileCollectionService {
  const FileCollectionService();

  /// Apply known successful operations, including descendants of renamed
  /// directories. Identical paths on another account are left untouched.
  FileCollection rewrite(
    FileCollection collection,
    StorageReference storage,
    Map<String, FileItem?> replacements, {
    Set<String> removedDirectories = const {},
  }) {
    final paths = storage.isLocal && !kIsWeb ? p.context : p.posix;
    final folders =
        replacements.entries
            .where(
              (entry) =>
                  entry.value?.isFolder == true &&
                  entry.value?.isSymlink != true,
            )
            .toList()
          ..sort((a, b) => b.key.length.compareTo(a.key.length));
    final rows = <FileCollectionEntry>[];
    final selected = <String>{};
    var changed = false;
    for (final entry in collection.entries) {
      FileCollectionEntry? next = entry;
      if (entry.reference.storage == storage) {
        final path = entry.reference.path;
        FileItem? replacement;
        var matches = replacements.containsKey(path);
        if (matches) replacement = replacements[path];
        if (!matches &&
            removedDirectories.any((parent) => paths.isWithin(parent, path))) {
          matches = true;
        }
        if (!matches) {
          for (final folder in folders) {
            if (!paths.isWithin(folder.key, path)) continue;
            replacement = entry.file.copyWith(
              path: paths.join(
                folder.value!.path!,
                paths.relative(path, from: folder.key),
              ),
            );
            matches = true;
            break;
          }
        }
        if (matches) {
          next = replacement == null ? null : capture(replacement, storage);
          changed = true;
        }
      }
      if (next == null) continue;
      rows.add(next);
      if (collection.selectedKeys.contains(entry.key)) selected.add(next.key);
    }
    return changed
        ? collection.copyWith(entries: rows, selectedKeys: selected)
        : collection;
  }

  static String? objectIdentity(FileItem file) =>
      file.uuid == null ||
          file.uuid!.isEmpty ||
          file.uuid == file.path ||
          file.uuid == file.name
      ? null
      : file.uuid;
  static String? version(FileItem file) =>
      (file.metadata?['etag'] ??
              file.metadata?['versionId'] ??
              file.metadata?['revision'])
          ?.toString();
  static FileCollectionEntry capture(FileItem file, StorageReference storage) {
    if (file.path == null || file.path!.isEmpty) {
      throw StateError('This row has no original path.');
    }
    return FileCollectionEntry(
      reference: FileReference(
        storage: storage,
        path: file.path!,
        objectId: objectIdentity(file),
        version: version(file),
      ),
      file: file.copyWith(storageId: storage.id),
    );
  }

  /// Only replacements whose account/path keys were reviewed may be accepted.
  /// Other replacements discovered by this refresh retain their original evidence.
  Future<CollectionRefreshResult> refresh(
    FileCollection collection,
    CollectionBackendResolver resolve, {
    Set<String> acceptedReplacementKeys = const {},
    bool Function()? isCancelled,
    void Function(int complete, int total)? onProgress,
  }) async {
    final accepted = Set<String>.unmodifiable(acceptedReplacementKeys);
    final directories = <String, Future<List<FileItem>>>{};
    final entries = <FileCollectionEntry>[];
    final verified = <String>{};
    void check() {
      if (isCancelled?.call() ?? false) {
        throw StateError('Collection refresh cancelled.');
      }
    }

    for (final entry in collection.entries) {
      check();
      final reference = entry.reference;
      final backend = resolve(reference.storage, reference.path);
      FileCollectionEntry unavailable(
        CollectionItemState state,
        String reason, {
        bool replacement = false,
      }) => FileCollectionEntry(
        reference: reference,
        // Preserve the original snapshot until a replacement is accepted.
        // Otherwise a type-only replacement becomes the comparison baseline
        // and a second refresh silently verifies it without consent.
        file: entry.file,
        state: state,
        detail: reason,
        replacement: replacement,
      );
      if (backend == null || !backend.isCurrent) {
        entries.add(
          unavailable(
            CollectionItemState.offline,
            'Reconnect the original storage account to check this item.',
          ),
        );
      } else {
        try {
          final path = backend.paths.normalize(reference.path);
          if (!backend.paths.isAbsolute(path) || path.contains('\u0000')) {
            throw const FormatException('The saved original path is invalid.');
          }
          final parent = backend.paths.dirname(path);
          final key = '${reference.storage.id}\u0000$parent';
          final siblings = await (directories[key] ??= backend.list(parent));
          check();
          if (!backend.isCurrent) {
            throw StateError('The storage account disconnected.');
          }
          final matches = siblings
              .where(
                (file) =>
                    file.path != null &&
                    backend.pathKey(file.path!) == backend.pathKey(path),
              )
              .toList();
          if (matches.isEmpty) {
            entries.add(
              unavailable(
                CollectionItemState.missing,
                'The original path is missing.',
              ),
            );
          } else if (matches.length != 1) {
            entries.add(
              unavailable(
                CollectionItemState.changed,
                'Multiple items share this path. Open the original folder to choose.',
                replacement: true,
              ),
            );
          } else {
            final current = matches.single.copyWith(
              storageId: reference.storage.id,
            );
            final differentObject =
                reference.objectId != null &&
                reference.objectId != objectIdentity(current);
            final differentType =
                current.isFolder != entry.file.isFolder ||
                (current.isSymlink == true) != (entry.file.isSymlink == true);
            if ((differentObject || differentType) &&
                !accepted.contains(entry.key)) {
              entries.add(
                unavailable(
                  CollectionItemState.changed,
                  'A different item now occupies this path. Review and accept it before operating.',
                  replacement: true,
                ),
              );
            } else {
              final changed =
                  differentObject ||
                  differentType ||
                  current.size != entry.file.size ||
                  current.updatedAt != entry.file.updatedAt ||
                  version(current) != reference.version;
              final captured = capture(current, reference.storage);
              entries.add(
                FileCollectionEntry(
                  reference: captured.reference,
                  file: captured.file,
                  state: changed
                      ? CollectionItemState.changed
                      : CollectionItemState.ready,
                  detail: changed
                      ? 'Metadata changed since the previous snapshot; this row is freshly verified.'
                      : null,
                ),
              );
              verified.add(entry.key);
            }
          }
        } catch (error) {
          check();
          entries.add(
            unavailable(CollectionItemState.offline, error.toString()),
          );
        }
      }
      onProgress?.call(entries.length, collection.entries.length);
    }
    check();
    return CollectionRefreshResult(
      collection.copyWith(entries: entries),
      verified,
    );
  }

  Future<CollectionRefreshResult> rerun(
    FileCollection collection,
    CollectionBackendResolver resolve, {
    bool Function()? isCancelled,
    void Function(int scanned, String path)? onProgress,
  }) async {
    final search = collection.search;
    if (search == null) {
      throw StateError('This collection has no saved search definition.');
    }
    final backend = resolve(search.storage, search.directory);
    if (backend == null || !backend.isCurrent) {
      throw StateError('Reconnect the original search account.');
    }
    final result = await RecursiveSearchService().search(
      backend,
      search.query,
      currentDirectory: search.directory,
      isCancelled: isCancelled,
      onProgress: onProgress,
    );
    if (result.cancelled || (isCancelled?.call() ?? false)) {
      throw StateError(
        'Search rerun cancelled; the saved collection is unchanged.',
      );
    }
    if (!backend.isCurrent) {
      throw StateError('The original search account disconnected.');
    }
    if (result.errors.isNotEmpty) {
      throw StateError(
        'The search could not check every location; the saved collection is unchanged. ${result.errors.take(3).join('\n')}',
      );
    }
    final unique = <String, FileCollectionEntry>{};
    for (final match in result.matches) {
      final entry = capture(match.file, search.storage);
      unique[entry.key] = entry;
    }
    return CollectionRefreshResult(
      collection.copyWith(
        entries: unique.values.toList(),
        selectedKeys: collection.selectedKeys.intersection(unique.keys.toSet()),
      ),
      unique.keys.toSet(),
      warnings: result.errors,
    );
  }
}
