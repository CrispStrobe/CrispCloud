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
}
