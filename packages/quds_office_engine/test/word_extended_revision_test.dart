import 'dart:io';
import 'dart:typed_data';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const meta =
    'w:id="13" w:author="Original reviewer" w:date="2026-11-19T10:00:00Z"';
String run(String text, [String properties = '']) =>
    '<w:r><w:rPr>$properties</w:rPr><w:t xml:space="preserve">$text</w:t></w:r>';
String changedRun(String text) =>
    run(text, '<w:b/><w:rPrChange $meta><w:rPr><w:i/></w:rPr></w:rPrChange>');
WmlDocument read(String body, {String? styles}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$w"><w:body>$body<w:sectPr/></w:body></w:document>',
      );
  if (styles != null) {
    package.createPart(
      '/word/styles.xml',
      OfficeContentTypes.wordStyles,
      Uint8List.fromList(styles.codeUnits),
    );
    package
        .relationshipsFor('/word/document.xml')
        .add(type: RelationshipTypes.styles, target: 'styles.xml');
  }
  return WordDeserializer().read(package);
}

WmlRun firstRun(WmlDocument d) =>
    d.paragraphs.first.inlines.whereType<WmlRun>().first;
WmlDocument reopen(WmlDocument d) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(d));
String move(String kind, String name, int id, String content) =>
    '<w:${kind}RangeStart w:id="$id" w:name="$name"/>'
    '<w:$kind $meta>$content</w:$kind><w:${kind}RangeEnd w:id="$id"/>';
void main() {
  test(
    'run history does not override current properties; reject restores the previous set',
    () {
      final d = read('<w:p>${changedRun('Changed')}</w:p>');
      expect(firstRun(d).properties.bold, isTrue);
      expect(firstRun(d).properties.italic, isFalse);
      expect(d.revisions.single.kind, WmlRevisionKind.runFormat);
      expect(d.revisions.single.author, 'Original reviewer');
      WordRevisions.reject(d, d.revisions.single);
      expect(firstRun(d).properties.bold, isFalse);
      expect(firstRun(d).properties.italic, isTrue);
      expect(reopen(d).revisions, isEmpty);
    },
  );
  test('accept keeps current formatting and removes native history', () {
    final d = read('<w:p>${changedRun('Changed')}</w:p>');
    WordRevisions.accept(d, d.revisions.single);
    final copy = reopen(d);
    expect(copy.revisions, isEmpty);
    expect(firstRun(copy).properties.bold, isTrue);
    expect(firstRun(copy).properties.italic, isFalse);
  });
  test(
    'paragraph formatting imports current alignment and rejects previous spacing',
    () {
      final d = read(
        '<w:p><w:pPr><w:jc w:val="center"/><w:pPrChange $meta><w:pPr><w:spacing w:after="240"/><w:jc w:val="right"/></w:pPr></w:pPrChange></w:pPr>${run('Paragraph')}</w:p>',
      );
      expect(
        d.paragraphs.first.properties.justification,
        WmlJustification.center,
      );
      expect(d.revisions.single.kind, WmlRevisionKind.paragraphFormat);
      WordRevisions.reject(d, d.revisions.single);
      expect(
        d.paragraphs.first.properties.justification,
        WmlJustification.right,
      );
      expect(d.paragraphs.first.properties.spacingAfter, 12);
      expect(reopen(d).revisions, isEmpty);
    },
  );
  test(
    'empty previous properties restore inheritance instead of editor defaults',
    () {
      const styles =
          '<w:styles xmlns:w="$w"><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:rPr><w:b/><w:color w:val="224466"/></w:rPr></w:style></w:styles>';
      final d = read(
        '<w:p>${run('Styled', '<w:b w:val="0"/><w:rPrChange $meta><w:rPr/></w:rPrChange>')}</w:p>',
        styles: styles,
      );
      expect(firstRun(d).properties.bold, isFalse);
      WordRevisions.reject(d, d.revisions.single);
      expect(firstRun(d).properties.bold, isTrue);
      expect(firstRun(d).properties.color, '224466');
      expect(
        firstRun(d).properties.sourcePropertiesXml,
        isNot(contains('<w:b')),
      );
    },
  );
  for (final isolate in [false, true]) {
    test(
      'formatting history survives three ${isolate ? 'isolate' : 'direct'} saves',
      () async {
        var d = read(
          '<w:p><w:pPr><w:jc w:val="center"/><w:pPrChange $meta><w:pPr/></w:pPrChange></w:pPr>${changedRun('Changed')}</w:p>',
        );
        for (var i = 0; i < 3; i++) {
          final bytes = isolate
              ? await OfficeIsolateSave.word(d)
              : WordSerializer().writeBytes(d);
          d = WordDeserializer().readBytes(bytes);
          expect(d.revisions.map((r) => r.kind).toSet(), {
            WmlRevisionKind.runFormat,
            WmlRevisionKind.paragraphFormat,
          });
          expect(
            d.revisions.every(
              (r) =>
                  r.author == 'Original reviewer' &&
                  r.dateIso == '2026-11-19T10:00:00Z',
            ),
            isTrue,
          );
          expect(firstRun(d).properties.bold, isTrue);
        }
      },
    );
  }
  for (final accept in [true, false]) {
    test(
      '${accept ? 'accept' : 'reject'} either side resolves an entire multi-run move',
      () {
        final d = read(
          '<w:p>${move('moveFrom', 'paired', 2, run('Old ') + run('place'))}${run(' middle ')}${move('moveTo', 'paired', 4, run('New ') + run('place'))}</w:p>',
        );
        expect(d.revisions.map((r) => r.kind).toSet(), {
          WmlRevisionKind.moveFrom,
          WmlRevisionKind.moveTo,
        });
        final selected = d.revisions.last;
        if (accept) {
          WordRevisions.accept(d, selected);
        } else {
          WordRevisions.reject(d, selected);
        }
        expect(d.revisions, isEmpty);
        expect(
          d.paragraphs.first.text,
          accept ? ' middle New place' : 'Old place middle ',
        );
        expect(reopen(d).revisions, isEmpty);
      },
    );
  }
  test(
    'move endpoints and linkage survive repeated native saves across paragraphs',
    () {
      var d = read(
        '<w:p><w:moveFromRangeStart w:id="2" w:name="paired"/><w:moveFrom $meta>${run('Part one')}</w:moveFrom></w:p><w:p><w:moveFrom $meta>${run('Part two')}</w:moveFrom><w:moveFromRangeEnd w:id="2"/></w:p><w:p>${move('moveTo', 'paired', 4, run('Part onePart two'))}</w:p>',
      );
      for (var i = 0; i < 3; i++) {
        d = reopen(d);
        expect(d.revisions, hasLength(3));
        expect(d.revisions.every((r) => r.moveName == 'paired'), isTrue);
      }
      WordRevisions.accept(d, d.revisions.first);
      expect(d.paragraphs.map((p) => p.text), ['', '', 'Part onePart two']);
      expect(d.revisions, isEmpty);
    },
  );
  test('move preflight is atomic when the other side is stale', () {
    final d = read(
      '<w:p>${move('moveFrom', 'paired', 2, run('from'))}${move('moveTo', 'paired', 4, run('to'))}</w:p>',
    );
    d.revisions.last.text = 'invalid';
    expect(() => WordRevisions.accept(d, d.revisions.first), throwsStateError);
    expect(d.paragraphs.first.text, 'fromto');
    expect(d.revisions, hasLength(2));
  });
  test(
    'formatting can overlap tracked text; accepting deletion discards its formatting',
    () {
      final d = read(
        '<w:p><w:del $meta>${changedRun('deleted')}</w:del>${run(' retained')}</w:p>',
      );
      expect(d.revisions, hasLength(2));
      WordRevisions.validate(d);
      final copy = reopen(d);
      expect(copy.revisions, hasLength(2));
      WordRevisions.acceptAll(copy);
      expect(copy.revisions, isEmpty);
      expect(copy.paragraphs.first.text, ' retained');
    },
  );
  test(
    'rejecting formatting leaves the overlapping text insertion pending',
    () {
      final d = read(
        '<w:p><w:ins $meta>${changedRun('inserted')}</w:ins></w:p>',
      );
      WordRevisions.reject(
        d,
        d.revisions.firstWhere((r) => r.kind.isFormatting),
      );
      expect(d.revisions.single.kind, WmlRevisionKind.insert);
      expect(firstRun(d).properties.italic, isTrue);
      expect(reopen(d).revisions.single.kind, WmlRevisionKind.insert);
    },
  );
  test('empty paragraphs preserve and resolve paragraph formatting', () {
    final d = read(
      '<w:p><w:pPr><w:jc w:val="right"/><w:pPrChange $meta><w:pPr/></w:pPrChange></w:pPr></w:p>',
    );
    expect(reopen(d).revisions.single.kind, WmlRevisionKind.paragraphFormat);
    WordRevisions.acceptAll(d);
    expect(reopen(d).revisions, isEmpty);
  });
  test(
    'old color, size and language attributes restore with namespace identity',
    () {
      final d = read(
        '<w:p>${run('Properties', '<w:color w:val="FF0000"/><w:rPrChange $meta><w:rPr><w:color w:val="112233"/><w:sz w:val="32"/><w:lang w:val="de-DE"/></w:rPr></w:rPrChange>')}</w:p>',
      );
      WordRevisions.reject(d, d.revisions.single);
      expect(firstRun(d).properties.color, '112233');
      expect(firstRun(d).properties.fontSizeHalfPoints, 32);
      expect(firstRun(d).properties.proofingLanguage, 'de-DE');
    },
  );
  test(
    'formatting ranges rebase through a text replacement without text attribution conflicts',
    () {
      final d = read('<w:p>${changedRun('Before')}</w:p>');
      final p = d.paragraphs.first;
      WordRevisions.rebaseEdit(d, p, start: 1, end: 4, insertedLength: 1);
      WmlRunEdit.replaceRange(p, 1, 4, 'X');
      expect(d.revisions.single.conflict, isNull);
      expect(d.revisions.single.displayText, 'BXre');
      expect(reopen(d).revisions.single.displayText, 'BXre');
      WordRevisions.reject(d, d.revisions.single);
      expect(p.text, 'BXre');
      expect(
        p.inlines.whereType<WmlRun>().every((r) => r.properties.italic),
        isTrue,
      );
    },
  );
  test('paragraph formatting remains reviewable when its text changes', () {
    final d = read(
      '<w:p><w:pPr><w:jc w:val="center"/><w:pPrChange $meta><w:pPr><w:jc w:val="right"/></w:pPr></w:pPrChange></w:pPr>${run('Before')}</w:p>',
    );
    final p = d.paragraphs.first;
    WordRevisions.rebaseEdit(d, p, start: 0, end: 6, insertedLength: 1);
    WmlRunEdit.replaceRange(p, 0, 6, 'X');
    expect(reopen(d).revisions.single.displayText, 'X');
    WordRevisions.reject(d, d.revisions.single);
    expect(p.properties.justification, WmlJustification.right);
  });
  test(
    'a missing previous property set cannot be silently accepted or exported',
    () {
      final d = read(
        '<w:p>${run('Broken', '<w:b/><w:rPrChange $meta/>')}</w:p>',
      );
      expect(
        () => WordRevisions.accept(d, d.revisions.single),
        throwsStateError,
      );
      expect(() => WordSerializer().writeBytes(d), throwsStateError);
    },
  );
  test(
    'an incomplete move cannot be partially resolved or silently exported',
    () {
      final d = read(
        '<w:p>${move('moveFrom', 'missingDestination', 2, run('Source'))}</w:p>',
      );
      expect(
        () => WordRevisions.accept(d, d.revisions.single),
        throwsStateError,
      );
      expect(() => WordSerializer().writeBytes(d), throwsStateError);
      expect(d.paragraphs.first.text, 'Source');
    },
  );
  test(
    'move preflight checks a protected destination before deleting source text',
    () {
      final d = read(
        '<w:p>${move('moveFrom', 'paired', 2, run('Source'))}<w:sdt><w:sdtPr><w:id w:val="6"/><w:lock w:val="contentLocked"/></w:sdtPr><w:sdtContent>${move('moveTo', 'paired', 4, run('Destination'))}</w:sdtContent></w:sdt></w:p>',
      );
      final before = d.paragraphs.first.text;
      expect(
        () => WordRevisions.accept(d, d.revisions.first),
        throwsStateError,
      );
      expect(d.paragraphs.first.text, before);
      expect(d.revisions, hasLength(2));
    },
  );
  test(
    'Word 16.111.1 saved native formatting and move revisions round-trip',
    () {
      final package = OpcPackage.create(OpcPackageKind.word);
      package
          .getPart('/word/document.xml')!
          .writeText(
            File(
              'test/fixtures/word_reviews/word-mac-16.111.1.xml',
            ).readAsStringSync(),
          );
      final doc = WordDeserializer().read(package);
      expect(doc.revisions.map((r) => r.kind).toSet(), {
        WmlRevisionKind.runFormat,
        WmlRevisionKind.paragraphFormat,
        WmlRevisionKind.moveFrom,
        WmlRevisionKind.moveTo,
      });
      final copy = reopen(doc);
      expect(copy.revisions, hasLength(4));
      expect(
        copy.revisions.every((r) => r.author == 'Original reviewer'),
        isTrue,
      );
      WordRevisions.rejectAll(copy);
      expect(firstRun(copy).properties.italic, isTrue);
      expect(
        copy.paragraphs.last.properties.justification,
        WmlJustification.right,
      );
      expect(
        copy.paragraphs.elementAt(1).text,
        'Moved sentence.Some other text.',
      );
    },
  );
  test('an empty text run retains its formatting revision through a save', () {
    final doc = read('<w:p>${changedRun('')}</w:p>');
    expect(reopen(doc).revisions.single.kind, WmlRevisionKind.runFormat);
    WordRevisions.rejectAll(doc);
    expect(reopen(doc).revisions, isEmpty);
  });
  test(
    'ambiguous or removed empty formatting targets fail without losing history',
    () {
      final duplicate = read('<w:p>${changedRun('')}${changedRun('')}</w:p>');
      expect(duplicate.revisions, hasLength(2));
      expect(() => WordSerializer().writeBytes(duplicate), throwsStateError);
      final removed = read('<w:p>${changedRun('')}</w:p>');
      removed.paragraphs.first.inlines.clear();
      expect(() => WordSerializer().writeBytes(removed), throwsStateError);
      expect(removed.revisions, hasLength(1));
    },
  );
  test('write a native tracked formatting and move interoperability fixture', () {
    final d = read(
      '<w:p>${changedRun('Changed formatting')}</w:p><w:p>${move('moveFrom', 'paired', 2, run('Moved sentence.'))}${run('Some other text.')}${move('moveTo', 'paired', 4, run('Moved sentence.'))}</w:p><w:p><w:pPr><w:jc w:val="center"/><w:pPrChange $meta><w:pPr><w:jc w:val="right"/></w:pPr></w:pPrChange></w:pPr>${run('Paragraph formatting')}</w:p>',
    );
    final output = File('build/fidelity-extended-revisions/review.docx');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(WordSerializer().writeBytes(d));
    expect(reopen(d).revisions, hasLength(4));
  });
}
