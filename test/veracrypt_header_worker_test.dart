@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/veracrypt_header_worker.dart';
import 'package:crisp_cloud/services/veracrypt_header_worker_io.dart' as native;
import 'package:crisp_cloud/services/veracrypt_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/veracrypt_container_fixture.dart';

const _quick = VeraCryptUnlockOptions(
  trueCryptMode: true,
  kdf: VeraCryptKdf.sha512,
);

// This is a valid, explicitly budgeted production configuration. It would
// require 19,015,000 PBKDF2 iterations; cancellation must stop the real work,
// not simply reject an invalid option or wait for a tiny fixture derivation.
const _expensive = VeraCryptUnlockOptions(
  kdf: VeraCryptKdf.sha512,
  pim: 19000,
  maxPbkdf2Iterations: 20000000,
);

void main() {
  final container = veraCryptContainerFixture();
  final header = Uint8List.sublistView(container, 0, 512);

  Future<VeraCryptUnlockedVolume?> open({
    VeraCryptUnlockOptions options = _quick,
    bool Function()? isCancelled,
  }) => unlockVeraCryptHeaderAsync(
    header,
    veraCryptFixturePassword,
    options: options,
    containerSizeBytes: container.length,
    isCancelled: isCancelled,
  );

  tearDown(() => native.debugOnVeraCryptHeaderWorkerStarted = null);

  test('a native worker transfers an owned unlocked volume', () async {
    final volume = await open();
    expect(volume, isNotNull);
    expect(volume!.header.trueCryptMode, isTrue);
    expect(volume.isClosed, isFalse);
    volume.dispose();
    expect(volume.isClosed, isTrue);
  });

  test('already cancelled attempts never start a worker', () async {
    var starts = 0;
    native.debugOnVeraCryptHeaderWorkerStarted = () => starts++;
    await expectLater(
      open(options: _expensive, isCancelled: () => true),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(starts, 0);
  });

  test(
    'running cancellation stops the KDF before the next queued unlock',
    () async {
      var cancelled = false;
      var starts = 0;
      final firstStarted = Completer<void>();
      native.debugOnVeraCryptHeaderWorkerStarted = () {
        starts++;
        if (!firstStarted.isCompleted) firstStarted.complete();
      };
      final expensive = open(options: _expensive, isCancelled: () => cancelled);
      final rejected = expectLater(
        expensive,
        throwsA(isA<ArchiveViewException>()),
      );
      addTearDown(() {
        cancelled = true;
      });
      await firstStarted.future.timeout(const Duration(seconds: 10));
      final next = open();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(starts, 1, reason: 'The second KDF must remain queued.');
      cancelled = true;
      await rejected.timeout(const Duration(seconds: 2));
      final volume = await next.timeout(const Duration(seconds: 5));
      expect(volume, isNotNull);
      volume?.dispose();
      expect(starts, 2);
    },
  );

  test('queued cancellation is prompt and never allocates its KDF', () async {
    var firstCancelled = false;
    var queuedCancelled = false;
    var starts = 0;
    final firstStarted = Completer<void>();
    native.debugOnVeraCryptHeaderWorkerStarted = () {
      starts++;
      if (!firstStarted.isCompleted) firstStarted.complete();
    };
    final first = open(options: _expensive, isCancelled: () => firstCancelled);
    final firstRejected = expectLater(
      first,
      throwsA(isA<ArchiveViewException>()),
    );
    addTearDown(() {
      firstCancelled = true;
      queuedCancelled = true;
    });
    await firstStarted.future.timeout(const Duration(seconds: 10));
    final queued = open(
      options: _expensive,
      isCancelled: () => queuedCancelled,
    );
    final queuedRejected = expectLater(
      queued,
      throwsA(isA<ArchiveViewException>()),
    );
    final next = open();
    queuedCancelled = true;
    await queuedRejected.timeout(const Duration(seconds: 2));
    expect(starts, 1);
    firstCancelled = true;
    await firstRejected.timeout(const Duration(seconds: 2));
    final volume = await next.timeout(const Duration(seconds: 5));
    expect(volume, isNotNull);
    volume?.dispose();
    expect(starts, 2, reason: 'The cancelled queued job must never start.');
  });

  test(
    'worker configuration and resource errors preserve their types',
    () async {
      await expectLater(
        open(options: const VeraCryptUnlockOptions(pim: -1)),
        throwsArgumentError,
      );
      await expectLater(
        open(
          options: const VeraCryptUnlockOptions(
            kdf: VeraCryptKdf.argon2id,
            maxArgon2MemoryKiB: 65536,
          ),
        ),
        throwsA(isA<VeraCryptResourceLimitException>()),
      );
      final volume = await open();
      expect(
        volume,
        isNotNull,
        reason: 'An error must release the worker slot.',
      );
      volume?.dispose();
    },
  );

  test('worker keyfile cleanup leaves caller-owned bytes unchanged', () async {
    final keyfile = Uint8List.fromList([1, 2, 3, 4, 5]);
    final volume = await open(
      options: VeraCryptUnlockOptions(
        kdf: VeraCryptKdf.sha512,
        trueCryptMode: true,
        keyfiles: [keyfile],
      ),
    );
    expect(volume, isNull, reason: 'This fixture has no keyfile.');
    expect(keyfile, [1, 2, 3, 4, 5]);
  });
}
