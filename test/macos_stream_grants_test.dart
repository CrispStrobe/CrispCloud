import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:crisp_cloud/services/local_file_service_native.dart';

class _Scopes extends Fake implements SecureBookmarks {
  final held = <String, int>{};
  @override
  Future<bool> startAccessingSecurityScopedResource(
    FileSystemEntity entity,
  ) async {
    held.update(entity.path, (n) => n + 1, ifAbsent: () => 1);
    return true;
  }

  @override
  Future<bool> stopAccessingSecurityScopedResource(
    FileSystemEntity entity,
  ) async {
    final n = held[entity.path] ?? 0;
    expect(
      n,
      greaterThan(0),
      reason: 'Every scope release must match an acquisition',
    );
    if (n == 1) {
      held.remove(entity.path);
    } else {
      held[entity.path] = n - 1;
    }
    return true;
  }
}

void main() {
  test('closing either viewer cannot release a concurrent reader in another folder', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'crisp-scope-readers-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final a = await Directory('${temporary.path}/a').create();
    final b = await Directory('${temporary.path}/b').create();
    final af = await File('${a.path}/one.txt').writeAsString('first');
    final bf = await File('${b.path}/two.txt').writeAsString('second');
    final scopes = _Scopes();
    final service = MacosFileService(
      bookmarks: scopes,
      resolveBookmarks: () async => [
        Directory(await a.resolveSymbolicLinks()),
        Directory(await b.resolveSymbolicLinks()),
      ],
    );
    expect(await service.beginStreamAccess(af.path), isTrue);
    expect(await service.beginStreamAccess(bf.path), isTrue);
    expect(scopes.held, hasLength(2));
    await service.endStreamAccess();
    expect(scopes.held, hasLength(2));
    await service.endStreamAccess();
    expect(scopes.held, isEmpty);
    await service.endStreamAccess();
    expect(scopes.held, isEmpty);
  });
}
