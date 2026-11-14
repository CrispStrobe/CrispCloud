import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/s3_client_adapter.dart';
import 'package:crisp_cloud/services/stream_rate_limiter.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/services/transfer_queue.dart';
import 'package:crisp_cloud/services/transfer_recovery_service.dart';
import 'package:crisp_cloud/services/transfer_resource_claims.dart';
import 'package:crisp_storage/crisp_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/verified_s3_fixture.dart';

const _block = 4 * 1024 * 1024;
const _options = FileOperationOptions(
  copyMethod: FileCopyMethod.verifiedDelta,
  fileConflict: FileConflictPolicy.replace,
);

Uint8List _payload([int length = 128 * 1024]) => Uint8List.fromList(
  List.generate(length, (i) => (i * 7 + i ~/ _block) % 251),
);

class _HookedJournalStorage extends MemoryTransferJournalStorage {
  Future<void> Function(Map<String, dynamic> entry)? afterEntry;

  @override
  Future<void> append(String line) async {
    await super.append(line);
    final event = decodeTransferEvent(line);
    if (event['kind'] == 'entries') {
      for (final entry in event['entries'] as List) {
        await afterEntry?.call(Map<String, dynamic>.from(entry as Map));
      }
    }
  }
}

class _Fixture {
  _Fixture(this.directory, this.server, this.adapter) {
    target = LocalOperationBackend(LocalFileService(), isCurrent: () => true);
    source = CloudOperationBackend(adapter, isCurrent: () => sourceCurrent);
  }

  final Directory directory;
  final VerifiedS3Fixture server;
  final S3ClientAdapter adapter;
  final storage = _HookedJournalStorage();
  late final journal = TransferJournal(storage);
  late final LocalOperationBackend target;
  late final CloudOperationBackend source;
  bool sourceCurrent = true;
  final phases = <String>[];
  File get local => File(p.join(directory.path, 'image.bin'));

  Future<FileOperationPlan> prepare({
    FileOperationOptions options = _options,
    String id = 'copy',
  }) async {
    final file = (await source.stat('/image.bin'))!;
    final plan = await const FileOperationService().prepare(
      files: [file],
      source: source,
      destination: target,
      targetDirectory: directory.path,
      options: options,
    );
    expect(plan.errors, isEmpty);
    expect(source.canRecover, isTrue);
    expect(target.canRecover, isTrue);
    await journal.create(id, plan);
    return plan;
  }

  Future<void> run(
    FileOperationPlan plan, {
    String id = 'copy',
    FileOperationControl? control,
    void Function(int bytes, int? total)? onProgress,
    DetailedFileConflictResolver? resolveDetailedConflict,
  }) => JournaledTransferRunner(journal).execute(
    id,
    plan,
    control: control ?? FileOperationControl(),
    resolveDetailedConflict: resolveDetailedConflict,
    onPhase: (_, phase) => phases.add(phase),
    onProgress: (_, bytes, total) => onProgress?.call(bytes, total),
  );

  Future<void> expectSuccess(
    FileOperationPlan plan, {
    String id = 'copy',
  }) async {
    expect(
      plan.entries.single.outcome,
      FileOperationOutcome.copied,
      reason: plan.entries.single.message,
    );
    expect(
      await File(plan.entries.single.destination).readAsBytes(),
      server.bytes,
    );
    expect(journal.job(id)!.status, TransferJobStatus.completed);
    final stored = journal.job(id)!.entries.single;
    expect(
      stored.recovery['contentSha256'],
      sha256.convert(server.bytes).toString(),
    );
    expect(stored.recovery['dataVerified'], isTrue);
    expect(stored.recovery['destinationSnapshot'], isA<Map>());
  }
}

class _RecordingLimiter extends StreamRateLimiter {
  _RecordingLimiter() : super(bytesPerSecond: 1024);
  int logicalBytes = 0;

  @override
  Stream<List<int>> bind(
    Stream<List<int>> input, {
    required StreamRateControl control,
  }) async* {
    await for (final chunk in input) {
      logicalBytes += chunk.length;
      yield chunk;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture fixture;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
    final directory = await Directory.systemTemp.createTemp('verified-copy-');
    fixture = _Fixture(
      directory,
      VerifiedS3Fixture(_payload()),
      await verifiedS3Adapter(cacheDirectory: p.join(directory.path, 'maps')),
    );
  });
  tearDown(() async => fixture.directory.delete(recursive: true));

  Future<void> inServer(Future<void> Function() action) =>
      http.runWithClient(action, fixture.server.client);

  test(
    'real signed HTTP copy learns its map and a journaled repeat reuses it',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final listener = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final endpoint = 'http://127.0.0.1:${listener.port}';
      final transport = fixture.server.client();
      Object? handlerError;
      final subscription = listener.listen((request) async {
        try {
          if (!(request.headers.value(HttpHeaders.authorizationHeader) ?? '')
              .startsWith('AWS4-HMAC-SHA256 ')) {
            throw StateError('The loopback request was not signed.');
          }
        // Exercise real native HTTP framing and signed requests with the
          // same deterministic server semantics used by fault-injection tests.
          final forwarded = http.Request(
            request.method,
            Uri.parse(endpoint).resolveUri(request.uri),
          );
          request.headers.forEach((name, values) {
            forwarded.headers[name] = values.join(',');
          });
          final response = await transport.send(forwarded);
          request.response.statusCode = response.statusCode;
          response.headers.forEach(request.response.headers.set);
          await request.response.addStream(response.stream);
          await request.response.close();
        } catch (error) {
          handlerError = error;
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        }
      });
      try {
        fixture = _Fixture(
          fixture.directory,
          fixture.server,
          await verifiedS3Adapter(
            cacheDirectory: p.join(fixture.directory.path, 'maps'),
            endpoint: endpoint,
          ),
        );
        final first = await fixture.prepare(id: 'native-first');
        await fixture.run(first, id: 'native-first');
        await fixture.expectSuccess(first, id: 'native-first');
        expect(handlerError, isNull);
        expect(fixture.server.fullReads, 0);
        expect(fixture.server.requestedBytes, fixture.server.bytes.length);
        fixture.server.resetRequests();
        final second = await fixture.prepare(id: 'native-reuse');
        await fixture.run(second, id: 'native-reuse');
        await fixture.expectSuccess(second, id: 'native-reuse');
        expect(handlerError, isNull);
        expect(fixture.server.heads, greaterThan(0));
        expect(fixture.server.ranges, isEmpty);
        expect(fixture.server.requestedBytes, 0);
      } finally {
        await listener.close(force: true);
        await subscription.cancel();
        transport.close();
      }
    },
  );

  test(
    'queued first copy learns once; replacement reuses local blocks with full progress and journal SHA',
    () => inServer(() async {
      fixture.server.bytes = _payload(_block + 65536);
      final allocator = TransferBandwidthAllocator();
      final queue = TransferQueue(maxConcurrent: 2, bandwidth: allocator);
      addTearDown(() {
        queue.dispose();
        allocator.dispose();
      });
      Future<void> queued(
        FileOperationPlan plan,
        String id,
        List<int> progress,
      ) async {
        final done = Completer<Object?>();
        queue.enqueue(
          TransferTask(
            id: id,
            operation: OperationProgress(
              id: id,
              type: OperationType.copy,
              sourcePath: '/image.bin',
              targetPath: fixture.directory.path,
              fileName: 'image.bin',
            ),
            resourceClaims: transferResourceClaims(plan),
            maxRetries: 0,
            execute: () => fixture.run(
              plan,
              id: id,
              onProgress: (bytes, total) {
                expect(total, fixture.server.bytes.length);
                progress.add(bytes);
              },
            ),
            retainCompletedTask: false,
            onDone: done.complete,
          ),
        );
        expect(await done.future, isNull);
      }

      final first = await fixture.prepare(id: 'first');
      final firstProgress = <int>[];
      await queued(first, 'first', firstProgress);
      await fixture.expectSuccess(first, id: 'first');
      expect(fixture.server.fullReads, 0);
      expect(fixture.server.requestedBytes, fixture.server.bytes.length);
      expect(fixture.server.ranges, [
        'bytes=0-4194303',
        'bytes=4194304-4259839',
      ]);
      expect(firstProgress.last, fixture.server.bytes.length);
      expect(allocator.snapshot.downloadBytes, fixture.server.bytes.length);
      expect(
        fixture.phases,
        containsAllInOrder([
          'writing',
          'committing',
          'committed',
          'verified',
          'complete',
        ]),
      );

      final changed = Uint8List.fromList(fixture.server.bytes)
        ..[_block + 7] ^= 255;
      await fixture.local.writeAsBytes(changed, flush: true);
      fixture.server.resetRequests();
      final second = await fixture.prepare(id: 'second');
      final secondProgress = <int>[];
      await queued(second, 'second', secondProgress);
      await fixture.expectSuccess(second, id: 'second');
      expect(fixture.server.ranges, ['bytes=4194304-4259839']);
      expect(fixture.server.requestedBytes, 65536);
      expect(fixture.server.validators, everyElement(fixture.server.version));
      expect(secondProgress.last, fixture.server.bytes.length);
      expect(secondProgress, orderedEquals([...secondProgress]..sort()));
      expect(
        allocator.snapshot.downloadBytes,
        fixture.server.bytes.length + 65536,
      );
      expect(allocator.snapshot.uploadBytes, 0);
      expect(allocator.snapshot.activeJobs, 0);
    }),
  );

  test(
    'ordinary streaming remains a full GET and does not enter the strategy',
    () => inServer(() async {
      final plan = await fixture.prepare(
        options: const FileOperationOptions(copyMethod: FileCopyMethod.stream),
      );
      await fixture.run(plan);
      await fixture.expectSuccess(plan);
      expect(fixture.server.fullReads, 1);
      expect(fixture.server.ranges, isEmpty);
      expect(fixture.server.heads, 0);
    }),
  );

  test(
    'missing reviewed ETag is rejected without a fallback source download',
    () => inServer(() async {
      fixture.server.includeETag = false;
      final plan = await fixture.prepare();
      await fixture.run(plan);
      expect(plan.entries.single.outcome, FileOperationOutcome.failed);
      expect(plan.entries.single.message, contains('strong ETag'));
      expect(fixture.server.fullReads, 0);
      expect(fixture.server.ranges, isEmpty);
      expect(await fixture.local.exists(), isFalse);
    }),
  );

  test(
    'keep-both builds a new copy without treating the old filename as its baseline',
    () => inServer(() async {
      await fixture.local.writeAsString('keep this existing file');
      final plan = await fixture.prepare(
        options: const FileOperationOptions(
          copyMethod: FileCopyMethod.verifiedDelta,
          fileConflict: FileConflictPolicy.keepBoth,
        ),
      );
      await fixture.run(plan);
      await fixture.expectSuccess(plan);
      expect(plan.entries.single.destination, isNot(fixture.local.path));
      expect(await fixture.local.readAsString(), 'keep this existing file');
      expect(fixture.server.requestedBytes, fixture.server.bytes.length);
    }),
  );

  for (final decision in [
    FileConflictDecision.append,
    FileConflictDecision.resumeVerified,
  ]) {
    test(
      'Ask cannot bypass verified method bounds with ${decision.name}',
      () => inServer(() async {
        await fixture.local.writeAsString('existing prefix');
        final plan = await fixture.prepare(
          options: const FileOperationOptions(
            copyMethod: FileCopyMethod.verifiedDelta,
          ),
        );
        await fixture.run(
          plan,
          resolveDetailedConflict: (_, _) async =>
              FileConflictResolution(decision),
        );
        expect(plan.entries.single.outcome, FileOperationOutcome.failed);
        expect(fixture.server.requestedBytes, 0);
        expect(await fixture.local.readAsString(), 'existing prefix');
      }),
    );
  }

  for (final mutation in [
    'baseline',
    'candidate',
    'new destination',
    'remote revision',
    'captured source',
  ]) {
    test(
      '$mutation change after the durable committing write prevents publication',
      () => inServer(() async {
        final hasOriginal = mutation != 'new destination';
        if (hasOriginal) await fixture.local.writeAsString('original bytes');
        final plan = await fixture.prepare();
        var changed = false;
        fixture.storage.afterEntry = (entry) async {
          if (entry['phase'] != 'committing' || changed) return;
          changed = true;
          switch (mutation) {
            case 'baseline':
            case 'new destination':
              await fixture.local.writeAsString('external edit', flush: true);
            case 'candidate':
              final recovery = entry['recovery'] as Map;
              final staged = File(recovery['stagedPath'] as String);
              final bytes = await staged.readAsBytes();
              bytes[0] ^= 255;
              await staged.writeAsBytes(bytes, flush: true);
            case 'remote revision':
              fixture.server.version = '"revision-2"';
            case 'captured source':
              // Revoke the pane after the journal's own source check and
              // during the final provider HEAD, while the adapter stays in.
              fixture.server.beforeHead = () async =>
                  fixture.sourceCurrent = false;
          }
        };
        await fixture.run(plan);
        expect(changed, isTrue);
        expect(
          plan.entries.single.outcome,
          FileOperationOutcome.failed,
          reason: plan.entries.single.message,
        );
        expect(fixture.phases, isNot(contains('committed')));
        expect(
          await fixture.local.readAsString(),
          mutation == 'baseline' || mutation == 'new destination'
              ? 'external edit'
              : 'original bytes',
        );
        expect(
          fixture.journal.job('copy')!.entries.single.recovery['contentSha256'],
          sha256.convert(fixture.server.bytes).toString(),
        );
      }),
    );
  }

  test(
    'pause after durable commit intent holds the original; changed baseline is rejected on resume',
    () => inServer(() async {
      await fixture.local.writeAsString('original bytes');
      final control = FileOperationControl();
      final paused = Completer<void>();
      final plan = await fixture.prepare();
      fixture.storage.afterEntry = (entry) async {
        if (entry['phase'] == 'committing') {
          control.pause();
          paused.complete();
        }
      };
      var done = false;
      final running = fixture
          .run(plan, control: control)
          .whenComplete(() => done = true);
      await paused.future;
      expect(done, isFalse);
      expect(await fixture.local.readAsString(), 'original bytes');
      await fixture.local.writeAsString('edit made while paused', flush: true);
      control.resume();
      await running;
      expect(plan.entries.single.outcome, FileOperationOutcome.failed);
      expect(await fixture.local.readAsString(), 'edit made while paused');
    }),
  );

  test(
    'cancel after durable commit intent is recorded as cancellation and keeps a recoverable private stage',
    () => inServer(() async {
      await fixture.local.writeAsString('original bytes');
      final control = FileOperationControl();
      final plan = await fixture.prepare();
      fixture.storage.afterEntry = (entry) async {
        if (entry['phase'] == 'committing') control.cancel();
      };
      await fixture.run(plan, control: control);
      expect(plan.entries.single.outcome, FileOperationOutcome.cancelled);
      expect(fixture.journal.job('copy')!.status, TransferJobStatus.cancelled);
      expect(await fixture.local.readAsString(), 'original bytes');
      final stage =
          fixture.journal.job('copy')!.entries.single.recovery['stagedPath']
              as String;
      expect(await File(stage).readAsBytes(), fixture.server.bytes);
      final restored = TransferJournal(fixture.storage);
      await restored.initialize();
      final preview = await const TransferRecoveryService().prepare(
        restored.job('copy')!,
        source: fixture.source,
        destination: fixture.target,
        control: FileOperationControl(),
      );
      expect(preview.issues, isEmpty);
      expect(preview.plan.options.copyMethod, FileCopyMethod.stream);
      expect(preview.actions[0], contains('ordinary streaming'));
      expect(preview.plan.entries.single.recovery!['resumeStagePath'], stage);
    }),
  );

  test(
    'lost committed acknowledgement is reconciled using the full logical SHA without another transfer',
    () => inServer(() async {
      final plan = await fixture.prepare();
      var lost = false;
      fixture.storage.afterEntry = (entry) async {
        if (entry['phase'] == 'committed' && !lost) {
          lost = true;
          throw StateError(
            'Fixture lost the durable committed acknowledgement.',
          );
        }
      };
      await fixture.run(plan);
      expect(lost, isTrue);
      expect(plan.entries.single.outcome, FileOperationOutcome.failed);
      expect(await fixture.local.readAsBytes(), fixture.server.bytes);
      final restored = TransferJournal(fixture.storage);
      await restored.initialize();
      fixture.server.resetRequests();
      final preview = await const TransferRecoveryService().prepare(
        restored.job('copy')!,
        source: fixture.source,
        destination: fixture.target,
        control: FileOperationControl(),
      );
      expect(preview.issues, isEmpty);
      expect(preview.plan.options.copyMethod, FileCopyMethod.stream);
      expect(
        preview.plan.entries.single.recovery!['resumeAfterCommit'],
        isTrue,
      );
      await JournaledTransferRunner(restored)
          .execute('copy', preview.plan, control: FileOperationControl());
      expect(preview.plan.entries.single.outcome, FileOperationOutcome.copied);
      expect(restored.job('copy')!.status, TransferJobStatus.completed);
      expect(fixture.server.requestedBytes, 0);
      expect(fixture.server.fullReads, 0);
    }),
  );

  test(
    'late cancellation preserves acknowledged contents and recovery evidence',
    () => inServer(() async {
      final control = FileOperationControl();
      final plan = await fixture.prepare();
      fixture.storage.afterEntry = (entry) async {
        if (entry['phase'] == 'committed') control.cancel();
      };
      await fixture.run(plan, control: control);
      // The ordinary queue still stops before remaining metadata work. It
      // records the installed data so a reviewed recovery can finish it.
      expect(plan.entries.single.outcome, FileOperationOutcome.cancelled);
      expect(fixture.phases, contains('committed'));
      expect(await fixture.local.readAsBytes(), fixture.server.bytes);
      final restored = TransferJournal(fixture.storage);
      await restored.initialize();
      final preview = await const TransferRecoveryService().prepare(
        restored.job('copy')!,
        source: fixture.source,
        destination: fixture.target,
        control: FileOperationControl(),
      );
      expect(preview.issues, isEmpty);
      expect(preview.plan.options.copyMethod, FileCopyMethod.stream);
      expect(
        preview.plan.entries.single.recovery!['resumeAfterCommit'],
        isTrue,
      );
    }),
  );

  test(
    'per-job limiter consumes the entire reused logical stream',
    () => inServer(() async {
      final first = await fixture.prepare(id: 'seed');
      await fixture.run(first, id: 'seed');
      await fixture.expectSuccess(first, id: 'seed');
      fixture.server.resetRequests();
      final plan = await fixture.prepare(
        options: const FileOperationOptions(
          copyMethod: FileCopyMethod.verifiedDelta,
          fileConflict: FileConflictPolicy.replace,
          clientBytesPerSecond: 1024,
        ),
      );
      final limiter = _RecordingLimiter();
      final service = FileOperationService(
        rateLimiterFactory: (rate) {
          expect(rate, 1024);
          return limiter;
        },
      );
      await service.execute(
        plan,
        control: FileOperationControl(),
        checkpoint: (entry, phase) =>
            fixture.journal.checkpoint('copy', 0, entry, phase),
      );
      expect(plan.entries.single.outcome, FileOperationOutcome.copied);
      expect(limiter.logicalBytes, fixture.server.bytes.length);
      expect(fixture.server.requestedBytes, 0);
      expect(
        plan.entries.single.recovery!['contentSha256'],
        sha256.convert(fixture.server.bytes).toString(),
      );
    }),
  );

  test(
    'destination claims stay reserved through asynchronous queue finalization',
    () => inServer(() async {
      final plan = await fixture.prepare();
      final queue = TransferQueue(maxConcurrent: 2);
      addTearDown(queue.dispose);
      final finalizing = Completer<void>();
      final release = Completer<void>();
      final firstDone = Completer<void>();
      final secondDone = Completer<void>();
      var secondStarted = false;
      OperationProgress operation(String id) => OperationProgress(
        id: id,
        type: OperationType.copy,
        sourcePath: '/image.bin',
        targetPath: fixture.directory.path,
        fileName: 'image.bin',
      );
      queue.enqueue(
        TransferTask(
          id: 'first',
          operation: operation('first'),
          resourceClaims: transferResourceClaims(plan),
          maxRetries: 0,
          execute: () => fixture.run(plan),
          onDone: (error) async {
            expect(error, isNull);
            finalizing.complete();
            await release.future;
            firstDone.complete();
          },
        ),
      );
      await finalizing.future;
      queue.enqueue(
        TransferTask(
          id: 'second',
          operation: operation('second'),
          resourceClaims: transferResourceClaims(plan),
          maxRetries: 0,
          execute: () async => secondStarted = true,
          onDone: (_) => secondDone.complete(),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(secondStarted, isFalse);
      expect(queue.blockedReason('second'), isNotNull);
      await fixture.expectSuccess(plan);
      release.complete();
      await firstDone.future;
      await secondDone.future;
      expect(secondStarted, isTrue);
    }),
  );
}
