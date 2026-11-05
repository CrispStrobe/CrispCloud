import 'dart:io';

import 'package:crisp_cloud/services/native_file_primitives.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'native_copy_primitives_',
    );
  });
  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test(
    'native preallocation reserves blocks and does not claim sparse truncation',
    () async {
      final file = await File(p.join(temporary.path, 'stage')).create();
      const size = 1024 * 1024;
      final allocated = await preallocateNativeFile(file.path, size);
      if (allocated) {
        expect(await file.length(), size);
        if (Platform.isLinux) {
          final result = await Process.run('stat', ['-c', '%b', file.path]);
          expect(result.exitCode, 0);
          expect(
            int.parse(result.stdout.toString().trim()) * 512,
            greaterThanOrEqualTo(size),
          );
        }
      } else {
        expect(await file.length(), 0);
      }
    },
  );

  test('allocation rejects populated files and invalid lengths without changing contents', () async {
    final file = await File(p.join(temporary.path, 'existing'))
        .writeAsString('keep');
    await expectLater(
      preallocateNativeFile(file.path, 1024),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      preallocateNativeFile(file.path, -1),
      throwsArgumentError,
    );
    expect(await file.readAsString(), 'keep');
  });

  test(
    'native clone preserves bytes and independent subsequent writes',
    () async {
      final source = await File(p.join(temporary.path, 'source'))
          .writeAsString('independent copy contents');
      final target = File(p.join(temporary.path, 'clone'));
      final cloned = await cloneNativeFile(source.path, target.path);
      if (cloned) {
        expect(await target.readAsString(), 'independent copy contents');
        await target.writeAsString('changed clone');
        expect(await source.readAsString(), 'independent copy contents');
      } else {
        expect(await target.exists(), isFalse);
      }
    },
  );

  test('native clone never replaces an existing destination', () async {
    final source = await File(p.join(temporary.path, 'source'))
        .writeAsString('source');
    final target = await File(p.join(temporary.path, 'target'))
        .writeAsString('existing');
    await expectLater(
      cloneNativeFile(source.path, target.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(await target.readAsString(), 'existing');
    expect(await source.readAsString(), 'source');
  });

  test(
    'native permissions and clone inspection never follow a symbolic link',
    () async {
      final file = await File(p.join(temporary.path, 'file'))
          .writeAsString('contents');
      await setNativeFileMode(file.path, 0x1a0); // 0640
      expect((await file.stat()).mode & 0x1ff, 0x1a0);
      final link = await Link(p.join(temporary.path, 'link')).create(file.path);
      await expectLater(
        setNativeFileMode(link.path, 0x1ff),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        cloneNativeFile(link.path, p.join(temporary.path, 'clone')),
        throwsA(isA<FileSystemException>()),
      );
      expect((await file.stat()).mode & 0x1ff, 0x1a0);
    },
    skip: !supportsNativePermissions,
  );
}
