import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlDocument _source() => WordDeserializer().readBytes(
  File('test/fixtures/fidelity/note-markers.docx').readAsBytesSync(),
);

WmlNote _note(WmlDocument document, int id, {bool endnote = false}) =>
    WordNotes.byId(document, id, endnote: endnote)!;

List<Map<String, Object?>> _locations(WmlNote note) {
  final result = <Map<String, Object?>>[];
  var paragraphIndex = 0;
  for (final paragraph in note.allParagraphs) {
    var offset = 0;
    for (final inline in paragraph.inlines) {
      if (inline is WmlRun) {
        offset += inline.text.length;
      } else if (inline is WmlNoteBodyMarker) {
        result.add(<String, Object?>{
          'paragraph': paragraphIndex,
          'offset': offset,
          'endnote': inline.endnote,
        });
      }
    }
    paragraphIndex++;
  }
  return result;
}

void _check(WmlDocument document, bool edited) {
  final expected =
      jsonDecode(
            File(
              'test/fixtures/fidelity/note_markers_expected.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  for (final value in expected['notes']! as List<Object?>) {
    final row = value! as Map<String, Object?>;
    final endnote = row['kind'] == 'endnote';
    final note = _note(document, row['id']! as int, endnote: endnote);
    expect(note.preserveBodyMarkers, isTrue);
    expect(
      note.allParagraphs.map((paragraph) => paragraph.text),
      row[edited ? 'edited_paragraphs' : 'paragraphs'],
    );
    final markers =
        (row[edited ? 'edited_markers' : 'markers']! as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(_locations(note), <Map<String, Object?>>[
      for (final marker in markers)
        <String, Object?>{
          'paragraph': marker['paragraph'],
          'offset': marker['offset'],
          'endnote': endnote,
        },
    ]);
  }
}

void _edit(WmlDocument document) {
  document.paragraphs.first.inlines.whereType<WmlRun>().first.text =
      'Edited automatic note markers';
  _note(document, 11).text = 'Replacement conventional';
  _note(document, 12).text = 'Replacement unmarked footnote';
  WmlRunEdit.replaceRange(_note(document, 13).paragraphs.first, 0, 0, 'Lead ');
  _note(document, 14).paragraphs.first.inlines.whereType<WmlRun>().last.text +=
      ' edited';
  _note(document, 15).paragraphs.first.inlines.whereType<WmlRun>().last.text +=
      ' revised';
  _note(
    document,
    16,
  ).allParagraphs.first.inlines.whereType<WmlRun>().last.text += ' edited';
  _note(document, 31, endnote: true).text = 'Replacement endnote';
  _note(document, 32, endnote: true).text = 'Replacement unmarked endnote';
  _note(
    document,
    33,
    endnote: true,
  ).paragraphs.first.inlines.whereType<WmlRun>().last.text += ' edited';
}

void main() {
  setUpAll(() {
    final output = File('build/fidelity-note-markers/markers-source.docx');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(
      File('test/fixtures/fidelity/note-markers.docx').readAsBytesSync(),
    );
  });

  for (final edited in <bool>[false, true]) {
    test(
      'native note markers retain ${edited ? 'edited' : 'imported'} positions over three saves',
      () async {
        var document = _source();
        _check(document, false);
        if (edited) _edit(document);
        _check(document, edited);
        for (var cycle = 1; cycle <= 3; cycle++) {
          final bytes = await OfficeIsolateSave.word(document);
          File(
            'build/fidelity-note-markers/markers-${edited ? 'edited' : 'imported'}-$cycle.docx',
          ).writeAsBytesSync(bytes);
          document = WordDeserializer().readBytes(bytes);
          _check(document, edited);
        }
      },
    );
  }

  test(
    'zero-width note marker copies retain source properties independently',
    () {
      final paragraph = _note(_source(), 13).paragraphs.first;
      final marker = paragraph.inlines.whereType<WmlNoteBodyMarker>().single;
      expect(marker.propertiesXml, contains('123456'));
      final clone = WmlClone.paragraph(paragraph);
      final copied = clone.inlines.whereType<WmlNoteBodyMarker>().single;
      expect(copied, isNot(same(marker)));
      expect(copied.propertiesXml, marker.propertiesXml);
      WmlRunEdit.applyRange(
        clone,
        0,
        clone.text.length,
        (properties) => properties.italic = true,
      );
      expect(
        clone.inlines.whereType<WmlNoteBodyMarker>().single.propertiesXml,
        marker.propertiesXml,
      );
      expect(
        paragraph.inlines.whereType<WmlRun>().first.properties.italic,
        isFalse,
      );
    },
  );

  test(
    'paragraph slicing gives a boundary note marker to following text once',
    () {
      final paragraph = _note(_source(), 13).paragraphs.first;
      final left = WmlClone.slicedParagraph(paragraph, 0, 7);
      final right = WmlClone.slicedParagraph(
        paragraph,
        7,
        paragraph.text.length,
      );
      expect(left.inlines.whereType<WmlNoteBodyMarker>(), isEmpty);
      expect(right.inlines.whereType<WmlNoteBodyMarker>(), hasLength(1));
      expect(right.inlines.first, isA<WmlNoteBodyMarker>());
    },
  );

  test(
    'actual paragraph split moves the automatic marker to its tail once',
    () async {
      var document = _source();
      final note = _note(document, 13);
      final paragraph = note.paragraphs.first;
      final marker = paragraph.inlines.whereType<WmlNoteBodyMarker>().single;
      final tail = WmlRunEdit.splitParagraphInlines(paragraph, 7);
      expect(paragraph.inlines.whereType<WmlNoteBodyMarker>(), isEmpty);
      expect(tail.first, same(marker));
      note.paragraphs.add(
        WmlParagraph(properties: paragraph.properties.copy(), inlines: tail),
      );
      document = WordDeserializer().readBytes(
        await OfficeIsolateSave.word(document),
      );
      expect(_locations(_note(document, 13)), <Map<String, Object?>>[
        <String, Object?>{'paragraph': 1, 'offset': 0, 'endnote': false},
      ]);
    },
  );

  test(
    'whole-body replacement retains the first marker and keeps absence',
    () async {
      var document = _source();
      final marked = _note(document, 15);
      expect(_locations(marked), hasLength(3));
      marked.text = 'Whole replacement';
      _note(document, 12).text = 'Still unmarked';
      expect(_locations(marked), <Map<String, Object?>>[
        <String, Object?>{'paragraph': 0, 'offset': 0, 'endnote': false},
      ]);
      document = WordDeserializer().readBytes(
        await OfficeIsolateSave.word(document),
      );
      expect(_locations(_note(document, 15)), hasLength(1));
      expect(_locations(_note(document, 12)), isEmpty);
      expect(_note(document, 12).text, 'Still unmarked');
    },
  );

  test('empty imported note body remains unmarked', () async {
    var document = _source();
    _note(document, 12).blocks.clear();
    document = WordDeserializer().readBytes(
      await OfficeIsolateSave.word(document),
    );
    expect(_locations(_note(document, 12)), isEmpty);
    expect(_note(document, 12).paragraphs, hasLength(1));
  });

  test(
    'new notes retain one generated mark and their conventional separator',
    () async {
      var document = WmlDocument.empty(text: 'Body');
      final note = WordNotes.insert(
        document,
        document.paragraphs.first,
        endnote: false,
        text: 'New body',
      );
      expect(note.preserveBodyMarkers, isFalse);
      note.text = 'Replacement new body';
      document = WordDeserializer().readBytes(
        await OfficeIsolateSave.word(document),
      );
      expect(_locations(document.footnotes.single), hasLength(1));
      expect(
        document.footnotes.single.paragraphs.first.text,
        ' Replacement new body',
      );
    },
  );
}
