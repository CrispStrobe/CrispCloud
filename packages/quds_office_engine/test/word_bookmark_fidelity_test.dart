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
      .writeText(File('$_fixtures/bookmark_ranges.xml').readAsStringSync());
  package
      .relationshipsFor('/word/document.xml')
      .add(
        id: 'rIdBookmarkLink',
        type: RelationshipTypes.hyperlink,
        target: 'https://example.org/bookmark-target',
        targetMode: RelationshipTargetMode.external,
      );
  return package;
}

WmlDocument _document() => WordDeserializer().read(_source());

Map<String, Object?> _ranges(WmlDocument doc) {
  final paragraphs = doc.paragraphs.toList();
  return {
    for (final range in WordBookmarks.ranges(doc))
      range.name: {
        'id': range.start.id,
        'start': [paragraphs.indexOf(range.startParagraph), range.startOffset],
        'end': [paragraphs.indexOf(range.endParagraph), range.endOffset],
        'text': range.text,
      },
  };
}

Map<String, Object?> _specification() =>
    jsonDecode(
          File('$_fixtures/bookmark_ranges_expected.json').readAsStringSync(),
        )
        as Map<String, Object?>;

void _edit(WmlDocument doc) {
  cli.applyStep(doc, {
    'op': 'replaceText',
    'paragraph': 0,
    'start': 12,
    'end': 12,
    'text': ' edited',
  });
  cli.applyStep(doc, {
    'op': 'replaceText',
    'paragraph': 1,
    'start': 7,
    'end': 12,
    'text': 'ALPHA!',
  });
  cli.applyStep(doc, {'op': 'paragraphSplit', 'paragraph': 2, 'offset': 13});
  cli.applyStep(doc, {'op': 'paragraphInsert', 'text': 'New generated target'});
  cli.applyStep(doc, {
    'op': 'bookmarkSet',
    'paragraph': 14,
    'name': 'Generated',
  });
  for (final name in _specification()['reference_names']! as List<Object?>) {
    final index = doc.paragraphs.length;
    cli.applyStep(doc, {'op': 'paragraphInsert', 'text': 'stale cache'});
    cli.applyStep(doc, {
      'op': 'reference',
      'paragraph': index,
      'bookmark': name,
    });
  }
  WordFields.update(doc);
}

Map<String, String> _parts(OpcPackage package) => {
  for (final part in package.parts) part.uri: base64Encode(part.readBytes()),
};

WmlParagraph _pair(String id, String name, {String text = 'marked'}) =>
    WmlParagraph(
      inlines: [
        WmlBookmarkBoundary(id: id, isStart: true, name: name),
        WmlRun(text: text),
        WmlBookmarkBoundary(id: id, isStart: false),
      ],
    );

void main() {
  test(
    'authored textbox endpoints and surrounding body REF retain separate story ownership',
    () async {
      const output = 'build/fidelity-bookmarks';
      final package = OpcPackage.create(OpcPackageKind.word);
      package
          .getPart('/word/document.xml')!
          .writeText(
            File('$_fixtures/bookmark_frame_stories.xml').readAsStringSync(),
          );
      final source = package.save();
      writeOutput('$output/frame-source.docx', source);
      var doc = WordDeserializer().readBytes(source);
      expect(doc.sections.first.blocks.whereType<WmlFrame>(), hasLength(1));
      const expected = {
        'BodyAroundFrame': 'Body before\n\nBody after',
        'TextBox': 'Textbox content',
      };
      for (final name in expected.keys) {
        final index = doc.paragraphs.length;
        cli.applyStep(doc, {'op': 'paragraphInsert', 'text': 'stale'});
        cli.applyStep(doc, {
          'op': 'reference',
          'paragraph': index,
          'bookmark': name,
        });
      }
      for (var cycle = 1; cycle <= 3; cycle++) {
        WordFields.update(doc);
        for (final entry in expected.entries) {
          final range = WordBookmarks.byName(doc, entry.key)!;
          expect(range.start.id, entry.key == 'BodyAroundFrame' ? '30' : '31');
          expect(range.text, entry.value);
        }
        expect(doc.paragraphs.skip(3).map((p) => p.text), expected.values);
        final bytes = await OfficeIsolateSave.word(doc);
        writeOutput('$output/frame-$cycle.docx', bytes);
        doc = WordDeserializer().readBytes(bytes);
      }
    },
  );

  test(
    'authored endpoints survive clone, real script edits and three async exports',
    () async {
      const output = 'build/fidelity-bookmarks';
      final source = _source().save();
      writeOutput('$output/source.docx', source);
      final specification = _specification();
      for (final phase in ['imported', 'cloned', 'edited']) {
        var doc = WordDeserializer().readBytes(source);
        if (phase == 'cloned') {
          for (final section in doc.sections) {
            final copies = section.blocks.map(WmlClone.block).toList();
            section.blocks
              ..clear()
              ..addAll(copies);
          }
        }
        if (phase == 'edited') _edit(doc);
        for (var cycle = 1; cycle <= 3; cycle++) {
          final bytes = await OfficeIsolateSave.word(doc);
          writeOutput('$output/$phase-$cycle.docx', bytes);
          doc = WordDeserializer().readBytes(bytes);
          expect(
            _ranges(doc),
            specification[phase == 'edited'
                ? 'edited_ranges'
                : 'source_ranges'],
          );
          final linked = WordBookmarks.byName(doc, 'Linked')!.startParagraph;
          expect(
            linked.inlines
                .whereType<WmlRun>()
                .singleWhere((run) => run.text == 'linked')
                .hyperlink
                ?.url,
            'https://example.org/bookmark-target',
          );
          if (phase == 'edited') {
            final fields = doc.paragraphs.skip(15).toList();
            final names = specification['reference_names']! as List<Object?>;
            expect(fields, hasLength(names.length));
            for (var i = 0; i < names.length; i++) {
              final name = names[i]! as String;
              expect(fields[i].text, WordBookmarks.textByName(doc, name));
              expect(
                fields[i].properties.fieldInstruction,
                contains('REF $name'),
              );
            }
          }
        }
      }
    },
  );

  test(
    'native aliases survive style cascade without expanding or duplicating ranges',
    () {
      var doc = _document();
      final p = doc.paragraphs.elementAt(1);
      expect(p.properties.bookmarkName, 'Alpha');
      expect(p.properties.sourceBookmarkName, 'Alpha');
      WordStyles.apply(p, 'Heading1', document: doc);
      WordLink.ensureHeadingBookmarks(doc);
      for (var cycle = 0; cycle < 3; cycle++) {
        doc = WordDeserializer().readBytes(WordSerializer().writeBytes(doc));
        final range = WordBookmarks.byName(doc, 'Alpha')!;
        expect(range.startOffset, 7);
        expect(range.endOffset, 12);
        expect(range.startParagraph.properties.sourceBookmarkName, 'Alpha');
        expect(WordBookmarks.generatedName(range.startParagraph), isNull);
        expect(WordBookmarks.ranges(doc), hasLength(11));
      }
    },
  );

  test(
    'native text REF uses exact selected whitespace, UTF-16 range and empty results',
    () {
      final doc = _document();
      final expected =
          _specification()['source_ranges']! as Map<String, Object?>;
      for (final entry in expected.entries) {
        expect(
          WordFields.evaluate(
            WmlFieldKind.ref,
            document: doc,
            instruction: ' REF ${entry.key} ',
          ),
          (entry.value! as Map<String, Object?>)['text'],
        );
      }
      expect(WordLink.paragraphIndexForAnchor(doc, 'Beta'), 1);
      expect(WordLink.paragraphIndexForAnchor(doc, 'TableInside'), 8);
    },
  );

  test(
    'clones retain exact endpoint metadata without sharing token identities',
    () {
      final source = _document().paragraphs.elementAt(1);
      final clone = WmlClone.paragraph(source);
      final original = source.inlines.whereType<WmlBookmarkBoundary>().toList();
      final copies = clone.inlines.whereType<WmlBookmarkBoundary>().toList();
      expect(copies, hasLength(4));
      for (var i = 0; i < copies.length; i++) {
        expect(copies[i], isNot(same(original[i])));
        expect(copies[i].sourceXml, original[i].sourceXml);
      }
      expect(copies.first.id, '000');
      expect(copies.first.sourceXml, contains('colFirst="0"'));
      expect(copies.first.sourceXml, contains('displacedByCustomXml="next"'));
    },
  );

  test(
    'generated names and decimal IDs reserve all existing native ownership',
    () {
      var doc = _document();
      final generated = WmlParagraph(
        properties: WmlParagraphProps(bookmarkName: 'NewRange'),
        inlines: [WmlRun(text: 'new')],
      );
      final heading = WmlParagraph(inlines: [WmlRun(text: 'Heading')]);
      WordToc.applyHeading(heading, 1);
      doc.sections.first.blocks.addAll([generated, heading]);
      WordLink.ensureHeadingBookmarks(doc);
      final ids = WordBookmarks.generatedIds(doc);
      expect(ids['NewRange'], '2');
      expect(ids[heading.properties.bookmarkName], '3');
      doc = WordDeserializer().readBytes(WordSerializer().writeBytes(doc));
      expect(WordBookmarks.byName(doc, 'Alpha')!.start.id, '000');
      expect(WordBookmarks.byName(doc, 'NewRange')!.start.id, '2');
    },
  );

  test('manual compatibility aliases defer to exact native endpoints', () {
    final p = _pair('7', 'Manual', text: 'value');
    p.properties.bookmarkName = 'Manual';
    final doc = WmlDocument(
      sections: [
        WmlSection(blocks: [p]),
      ],
    );
    expect(WordBookmarks.generatedIds(doc), isEmpty);
    final reopened = WordDeserializer().readBytes(
      WordSerializer().writeBytes(doc),
    );
    expect(WordBookmarks.ranges(reopened), hasLength(1));
    expect(WordBookmarks.byName(reopened, 'Manual')!.text, 'value');
  });

  test(
    'duplicate native copy is rejected before changing any package part',
    () {
      final doc = _document();
      doc.sections.first.blocks.add(
        WmlClone.paragraph(doc.paragraphs.elementAt(1)),
      );
      final before = _parts(doc.package!);
      expect(
        () => WordSerializer().write(doc),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'explanation',
            contains('requires remapping'),
          ),
        ),
      );
      expect(_parts(doc.package!), before);
    },
  );

  for (final removeStart in [false, true]) {
    test(
      'unpaired ${removeStart ? 'end' : 'start'} is rejected before package mutation',
      () {
        final doc = _document();
        final p = doc.paragraphs.elementAt(1);
        p.inlines.removeWhere(
          (inline) =>
              inline is WmlBookmarkBoundary &&
              inline.id == '000' &&
              inline.isStart == removeStart,
        );
        final before = _parts(doc.package!);
        expect(() => WordSerializer().write(doc), throwsStateError);
        expect(_parts(doc.package!), before);
      },
    );
  }

  test('source metadata mismatch fails before package mutation', () {
    final doc = _document();
    final p = doc.paragraphs.elementAt(1);
    final index = p.inlines.indexWhere(
      (inline) => inline is WmlBookmarkBoundary,
    );
    final old = p.inlines[index] as WmlBookmarkBoundary;
    p.inlines[index] = WmlBookmarkBoundary(
      id: old.id,
      isStart: true,
      name: 'WrongName',
      sourceXml: old.sourceXml,
    );
    final before = _parts(doc.package!);
    expect(() => WordSerializer().write(doc), throwsStateError);
    expect(_parts(doc.package!), before);
  });

  test(
    'generated duplicate name cannot shadow a native range in another paragraph',
    () {
      final doc = _document();
      doc.paragraphs.first.properties.bookmarkName = 'Alpha';
      final before = _parts(doc.package!);
      expect(() => WordSerializer().write(doc), throwsStateError);
      expect(_parts(doc.package!), before);
    },
  );

  test('deleting one endpoint paragraph rejects before changing the model', () {
    final doc = _document();
    final blocks = List<WmlBlock>.from(doc.sections.first.blocks);
    final ranges = _ranges(doc);
    expect(
      () => cli.applyStep(doc, {'op': 'paragraphDelete', 'paragraph': 2}),
      throwsArgumentError,
    );
    expect(doc.sections.first.blocks, orderedEquals(blocks));
    expect(_ranges(doc), ranges);
  });

  test(
    'automatic field refresh retains a native cache containing bookmark endpoints',
    () {
      final package = OpcPackage.create(OpcPackageKind.word);
      package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
  <w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText> REF Target </w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r>
    <w:bookmarkStart w:id="5" w:name="CachedResult"/><w:r><w:t>Old cache</w:t></w:r><w:bookmarkEnd w:id="5"/><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>
  <w:p><w:bookmarkStart w:id="6" w:name="Target"/><w:r><w:t>New target</w:t></w:r><w:bookmarkEnd w:id="6"/></w:p><w:sectPr/>
</w:body></w:document>''');
      var doc = WordDeserializer().read(package);
      for (var cycle = 0; cycle < 3; cycle++) {
        WordFields.update(doc);
        expect(WordBookmarks.byName(doc, 'CachedResult')!.text, 'Old cache');
        expect(WordBookmarks.byName(doc, 'Target')!.text, 'New target');
        expect(
          doc.paragraphs.first.properties.fieldInstruction,
          contains('REF Target'),
        );
        doc = WordDeserializer().readBytes(WordSerializer().writeBytes(doc));
      }
    },
  );

  test('whole-paragraph field replacement cannot erase native endpoints', () {
    final doc = _document();
    final p = doc.paragraphs.elementAt(1);
    final inlines = List<WmlInline>.from(p.inlines);
    expect(
      () => WordFields.stamp(
        p,
        WmlFieldKind.ref,
        argument: 'Beta',
        result: 'Beta',
      ),
      throwsArgumentError,
    );
    expect(p.inlines, orderedEquals(inlines));
    expect(p.properties.fieldInstruction, isNull);
    expect(WordBookmarks.byName(doc, 'Alpha')!.text, 'Alpha');
  });

  test(
    'native range replacement and deletion retain its endpoints exactly once',
    () {
      final doc = _document();
      final p = doc.paragraphs.elementAt(1);
      WmlRunEdit.replaceRange(p, 7, 12, 'changed');
      expect(WordBookmarks.byName(doc, 'Alpha')!.text, 'changed');
      WmlRunEdit.replaceRange(p, 7, 14, '');
      final empty = WordBookmarks.byName(doc, 'Alpha')!;
      expect(empty.text, '');
      expect(empty.startOffset, 7);
      expect(empty.endOffset, 7);
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(doc),
      );
      expect(WordBookmarks.byName(reopened, 'Alpha')!.text, '');
      expect(WordBookmarks.ranges(reopened), hasLength(11));
    },
  );

  test(
    'header footer comment and note stories own independent endpoint pairs',
    () {
      var doc = WmlDocument(
        sections: [
          WmlSection(
            blocks: [_pair('7', 'Body')],
            header: [_pair('7', 'Header')],
            footer: [_pair('7', 'Footer')],
          ),
        ],
        comments: [
          WmlComment(id: 0, paragraphs: [_pair('7', 'Comment')]),
        ],
        footnotes: [
          WmlNote(
            id: 1,
            endnote: false,
            addReference: false,
            blocks: [_pair('7', 'Footnote')],
          ),
        ],
        endnotes: [
          WmlNote(
            id: 1,
            endnote: true,
            addReference: false,
            blocks: [_pair('7', 'Endnote')],
          ),
        ],
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        doc = WordDeserializer().readBytes(WordSerializer().writeBytes(doc));
        expect(WordBookmarks.ranges(doc).map((range) => range.name).toSet(), {
          'Body',
          'Header',
          'Footer',
          'Comment',
          'Footnote',
          'Endnote',
        });
        for (final range in WordBookmarks.ranges(doc)) {
          expect(range.start.id, '7');
          expect(range.text, 'marked');
        }
      }
    },
  );
}
