import 'dart:io';

import 'package:path/path.dart' as p;

import 'sandbox_shell_fs_base.dart';

/// Native filesystem view for the built-in sandbox shell.
///
/// This deliberately uses `dart:io` rather than spawning `/bin/sh`. It works
/// inside App Sandbox (for the app container and user-granted locations), on
/// iOS/Android (where process spawning is unavailable), and on desktop.
class IoSandboxShellFs implements SandboxShellFs {
  String? _home;

  @override
  Future<String> get home async {
    final cached = _home;
    if (cached != null) return cached;
    for (final candidate in <String?>[
      Platform.environment['HOME'],
      Platform.environment['USERPROFILE'],
      Directory.systemTemp.path,
      Directory.current.path,
    ]) {
      if (candidate == null || candidate.isEmpty) continue;
      try {
        if (Directory(candidate).existsSync()) {
          _home = p.normalize(candidate);
          return _home!;
        }
      } catch (_) {
        // Try the next writable candidate.
      }
    }
    _home = p.normalize(Directory.current.path);
    return _home!;
  }

  @override
  String get platformName => Platform.operatingSystem;

  @override
  bool get isMemory => false;

  @override
  Future<String> normalize(String path, String cwd) async {
    final value = path;
    if (value.isEmpty) return cwd;
    final homePath = await home;
    if (value == '~') return homePath;
    if (value.startsWith('~/') || value.startsWith('~\\')) {
      return p.normalize(p.join(homePath, value.substring(2)));
    }
    if (p.isAbsolute(value)) return p.normalize(value);
    return p.normalize(p.join(cwd, value));
  }

  @override
  Future<bool> exists(String path) async {
    try {
      return await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.notFound;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isDirectory(String path) async {
    try {
      return await FileSystemEntity.isDirectory(path);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<ShellEntry>> list(String path) async {
    final entries = <ShellEntry>[];
    await for (final entity in Directory(path).list(followLinks: false)) {
      final name = p.basename(entity.path);
      final stat = await FileStat.stat(entity.path);
      entries.add(
        ShellEntry(
          name: name,
          isDirectory: entity is Directory,
          size: stat.type == FileSystemEntityType.file ? stat.size : 0,
          modified: stat.modified,
        ),
      );
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  @override
  Future<List<int>> readBytes(String path) => File(path).readAsBytes();

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final parent = Directory(p.dirname(path));
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await File(path).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {
    final directory = Directory(path);
    if (await directory.exists()) {
      if (!recursive) throw FileSystemException('Already exists', path);
      return;
    }
    await directory.create(recursive: recursive);
  }

  @override
  Future<void> delete(String path, {bool recursive = false}) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('No such file or directory', path);
    }
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: recursive);
      return;
    }
    if (type == FileSystemEntityType.link) {
      await Link(path).delete();
      return;
    }
    await File(path).delete();
  }

  @override
  Future<void> rename(String from, String to) async {
    final type = await FileSystemEntity.type(from, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('No such file or directory', from);
    }
    await _checkDestination(
      from,
      to,
      directory: type == FileSystemEntityType.directory,
    );
    try {
      if (type == FileSystemEntityType.directory) {
        await Directory(from).rename(to);
      } else if (type == FileSystemEntityType.link) {
        await Link(from).rename(to);
      } else {
        await File(from).rename(to);
      }
    } on FileSystemException catch (error) {
      // EXDEV on POSIX, ERROR_NOT_SAME_DEVICE on Windows. Other rename
      // failures must retain both source and destination without a fallback.
      final crossDevice =
          error.osError?.errorCode == (Platform.isWindows ? 17 : 18);
      if (!crossDevice) rethrow;
      await copy(from, to, recursive: true);
      await delete(from, recursive: true);
    }
  }

  @override
  Future<void> copy(String from, String to, {bool recursive = false}) async {
    final type = await FileSystemEntity.type(from, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('No such file or directory', from);
    }
    await _checkDestination(
      from,
      to,
      directory: type == FileSystemEntityType.directory,
    );
    if (type == FileSystemEntityType.directory) {
      if (!recursive) throw FileSystemException('Is a directory', from);
      final sourceRoot = await Directory(from).resolveSymbolicLinks();
      await _copyDirectory(Directory(from), Directory(to), sourceRoot);
      return;
    }
    final parent = Directory(p.dirname(to));
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    if (type == FileSystemEntityType.link) {
      // Preserve links instead of following a directory link outside the tree.
      await Link(to).create(await Link(from).target());
    } else {
      await File(from).copy(to);
    }
  }

  Future<void> _copyDirectory(
    Directory from,
    Directory to,
    String sourceRoot,
  ) async {
    final targetType = await FileSystemEntity.type(to.path, followLinks: false);
    if (targetType == FileSystemEntityType.link) {
      throw FileSystemException(
        'A directory copy cannot replace a symbolic link',
        to.path,
      );
    }
    final resolvedTarget = await _canonicalDestination(to.path);
    if (p.equals(sourceRoot, resolvedTarget) ||
        p.isWithin(sourceRoot, resolvedTarget)) {
      throw FileSystemException('Cannot copy a directory into itself', to.path);
    }
    await to.create(recursive: true);
    await for (final entity in from.list(followLinks: false)) {
      final name = p.basename(entity.path);
      final target = p.join(to.path, name);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(target), sourceRoot);
      } else if (entity is File) {
        await entity.copy(target);
      } else if (entity is Link) {
        await Link(target).create(await entity.target());
      }
    }
  }

  Future<void> _checkDestination(
    String from,
    String to, {
    required bool directory,
  }) async {
    final sourcePath = p.normalize(p.absolute(from));
    final destinationPath = p.normalize(p.absolute(to));
    if (p.equals(sourcePath, destinationPath)) {
      throw FileSystemException('Source and destination are the same item', to);
    }
    String source;
    try {
      source = await File(from).resolveSymbolicLinks();
    } on FileSystemException {
      if (await FileSystemEntity.type(from, followLinks: false) !=
          FileSystemEntityType.link)
        rethrow;
      // A dangling symlink is still an item which can be copied or renamed.
      source = p.join(
        await Directory(p.dirname(from)).resolveSymbolicLinks(),
        p.basename(from),
      );
    }
    final target = await _canonicalDestination(to);
    if (p.equals(source, target) ||
        (await exists(to) && await FileSystemEntity.identical(from, to))) {
      throw FileSystemException('Source and destination are the same item', to);
    }
    if (directory && p.isWithin(source, target)) {
      throw FileSystemException(
        'Cannot copy or move a directory into itself',
        to,
      );
    }
  }

  /// Resolve existing parent links even when the final destination is new.
  Future<String> _canonicalDestination(String path) async {
    var existing = p.normalize(p.absolute(path));
    final missing = <String>[];
    while (await FileSystemEntity.type(existing, followLinks: false) ==
        FileSystemEntityType.notFound) {
      final parent = p.dirname(existing);
      if (parent == existing) break;
      missing.add(p.basename(existing));
      existing = parent;
    }
    final canonical = await File(existing).resolveSymbolicLinks();
    return p.normalize(p.joinAll([canonical, ...missing.reversed]));
  }

  @override
  Future<ShellEntry> stat(String path) async {
    final stat = await FileStat.stat(path);
    if (stat.type == FileSystemEntityType.notFound) {
      throw FileSystemException('No such file or directory', path);
    }
    return ShellEntry(
      name: p.basename(path),
      isDirectory: stat.type == FileSystemEntityType.directory,
      size: stat.type == FileSystemEntityType.file ? stat.size : 0,
      modified: stat.modified,
    );
  }
}

SandboxShellFs createSandboxShellFs() => IoSandboxShellFs();
