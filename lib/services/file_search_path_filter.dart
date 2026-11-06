import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/file_search_query.dart';
import 'file_selection_pattern.dart';

/// Applies hidden-directory and directory-exclusion rules to both a recursive
/// walk and a flat result list. A matching ancestor excludes all descendants.
/// [root] is the explicitly selected search root and is not itself pruned.
class FileSearchPathFilter {
  FileSearchPathFilter(this.query, {required this.paths})
    : _excluded = query.excludeDirectories.isEmpty
          ? null
          : FileSelectionPattern(
              query.excludeDirectories,
              caseSensitive: query.caseSensitive,
              matchFullPath:
                  query.excludeDirectories.contains('/') ||
                  (paths.style == p.Style.windows &&
                      query.excludeDirectories.contains(r'\')),
            );

  final FileSearchQuery query;
  final p.Context paths;
  final FileSelectionPattern? _excluded;

  bool allows(FileItem file, {String? root}) {
    if (!query.includeHidden && file.name.startsWith('.')) return false;
    final rawPath = file.path;
    if (rawPath == null) {
      return !file.isFolder || !(_excluded?.matches(file) ?? false);
    }
    final path = paths.normalize(rawPath);
    final boundary = root == null ? null : paths.normalize(root);
    var directory = file.isFolder ? path : paths.dirname(path);
    while (directory != boundary &&
        directory != '.' &&
        directory != paths.dirname(directory)) {
      final name = paths.basename(directory);
      if (!query.includeHidden && name.startsWith('.')) return false;
      if (_excluded?.matches(
            FileItem(name: name, path: directory, isFolder: true),
          ) ??
          false) {
        return false;
      }
      directory = paths.dirname(directory);
    }
    return true;
  }
}
