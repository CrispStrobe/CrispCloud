import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_batch_integrity_service.dart';
import 'package:crisp_cloud/services/archive_integrity_service.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_creation_backend.dart';
import 'support/archive_volume_fixtures.dart';

Uint8List _zip({
  String? password,
  String name = 'hello.txt',
  String text = 'hello',
}) => Uint8List.fromList(
  ar.ZipEncoder(password: password).encode(
    ar.Archive()..addFile(ar.ArchiveFile.bytes(name, utf8.encode(text))),
  ),
);

class _Backend extends ArchiveCreationBackend {
  Object token = Object();
  final reads = <String>[];
  final revisions = <String, Map<String, dynamic>>{};
  Future<void>? readGate;
  void Function()? afterRead;
  bool invalidBytes = false;
  @override
  Object get identity => token;
  @override
  String get persistentStorageId => 'captured-test-files';
  @override
  Future<FileItem?> stat(String path) async {
    final item = await super.stat(path);
    return item?.copyWith(
      metadata: revisions.putIfAbsent(path, () => {'revision': 'one'}),
    );
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    reads.add(file.path!);
    if (readGate != null) await readGate;
    if (invalidBytes) {
      yield [-1, 256];
      return;
    }
    yield* super.readFile(file);
    afterRead?.call();
  }

  Future<FileItem> select(String name) async => (await stat('/input/$name'))!;
}

void main() {
  for (final native in [false, true]) {
    group(native ? 'native snapshot' : 'memory snapshot', () {
      late _Backend backend;
      setUp(() => backend = _Backend());
      Future<ArchiveBatchIntegrityRun> run(
        List<String> names, {
        int maxInputBytes = kArchiveStreamingLimit,
        int maxReportEntries = 200000,
      }) async => ArchiveBatchIntegrityRun(
        source: backend,
        files: [for (final name in names) await backend.select(name)],
        spoolToDisk: native,
        maxInputBytes: maxInputBytes,
        maxReportEntries: maxReportEntries,
      );

      test(
        'continues after an invalid container and reports independent hashes',
        () async {
          final bytes = _zip();
          backend.put('/input/invalid.zip', [1, 2, 3]);
          backend.put('/input/healthy.zip', bytes);
          final report = await (await run(['invalid.zip', 'healthy.zip']))
              .check();
          expect(report.issueCount, 1);
          expect(report.checkedCount, 1);
          expect(report.unprocessedCount, 0);
          expect(report.items.first.error, isNotEmpty);
          expect(
            report.items.last.snapshotSha256,
            sha256.convert(bytes).toString(),
          );
          expect(
            report.items.last.report!.entries.single.sha256,
            sha256.convert(utf8.encode('hello')).toString(),
          );
          expect(backend.reads, ['/input/invalid.zip', '/input/healthy.zip']);
          expect(backend.writes, isEmpty);
        },
      );

      test('reports unsafe member namespace without losing readable sibling checks', () async {
        final data = ar.Archive()
          ..addFile(
            ar.ArchiveFile.bytes('../escape.txt', utf8.encode('unsafe')),
          )
          ..addFile(ar.ArchiveFile.bytes('good.txt', utf8.encode('safe')));
        backend.put('/input/unsafe.zip', ar.ZipEncoder().encode(data));
        final report = await (await run(['unsafe.zip'])).check();
        final member = report.items.single.report!;
        expect(member.namespaceIssue, isNotNull);
        expect(member.checkedCount, 1);
        expect(member.skippedCount, 1);
        expect(member.allRegularMembersChecked, isFalse);
        expect(report.checkedCount, 0);
      });

      test('password retry reuses one ordinary archive snapshot', () async {
        backend.put('/input/protected.zip', _zip(password: 'correct 🔑'));
        final prompts = <bool>[];
        final report = await (await run(['protected.zip'])).check(
          requestPassword: (file, {required wrongPassword}) async {
            expect(file.name, 'protected.zip');
            prompts.add(wrongPassword);
            return prompts.length == 1 ? 'wrong' : 'correct 🔑';
          },
        );
        expect(report.allArchivesChecked, isTrue);
        expect(prompts, [false, true]);
        expect(backend.reads, ['/input/protected.zip']);
        expect(
          report.items.single.report!.entries.single.sha256,
          sha256.convert(utf8.encode('hello')).toString(),
        );
      });

      test(
        'declined visible password reports skipped content and continues',
        () async {
          backend.put('/input/protected.zip', _zip(password: 'secret'));
          backend.put('/input/healthy.zip', _zip());
          var prompts = 0;
          final report = await (await run(['protected.zip', 'healthy.zip']))
              .check(
                requestPassword: (_, {required wrongPassword}) async {
                  prompts++;
                  return null;
                },
              );
          expect(prompts, 1);
          expect(report.items.first.report!.skippedCount, 1);
          expect(
            report.items.first.report!.entries.single.skipReason,
            ArchiveIntegritySkipReason.passwordRequired,
          );
          expect(report.checkedCount, 1);
          expect(report.allArchivesChecked, isFalse);
        },
      );

      test(
        'password attempts are bounded and failed content never passes',
        () async {
          backend.put('/input/protected.zip', _zip(password: 'secret'));
          var prompts = 0;
          final report = await (await run(['protected.zip'])).check(
            requestPassword: (_, {required wrongPassword}) async {
              prompts++;
              return 'incorrect';
            },
          );
          expect(prompts, 3);
          expect(report.items.single.report!.failedCount, 1);
          expect(report.allArchivesChecked, isFalse);
          expect(backend.reads, hasLength(1));
        },
      );

      test('hidden-header passwords reopen the same captured bytes', () async {
        backend.put(
          '/input/secret.7z',
          File('test/fixtures/archives/header_encrypted.7z').readAsBytesSync(),
        );
        var attempts = 0;
        final report = await (await run(['secret.7z'])).check(
          requestPassword: (_, {required wrongPassword}) async {
            expect(wrongPassword, attempts > 0);
            return ++attempts == 1 ? 'wrong' : 'secret';
          },
        );
        expect(report.allArchivesChecked, isTrue);
        expect(attempts, 2);
        expect(backend.reads, hasLength(1));
      });

      test(
        'declined hidden-header password is an explicit archive skip',
        () async {
          backend.put(
            '/input/secret.7z',
            File('test/fixtures/archives/header_encrypted.7z')
                .readAsBytesSync(),
          );
          final report = await (await run(['secret.7z'])).check(
            requestPassword: (_, {required wrongPassword}) async => null,
          );
          expect(
            report.items.single.skipReason,
            ArchiveBatchIntegritySkipReason.passwordRequired,
          );
          expect(report.items.single.report, isNull);
          expect(report.skippedCount, 1);
          expect(report.checkedCount, 0);
        },
      );

      test('input bound refuses before copying source bytes', () async {
        backend.put('/input/large.zip', _zip());
        final report = await (await run([
          'large.zip',
        ], maxInputBytes: 20)).check();
        expect(report.items.single.error, contains('limit'));
        expect(backend.reads, isEmpty);
      });

      test(
        'selected revision is captured before mutable provider maps change',
        () async {
          backend.put('/input/changed.zip', _zip());
          final captured = await run(['changed.zip']);
          backend.revisions['/input/changed.zip']!['revision'] = 'two';
          final report = await captured.check();
          expect(report.items.single.error, contains('changed'));
          expect(backend.reads, isEmpty);
        },
      );

      test(
        'source revision change during capture refuses a snapshot verdict',
        () async {
          backend.put('/input/changed.zip', _zip());
          backend.afterRead = () =>
              backend.revisions['/input/changed.zip']!['revision'] = 'two';
          final report = await (await run(['changed.zip'])).check();
          expect(report.items.single.error, isNotNull);
          expect(report.items.single.report, isNull);
          expect(report.allArchivesChecked, isFalse);
        },
      );

      test(
        'backend identity change during member checks stops remaining archives',
        () async {
          backend.put('/input/one.zip', _zip());
          backend.put('/input/two.zip', _zip());
          final report = await (await run(['one.zip', 'two.zip'])).check(
            onProgress: (progress) {
              if (progress.memberProgress != null) backend.token = Object();
            },
          );
          expect(
            report.stopReason,
            ArchiveBatchIntegrityStopReason.unavailable,
          );
          expect(report.unprocessedCount, 1);
          expect(report.items.single.report!.unprocessedCount, 1);
          expect(report.allArchivesChecked, isFalse);
          expect(backend.reads, ['/input/one.zip']);
        },
      );

      test(
        'cancel before the next archive leaves it explicitly unprocessed',
        () async {
          backend.put('/input/one.zip', _zip());
          backend.put('/input/two.zip', _zip());
          var cancelled = false;
          final report = await (await run(['one.zip', 'two.zip'])).check(
            isCancelled: () => cancelled,
            onProgress: (progress) {
              if (progress.completedArchives == 1) cancelled = true;
            },
          );
          expect(report.stopReason, ArchiveBatchIntegrityStopReason.cancelled);
          expect(report.checkedCount, 1);
          expect(report.unprocessedCount, 1);
          expect(report.allArchivesChecked, isFalse);
          expect(backend.reads, ['/input/one.zip']);
        },
      );

      test(
        'cancellation releases a snapshot with a stalled source read',
        () async {
          backend.put('/input/stalled.zip', _zip());
          final gate = Completer<void>();
          backend.readGate = gate.future;
          addTearDown(() {
            if (!gate.isCompleted) gate.complete();
          });
          var cancelled = false;
          final checking = (await run(['stalled.zip']))
              .check(isCancelled: () => cancelled);
          while (backend.reads.isEmpty) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
          cancelled = true;
          final report = await checking.timeout(const Duration(seconds: 4));
          expect(report.stopReason, ArchiveBatchIntegrityStopReason.cancelled);
          expect(report.unprocessedCount, 1);
          expect(report.items, isEmpty);
          gate.complete();
        },
      );

      test(
        'invalid provider bytes cannot be coerced into a successful archive',
        () async {
          backend.put('/input/invalid.zip', _zip());
          backend.invalidBytes = true;
          final report = await (await run(['invalid.zip'])).check();
          expect(report.items.single.error, contains('invalid bytes'));
          expect(report.items.single.report, isNull);
        },
      );

      test('member report budget stops the batch explicitly', () async {
        for (final name in ['one.zip', 'two.zip', 'three.zip']) {
          backend.put('/input/$name', _zip());
        }
        final report = await (await run([
          'one.zip',
          'two.zip',
          'three.zip',
        ], maxReportEntries: 1)).check();
        expect(report.stopReason, ArchiveBatchIntegrityStopReason.reportLimit);
        expect(report.checkedCount, 1);
        expect(report.issueCount, 1);
        expect(report.unprocessedCount, 1);
        expect(report.items[1].error, contains('1 members'));
      });

      test(
        'encrypted split header retries reject substituted same-size parts',
        () async {
          final data = File('test/fixtures/archives/header_encrypted.7z')
              .readAsBytesSync();
          final parts = volumeSplitBytes(data);
          for (var i = 0; i < parts.length; i++) {
            backend.put(
              '/input/protected.7z.${(i + 1).toString().padLeft(3, '0')}',
              parts[i],
            );
          }
          var prompts = 0;
          final report = await (await run(['protected.7z.001'])).check(
            requestPassword: (_, {required wrongPassword}) async {
              prompts++;
              // Change a packed byte while retaining framing CRCs, length and
              // provider metadata. Every password attempt must share a digest.
              backend.contents['/input/protected.7z.001']![32] ^= 1;
              return 'secret';
            },
          );
          expect(prompts, 1);
          expect(report.items.single.error, contains('changed'));
          expect(report.items.single.report, isNull);
          expect(report.allArchivesChecked, isFalse);
        },
      );

      test(
        'first numbered 7z part checks the complete captured volume set',
        () async {
          final data = volumeReferenceSevenZip();
          final parts = volumeSplitBytes(data);
          for (var i = 0; i < parts.length; i++) {
            backend.put(
              '/input/archive.7z.${(i + 1).toString().padLeft(3, '0')}',
              parts[i],
            );
          }
          final report = await (await run(['archive.7z.001'])).check();
          expect(report.allArchivesChecked, isTrue);
          expect(report.items.single.report!.checkedCount, 2);
          expect(report.items.single.report!.formatName, 'volumes/7z');
          expect(
            report.items.single.snapshotSha256,
            sha256.convert(data).toString(),
          );
          expect(backend.writes, isEmpty);
        },
      );
    });
  }

  test(
    'captures selection list and skips folders, links and duplicates',
    () async {
      final backend = _Backend()..put('/input/valid.zip', _zip());
      backend.links.add('/input/link.zip');
      final selected = [
        await backend.select('valid.zip'),
        await backend.select('valid.zip'),
        (await backend.stat('/input'))!,
        await backend.select('link.zip'),
      ];
      final run = ArchiveBatchIntegrityRun(
        source: backend,
        files: selected,
        spoolToDisk: false,
      );
      selected.clear();
      final report = await run.check();
      expect(report.totalArchives, 4);
      expect(report.checkedCount, 1);
      expect(report.skippedCount, 3);
      expect(report.items.skip(1).map((item) => item.skipReason), [
        ArchiveBatchIntegritySkipReason.duplicate,
        ArchiveBatchIntegritySkipReason.directory,
        ArchiveBatchIntegritySkipReason.symbolicLink,
      ]);
      expect(backend.reads, hasLength(1));
      expect(() => run.files.clear(), throwsUnsupportedError);
      await expectLater(run.check(), throwsStateError);
    },
  );

  test('scoped selections use the captured backend account when stat has no storage tag', () async {
    final backend = _Backend()..put('/input/scoped.zip', _zip());
    final file = (await backend.select('scoped.zip'))
        .copyWith(storageId: backend.persistentStorageId);
    final report = await ArchiveBatchIntegrityRun(
      source: backend,
      files: [file],
      spoolToDisk: false,
    ).check();
    expect(report.allArchivesChecked, isTrue);
    final wrongAccount = await ArchiveBatchIntegrityRun(
      source: backend,
      files: [file.copyWith(storageId: 'another-account')],
      spoolToDisk: false,
    ).check();
    expect(
      wrongAccount.items.single.error,
      contains('another storage account'),
    );
    expect(backend.reads, hasLength(1));
  });

  test('empty or already unavailable selections never claim success', () async {
    final backend = _Backend();
    final empty = await ArchiveBatchIntegrityRun(
      source: backend,
      files: [],
    ).check();
    expect(empty.allArchivesChecked, isFalse);
    backend.put('/input/file.zip', _zip());
    final run = ArchiveBatchIntegrityRun(
      source: backend,
      files: [await backend.select('file.zip')],
    );
    backend.current = false;
    final report = await run.check();
    expect(report.stopReason, ArchiveBatchIntegrityStopReason.unavailable);
    expect(report.items, isEmpty);
    expect(report.unprocessedCount, 1);
  });
}
