import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/models/operation_progress.dart';

void main() {
  group('OperationProgress', () {
    test('creates with correct initial state', () {
      final op = OperationProgress(
        type: OperationType.upload,
        fileName: 'test.txt',
        totalBytes: 1024,
      );

      expect(op.type, equals(OperationType.upload));
      expect(op.fileName, equals('test.txt'));
      expect(op.totalBytes, equals(1024));
      expect(op.bytesTransferred, equals(0));
      expect(op.isComplete, isFalse);
      expect(op.isCancelled, isFalse);
      expect(op.progress, equals(0.0));
    });

    test('progress updates correctly', () {
      final op = OperationProgress(
        type: OperationType.download,
        fileName: 'file.pdf',
        totalBytes: 1000,
      );

      op.bytesTransferred = 500;
      expect(op.progress, closeTo(0.5, 0.01));

      op.bytesTransferred = 1000;
      expect(op.progress, closeTo(1.0, 0.01));
    });

    test('handles zero totalBytes', () {
      final op = OperationProgress(
        type: OperationType.upload,
        fileName: 'empty.txt',
        totalBytes: 0,
      );

      expect(op.progress, equals(0.0));
    });

    test('cancel sets isCancelled', () {
      final op = OperationProgress(
        type: OperationType.upload,
        fileName: 'test.txt',
        totalBytes: 100,
      );

      op.cancel();
      expect(op.isCancelled, isTrue);
    });

    test('markComplete sets isComplete', () {
      final op = OperationProgress(
        type: OperationType.upload,
        fileName: 'test.txt',
        totalBytes: 100,
      );

      op.markComplete();
      expect(op.isComplete, isTrue);
    });

    test('markError stores error message', () {
      final op = OperationProgress(
        type: OperationType.upload,
        fileName: 'test.txt',
        totalBytes: 100,
      );

      op.markError('Upload failed');
      expect(op.error, equals('Upload failed'));
      expect(op.hasError, isTrue);
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
