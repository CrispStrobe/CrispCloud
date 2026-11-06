import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/sandbox_shell.dart';
import 'package:crisp_cloud/services/sandbox_shell_connection.dart';
import 'package:crisp_cloud/services/sandbox_shell_fs_memory.dart';

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
    await shell.executeLine('cp -r work copy');
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
}
