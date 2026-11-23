import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/async_lock.dart';

final _localLock = AsyncLock();

Future<T> withWindowsCredentialStoreLock<T>(Future<T> Function() operation) {
  // Follow the platform the storage plugin targets: tests on a Windows host
  // that override the target platform must not take the Windows file lock.
  if (!Platform.isWindows || defaultTargetPlatform != TargetPlatform.windows) {
    return operation();
  }
  return _localLock.synchronized(() async {
    final Directory directory;
    try {
      directory = await getApplicationSupportDirectory();
    } on MissingPluginException {
      // No registered path provider means no other app instance shares the
      // store (headless tests); the in-process lock still serializes access.
      return operation();
    }
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
