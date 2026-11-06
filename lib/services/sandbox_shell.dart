import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;

import 'sandbox_shell_fs.dart';

/// Result of one command or pipeline.
class ShellResult {
  const ShellResult({
    this.stdout = '',
    this.stderr = '',
    this.exitCode = 0,
    this.exit = false,
  });

  final String stdout;
  final String stderr;
  final int exitCode;
  final bool exit;
}

/// A small, pure-Dart shell used when the host cannot (or must not) launch a
/// PTY. It is intentionally not a general-purpose process launcher; it exposes
/// safe file inspection and editing commands over [SandboxShellFs].
class SandboxShell {
  SandboxShell({
    required this.fs,
    required String cwd,
    Map<String, String>? environment,
  }) : cwd = cwd,
       env = <String, String>{
         'HOME': cwd,
         'PWD': cwd,
         'USER': 'user',
         ...?environment,
       };

  final SandboxShellFs fs;
  final Map<String, String> env;
  final List<String> history = <String>[];
  String cwd;

  /// Optional one-line explanation shown before the welcome banner, e.g. when
  /// a host PTY was denied by the sandbox.
  String? startupNotice;

  static Future<SandboxShell> create({String? startPath}) async {
    final fs = createSandboxShellFs();
    var cwd = await fs.home;
    if (startPath != null && startPath.trim().isNotEmpty) {
      try {
        final candidate = await fs.normalize(startPath, cwd);
        if (await fs.isDirectory(candidate)) {
          // Probe readability as well as existence; a sandbox-denied directory
          // must not become the shell's unusable starting point.
          await fs.list(candidate);
          cwd = candidate;
        }
      } catch (_) {
        // Keep the home directory.
      }
    }
    return SandboxShell(fs: fs, cwd: cwd);
  }

  String get displayCwd => cwd;

  String get prompt {
    final user = env['USER'] ?? 'user';
    final short = _shortPath(cwd);
    return '\x1b[32m$user@crispcloud\x1b[0m:\x1b[34m$short\x1b[0m\$ ';
  }

  String get welcome {
    final memory = fs.isMemory
        ? ' Files live in memory for this browser session.'
        : '';
    final notice = startupNotice == null
        ? ''
        : '\x1b[33m$startupNotice\x1b[0m\r\n';
    return '${notice}\x1b[36mCrispCloud built-in shell\x1b[0m '
        '(${fs.platformName})\r\n'
        'No host process is launched; this is the sandbox-safe shell.$memory\r\n'
        "Type 'help' for the built-in commands. Use SSH for a full remote shell.\r\n";
  }

  String _shortPath(String path) {
    final home = env['HOME'];
    if (home != null && path == home) return '~';
    if (home != null && path.startsWith('$home${p.separator}')) {
      return '~${path.substring(home.length)}';
    }
    return path;
  }

  Future<ShellResult> executeLine(String line) async {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return const ShellResult();
    history.add(trimmed);
    if (history.length > 200) history.removeAt(0);

    final tokens = _tokenize(trimmed);
    if (tokens.isEmpty) return const ShellResult();
    final groups = <List<String>>[];
    var current = <String>[];
    for (final token in tokens) {
      if (token == '|') {
        if (current.isNotEmpty) groups.add(current);
        current = <String>[];
      } else {
        current.add(token);
      }
    }
    if (current.isNotEmpty) groups.add(current);
    if (groups.isEmpty) return const ShellResult();

    var stdin = '';
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    var lastCode = 0;

    for (var index = 0; index < groups.length; index++) {
      final group = groups[index];
      String? outputFile;
      String? inputFile;
      var append = false;
      final argv = <String>[];
      for (var i = 0; i < group.length; i++) {
        final token = group[i];
        if ((token == '>' || token == '>>') && i + 1 < group.length) {
          outputFile = group[++i];
          append = token == '>>';
        } else if (token == '<' && i + 1 < group.length) {
          inputFile = group[++i];
        } else {
          argv.add(token);
        }
      }
      if (argv.isEmpty) continue;

      if (inputFile != null) {
        try {
          stdin = await _readText(await _resolve(inputFile));
        } catch (error) {
          stderr.writeln('$inputFile: ${_message(error)}');
          lastCode = 1;
          continue;
        }
      }

      final result = await _run(argv, stdin);
      lastCode = result.exitCode;
      if (result.stderr.isNotEmpty) stderr.write(result.stderr);
      if (result.exit) {
        return ShellResult(
          stdout: stdout.toString() + result.stdout,
          stderr: stderr.toString(),
          exitCode: result.exitCode,
          exit: true,
        );
      }

      if (outputFile != null) {
        final path = await _resolve(outputFile);
        try {
          final existing = append && await fs.exists(path)
              ? await _readText(path)
              : '';
          await fs.writeBytes(path, utf8.encode(existing + result.stdout));
        } catch (error) {
          stderr.writeln('$outputFile: ${_message(error)}');
          lastCode = 1;
        }
        stdin = '';
      } else {
        stdin = result.stdout;
        if (index == groups.length - 1) stdout.write(result.stdout);
      }
    }

    return ShellResult(
      stdout: stdout.toString(),
      stderr: stderr.toString(),
      exitCode: lastCode,
    );
  }

  Future<ShellResult> _run(List<String> argv, String stdin) async {
    final command = argv.first;
    final args = argv.sublist(1).map(_expand).toList();
    try {
      switch (command) {
        case 'help':
        case '?':
          return _ok(_helpText);
        case 'pwd':
          return _ok('$cwd\n');
        case 'cd':
          return await _cd(args);
        case 'ls':
          return await _ls(args);
        case 'cat':
          return await _cat(args, stdin);
        case 'head':
          return await _head(args, stdin, fromEnd: false);
        case 'tail':
          return await _head(args, stdin, fromEnd: true);
        case 'wc':
          return await _wc(args, stdin);
        case 'grep':
          return await _grep(args, stdin);
        case 'find':
          return await _find(args);
        case 'echo':
          return _echo(args);
        case 'mkdir':
          return await _mkdir(args);
        case 'touch':
          return await _touch(args);
        case 'rm':
          return await _rm(args);
        case 'mv':
          return await _mv(args);
        case 'cp':
          return await _cp(args);
        case 'stat':
          return await _stat(args);
        case 'file':
          return await _file(args, stdin);
        case 'xxd':
        case 'hexdump':
          return await _hexdump(args, stdin);
        case 'date':
          return _ok('${DateTime.now()}\n');
        case 'whoami':
          return _ok('${env['USER'] ?? 'user'}\n');
        case 'uname':
          return _ok(
            args.contains('-a')
                ? 'CrispCloud built-in shell ${fs.platformName} '
                      '(${fs.isMemory ? 'memory' : 'filesystem'})\n'
                : 'CrispCloud\n',
          );
        case 'env':
          return _env(args);
        case 'export':
          return _export(args);
        case 'unset':
          for (final name in args) {
            env.remove(name);
          }
          return const ShellResult();
        case 'history':
          final out = StringBuffer();
          for (var i = 0; i < history.length; i++) {
            out.writeln('${i + 1}  ${history[i]}');
          }
          return _ok(out.toString());
        case 'clear':
          return _ok('\x1b[2J\x1b[H');
        case 'which':
          final known = _commands.contains(args.isEmpty ? '' : args.first);
          return known
              ? _ok('${args.first}: built-in shell command\n')
              : _err('${args.first}: not a built-in command\n', 1);
        case 'true':
          return const ShellResult();
        case 'false':
          return const ShellResult(exitCode: 1);
        case 'exit':
        case 'logout':
          return const ShellResult(stdout: 'logout\n', exit: true);
        default:
          if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(command)) {
            for (final assignment in argv) {
              final index = assignment.indexOf('=');
              if (index > 0) {
                env[assignment.substring(0, index)] = _expand(
                  assignment.substring(index + 1),
                );
              }
            }
            return const ShellResult();
          }
          return _err(
            '$command: command not found (built-in shell; use SSH for '
            'external programs)\n',
            127,
          );
      }
    } on StateError catch (error) {
      return _err('${error.message}\n', 1);
    } catch (error) {
      return _err('${_message(error)}\n', 1);
    }
  }

  static const _commands = <String>{
    'help',
    'pwd',
    'cd',
    'ls',
    'cat',
    'head',
    'tail',
    'wc',
    'grep',
    'find',
    'echo',
    'mkdir',
    'touch',
    'rm',
    'mv',
    'cp',
    'stat',
    'file',
    'xxd',
    'hexdump',
    'date',
    'whoami',
    'uname',
    'env',
    'export',
    'unset',
    'history',
    'clear',
    'which',
    'true',
    'false',
    'exit',
    'logout',
  };

  static const _helpText =
      'CrispCloud built-in shell\n'
      '\n'
      'File inspection:\n'
      '  pwd, ls [-l] [path], cd [path]\n'
      '  cat, head [-n N], tail [-n N], wc [-lwc]\n'
      '  grep [-invc] PATTERN [file...], find [path] [-name PATTERN]\n'
      '  stat PATH, file PATH, xxd/hexdump [-l N] [file...]\n'
      '\n'
      'Files and directories:\n'
      '  mkdir [-p] DIR..., touch FILE..., rm [-rf] PATH...\n'
      '  cp [-r] SRC... DST, mv SRC... DST\n'
      '\n'
      'Shell:\n'
      '  echo [-n] TEXT..., export NAME=VALUE, unset NAME, env\n'
      '  date, whoami, uname [-a], history, clear, which CMD, exit\n'
      '\n'
      'Pipes (|), input (<) and output (> or >>) work between built-ins.\n'
      'External programs, sudo and background jobs are not available here.\n'
      'Use SSH for a full remote shell, or an unsandboxed desktop build for a\n'
      'host PTY.\n';

  Future<ShellResult> _cd(List<String> args) async {
    final target = args.isEmpty ? await fs.home : await _resolve(args.first);
    if (!await fs.isDirectory(target)) {
      return _err(
        'cd: not a directory: ${args.isEmpty ? target : args.first}\n',
        1,
      );
    }
    cwd = target;
    env['PWD'] = target;
    return const ShellResult();
  }

  Future<ShellResult> _ls(List<String> args) async {
    var long = false;
    String? requested;
    for (final arg in args) {
      if (arg.startsWith('-') && arg.length > 1) {
        if (arg.contains('l')) long = true;
      } else {
        requested = arg;
      }
    }
    final path = await _resolve(requested ?? cwd);
    final entries = <ShellEntry>[];
    if (await fs.isDirectory(path)) {
      entries.addAll(await fs.list(path));
    } else if (await fs.exists(path)) {
      entries.add(await fs.stat(path));
    } else {
      return _err('ls: no such file or directory: ${requested ?? path}\n', 2);
    }
    final out = StringBuffer();
    for (final entry in entries) {
      if (long) {
        final modified = entry.modified;
        final stamp = modified == null
            ? '1970-01-01 00:00'
            : '${modified.year.toString().padLeft(4, '0')}-'
                  '${modified.month.toString().padLeft(2, '0')}-'
                  '${modified.day.toString().padLeft(2, '0')} '
                  '${modified.hour.toString().padLeft(2, '0')}:'
                  '${modified.minute.toString().padLeft(2, '0')}';
        out.writeln(
          '${entry.isDirectory ? 'd' : '-'} '
          '${entry.size.toString().padLeft(9)} $stamp ${entry.name}'
          '${entry.isDirectory ? '/' : ''}',
        );
      } else {
        out.writeln('${entry.name}${entry.isDirectory ? '/' : ''}');
      }
    }
    return _ok(out.toString());
  }

  Future<ShellResult> _cat(List<String> args, String stdin) async {
    if (args.isEmpty) return _ok(stdin);
    final out = StringBuffer();
    for (final arg in args) {
      try {
        out.write(await _readText(await _resolve(arg)));
      } catch (error) {
        return _err('cat: $arg: ${_message(error)}\n', 1);
      }
    }
    return _ok(out.toString());
  }

  Future<ShellResult> _head(
    List<String> args,
    String stdin, {
    required bool fromEnd,
  }) async {
    var count = 10;
    final files = <String>[];
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '-n' && i + 1 < args.length) {
        count = int.tryParse(args[++i]) ?? count;
      } else if (arg.startsWith('-n') && arg.length > 2) {
        count = int.tryParse(arg.substring(2)) ?? count;
      } else if (arg.startsWith('-') &&
          int.tryParse(arg.substring(1)) != null) {
        count = int.parse(arg.substring(1));
      } else {
        files.add(arg);
      }
    }
    final text = files.isEmpty
        ? stdin
        : (await Future.wait(
            files.map((file) async {
              return _readText(await _resolve(file));
            }),
          )).join();
    final lines = text.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    final selected = fromEnd
        ? lines.sublist((lines.length - count).clamp(0, lines.length))
        : lines.take(count).toList();
    return _ok(selected.isEmpty ? '' : '${selected.join('\n')}\n');
  }

  Future<ShellResult> _wc(List<String> args, String stdin) async {
    var linesFlag = false;
    var wordsFlag = false;
    var bytesFlag = false;
    final files = <String>[];
    for (final arg in args) {
      if (arg.startsWith('-') && arg.length > 1) {
        if (arg.contains('l')) linesFlag = true;
        if (arg.contains('w')) wordsFlag = true;
        if (arg.contains('c')) bytesFlag = true;
      } else {
        files.add(arg);
      }
    }
    if (!linesFlag && !wordsFlag && !bytesFlag) {
      linesFlag = true;
      wordsFlag = true;
      bytesFlag = true;
    }
    final out = StringBuffer();
    Future<void> count(String text, String name) async {
      final lineCount =
          '\n'.allMatches(text).length +
          (text.isNotEmpty && !text.endsWith('\n') ? 1 : 0);
      final wordCount = text.trim().isEmpty
          ? 0
          : text.trim().split(RegExp(r'\s+')).length;
      final byteCount = utf8.encode(text).length;
      final values = <String>[
        if (linesFlag) lineCount.toString(),
        if (wordsFlag) wordCount.toString(),
        if (bytesFlag) byteCount.toString(),
      ];
      out.writeln('${values.join(' ')}${name.isEmpty ? '' : ' $name'}');
    }

    if (files.isEmpty) {
      await count(stdin, '');
    } else {
      for (final file in files) {
        await count(await _readText(await _resolve(file)), file);
      }
    }
    return _ok(out.toString());
  }

  Future<ShellResult> _grep(List<String> args, String stdin) async {
    var ignoreCase = false;
    var lineNumbers = false;
    var invert = false;
    var countOnly = false;
    final rest = <String>[];
    for (final arg in args) {
      if (arg.startsWith('-') && arg.length > 1 && rest.isEmpty) {
        if (arg.contains('i')) ignoreCase = true;
        if (arg.contains('n')) lineNumbers = true;
        if (arg.contains('v')) invert = true;
        if (arg.contains('c')) countOnly = true;
      } else {
        rest.add(arg);
      }
    }
    if (rest.isEmpty) return _err('grep: missing pattern\n', 2);
    final pattern = rest.first;
    final files = rest.sublist(1);
    late final RegExp expression;
    try {
      expression = RegExp(pattern, caseSensitive: !ignoreCase);
    } on FormatException catch (error) {
      return _err('grep: ${error.message}\n', 2);
    }
    final sources = files.isEmpty
        ? <String, String>{'': stdin}
        : <String, String>{
            for (final file in files)
              file: await _readText(await _resolve(file)),
          };
    final out = StringBuffer();
    for (final source in sources.entries) {
      var matches = 0;
      final lines = source.value.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final matched = expression.hasMatch(lines[i]) != invert;
        if (!matched) continue;
        matches++;
        if (countOnly) continue;
        final prefix = <String>[
          if (sources.length > 1) source.key,
          if (lineNumbers) '${i + 1}',
        ].join(':');
        out.writeln('${prefix.isEmpty ? '' : '$prefix:'}${lines[i]}');
      }
      if (countOnly) {
        out.writeln('${sources.length > 1 ? '${source.key}:' : ''}$matches');
      }
    }
    return _ok(out.toString());
  }

  Future<ShellResult> _find(List<String> args) async {
    var root = '.';
    String? namePattern;
    for (var i = 0; i < args.length; i++) {
      if (args[i] == '-name' && i + 1 < args.length) {
        namePattern = args[++i];
      } else if (!args[i].startsWith('-')) {
        root = args[i];
      }
    }
    final start = await _resolve(root);
    if (!await fs.exists(start)) {
      return _err('find: no such path: $root\n', 1);
    }
    final expression = namePattern == null
        ? null
        : RegExp(
            '^${namePattern.replaceAll('.', r'\.').replaceAll('*', '.*').replaceAll('?', '.')}\$',
            caseSensitive: false,
          );
    final out = StringBuffer();
    var visited = 0;
    Future<void> walk(String path, int depth) async {
      if (depth > 64 || visited++ > 10000) return;
      final entry = await fs.stat(path);
      final relativeName = path == start ? p.basename(path) : p.basename(path);
      if (expression == null || expression.hasMatch(relativeName)) {
        out.writeln(path);
      }
      if (!entry.isDirectory) return;
      for (final child in await fs.list(path)) {
        await walk(p.join(path, child.name), depth + 1);
      }
    }

    await walk(start, 0);
    return _ok(out.toString());
  }

  ShellResult _echo(List<String> args) {
    var trailingNewline = true;
    final values = <String>[];
    for (final arg in args) {
      if (arg == '-n' && values.isEmpty) {
        trailingNewline = false;
      } else {
        values.add(arg);
      }
    }
    return _ok('${values.join(' ')}${trailingNewline ? '\n' : ''}');
  }

  Future<ShellResult> _mkdir(List<String> args) async {
    var recursive = false;
    final paths = <String>[];
    for (final arg in args) {
      if (arg == '-p') {
        recursive = true;
      } else {
        paths.add(arg);
      }
    }
    if (paths.isEmpty) return _err('mkdir: missing operand\n', 1);
    for (final path in paths) {
      try {
        await fs.createDirectory(await _resolve(path), recursive: recursive);
      } catch (error) {
        return _err('mkdir: $path: ${_message(error)}\n', 1);
      }
    }
    return const ShellResult();
  }

  Future<ShellResult> _touch(List<String> args) async {
    if (args.isEmpty) return _err('touch: missing file operand\n', 1);
    for (final path in args) {
      final resolved = await _resolve(path);
      if (!await fs.exists(resolved)) {
        await fs.writeBytes(resolved, const <int>[]);
      }
    }
    return const ShellResult();
  }

  Future<ShellResult> _rm(List<String> args) async {
    var recursive = false;
    var force = false;
    final paths = <String>[];
    for (final arg in args) {
      if (arg.startsWith('-') && arg.length > 1) {
        if (arg.contains('r') || arg.contains('R')) recursive = true;
        if (arg.contains('f')) force = true;
      } else {
        paths.add(arg);
      }
    }
    if (paths.isEmpty) return _err('rm: missing operand\n', 1);
    for (final path in paths) {
      final resolved = await _resolve(path);
      if (!await fs.exists(resolved)) {
        if (force) continue;
        return _err('rm: $path: no such file or directory\n', 1);
      }
      try {
        await fs.delete(resolved, recursive: recursive);
      } catch (error) {
        return _err('rm: $path: ${_message(error)}\n', 1);
      }
    }
    return const ShellResult();
  }

  Future<ShellResult> _mv(List<String> args) async {
    if (args.length < 2) return _err('mv: missing destination\n', 1);
    final destination = await _resolve(args.last);
    final sources = args.sublist(0, args.length - 1);
    final destinationIsDirectory = await fs.isDirectory(destination);
    for (final source in sources) {
      final from = await _resolve(source);
      final to = destinationIsDirectory
          ? p.join(destination, p.basename(from))
          : destination;
      try {
        await fs.rename(from, to);
      } catch (_) {
        // Cross-filesystem moves: copy then remove.
        try {
          await fs.copy(from, to, recursive: true);
          await fs.delete(from, recursive: true);
        } catch (error) {
          return _err('mv: $source: ${_message(error)}\n', 1);
        }
      }
    }
    return const ShellResult();
  }

  Future<ShellResult> _cp(List<String> args) async {
    var recursive = false;
    final paths = <String>[];
    for (final arg in args) {
      if (arg == '-r' || arg == '-R') {
        recursive = true;
      } else {
        paths.add(arg);
      }
    }
    if (paths.length < 2) return _err('cp: missing destination\n', 1);
    final destination = await _resolve(paths.last);
    final sources = paths.sublist(0, paths.length - 1);
    final destinationIsDirectory = await fs.isDirectory(destination);
    for (final source in sources) {
      final from = await _resolve(source);
      final to = destinationIsDirectory
          ? p.join(destination, p.basename(from))
          : destination;
      try {
        await fs.copy(from, to, recursive: recursive);
      } catch (error) {
        return _err('cp: $source: ${_message(error)}\n', 1);
      }
    }
    return const ShellResult();
  }

  Future<ShellResult> _stat(List<String> args) async {
    if (args.isEmpty) return _err('stat: missing operand\n', 1);
    final out = StringBuffer();
    for (final arg in args) {
      final path = await _resolve(arg);
      final entry = await fs.stat(path);
      out.writeln('  File: $path');
      out.writeln(
        '  Type: ${entry.isDirectory ? 'directory' : 'regular file'}',
      );
      out.writeln('  Size: ${entry.size} bytes');
      out.writeln('Modify: ${entry.modified ?? 'unknown'}');
    }
    return _ok(out.toString());
  }

  Future<ShellResult> _file(List<String> args, String stdin) async {
    if (args.isEmpty && stdin.isEmpty)
      return _err('file: missing operand\n', 1);
    if (args.isEmpty)
      return _ok('standard input: ${_describeBytes(utf8.encode(stdin))}\n');
    final out = StringBuffer();
    for (final arg in args) {
      try {
        final bytes = await fs.readBytes(await _resolve(arg));
        out.writeln('$arg: ${_describeBytes(bytes)}');
      } catch (error) {
        out.writeln('$arg: cannot open (${_message(error)})');
      }
    }
    return _ok(out.toString());
  }

  Future<ShellResult> _hexdump(List<String> args, String stdin) async {
    var limit = 4096;
    final files = <String>[];
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if ((arg == '-l' || arg == '-n') && i + 1 < args.length) {
        limit = int.tryParse(args[++i]) ?? limit;
      } else if (arg.startsWith('-l') && arg.length > 2) {
        limit = int.tryParse(arg.substring(2)) ?? limit;
      } else {
        files.add(arg);
      }
    }
    if (files.isEmpty) {
      final bytes = utf8.encode(stdin);
      return _ok(_hexDump(bytes, limit));
    }
    final out = StringBuffer();
    for (final file in files) {
      final bytes = await fs.readBytes(await _resolve(file));
      if (files.length > 1) out.writeln('==> $file <==');
      out.write(_hexDump(bytes, limit));
      if (bytes.length > limit) {
        out.writeln('... ${bytes.length - limit} more bytes');
      }
    }
    return _ok(out.toString());
  }

  ShellResult _env(List<String> args) {
    if (args.isEmpty) {
      final keys = env.keys.toList()..sort();
      return _ok(keys.map((key) => '$key=${env[key]}').join('\n') + '\n');
    }
    final out = StringBuffer();
    for (final key in args) {
      if (env.containsKey(key)) out.writeln('$key=${env[key]}');
    }
    return _ok(out.toString());
  }

  ShellResult _export(List<String> args) {
    if (args.isEmpty) return _env(const <String>[]);
    for (final assignment in args) {
      final index = assignment.indexOf('=');
      if (index <= 0) continue;
      env[assignment.substring(0, index)] = _expand(
        assignment.substring(index + 1),
      );
    }
    return const ShellResult();
  }

  String _describeBytes(List<int> bytes) {
    if (bytes.isEmpty) return 'empty';
    if (bytes.length >= 4 &&
        bytes[0] == 0x00 &&
        bytes[1] == 0x61 &&
        bytes[2] == 0x73 &&
        bytes[3] == 0x6d) {
      return 'WebAssembly binary';
    }
    if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
      return 'UTF-16 LE text';
    }
    if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
      return 'UTF-16 BE text';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf) {
      return 'UTF-8 text with BOM';
    }
    if (bytes.contains(0)) return 'binary data';
    try {
      final text = utf8.decode(bytes);
      final crlf = '\r\n'.allMatches(text).length;
      final lf = '\n'.allMatches(text).length - crlf;
      final cr = '\r'.allMatches(text).length - crlf;
      final ending = crlf > 0 && lf == 0 && cr == 0
          ? 'CRLF line endings'
          : lf > 0 && crlf == 0 && cr == 0
          ? 'LF line endings'
          : crlf > 0 || lf > 0 || cr > 0
          ? 'mixed line endings'
          : 'no line endings';
      return 'UTF-8 text, $ending';
    } on FormatException {
      return 'binary or non-UTF-8 data';
    }
  }

  String _hexDump(List<int> bytes, int limit) {
    final end = bytes.length < limit ? bytes.length : limit;
    final out = StringBuffer();
    for (var offset = 0; offset < end; offset += 16) {
      final lineEnd = (offset + 16 < end) ? offset + 16 : end;
      final hex = StringBuffer();
      final ascii = StringBuffer();
      for (var i = offset; i < offset + 16; i++) {
        if (i < lineEnd) {
          final value = bytes[i];
          hex.write(value.toRadixString(16).padLeft(2, '0'));
          ascii.write(
            value >= 0x20 && value <= 0x7e ? String.fromCharCode(value) : '.',
          );
        } else {
          hex.write('  ');
          ascii.write(' ');
        }
        if (i % 2 == 1) hex.write(' ');
      }
      out.writeln(
        '${offset.toRadixString(16).padLeft(8, '0')}  '
        '${hex.toString().padRight(40)}  |${ascii.toString()}|',
      );
    }
    if (end == 0) out.writeln('(empty)');
    return out.toString();
  }

  Future<String> _resolve(String path) => fs.normalize(_expand(path), cwd);

  Future<String> _readText(String path) async =>
      utf8.decode(await fs.readBytes(path), allowMalformed: true);

  String _expand(String value) {
    return value.replaceAllMapped(
      RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)'),
      (match) => env[match.group(1) ?? match.group(2)] ?? '',
    );
  }

  List<String> _tokenize(String input) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    String? quote;
    var escaped = false;
    var hasToken = false;
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (escaped) {
        buffer.write(char);
        escaped = false;
        hasToken = true;
        continue;
      }
      if (quote != null) {
        if (char == quote) {
          quote = null;
        } else if (char == '\\' && quote == '"') {
          escaped = true;
        } else {
          buffer.write(char);
        }
        hasToken = true;
        continue;
      }
      if (char == "'" || char == '"') {
        quote = char;
        hasToken = true;
        continue;
      }
      if (char == '\\') {
        escaped = true;
        hasToken = true;
        continue;
      }
      if (char == ' ' || char == '\t') {
        if (hasToken) {
          tokens.add(buffer.toString());
          buffer.clear();
          hasToken = false;
        }
        continue;
      }
      if (char == '|' || char == '>' || char == '<') {
        if (hasToken) {
          tokens.add(buffer.toString());
          buffer.clear();
          hasToken = false;
        }
        if (char == '>' && i + 1 < input.length && input[i + 1] == '>') {
          tokens.add('>>');
          i++;
        } else {
          tokens.add(char);
        }
        continue;
      }
      buffer.write(char);
      hasToken = true;
    }
    if (escaped) buffer.write('\\');
    if (hasToken) tokens.add(buffer.toString());
    return tokens;
  }

  ShellResult _ok(String stdout) => ShellResult(stdout: stdout);
  ShellResult _err(String stderr, int code) =>
      ShellResult(stderr: stderr, exitCode: code);

  String _message(Object error) {
    if (error is StateError) return error.message;
    return error.toString();
  }
}
