// Copyright 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'archive_types.dart';
import 'veracrypt_service.dart';

/// Browser fallback. The crypto service rejects Argon2id and enforces its
/// smaller PBKDF2 budget before deriving. There is no native isolate on this
/// platform: once the bounded synchronous derivation starts it cannot be
/// interrupted. Cancellation is checked both before and after that work.
Future<VeraCryptUnlockedVolume?> unlockVeraCryptHeaderAsync(
  Uint8List header,
  String password, {
  required VeraCryptUnlockOptions options,
  required int containerSizeBytes,
  bool Function()? isCancelled,
}) async {
  void check() {
    if (isCancelled?.call() ?? false) {
      throw const ArchiveViewException('Container opening was cancelled.');
    }
  }

  check();
  await Future<void>.delayed(Duration.zero);
  check();
  final volume = VeraCryptService.unlockHeader(
    header,
    password,
    options: options,
    containerSizeBytes: containerSizeBytes,
  );
  try {
    check();
    return volume;
  } catch (_) {
    volume?.dispose();
    rethrow;
  }
}
