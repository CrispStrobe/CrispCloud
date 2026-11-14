import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/binary_comparison_source.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';

class _Source extends FileOperationBackend {
  List<int> bytes = [1, 2, 3, 4];
  Object sourceIdentity = Object();
  bool current = true, knownSize = true, folder = false, symlink = false;
  int? sizeOverride;
  int reads = 0, stats = 0, writes = 0;
  final metadata = <String, dynamic>{};
  Future<FileItem?> Function(int call)? onStat;
  Stream<List<int>> Function(int call)? onRead;

  @override
  Object get identity => sourceIdentity;
  @override
  bool get isCurrent => current;
  @override
  String get label => 'Comparison fixture';
  @override
  p.Context get paths => p.Context(style: p.Style.posix);

  FileItem get item => FileItem(
    name: 'input.bin',
    path: '/input.bin',
    uuid: 'stable-input',
    isFolder: folder,
    isSymlink: symlink,
    size: knownSize ? sizeOverride ?? bytes.length : null,
    updatedAt: DateTime.utc(2026, 11, 14),
    metadata: metadata,
  );

  @override
  Future<FileItem?> stat(String path) async {
    stats++;
    return onStat == null ? item : await onStat!(stats);
  }

  @override
  Stream<List<int>> readFile(FileItem file) {
    reads++;
    return onRead == null ? Stream.value(List<int>.of(bytes)) : onRead!(reads);
  }

  @override
  Future<List<FileItem>> list(String path) async => [item];
  @override
  Future<void> createDirectory(String path) async => writes++;
  @override
  Future<void> deleteFile(FileItem file) async => writes++;
  @override
  Future<void> deleteEmptyDirectory(String path) async => writes++;
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async => writes++;
}

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('binary-capture-test-');
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  Future<T> captured<T>(Future<T> Function() action) =>
      IOOverrides.runZoned(action, getSystemTemp: () => temporary);

  test(
    'verified copies retain exact hashes, owned windows and read-only input',
    () async {
      await captured(() async {
        final backend = _Source();
        final snapshot = await BinaryComparisonSnapshot.capture(
          backend,
          backend.item,
        );
        expect(snapshot.length, 4);
        expect(snapshot.sha256Digest, sha256.convert([1, 2, 3, 4]).toString());
        expect(backend.reads, 2);
        final page = await snapshot.read(0, 4);
        page[0] = 99;
        final chunks = await snapshot.readRange(0).toList();
        chunks.single[1] = 88;
        backend.bytes = [9, 9, 9, 9];
        await snapshot.validate();
        expect(await snapshot.read(0, 4), [1, 2, 3, 4]);
        expect(await snapshot.read(4, 0), isEmpty);
        expect(await snapshot.readRange(4).toList(), isEmpty);
        expect(backend.reads, 2);
        expect(backend.writes, 0);
        expect(temporary.listSync(), hasLength(1));
        await snapshot.close();
        await snapshot.close();
        expect(temporary.listSync(), isEmpty);
        await expectLater(snapshot.read(0, 1), throwsStateError);
        await expectLater(snapshot.validate(), throwsStateError);
      });
    },
  );

  test(
    'same-size same-metadata rewrite between passes is rejected and removed',
    () async {
      await captured(() async {
        final backend = _Source();
        backend.onRead = (call) =>
            Stream.value(call == 1 ? [1, 2, 3, 4] : [1, 2, 9, 4]);
        await expectLater(
          BinaryComparisonSnapshot.capture(backend, backend.item),
          throwsA(isA<BinaryComparisonSourceChanged>()),
        );
        expect(backend.reads, 2);
        expect(temporary.listSync(), isEmpty);
        expect(backend.writes, 0);
      });
    },
  );

  test(
    'mutable provider version maps do not rewrite the captured identity',
    () async {
      await captured(() async {
        final backend = _Source()..metadata['version'] = 'v1';
        final snapshot = await BinaryComparisonSnapshot.capture(
          backend,
          backend.item,
        );
        backend.metadata['version'] = 'v2';
        expect(snapshot.file.metadata!['version'], 'v1');
        await expectLater(
          snapshot.validate(),
          throwsA(isA<BinaryComparisonSourceChanged>()),
        );
        await snapshot.close();
        expect(temporary.listSync(), isEmpty);
      });
    },
  );

  test(
    'metadata token mutation during capture cannot hide source replacement',
    () async {
      await captured(() async {
        final backend = _Source()..metadata['version'] = 'v1';
        backend.onRead = (_) {
          backend.metadata['version'] = 'v2';
          return Stream.value([1, 2, 3, 4]);
        };
        await expectLater(
          BinaryComparisonSnapshot.capture(backend, backend.item),
          throwsA(isA<BinaryComparisonSourceChanged>()),
        );
        expect(backend.reads, 1);
        expect(temporary.listSync(), isEmpty);
      });
    },
  );

  test('known oversize input is rejected before any read or spool', () async {
    await captured(() async {
      final backend = _Source();
      await expectLater(
        BinaryComparisonSnapshot.capture(
          backend,
          backend.item,
          limits: const BinaryComparisonLimits(maxBytes: 3),
        ),
        throwsA(isA<BinaryComparisonLimitExceeded>()),
      );
      expect(backend.reads, 0);
      expect(temporary.listSync(), isEmpty);
    });
  });

  test('unknown-size streams are bounded while capturing', () async {
    await captured(() async {
      final backend = _Source()..knownSize = false;
      backend.onRead = (_) => Stream.fromIterable([
        [1, 2],
        [3, 4],
      ]);
      await expectLater(
        BinaryComparisonSnapshot.capture(
          backend,
          backend.item,
          limits: const BinaryComparisonLimits(maxBytes: 3),
        ),
        throwsA(isA<BinaryComparisonLimitExceeded>()),
      );
      expect(temporary.listSync(), isEmpty);
    });
  });

  test(
    'unknown sizes are measured and second reads require that exact length',
    () async {
      await captured(() async {
        final backend = _Source()..knownSize = false;
        final snapshot = await BinaryComparisonSnapshot.capture(
          backend,
          backend.item,
        );
        expect(snapshot.length, 4);
        await snapshot.validate();
        await snapshot.close();
        backend.reads = 0;
        backend.onRead = (call) =>
            Stream.value(call == 1 ? [1, 2, 3, 4] : [1, 2, 3]);
        await expectLater(
          BinaryComparisonSnapshot.capture(backend, backend.item),
          throwsA(isA<BinaryComparisonSourceChanged>()),
        );
        expect(temporary.listSync(), isEmpty);
      });
    },
  );

  for (final declared in [3, 5]) {
    test('declared length $declared cannot admit a four-byte source', () async {
      await captured(() async {
        final backend = _Source()..sizeOverride = declared;
        await expectLater(
          BinaryComparisonSnapshot.capture(backend, backend.item),
          throwsA(isA<BinaryComparisonSourceChanged>()),
        );
        expect(temporary.listSync(), isEmpty);
      });
    });
  }

  test('newly available metadata length must equal measured bytes', () async {
    await captured(() async {
      final backend = _Source()..knownSize = false;
      backend.onStat = (call) async {
        if (call >= 2) {
          backend.knownSize = true;
          backend.sizeOverride = 5;
        }
        return backend.item;
      };
      await expectLater(
        BinaryComparisonSnapshot.capture(backend, backend.item),
        throwsA(isA<BinaryComparisonSourceChanged>()),
      );
      expect(backend.reads, 1);
      expect(temporary.listSync(), isEmpty);
    });
  });

  test(
    'empty files preserve their exact identity and release storage',
    () async {
      await captured(() async {
        final backend = _Source()..bytes = [];
        final snapshot = await BinaryComparisonSnapshot.capture(
          backend,
          backend.item,
        );
        expect(snapshot.length, 0);
        expect(snapshot.sha256Digest, sha256.convert([]).toString());
        expect(await snapshot.read(0, 0), isEmpty);
        await snapshot.close();
        expect(temporary.listSync(), isEmpty);
      });
    },
  );

  test('empty and tiny chunk work has a finite allowance', () async {
    await captured(() async {
      for (final empty in [true, false]) {
        final backend = _Source()..knownSize = false;
        backend.onRead = (_) =>
            Stream.fromIterable(List.generate(5, (_) => empty ? <int>[] : [1]));
        await expectLater(
          BinaryComparisonSnapshot.capture(
            backend,
            backend.item,
            limits: BinaryComparisonLimits(
              maxChunks: empty ? 10 : 3,
              maxEmptyChunks: 3,
            ),
          ),
          throwsA(isA<BinaryComparisonLimitExceeded>()),
        );
        expect(temporary.listSync(), isEmpty);
      }
    });
  });

  test('provider bytes outside 0..255 are not silently normalized', () async {
    await captured(() async {
      final backend = _Source()..bytes = [1, 2, 256, 4];
      await expectLater(
        BinaryComparisonSnapshot.capture(backend, backend.item),
        throwsRangeError,
      );
      expect(temporary.listSync(), isEmpty);
    });
  });

  test(
    'cancellation bounds an initial metadata future and observes late errors',
    () async {
      await captured(() async {
        final entered = Completer<void>(), metadata = Completer<FileItem?>();
        final backend = _Source();
        backend.onStat = (_) {
          entered.complete();
          return metadata.future;
        };
        var cancelled = false;
        final pending = BinaryComparisonSnapshot.capture(
          backend,
          backend.item,
          isCancelled: () => cancelled,
        );
        final expectation = expectLater(
          pending.timeout(const Duration(seconds: 2)),
          throwsA(isA<BinaryComparisonCancelled>()),
        );
        await entered.future;
        cancelled = true;
        await expectation;
        metadata.completeError(StateError('late provider error'));
        await Future<void>.delayed(Duration.zero);
        expect(backend.reads, 0);
        expect(temporary.listSync(), isEmpty);
      });
    },
  );

  for (final phase in [1, 2]) {
    test(
      'cancellation detaches a stalled read in capture pass $phase',
      () async {
        await captured(() async {
          final entered = Completer<void>(), release = Completer<void>();
          final backend = _Source();
          Stream<List<int>> stalled() async* {
            entered.complete();
            await release.future;
            yield [1, 2, 3, 4];
          }

          backend.onRead = (call) =>
              call == phase ? stalled() : Stream.value([1, 2, 3, 4]);
          var cancelled = false;
          final pending = BinaryComparisonSnapshot.capture(
            backend,
            backend.item,
            isCancelled: () => cancelled,
          );
          final expectation = expectLater(
            pending.timeout(const Duration(seconds: 2)),
            throwsA(isA<BinaryComparisonCancelled>()),
          );
          await entered.future;
          cancelled = true;
          try {
            await expectation;
            expect(temporary.listSync(), isEmpty);
          } finally {
            release.complete();
          }
        });
      },
    );
  }

  test(
    'same-current backend identity changes cancel a pending metadata read',
    () async {
      await captured(() async {
        final entered = Completer<void>(), metadata = Completer<FileItem?>();
        final backend = _Source();
        backend.onStat = (_) {
          entered.complete();
          return metadata.future;
        };
        final pending = BinaryComparisonSnapshot.capture(backend, backend.item);
        final expectation = expectLater(
          pending.timeout(const Duration(seconds: 2)),
          throwsA(isA<BinaryComparisonSourceChanged>()),
        );
        await entered.future;
        backend.sourceIdentity = Object();
        await expectation;
        metadata.complete(backend.item);
        expect(temporary.listSync(), isEmpty);
      });
    },
  );

  test(
    'inactivity timeout bounds metadata even without cancellation callbacks',
    () async {
      await captured(() async {
        final metadata = Completer<FileItem?>();
        final backend = _Source()..onStat = (_) => metadata.future;
        await expectLater(
          BinaryComparisonSnapshot.capture(
            backend,
            backend.item,
            limits: const BinaryComparisonLimits(
              inactivityTimeout: Duration(milliseconds: 40),
            ),
          ).timeout(const Duration(seconds: 2)),
          throwsA(isA<TimeoutException>()),
        );
        metadata.complete(backend.item);
        expect(temporary.listSync(), isEmpty);
      });
    },
  );

  test(
    'a cancelled snapshot validation does not wait for provider metadata',
    () async {
      await captured(() async {
        final backend = _Source();
        final snapshot = await BinaryComparisonSnapshot.capture(
          backend,
          backend.item,
        );
        final entered = Completer<void>(), metadata = Completer<FileItem?>();
        backend.onStat = (_) {
          entered.complete();
          return metadata.future;
        };
        var cancelled = false;
        final pending = snapshot.validate(isCancelled: () => cancelled);
        final expectation = expectLater(
          pending.timeout(const Duration(seconds: 2)),
          throwsA(isA<BinaryComparisonCancelled>()),
        );
        await entered.future;
        cancelled = true;
        await expectation;
        await snapshot.close();
        metadata.complete(backend.item);
        expect(temporary.listSync(), isEmpty);
      });
    },
  );

  test(
    'closing during a queued native read never recreates deleted storage',
    () async {
      await captured(() async {
        final backend = _Source()..bytes = Uint8List(128 * 1024);
        final snapshot = await BinaryComparisonSnapshot.capture(
          backend,
          backend.item,
        );
        final pending = snapshot.read(0, 64 * 1024);
        final outcome = expectLater(pending, throwsStateError);
        await snapshot.close();
        await outcome;
        expect(temporary.listSync(), isEmpty);
      });
    },
  );

  test(
    'invalid inputs and ceilings are rejected before any source access',
    () async {
      await captured(() async {
        for (final limits in [
          const BinaryComparisonLimits(maxBytes: 0),
          const BinaryComparisonLimits(
            maxBytes: kBinaryComparisonNativeInputLimit + 1,
          ),
          const BinaryComparisonLimits(maxChunks: 0),
          const BinaryComparisonLimits(maxEmptyChunks: -1),
          const BinaryComparisonLimits(overallTimeout: Duration.zero),
        ]) {
          final backend = _Source();
          await expectLater(
            BinaryComparisonSnapshot.capture(
              backend,
              backend.item,
              limits: limits,
            ),
            throwsArgumentError,
          );
          expect(backend.stats, 0);
        }
        for (final file in [
          FileItem(name: 'missing', isFolder: false),
          FileItem(name: 'folder', path: '/input.bin', isFolder: true),
          FileItem(
            name: 'link',
            path: '/input.bin',
            isFolder: false,
            isSymlink: true,
          ),
        ]) {
          final backend = _Source();
          await expectLater(
            BinaryComparisonSnapshot.capture(backend, file),
            throwsArgumentError,
          );
          expect(backend.stats, 0);
        }
        expect(temporary.listSync(), isEmpty);
      });
    },
  );
}
