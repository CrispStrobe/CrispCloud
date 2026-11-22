import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

Uint8List _odt({bool broken = false}) {
  final name = encodeXmlAttribute(
    'ZOTERO_ITEM CSL_CITATION {"citationID":"loaded",'
    '"citationItems":[{"id":1,"locator":"9"}],'
    '"properties":{"plainCitation":"(Citation)"}} RND0123456789',
  );
  return (ZipWriter()
        ..addFile(
          'mimetype',
          utf8.encode('application/vnd.oasis.opendocument.text'),
          store: true,
        )
        ..addFile(
          'content.xml',
          utf8.encode(
            '<office:document-content '
            'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
            'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">'
            '<office:body><office:text><text:p>Imported '
            '<text:reference-mark-start text:name="$name"/>(Citation)'
            '${broken ? '' : '<text:reference-mark-end text:name="$name"/>'}'
            '</text:p></office:text></office:body></office:document-content>',
          ),
        ))
      .close();
}

WordEditorController _controller() {
  final controller = WordEditorController(
    document: WmlDocument.empty(text: 'Keep this work'),
    proofingService: OfficeProofingService(providers: []),
  );
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'untouched LibreOffice prose publishes script formatting and saves as DOCX',
    () async {
      final fixture = File(
        '../quds_office_engine/test/fixtures/zotero/odt/native-prose.odt',
      );
      final bytes = fixture.readAsBytesSync();
      final originalBytes = Uint8List.fromList(bytes);

      void expectProse(WmlDocument document) {
        final paragraphs = document.paragraphs.toList();
        expect(paragraphs.map((paragraph) => paragraph.text), [
          'Research bold and italic prose.',
          'Second paragraph العربية 😀.',
        ]);
        final firstRuns = paragraphs.first.inlines.whereType<WmlRun>();
        expect(
          firstRuns.singleWhere((run) => run.text == 'bold').properties.bold,
          isTrue,
        );
        expect(
          firstRuns
              .singleWhere((run) => run.text == 'italic')
              .properties
              .italic,
          isTrue,
        );
        final secondRuns = paragraphs[1].inlines.whereType<WmlRun>();
        final latin = secondRuns
            .singleWhere((run) => run.text.contains('Second paragraph'))
            .properties;
        expect(latin.fontSizeHalfPoints, 22);
        expect(latin.asciiFont, 'Arial');
        expect(latin.proofingLanguage, 'en-US');
        final arabic = secondRuns
            .singleWhere((run) => run.text.contains('العربية'))
            .properties;
        expect(arabic.fontSizeHalfPoints, 20);
        expect(arabic.csFont, 'Arial');
        // The native source's language slot is independent of its glyphs.
        expect(arabic.complexScriptLanguage, 'hi-IN');
        expect(WordZotero.fields(document), isEmpty);
      }

      final controller = _controller()..insertText('Draft ');
      final previousDocument = controller.document;
      final stages = <String>[];
      final loading = controller.loadBytesAsync(
        bytes,
        onProgress: (progress) {
          stages.add(progress.stage);
          // Publication happens only after the complete import/layout result.
          expect(controller.document, same(previousDocument));
        },
      );
      expect(controller.document, same(previousDocument));
      await loading;
      expect(stages, contains('archive'));
      expect(controller.document, isNot(same(previousDocument)));
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
      expectProse(controller.document);

      final saved = controller.saveBytes();
      expect(OdtDocumentReader.isOdt(saved), isFalse);
      final reopened = _controller();
      await reopened.loadBytesAsync(saved);
      expectProse(reopened.document);
      expect(reopened.isDirty, isFalse);
      expect(reopened.canUndo, isFalse);
      expect(bytes, originalBytes);
      expect(fixture.readAsBytesSync(), originalBytes);
    },
  );

  test(
    'native ODT load publishes active citations and clears old file history',
    () async {
      final controller = _controller()..insertText('Draft ');
      await controller.loadBytesAsync(_odt());
      expect(controller.document.paragraphs.single.text, 'Imported (Citation)');
      expect(controller.zoteroFields.single.citation!.citationId, 'loaded');
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
      final reopened = WordDeserializer().read(
        OpcPackage.openBytes(controller.saveBytes()),
      );
      expect(
        WordZotero.fields(reopened).single.citation!.items.single.locator,
        '9',
      );
    },
  );

  test(
    'failed ODT import retains document, selection, undo and dirty state',
    () async {
      final controller = _controller()..insertText('Draft ');
      final original = controller.document;
      final revision = controller.contentRevision;
      final caret = controller.caret.logicalIndex;
      await expectLater(
        controller.loadBytesAsync(_odt(broken: true)),
        throwsA(isA<StateError>()),
      );
      expect(identical(controller.document, original), isTrue);
      expect(controller.contentRevision, revision);
      expect(controller.caret.logicalIndex, caret);
      expect(controller.isDirty, isTrue);
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(controller.document.paragraphs.single.text, 'Keep this work');
    },
  );

  test(
    'an edit during native import cannot be replaced by its delayed result',
    () async {
      final controller = _controller();
      final original = controller.document;
      var edited = false;
      await expectLater(
        controller.loadBytesAsync(
          _odt(),
          onProgress: (_) {
            if (edited) return;
            edited = true;
            controller.insertText('Newer ');
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(identical(controller.document, original), isTrue);
      expect(
        controller.document.paragraphs.single.text,
        'Newer Keep this work',
      );
      expect(controller.isDirty, isTrue);
      expect(controller.canUndo, isTrue);
    },
  );

  test(
    'replacing and restoring the document invalidates the pending open',
    () async {
      final controller = _controller();
      final original = controller.document;
      var changed = false;
      await expectLater(
        controller.loadBytesAsync(
          _odt(),
          onProgress: (_) {
            if (changed) return;
            changed = true;
            controller.document = WmlDocument.empty(text: 'Temporary document');
            controller.document = original;
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(identical(controller.document, original), isTrue);
      expect(original.paragraphs.single.text, 'Keep this work');
    },
  );

  test(
    'a newer async open owns publication even when the first finishes later',
    () async {
      final controller = _controller();
      Future<void>? newer;
      final bytes = WordSerializer().writeBytes(
        WmlDocument.empty(text: 'Newest file'),
      );
      final older = controller.loadBytesAsync(
        _odt(),
        onProgress: (_) {
          newer ??= controller.loadBytesAsync(bytes);
        },
      );
      await expectLater(older, throwsA(isA<StateError>()));
      await newer;
      expect(controller.document.paragraphs.single.text, 'Newest file');
      expect(controller.zoteroFields, isEmpty);
    },
  );

  test(
    'a synchronous replacement invalidates an earlier async import',
    () async {
      final controller = _controller();
      final bytes = WordSerializer().writeBytes(
        WmlDocument.empty(text: 'Synchronous file'),
      );
      var replaced = false;
      await expectLater(
        controller.loadBytesAsync(
          _odt(),
          onProgress: (_) {
            if (replaced) return;
            replaced = true;
            controller.loadBytes(bytes);
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(controller.document.paragraphs.single.text, 'Synchronous file');
    },
  );

  test('disposing during import prevents document publication', () async {
    final controller = _controller();
    final original = controller.document;
    await expectLater(
      controller.loadBytesAsync(
        _odt(),
        onProgress: (_) {
          if (!controller.isDisposed) controller.dispose();
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(identical(controller.document, original), isTrue);
  });

  test(
    'synchronous ODT input refuses rather than discarding native fields',
    () {
      final controller = _controller()..insertText('Draft ');
      final original = controller.document;
      expect(() => controller.loadBytes(_odt()), throwsUnsupportedError);
      expect(identical(controller.document, original), isTrue);
      expect(controller.isDirty, isTrue);
      expect(controller.canUndo, isTrue);
    },
  );
}
