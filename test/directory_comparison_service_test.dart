import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/directory_comparison_service.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';

import 'support/workflow_fake_client.dart';

void main() {
  test(
    'missing comparison roots cannot masquerade as empty directories',
    () async {
      final a = WorkflowFakeClient()..put('/a/file', [1]);
      final b = WorkflowFakeClient();
      final service = DirectoryComparisonService();
      final plan = await service.compare(
        left: CloudOperationBackend(a, isCurrent: () => true),
        right: CloudOperationBackend(b, isCurrent: () => true),
        leftRoot: '/a',
        rightRoot: '/missing',
      );
      expect(plan.errors.single, contains('missing or unavailable'));
      await expectLater(
        service.apply(plan, {}, control: FileOperationControl()),
        throwsStateError,
      );
      expect(b.writes, isEmpty);
    },
  );

  test('changes to a later reviewed target during an earlier copy stop replacement', () async {
    final a = WorkflowFakeClient()
      ..put('/a/first', [1])
      ..put('/a/second', [2]);
    final b = WorkflowFakeClient()
      ..put('/b/first', [8])
      ..put('/b/second', [9]);
    final service = DirectoryComparisonService();
    final plan = await service.compare(
      left: CloudOperationBackend(a, isCurrent: () => true),
      right: CloudOperationBackend(b, isCurrent: () => true),
      leftRoot: '/a',
      rightRoot: '/b',
    );
    await expectLater(
      service.apply(
        plan,
        {
          'first': DirectoryComparisonAction.copyToRight,
          'second': DirectoryComparisonAction.copyToRight,
        },
        control: FileOperationControl(),
        onProgress: (path) {
          if (path.endsWith('/first')) b.put('/b/second', [7]);
        },
      ),
      throwsStateError,
    );
    expect(b.files['/b/first'], [1]);
    expect(b.files['/b/second'], [7]);
  });

  test('recursive cloud comparison verifies contents and identifies unique/type-conflict rows', () async {
    final a = WorkflowFakeClient()
      ..put('/a/sub/same.txt', [1])
      ..put('/a/different.txt', [2])
      ..put('/a/unique', [3]);
    final b = WorkflowFakeClient()
      ..put('/b/sub/same.txt', [1])
      ..put('/b/different.txt', [9]);
    b.directories.add('/b/unique');
    final plan = await DirectoryComparisonService().compare(
      left: CloudOperationBackend(a, isCurrent: () => true),
      right: CloudOperationBackend(b, isCurrent: () => true),
      leftRoot: '/a',
      rightRoot: '/b',
    );
    expect(plan.errors, isEmpty);
    final rows = {for (final row in plan.rows) row.relativePath: row};
    expect(rows['sub/same.txt']!.status, DirectoryComparisonStatus.equal);
    expect(rows['different.txt']!.status, DirectoryComparisonStatus.different);
    expect(rows['unique']!.status, DirectoryComparisonStatus.typeConflict);
    expect(rows['unique']!.choices, [DirectoryComparisonAction.skip]);
    expect(a.writes, isEmpty);
    expect(b.writes, isEmpty);
  });

  test(
    'applying a directory row never implicitly copies unchecked descendants',
    () async {
      final temp = await Directory.systemTemp.createTemp('compare-selection-');
      addTearDown(() => temp.delete(recursive: true));
      final left = await Directory('${temp.path}/left/sub')
          .create(recursive: true);
      await File('${left.path}/checked.txt').writeAsString('chosen');
      await File('${left.path}/unchecked.txt').writeAsString('retain');
      final right = await Directory('${temp.path}/right').create();
      final backend = LocalOperationBackend(
        LocalFileService(),
        isCurrent: () => true,
      );
      final service = DirectoryComparisonService();
      final plan = await service.compare(
        left: backend,
        right: backend,
        leftRoot: '${temp.path}/left',
        rightRoot: right.path,
      );
      final errors = await service.apply(plan, {
        'sub': DirectoryComparisonAction.copyToRight,
        'sub/checked.txt': DirectoryComparisonAction.copyToRight,
      }, control: FileOperationControl());
      expect(errors, isEmpty);
      expect(
        await File('${right.path}/sub/checked.txt').readAsString(),
        'chosen',
      );
      expect(await File('${right.path}/sub/unchecked.txt').exists(), isFalse);
    },
  );

  test('content changes with unchanged metadata invalidate selected copy before writes', () async {
    final a = WorkflowFakeClient()..put('/a/file', [1]);
    final b = WorkflowFakeClient()..put('/b/file', [2]);
    final service = DirectoryComparisonService();
    final plan = await service.compare(
      left: CloudOperationBackend(a, isCurrent: () => true),
      right: CloudOperationBackend(b, isCurrent: () => true),
      leftRoot: '/a',
      rightRoot: '/b',
    );
    b.put('/b/file', [3]);
    await expectLater(
      service.apply(plan, {
        'file': DirectoryComparisonAction.copyToRight,
      }, control: FileOperationControl()),
      throwsStateError,
    );
    expect(b.files['/b/file'], [3]);
    expect(b.writes, isEmpty);
  });

  test('source changes invalidate comparison execution', () async {
    var current = true;
    final a = WorkflowFakeClient()..put('/a/file', [1]);
    final b = WorkflowFakeClient()..directories.add('/b');
    final service = DirectoryComparisonService();
    final plan = await service.compare(
      left: CloudOperationBackend(a, isCurrent: () => current),
      right: CloudOperationBackend(b, isCurrent: () => true),
      leftRoot: '/a',
      rightRoot: '/b',
    );
    current = false;
    await expectLater(
      service.apply(plan, {
        'file': DirectoryComparisonAction.copyToRight,
      }, control: FileOperationControl()),
      throwsStateError,
    );
    expect(b.writes, isEmpty);
  });
}
