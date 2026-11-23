@TestOn('windows')
library;

import 'dart:io';

import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter/foundation.dart';
// The test exercises the same Windows plugin that the release registers.
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_windows/flutter_secure_storage_windows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows probes and writes share the lock for the DPAPI map', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'crisp_dpapi_test_',
    );
    final previousPaths = PathProviderPlatform.instance;
    final previousPlatform = debugDefaultTargetPlatformOverride;
    PathProviderPlatform.instance = _Paths(temporary.path);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    FlutterSecureStorageWindows.registerWith();
    addTearDown(() async {
      PathProviderPlatform.instance = previousPaths;
      debugDefaultTargetPlatformOverride = previousPlatform;
      await temporary.delete(recursive: true);
    });

    final first = PlatformSecureStorage();
    final second = PlatformSecureStorage();
    await first.write('preserved', 'test value');

    final lock = File(
      p.join(temporary.path, 'flutter_secure_storage.dat.lock'),
    );
    final otherHandle = await lock.open(mode: FileMode.append);
    await otherHandle.lock(FileLock.exclusive);
    var entered = false;
    final waiting = first.read('preserved').then((value) {
      entered = true;
      return value;
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(entered, isFalse);
    } finally {
      await otherHandle.close();
    }
    expect(await waiting, 'test value');

    await Future.wait([
      first.verifyAvailable(),
      second.verifyAvailable(),
      for (var index = 0; index < 10; index++)
        (index.isEven ? first : second).write('key-$index', 'value-$index'),
    ]);

    expect(await first.read('preserved'), 'test value');
    for (var index = 0; index < 10; index++) {
      expect(await second.read('key-$index'), 'value-$index');
    }
  });
}

class _Paths extends PathProviderPlatform {
  _Paths(this.directory);

  final String directory;

  @override
  Future<String?> getApplicationSupportPath() async => directory;
}
