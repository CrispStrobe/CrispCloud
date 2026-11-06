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
    final value = path.trim();
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
      return await FileSystemEntity.type(path) != FileSystemEntityType.notFound;
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
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('No such file or directory', path);
    }
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: recursive);
      return;
    }
    await File(path).delete();
  }

  @override
  Future<void> rename(String from, String to) async {
    final type = await FileSystemEntity.type(from);
    if (type == FileSystemEntityType.directory) {
      await Directory(from).rename(to);
      return;
    }
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('No such file or directory', from);
    }
    await File(from).rename(to);
  }

  @override
  Future<void> copy(String from, String to, {bool recursive = false}) async {
    final type = await FileSystemEntity.type(from);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('No such file or directory', from);
    }
    if (type == FileSystemEntityType.directory) {
      if (!recursive) throw FileSystemException('Is a directory', from);
      await _copyDirectory(Directory(from), Directory(to));
      return;
    }
    final parent = Directory(p.dirname(to));
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await File(from).copy(to);
  }

  Future<void> _copyDirectory(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entity in from.list(followLinks: false)) {
      final name = p.basename(entity.path);
      final target = p.join(to.path, name);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(target));
      } else if (entity is File) {
        await entity.copy(target);
      } else if (entity is Link) {
        await Link(target).create(await entity.target());
      }
    }
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
