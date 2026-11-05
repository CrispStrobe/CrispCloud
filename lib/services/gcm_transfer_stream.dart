import 'dart:async';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'bounded_transfer_stream.dart';
import 'encryption_service.dart';
import 'transfer_spool.dart';

const _chunkSize = 64 * 1024;
// AES-GCM's existing single-message format permits at most 2^39 - 256 bits.
const maxGcmPlaintextBytes = 68719476704;

Stream<List<int>> encryptGcmTransfer(
  Stream<List<int>> source,
  int length,
  Uint8List key,
  void Function() checkCurrent,
) async* {
  if (length < 0 || length > maxGcmPlaintextBytes) {
    throw ArgumentError.value(
      length,
      'length',
      'Unsupported AES-GCM file size',
    );
  }
  checkCurrent();
  final nonce = EncryptionService.generateNonce();
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
  yield nonce;
  await for (final part in validatedTransferParts(source, length, _chunkSize)) {
    checkCurrent();
    final output = Uint8List(part.length + 32);
    final count = cipher.processBytes(part, 0, part.length, output, 0);
    if (count > 0) yield Uint8List.sublistView(output, 0, count);
  }
  checkCurrent();
  final finalBlock = Uint8List(32);
  final count = cipher.doFinal(finalBlock, 0);
  yield Uint8List.sublistView(finalBlock, 0, count);
}

Stream<List<int>> _decryptToPrivateSpool(
  Stream<List<int>> source,
  Uint8List key,
  void Function() checkCurrent,
) async* {
  GCMBlockCipher? cipher;
  var received = 0;
  Stream<List<int>> body() async* {
    await for (final part in transferParts(source, _chunkSize)) {
      checkCurrent();
      received += part.length;
      if (received > maxGcmPlaintextBytes + 28) {
        throw const FormatException(
          'Encrypted file exceeds the AES-GCM format limit.',
        );
      }
      if (cipher == null) {
        if (part.length < 12) {
          throw const FormatException('Encrypted nonce is truncated.');
        }
        cipher = GCMBlockCipher(AESEngine())
          ..init(
            false,
            AEADParameters(
              KeyParameter(key),
              128,
              Uint8List.sublistView(part, 0, 12),
              Uint8List(0),
            ),
          );
        yield Uint8List.sublistView(part, 12);
      } else {
        yield part;
      }
    }
  }

  // Rechunk after removing the nonce so all intermediate cipher calls are
  // block aligned, independent of the provider's arbitrary network boundaries.
  await for (final part in transferParts(body(), _chunkSize)) {
    checkCurrent();
    if (received < 28) {
      throw const FormatException('Encrypted authentication tag is truncated.');
    }
    final output = Uint8List(part.length + 32);
    final count = cipher!.processBytes(part, 0, part.length, output, 0);
    if (count > 0) yield Uint8List.sublistView(output, 0, count);
  }
  checkCurrent();
  if (received < 28 || cipher == null) {
    throw const FormatException('Encrypted file is truncated.');
  }
  final finalBlock = Uint8List(32);
  final count = cipher!.doFinal(
    finalBlock,
    0,
  ); // Verifies the authentication tag.
  if (count > 0) yield Uint8List.sublistView(finalBlock, 0, count);
}

Future<TransferSpool> createAuthenticatedGcmSpool(
  Stream<List<int>> source,
  Uint8List key,
  void Function() checkCurrent,
) => createTransferSpool(
  _decryptToPrivateSpool(source, key, checkCurrent),
  checkpoint: () async => checkCurrent(),
);

/// Keeps plaintext in an owned temporary file until the complete GCM tag has
/// verified. Cancellation interrupts the upstream subscription even before the
/// first authenticated output chunk is ready. Pausing respects disk and network
/// backpressure, and every success/error/cancellation removes the private spool.
Stream<List<int>> authenticatedGcmDownload(
  Stream<List<int>> source,
  Uint8List key,
  void Function() checkCurrent,
) {
  late StreamController<List<int>> output;
  late StreamController<List<int>> input;
  StreamSubscription<List<int>>? upstream;
  Future<void>? running;
  Completer<void>? resumed;
  var cancelled = false;
  void check() {
    if (cancelled) throw StateError('Encrypted download cancelled.');
    checkCurrent();
  }

  void cancelProvider() {
    final cancellation = upstream?.cancel();
    if (cancellation != null) {
      // An async* provider may be stuck in an uncancellable network future.
      // Its eventual cleanup must not hold our input/spool cleanup hostage.
      unawaited(cancellation.catchError((Object _, StackTrace __) {}));
    }
  }

  Future<void> run() async {
    TransferSpool? spool;
    try {
      spool = await createAuthenticatedGcmSpool(input.stream, key, check);
      check();
      await for (final part in spool.openRead()) {
        await resumed?.future;
        check();
        output.add(part);
      }
    } catch (error, stack) {
      if (!cancelled) output.addError(error, stack);
    } finally {
      await spool?.dispose();
      unawaited(output.close());
    }
  }

  input = StreamController<List<int>>(
    onListen: () {
      upstream = source.listen(
        input.add,
        onError: input.addError,
        onDone: input.close,
      );
      if (output.isPaused) upstream?.pause();
    },
    onPause: () => upstream?.pause(),
    onResume: () => upstream?.resume(),
    onCancel: cancelProvider,
  );
  output = StreamController<List<int>>(
    onListen: () => running = run(),
    onPause: () {
      resumed ??= Completer<void>();
      upstream?.pause();
    },
    onResume: () {
      resumed?.complete();
      resumed = null;
      upstream?.resume();
    },
    onCancel: () async {
      cancelled = true;
      resumed?.complete();
      resumed = null;
      cancelProvider();
      unawaited(input.close());
      await running;
    },
  );
  return output.stream;
}
