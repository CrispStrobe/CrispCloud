import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/services/sandbox_shell.dart';
import 'package:crisp_cloud/services/sandbox_shell_fs_io.dart';

void main() {
  late Directory temporary;
  late IoSandboxShellFs files;
  late SandboxShell shell;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('sandbox_shell_fs_');
    files = IoSandboxShellFs();
    shell = SandboxShell(fs: files, cwd: temporary.path);
  });
  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  Future<void> write(String relative, List<int> bytes) =>
      files.writeBytes(p.join(temporary.path, relative), bytes);

  test('native directory copy retains every child and rejects self or descendant targets', () async {
    await write('source/a', [1]);
    await write('source/nested/b', [2]);
    expect((await shell.executeLine('cp -r source copy')).exitCode, 0);
    expect(await files.readBytes(p.join(temporary.path, 'copy/a')), [1]);
    expect(await files.readBytes(p.join(temporary.path, 'copy/nested/b')), [2]);
    for (final command in [
      'cp -r source source/child',
      'cp -r source .',
      'mv source source/child',
      'cp source/a source/a',
    ]) {
      expect(
        (await shell.executeLine(command)).exitCode,
        isNot(0),
        reason: command,
      );
      expect(await files.readBytes(p.join(temporary.path, 'source/a')), [1]);
      expect(
        await files.exists(p.join(temporary.path, 'source/child')),
        isFalse,
      );
    }
  });

  for (final command in ['cp', 'mv']) {
    test(
      'native $command cannot overwrite a destination with multiple sources',
      () async {
        await write('a', [1]);
        await write('b', [2]);
        await write('destination', [3]);
        expect(
          (await shell.executeLine('$command a b destination')).exitCode,
          isNot(0),
        );
        expect(await files.readBytes(p.join(temporary.path, 'a')), [1]);
        expect(await files.readBytes(p.join(temporary.path, 'b')), [2]);
        expect(await files.readBytes(p.join(temporary.path, 'destination')), [
          3,
        ]);
      },
    );
  }

  test(
    'canonical destination checks reject a symlink back into the source',
    () async {
      await write('source/a', [1]);
      await Link(p.join(temporary.path, 'alias'))
          .create(p.join(temporary.path, 'source'));
      expect(
        (await shell.executeLine('cp -r source alias/child')).exitCode,
        isNot(0),
      );
      expect(
        await files.exists(p.join(temporary.path, 'source/child')),
        isFalse,
      );
      expect(await files.readBytes(p.join(temporary.path, 'source/a')), [1]);
    },
    skip: Platform.isWindows,
  );

  test('link copies preserve targets and deleting a link preserves the target directory', () async {
    await write('target/keep', [9]);
    final link = Link(p.join(temporary.path, 'link'));
    await link.create(p.join(temporary.path, 'target'));
    await files.copy(link.path, p.join(temporary.path, 'copy'));
    expect(
      await Link(p.join(temporary.path, 'copy')).target(),
      await link.target(),
    );
    expect((await shell.executeLine('rm -rf link')).exitCode, 0);
    expect(await files.readBytes(p.join(temporary.path, 'target/keep')), [9]);
    expect(await files.exists(link.path), isFalse);
  }, skip: Platform.isWindows);

  test('dangling links can be copied, renamed and removed as links', () async {
    final broken = Link(p.join(temporary.path, 'broken'));
    await broken.create(p.join(temporary.path, 'missing'));
    expect(await files.exists(broken.path), isTrue);
    await files.copy(broken.path, p.join(temporary.path, 'copy'));
    await files.rename(broken.path, p.join(temporary.path, 'renamed'));
    expect(
      await Link(p.join(temporary.path, 'renamed')).target(),
      p.join(temporary.path, 'missing'),
    );
    expect((await shell.executeLine('rm copy renamed')).exitCode, 0);
    expect(await files.exists(p.join(temporary.path, 'copy')), isFalse);
    expect(await files.exists(p.join(temporary.path, 'renamed')), isFalse);
  }, skip: Platform.isWindows);
}
