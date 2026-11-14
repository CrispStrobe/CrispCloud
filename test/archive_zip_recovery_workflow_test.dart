import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_zip_recovery_workflow.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/zip_recovery_workflow_fixture.dart';

class _BlockedRecoveryBackend extends RecoveryWorkflowBackend {
  _BlockedRecoveryBackend() : super('blocked');
  bool blocked = false;
  final reading = Completer<void>();
  final blockedStream = StreamController<List<int>>();
  @override
  Stream<List<int>> readFile(file) {
    if (!blocked) return super.readFile(file);
    if (!reading.isCompleted) reading.complete();
    return blockedStream.stream;
  }
}

class _InvalidByteBackend extends RecoveryWorkflowBackend {
  _InvalidByteBackend() : super('invalid');
  @override
  Stream<List<int>> readFile(file) async* {
    yield [...contents[file.path]!.take(contents[file.path]!.length - 1), 256];
  }
}

void main() {
  late RecoveryWorkflowBackend source, destination;
  late Uint8List original;
  setUp(() {
    original = recoveryWorkflowZip();
    source = RecoveryWorkflowBackend('source')
      ..put('/input/broken.zip', original);
    destination = RecoveryWorkflowBackend('destination');
  });
  Future<CapturedArchiveZipRecovery> capture() async =>
      captureArchiveZipRecovery(
        source: source,
        file: (await source.stat('/input/broken.zip'))!,
      );
  Future<ArchiveCreationResult> publish(
    CapturedArchiveZipRecovery captured, {
    Set<int>? offsets,
    String name = 'recovered.zip',
    FileOperationControl? control,
    Future<void> Function(Map<String, dynamic>)? checkpoint,
  }) => publishArchiveZipRecovery(
    captured: captured,
    destination: destination,
    destinationDirectory: '/output',
    outputName: name,
    selectedOffsets:
        offsets ??
        captured.report.recoverableEntries.map((e) => e.offset).toSet(),
    control: control,
    onPublicationCheckpoint: checkpoint,
  );

  test(
    'review does not write and selected records become a separate verified ZIP',
    () async {
      final captured = await capture();
      expect(source.writes, isEmpty);
      expect(destination.writes, isEmpty);
      expect(captured.report.recoverableEntries.length, 2);
      final phases = <String>[];
      final result = await publish(
        captured,
        offsets: {captured.report.recoverableEntries.last.offset},
        checkpoint: (event) async {
          phases.add(event['phase'] as String);
        },
      );
      expect(phases, ['prepared', 'staging', 'committing', 'committed']);
      expect(result.path, '/output/recovered.zip');
      expect(result.entryCount, 1);
      final archive = await openViewerArchive(
        destination.contents[result.path]!,
        name: 'out.zip',
      );
      expect(archive.members.map((e) => e.name), ['two.txt']);
      expect(
        utf8.decode(await archive.readMember(archive.members.single)),
        'second payload',
      );
      await archive.close();
      expect(source.contents['/input/broken.zip'], original);
    },
  );

  test(
    'changed content with identical size and timestamp refuses publication',
    () async {
      final captured = await capture();
      source.contents['/input/broken.zip']!.last ^= 1;
      await expectLater(publish(captured), throwsStateError);
      expect(destination.writes, isEmpty);
    },
  );

  test(
    'changed source at the final commit boundary refuses publication',
    () async {
      final captured = await capture();
      destination.beforeCommit = () async {
        source.contents['/input/broken.zip']!.last ^= 1;
      };
      await expectLater(publish(captured), throwsStateError);
      expect(destination.writes, isEmpty);
    },
  );

  test(
    'staged payload corruption is detected before the new file exists',
    () async {
      final captured = await capture();
      destination.corruptStage = true;
      await expectLater(publish(captured), throwsStateError);
      expect(
        destination.contents.containsKey('/output/recovered.zip'),
        isFalse,
      );
      expect(source.contents['/input/broken.zip'], original);
    },
  );

  test(
    'existing output and a collision arriving during commit are retained',
    () async {
      final captured = await capture();
      destination.put('/output/recovered.zip', [4, 5]);
      await expectLater(publish(captured), throwsStateError);
      expect(destination.contents['/output/recovered.zip'], [4, 5]);
      destination.contents.remove('/output/recovered.zip');
      destination.beforeCommit = () async {
        destination.put('/output/recovered.zip', [6, 7]);
      };
      await expectLater(publish(captured), throwsStateError);
      expect(destination.contents['/output/recovered.zip'], [6, 7]);
      expect(destination.writes, isEmpty);
    },
  );

  test(
    'publication freezes selected offsets before its first asynchronous check',
    () async {
      final captured = await capture();
      final selection = {captured.report.recoverableEntries.first.offset};
      final pending = publish(captured, offsets: selection);
      selection
        ..clear()
        ..add(captured.report.recoverableEntries.last.offset);
      final result = await pending;
      final archive = await openViewerArchive(
        destination.contents[result.path]!,
        name: 'result.zip',
      );
      expect(archive.members.map((m) => m.name), ['one.txt']);
      await archive.close();
    },
  );

  for (final scanning in [true, false]) {
    test(
      'Stop interrupts a blocked ${scanning ? 'scan' : 'publication proof'} read',
      () async {
        final backend = _BlockedRecoveryBackend()
          ..put('/input/broken.zip', original);
        addTearDown(() {
          unawaited(backend.blockedStream.close());
        });
        final control = FileOperationControl();
        final captured = scanning
            ? null
            : await captureArchiveZipRecovery(
                source: backend,
                file: (await backend.stat('/input/broken.zip'))!,
              );
        backend.blocked = true;
        final pending = scanning
            ? captureArchiveZipRecovery(
                source: backend,
                file: (await backend.stat('/input/broken.zip'))!,
                control: control,
              )
            : publish(captured!, control: control);
        await backend.reading.future;
        control.cancel();
        await expectLater(
          pending.timeout(const Duration(seconds: 2)),
          throwsA(isA<FileOperationCancelled>()),
        );
        expect(destination.writes, isEmpty);
      },
    );
  }

  test(
    'invalid provider bytes are rejected before a snapshot can be reviewed',
    () async {
      final backend = _InvalidByteBackend()..put('/input/broken.zip', original);
      await expectLater(
        captureArchiveZipRecovery(
          source: backend,
          file: (await backend.stat('/input/broken.zip'))!,
        ),
        throwsStateError,
      );
      expect(destination.writes, isEmpty);
    },
  );

  test('source filename cannot be its own recovery destination', () async {
    final captured = await capture();
    await expectLater(
      publishArchiveZipRecovery(
        captured: captured,
        destination: source,
        destinationDirectory: '/input',
        outputName: 'broken.zip',
        selectedOffsets: captured.report.recoverableEntries
            .map((e) => e.offset)
            .toSet(),
      ),
      throwsStateError,
    );
    expect(source.writes, isEmpty);
  });

  test(
    'cancellation at final boundary stops before exclusive install',
    () async {
      final captured = await capture();
      final control = FileOperationControl();
      destination.beforeCommit = () async {
        control.cancel();
      };
      await expectLater(
        publish(captured, control: control),
        throwsA(isA<FileOperationCancelled>()),
      );
      expect(destination.writes, isEmpty);
      expect(source.contents['/input/broken.zip'], original);
    },
  );

  test(
    'pause then source change cannot use an earlier verification result',
    () async {
      final captured = await capture();
      final control = FileOperationControl();
      final paused = Completer<void>();
      destination.beforeCommit = () async {
        control.pause();
        paused.complete();
      };
      final pending = publish(captured, control: control);
      await paused.future;
      expect(destination.writes, isEmpty);
      source.contents['/input/broken.zip']!.last ^= 1;
      control.resume();
      await expectLater(pending, throwsStateError);
      expect(destination.writes, isEmpty);
    },
  );

  test(
    'install remains successful after Stop and a completion observer failure',
    () async {
      final captured = await capture();
      final control = FileOperationControl();
      destination.afterInstall = control.cancel;
      final result = await publish(
        captured,
        control: control,
        checkpoint: (event) async {
          if (event['phase'] == 'committed') {
            throw StateError('journal offline');
          }
        },
      );
      expect(result.path, '/output/recovered.zip');
      expect(result.publicationWarning, isA<StateError>());
      expect(destination.writes, ['/output/recovered.zip']);
      expect(source.contents['/input/broken.zip'], original);
    },
  );

  test(
    'source revocation after review refuses both decode and publication',
    () async {
      final captured = await capture();
      source.current = false;
      await expectLater(publish(captured), throwsStateError);
      expect(destination.writes, isEmpty);
    },
  );

  test(
    'symlink destination parent and oversized source are rejected',
    () async {
      source.advertisedSizes['/input/broken.zip'] = 64 * 1024 * 1024 + 1;
      await expectLater(capture(), throwsA(isA<ArchiveViewException>()));
      source.advertisedSizes.clear();
      final captured = await capture();
      destination.directories.remove('/output');
      destination.links.add('/output');
      await expectLater(publish(captured), throwsStateError);
      expect(destination.writes, isEmpty);
    },
  );
}
