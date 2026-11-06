import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/read_only_operation_backend.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/workflow_fake_client.dart';

void main() {
  test(
    'snapshot source stops streaming after its captured account changes',
    () async {
      final client = WorkflowFakeClient()..put('/file', [1, 2, 3, 4]);
      var available = true;
      final source = ReadOnlyOperationBackend(
        CloudOperationBackend(client, isCurrent: () => true),
        isAvailable: () => available,
      );
      final file = (await source.stat('/file'))!;
      final chunks = <List<int>>[];
      await expectLater(() async {
        await for (final chunk in source.readFile(file)) {
          chunks.add(chunk);
          available = false;
        }
      }(), throwsStateError);
      expect(chunks, [
        [1, 2],
      ]);
      expect(source.canRecover, isFalse);
      expect(source.persistentStorageId, isNull);
      await expectLater(source.deleteFile(file), throwsUnsupportedError);
      expect(client.files['/file'], [1, 2, 3, 4]);
    },
  );
}
