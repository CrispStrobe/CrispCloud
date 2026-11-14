import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'archive_service.dart';
import 'archive_viewer_service.dart';

/// A shared validated namespace for browsing and editing. Sanitized traversal,
/// special entries, duplicate names, and file/directory collisions never become
/// selectable rows, including when they appear only in an implicit ancestor.
/// Read-only ext/NTFS/disk images retain special metadata in the original F3 listing,
/// but omit it from this regular-file navigation/extraction namespace. Validate
/// the complete namespace before omission so a hidden special entry cannot
/// conceal a duplicate or act as an implicit directory for a selectable file.
class ArchiveMemberIndex {
  ArchiveMemberIndex(ViewerArchive archive) {
    final imageMetadata =
        archive.formatName == 'ext' ||
        archive.formatName == 'ntfs' ||
        archive.formatName == 'disk-image';
    for (final member in archive.members) {
      if (member.pathEscapedRoot ||
          (member.isSpecial && (!imageMetadata || !member.isFile))) {
        throw ArchiveViewException(
          'Unsafe or unsupported member: ${member.name}',
        );
      }
      if (member.name == '/' && !member.isFile) continue;
      final path = ArchiveService.safeMemberPath(member.name);
      if (members.containsKey(path)) {
        throw ArchiveViewException('Duplicate member path: $path');
      }
      members[path] = member;
    }
    if (members.length > 200000) {
      throw const ArchiveViewException(
        'Archive exceeds the 200,000 member limit.',
      );
    }
    for (final path in members.keys) {
      var parent = p.posix.dirname(path);
      while (parent != '.') {
        if (members[parent]?.isFile == true) {
          throw ArchiveViewException(
            'Archive file is also a directory: $parent',
          );
        }
        _directories.add(parent);
        parent = p.posix.dirname(parent);
      }
      if (!members[path]!.isFile) _directories.add(path);
    }
    if (imageMetadata) {
      members.removeWhere((_, member) => member.isSpecial);
    }
  }

  final Map<String, ViewerArchiveMember> members = {};
  final Set<String> _directories = {''};

  String directoryPath(String path) {
    if (path.isEmpty || path == '/') return '';
    final normalized = ArchiveService.safeMemberPath(path);
    if (!_directories.contains(normalized)) {
      throw ArchiveViewException('Archive directory no longer exists: $path');
    }
    return normalized;
  }

  List<FileItem> list(String directory) {
    final normalized = directoryPath(directory);
    final prefix = normalized.isEmpty ? '' : '$normalized/';
    final result = <String, FileItem>{};
    for (final entry in members.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final remainder = entry.key.substring(prefix.length);
      if (remainder.isEmpty) continue;
      final slash = remainder.indexOf('/');
      final name = slash < 0 ? remainder : remainder.substring(0, slash);
      final folder = slash >= 0 || !entry.value.isFile;
      final explicit = members['$prefix$name'];
      result[name] = FileItem(
        name: name,
        path: '$prefix$name${folder ? '/' : ''}',
        isFolder: folder,
        size: folder ? null : entry.value.size,
        updatedAt: explicit?.modified,
      );
    }
    return result.values.toList();
  }

  ViewerArchiveMember file(String path) {
    final normalized = ArchiveService.safeMemberPath(path);
    final member = members[normalized];
    if (member == null || !member.isFile) {
      throw ArchiveViewException('Archive member no longer exists: $path');
    }
    return member;
  }
}
