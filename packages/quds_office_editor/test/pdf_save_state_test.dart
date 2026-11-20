import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

Uint8List _fixture() {
  final document = PdfDocument(title: 'Saved fixture');
  document.addPage(
    PdfPage(
      width: 300,
      height: 400,
      content:
          (PdfCanvas(300, 400)
                ..rect(10, 10, 40, 20)
                ..fill())
              .toStream(),
    ),
  );
  return document.save();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDF rotation has undo/redo and viewing mode cannot mutate it', () {
    final c = PdfEditorController.fromBytes(_fixture());
    addTearDown(c.dispose);
    c.markClean();
    c.rotateCurrentPage(90);
    expect(c.file!.pageAt(0).rotate, 90);
    expect(c.commands.canUndo, isTrue);
    c.undo();
    expect(c.file!.pageAt(0).rotate, 0);
    c.redo();
    expect(c.file!.pageAt(0).rotate, 90);
    final view = PdfEditorController.fromBytes(
      _fixture(),
      config: const OfficeSurfaceConfig(mode: OfficeInteractionMode.viewing),
    );
    addTearDown(view.dispose);
    view.rotateCurrentPage(90);
    expect(view.file!.pageAt(0).rotate, 0);
    expect(view.contentRevision, 0);
  });

  test(
    'PDF encoding is repeatable and does not commit annotation or page IDs',
    () {
      final controller = PdfEditorController.fromBytes(_fixture());
      addTearDown(controller.dispose);
      controller.addNote(
        const PdfRect(x: 10, y: 20, width: 20, height: 20),
        'Keep this note',
      );
      controller.insertBlankPage(1);
      final file = controller.file!;
      final note = file.annotsOn(0).single;
      final blank = file.pageRec(1);
      expect(note.objectId, isNull);
      expect(blank.objectId, isNull);
      final first = controller.saveBytes();
      expect(note.objectId, isNull);
      expect(blank.objectId, isNull);
      expect(blank.dict.values, isEmpty);
      final second = controller.saveBytes();
      expect(second, first);
      for (final bytes in <Uint8List>[first, second]) {
        final reopened = PdfFile.open(bytes);
        expect(reopened.pageCount, 2);
        expect(reopened.annotsOn(0).single.contents, 'Keep this note');
      }
      expect(controller.isDirty, isTrue);
    },
  );

  test(
    'markClean preserves PDF undo and later edits cannot inherit save state',
    () {
      final controller = PdfEditorController.fromBytes(_fixture());
      addTearDown(controller.dispose);
      controller.addNote(
        const PdfRect(x: 10, y: 20, width: 20, height: 20),
        'Saved note',
      );
      final savedRevision = controller.contentRevision;
      controller.saveBytes();
      expect(controller.isDirty, isTrue);
      controller.markClean();
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isTrue);
      controller.setScale(1.5, animate: false);
      controller.goToPage(0);
      expect(controller.contentRevision, savedRevision);
      expect(controller.isDirty, isFalse);
      controller.undo();
      expect(controller.contentRevision, greaterThan(savedRevision));
      expect(controller.isDirty, isTrue);
      expect(controller.file!.annotsOn(0), isEmpty);
      controller.redo();
      expect(controller.file!.annotsOn(0).single.contents, 'Saved note');
      expect(PdfFile.open(controller.saveBytes()).annotsOn(0), hasLength(1));
    },
  );

  test('page and form changes advance PDF save revisions', () {
    final controller = PdfEditorController.fromBytes(_fixture());
    addTearDown(controller.dispose);
    controller.file!.form.fields.add(PdfFormField(name: 'Name', type: 'Tx'));
    controller.markClean();
    final initial = controller.contentRevision;
    controller.setFieldValue('Name', 'CrispOffice');
    expect(controller.contentRevision, greaterThan(initial));
    expect(controller.isDirty, isTrue);
    controller.markClean();
    final filled = controller.contentRevision;
    controller.setFieldValue('Name', 'CrispOffice');
    expect(controller.contentRevision, filled);
    controller.rotatePageAt(0, 90);
    expect(controller.isDirty, isTrue);
    controller.markClean();
    controller.insertBlankPage(1);
    expect(controller.isDirty, isTrue);
    controller.markClean();
    controller.deletePageAt(1);
    expect(controller.isDirty, isTrue);
  });

  test(
    'async PDF encoding snapshots content and replacement clears old history',
    () async {
      final controller = PdfEditorController.fromBytes(_fixture());
      addTearDown(controller.dispose);
      controller.addNote(
        const PdfRect(x: 10, y: 20, width: 20, height: 20),
        'First note',
      );
      final before = controller.contentRevision;
      final pending = controller.saveBytesAsync();
      controller.addNote(
        const PdfRect(x: 40, y: 20, width: 20, height: 20),
        'Later note',
      );
      final saved = await pending;
      expect(controller.contentRevision, greaterThan(before));
      expect(controller.isDirty, isTrue);
      expect(
        PdfFile.open(saved).annotsOn(0).map((note) => note.contents),
        <String>['First note'],
      );
      expect(
        controller.file!.annotsOn(0).every((note) => note.objectId == null),
        isTrue,
      );
      await controller.loadBytesAsync(_fixture());
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isFalse);
      expect(controller.file!.annotsOn(0), isEmpty);
    },
  );
}
