import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:crisp_cloud/services/native_file_primitives.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('crisp-exclusive-');
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'exclusive rename keeps an occupied destination and source intact',
    () async {
      final source = File(p.join(root.path, 'source'));
      final destination = File(p.join(root.path, 'destination'));
      await source.writeAsString('new');
      await destination.writeAsString('old');
      await expectLater(
        moveNativeNoReplace(source.path, destination.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await source.readAsString(), 'new');
      expect(await destination.readAsString(), 'old');
    },
    skip: !supportsNativeExclusiveRename,
  );

  test('exclusive rename moves files and nonempty directories', () async {
    final source = Directory(p.join(root.path, 'source'));
    await source.create();
    await File(p.join(source.path, 'payload')).writeAsString('value');
    final destination = p.join(root.path, 'destination');
    expect(await moveNativeNoReplace(source.path, destination), isTrue);
    expect(await source.exists(), isFalse);
    expect(await File(p.join(destination, 'payload')).readAsString(), 'value');
    final finalPath = p.join(root.path, 'final');
    expect(
      await moveNativeNoReplace(p.join(destination, 'payload'), finalPath),
      isTrue,
    );
    expect(await File(finalPath).readAsString(), 'value');
  }, skip: !supportsNativeExclusiveRename);

  test(
    'exclusive rename preserves a symbolic link without following it',
    () async {
      final target = File(p.join(root.path, 'target'));
      await target.writeAsString('value');
      final source = Link(p.join(root.path, 'link'));
      await source.create('target');
      final destination = p.join(root.path, 'renamed');
      expect(await moveNativeNoReplace(source.path, destination), isTrue);
      expect(await Link(destination).target(), 'target');
      expect(await target.readAsString(), 'value');
    },
    skip: Platform.isWindows || !supportsNativeExclusiveRename,
  );
}
