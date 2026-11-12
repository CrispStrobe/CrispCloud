import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

OpcPackage _source(String body) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>$body'
        '<w:sectPr/></w:body></w:document>',
      );
  return package;
}

Iterable<WmlRun> _fields(WmlParagraph paragraph) => paragraph.inlines
    .whereType<WmlRun>()
    .where((run) => run.fieldInstruction != null);

WmlDocument _citations() {
  final document = WmlDocument.empty(text: 'Before');
  final paragraph = document.paragraphs.single;
  paragraph.inlines.whereType<WmlRun>().single.properties.bold = true;
  WordCitations.insert(
    document,
    paragraph,
    WmlCitation(
      tag: 'PAGE',
      author: 'Ada',
      title: 'First source',
      year: '2026',
    ),
  );
  paragraph.inlines.add(
    WmlRun(text: ' between', properties: WmlRunProps(italic: true)),
  );
  WordCitations.insert(
    document,
    paragraph,
    WmlCitation(
      tag: 'TIME',
      author: 'Grace',
      title: 'Second source',
      year: '2025',
    ),
  );
  paragraph.inlines.add(
    WmlRun(
      text: ' after',
      properties: WmlRunProps(underline: WmlUnderline.single),
    ),
  );
  return document;
}

void main() {
  group('field kind uses only its command', () {
    const cases = <String, WmlFieldKind>{
      ' CITATION PAGE ': WmlFieldKind.citation,
      ' CITATION DATE ': WmlFieldKind.citation,
      ' REF TIME ': WmlFieldKind.ref,
      ' SEQ TITLE ': WmlFieldKind.seq,
      ' HYPERLINK "https://example.com/date" ': WmlFieldKind.hyperlink,
      ' MERGEFIELD AUTHOR ': WmlFieldKind.mergeField,
      ' page ': WmlFieldKind.page,
      ' NUMPAGES ': WmlFieldKind.numPages,
      ' IF PAGE = 1 "first" "other" ': WmlFieldKind.unknown,
      ' CUSTOM DATE ': WmlFieldKind.unknown,
    };
    for (final entry in cases.entries) {
      test(entry.key, () => expect(WordFields.kindOf(entry.key), entry.value));
    }
  });

  for (final isolate in <bool>[false, true]) {
    final mode = isolate ? 'isolate' : 'direct';
    test(
      'two inline citations retain surrounding text over three $mode saves',
      () async {
        WmlDocument document = _citations();
        for (var cycle = 1; cycle <= 3; cycle++) {
          WordFields.update(document);
          final paragraph = document.paragraphs.single;
          expect(
            paragraph.text,
            'Before (Ada 2026) between (Grace 2025) after',
          );
          expect(paragraph.properties.fieldInstruction, isNull);
          expect(
            _fields(paragraph).map((run) => run.fieldInstruction),
            <String>[' CITATION PAGE ', ' CITATION TIME '],
          );
          final Uint8List bytes = isolate
              ? await OfficeIsolateSave.word(document)
              : WordSerializer().writeBytes(document);
          final saved = OpcPackage.openBytes(bytes);
          final body = XmlDocument.parse(
            saved.getPart('/word/document.xml')!.readText(),
          ).root!.firstChild('body')!.firstChild('p')!;
          final fields = body.childrenNamed('fldSimple');
          expect(fields, hasLength(2));
          expect(fields.map((field) => field.getAttribute('instr')), <String>[
            ' CITATION PAGE ',
            ' CITATION TIME ',
          ]);
          expect(
            fields.map((field) => field.firstChild('r')!.firstChild('t')!.text),
            <String>['(Ada 2026)', '(Grace 2025)'],
          );
          expect(
            body.childrenNamed('r').first.firstChild('rPr')!.firstChild('b'),
            isNotNull,
          );
          expect(
            body
                .childrenNamed('r')
                .last
                .firstChild('rPr')!
                .firstChild('u')!
                .getAttribute('val'),
            'single',
          );
          final output = File('build/fidelity-inline-fields/$mode-$cycle.docx');
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(bytes);
          document = WordDeserializer().readBytes(bytes);
        }
        WordFields.update(document);
        expect(
          document.paragraphs.single.text,
          'Before (Ada 2026) between (Grace 2025) after',
        );
      },
    );
  }

  test('citation edits update only the live result at the selected caret', () {
    final document = WmlDocument.empty(text: 'LeftRight');
    final paragraph = document.paragraphs.single;
    WordCitations.insert(
      document,
      paragraph,
      WmlCitation(
        tag: 'source',
        author: 'Old author',
        title: 'Original',
        year: '2026',
      ),
      index: 4,
    );
    expect(paragraph.text, 'Left (Old author 2026) Right');
    document.citations.single.author = 'New author';
    WordFields.update(document);
    expect(paragraph.text, 'Left (New author 2026) Right');
    expect(_fields(paragraph), hasLength(1));
  });

  test('native locked simple fields retain flags and cached results', () {
    var document = WordDeserializer().read(
      _source(
        '<w:p><w:r><w:t xml:space="preserve">Prefix </w:t></w:r>'
        '<w:fldSimple w:instr=" CITATION source " w:fldLock="true" w:dirty="false">'
        '<w:r><w:rPr><w:i/></w:rPr><w:t>Cached native result</w:t></w:r>'
        '</w:fldSimple><w:r><w:t xml:space="preserve"> suffix</w:t></w:r></w:p>',
      ),
    );
    document.citations.add(
      WmlCitation(
        tag: 'source',
        author: 'Updated',
        title: 'Updated source',
        year: '2026',
      ),
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      WordFields.update(document);
      expect(
        document.paragraphs.single.text,
        'Prefix Cached native result suffix',
      );
      final field = _fields(document.paragraphs.single).single;
      expect(field.fieldLocked, isTrue);
      expect(field.fieldDirty, isFalse);
      expect(field.properties.italic, isTrue);
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
    }
    _fields(document.paragraphs.single).single.fieldLocked = false;
    WordFields.update(document);
    expect(document.paragraphs.single.text, 'Prefix (Updated 2026) suffix');
  });

  test('unknown native simple fields retain their instruction and cache', () {
    var document = WordDeserializer().read(
      _source(
        '<w:p><w:r><w:t>Before</w:t></w:r>'
        '<w:fldSimple w:instr=" CUSTOM DATE "><w:r><w:t>Opaque result</w:t></w:r>'
        '</w:fldSimple><w:r><w:t>After</w:t></w:r></w:p>',
      ),
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      WordFields.update(document);
      expect(document.paragraphs.single.text, 'BeforeOpaque resultAfter');
      expect(
        _fields(document.paragraphs.single).single.fieldInstruction,
        ' CUSTOM DATE ',
      );
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
    }
  });

  test(
    'cloning, extraction, insertion and formatting preserve inline fields',
    () {
      final paragraph = WmlParagraph(
        inlines: <WmlInline>[
          WmlRun(text: 'Before'),
          WmlRun(
            text: '(Author 2026)',
            fieldInstruction: ' CITATION source ',
            fieldLocked: true,
            fieldDirty: false,
          ),
          WmlRun(text: 'After'),
        ],
      );
      final copied = WmlClone.paragraph(paragraph);
      final sliced = WmlClone.slicedParagraph(paragraph, 7, 8);
      final extracted = WmlRunEdit.extractRuns(paragraph, 7, 8);
      final destination = WmlParagraph();
      WmlRunEdit.insertRuns(destination, 0, extracted);
      WmlRunEdit.applyRange(copied, 7, 8, (props) => props.bold = true);
      final comment = WmlComment(
        id: 0,
        paragraphs: <WmlParagraph>[paragraph],
      ).copy();
      for (final owner in <WmlParagraph>[
        copied,
        sliced,
        destination,
        comment.paragraphs.single,
      ]) {
        final field = _fields(owner).single;
        expect(field.text, '(Author 2026)');
        expect(field.fieldInstruction, ' CITATION source ');
        expect(field.fieldLocked, isTrue);
        expect(field.fieldDirty, isFalse);
      }
      expect(_fields(copied).single.properties.bold, isTrue);
      expect(_fields(paragraph).single.properties.bold, isFalse);
      WmlRunEdit.replaceRange(copied, 7, 8, 'replacement');
      expect(copied.text, 'BeforereplacementAfter');
      expect(_fields(copied), isEmpty);
    },
  );

  test(
    'citation insertion rejects existing paragraph fields before mutation',
    () {
      final document = WmlDocument.empty(text: 'Existing live result');
      final paragraph = document.paragraphs.single;
      paragraph.properties.fieldInstruction = ' REF ExistingBookmark ';
      expect(
        () => WordCitations.insert(
          document,
          paragraph,
          WmlCitation(tag: 'new', author: 'New author', title: 'New source'),
        ),
        throwsUnsupportedError,
      );
      expect(paragraph.text, 'Existing live result');
      expect(paragraph.properties.fieldInstruction, ' REF ExistingBookmark ');
      expect(document.citations, isEmpty);
    },
  );

  test('inline fields refresh in headers, notes, and comments', () {
    final document = WmlDocument.empty(text: 'Body');
    WmlParagraph story() => WmlParagraph(
      inlines: <WmlInline>[
        WmlRun(text: 'Prefix '),
        WmlRun(text: 'old', fieldInstruction: ' CITATION source '),
        WmlRun(text: ' suffix'),
      ],
    );
    final header = story();
    final note = story();
    final comment = story();
    document.sections.single.header.add(header);
    document.footnotes.add(
      WmlNote(id: 1, endnote: false, paragraphs: <WmlParagraph>[note]),
    );
    document.comments.add(
      WmlComment(id: 0, paragraphs: <WmlParagraph>[comment]),
    );
    document.citations.add(
      WmlCitation(
        tag: 'source',
        author: 'Author',
        title: 'Source',
        year: '2026',
      ),
    );
    WordFields.update(document);
    for (final paragraph in <WmlParagraph>[header, note, comment]) {
      expect(paragraph.text, 'Prefix (Author 2026) suffix');
    }
    final page = WmlParagraph(
      inlines: <WmlInline>[
        WmlRun(text: 'Page '),
        WmlRun(text: '1', fieldInstruction: ' PAGE '),
        WmlRun(text: ' of '),
        WmlRun(text: '1', fieldInstruction: ' NUMPAGES '),
      ],
    );
    expect(
      WordFields.chromeText(
        page,
        document: document,
        pageNumber: 4,
        pageCount: 8,
      ),
      'Page 4 of 8',
    );
  });
}
