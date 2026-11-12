import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_output_spool.dart';
import 'package:crisp_cloud/services/archive_output_spool_memory.dart'
    as memory;
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final inMemory in [false, true]) {
    final label = inMemory ? 'memory' : 'native';
    Future<ArchiveOutputSpool> create(int size) => inMemory
        ? memory.createArchiveOutputSpool(maxBytes: size)
        : ArchiveOutputSpool.create(maxBytes: size);

    test(
      '$label spool seals output and supplies independent positional readers',
      () async {
        final spool = await create(1024 * 1024);
        addTearDown(spool.dispose);
        final input = Uint8List.fromList(List.generate(600001, (i) => i % 251));
        await expectLater(spool.openByteSource(), throwsStateError);
        await spool.write(input.sublist(0, 100003));
        await spool.write(input.sublist(100003));
        expect(spool.length, input.length);
        await spool.finish();
        await spool.finish();
        final first = await spool.openByteSource();
        final second = await spool.openByteSource();
        final reads = await Future.wait([
          first.read(99999, 200007),
          first.read(0, 17),
          second.read(599900, 101),
        ]);
        expect(reads[0], input.sublist(99999, 300006));
        expect(reads[1], input.sublist(0, 17));
        expect(reads[2], input.sublist(599900));
        reads[1][0] = 255;
        expect(await first.read(0, 1), [0]);
        expect(await first.read(input.length, 0), isEmpty);
        await first.close();
        await expectLater(first.read(0, 1), throwsStateError);
        expect(await second.read(0, 1), [0]);
        final streamed = BytesBuilder(copy: false);
        await for (final chunk in spool.openRead(chunkSize: 12345)) {
          expect(chunk.length, lessThanOrEqualTo(12345));
          streamed.add(chunk);
        }
        expect(streamed.takeBytes(), input);
        await expectLater(spool.write([1]), throwsStateError);
        await spool.dispose();
        await expectLater(second.read(0, 1), throwsStateError);
        await expectLater(spool.openByteSource(), throwsStateError);
        await spool.dispose();
      },
    );

    test('$label spool captures input and refuses invalid reads', () async {
      final spool = await create(5);
      addTearDown(spool.dispose);
      final bytes = Uint8List.fromList([1, 2, 3]);
      await spool.write(bytes);
      bytes[0] = 9;
      await spool.finish();
      final source = await spool.openByteSource();
      expect(await source.read(0, 3), [1, 2, 3]);
      for (final range in [(-1, 1), (0, -1), (2, 2), (4, 0)]) {
        await expectLater(source.read(range.$1, range.$2), throwsRangeError);
      }
      expect(await source.read(1, 1), [2]);
      await expectLater(
        spool.openRead(chunkSize: 0).drain<void>(),
        throwsArgumentError,
      );
    });

    test(
      '$label over-limit write poisons the spool without growing it',
      () async {
        final spool = await create(3);
        addTearDown(spool.dispose);
        await spool.write([1, 2]);
        await expectLater(
          spool.write([3, 4]),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(spool.length, 2);
        await expectLater(spool.finish(), throwsStateError);
        await expectLater(spool.openByteSource(), throwsStateError);
      },
    );

    test('$label invalid bytes cannot be sealed as archive output', () async {
      final spool = await create(3);
      addTearDown(spool.dispose);
      await expectLater(
        spool.write([256]),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(spool.length, 0);
      await expectLater(spool.finish(), throwsStateError);
    });

    test('$label empty output can be sealed, read and disposed', () async {
      final spool = await create(1);
      await spool.finish();
      expect(await spool.openRead().toList(), isEmpty);
      await spool.dispose();
    });
  }

  test(
    'browser output cap is 256 MiB even when the caller permits two GiB',
    () async {
      final spool = await memory.createArchiveOutputSpool(
        maxBytes: 2 * 1024 * 1024 * 1024,
      );
      addTearDown(spool.dispose);
      expect(spool.maxBytes, 256 * 1024 * 1024);
    },
  );

  test(
    'native disposal waits for a source opening and then invalidates it',
    () async {
      final spool = await ArchiveOutputSpool.create(maxBytes: 3);
      await spool.write([1, 2, 3]);
      await spool.finish();
      final pending = spool.openByteSource();
      final result = expectLater(pending, throwsStateError);
      await spool.dispose();
      await result;
    },
  );
}
