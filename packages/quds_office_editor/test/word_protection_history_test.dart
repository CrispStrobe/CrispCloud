import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WordEditorController controller({
  WmlDocument? document,
  OfficeSurfaceConfig? config,
}) {
  final result = WordEditorController(
    document: document ?? WmlDocument.empty(text: 'Body'),
    config: config,
  );
  addTearDown(result.dispose);
  return result;
}

WmlDocument imported(String attributes) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package.createPart(
    '/word/settings.xml',
    OfficeContentTypes.wordSettings,
    utf8.encode(
      '<w:settings xmlns:w="${OfficeNamespaces.w}"><w:documentProtection $attributes/></w:settings>',
    ),
  );
  package
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.settings, target: 'settings.xml');
  return WordDeserializer().read(package);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'protection is dirty, revision tracked, and undoable while read-only',
    () async {
      final word = controller();
      final initial = word.contentRevision;
      word.setRestrictEditing(true);
      expect(word.isDirty, isTrue);
      expect(word.contentRevision, initial + 1);
      expect(word.config.allowsMutation, isFalse);
      expect(word.canUndo, isTrue);
      word.insertText('blocked');
      expect(word.document.paragraphs.single.text, 'Body');
      final protectedBytes = await word.saveBytesAsync();
      expect(
        WordDeserializer().readBytes(protectedBytes).restrictEditing,
        isTrue,
      );
      expect(word.isDirty, isTrue);
      word.markClean();
      for (var cycle = 0; cycle < 3; cycle++) {
        word.undo();
        expect(word.document.restrictEditing, isFalse);
        expect(word.config.allowsMutation, isTrue);
        expect(word.isDirty, isTrue);
        word.redo();
        expect(word.document.restrictEditing, isTrue);
        expect(word.config.allowsMutation, isFalse);
      }
      expect(word.contentRevision, initial + 7);
    },
  );

  test('host rebuilds retain restrictions and host viewing blocks history', () {
    final word = controller();
    word.setRestrictEditing(true);
    word.syncConfig(const OfficeSurfaceConfig());
    expect(word.config.allowsMutation, isFalse);
    expect(word.canChangeProtection, isTrue);
    word.syncConfig(
      const OfficeSurfaceConfig(mode: OfficeInteractionMode.selecting),
    );
    final revision = word.contentRevision;
    word.undo();
    word.setRestrictEditing(false);
    expect(word.document.restrictEditing, isTrue);
    expect(word.contentRevision, revision);
    expect(word.config.mode, OfficeInteractionMode.selecting);
    word.setMode(OfficeInteractionMode.editing);
    expect(word.config.allowsMutation, isFalse);
    word.undo();
    expect(word.config.allowsMutation, isTrue);
  });

  test(
    'only a protection command may cross the read-only history boundary',
    () {
      final word = controller();
      word.insertText('X');
      word.setRestrictEditing(true);
      word.setRestrictEditing(false);
      word.undo();
      expect(word.document.restrictEditing, isTrue);
      expect(word.canRedo, isTrue);
      word.redo();
      expect(word.document.restrictEditing, isFalse);
      word.undo();
      word.undo();
      expect(word.document.restrictEditing, isFalse);
      word.undo();
      expect(word.document.paragraphs.single.text, 'Body');
    },
  );

  for (final mode in WmlRestrictMode.values.where(
    (mode) => mode != WmlRestrictMode.none,
  )) {
    test('imported ${mode.name} cannot be bypassed by editing config', () {
      final word = controller(
        document: imported('w:enforcement="1" w:edit="${mode.name}"'),
      );
      expect(word.config.allowsMutation, isFalse);
      word.config = const OfficeSurfaceConfig();
      word.syncConfig(const OfficeSurfaceConfig());
      word.setMode(OfficeInteractionMode.editing);
      expect(word.config.allowsMutation, isFalse);
      expect(word.canUndo, isFalse);
      word.setRestrictEditing(false);
      expect(word.document.restrictEditing, isFalse);
      word.undo();
      expect(word.document.restrictEditing, isTrue);
      expect(word.document.restrictMode, mode);
      expect(word.config.allowsMutation, isFalse);
    });
  }

  test(
    'password protection cannot be removed or changed without verification',
    () {
      final word = controller(
        document: imported(
          'w:enforcement="1" w:edit="forms" w:hash="AAAA" w:salt="AQID"',
        ),
      );
      expect(word.canChangeProtection, isFalse);
      word.setRestrictEditing(false);
      word.setRestrictEditing(true, mode: WmlRestrictMode.none);
      word.undo();
      expect(word.isDirty, isFalse);
      expect(word.document.restrictEditing, isTrue);
      expect(word.document.restrictMode, WmlRestrictMode.forms);
      expect(word.config.allowsMutation, isFalse);
    },
  );

  test('formatting-only native restriction stays conservatively read-only', () {
    final word = controller(
      document: imported('w:enforcement="1" w:edit="none" w:formatting="1"'),
    );
    expect(word.document.restrictMode, WmlRestrictMode.none);
    expect(word.config.allowsMutation, isFalse);
    word.applyParagraphFormat((properties) => properties.spacingBefore = 22);
    expect(word.isDirty, isFalse);
  });

  test(
    'new document loading clears old history and effective restrictions',
    () {
      final word = controller();
      word.setRestrictEditing(true);
      word.loadBytes(
        WordSerializer().writeBytes(WmlDocument.empty(text: 'Replacement')),
      );
      expect(word.canUndo, isFalse);
      expect(word.canRedo, isFalse);
      expect(word.config.allowsMutation, isTrue);
      word.undo();
      expect(word.document.paragraphs.single.text, 'Replacement');
      expect(word.document.restrictEditing, isFalse);
    },
  );

  test(
    'unchanged protection is a no-op and pending notes precede protection',
    () {
      final word = controller();
      word.setRestrictEditing(false);
      expect(word.isDirty, isFalse);
      word.insertFootnote(text: 'Original note');
      final note = word.document.footnotes.single;
      word.setNoteText(note, 'Draft note');
      word.setRestrictEditing(true);
      word.undo();
      expect(note.text, 'Draft note');
      word.undo();
      expect(note.text, 'Original note');
    },
  );
}
