import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WmlContentControlData _control() => WmlContentControlData(
  xml: '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtContent/></w:sdt>',
  sourcePartUri: '/word/document.xml',
  relationships: const [],
);

final _shapeChanges = <String, void Function(WmlParagraph)>{
  'atomic field': (paragraph) {
    paragraph.inlines.whereType<WmlRun>().single.fieldInstruction =
        ' REF entire ';
  },
  'content-control boundaries': (paragraph) {
    final control = _control();
    paragraph.inlines.insert(
      0,
      WmlContentControlBoundary(control: control, start: true),
    );
    paragraph.inlines.add(
      WmlContentControlBoundary(control: control, start: false),
    );
  },
  'bookmark boundaries': (paragraph) {
    paragraph.inlines.insert(
      0,
      WmlBookmarkBoundary(id: '1', isStart: true, name: 'Target'),
    );
    paragraph.inlines.add(WmlBookmarkBoundary(id: '1', isStart: false));
  },
};

void main() {
  test(
    'replace all validates later control boundaries before earlier matches mutate',
    () {
      final first = _paragraph('bX safe');
      final control = WmlContentControlData(
        xml: '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtContent/></w:sdt>',
        sourcePartUri: '/word/document.xml',
        relationships: const [],
      );
      final last = WmlParagraph(
        inlines: [
          WmlRun(text: 'ab'),
          WmlContentControlBoundary(control: control, start: true),
          WmlRun(text: 'XYZ'),
          WmlContentControlBoundary(control: control, start: false),
          WmlRun(text: 'cd'),
        ],
      );
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [first, last]),
        ],
      );
      expect(
        () => OfficeFind.replaceWord(
          document,
          const OfficeFindOptions(query: 'bX', replaceWith: '!'),
        ),
        throwsUnsupportedError,
      );
      expect(first.text, 'bX safe');
      expect(last.text, 'abXYZcd');
      expect(last.inlines.whereType<WmlContentControlBoundary>(), hasLength(2));
    },
  );

  test('a stale prepared plan fails before changing any of its targets', () {
    final first = _paragraph('old first');
    final last = _paragraph('old last');
    final document = WmlDocument(
      sections: [
        WmlSection(blocks: [first, last]),
      ],
    );
    final plan = OfficeFind.prepareWordReplace(
      document,
      const OfficeFindOptions(query: 'old', replaceWith: 'new'),
    );
    WmlRunEdit.replaceRange(last, 0, 0, '!');
    expect(plan.apply, throwsStateError);
    expect(first.text, 'old first');
    expect(last.text, '!old last');
  });

  for (final change in _shapeChanges.entries) {
    test('a stale ${change.key} plan fails before any replacement', () {
      final first = _paragraph('bar first');
      final last = _paragraph('foo bar baz');
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [first, last]),
        ],
      );
      final plan = OfficeFind.prepareWordReplace(
        document,
        const OfficeFindOptions(query: 'bar', replaceWith: 'X'),
      );
      change.value(last);
      final firstInlines = List<WmlInline>.of(first.inlines);
      final lastInlines = List<WmlInline>.of(last.inlines);
      expect(plan.apply, throwsStateError);
      expect(first.text, 'bar first');
      expect(last.text, 'foo bar baz');
      expect(first.inlines, orderedEquals(firstInlines));
      expect(last.inlines, orderedEquals(lastInlines));
    });

    test('a retained hit rejects changed ${change.key}', () {
      final document = WmlDocument.empty(text: 'foo bar baz');
      final paragraph = document.paragraphs.single;
      const options = OfficeFindOptions(query: 'bar', replaceWith: 'X');
      final hit = OfficeFind.inWord(document, options).single;
      change.value(paragraph);
      final inlines = List<WmlInline>.of(paragraph.inlines);
      expect(
        () => OfficeFind.replaceWord(document, options, only: hit),
        throwsStateError,
      );
      expect(paragraph.text, 'foo bar baz');
      expect(paragraph.inlines, orderedEquals(inlines));
    });
  }

  test('a prepared plan accepts equivalent rich history clones', () {
    final control = _control();
    final paragraph = WmlParagraph(
      inlines: [
        WmlContentControlBoundary(control: control, start: true),
        WmlBookmarkBoundary(id: '1', isStart: true, name: 'Target'),
        WmlRun(text: 'old'),
        WmlBookmarkBoundary(id: '1', isStart: false),
        WmlContentControlBoundary(control: control, start: false),
        WmlRun(text: ' tail'),
      ],
    );
    final document = WmlDocument(
      sections: [
        WmlSection(blocks: [paragraph]),
      ],
    );
    final plan = OfficeFind.prepareWordReplace(
      document,
      const OfficeFindOptions(query: 'old', replaceWith: 'new'),
    );
    paragraph.inlines = WmlClone.inlines(paragraph.inlines);
    expect(plan.apply(), 1);
    expect(paragraph.text, 'new tail');
    expect(WordBookmarks.byName(document, 'Target')!.text, 'new');
    expect(
      paragraph.inlines.whereType<WmlContentControlBoundary>(),
      hasLength(2),
    );
  });

  test('multiple matches inside one atomic field replace it once', () {
    final paragraph = WmlParagraph(
      inlines: [
        WmlRun(text: 'Before '),
        WmlRun(text: 'foofoo', fieldInstruction: ' REF target '),
        WmlRun(text: ' after'),
      ],
    );
    final document = WmlDocument(
      sections: [
        WmlSection(blocks: [paragraph]),
      ],
    );
    expect(
      OfficeFind.replaceWord(
        document,
        const OfficeFindOptions(query: 'foo', replaceWith: 'Replacement'),
      ),
      1,
    );
    expect(paragraph.text, 'Before Replacement after');
    expect(
      paragraph.inlines.whereType<WmlRun>().where((run) => run.isAtomic),
      isEmpty,
    );
  });

  test('a stale selected match cannot replace unrelated text', () {
    final document = WmlDocument.empty(text: 'old target');
    const options = OfficeFindOptions(query: 'old', replaceWith: 'replacement');
    final hit = OfficeFind.inWord(document, options).single;
    WmlRunEdit.replaceRange(document.paragraphs.single, 0, 3, 'new');
    expect(
      () => OfficeFind.replaceWord(document, options, only: hit),
      throwsStateError,
    );
    expect(document.paragraphs.single.text, 'new target');
  });

  test(
    'a retained hit rejects an identical paragraph inserted at its index',
    () {
      final target = _paragraph('old target');
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [target]),
        ],
      );
      const options = OfficeFindOptions(query: 'old', replaceWith: 'new');
      final hit = OfficeFind.inWord(document, options).single;
      final inserted = _paragraph('old target');
      document.sections.single.blocks.insert(0, inserted);
      expect(
        () => OfficeFind.replaceWord(document, options, only: hit),
        throwsStateError,
      );
      expect(document.paragraphs, [same(inserted), same(target)]);
      expect(inserted.text, 'old target');
      expect(target.text, 'old target');
    },
  );

  test('a retained hit cannot be used in another document', () {
    final target = _paragraph('old target');
    final source = WmlDocument(
      sections: [
        WmlSection(blocks: [target]),
      ],
    );
    final destination = WmlDocument(
      sections: [
        WmlSection(blocks: [target]),
      ],
    );
    const options = OfficeFindOptions(query: 'old', replaceWith: 'new');
    final hit = OfficeFind.inWord(source, options).single;
    expect(
      () => OfficeFind.replaceWord(destination, options, only: hit),
      throwsStateError,
    );
    expect(target.text, 'old target');
  });
}
