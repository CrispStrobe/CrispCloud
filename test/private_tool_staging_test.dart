import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/private_tool_staging.dart';
import 'package:crisp_cloud/services/private_tool_staging_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Matcher stageFailure(PrivateStageFailure value) => isA<PrivateStageException>()
    .having((error) => error.failure, 'failure', value);

void main() {
  late Directory temporary;
  late PrivateToolStagingStore store;
  final opened = <PrivateToolStage>[];
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('crisp-stage-test-');
    store = PrivateToolStagingStore(
      rootDirectory: () async => p.join(temporary.path, 'retained'),
    );
  });
  tearDown(() async {
    for (final stage in opened) {
      await stage.close();
    }
    opened.clear();
    await temporary.delete(recursive: true);
  });

  Future<PrivateToolStage> create([String kind = 'external-edit']) async {
    final stage = await store.create(kind: kind);
    opened.add(stage);
    return stage;
  }

  test(
    'retains distinct source slots and durable manifests across reopen',
    () async {
      final stage = await create('external-compare');
      final left = await stage.write(
        'left.txt',
        Stream.value(utf8.encode('café')),
        maxBytes: 1024,
        expectedLength: 5,
      );
      final right = await stage.write(
        'right.txt',
        Stream.value([1, 2, 3]),
        maxBytes: 1024,
      );
      expect(left.path, isNot(right.path));
      expect(left.sha256, sha256.convert(utf8.encode('café')).toString());
      await stage.writeManifest({
        'version': 1,
        'left': left.name,
        'right': right.name,
      });
      await stage.close();
      expect(await store.list('external-compare'), [stage.id]);
      final recovered = await store.open(kind: stage.kind, id: stage.id);
      opened.add(recovered);
      expect(await recovered.readManifest(), {
        'version': 1,
        'left': 'left.txt',
        'right': 'right.txt',
      });
      final identity = await recovered.inspect('left.txt', maxBytes: 1024);
      expect(
        await recovered.openRead(identity).expand((bytes) => bytes).toList(),
        utf8.encode('café'),
      );
      if (!Platform.isWindows) {
        expect((await Directory(stage.directoryPath).stat()).mode & 0x3f, 0);
        expect((await File(identity.path).stat()).mode & 0x3f, 0);
      }
    },
  );

  test(
    'live leases exclude another store and explicit delete removes one session',
    () async {
      final stage = await create();
      final peer = await create();
      final other = PrivateToolStagingStore(
        rootDirectory: () async => p.join(temporary.path, 'retained'),
      );
      await expectLater(
        other.open(kind: stage.kind, id: stage.id),
        throwsA(stageFailure(PrivateStageFailure.busy)),
      );
      await stage.close();
      final recovered = await other.open(kind: stage.kind, id: stage.id);
      opened.add(recovered);
      await recovered.delete();
      expect(await store.list('external-edit'), [peer.id]);
      expect(await Directory(peer.directoryPath).exists(), isTrue);
    },
  );

  test(
    'interrupted creation is discoverable without launching or deleting data',
    () async {
      final stage = await create();
      await stage.write('working.txt', Stream.value([7, 8]), maxBytes: 10);
      expect(await stage.readManifest(), isNull);
      await stage.close();
      final restored = await store.open(kind: stage.kind, id: stage.id);
      opened.add(restored);
      expect(await restored.readManifest(), isNull);
      expect((await restored.inspect('working.txt', maxBytes: 10)).length, 2);
    },
  );

  test('bounded and cancelled writes do not install partial files', () async {
    final stage = await create();
    await expectLater(
      stage.write(
        'oversized.bin',
        Stream.value(List.filled(128 * 1024, 1)),
        maxBytes: 4,
      ),
      throwsA(stageFailure(PrivateStageFailure.tooLarge)),
    );
    var checks = 0;
    await expectLater(
      stage.write(
        'cancelled.bin',
        Stream.value(List.filled(128 * 1024, 1)),
        maxBytes: 256 * 1024,
        checkpoint: () async {
          if (++checks >= 3) throw StateError('cancelled');
        },
      ),
      throwsStateError,
    );
    await expectLater(
      stage.write(
        'short.bin',
        Stream.value([1]),
        maxBytes: 10,
        expectedLength: 2,
      ),
      throwsA(stageFailure(PrivateStageFailure.changed)),
    );
    final names = await Directory(stage.directoryPath)
        .list()
        .map((entry) => p.basename(entry.path))
        .toList();
    expect(names, ['lease']);
  });

  test(
    'completed names cannot be overwritten and snapshots stay independent',
    () async {
      final stage = await create();
      final working = await stage.write(
        'working.txt',
        Stream.value([1, 2]),
        maxBytes: 10,
      );
      final frozen = await stage.snapshot(
        'working.txt',
        'generation-1.txt',
        maxBytes: 10,
      );
      await File(working.path).writeAsBytes([3, 4], flush: true);
      expect(await stage.openRead(frozen).expand((bytes) => bytes).toList(), [
        1,
        2,
      ]);
      await expectLater(
        stage.write('generation-1.txt', Stream.value([9]), maxBytes: 10),
        throwsA(stageFailure(PrivateStageFailure.changed)),
      );
      expect(await File(frozen.path).readAsBytes(), [1, 2]);
      await expectLater(
        stage.openRead(working).drain<void>(),
        throwsA(stageFailure(PrivateStageFailure.changed)),
      );
    },
  );

  test('path escapes, foreign identities and symlinks are refused', () async {
    final stage = await create();
    for (final name in [
      '../outside',
      '/absolute',
      r'a\b',
      'manifest.json',
      '_pending',
    ]) {
      await expectLater(
        stage.write(name, const Stream.empty(), maxBytes: 10),
        throwsA(stageFailure(PrivateStageFailure.invalid)),
      );
    }
    final file = await stage.write(
      'working.txt',
      Stream.value([1]),
      maxBytes: 10,
    );
    await expectLater(
      stage
          .openRead(
            PrivateStagedFile(
              name: file.name,
              path: p.join(temporary.path, 'elsewhere'),
              length: file.length,
              sha256: file.sha256,
            ),
          )
          .drain<void>(),
      throwsA(stageFailure(PrivateStageFailure.invalid)),
    );
    if (!Platform.isWindows) {
      final outside = File(p.join(temporary.path, 'outside.txt'));
      await outside.writeAsString('retained');
      await File(file.path).delete();
      await Link(file.path).create(outside.path);
      await expectLater(
        stage.inspect(file.name, maxBytes: 10),
        throwsA(stageFailure(PrivateStageFailure.invalid)),
      );
      await stage.delete();
      expect(await outside.readAsString(), 'retained');
    }
  });

  test(
    'manifest bounds and checksum reject corrupted recovery instructions',
    () async {
      final stage = await create();
      await stage.writeManifest({'revision': 1});
      await stage.writeManifest({'revision': 2});
      expect(await stage.readManifest(), {'revision': 2});
      await expectLater(
        stage.writeManifest({'oversized': 'a' * (64 * 1024)}),
        throwsA(stageFailure(PrivateStageFailure.tooLarge)),
      );
      final file = File(p.join(stage.directoryPath, 'manifest.json'));
      final envelope =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      envelope['payload'] = '{"revision":99}';
      await file.writeAsString(jsonEncode(envelope), flush: true);
      await expectLater(
        stage.readManifest(),
        throwsA(stageFailure(PrivateStageFailure.invalid)),
      );
    },
  );

  test(
    'close waits for admitted streams and keeps their completed payload',
    () async {
      final stage = await create();
      final started = Completer<void>();
      final source = StreamController<List<int>>(onListen: started.complete);
      final write = stage.write('working.txt', source.stream, maxBytes: 10);
      await started.future;
      var closed = false;
      final closing = stage.close().then((_) {
        closed = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      source.add([1, 2]);
      await source.close();
      final result = await write;
      await closing;
      expect(await File(result.path).readAsBytes(), [1, 2]);
      final reopened = await store.open(kind: stage.kind, id: stage.id);
      opened.add(reopened);
      expect(
        (await reopened.inspect(result.name, maxBytes: 10)).sha256,
        result.sha256,
      );
    },
  );

  test(
    'cleanup excludes reopening after the session lease is released',
    () async {
      final deleting = Completer<void>();
      final continueDelete = Completer<void>();
      final cleanupStore = NativePrivateToolStagingStore(
        rootDirectory: () async => p.join(temporary.path, 'retained'),
        beforeDelete: () async {
          deleting.complete();
          await continueDelete.future;
        },
      );
      final stage = await cleanupStore.create(kind: 'external-edit');
      opened.add(stage);
      await stage.write('working.txt', Stream.value([1, 2]), maxBytes: 10);
      final deletion = stage.delete();
      await deleting.future;
      await expectLater(
        store.open(kind: stage.kind, id: stage.id),
        throwsA(stageFailure(PrivateStageFailure.busy)),
      );
      continueDelete.complete();
      await deletion;
      expect(await store.list(stage.kind), isEmpty);
    },
  );

  test('delete after retaining a closed handle requires a new lease', () async {
    final stage = await create();
    await stage.close();
    await expectLater(
      stage.delete(),
      throwsA(stageFailure(PrivateStageFailure.unavailable)),
    );
    expect(await store.list(stage.kind), [stage.id]);
    final recovered = await store.open(kind: stage.kind, id: stage.id);
    opened.add(recovered);
    await recovered.delete();
    expect(await store.list(stage.kind), isEmpty);
  });
}
