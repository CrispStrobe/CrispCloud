import 'dart:convert';
import 'dart:typed_data';

import 'sandbox_shell_fs_base.dart';

/// In-memory filesystem for the browser and for deterministic shell tests.
///
/// It intentionally lives only for the current session. Browser users get a
/// useful demo tree and can create files while the page is open; real local
/// files are only reachable through the desktop/iOS/Android filesystem
/// implementation.
class MemorySandboxShellFs implements SandboxShellFs {
  MemorySandboxShellFs() {
    _nodes['/'] = _MemoryNode.directory();
    for (final directory in <String>[
      '/home',
      '/home/user',
      '/home/user/Documents',
      '/home/user/Downloads',
      '/tmp',
    ]) {
      _createDirectory(directory);
    }
    _writeBytes(
      '/home/user/README.txt',
      utf8.encode(
        'CrispCloud built-in shell\n'
        '\n'
        'This browser session has an in-memory filesystem. Files disappear\n'
        'when the page is closed. Use "help" to list the built-in commands.\n',
      ),
    );
    _writeBytes(
      '/home/user/Documents/line-endings.txt',
      utf8.encode('first line\r\nsecond line\r\nthird line\r\n'),
    );
  }

  final Map<String, _MemoryNode> _nodes = <String, _MemoryNode>{};

  @override
  Future<String> get home async => '/home/user';

  @override
  String get platformName => 'web';

  @override
  bool get isMemory => true;

  @override
  Future<String> normalize(String path, String cwd) async {
    final value = path.trim();
    if (value.isEmpty) return cwd;
    if (value == '~') return home;
    if (value.startsWith('~/')) {
      return _normalizeAbsolute('${await home}/${value.substring(2)}');
    }
    if (value.startsWith('/')) return _normalizeAbsolute(value);
    return _normalizeAbsolute('$cwd/$value');
  }

  String _normalizeAbsolute(String value) {
    final parts = <String>[];
    for (final part in value.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(part);
      }
    }
    return '/${parts.join('/')}';
  }

  String _parent(String path) {
    if (path == '/') return '/';
    final index = path.lastIndexOf('/');
    return index <= 0 ? '/' : path.substring(0, index);
  }

  String _name(String path) {
    if (path == '/') return '/';
    return path.substring(path.lastIndexOf('/') + 1);
  }

  void _createDirectory(String path) {
    final normalized = _normalizeAbsolute(path);
    if (normalized == '/') {
      _nodes.putIfAbsent('/', _MemoryNode.directory);
      return;
    }
    _createDirectory(_parent(normalized));
    _nodes.putIfAbsent(normalized, _MemoryNode.directory);
  }

  void _writeBytes(String path, List<int> bytes) {
    final normalized = _normalizeAbsolute(path);
    _createDirectory(_parent(normalized));
    _nodes[normalized] = _MemoryNode.file(Uint8List.fromList(bytes));
  }

  @override
  Future<bool> exists(String path) async => _nodes.containsKey(path);

  @override
  Future<bool> isDirectory(String path) async =>
      _nodes[path]?.isDirectory ?? false;

  @override
  Future<List<ShellEntry>> list(String path) async {
    final node = _nodes[path];
    if (node == null) throw StateError('No such file or directory: $path');
    if (!node.isDirectory) throw StateError('Not a directory: $path');
    final prefix = path == '/' ? '/' : '$path/';
    final entries = <ShellEntry>[];
    for (final entry in _nodes.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final rest = entry.key.substring(prefix.length);
      if (rest.isEmpty || rest.contains('/')) continue;
      final child = entry.value;
      entries.add(
        ShellEntry(
          name: rest,
          isDirectory: child.isDirectory,
          size: child.isDirectory ? 0 : child.bytes.length,
          modified: child.modified,
        ),
      );
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return entries;
  }

  @override
  Future<List<int>> readBytes(String path) async {
    final node = _nodes[path];
    if (node == null) throw StateError('No such file: $path');
    if (node.isDirectory) throw StateError('Is a directory: $path');
    return Uint8List.fromList(node.bytes);
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    _writeBytes(path, bytes);
  }

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {
    final normalized = _normalizeAbsolute(path);
    if (!recursive) {
      final parent = _parent(normalized);
      if (!(_nodes[parent]?.isDirectory ?? false)) {
        throw StateError('No such directory: $parent');
      }
      if (_nodes.containsKey(normalized)) {
        throw StateError('Already exists: $path');
      }
    }
    _createDirectory(normalized);
  }

  @override
  Future<void> delete(String path, {bool recursive = false}) async {
    final node = _nodes[path];
    if (node == null) throw StateError('No such file or directory: $path');
    if (node.isDirectory) {
      final children = _nodes.keys.where(
        (candidate) =>
            candidate != path &&
            candidate.startsWith(path == '/' ? '/' : '$path/'),
      );
      if (!recursive && children.isNotEmpty) {
        throw StateError('Directory not empty: $path');
      }
      _nodes.removeWhere(
        (candidate, _) =>
            candidate == path ||
            candidate.startsWith(path == '/' ? '/' : '$path/'),
      );
    } else {
      _nodes.remove(path);
    }
  }

  @override
  Future<void> rename(String from, String to) async {
    final node = _nodes[from];
    if (node == null) throw StateError('No such file or directory: $from');
    final moving = <String, _MemoryNode>{};
    for (final entry in _nodes.entries) {
      if (entry.key == from ||
          entry.key.startsWith(from == '/' ? '/' : '$from/')) {
        moving[entry.key] = entry.value;
      }
    }
    for (final key in moving.keys) {
      _nodes.remove(key);
    }
    for (final entry in moving.entries) {
      final suffix = entry.key.substring(from.length);
      _nodes['$to$suffix'] = entry.value;
    }
  }

  @override
  Future<void> copy(String from, String to, {bool recursive = false}) async {
    final node = _nodes[from];
    if (node == null) throw StateError('No such file or directory: $from');
    if (node.isDirectory) {
      if (!recursive) throw StateError('Is a directory: $from');
      _createDirectory(to);
      for (final entry in _nodes.entries) {
        if (!entry.key.startsWith('$from/')) continue;
        final target = '$to${entry.key.substring(from.length)}';
        if (entry.value.isDirectory) {
          _createDirectory(target);
        } else {
          _writeBytes(target, entry.value.bytes);
        }
      }
      return;
    }
    _writeBytes(to, node.bytes);
  }

  @override
  Future<ShellEntry> stat(String path) async {
    final node = _nodes[path];
    if (node == null) throw StateError('No such file or directory: $path');
    return ShellEntry(
      name: _name(path),
      isDirectory: node.isDirectory,
      size: node.isDirectory ? 0 : node.bytes.length,
      modified: node.modified,
    );
  }
}

class _MemoryNode {
  _MemoryNode.directory()
    : isDirectory = true,
      bytes = Uint8List(0),
      modified = DateTime.now();

  _MemoryNode.file(this.bytes) : isDirectory = false, modified = DateTime.now();

  final bool isDirectory;
  final Uint8List bytes;
  final DateTime modified;
}

SandboxShellFs createSandboxShellFs() => MemorySandboxShellFs();
