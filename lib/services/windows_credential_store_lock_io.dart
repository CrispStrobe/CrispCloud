import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../utils/async_lock.dart';

final _localLock = AsyncLock();

Future<T> withWindowsCredentialStoreLock<T>(Future<T> Function() operation) {
  if (!Platform.isWindows) return operation();
  return _localLock.synchronized(() async {
    final directory = await getApplicationSupportDirectory();
    // The plugin reads and rewrites one DPAPI-protected map for every key.
    // Keep the entire operation under a lock shared by app instances.
    final file = File('${directory.path}\\flutter_secure_storage.dat.lock');
    final handle = await file.open(mode: FileMode.append);
    try {
      final deadline = Stopwatch()..start();
      while (true) {
        try {
          await handle.lock(FileLock.exclusive);
          break;
        } on FileSystemException catch (error) {
          const errorLockViolation = 33;
          if (error.osError?.errorCode != errorLockViolation ||
              deadline.elapsed >= const Duration(seconds: 3)) {
            rethrow;
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
      return await operation();
    } finally {
      await handle.close();
    }
  });
}
