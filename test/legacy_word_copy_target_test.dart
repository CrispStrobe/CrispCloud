import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/legacy_word_copy_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../packages/quds_office_engine/test/support/legacy_word_fixture.dart';
import 'support/workflow_fake_client.dart';

void main() {
  late WorkflowFakeClient cloud;
  late LegacyWordCopyTarget target;
  final original = legacyWordFixture('Original Word text\r');

  setUp(() {
    cloud = WorkflowFakeClient()..put('/original/notes.doc', original);
    target = LegacyWordCopyTarget(
      backend: CloudOperationBackend(cloud, isCurrent: () => cloud.current),
      sourcePath: '/original/notes.doc',
    );
  });

  test(
    'creates and verifies a sibling copy without changing original',
    () async {
      final converted = convertLegacyWordToDocx(original);
      final created = await target.create(
        LegacyWordDocxCopy(fileName: 'notes (text).docx', bytes: converted),
      );
      expect(created.path, '/original/notes (text).docx');
      expect(cloud.files[created.path], converted);
      expect(cloud.files['/original/notes.doc'], original);
    },
  );

  test('an existing output is never overwritten', () async {
    cloud.put('/original/notes.docx', [7, 8, 9]);
    await expectLater(
      target.create(
        LegacyWordDocxCopy(fileName: 'notes.docx', bytes: original),
      ),
      throwsStateError,
    );
    expect(cloud.files['/original/notes.docx'], [7, 8, 9]);
    expect(cloud.writes, isEmpty);
  });

  test('directory changes cannot be injected through the filename', () async {
    await expectLater(
      target.create(
        LegacyWordDocxCopy(fileName: '../notes.docx', bytes: original),
      ),
      throwsA(isA<LegacyWordConversionException>()),
    );
    expect(cloud.writes, isEmpty);
  });

  test('disconnection blocks creation on the captured storage', () async {
    cloud.current = false;
    await expectLater(
      target.create(
        LegacyWordDocxCopy(fileName: 'notes.docx', bytes: original),
      ),
      throwsStateError,
    );
    expect(cloud.writes, isEmpty);
    expect(cloud.files['/original/notes.doc'], original);
  });
}
