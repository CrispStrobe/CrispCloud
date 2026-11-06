import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/models/operation_progress.dart';

void main() {
  group('OperationProgress', () {
    test('creates with correct initial state', () {
      final op = OperationProgress(
        id: 'op-1',
        type: OperationType.upload,
        sourcePath: '/local/test.txt',
        targetPath: '/remote/test.txt',
        fileName: 'test.txt',
        totalBytes: 1024,
      );

      expect(op.type, equals(OperationType.upload));
      expect(op.fileName, equals('test.txt'));
      expect(op.totalBytes, equals(1024));
      expect(op.currentBytes, equals(0));
      expect(op.isComplete, isFalse);
      expect(op.isCancelled, isFalse);
      expect(op.progress, equals(0.0));
    });

    test('progress updates correctly', () {
      final op = OperationProgress(
        id: 'op-2',
        type: OperationType.download,
        sourcePath: '/remote/file.pdf',
        targetPath: '/local/file.pdf',
        fileName: 'file.pdf',
        totalBytes: 1000,
      );

      op.currentBytes = 500;
      expect(op.progress, closeTo(0.5, 0.01));

      op.currentBytes = 1000;
      expect(op.progress, closeTo(1.0, 0.01));
    });

    test('handles zero totalBytes', () {
      final op = OperationProgress(
        id: 'op-3',
        type: OperationType.upload,
        sourcePath: '/local/empty.txt',
        targetPath: '/remote/empty.txt',
        fileName: 'empty.txt',
        totalBytes: 0,
      );

      expect(op.progress, equals(0.0));
    });

    test('cancel sets isCancelled', () {
      final op = OperationProgress(
        id: 'op-4',
        type: OperationType.upload,
        sourcePath: '/local/test.txt',
        targetPath: '/remote/test.txt',
        fileName: 'test.txt',
        totalBytes: 100,
      );

      op.cancel();
      expect(op.isCancelled, isTrue);
    });

    test('complete() sets isComplete', () {
      final op = OperationProgress(
        id: 'op-5',
        type: OperationType.upload,
        sourcePath: '/local/test.txt',
        targetPath: '/remote/test.txt',
        fileName: 'test.txt',
        totalBytes: 100,
      );

      op.complete();
      expect(op.isComplete, isTrue);
    });

    test('fail() stores error message', () {
      final op = OperationProgress(
        id: 'op-6',
        type: OperationType.upload,
        sourcePath: '/local/test.txt',
        targetPath: '/remote/test.txt',
        fileName: 'test.txt',
        totalBytes: 100,
      );

      op.fail('Upload failed');
      expect(op.error, equals('Upload failed'));
      expect(op.error != null, isTrue);
    });
  });

  group('OperationType', () {
    test('has all expected values', () {
      expect(OperationType.values, contains(OperationType.upload));
      expect(OperationType.values, contains(OperationType.download));
      expect(OperationType.values, contains(OperationType.move));
      expect(OperationType.values, contains(OperationType.copy));
      expect(OperationType.values, contains(OperationType.delete));
    });
  });

  test('pause, resume and a restarted stream reset throughput and ETA', () {
    var clock = DateTime.utc(2026);
    final operation = OperationProgress(
      id: 'rate',
      type: OperationType.copy,
      sourcePath: '/a',
      targetPath: '/b',
      fileName: 'a',
      totalBytes: 1000,
      now: () => clock,
    );
    operation.updateProgress(0);
    clock = clock.add(const Duration(seconds: 1));
    operation.updateProgress(100);
    expect(operation.currentSpeed, 100);
    expect(operation.estimatedSecondsRemaining, 9);
    operation.pause();
    expect(operation.currentSpeed, 0);
    expect(operation.estimatedSecondsRemaining, 0);
    clock = clock.add(const Duration(hours: 1));
    operation.resume();
    operation.updateProgress(100);
    clock = clock.add(const Duration(seconds: 1));
    operation.updateProgress(200);
    expect(operation.currentSpeed, 100);
    operation.updateProgress(0);
    expect(operation.currentSpeed, 0);
    expect(operation.estimatedSecondsRemaining, 0);
    clock = clock.add(const Duration(seconds: 1));
    operation.updateProgress(100);
    expect(operation.currentSpeed, 100);
    operation.complete();
    expect(operation.currentSpeed, 0);
    expect(operation.estimatedSecondsRemaining, 0);
  });

  test('processed counts distinguish skipped rows from successful copies', () {
    final operation = OperationProgress(
      id: 'filtered',
      type: OperationType.copy,
      sourcePath: '/source',
      targetPath: '/target',
      fileName: 'batch',
      files: [
        FileProgress(
          name: 'copied',
          path: '/copied',
          size: 10,
          isComplete: true,
        ),
        FileProgress(
          name: 'skip',
          path: '/skip',
          size: 10,
          statusLabel: 'skipped',
        ),
        FileProgress(
          name: 'filter',
          path: '/filter',
          size: 10,
          statusLabel: 'filtered',
        ),
        FileProgress(name: 'pending', path: '/pending', size: 10),
      ],
    );
    expect(operation.completedFiles, 1);
    expect(operation.skippedFiles, 2);
    expect(operation.processedFiles, 3);
    expect(operation.totalFiles, 4);
  });
}
