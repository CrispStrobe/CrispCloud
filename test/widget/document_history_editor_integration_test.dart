import 'package:crisp_cloud/services/document_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import '../support/office_test_harness.dart';

void main() {
  testWidgets(
    'only successful Office saves enter recent edits on the captured storage',
    (tester) async {
      await tester.runAsync(() async {
        final host = await OfficeTestHarness.open(tester);
        final history = host.container.read(documentHistoryProvider);
        await history.ready;
        expect(
          history.entries,
          isEmpty,
        ); // opening an editor is not a successful edit
        final controller = host.controller as WordEditorController;
        controller.insertText('Saved change');
        host.cloud.failUploads = true;
        await host.save();
        expect(history.entries, isEmpty);
        host.cloud.failUploads = false;
        await host.save();
        for (var i = 0; i < 50 && history.entries.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(history.entries.single.file.path, '/report.docx');
        expect(history.entries.single.file.storage.isLocal, isFalse);
        expect(history.entries.single.editedAt, isNotNull);
        expect(history.entries.single.openedAt, isNull);
        await host.dispose();
      });
    },
  );
}
