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
