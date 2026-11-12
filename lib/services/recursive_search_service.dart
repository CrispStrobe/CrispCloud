import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:quds_office_engine/quds_office_engine.dart'
    show isSearchableOfficeDocument, officeSearchText;

import '../models/file_item.dart';
import '../models/file_search_query.dart';
import 'archive_service.dart';
import 'archive_viewer_service.dart';
import 'file_operation_service.dart';
import 'file_search_path_filter.dart';
import 'internal_viewer_service.dart';
import 'search_content_matcher.dart';

class FileSearchMatch {
  const FileSearchMatch(this.file, {this.snippet = '', this.archiveMember});
  final FileItem file;
  final String snippet;

  /// Archive matches refer to the original archive file for safe list actions.
  final String? archiveMember;

  /// Group archive hits without losing earlier members when the outer archive
  /// also matches. The evidence is display data, not a virtual-file capability.
  FileItem groupedFile(FileItem? previous) {
    final members = <String>{
      ...?(previous?.metadata?['matchingArchiveMembers'] as List?)
          ?.whereType<String>(),
      if (archiveMember != null) archiveMember!,
    };
    return members.isEmpty
        ? file
        : file.copyWith(
            metadata: {
              ...?file.metadata,
              'matchingArchiveMembers': members.toList(),
            },
          );
  }
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
    final pathFilter = FileSearchPathFilter(query, paths: source.paths);
    final archiveFilter = FileSearchPathFilter(query, paths: p.posix);
    final matches = <FileSearchMatch>[];
    final errors = <String>[];
    final seen = <String>{};
    var scanned = 0;
    var cancelled = false;

    void check() {
      if (isCancelled?.call() ?? false) throw const _SearchCancelled();
      if (!source.isCurrent) {
        throw StateError('The search source changed. Run the search again.');
      }
    }

    void emit(FileSearchMatch match) {
      check();
      matches.add(match);
      onMatch?.call(match);
    }

    void scan(String path) {
      check();
      if (scanned >= 200000) throw const _SearchLimitReached();
      scanned++;
      onProgress?.call(scanned, path);
    }

    Future<String?> contentMatch(Uint8List bytes, String name) async {
      final text = isSearchableOfficeDocument(name)
          ? await officeSearchText(bytes, name, query.maxContentBytes)
          : InternalViewerService.decodeTextForView(
              bytes,
              encoding: query.contentEncoding == 'auto'
                  ? null
                  : query.contentEncoding,
            ).text;
      check();
      return matchSearchText(text, query);
    }

    Future<Uint8List> read(FileItem file, int limit) async {
      if ((file.size ?? 0) > limit) {
        throw StateError('Content exceeds the configured $limit byte limit.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in source.readFile(file)) {
        check();
        if (bytes.length + chunk.length > limit) {
          throw StateError('Content exceeds the configured $limit byte limit.');
        }
        bytes.add(chunk);
      }
      check();
      return bytes.takeBytes();
    }

    Future<void> examine(FileItem file, int depth) async {
      check();
      if (file.name == '.' ||
          file.name == '..' ||
          file.path == null ||
          file.isSymlink == true) {
        return;
      }
      if (!query.includeHidden && file.name.startsWith('.')) return;
      scan(file.path!);
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
              if (entry.pathEscapedRoot || entry.isSpecial) continue;
              final memberPath = p.posix.normalize(entry.name);
              if (p.posix.isAbsolute(memberPath) ||
                  memberPath == '..' ||
                  memberPath.startsWith('../')) {
                continue;
              }
              scan('${file.path}!/$memberPath');
              final memberDepth = p.posix.split(memberPath).length - 1;
              if ((!query.recursive && memberDepth > 0) ||
                  (query.maxDepth != null &&
                      depth + memberDepth > query.maxDepth!)) {
                continue;
              }
              final member = FileItem(
                name: p.posix.basename(memberPath),
                path: memberPath,
                isFolder: !entry.isFile,
                size: entry.size,
                updatedAt: entry.modified,
              );
              if (!archiveFilter.allows(member, root: '.') ||
                  !matcher.matches(member) ||
                  !query.matchesMetadata(member)) {
                continue;
              }
              if (!entry.isFile && query.contentPattern.isNotEmpty) continue;
              String? snippet;
              try {
                snippet = query.contentPattern.isEmpty
                    ? ''
                    : await contentMatch(
                        await archive.readMember(
                          entry,
                          maxBytes: query.maxContentBytes,
                        ),
                        entry.name,
                      );
              } on _SearchCancelled {
                rethrow;
              } catch (error) {
                check();
                errors.add('${file.path}!/${entry.name}: $error');
                continue;
              }
              if (snippet != null) {
                emit(
                  FileSearchMatch(
                    file,
                    snippet: snippet,
                    archiveMember: entry.name,
                  ),
                );
              }
            }
          } finally {
            await archive.close();
          }
        } on _SearchCancelled {
          rethrow;
        } on _SearchLimitReached {
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
          final snippet =
              !query.contentRegex && !isSearchableOfficeDocument(file.name)
              ? await searchLiteralContent(
                  source.readFile(file),
                  query,
                  check: check,
                )
              : await contentMatch(
                  await read(file, query.maxContentBytes),
                  file.name,
                );
          if (snippet != null) emit(FileSearchMatch(file, snippet: snippet));
        } on _SearchCancelled {
          rethrow;
        } catch (error) {
          errors.add('${file.path}: $error');
        }
      }
    }

    Future<void> walk(String directory, int depth, String root) async {
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
        if (!pathFilter.allows(file, root: root)) continue;
        await examine(file, depth);
        if (file.isFolder &&
            file.isSymlink != true &&
            query.recursive &&
            (query.maxDepth == null || depth < query.maxDepth!)) {
          await walk(file.path!, depth + 1, root);
        }
      }
    }

    try {
      for (final root
          in query.roots.isEmpty ? [currentDirectory] : query.roots) {
        final normalized = source.paths.normalize(root);
        if (!source.paths.isAbsolute(normalized)) {
          throw const FormatException('Search roots must be absolute paths.');
        }
        await walk(normalized, 0, normalized);
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

class _SearchLimitReached implements Exception {
  const _SearchLimitReached();
  @override
  String toString() =>
      'Search reached its 200,000 item limit. Narrow its scope.';
}
