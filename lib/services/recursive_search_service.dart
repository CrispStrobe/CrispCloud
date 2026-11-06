import 'dart:typed_data';
import 'dart:convert';

import '../models/file_item.dart';
import '../models/file_search_query.dart';
import 'archive_service.dart';
import 'archive_viewer_service.dart';
import 'file_operation_service.dart';
import 'file_selection_pattern.dart';
import 'internal_viewer_service.dart';
import 'office_search_text.dart';

class FileSearchMatch {
  const FileSearchMatch(this.file, {this.snippet = '', this.archiveMember});
  final FileItem file;
  final String snippet;

  /// Archive matches refer to the original archive file for safe list actions.
  final String? archiveMember;
}

class FileSearchResult {
  const FileSearchResult(
    this.matches,
    this.errors,
    this.scanned,
    this.cancelled,
  );
  final List<FileSearchMatch> matches;
  final List<String> errors;
  final int scanned;
  final bool cancelled;
}

/// One engine for every local/cloud backend, using captured source identity.
/// Content budgets and unreadable directories are reported, never hidden.
class RecursiveSearchService {
  Future<FileSearchResult> search(
    FileOperationBackend source,
    FileSearchQuery query, {
    required String currentDirectory,
    bool Function()? isCancelled,
    void Function(FileSearchMatch match)? onMatch,
    void Function(int scanned, String path)? onProgress,
  }) async {
    query.validate();
    final matcher = query.nameMatcher;
    final excludedDirectories = query.excludeDirectories.isEmpty
        ? null
        : FileSelectionPattern(
            query.excludeDirectories,
            caseSensitive: query.caseSensitive,
            matchFullPath: query.excludeDirectories.contains('/'),
          );
    final contentRegex = query.contentRegex && query.contentPattern.isNotEmpty
        ? RegExp(
            query.contentPattern,
            caseSensitive: query.contentCaseSensitive,
            multiLine: true,
            unicode: true,
          )
        : null;
    final matches = <FileSearchMatch>[];
    final errors = <String>[];
    final seen = <String>{};
    var scanned = 0;
    var cancelled = false;

    void check() {
      if (isCancelled?.call() ?? false) throw const _SearchCancelled();
      if (!source.isCurrent)
        throw StateError('The search source changed. Run the search again.');
    }

    void emit(FileSearchMatch match) {
      check();
      matches.add(match);
      onMatch?.call(match);
    }

    String? contentMatch(Uint8List bytes) {
      final text = InternalViewerService.decodeTextForView(
        bytes,
        encoding: query.contentEncoding == 'auto'
            ? null
            : query.contentEncoding,
      ).text;
      final pattern = query.contentPattern;
      final match = contentRegex?.firstMatch(text);
      final index = contentRegex != null
          ? match?.start ?? -1
          : query.contentCaseSensitive
          ? text.indexOf(pattern)
          : text.toLowerCase().indexOf(pattern.toLowerCase());
      if (query.contentNegated)
        return index < 0 ? 'Content does not contain the query.' : null;
      if (index < 0) return null;
      final start = (index - 45).clamp(0, text.length);
      final end = (index + (match?.group(0)?.length ?? pattern.length) + 90)
          .clamp(0, text.length);
      return '${start > 0 ? '…' : ''}${text.substring(start, end).replaceAll('\n', ' ')}${end < text.length ? '…' : ''}';
    }

    Future<Uint8List> read(FileItem file, int limit) async {
      if ((file.size ?? 0) > limit)
        throw StateError('Content exceeds the configured $limit byte limit.');
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in source.readFile(file)) {
        check();
        if (bytes.length + chunk.length > limit)
          throw StateError('Content exceeds the configured $limit byte limit.');
        bytes.add(chunk);
      }
      check();
      return bytes.takeBytes();
    }

    Future<void> examine(FileItem file) async {
      check();
      if (file.name == '.' ||
          file.name == '..' ||
          file.path == null ||
          file.isSymlink == true)
        return;
      if (!query.includeHidden && file.name.startsWith('.')) return;
      scanned++;
      onProgress?.call(scanned, file.path!);
      if (scanned > 200000)
        throw StateError(
          'Search reached its 200,000 item limit. Narrow its scope.',
        );
      if (query.searchArchives &&
          !file.isFolder &&
          ArchiveService.isArchive(file.name)) {
        try {
          final archive = await openViewerArchive(
            await read(file, ArchiveService.maxArchiveBytes),
            name: file.name,
            maxMemberBytes: query.maxContentBytes,
          );
          try {
            for (final entry in archive.members) {
              check();
              if (entry.pathEscapedRoot || entry.isSpecial || !entry.isFile)
                continue;
              final member = FileItem(
                name: entry.name.split('/').last,
                path: entry.name,
                isFolder: false,
                size: entry.size,
              );
              if (!matcher.matches(member) || !query.matchesMetadata(member))
                continue;
              final snippet = query.contentPattern.isEmpty
                  ? ''
                  : contentMatch(
                      await archive.readMember(
                        entry,
                        maxBytes: query.maxContentBytes,
                      ),
                    );
              if (snippet != null)
                emit(
                  FileSearchMatch(
                    file,
                    snippet: snippet,
                    archiveMember: entry.name,
                  ),
                );
            }
          } finally {
            await archive.close();
          }
        } on _SearchCancelled {
          rethrow;
        } catch (error) {
          errors.add('${file.path}: $error');
        }
      }
      if (!matcher.matches(file) || !query.matchesMetadata(file)) return;
      if (query.contentPattern.isEmpty) {
        emit(FileSearchMatch(file));
      } else if (!file.isFolder && !ArchiveService.isArchive(file.name)) {
        try {
          var content = await read(file, query.maxContentBytes);
          if (isSearchableOfficeDocument(file.name)) {
            content = Uint8List.fromList(
              utf8.encode(
                await officeSearchText(
                  content,
                  file.name,
                  query.maxContentBytes,
                ),
              ),
            );
          }
          final snippet = contentMatch(content);
          if (snippet != null) emit(FileSearchMatch(file, snippet: snippet));
        } on _SearchCancelled {
          rethrow;
        } catch (error) {
          errors.add('${file.path}: $error');
        }
      }
    }

    Future<void> walk(String directory, int depth) async {
      check();
      final key = source.pathKey(directory);
      if (!seen.add(key)) return;
      List<FileItem> children;
      try {
        children = await source.list(directory);
      } catch (error) {
        errors.add('$directory: $error');
        return;
      }
      check();
      for (final file in children) {
        check();
        if (file.path == null ||
            source.paths.dirname(file.path!) != directory ||
            !source.isWithin(directory, file.path!)) {
          errors.add('Invalid child path returned by source: ${file.path}');
          continue;
        }
        if (file.isFolder && excludedDirectories?.matches(file) == true)
          continue;
        if (!query.includeHidden && file.name.startsWith('.')) continue;
        await examine(file);
        if (file.isFolder &&
            file.isSymlink != true &&
            query.recursive &&
            (query.maxDepth == null || depth < query.maxDepth!)) {
          await walk(file.path!, depth + 1);
        }
      }
    }

    try {
      for (final root
          in query.roots.isEmpty ? [currentDirectory] : query.roots) {
        final normalized = source.paths.normalize(root);
        if (!source.paths.isAbsolute(normalized))
          throw const FormatException('Search roots must be absolute paths.');
        await walk(normalized, 0);
      }
    } on _SearchCancelled {
      cancelled = true;
    } catch (error) {
      errors.add(error.toString());
    }
    return FileSearchResult(matches, errors, scanned, cancelled);
  }
}

class _SearchCancelled implements Exception {
  const _SearchCancelled();
}
