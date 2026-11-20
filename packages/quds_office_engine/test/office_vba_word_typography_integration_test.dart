import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/serial/word_property_io.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String body) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    source:
        '''
Sub Main()
With Application.ActiveDocument.Paragraphs.Item(1).Range
$body
End With
End Sub
''',
  ),
);

Uint8List _fixture(String runs, {String styles = ''}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p>$runs'
        '</w:p><w:sectPr/></w:body></w:document>',
      );
  if (styles.isNotEmpty) {
    package
        .getPart('/word/styles.xml')!
        .writeText(
          '<w:styles xmlns:w="${OfficeNamespaces.w}">$styles</w:styles>',
        );
  }
  return package.save();
}

List<WmlRun> _runs(Uint8List bytes) => WordDeserializer()
    .readBytes(bytes)
    .paragraphs
    .single
    .inlines
    .whereType<WmlRun>()
    .where((run) => run.text.isNotEmpty)
    .toList();

List<XmlElement> _elements(XmlElement root, String name) => <XmlElement>[
  for (final child in root.childElements) ...<XmlElement>[
    if (child.localName == name && child.namespaceUri == OfficeNamespaces.w)
      child,
    ..._elements(child, name),
  ],
];

XmlElement _xml(Uint8List bytes) => XmlDocument.parse(
  OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
).root!;

String? _val(XmlElement element) =>
    element.getAttribute('val', namespaceUri: OfficeNamespaces.w);

const _mixedRuns =
    '<w:r><w:rPr><w:rStyle w:val="Super"/></w:rPr><w:t>Super</w:t></w:r>'
    '<w:r><w:rPr><w:rStyle w:val="Sub"/></w:rPr><w:t>Sub</w:t></w:r>'
    '<w:r><w:t>Base</w:t></w:r>';
const _mixedStyles =
    '<w:style w:type="character" w:styleId="Super"><w:rPr>'
    '<w:vertAlign w:val="superscript"/><w:smallCaps/>'
    '<w:highlight w:val="yellow"/></w:rPr></w:style>'
    '<w:style w:type="character" w:styleId="Sub"><w:rPr>'
    '<w:vertAlign w:val="subscript"/></w:rPr></w:style>';

void main() {
  for (final (property, expected) in <(String, List<WmlVertAlign>)>[
    (
      'Superscript',
      [WmlVertAlign.baseline, WmlVertAlign.subscript, WmlVertAlign.baseline],
    ),
    (
      'Subscript',
      [WmlVertAlign.superscript, WmlVertAlign.baseline, WmlVertAlign.baseline],
    ),
  ]) {
    test(
      '$property=False clears only that mode across inherited mixed runs',
      () async {
        final bytes = _fixture(_mixedRuns, styles: _mixedStyles);
        expect(_runs(bytes).map((run) => run.properties.vertAlign), [
          WmlVertAlign.superscript,
          WmlVertAlign.subscript,
          WmlVertAlign.baseline,
        ]);
        final session = OfficeMacroSession(
          bytes,
          format: OfficeMacroFormat.docx,
        );
        final plan = _compile('.Font.$property = False');
        await session.validate(plan);
        expect(session.bytes, bytes);
        expect(session.revision, 0);
        for (var repeat = 0; repeat < 2; repeat++) {
          await session.run(plan);
          expect(_runs(session.bytes).map((run) => run.text), [
            'Super',
            'Sub',
            'Base',
          ]);
          expect(
            _runs(session.bytes).map((run) => run.properties.vertAlign),
            expected,
          );
          final root = _xml(session.bytes);
          expect(
            _elements(root, 'vertAlign').map(_val),
            expected.map((value) => value.name),
          );
          expect(_elements(root, 'rStyle').map(_val), ['Super', 'Sub']);
        }
      },
    );
  }

  test(
    'true assignments select one script mode; later false preserves the opposite',
    () async {
      final session = OfficeMacroSession(
        _fixture(_mixedRuns, styles: _mixedStyles),
        format: OfficeMacroFormat.docx,
      );
      await session.run(
        _compile('.Font.Superscript = True\n.Font.Subscript = False'),
      );
      expect(
        _runs(session.bytes).map((run) => run.properties.vertAlign),
        everyElement(WmlVertAlign.superscript),
      );
      await session.run(
        _compile('.Font.Subscript = True\n.Font.Superscript = False'),
      );
      expect(
        _runs(session.bytes).map((run) => run.properties.vertAlign),
        everyElement(WmlVertAlign.subscript),
      );
      await session.run(_compile('.Font.Subscript = False'));
      expect(
        _runs(session.bytes).map((run) => run.properties.vertAlign),
        everyElement(WmlVertAlign.baseline),
      );
    },
  );

  test(
    'SmallCaps explicitly clears inherited and direct caps, preserving source',
    () async {
      final session = OfficeMacroSession(
        _fixture(
          '<w:r><w:rPr><w:rStyle w:val="CapStyle"/><w:color w:val="112233"/>'
          '<w:lang w:val="en-US" w:eastAsia="ja-JP"/></w:rPr><w:t>Mixed</w:t></w:r>'
          '<w:r><w:rPr><w:caps/><w:i/><w:sz w:val="32"/></w:rPr><w:t>Text</w:t></w:r>',
          styles:
              '<w:style w:type="character" w:styleId="CapStyle"><w:rPr>'
              '<w:caps/><w:smallCaps w:val="0"/><w:b/></w:rPr></w:style>',
        ),
        format: OfficeMacroFormat.docx,
      );
      await session.run(_compile('.Font.SmallCaps = True'));
      for (var reopen = 0; reopen < 2; reopen++) {
        final runs = _runs(session.bytes);
        expect(runs.map((run) => run.text), ['Mixed', 'Text']);
        expect(
          runs.map((run) => run.properties.smallCaps),
          everyElement(isTrue),
        );
        expect(runs.first.properties.bold, isTrue);
        expect(runs.first.properties.color, '112233');
        expect(runs.last.properties.italic, isTrue);
        expect(runs.last.properties.fontSizeHalfPoints, 32);
        expect(_elements(_xml(session.bytes), 'caps').map(_val), ['0', '0']);
        expect(_elements(_xml(session.bytes), 'smallCaps').map(_val), [
          '1',
          '1',
        ]);
        final lang = _elements(_xml(session.bytes), 'lang').single;
        expect(
          lang.getAttribute('eastAsia', namespaceUri: OfficeNamespaces.w),
          'ja-JP',
        );
        await session.run(_compile('.Font.SmallCaps = True'));
      }
      await session.run(_compile('.Font.SmallCaps = False'));
      expect(
        _runs(session.bytes).map((run) => run.properties.smallCaps),
        everyElement(isFalse),
      );
      expect(_elements(_xml(session.bytes), 'caps').map(_val), ['0', '0']);
      expect(_elements(_xml(session.bytes), 'smallCaps').map(_val), ['0', '0']);
    },
  );

  test('SmallCaps=False retains an unrelated direct caps property', () async {
    final bytes = _fixture(
      '<w:r><w:rPr><w:caps/><w:smallCaps/></w:rPr><w:t>Keep</w:t></w:r>',
    );
    final session = OfficeMacroSession(bytes, format: OfficeMacroFormat.docx);
    await session.run(_compile('.Font.SmallCaps = False'));
    expect(_runs(session.bytes).single.properties.smallCaps, isFalse);
    expect(_elements(_xml(session.bytes), 'caps'), hasLength(1));
    expect(_val(_elements(_xml(session.bytes), 'caps').single), isNull);
  });

  test(
    'native authored SmallCaps retains earlier authored and pending fields',
    () {
      final props = WmlRunProps(
        bold: true,
        italic: true,
        color: '445566',
        fontSizeHalfPoints: 37,
      );
      final paragraph = WmlParagraph(
        inlines: [WmlRun(text: 'Authored', properties: props)],
      );
      final doc = WmlDocument(
        sections: [
          WmlSection(blocks: [paragraph]),
        ],
      );
      OfficeOperationCatalog.apply(doc, 'docx.runFormat', {
        'paragraph': 0,
        'smallCaps': true,
      });
      final run = paragraph.inlines.whereType<WmlRun>().single;
      expect(run.properties.smallCaps, isTrue);
      expect(run.properties.bold, isTrue);
      expect(run.properties.italic, isTrue);
      expect(run.properties.color, '445566');
      expect(run.properties.fontSizeHalfPoints, 37);
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(doc),
      );
      final reread = reopened.paragraphs.single.inlines
          .whereType<WmlRun>()
          .single
          .properties;
      expect(reread.smallCaps, isTrue);
      expect(reread.bold, isTrue);
      expect(reread.italic, isTrue);
      expect(reread.color, '445566');
      expect(reread.fontSizeHalfPoints, 37);
    },
  );

  test(
    'clearing inherited highlighting is explicit and survives repeated saves',
    () async {
      final session = OfficeMacroSession(
        _fixture(_mixedRuns, styles: _mixedStyles),
        format: OfficeMacroFormat.docx,
      );
      expect(_runs(session.bytes).first.properties.highlight, 'FFFF00');
      await session.run(_compile('.HighlightColorIndex = wdNoHighlight'));
      for (var save = 0; save < 2; save++) {
        expect(
          _runs(session.bytes).map((run) => run.properties.highlight),
          everyElement(isNull),
        );
        expect(_elements(_xml(session.bytes), 'highlight').map(_val), [
          'none',
          'none',
          'none',
        ]);
        await session.run(_compile('.Font.SmallCaps = False'));
      }
    },
  );

  for (final (name, xml) in <(String, String)>[
    ('wdBlack', 'black'),
    ('wdBlue', 'blue'),
    ('wdTurquoise', 'cyan'),
    ('wdBrightGreen', 'green'),
    ('wdPink', 'magenta'),
    ('wdRed', 'red'),
    ('wdYellow', 'yellow'),
    ('wdWhite', 'white'),
    ('wdDarkBlue', 'darkBlue'),
    ('wdTeal', 'darkCyan'),
    ('wdGreen', 'darkGreen'),
    ('wdViolet', 'darkMagenta'),
    ('wdDarkRed', 'darkRed'),
    ('wdDarkYellow', 'darkYellow'),
    ('wdGray50', 'darkGray'),
    ('wdGray25', 'lightGray'),
  ]) {
    test('$name writes native highlight token $xml', () async {
      final bytes = (DocxDocumentBuilder()..paragraph('Palette')).build();
      final session = OfficeMacroSession(bytes, format: OfficeMacroFormat.docx);
      await session.run(_compile('.HighlightColorIndex = $name'));
      expect(_elements(_xml(session.bytes), 'highlight').map(_val), [xml]);
    });
  }

  test(
    'malformed native arguments do not split or mutate the existing runs',
    () {
      final paragraph = WmlParagraph(inlines: [WmlRun(text: 'Original')]);
      final doc = WmlDocument(
        sections: [
          WmlSection(blocks: [paragraph]),
        ],
      );
      for (final fields in <Map<String, Object?>>[
        {'smallCaps': true, 'color': 'invalid'},
        {'superscript': true, 'subscript': false},
        {'smallCaps': 'True'},
      ]) {
        final before = paragraph.inlines.single;
        expect(
          () => OfficeOperationCatalog.apply(doc, 'docx.runFormat', {
            'paragraph': 0,
            'start': 1,
            'end': 4,
            ...fields,
          }),
          throwsArgumentError,
        );
        expect(paragraph.inlines, [same(before)]);
        final props = (before as WmlRun).properties;
        expect(props.smallCaps, isFalse);
        expect(props.vertAlign, WmlVertAlign.baseline);
        expect(props.sourcePropertiesXml, isNull);
      }
    },
  );

  test(
    'SmallCaps retains extension attributes named w without duplicate xmlns:w',
    () {
      const extensionNamespace = 'urn:word-typography-test';
      final props = WmlRunProps(bold: true)
        // Keep x:w before xmlns:w so a local-name-only setter would overwrite
        // the extension attribute rather than the actual namespace declaration.
        ..sourcePropertiesXml =
            '<w:rPr xmlns:x="$extensionNamespace" x:w="keep" '
            'xmlns:w="${OfficeNamespaces.w}"><w:b/></w:rPr>'
        ..importedValues = <String, String>{};
      final paragraph = WmlParagraph(
        inlines: [WmlRun(text: 'Namespace', properties: props)],
      );
      final doc = WmlDocument(
        sections: [
          WmlSection(blocks: [paragraph]),
        ],
      );
      OfficeOperationCatalog.apply(doc, 'docx.runFormat', {
        'paragraph': 0,
        'smallCaps': true,
      });
      final saved = WordSerializer().writeBytes(doc);
      final properties = _elements(_xml(saved), 'rPr').single;
      expect(
        properties.getAttribute('w', namespaceUri: extensionNamespace),
        'keep',
      );
      expect(
        properties.attributes.where(
          (attribute) => attribute.qualifiedName == 'xmlns:w',
        ),
        hasLength(1),
      );
      expect(_elements(properties, 'caps').map(_val), ['0']);
      final reopened = _runs(saved).single.properties;
      expect(reopened.smallCaps, isTrue);
      expect(reopened.bold, isTrue);
    },
  );

  for (final (field, mode) in <(String, WmlVertAlign)>[
    ('superscript', WmlVertAlign.superscript),
    ('subscript', WmlVertAlign.subscript),
  ]) {
    test('authored $field and highlight clears override inherited styles', () {
      final bytes = _fixture(
        '<w:r><w:rPr><w:rStyle w:val="Script"/></w:rPr>'
        '<w:t>Authored style</w:t></w:r>',
        styles:
            '<w:style w:type="character" w:styleId="Script"><w:rPr>'
            '<w:vertAlign w:val="${mode.name}"/><w:highlight w:val="yellow"/>'
            '</w:rPr></w:style>',
      );
      final doc = WordDeserializer().readBytes(bytes);
      final original = doc.paragraphs.single.inlines.whereType<WmlRun>().single;
      expect(original.properties.vertAlign, mode);
      expect(original.properties.highlight, 'FFFF00');
      // Keep the authored values and style reference, with no sparse import
      // provenance. The full serializer must retain the following clears.
      original.properties
        ..sourcePropertiesXml = null
        ..importedValues = null
        ..explicitProperties.clear();
      OfficeOperationCatalog.apply(doc, 'docx.runFormat', {
        'paragraph': 0,
        field: false,
        'highlight': null,
      });
      final updated = doc.paragraphs.single.inlines.whereType<WmlRun>().single;
      expect(updated.properties.vertAlign, WmlVertAlign.baseline);
      expect(updated.properties.highlight, isNull);
      var saved = WordSerializer().writeBytes(doc);
      for (var reopen = 0; reopen < 2; reopen++) {
        expect(_elements(_xml(saved), 'vertAlign').map(_val), ['baseline']);
        expect(_elements(_xml(saved), 'highlight').map(_val), ['none']);
        final restored = WordDeserializer().readBytes(saved);
        final run = restored.paragraphs.single.inlines
            .whereType<WmlRun>()
            .single;
        expect(run.text, 'Authored style');
        expect(run.properties.styleId, 'Script');
        expect(run.properties.vertAlign, WmlVertAlign.baseline);
        expect(run.properties.highlight, isNull);
        saved = WordSerializer().writeBytes(restored);
      }
    });
  }

  test(
    'property ownership accepts Word namespace aliases and internal w fragments',
    () {
      const extensionNamespace = 'urn:word-typography-test';
      for (final (prefix, declaration) in <(String, String)>[
        ('w', 'xmlns:w="${OfficeNamespaces.w}"'),
        ('a', 'xmlns:a="${OfficeNamespaces.w}"'),
        ('w', ''),
      ]) {
        final source =
            '<$prefix:rPr $declaration xmlns:x="$extensionNamespace">'
            '<x:smallCaps x:token="keep"/><$prefix:smallCaps $prefix:val="0"/>'
            '</$prefix:rPr>';
        final result = WordPropertyIo.preserve(
          WordPropertyIo.parse(
            '<w:rPr xmlns:w="${OfficeNamespaces.w}">'
                '<w:smallCaps w:val="1"/></w:rPr>',
            'rPr',
          ),
          source,
          {'smallCaps': 'false'},
          {'smallCaps': 'true'},
        );
        final children = result.childElements
            .where((element) => element.localName == 'smallCaps')
            .toList();
        expect(children, hasLength(2));
        expect(
          children
              .singleWhere(
                (element) => element.namespaceUri == extensionNamespace,
              )
              .getAttribute('token', namespaceUri: extensionNamespace),
          'keep',
        );
        expect(
          _val(
            children.singleWhere(
              (element) => element.namespaceUri == OfficeNamespaces.w,
            ),
          ),
          '1',
        );
      }
    },
  );

  test(
    'typography edits preserve foreign same-name properties across saves',
    () async {
      const extensionNamespace = 'urn:word-typography-test';
      const compatibilityNamespace =
          'http://schemas.openxmlformats.org/markup-compatibility/2006';
      final session = OfficeMacroSession(
        _fixture(
          '<w:r><w:rPr xmlns:x="$extensionNamespace" '
          'xmlns:mc="$compatibilityNamespace" mc:Ignorable="x">'
          '<x:smallCaps x:token="small"/><w:smallCaps w:val="0"/>'
          '<x:highlight x:token="color"/><w:highlight w:val="yellow"/>'
          '<x:vertAlign x:token="script"/><w:vertAlign w:val="superscript"/>'
          '</w:rPr><w:t>Owned properties</w:t></w:r>',
        ),
        format: OfficeMacroFormat.docx,
      );
      final plan = _compile('''
.Font.SmallCaps = True
.Font.Superscript = False
.HighlightColorIndex = wdNoHighlight
''');
      // Focus on source-property ownership: native edits must preserve foreign
      // payloads with the same local names through a later reopen and save.
      for (var repeat = 0; repeat < 2; repeat++) {
        await session.run(plan);
        final properties = _elements(_xml(session.bytes), 'rPr').single;
        expect(
          properties.childElements
              .where((element) => element.namespaceUri == extensionNamespace)
              .map(
                (element) => (
                  element.localName,
                  element.getAttribute(
                    'token',
                    namespaceUri: extensionNamespace,
                  ),
                ),
              ),
          unorderedEquals(<(String, String?)>[
            ('smallCaps', 'small'),
            ('highlight', 'color'),
            ('vertAlign', 'script'),
          ]),
        );
        expect(
          properties.getAttribute(
            'Ignorable',
            namespaceUri: compatibilityNamespace,
          ),
          'x',
        );
        expect(_elements(properties, 'smallCaps'), hasLength(1));
        expect(_elements(properties, 'vertAlign').map(_val), ['baseline']);
        expect(_elements(properties, 'highlight').map(_val), ['none']);
        final run = _runs(session.bytes).single;
        expect(run.text, 'Owned properties');
        expect(run.properties.smallCaps, isTrue);
        expect(run.properties.vertAlign, WmlVertAlign.baseline);
        expect(run.properties.highlight, isNull);
      }
    },
  );

  test(
    'typography changes roll back when a later explicit paragraph is absent',
    () async {
      final bytes = _fixture(_mixedRuns, styles: _mixedStyles);
      final session = OfficeMacroSession(bytes, format: OfficeMacroFormat.docx);
      final plan = _compile('''
.Font.SmallCaps = True
.Font.Subscript = True
.HighlightColorIndex = wdRed
ActiveDocument.Paragraphs.Item(9).Range.Font.SmallCaps = False
''');
      await expectLater(
        session.validate(plan),
        throwsA(isA<OfficeMacroException>()),
      );
      await expectLater(
        session.run(plan),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(session.bytes, bytes);
      expect(session.revision, 0);
    },
  );
}
