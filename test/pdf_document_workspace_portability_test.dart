import 'dart:typed_data';

import 'package:crisp_cloud/services/document_conversion.dart';
import 'package:crisp_cloud/services/document_history.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart' show PdfBlankDocument;
import 'package:quds_office_editor/quds_office_editor.dart'
    show WordEditorController;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('portable history export preserves account scope without enabling opened logging', () async {
    final history = DocumentHistory();
    await history.record(
      const FileReference(
        storage: StorageReference(
          kind: 'remote',
          provider: 'webdav',
          accountKey: 'account-one',
        ),
        path: '/notes.docx',
      ),
      edited: true,
    );
    final copy = DocumentHistory();
    await copy.importJson(history.exportJson());
    expect(copy.entries.single.file.storage.accountKey, 'account-one');
    expect(copy.recordOpens, isFalse);
    await copy.purge();
    expect(copy.entries, isEmpty);
    history.dispose();
    copy.dispose();
  });
  test('portable PDF conversion returns a valid editable package and explicit OCR limits', () async {
    final Uint8List source = PdfBlankDocument.create();
    final result = await convertDocument(
      source,
      sourceName: 'scan.pdf',
      extension: 'docx',
    );
    expect(result.notices.join(' '), contains('OCR'));
    final editor = WordEditorController.fromBytes(result.bytes);
    expect(editor.document.sections, isNotEmpty);
    editor.dispose();
  });
}
