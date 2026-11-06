import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/duplicate_finder_service.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';

import 'support/workflow_fake_client.dart';

void main() {
  test('remote equal-size different content remains distinct; exact matches verify', () async {
    final client = WorkflowFakeClient()
      ..put('/a.txt', 'first'.codeUnits)
      ..put('/b.txt', 'other'.codeUnits)
      ..put('/c.txt', 'first'.codeUnits);
    final source = CloudOperationBackend(
      client,
      isCurrent: () => client.current,
    );
    final result = await DuplicateFinderService().scan(
      source,
      await source.list('/'),
    );
    expect(result.groups, hasLength(1));
    expect(
      result.groups.single.map((file) => file.path),
      unorderedEquals(['/a.txt', '/c.txt']),
    );
    expect(result.checkedFiles, 3);
    expect(result.errors, isEmpty);
  });

  test(
    'empty files verify and repeated source paths do not create fake groups',
    () async {
      final client = WorkflowFakeClient()
        ..put('/a', [])
        ..put('/b', []);
      final source = CloudOperationBackend(client, isCurrent: () => true);
      final files = await source.list('/');
      final result = await DuplicateFinderService().scan(source, [
        ...files,
        files.first,
      ]);
      expect(result.groups.single, hasLength(2));
    },
  );

  test('cancellation stops content reads without reporting candidates as duplicates', () async {
    final client = WorkflowFakeClient()
      ..put('/a', [1])
      ..put('/b', [1]);
    final source = CloudOperationBackend(client, isCurrent: () => true);
    final result = await DuplicateFinderService().scan(
      source,
      await source.list('/'),
      isCancelled: () => true,
    );
    expect(result.cancelled, isTrue);
    expect(result.groups, isEmpty);
    expect(result.checkedFiles, 0);
  });

  test('stale account never produces verified groups', () async {
    final client = WorkflowFakeClient()
      ..put('/a', [1])
      ..put('/b', [1]);
    final source = CloudOperationBackend(
      client,
      isCurrent: () => client.current,
    );
    final files = await source.list('/');
    client.current = false;
    final result = await DuplicateFinderService().scan(source, files);
    expect(result.groups, isEmpty);
    expect(result.errors, hasLength(2));
  });
}
