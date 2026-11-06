// macOS symlink handling for local file access.
//
// A symlink can live under a granted folder while its target lives on another
// volume. Access checks and I/O must resolve the target so the app asks for
// the right folder instead of trusting the link's path.

import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/local_file_service_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  test(
    'macOS access accepts a new output in an accessible unbookmarked parent',
    () async {
      final temp = await Directory.systemTemp.createTemp('crisp-new-output-');
      addTearDown(() => temp.delete(recursive: true));
      final path = '${temp.path}/new.txt';
      final service = MacosFileService();
      expect(await service.hasAccessToPath(path), isTrue);
      await service.withFileOperationAccess(
        path,
        () => File(path).writeAsString('new data'),
      );
      expect(await File(path).readAsString(), 'new data');
    },
  );

  test(
    'macOS new-output access resolves an ancestor symlink before probing',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'crisp-new-linked-output-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final parent = await Directory('${temp.path}/real').create();
      final link = await Link('${temp.path}/alias').create(parent.path);
      final path = '${link.path}/new.txt';
      final service = MacosFileService();
      expect(await service.hasAccessToPath(path), isTrue);
      await service.withFileOperationAccess(
        path,
        () => File(path).writeAsString('through parent link'),
      );
      expect(
        await File('${parent.path}/new.txt').readAsString(),
        'through parent link',
      );
      expect(await Link(link.path).exists(), isTrue);
      // A lexical parent is insufficient when its actual target does not exist.
      await link.delete();
      await link.create('${temp.path}/missing');
      expect(await service.hasAccessToPath(path), isFalse);
    },
    skip: Platform.isWindows,
  );

  test('macOS new-output access rejects a regular-file parent', () async {
    final temp = await Directory.systemTemp.createTemp('crisp-invalid-parent-');
    addTearDown(() => temp.delete(recursive: true));
    final parent = await File('${temp.path}/file').writeAsString('retain');
    expect(
      await MacosFileService().hasAccessToPath('${parent.path}/new.txt'),
      isFalse,
    );
    expect(await parent.readAsString(), 'retain');
  });

  test('macOS new-output access rejects an inaccessible parent', () async {
    final temp = await Directory.systemTemp.createTemp('crisp-denied-parent-');
    addTearDown(() async {
      await Process.run('chmod', ['700', temp.path]);
      await temp.delete(recursive: true);
    });
    final result = await Process.run('chmod', ['000', temp.path]);
    expect(result.exitCode, 0);
    expect(
      await MacosFileService().hasAccessToPath('${temp.path}/new.txt'),
      isFalse,
    );
  }, skip: !Platform.isMacOS);

  test(
    'macOS local service reads, stats and writes through a symlink',
    () async {
      if (!Platform.isMacOS) {
        return;
      }

      final temp = await Directory.systemTemp.createTemp('crisp-symlink-');
      addTearDown(() async {
        try {
          await temp.delete(recursive: true);
        } catch (_) {
          // Best effort.
        }
      });

      final target = File('${temp.path}/target.txt');
      await target.writeAsString('target contents');
      final link = Link('${temp.path}/link.txt');
      await link.create(target.path);

      final service = MacosFileService();
      expect(await service.readFile(link.path), utf8Bytes('target contents'));
      expect(await service.fileLength(link.path), target.lengthSync());
      expect(await service.hasAccessToPath(link.path), isTrue);

      await service.saveFile(link.path, utf8Bytes('updated contents'));
      expect(await target.readAsString(), 'updated contents');
      expect(
        await FileSystemEntity.type(link.path, followLinks: false),
        FileSystemEntityType.link,
      );
    },
  );
}

Uint8List utf8Bytes(String value) => Uint8List.fromList(value.codeUnits);
