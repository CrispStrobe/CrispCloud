import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/sandbox_shell.dart';
import 'package:crisp_cloud/services/sandbox_shell_connection.dart';
import 'package:crisp_cloud/services/sandbox_shell_fs_memory.dart';

class _BlockingReadFs extends MemorySandboxShellFs {
  final reading = Completer<void>();
  final completeRead = Completer<List<int>>();

  @override
  Future<List<int>> readBytes(String path) {
    if (!reading.isCompleted) reading.complete();
    return completeRead.future;
  }
}

class _FailedRenameFs extends MemorySandboxShellFs {
  var copies = 0;
  var deletes = 0;

  @override
  Future<void> rename(String from, String to) async {
    throw StateError('Permission denied');
  }

  @override
  Future<void> copy(String from, String to, {bool recursive = false}) async {
    copies++;
    await super.copy(from, to, recursive: recursive);
  }

  @override
  Future<void> delete(String path, {bool recursive = false}) async {
    deletes++;
    await super.delete(path, recursive: recursive);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemorySandboxShellFs fs;
  late SandboxShell shell;

  setUp(() {
    fs = MemorySandboxShellFs();
    shell = SandboxShell(fs: fs, cwd: '/home/user');
  });

  test('navigation and file commands work without a host process', () async {
    expect((await shell.executeLine('pwd')).stdout.trim(), '/home/user');
    expect(
      (await shell.executeLine('echo hello world')).stdout.trim(),
      'hello world',
    );

    expect((await shell.executeLine('mkdir work')).exitCode, 0);
    expect((await shell.executeLine('cd work')).exitCode, 0);
    expect((await shell.executeLine('pwd')).stdout.trim(), '/home/user/work');

    final redirected = await shell.executeLine('echo "a b" > note.txt');
    expect(redirected.exitCode, 0);
    expect((await shell.executeLine('cat note.txt')).stdout.trim(), 'a b');
    expect(
      (await shell.executeLine('wc -l note.txt')).stdout.trim(),
      '1 note.txt',
    );
    expect(
      (await shell.executeLine('file note.txt')).stdout,
      contains('LF line endings'),
    );

    final dump = await shell.executeLine('xxd note.txt');
    expect(dump.stdout, contains('6120 620a'));

    await shell.executeLine('cd ..');
    expect((await shell.executeLine('cp -r work copy')).exitCode, 0);
    expect((await shell.executeLine('cat copy/note.txt')).stdout.trim(), 'a b');
    await shell.executeLine('mv copy moved');
    expect(
      (await shell.executeLine('cat moved/note.txt')).stdout.trim(),
      'a b',
    );
    expect(
      (await shell.executeLine('find . -name "*.txt"')).stdout,
      contains('moved/note.txt'),
    );
    await shell.executeLine('rm -rf moved work');
    expect((await shell.executeLine('ls')).stdout, isNot(contains('moved/')));
  });

  test(
    'line-ending inspection distinguishes CRLF, LF and mixed files',
    () async {
      await fs.writeBytes('/home/user/lf.txt', utf8.encode('a\nb\n'));
      await fs.writeBytes('/home/user/crlf.txt', utf8.encode('a\r\nb\r\n'));
      await fs.writeBytes('/home/user/mixed.txt', utf8.encode('a\nb\r\n'));

      expect(
        (await shell.executeLine('file lf.txt')).stdout,
        contains('LF line endings'),
      );
      expect(
        (await shell.executeLine('file crlf.txt')).stdout,
        contains('CRLF line endings'),
      );
      expect(
        (await shell.executeLine('file mixed.txt')).stdout,
        contains('mixed line endings'),
      );
    },
  );

  test('pipelines, grep and unknown commands', () async {
    await fs.writeBytes(
      '/home/user/lines.txt',
      utf8.encode('alpha\nbeta\nGamma\n'),
    );
    expect(
      (await shell.executeLine('cat lines.txt | grep -i gamma')).stdout.trim(),
      'Gamma',
    );
    expect(
      (await shell.executeLine('grep -n beta lines.txt')).stdout.trim(),
      '2:beta',
    );
    final missing = await shell.executeLine('python3');
    expect(missing.exitCode, 127);
    expect(missing.stderr, contains('command not found'));
  });

  test(
    'quoted, escaped and expanded operators remain literal arguments',
    () async {
      await fs.writeBytes('/home/user/keep.txt', utf8.encode('unchanged'));
      for (final command in [
        "echo '|' rm keep.txt",
        'echo "|" rm keep.txt',
        r'echo \| rm keep.txt',
      ]) {
        final result = await shell.executeLine(command);
        expect(result.exitCode, 0);
        expect(result.stdout, '| rm keep.txt\n');
        expect(
          utf8.decode(await fs.readBytes('/home/user/keep.txt')),
          'unchanged',
        );
      }
      for (final operator in ['>', '>>', '<']) {
        final result = await shell.executeLine("echo '$operator' keep.txt");
        expect(result.stdout, '$operator keep.txt\n');
        expect(
          utf8.decode(await fs.readBytes('/home/user/keep.txt')),
          'unchanged',
        );
      }
      shell.env['OP'] = '|';
      expect(
        (await shell.executeLine(r'echo "$OP" rm keep.txt')).stdout,
        '| rm keep.txt\n',
      );
      expect(await fs.exists('/home/user/keep.txt'), isTrue);
      expect((await shell.executeLine(r"echo '$HOME'")).stdout, '\$HOME\n');
      expect((await shell.executeLine(r'echo \$HOME')).stdout, '\$HOME\n');
      expect((await shell.executeLine(r'echo "$HOME"')).stdout, '/home/user\n');
    },
  );

  test(
    'invalid syntax is rejected before an earlier command can mutate files',
    () async {
      await fs.writeBytes('/home/user/keep.txt', utf8.encode('unchanged'));
      for (final command in [
        'rm keep.txt |',
        'rm keep.txt >',
        'rm keep.txt > > output.txt',
        'rm keep.txt "unfinished',
        'rm keep.txt \\',
      ]) {
        final result = await shell.executeLine(command);
        expect(result.exitCode, 2, reason: command);
        expect(await fs.exists('/home/user/keep.txt'), isTrue, reason: command);
      }
    },
  );

  test('empty operands and unsupported rm flags cannot delete the working directory', () async {
    await fs.writeBytes('/home/user/keep.txt', utf8.encode('unchanged'));
    for (final command in [
      r'rm -rf "$UNDEFINED"',
      "rm -rf ''",
      'rm --invalid keep.txt',
    ]) {
      final result = await shell.executeLine(command);
      expect(result.exitCode, isNot(0));
      expect(await fs.exists('/home/user/keep.txt'), isTrue);
    }
    expect((await shell.executeLine("touch ' padded.txt '")).exitCode, 0);
    expect(await fs.exists('/home/user/ padded.txt '), isTrue);
    expect(await fs.exists('/home/user/padded.txt'), isFalse);
    await fs.writeBytes('/home/user/-file', [7]);
    expect((await shell.executeLine('rm -- -file')).exitCode, 0);
    expect(await fs.exists('/home/user/-file'), isFalse);
  });

  for (final command in ['cp', 'mv']) {
    test(
      '$command rejects multiple sources unless destination is a directory',
      () async {
        await fs.writeBytes('/home/user/a', [1]);
        await fs.writeBytes('/home/user/b', [2]);
        for (final existing in [false, true]) {
          if (existing) await fs.writeBytes('/home/user/destination', [3]);
          final result = await shell.executeLine('$command a b destination');
          expect(result.exitCode, isNot(0));
          expect(await fs.readBytes('/home/user/a'), [1]);
          expect(await fs.readBytes('/home/user/b'), [2]);
          expect(await fs.exists('/home/user/destination'), existing);
          if (existing)
            expect(await fs.readBytes('/home/user/destination'), [3]);
        }
      },
    );
  }

  test(
    'memory directory copy snapshots all children and rejects overlap',
    () async {
      await fs.writeBytes('/home/user/source/a', [1]);
      await fs.writeBytes('/home/user/source/nested/b', [2]);
      expect((await shell.executeLine('cp -r source copy')).exitCode, 0);
      expect(await fs.readBytes('/home/user/copy/a'), [1]);
      expect(await fs.readBytes('/home/user/copy/nested/b'), [2]);
      for (final command in [
        'cp -r source source/child',
        'mv source source/child',
        'cp source/a source/a',
      ]) {
        expect((await shell.executeLine(command)).exitCode, isNot(0));
        expect(await fs.readBytes('/home/user/source/a'), [1]);
        expect(await fs.exists('/home/user/source/child'), isFalse);
      }
    },
  );

  test(
    'a failed rename never invokes a generic copy-delete fallback',
    () async {
      final failed = _FailedRenameFs();
      await failed.writeBytes('/home/user/a', [1]);
      final failingShell = SandboxShell(fs: failed, cwd: '/home/user');
      expect((await failingShell.executeLine('mv a b')).exitCode, isNot(0));
      expect(failed.copies, 0);
      expect(failed.deletes, 0);
      expect(await failed.readBytes('/home/user/a'), [1]);
      expect(await failed.exists('/home/user/b'), isFalse);
    },
  );

  test('terminal connection echoes, executes and exits cleanly', () async {
    final connection = SandboxShellConnection(shell);
    final output = StringBuffer();
    final done = Completer<void>();
    connection.output.listen(output.write, onDone: done.complete);
    await connection.write('echo from-terminal\r');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(output.toString(), contains('from-terminal'));
    expect(output.toString(), contains('user@crispcloud'));

    await connection.write('exit\r');
    await done.future.timeout(const Duration(seconds: 2));
    expect(await connection.exitCode, 0);
  });

  test(
    'connection preserves an escape sequence split between writes',
    () async {
      final connection = SandboxShellConnection(shell);
      final output = StringBuffer();
      connection.output.listen(output.write);
      await connection.write('echo ac');
      await connection.write('\x1b[');
      await connection.write('D');
      await connection.write('b\r');
      await Future<void>.delayed(Duration.zero);
      expect(output.toString(), contains('\r\nabc\r\n'));
      await connection.close();
    },
  );

  test(
    'close waits for an accepted filesystem command and skips queued input',
    () async {
      final blocked = _BlockingReadFs();
      final connection = SandboxShellConnection(
        SandboxShell(fs: blocked, cwd: '/home/user'),
      );
      final output = StringBuffer();
      final errors = <Object>[];
      connection.output.listen(output.write, onError: errors.add);
      final write = connection.write('cat large.txt\r');
      await blocked.reading.future;
      final queued = connection.write('touch after-close\r');
      var finished = false;
      final closed = connection.close().then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      blocked.completeRead.complete(utf8.encode('late result'));
      await Future.wait([write, queued, closed]);
      expect(await blocked.exists('/home/user/after-close'), isFalse);
      expect(output.toString(), isNot(contains('late result')));
      expect(errors, isEmpty);
      expect(await connection.exitCode, 0);
    },
  );

  test(
    'a cancelled connection closes without ever attaching a listener',
    () async {
      final connection = SandboxShellConnection(shell);
      await connection.close().timeout(const Duration(seconds: 1));
      expect(await connection.exitCode, 0);
      expect(await connection.output.toList(), isEmpty);
    },
  );
}
