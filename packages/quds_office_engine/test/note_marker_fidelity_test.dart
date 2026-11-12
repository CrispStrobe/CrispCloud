import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/fidelity/office_steps.dart' as cli;
import '../tool/fidelity/step_input.dart';

const _fixtures = 'test/fixtures/fidelity';

OpcPackage _source() {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        File('$_fixtures/note_markers_document.xml').readAsStringSync(),
      );
  for (final endnote in [false, true]) {
    final kind = endnote ? 'endnote' : 'footnote';
    final uri = '/word/${kind}s.xml';
    final bytes = File(
      '$_fixtures/note_markers_${kind}s.xml',
    ).readAsBytesSync();
    final part = package.getPart(uri);
    if (part == null) {
      package.createPart(
        uri,
        endnote
            ? OfficeContentTypes.wordEndnotes
            : OfficeContentTypes.wordFootnotes,
        bytes,
      );
    } else {
      part.writeBytes(bytes);
    }
    final rels = package.relationshipsFor('/word/document.xml');
    final type = endnote
        ? RelationshipTypes.endnotes
        : RelationshipTypes.footnotes;
    if (rels.firstByType(type) == null) {
      rels.add(type: type, target: '${kind}s.xml');
    }
  }
  return package;
}

WmlDocument _document() => WordDeserializer().read(_source());

List<WmlNote> _notes(WmlDocument doc, bool endnote) =>
    endnote ? doc.endnotes : doc.footnotes;

Map<String, Object> _positions(List<WmlNote> notes) => {
  for (final note in notes)
    '${note.id}': {
      for (final entry in note.allParagraphs.indexed)
        if (_offsets(entry.$2).isNotEmpty) '${entry.$1}': _offsets(entry.$2),
    },
};

List<int> _offsets(WmlParagraph paragraph) {
  final result = <int>[];
  var offset = 0;
  for (final inline in paragraph.inlines) {
    if (inline is WmlNoteMarker) result.add(offset);
    if (inline is WmlRun) offset += inline.text.length;
  }
  return result;
}

Iterable<WmlNoteMarker> _markers(WmlNote note) =>
    note.allParagraphs.expand((p) => p.inlines.whereType<WmlNoteMarker>());

void _cloneStories(WmlDocument doc) {
  for (final note in [...doc.footnotes, ...doc.endnotes]) {
    final originals = _markers(note).toList();
    final blocks = note.blocks.map(WmlClone.block).toList();
    note.blocks
      ..clear()
      ..addAll(blocks);
    final copies = _markers(note).toList();
    expect(copies, hasLength(originals.length));
    for (var i = 0; i < copies.length; i++) {
      expect(copies[i], isNot(same(originals[i])));
      expect(copies[i].properties, isNot(same(originals[i].properties)));
      expect(
        copies[i].properties.sourcePropertiesXml,
        originals[i].properties.sourcePropertiesXml,
      );
      expect(
        copies[i].properties.importedValues,
        originals[i].properties.importedValues,
      );
    }
  }
}

void _editStories(WmlDocument doc) {
  for (final endnote in [false, true]) {
    final notes = _notes(doc, endnote);
    for (final id in [1, 2, 5, 6]) {
      final note = notes.firstWhere((n) => n.id == id);
      final paragraph = note.allParagraphs.first;
      cli.applyStep(doc, {
        'op': 'replaceText',
        'story': endnote ? 'endnote' : 'footnote',
        'note': id,
        'paragraph': 0,
        'start': paragraph.text.length,
        'end': paragraph.text.length,
        'text': ' edited',
      });
    }
    final cell = notes.firstWhere((n) => n.id == 4).allParagraphs.elementAt(1);
    cli.applyStep(doc, {
      'op': 'replaceText',
      'story': endnote ? 'endnote' : 'footnote',
      'note': 4,
      'paragraph': 1,
      'start': cell.text.length,
      'end': cell.text.length,
      'text': ' edited',
    });
  }
}

WmlDocument _singleNote(bool endnote, int id) {
  final doc = _document();
  final note = _notes(doc, endnote).firstWhere((n) => n.id == id);
  doc.footnotes.clear();
  doc.endnotes.clear();
  _notes(doc, endnote).add(note);
  doc.sections.first.blocks
    ..clear()
    ..add(
      WmlParagraph(
        inlines: [
          WmlRun(text: 'Body'),
          WmlRun(text: '$id', noteRefId: id, noteRefEndnote: endnote),
        ],
      ),
    );
  return doc;
}

List<LaidOutLine> _noteLines(WmlDocument doc) => WordLayoutEngine(font: null)
    .layout(doc)
    .pages
    .expand((p) => p.notes)
    .where((line) => line.overlayText != 'Endnotes')
    .toList();

void main() {
  final expected =
      jsonDecode(
            File('$_fixtures/note_markers_expected.json').readAsStringSync(),
          )
          as Map<String, Object?>;

  test(
    'authored note-marker stories retain position, kind and properties for three export cycles',
    () async {
      const root = 'build/fidelity-note-markers';
      final source = _source().save();
      writeOutput('$root/source.docx', source);
      for (final phase in ['imported', 'cloned', 'edited']) {
        var doc = WordDeserializer().readBytes(source);
        if (phase == 'cloned') _cloneStories(doc);
        if (phase == 'edited') _editStories(doc);
        for (var cycle = 1; cycle <= 3; cycle++) {
          final bytes = await OfficeIsolateSave.word(doc);
          writeOutput('$root/$phase-$cycle.docx', bytes);
          doc = WordDeserializer().readBytes(bytes);
          for (final endnote in [false, true]) {
            final notes = _notes(doc, endnote);
            expect(notes.map((n) => n.id), [1, 2, 3, 4, 5, 6]);
            expect(_positions(notes), expected['marker_offsets']);
            expect(notes.every((note) => !note.addReference), isTrue);
            expect(
              notes.firstWhere((n) => n.id == 4).blocks.first,
              isA<WmlTable>(),
            );
            expect(
              notes.firstWhere((n) => n.id == 5).hasReferenceMarkers,
              isFalse,
            );
            expect(notes.firstWhere((n) => n.id == 3).text, isEmpty);
            for (final note in notes) {
              expect(
                _markers(note).every((marker) => marker.endnote == endnote),
                isTrue,
              );
            }
            final middle = _markers(
              notes.firstWhere((n) => n.id == 2),
            ).single.properties;
            expect(middle.color, '335577');
            expect(middle.italic, isTrue);
            expect(middle.fontSizeHalfPoints, 20);
            expect(middle.sourcePropertiesXml, contains('fr-FR'));
          }
        }
      }
    },
  );

  test(
    'zero-width marker clones do not share mutable run property snapshots',
    () {
      final doc = _document();
      final source = doc.footnotes
          .firstWhere((n) => n.id == 2)
          .allParagraphs
          .single;
      final copy = WmlClone.paragraph(source);
      final old = source.inlines.whereType<WmlNoteMarker>().single;
      final next = copy.inlines.whereType<WmlNoteMarker>().single;
      next.properties.color = 'AABBCC';
      next.properties.importedValues!['color'] = 'different';
      expect(old.properties.color, '335577');
      expect(old.properties.importedValues!['color'], '335577');
      expect(copy.text, source.text);
      expect(_offsets(copy), [7]);
    },
  );

  test(
    'paragraph-scoped note script edit preserves nested content and exact unnumbered whitespace',
    () {
      final doc = _document();
      final unnumbered = doc.footnotes.firstWhere((n) => n.id == 5);
      expect(WordNotes.editableText(unnumbered), '  Intentionally unnumbered');
      _editStories(doc);
      expect(
        unnumbered.paragraphs.single.text,
        '  Intentionally unnumbered edited',
      );
      expect(unnumbered.hasReferenceMarkers, isFalse);
      final nested = doc.footnotes.firstWhere((n) => n.id == 4);
      expect(nested.blocks.single, isA<WmlTable>());
      expect(nested.allParagraphs.map((p) => p.text), [
        'Cell before',
        'Cell  tail edited',
      ]);
      expect(_positions(doc.footnotes), expected['marker_offsets']);
    },
  );

  test(
    'legacy whole-story replacement retains its automatic marker or source absence',
    () async {
      var doc = _document();
      final marked = doc.footnotes.firstWhere((note) => note.id == 1);
      marked.text = 'Replacement';
      final absent = doc.footnotes.firstWhere((note) => note.id == 5);
      absent.text = 'Replacement without marker';
      expect(marked.blocks, hasLength(1));
      expect(marked.text, 'Replacement');
      expect(_markers(marked).single.properties.color, '123456');
      expect(absent.hasReferenceMarkers, isFalse);
      doc = WordDeserializer().readBytes(await OfficeIsolateSave.word(doc));
      expect(
        _markers(doc.footnotes.firstWhere((note) => note.id == 1)),
        hasLength(1),
      );
      expect(
        doc.footnotes.firstWhere((note) => note.id == 5).hasReferenceMarkers,
        isFalse,
      );
    },
  );

  test(
    'minimal note edits retain all source spacing after a leading marker',
    () async {
      for (final endnote in [false, true]) {
        for (final whitespace in ['', ' ', '  ', '\t']) {
          var doc = _singleNote(endnote, 3);
          final note = _notes(doc, endnote).single;
          note.paragraphs.single.inlines.add(
            WmlRun(text: '${whitespace}Visible'),
          );
          WordNotes.editText(note, '${WordNotes.editableText(note)} edited');
          expect(note.paragraphs.single.text, '${whitespace}Visible edited');
          doc = WordDeserializer().readBytes(await OfficeIsolateSave.word(doc));
          expect(
            _notes(doc, endnote).single.paragraphs.single.text,
            '${whitespace}Visible edited',
          );
          expect(_offsets(_notes(doc, endnote).single.paragraphs.single), [0]);
        }
      }
    },
  );

  const rendered = <int, List<String>>{
    1: ['Opening text', '1 Later marker'],
    2: ['Before 2 after'],
    3: ['3'],
    4: ['Cell before', 'Cell 4 tail'],
    5: ['  Intentionally unnumbered'],
    6: ['6A6B6'],
  };
  for (final endnote in [false, true]) {
    for (final id in rendered.keys) {
      test(
        'layout preserves note marker location/absence: endnote=$endnote id=$id',
        () {
          final lines = _noteLines(_singleNote(endnote, id));
          expect(lines.map((line) => line.sourceText), rendered[id]);
          if (id == 1) {
            final number = lines.last.glyphs.first;
            expect(number.color, '123456');
            expect(number.fontSize, 10);
            expect(number.vertAlign, WmlVertAlign.baseline);
          }
        },
      );
    }
    test(
      'new-note display and reference properties remain stable after save: endnote=$endnote',
      () async {
        var doc = WmlDocument.empty(text: 'Body');
        WordNotes.insert(
          doc,
          doc.paragraphs.single,
          endnote: endnote,
          text: 'New note',
        );
        for (var cycle = 0; cycle < 4; cycle++) {
          final lines = _noteLines(doc);
          expect(lines.single.sourceText, '1 New note');
          expect(lines.single.glyphs.first.vertAlign, WmlVertAlign.superscript);
          final bytes = await OfficeIsolateSave.word(doc);
          final kind = endnote ? 'endnote' : 'footnote';
          final root = XmlDocument.parse(
            OpcPackage.openBytes(
              bytes,
            ).getPart('/word/${kind}s.xml')!.readText(),
          ).root!;
          final note = root
              .childrenNamed(kind)
              .firstWhere((n) => n.getAttribute('id') == '1');
          final run = note.firstChild('p')!.childrenNamed('r').first;
          expect(run.firstChild('${kind}Ref'), isNotNull);
          expect(
            run.firstChild('rPr')!.firstChild('rStyle')!.getAttribute('val'),
            endnote ? 'EndnoteReference' : 'FootnoteReference',
          );
          expect(
            run.firstChild('rPr')!.firstChild('vertAlign')!.getAttribute('val'),
            'superscript',
          );
          doc = WordDeserializer().readBytes(bytes);
        }
      },
    );
  }
}
