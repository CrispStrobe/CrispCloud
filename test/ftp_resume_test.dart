import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/ftp_client_adapter.dart';
import 'package:crisp_cloud/services/ftp_config_service.dart';
import 'package:crisp_cloud/services/ftp_download_snapshot.dart';
import 'package:crisp_cloud/services/ftp_security_mode.dart';
import 'package:crisp_cloud/services/ftp_transfer_session.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/services/transfer_recovery_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ftp_resume_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
  });

  Future<FtpResumeFixture> server({
    FtpSecurityMode mode = FtpSecurityMode.plain,
  }) async {
    final fixture = await FtpResumeFixture.open(mode: mode);
    addTearDown(() async {
      await fixture.close();
      expect(fixture.errors, isEmpty);
    });
    return fixture;
  }

  Future<FtpTransferSession> session(
    FtpResumeFixture fixture, {
    bool Function()? isCurrent,
  }) async {
    final client = FtpTransferSession(
      host: '127.0.0.1',
      port: fixture.port,
      username: 'fixture',
      password: 'synthetic-password',
      securityMode: fixture.mode,
      securityContext: FtpResumeFixture.trustedContext(),
      isCurrent: isCurrent ?? () => true,
      timeout: const Duration(seconds: 3),
    );
    addTearDown(client.close);
    await client.connect();
    return client;
  }

  Future<FTPClientAdapter> adapter(FtpResumeFixture fixture) async {
    final client = FTPClientAdapter(
      config: FTPConfigService(
        configPath: '',
        secureStorage: InMemorySecureStorage(),
      ),
      securityContext: FtpResumeFixture.trustedContext(),
    );
    await client.login(
      'fixture@127.0.0.1:${fixture.port}?security=${fixture.mode.name}',
      'synthetic-password',
    );
    addTearDown(client.logout);
    return client;
  }

  Future<Directory> directory() async {
    final directory = await Directory.systemTemp.createTemp(
      'crisp-ftp-resume-',
    );
    addTearDown(() => directory.delete(recursive: true));
    return directory;
  }

  for (final mode in FtpSecurityMode.values) {
    test(
      '${mode.name} REST immediately precedes RETR at the exact binary offset',
      () async {
        final fixture = await server(mode: mode);
        final client = await session(fixture);
        final captured = await client.captureDownloadSnapshot('/payload.bin');
        const offset = 65537;
        final bytes = await client
            .downloadRange('/payload.bin', offset, expected: captured)
            .expand((chunk) => chunk)
            .toList();
        expect(bytes, fixture.payload.sublist(offset));
        expect(fixture.offsets, [offset]);
        final commands = fixture.sessions.values.single;
        final rest = commands.indexOf('REST $offset');
        expect(commands.sublist(rest - 1, rest + 2), [
          'EPSV',
          'REST $offset',
          'RETR /payload.bin',
        ]);
        expect(
          commands,
          containsAllInOrder(['TYPE I', 'FEAT', 'MODE S', 'STRU F']),
        );
        expect(commands.sublist(commands.length - 2), [
          'SIZE /payload.bin',
          'MDTM /payload.bin',
        ]);
        if (mode.isSecure) {
          expect(fixture.protectedDataConnections, 1);
          expect(
            fixture.cleartextCommands,
            mode == FtpSecurityMode.explicitTls ? ['AUTH TLS'] : isEmpty,
          );
          expect(fixture.protectedCommands, contains('REST $offset'));
        }
      },
    );
  }

  test(
    'length is exclusive and the complete remaining transfer is confirmed',
    () async {
      final fixture = await server();
      final client = await session(fixture);
      final captured = await client.captureDownloadSnapshot('/payload.bin');
      final bytes = await client
          .downloadRange('/payload.bin', 120001, length: 11, expected: captured)
          .expand((chunk) => chunk)
          .toList();
      expect(bytes, fixture.payload.sublist(120001, 120012));
      expect(fixture.offsets, [120001]);
      expect(fixture.commands.last, 'MDTM /payload.bin');
    },
  );

  for (final atEof in [false, true]) {
    test(
      'an empty ${atEof ? 'EOF' : 'bounded'} range opens no data channel',
      () async {
        final fixture = await server();
        final client = await session(fixture);
        final captured = await client.captureDownloadSnapshot('/payload.bin');
        expect(
          await client
              .downloadRange(
                '/payload.bin',
                atEof ? captured.size : 9,
                length: atEof ? null : 0,
                expected: captured,
              )
              .toList(),
          isEmpty,
        );
        expect(fixture.offsets, isEmpty);
        expect(fixture.commands, isNot(contains('EPSV')));
      },
    );
  }

  for (final bounds in [(-1, null), (196734, null), (10, -1), (196732, 2)]) {
    test(
      'rejects range offset ${bounds.$1} length ${bounds.$2} before REST',
      () async {
        final fixture = await server();
        final client = await session(fixture);
        final captured = await client.captureDownloadSnapshot('/payload.bin');
        await expectLater(
          client
              .downloadRange(
                '/payload.bin',
                bounds.$1,
                length: bounds.$2,
                expected: captured,
              )
              .toList(),
          throwsRangeError,
        );
        expect(fixture.commands, isNot(contains('FEAT')));
        expect(fixture.offsets, isEmpty);
      },
    );
  }

  for (final feature in ['', 'REST', 'REST BLOCK', 'REST STREAM EXTRA']) {
    test(
      'missing exact REST STREAM feature ($feature) has no restart fallback',
      () async {
        final fixture = await server()
          ..feature = feature;
        final client = await session(fixture);
        final captured = await client.captureDownloadSnapshot('/payload.bin');
        await expectLater(
          client.downloadRange('/payload.bin', 12, expected: captured).toList(),
          throwsUnsupportedError,
        );
        expect(fixture.offsets, isEmpty);
      },
    );
  }

  test('refused FEAT remains an explicit unsupported resume outcome', () async {
    final fixture = await server()
      ..featureCode = 500;
    final client = await session(fixture);
    final captured = await client.captureDownloadSnapshot('/payload.bin');
    await expectLater(
      client.downloadRange('/payload.bin', 12, expected: captured).toList(),
      throwsUnsupportedError,
    );
    expect(fixture.offsets, isEmpty);
  });

  test('REST STREAM feature is case insensitive', () async {
    final fixture = await server()
      ..feature = 'rest stream';
    final client = await session(fixture);
    final captured = await client.captureDownloadSnapshot('/payload.bin');
    expect(
      await client
          .downloadRange('/payload.bin', captured.size - 1, expected: captured)
          .expand((part) => part)
          .toList(),
      [fixture.payload.last],
    );
  });

  for (final code in [200, 250, 351, 450, 500, 501, 502, 504]) {
    test('REST reply $code never starts RETR', () async {
      final fixture = await server()
        ..restCode = code;
      final client = await session(fixture);
      final captured = await client.captureDownloadSnapshot('/payload.bin');
      await expectLater(
        client.downloadRange('/payload.bin', 2, expected: captured).toList(),
        throwsA(anything),
      );
      expect(fixture.commands, contains('REST 2'));
      expect(fixture.offsets, isEmpty);
      await fixture.controlPeerClosed.future.timeout(
        const Duration(seconds: 1),
      );
    });
  }

  for (final code in [450, 550, 551]) {
    test(
      'RETR refusal $code after accepted REST fails without fallback',
      () async {
        final fixture = await server()
          ..retrCode = code;
        final client = await session(fixture);
        final captured = await client.captureDownloadSnapshot('/payload.bin');
        await expectLater(
          client.downloadRange('/payload.bin', 2, expected: captured).toList(),
          throwsStateError,
        );
        expect(fixture.offsets, [2]);
      },
    );
  }

  test('PASV ignores a third-party address before the REST command', () async {
    final fixture = await server()
      ..useEpsv = false;
    final client = await session(fixture);
    final captured = await client.captureDownloadSnapshot('/payload.bin');
    expect(
      await client
          .downloadRange('/payload.bin', 3, expected: captured)
          .expand((part) => part)
          .toList(),
      fixture.payload.sublist(3),
    );
    expect(
      fixture.commands,
      containsAllInOrder(['EPSV', 'PASV', 'REST 3', 'RETR /payload.bin']),
    );
  });

  for (final mutation in [
    'modified before',
    'size before',
    'modified after',
    'size after',
  ]) {
    test('rejects a source with changed $mutation', () async {
      final fixture = await server();
      final client = await session(fixture);
      final captured = await client.captureDownloadSnapshot('/payload.bin');
      switch (mutation) {
        case 'modified before':
          fixture.modified = '20261112090000';
        case 'size before':
          fixture.sizeReply = '213 ${fixture.payload.length + 1}';
        case 'modified after':
          fixture.changeModifiedAfterData = true;
        case 'size after':
          fixture.changeSizeAfterData = true;
      }
      await expectLater(
        client.downloadRange('/payload.bin', 42, expected: captured).toList(),
        throwsStateError,
      );
      expect(fixture.offsets, mutation.endsWith('before') ? isEmpty : [42]);
    });
  }

  for (final badReply in [
    '502 No MDTM',
    '213 yesterday',
    '213 20261312080000',
    '213 20260230080000',
  ]) {
    test('unverifiable modification reply $badReply prevents resume', () async {
      final fixture = await server();
      final client = await session(fixture);
      final captured = await client.captureDownloadSnapshot('/payload.bin');
      fixture.modifiedReply = badReply;
      await expectLater(
        client.downloadRange('/payload.bin', 1, expected: captured).toList(),
        throwsA(anything),
      );
      expect(fixture.offsets, isEmpty);
    });
  }

  for (final badReply in [
    '213 -1',
    '213 5 bytes',
    '213 9999999999999999999999999999999',
  ]) {
    test('invalid SIZE reply $badReply prevents resume', () async {
      final fixture = await server();
      final client = await session(fixture);
      final captured = await client.captureDownloadSnapshot('/payload.bin');
      fixture.sizeReply = badReply;
      await expectLater(
        client.downloadRange('/payload.bin', 1, expected: captured).toList(),
        throwsStateError,
      );
      expect(fixture.offsets, isEmpty);
    });
  }

  for (final changed in ['path', 'account', 'port', 'security']) {
    test('a snapshot cannot be rebound to another $changed', () async {
      final fixture = await server();
      final client = await session(fixture);
      final captured = FtpDownloadSnapshot(
        connectionIdentity: FtpDownloadSnapshot.identity(
          host: '127.0.0.1',
          port: fixture.port + (changed == 'port' ? 1 : 0),
          username: changed == 'account' ? 'other' : 'fixture',
          securityMode: changed == 'security'
              ? FtpSecurityMode.implicitTls
              : fixture.mode,
        ),
        path: changed == 'path' ? '/other.bin' : '/payload.bin',
        size: fixture.payload.length,
        modified: fixture.modified,
      );
      await expectLater(
        client.downloadRange('/payload.bin', 1, expected: captured).toList(),
        throwsStateError,
      );
      expect(fixture.commands, isNot(contains('FEAT')));
      expect(fixture.offsets, isEmpty);
    });
  }

  for (final failure in [
    'ignored offset',
    'short data',
    'failed completion',
    'closed control',
  ]) {
    test('$failure cannot complete a resumed stream', () async {
      final fixture = await server();
      final client = await session(fixture);
      final captured = await client.captureDownloadSnapshot('/payload.bin');
      switch (failure) {
        case 'ignored offset':
          fixture.ignoreOffset = true;
        case 'short data':
          fixture.truncateTail = 1;
        case 'failed completion':
          fixture.finalCode = 426;
        case 'closed control':
          fixture.closeBeforeCompletion = true;
      }
      await expectLater(
        client
            .downloadRange('/payload.bin', 150003, expected: captured)
            .toList(),
        throwsA(anything),
      );
      expect(fixture.offsets, [150003]);
    });
  }

  test('bounded ranges still reject a short unselected tail', () async {
    final fixture = await server()
      ..truncateTail = 1;
    final client = await session(fixture);
    final captured = await client.captureDownloadSnapshot('/payload.bin');
    await expectLater(
      client
          .downloadRange('/payload.bin', 1, length: 2, expected: captured)
          .toList(),
      throwsStateError,
    );
  });

  for (final mode in [
    FtpSecurityMode.implicitTls,
    FtpSecurityMode.explicitTls,
  ]) {
    for (final certificate in [
      'wrong-host.pem',
      'expired.pem',
      'forged-issuer.pem',
    ]) {
      test('${mode.name} resumed data rejects $certificate', () async {
        final fixture = await server(mode: mode)
          ..dataCertificate = certificate;
        final client = await session(fixture);
        final captured = await client.captureDownloadSnapshot('/payload.bin');
        await expectLater(
          client.downloadRange('/payload.bin', 15, expected: captured).toList(),
          throwsA(isA<TlsException>()),
        );
        expect(fixture.protectedDataConnections, 0);
        expect(fixture.offsets, [15]);
      });
    }

    test(
      '${mode.name} subscription cancellation closes a pending data TLS handshake',
      () async {
        final fixture = await server(mode: mode)
          ..stallDataHandshake = true;
        final client = await session(fixture);
        final captured = await client.captureDownloadSnapshot('/payload.bin');
        final subscription = client
            .downloadRange('/payload.bin', 8193, expected: captured)
            .listen((_) {}, onError: (Object _) {});
        await fixture.dataHandshakeStarted.future.timeout(
          const Duration(seconds: 2),
        );
        await subscription.cancel().timeout(const Duration(seconds: 1));
        await fixture.dataPeerClosed.future.timeout(const Duration(seconds: 1));
        expect(fixture.stalledTlsPrefix.first, 22);
      },
    );
  }

  test(
    'subscription cancellation closes a control peer waiting for REST reply',
    () async {
      final fixture = await server()
        ..stallCommand = 'REST';
      final client = await session(fixture);
      final captured = await client.captureDownloadSnapshot('/payload.bin');
      final subscription = client
          .downloadRange('/payload.bin', 8193, expected: captured)
          .listen((_) {}, onError: (Object _) {});
      await fixture.stalledCommandReceived.future.timeout(
        const Duration(seconds: 2),
      );
      await subscription.cancel().timeout(const Duration(seconds: 1));
      await fixture.controlPeerClosed.future.timeout(
        const Duration(seconds: 1),
      );
      expect(fixture.offsets, isEmpty);
    },
  );

  test(
    'cancelling a resumed data stream closes its peer before teardown',
    () async {
      final fixture = await server()
        ..pauseAfterBytes = 4096
        ..releaseData = Completer<void>();
      final client = await session(fixture);
      final captured = await client.captureDownloadSnapshot('/payload.bin');
      final first = Completer<void>();
      final subscription = client
          .downloadRange('/payload.bin', 8193, expected: captured)
          .listen((_) {
            if (!first.isCompleted) first.complete();
          }, onError: (Object _) {});
      await first.future.timeout(const Duration(seconds: 2));
      await subscription.cancel().timeout(const Duration(seconds: 1));
      await fixture.dataPeerClosed.future.timeout(const Duration(seconds: 1));
      expect(fixture.offsets, [8193]);
    },
  );

  test('invalidated captured session cannot issue REST', () async {
    var current = true;
    final fixture = await server();
    final client = await session(fixture, isCurrent: () => current);
    final captured = await client.captureDownloadSnapshot('/payload.bin');
    current = false;
    await expectLater(
      client.downloadRange('/payload.bin', 7, expected: captured).toList(),
      throwsStateError,
    );
    expect(fixture.offsets, isEmpty);
  });

  test('adapter persists range evidence separately from immutable version metadata', () async {
    final fixture = await server();
    final client = await adapter(fixture);
    final source = CloudOperationBackend(client, isCurrent: () => true);
    final file = (await source.stat('/payload.bin'))!;
    expect(client.transferCapabilities.readRanges, isTrue);
    expect(client.transferCapabilities.resumableUpload, isFalse);
    expect(client.transferCapabilities.append, isFalse);
    expect(transferFileVersion(file), isNull);
    final captured = FtpDownloadSnapshot.decode(
      file.metadata!['rangeReadSnapshot'] as String,
    );
    expect(captured.modified, fixture.modified);
    expect(captured.connectionIdentity, client.transferIdentity);
    final restored = transferFileFromJson(transferFileJson(file));
    expect(restored.metadata!['rangeReadSnapshot'], captured.encode());
    expect(
      await source.readRange(restored, 9217).expand((part) => part).toList(),
      fixture.payload.sublist(9217),
    );
    expect(fixture.offsets, [9217]);
  });

  test('adapter refuses resume without the original source evidence', () async {
    final fixture = await server();
    final client = await adapter(fixture);
    await expectLater(
      client.readTransferRange('/payload.bin', 1).toList(),
      throwsUnsupportedError,
    );
    expect(fixture.offsets, isEmpty);
  });

  test(
    'adapter stream cancellation propagates while REST is pending',
    () async {
      final fixture = await server();
      final client = await adapter(fixture);
      final source = CloudOperationBackend(client, isCurrent: () => true);
      final file = (await source.stat('/payload.bin'))!;
      fixture.stallCommand = 'REST';
      final subscription = source
          .readRange(file, 8)
          .listen((_) {}, onError: (Object _) {});
      await fixture.stalledCommandReceived.future.timeout(
        const Duration(seconds: 2),
      );
      await subscription.cancel().timeout(const Duration(seconds: 1));
      await fixture.controlPeerClosed.future.timeout(
        const Duration(seconds: 1),
      );
      expect(fixture.offsets, isEmpty);
    },
  );

  for (final scenario in [
    'verified',
    'wrong prefix',
    'wrong same-length suffix',
  ]) {
    test(
      'direct conflict-resume $scenario preserves publication integrity',
      () async {
        final fixture = await server();
        final client = await adapter(fixture);
        final source = CloudOperationBackend(client, isCurrent: () => true);
        final root = await directory();
        final target = LocalOperationBackend(
          LocalFileService(),
          isCurrent: () => true,
        );
        final destination = File(p.join(root.path, 'payload.bin'));
        final prefix = fixture.payload.sublist(0, 8193);
        if (scenario == 'wrong prefix') prefix[12] ^= 1;
        await destination.writeAsBytes(prefix, flush: true);
        fixture.corruptResumedPayload = scenario == 'wrong same-length suffix';
        final plan = await const FileOperationService().prepare(
          source: source,
          destination: target,
          files: [(await source.stat('/payload.bin'))!],
          targetDirectory: root.path,
          options: const FileOperationOptions(
            fileConflict: FileConflictPolicy.resumeVerified,
          ),
        );
        expect(plan.errors, isEmpty);
        await const FileOperationService().execute(
          plan,
          control: FileOperationControl(),
        );
        if (scenario == 'verified') {
          expect(plan.entries.single.outcome, FileOperationOutcome.copied);
          expect(await destination.readAsBytes(), fixture.payload);
          expect(fixture.offsets.whereType<int>(), [8193]);
        } else {
          expect(plan.entries.single.outcome, FileOperationOutcome.failed);
          expect(await destination.readAsBytes(), prefix);
          expect(
            fixture.offsets.whereType<int>(),
            scenario == 'wrong prefix' ? isEmpty : [8193],
          );
        }
      },
    );
  }

  for (final mutation in [false, true]) {
    test(
      'durable recovery ${mutation ? 'rejects changed bytes' : 'uses the saved verified offset'}',
      () async {
        final fixture = await server();
        final client = await adapter(fixture);
        final source = CloudOperationBackend(client, isCurrent: () => true);
        final root = await directory();
        final target = LocalOperationBackend(
          LocalFileService(),
          isCurrent: () => true,
        );
        final plan = await const FileOperationService().prepare(
          source: source,
          destination: target,
          files: [(await source.stat('/payload.bin'))!],
          targetDirectory: root.path,
        );
        final stageDirectory = await Directory(
          p.join(root.path, '.crisp-transfer-saved'),
        ).create();
        final stage = File(p.join(stageDirectory.path, 'payload'));
        final prefix = fixture.payload.sublist(0, 16387);
        await stage.writeAsBytes(prefix, flush: true);
        plan.entries.single
          ..outcome = FileOperationOutcome.failed
          ..recovery = {
            'stagedPath': stage.path,
            'phase': 'writing',
            'sourceSha256': sha256.convert(fixture.payload).toString(),
          };
        final storage = MemoryTransferJournalStorage();
        final journal = TransferJournal(storage);
        await journal.create('ftp-resume', plan);
        if (mutation) fixture.payload[fixture.payload.length - 1] ^= 1;
        final restarted = TransferJournal(storage);
        await restarted.initialize();
        final preview = await const TransferRecoveryService().prepare(
          restarted.job('ftp-resume')!,
          source: source,
          destination: target,
          control: FileOperationControl(),
        );
        if (mutation) {
          expect(preview.issues, isNotEmpty);
          expect(fixture.offsets.whereType<int>(), isEmpty);
        } else {
          expect(preview.issues, isEmpty);
          expect(
            preview.plan.entries.single.recovery?['resumeStagePath'],
            stage.path,
          );
          await JournaledTransferRunner(restarted).execute(
            'ftp-resume',
            preview.plan,
            control: FileOperationControl(),
          );
          expect(
            restarted.job('ftp-resume')!.status,
            TransferJobStatus.completed,
          );
          expect(
            await File(p.join(root.path, 'payload.bin')).readAsBytes(),
            fixture.payload,
          );
          expect(fixture.offsets.whereType<int>(), [16387]);
        }
        if (await stage.exists()) expect(await stage.readAsBytes(), prefix);
      },
    );
  }

  test('actual cancelled FTP write survives a journal reload and resumes after reconnect', () async {
    final fixture = await server();
    final client = await adapter(fixture);
    final source = CloudOperationBackend(client, isCurrent: () => true);
    final root = await directory();
    final target = LocalOperationBackend(
      LocalFileService(),
      isCurrent: () => true,
    );
    final plan = await const FileOperationService().prepare(
      source: source,
      destination: target,
      files: [(await source.stat('/payload.bin'))!],
      targetDirectory: root.path,
    );
    final storage = MemoryTransferJournalStorage();
    final journal = TransferJournal(storage);
    await journal.create('cancelled-ftp', plan);
    final control = FileOperationControl();
    await JournaledTransferRunner(journal).execute(
      'cancelled-ftp',
      plan,
      control: control,
      onPhase: (_, phase) {
        if (phase == 'staging') {
          fixture.pauseAfterBytes = 8193;
          fixture.releaseData = Completer<void>();
        }
      },
      onProgress: (_, count, _) {
        if (count >= 8193) scheduleMicrotask(control.cancel);
      },
    );
    final entry = journal.job('cancelled-ftp')!.entries.single;
    expect(entry.outcome, FileOperationOutcome.cancelled);
    expect(
      entry.recovery['sourceSha256'],
      sha256.convert(fixture.payload).toString(),
    );
    final stage = File(entry.recovery['stagedPath'] as String);
    final prefix = await stage.readAsBytes();
    expect(prefix, fixture.payload.sublist(0, 8193));
    expect(await File(p.join(root.path, 'payload.bin')).exists(), isFalse);

    fixture.pauseAfterBytes = null;
    fixture.releaseData!.complete();
    await client.logout();
    final reconnected = await adapter(fixture);
    final recoveredSource = CloudOperationBackend(
      reconnected,
      isCurrent: () => true,
    );
    final restored = TransferJournal(storage);
    await restored.initialize();
    final preview = await const TransferRecoveryService().prepare(
      restored.job('cancelled-ftp')!,
      source: recoveredSource,
      destination: target,
      control: FileOperationControl(),
    );
    expect(preview.issues, isEmpty);
    expect(
      preview.plan.entries.single.recovery?['resumeStagePath'],
      stage.path,
    );
    await JournaledTransferRunner(
      restored,
    ).execute('cancelled-ftp', preview.plan, control: FileOperationControl());
    expect(restored.job('cancelled-ftp')!.status, TransferJobStatus.completed);
    expect(
      await File(p.join(root.path, 'payload.bin')).readAsBytes(),
      fixture.payload,
    );
    expect(fixture.offsets.whereType<int>(), [8193]);
  });
}
