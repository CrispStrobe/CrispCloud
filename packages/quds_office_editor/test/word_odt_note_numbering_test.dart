import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _namespaces =
    'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
    'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
    'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
    'xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0"';

List<String> _labels(bool uppercase, int start) {
  final labels = switch (start) {
    1 => ['i', 'ii', 'iii', 'iv'],
    9 => ['ix', 'x', 'xi', 'xii'],
    _ => throw ArgumentError.value(start),
  };
  return uppercase
      ? labels.map((label) => label.toUpperCase()).toList()
      : labels;
}

// Independently authored ODF; this does not use the writer under test.
Uint8List _numberedOdt({
  bool endnote = true,
  bool uppercase = false,
  bool mismatchedLabel = false,
  int start = 1,
}) {
  final kind = endnote ? 'endnote' : 'footnote';
  final labels = _labels(uppercase, start);
  final body = StringBuffer();
  for (var index = 0; index < labels.length; index++) {
    final number = index + 1;
    final citation = ZoteroCitation(
      citationId: 'roman-$number',
      plainCitation: '(Source $number)',
      noteIndex: number,
      items: [
        ZoteroCitationItem.fromCsl(
          itemData: <String, Object?>{
            'id': number,
            'type': 'book',
            'title': 'Source $number',
          },
          uris: ['http://zotero.org/users/42/items/ABCD1234'],
          locator: '$number',
          label: 'page',
        ),
      ],
    );
    final mark = encodeXmlAttribute(
      'ZOTERO_ITEM CSL_CITATION ${jsonEncode(citation.toJson())} RND0123456789',
    );
    final label = mismatchedLabel && index == 3 ? 'v' : labels[index];
    body.write(
      '<text:p>Body $number '
      '<text:note text:id="source-$number" text:note-class="$kind">'
      '<text:note-citation>$label</text:note-citation><text:note-body>'
      '<text:p>Note $number '
      '${index == 0 ? 'uncited' : '<text:reference-mark-start text:name="$mark"/>(Source $number)<text:reference-mark-end text:name="$mark"/>'}'
      ' tail</text:p></text:note-body></text:note> after</text:p>',
    );
  }
  final preferences = jsonEncode(<String, Object?>{
    'style': <String, Object?>{
      'styleID': 'http://www.zotero.org/styles/apa',
      'locale': 'de-DE',
    },
    'prefs': <String, Object?>{'fieldType': 'ReferenceMark', 'noteType': 0},
  });
  return (ZipWriter()
        ..addFile(
          'mimetype',
          utf8.encode('application/vnd.oasis.opendocument.text'),
          store: true,
        )
        ..addFile(
          'content.xml',
          utf8.encode(
            '<office:document-content $_namespaces><office:body><office:text>'
            '$body</office:text></office:body></office:document-content>',
          ),
        )
        ..addFile(
          'styles.xml',
          utf8.encode(
            '<office:document-styles $_namespaces><office:styles>'
            '<text:notes-configuration text:note-class="$kind" '
            'style:num-format="${uppercase ? 'I' : 'i'}" text:start-value="$start" '
            '${endnote ? '' : 'text:start-numbering-at="document"'} />'
            '</office:styles></office:document-styles>',
          ),
        )
        ..addFile(
          'meta.xml',
          utf8.encode(
            '<office:document-meta $_namespaces><office:meta>'
            '<meta:user-defined meta:name="ZOTERO_PREF_1">'
            '${encodeXmlText(preferences)}</meta:user-defined>'
            '</office:meta></office:document-meta>',
          ),
        ))
      .close();
}

WordEditorController _controller() {
  final result = WordEditorController(
    document: WmlDocument.empty(text: 'Keep this draft'),
    proofingService: OfficeProofingService(providers: []),
  );
  addTearDown(() {
    if (!result.isDisposed) result.dispose();
  });
  return result;
}

void _expectNotes(
  WmlDocument document, {
  bool endnote = true,
  bool upper = false,
  int start = 1,
}) {
  final notes = endnote ? document.endnotes : document.footnotes;
  final numbering = WordNoteNumbering(document);
  expect(notes.map(numbering.labelFor), _labels(upper, start));
  expect(notes.every(numbering.hasExactLabel), isTrue);
  final fields = WordZotero.fields(document);
  expect(fields.map((field) => field.citation!.citationId), [
    'roman-2',
    'roman-3',
    'roman-4',
  ]);
  expect(fields.map((field) => field.citation!.items.single.locator), [
    '2',
    '3',
    '4',
  ]);
  for (var index = 0; index < fields.length; index++) {
    expect(fields[index].paragraph, same(notes[index + 1].paragraphs.single));
    expect(fields[index].canEdit, isTrue);
  }
}

void main() {
  test('Word layout failure leaves the previously opened document in place', () async {
    final original = WmlDocument.empty(text: 'Original body');
    var failMeasure = false;
    final editor = WordEditorController(
      document: original,
      layoutEngine: WordLayoutEngine(
        font: null,
        measure: (codePoint, size, properties) {
          if (failMeasure) throw StateError('Layout measurement failed');
          return size / 2;
        },
      ),
    );
    addTearDown(editor.dispose);
    final previousLayout = editor.documentLaidOut;
    failMeasure = true;
    await expectLater(
      editor.loadBytesAsync(WordSerializer().writeBytes(
        WmlDocument.empty(text: 'Valid replacement'),
      )),
      throwsStateError,
    );
    expect(editor.document, same(original));
    expect(editor.documentLaidOut, same(previousLayout));
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  for (final start in [1, 9]) {
    for (final endnote in [false, true]) {
      for (final upper in [false, true]) {
        final name =
            '${upper ? 'upper' : 'lower'} Roman ${endnote ? 'endnotes' : 'footnotes'} starting at $start';
        test(
          '$name import and normal DOCX save preserve active ownership',
          () async {
            final bytes = _numberedOdt(
              endnote: endnote,
              uppercase: upper,
              start: start,
            );
            final original = Uint8List.fromList(bytes);
            final word = _controller()..insertText('Unsaved ');
            final previous = word.document;
            await word.loadBytesAsync(
              bytes,
              onProgress: (_) {
                expect(word.document, same(previous));
              },
            );
            expect(word.isDirty, isFalse);
            expect(word.canUndo, isFalse);
            _expectNotes(
              word.document,
              endnote: endnote,
              upper: upper,
              start: start,
            );
            final saved = word.saveBytes();
            expect(OdtDocumentReader.isOdt(saved), isFalse);
            final reopened = _controller();
            await reopened.loadBytesAsync(saved);
            _expectNotes(
              reopened.document,
              endnote: endnote,
              upper: upper,
              start: start,
            );
            expect(bytes, original);
          },
        );
      }
    }
  }

  for (final start in [1, 9]) {
    test(
      'native Refresh after Roman ODT import starting at $start retains numbering and undo',
      () async {
        final word = _controller();
        await word.loadBytesAsync(_numberedOdt(start: start));
        final note = word.document.endnotes[1];
        const selection = TextSelection.collapsed(offset: 2);
        word.setNoteEditingTarget(note, selection);
        final original = word.noteEditText(note);
        const id = 'roman-import-refresh';
        final operation = word.beginZoteroTransaction(
          documentId: id,
          command: ZoteroCitingCommand.refresh,
        );
        final fields =
            (operation.handle('Document.getFields', [id, 'Http'])
                    as List<Object?>)
                .cast<Map<String, Object>>();
        expect(fields.map((field) => field['noteIndex']), [2, 3, 4]);
        operation.handle('Field.select', [id, fields.first['id']]);
        expect(operation.presentedFieldContext?.sourceNote, same(note));
        final citation = Map<String, Object?>.from(
          word.zoteroFields.first.citation!.toJson(),
        );
        final properties = Map<String, Object?>.from(
          citation['properties']! as Map<String, Object?>,
        );
        properties['plainCitation'] = '(Updated source, p. 2)';
        properties['formattedCitation'] = '(Updated source, p. 2)';
        citation['properties'] = properties;
        operation.handle('Field.setCode', [
          id,
          fields.first['id'],
          'ITEM CSL_CITATION ${jsonEncode(citation)}',
        ]);
        operation.handle('Field.setText', [
          id,
          fields.first['id'],
          '(Updated source, p. 2)',
          false,
        ]);
        operation.handle('Document.complete', [id]);
        operation.session.prepareReview();
        expect(word.noteEditText(note), original);
        operation.apply();
        expect(word.noteEditText(note), contains('(Updated source, p. 2)'));
        expect(word.noteEditingTarget?.selection, selection);
        _expectNotes(word.document, start: start);
        expect(word.canUndo, isTrue);
        word.undo();
        expect(word.noteEditText(note), original);
        expect(word.noteEditingTarget?.selection, selection);
        _expectNotes(word.document, start: start);
        expect(word.canUndo, isFalse);
        word.redo();
        _expectNotes(
          WordDeserializer().readBytes(word.saveBytes()),
          start: start,
        );
        final odt = OdtDocumentWriter.writeEditableZoteroBytes(word.document);
        final imported = await OdtDocumentReader.readBytes(odt);
        _expectNotes(imported, start: start);
        expect(
          WordZotero.fields(imported).first.cachedText,
          '(Updated source, p. 2)',
        );
      },
    );
  }

  test(
    'mismatched Roman label refuses without publishing over a dirty draft',
    () async {
      final word = _controller()..insertText('Unsaved ');
      final original = word.document;
      final revision = word.contentRevision;
      final caret = word.caret.logicalIndex;
      await expectLater(
        word.loadBytesAsync(_numberedOdt(mismatchedLabel: true, start: 9)),
        throwsA(isA<StateError>()),
      );
      expect(word.document, same(original));
      expect(word.contentRevision, revision);
      expect(word.caret.logicalIndex, caret);
      expect(word.isDirty, isTrue);
      expect(word.canUndo, isTrue);
      word.undo();
      expect(word.document.paragraphs.single.text, 'Keep this draft');
    },
  );

  test(
    'editing during Roman import invalidates its delayed publication',
    () async {
      final word = _controller();
      final original = word.document;
      var edited = false;
      await expectLater(
        word.loadBytesAsync(
          _numberedOdt(start: 9),
          onProgress: (_) {
            if (edited) return;
            edited = true;
            word.insertText('Newer ');
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(word.document, same(original));
      expect(original.paragraphs.single.text, 'Newer Keep this draft');
      expect(word.zoteroFields, isEmpty);
      expect(word.isDirty, isTrue);
      expect(word.canUndo, isTrue);
    },
  );
}
