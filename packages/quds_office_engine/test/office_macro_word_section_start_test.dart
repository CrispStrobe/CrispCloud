import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_section_start_steps.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_page_setup_smoke.dart' as fixture;

const _w = OfficeNamespaces.w;
const _x = 'urn:word-section-start-test';

WmlDocument _document({
  String start = '<w:type w:val="continuous"/>',
  String extra = '',
  String attributes = '',
}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Original text')).build(),
  );
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="$_w" xmlns:x="$_x" xmlns:mc="${OfficeNamespaces.mc}" $attributes><w:body>
<w:p><w:r><w:t>Original text</w:t></w:r></w:p>
<w:sectPr>$start
<w:pgSz w:w="12240" w:h="15840" w:orient="portrait" w:code="9"/>
<w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440" w:header="720" w:footer="720"/>
<w:cols w:num="2" w:space="720"/><w:pgNumType w:start="7"/>
<x:metadata x:val="keep"/>$extra</w:sectPr>
</w:body></w:document>''');
  return WordDeserializer().read(package);
}

XmlElement _source(WmlSection section) =>
    XmlDocument.parse(section.sourceProperties!.xml).root!;

void _set(WmlDocument document, String kind) =>
    setWordSectionStart(document, document.sections.single, kind: kind);

void _refuses(WmlDocument document, String kind, Matcher failure) {
  final section = document.sections.single;
  final before = section.breakKind;
  final source = section.sourceProperties;
  final size = section.pageSize;
  final margins = section.margins;
  final parts = <String, Uint8List>{
    for (final part in document.package!.parts) part.uri: part.readBytes(),
  };
  expect(() => _set(document, kind), failure);
  expect(section.breakKind, before);
  expect(section.sourceProperties, same(source));
  expect(section.pageSize, same(size));
  expect(section.margins, same(margins));
  expect({
    for (final part in document.package!.parts) part.uri: part.readBytes(),
  }, parts);
}

void main() {
  for (final kind in ['continuous', 'nextPage', 'evenPage', 'oddPage']) {
    test('$kind edits only the selected section through DOCM reopens', () {
      var document = WordDeserializer().readBytes(fixture.wordPageSetupInput());
      final before = fixture.wordPageSetupState(fixture.wordPageSetupInput());
      setWordSectionStart(document, document.sections[1], kind: kind);
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = WordSerializer().writeBytes(document);
        final state = fixture.wordPageSetupState(bytes);
        expect(state, [
          before[0],
          {...before[1], 'break': kind},
          before[2],
        ]);
        final start = fixture
            .wordPageSetupSection(bytes, 1)
            .firstChild('type', namespaceUri: _w)!;
        expect(start.getAttribute('val', namespaceUri: _w), kind);
        fixture.assertWordPageSetupPackage(bytes);
        document = WordDeserializer().readBytes(bytes);
      }
    });
  }

  test('a source-free section writes its new break on first serialization', () {
    final document = WmlDocument.empty(text: 'Fresh');
    expect(document.sections.single.sourceProperties, isNull);
    _set(document, 'oddPage');
    final reopened = WordDeserializer().readBytes(
      WordSerializer().writeBytes(document),
    );
    expect(reopened.sections.single.breakKind, WmlSectionBreakKind.oddPage);
    expect(reopened.paragraphs.single.text, 'Fresh');
  });

  for (final (kind, pageNumber) in [
    ('continuous', 1),
    ('nextPage', 2),
    ('evenPage', 2),
    ('oddPage', 3),
  ]) {
    test('$kind starts the selected section on expected laid-out page', () {
      var document = WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlParagraph(inlines: [WmlRun(text: 'First section')]),
            ],
          ),
          WmlSection(
            blocks: [
              WmlParagraph(inlines: [WmlRun(text: 'Second section')]),
            ],
          ),
        ],
      );
      setWordSectionStart(document, document.sections[1], kind: kind);
      for (var cycle = 0; cycle < 2; cycle++) {
        final laid = WordLayoutEngine(font: null).layout(document);
        final pageIndex = laid.pages.indexWhere(
          (page) => page.lines.any((line) => line.paragraphIndex == 1),
        );
        expect(pageIndex + 1, pageNumber);
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
      }
    });
  }

  test('same-value assignment creates an explicit missing native type', () {
    final document = _document(start: '');
    expect(document.sections.single.breakKind, WmlSectionBreakKind.nextPage);
    _set(document, 'nextPage');
    final source = _source(document.sections.single);
    expect(
      source
          .firstChild('type', namespaceUri: _w)!
          .getAttribute('val', namespaceUri: _w),
      'nextPage',
    );
    final reopened = WordDeserializer().readBytes(
      WordSerializer().writeBytes(document),
    );
    expect(reopened.sections.single.breakKind, WmlSectionBreakKind.nextPage);
    expect(
      _source(reopened.sections.single).firstChild('type', namespaceUri: _w),
      isNotNull,
    );
  });

  test('explicit target replaces an imported unmodeled break fallback', () {
    final document = _document(
      start: '<w:type w:val="nextColumn" x:val="foreign"/>',
    );
    expect(document.sections.single.breakKind, WmlSectionBreakKind.nextPage);
    _set(document, 'nextPage');
    final reopened = WordDeserializer().readBytes(
      WordSerializer().writeBytes(document),
    );
    final start = _source(
      reopened.sections.single,
    ).firstChild('type', namespaceUri: _w)!;
    expect(start.getAttribute('val', namespaceUri: _w), 'nextPage');
    expect(start.getAttribute('val', namespaceUri: _x), 'foreign');
  });

  test(
    'source ownership preserves pending general geometry and section edits',
    () {
      var document = _document(
        extra:
            '<w:sectPrChange w:id="7" w:author="History">'
            '<w:sectPr><w:type w:val="evenPage"/></w:sectPr>'
            '</w:sectPrChange>',
      );
      native.applyStep(document, {
        'op': 'sectionFormat',
        'section': 0,
        'height': 900,
        'left': 54,
        'differentFirstPage': true,
        'breakKind': 'oddPage',
      });
      _set(document, 'evenPage');
      for (var cycle = 0; cycle < 3; cycle++) {
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        final section = document.sections.single;
        expect(section.breakKind, WmlSectionBreakKind.evenPage);
        expect(section.pageSize.height, 900);
        expect(section.margins.left, 54);
        expect(section.differentFirstPage, isTrue);
        expect(section.columnCount, 2);
        final source = _source(section);
        expect(
          source
              .firstChild('pgNumType', namespaceUri: _w)!
              .getAttribute('start', namespaceUri: _w),
          '7',
        );
        expect(source.firstChild('metadata', namespaceUri: _x), isNotNull);
        expect(
          source
              .firstChild('sectPrChange', namespaceUri: _w)!
              .firstChild('sectPr', namespaceUri: _w)!
              .firstChild('type', namespaceUri: _w)!
              .getAttribute('val', namespaceUri: _w),
          'evenPage',
        );
      }
    },
  );

  for (final start in [
    '<type xmlns="$_w" xmlns:w="$_x" xmlns:n="$_w" '
        'n:val="continuous" w:val="foreign"><w:opaque/></type>',
    '<type xmlns="$_w" xmlns:w="$_x" w:val="foreign"><w:opaque/></type>',
  ]) {
    test('native type writes preserve foreign namespace aliases: $start', () {
      var document = _document(start: start);
      _set(document, 'oddPage');
      final snapshot = document.sections.single.sourceProperties!.xml;
      for (var index = 0; index < 20; index++) {
        _set(document, 'oddPage');
      }
      expect(document.sections.single.sourceProperties!.xml, snapshot);
      for (var cycle = 0; cycle < 3; cycle++) {
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        final type = _source(
          document.sections.single,
        ).firstChild('type', namespaceUri: _w)!;
        expect(type.getAttribute('val', namespaceUri: _w), 'oddPage');
        expect(type.getAttribute('val', namespaceUri: _x), 'foreign');
        expect(type.firstChild('opaque', namespaceUri: _x), isNotNull);
        expect(type.firstChild('opaque', namespaceUri: _w), isNull);
      }
    });
  }

  test('section start does not require geometry or supported margin modes', () {
    final document = _document();
    final section = document.sections.single;
    final source = section.sourceProperties!;
    section.sourceProperties = WmlSectionSource(
      xml: source.xml.replaceFirst('w:top="1440"', 'w:top="-240"'),
      values: source.values,
    );
    _set(document, 'oddPage');
    expect(
      _source(section)
          .firstChild('pgMar', namespaceUri: _w)!
          .getAttribute('top', namespaceUri: _w),
      '-240',
    );
    expect(section.breakKind, WmlSectionBreakKind.oddPage);
  });

  for (final kind in ['', 'newPage', 'nextColumn', 'portrait', 'EVENPAGE']) {
    test('unsupported target $kind is rejected without mutation', () {
      _refuses(_document(), kind, throwsArgumentError);
    });
  }

  for (final start in [
    '<w:type w:val="continuous"/><w:type w:val="oddPage"/>',
    '<w:type xmlns:n="$_w" w:val="continuous" n:val="oddPage"/>',
  ]) {
    test(
      'ambiguous direct native type is rejected before mutation: $start',
      () {
        _refuses(_document(start: start), 'evenPage', throwsUnsupportedError);
      },
    );
  }

  test('foreign type siblings are preserved and do not affect selection', () {
    final document = _document(extra: '<x:type x:val="foreign"/>');
    _set(document, 'oddPage');
    final source = _source(document.sections.single);
    expect(
      source
          .firstChild('type', namespaceUri: _w)!
          .getAttribute('val', namespaceUri: _w),
      'oddPage',
    );
    expect(
      source
          .firstChild('type', namespaceUri: _x)!
          .getAttribute('val', namespaceUri: _x),
      'foreign',
    );
  });

  for (final attributes in ['mc:Ignorable="x" mc:ProcessContent="x:wrapper"']) {
    test('ProcessContent identity ambiguity is rejected atomically', () {
      _refuses(
        _document(attributes: attributes),
        'evenPage',
        throwsUnsupportedError,
      );
    });
  }

  test(
    'original alternative section properties are rejected after projection',
    () {
      final document = _document();
      final part = document.package!.getPart('/word/document.xml')!;
      part.writeText(
        part
            .readText()
            .replaceFirst(
              '<w:sectPr>',
              '<mc:AlternateContent><mc:Choice Requires="x"><w:sectPr>',
            )
            .replaceFirst(
              '</w:sectPr>',
              '</w:sectPr></mc:Choice>'
                  '<mc:Fallback><w:sectPr/></mc:Fallback></mc:AlternateContent>',
            ),
      );
      // The captured model still resolves one section. Admission must also
      // inspect the original package, not only that projected source fragment.
      _refuses(document, 'oddPage', throwsUnsupportedError);
    },
  );

  test('a malformed section source is rejected before changing the break', () {
    final document = _document();
    final section = document.sections.single;
    section.sourceProperties = WmlSectionSource(
      xml: '<x:sectPr xmlns:x="$_x"/>',
      values: section.sourceProperties!.values,
    );
    _refuses(document, 'oddPage', throwsUnsupportedError);
  });
}
