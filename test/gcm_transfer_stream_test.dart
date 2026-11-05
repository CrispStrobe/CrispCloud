import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/services/encryption_service.dart';
import 'package:crisp_cloud/services/gcm_transfer_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  Future<Uint8List> collect(Stream<List<int>> source) async {
    final result = BytesBuilder();
    await for (final part in source) {
      result.add(part);
    }
    return result.takeBytes();
  }

  Stream<List<int>> split(List<int> bytes, int size) async* {
    for (var start = 0; start < bytes.length; start += size) {
      yield bytes.sublist(start, (start + size).clamp(0, bytes.length));
    }
  }

  for (final size in [0, 1, 15, 16, 17, 65535, 65536, 65537, 131073]) {
    test('chunked GCM retains existing format at length $size', () async {
      final plain = Uint8List.fromList(List.generate(size, (i) => i % 251));
      final encrypted = await collect(
        encryptGcmTransfer(split(plain, 31), size, key, () {}),
      );
      expect(encrypted.length, plain.length + 28);
      expect(EncryptionService.decrypt(encrypted, key), plain);
      final restored = await collect(
        authenticatedGcmDownload(split(encrypted, 29), key, () {}),
      );
      expect(restored, plain);
    });
  }
  test(
    'invalid final tag exposes no plaintext, even after full preceding blocks',
    () async {
      final encrypted = EncryptionService.encrypt(Uint8List(200000), key);
      encrypted.last ^= 1;
      var exposed = 0;
      await expectLater(
        authenticatedGcmDownload(split(encrypted, 4000), key, () {}).map((
          part,
        ) {
          exposed += part.length;
          return part;
        }).drain<void>(),
        throwsA(isA<Exception>()),
      );
      expect(exposed, 0);
    },
  );
  test(
    'consumer cancellation interrupts source before authenticated output',
    () async {
      final cancelled = Completer<void>();
      final source = StreamController<List<int>>(
        onCancel: () => cancelled.complete(),
      );
      final subscription = authenticatedGcmDownload(source.stream, key, () {})
          .listen((_) {
            fail('No plaintext may be released from an incomplete message.');
          });
      source.add(List.filled(20, 0));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await subscription.cancel().timeout(const Duration(seconds: 2));
      await cancelled.future;
      await source.close();
    },
  );
  test('truncated nonce or tag is rejected without output', () async {
    for (final size in [0, 1, 11, 12, 27]) {
      await expectLater(
        authenticatedGcmDownload(
          Stream.value(Uint8List(size)),
          key,
          () {},
        ).drain<void>(),
        throwsA(isA<Exception>()),
      );
    }
  });
  test(
    'declared plaintext length is checked before a final encryption tag',
    () async {
      await expectLater(
        encryptGcmTransfer(Stream.value([1, 2]), 3, key, () {}).drain<void>(),
        throwsStateError,
      );
      await expectLater(
        encryptGcmTransfer(Stream.value([1, 2]), 1, key, () {}).drain<void>(),
        throwsStateError,
      );
    },
  );
  test(
    'account changes during decrypt cannot release authenticated plaintext',
    () async {
      var valid = true;
      final encrypted = EncryptionService.encrypt(Uint8List(131073), key);
      Stream<List<int>> source() async* {
        yield encrypted.sublist(0, 65536);
        valid = false;
        yield encrypted.sublist(65536);
      }

      var exposed = 0;
      await expectLater(
        authenticatedGcmDownload(source(), key, () {
          if (!valid) throw StateError('Account changed');
        }).map((part) {
          exposed += part.length;
          return part;
        }).drain<void>(),
        throwsStateError,
      );
      expect(exposed, 0);
    },
  );
}
