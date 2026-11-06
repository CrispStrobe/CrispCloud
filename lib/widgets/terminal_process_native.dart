// lib/widgets/terminal_process_native.dart
//
// Native (non-web) terminal backends.
//
// * Desktop: a real shell process, on macOS under a pseudo-terminal so the
//   prompt and line editing work.
// * iOS: no arbitrary process spawning is permitted, so this file provides a
//   small built-in command interpreter (pwd, cd, ls, cat, cp, mv, rm, mkdir,
//   touch, echo, date, whoami, uname, clear, help, exit). It works inside the
//   app container and any document-picker grant the app holds.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Common terminal backend interface.
abstract class ShellProcess {
  Stream<String> get outputStream;
  void writeln(String command);
  void kill();
}

class _ProcessShell implements ShellProcess {
  _ProcessShell(this._process) {
    _process.stdout.listen(
      (data) => _controller.add(utf8.decode(data, allowMalformed: true)),
    );
    _process.stderr.listen(
      (data) => _controller.add(utf8.decode(data, allowMalformed: true)),
    );
    _process.exitCode.then((_) => _controller.close());
  }

  final Process _process;
  final _controller = StreamController<String>.broadcast();
  late final Stream<String> _outputStream = _controller.stream;

  @override
  Stream<String> get outputStream => _outputStream;

  @override
  void writeln(String command) => _process.stdin.writeln(command);

  @override
  void kill() => _process.kill();
}

class _BuiltInShell implements ShellProcess {
  _BuiltInShell(this._cwd) {
    _cwd = _normalize(_cwd);
    _controller = StreamController<String>.broadcast();
  }

  String _cwd;
  late final StreamController<String> _controller;
  bool _closed = false;

  @override
  Stream<String> get outputStream => _controller.stream;

  void _write(String text) {
    if (!_closed) _controller.add(text);
  }

  String _normalize(String value) {
    if (value.isEmpty) return _cwd;
    final expanded = value == '~'
        ? (Platform.environment['HOME'] ?? '/')
        : value.startsWith('~/')
        ? p.join(Platform.environment['HOME'] ?? '/', value.substring(2))
        : value;
    final resolved = p.isAbsolute(expanded)
        ? p.normalize(expanded)
        : p.normalize(p.join(_cwd, expanded));
    return resolved;
  }

  @override
  void writeln(String command) {
    final line = command.trim();
    if (line.isEmpty) return;
    unawaited(_run(line));
  }

  Future<void> _run(String line) async {
    final parts = _split(line);
    if (parts.isEmpty) return;
    final command = parts.first;
    final args = parts.sublist(1);
    try {
      switch (command) {
        case 'pwd':
          _write('$_cwd\n');
        case 'cd':
          final target = _normalize(args.isEmpty ? '~' : args.first);
          if (await Directory(target).exists()) {
            _cwd = target;
          } else {
            _write('cd: no such directory: $target\n');
          }
        case 'ls':
        case 'dir':
          await _ls(args);
        case 'cat':
          if (args.isEmpty) {
            _write('cat: missing file\n');
          } else {
            for (final arg in args) {
              final path = _normalize(arg);
              try {
                final bytes = await File(path).readAsBytes();
                _write(utf8.decode(bytes, allowMalformed: true));
                if (!utf8.decode(bytes, allowMalformed: true).endsWith('\n')) {
                  _write('\n');
                }
              } catch (e) {
                _write('cat: $arg: $e\n');
              }
            }
          }
        case 'mkdir':
          final paths = args.where((a) => !a.startsWith('-')).toList();
          if (paths.isEmpty) {
            _write('mkdir: missing path\n');
          } else {
            for (final arg in paths) {
              await Directory(_normalize(arg)).create(recursive: true);
            }
          }
        case 'touch':
          for (final arg in args.where((a) => !a.startsWith('-'))) {
            final path = _normalize(arg);
            final file = File(path);
            if (!await file.exists()) await file.create(recursive: true);
            await file.setLastModified(DateTime.now());
          }
        case 'rm':
          final recursive = args.any((a) => a == '-r' || a == '-rf');
          final force = args.any((a) => a.contains('f'));
          for (final arg in args.where((a) => !a.startsWith('-'))) {
            final path = _normalize(arg);
            try {
              final type = await FileSystemEntity.type(path);
              if (type == FileSystemEntityType.directory) {
                if (!recursive) {
                  _write('rm: $arg is a directory (use -r)\n');
                  continue;
                }
                await Directory(path).delete(recursive: true);
              } else if (type == FileSystemEntityType.file) {
                await File(path).delete();
              } else if (!force) {
                _write('rm: $arg: not found\n');
              }
            } catch (e) {
              if (!force) _write('rm: $arg: $e\n');
            }
          }
        case 'cp':
          await _copy(args, move: false);
        case 'mv':
          await _copy(args, move: true);
        case 'echo':
          _write('${args.join(' ')}\n');
        case 'date':
          _write('${DateTime.now()}\n');
        case 'whoami':
          _write('${Platform.environment['USER'] ?? 'mobile'}\n');
        case 'uname':
          _write(
            '${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n',
          );
        case 'clear':
          _write('\n');
        case 'help':
          _write(
            'Built-in iOS shell commands:\n'
            '  pwd cd ls dir cat mkdir touch rm cp mv echo date whoami uname clear exit help\n',
          );
        case 'exit':
          _closed = true;
          await _controller.close();
        default:
          _write('$command: command not found (built-in shell)\n');
      }
    } catch (e) {
      _write('$command: $e\n');
    }
  }

  Future<void> _ls(List<String> args) async {
    final long = args.any((a) => a == '-l' || a == '-la' || a == '-al');
    final showHidden = args.any((a) => a.contains('a'));
    final targets = args.where((a) => !a.startsWith('-')).toList();
    final dir = _normalize(targets.isEmpty ? '.' : targets.first);
    final directory = Directory(dir);
    if (!await directory.exists()) {
      _write('ls: no such directory: $dir\n');
      return;
    }
    final entries = await directory.list(followLinks: false).toList();
    entries.sort((a, b) => a.path.compareTo(b.path));
    for (final entry in entries) {
      final name = p.basename(entry.path);
      if (!showHidden && name.startsWith('.')) continue;
      if (long) {
        try {
          final stat = await entry.stat();
          final kind = stat.type == FileSystemEntityType.directory ? 'd' : '-';
          _write(
            '$kind ${stat.size.toString().padLeft(8)} ${stat.modified.toIso8601String().substring(0, 16)} $name\n',
          );
        } catch (_) {
          _write('? $name\n');
        }
      } else {
        _write('$name\n');
      }
    }
  }

  Future<void> _copy(List<String> args, {required bool move}) async {
    final paths = args.where((a) => !a.startsWith('-')).toList();
    if (paths.length < 2) {
      _write('${move ? 'mv' : 'cp'}: source and destination required\n');
      return;
    }
    final source = _normalize(paths[0]);
    final destination = _normalize(paths[1]);
    final type = await FileSystemEntity.type(source);
    if (type == FileSystemEntityType.directory) {
      if (move) {
        await Directory(source).rename(destination);
      } else {
        await _copyDirectory(Directory(source), Directory(destination));
      }
    } else if (type == FileSystemEntityType.file) {
      if (move) {
        await File(source).rename(destination);
      } else {
        await File(source).copy(destination);
      }
    } else {
      _write('${move ? 'mv' : 'cp'}: $paths[0]: not found\n');
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final target = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(target));
      } else if (entity is File) {
        await entity.copy(target);
      }
    }
  }

  List<String> _split(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    String? quote;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (quote != null) {
        if (char == quote) {
          quote = null;
        } else {
          buffer.write(char);
        }
      } else if (char == '"' || char == "'") {
        quote = char;
      } else if (char.trim().isEmpty) {
        if (buffer.isNotEmpty) {
          result.add(buffer.toString());
          buffer.clear();
        }
      } else {
        buffer.write(char);
      }
    }
    if (buffer.isNotEmpty) result.add(buffer.toString());
    return result;
  }

  @override
  void kill() {
    if (_closed) return;
    _closed = true;
    _controller.close();
  }
}

String _accessibleWorkingDirectory(String requested) {
  bool usable(String path) {
    try {
      return Directory(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  if (usable(requested)) return requested;
  final home = Platform.environment['HOME'];
  if (home != null && usable(home)) return home;
  final temp = Directory.systemTemp.path;
  return usable(temp) ? temp : Directory.current.path;
}

/// Start the best available local terminal backend for this platform.
Future<ShellProcess?> startShell(String workingDirectory) async {
  final cwd = _accessibleWorkingDirectory(workingDirectory);
  if (Platform.isIOS) return _BuiltInShell(cwd);
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    return null;
  }

  final shell = Platform.isWindows
      ? 'cmd.exe'
      : Platform.environment['SHELL'] ?? '/bin/bash';

  Process process;
  if (Platform.isMacOS && File('/usr/bin/script').existsSync()) {
    process = await Process.start(
      '/usr/bin/script',
      <String>['-q', '/dev/null', shell, '-i'],
      workingDirectory: cwd,
      environment: Platform.environment,
    );
  } else {
    process = await Process.start(
      shell,
      Platform.isWindows ? <String>[] : <String>['--login', '-i'],
      workingDirectory: cwd,
      environment: Platform.environment,
    );
  }

  return _ProcessShell(process);
}

/// Built-in fallback for platforms or sandboxes where spawning a shell is not
/// permitted or not useful.
Future<ShellProcess?> startBuiltInShell(String workingDirectory) async {
  return _BuiltInShell(_accessibleWorkingDirectory(workingDirectory));
}
