import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/serial/word_property_io.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String body) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    source: 'Sub Main()\n$body\nEnd Sub',
  ),
);
Uint8List _fixture(
  String properties, {
  String styles = '',
  String text = 'Original',
}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}" xmlns:x="urn:layout-test">'
        '<w:body><w:p><w:pPr>$properties</w:pPr>'
        '<w:r><w:rPr><w:i/></w:rPr><w:t>$text</w:t></w:r>'
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

XmlElement _properties(Uint8List bytes) =>
    XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!
        .firstChild('body', namespaceUri: OfficeNamespaces.w)!
        .firstChild('p', namespaceUri: OfficeNamespaces.w)!
        .firstChild('pPr', namespaceUri: OfficeNamespaces.w)!;
XmlElement _spacing(Uint8List bytes) =>
    _properties(bytes).firstChild('spacing', namespaceUri: OfficeNamespaces.w)!;
String? _w(XmlElement node, String name) =>
    node.getAttribute(name, namespaceUri: OfficeNamespaces.w);
const _style =
    '<w:style w:type="paragraph" w:styleId="Layout"><w:pPr>'
    '<w:spacing w:before="180" w:after="240" w:line="480" w:lineRule="auto"/>'
    '<w:bidi/><w:jc w:val="center"/></w:pPr></w:style>';

void main() {
  test('nested Word layout lookalikes inside an extension stay opaque', () async {
    final session = OfficeMacroSession(
      _fixture(
        '<w:spacing w:line="480" w:lineRule="auto"/><w:bidi/>'
        '<x:metadata x:token="keep"><w:spacing w:line="960" w:lineRule="auto"/>'
        '<w:bidi w:val="1"/></x:metadata>',
      ),
      format: OfficeMacroFormat.docx,
    );
    await session.run(
      _compile('''
ActiveDocument.Paragraphs(1).Format.LineSpacingRule = wdLineSpaceSingle
ActiveDocument.Paragraphs(1).Format.ReadingOrder = wdReadingOrderLtr
'''),
    );
    final doc = WordDeserializer().readBytes(session.bytes);
    expect(doc.paragraphs.single.properties.lineSpacing, 1);
    expect(doc.paragraphs.single.properties.rightToLeft, isFalse);
    final metadata = _properties(
      session.bytes,
    ).firstChild('metadata', namespaceUri: 'urn:layout-test')!;
    expect(
      _w(
        metadata.firstChild('spacing', namespaceUri: OfficeNamespaces.w)!,
        'line',
      ),
      '960',
    );
    expect(
      _w(metadata.firstChild('bidi', namespaceUri: OfficeNamespaces.w)!, 'val'),
      '1',
    );
  });

  test(
    'foreign paragraph lookalikes cannot override native layout on reopen',
    () async {
      final session = OfficeMacroSession(
        _fixture(
          '<w:spacing w:line="480" w:lineRule="auto"/>'
          '<x:spacing w:line="960" w:lineRule="auto" x:token="spacing"/>'
          '<w:bidi w:val="1"/><x:bidi w:val="1" x:token="direction"/>',
        ),
        format: OfficeMacroFormat.docx,
      );
      await session.run(
        _compile('''
With ActiveDocument.Paragraphs(1).Format
  .LineSpacingRule = wdLineSpaceSingle
  .ReadingOrder = wdReadingOrderLtr
End With
'''),
      );
      var saved = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        final source = _properties(saved);
        expect(
          source
              .firstChild('spacing', namespaceUri: 'urn:layout-test')!
              .getAttribute('token', namespaceUri: 'urn:layout-test'),
          'spacing',
        );
        expect(
          source
              .firstChild('bidi', namespaceUri: 'urn:layout-test')!
              .getAttribute('token', namespaceUri: 'urn:layout-test'),
          'direction',
        );
        final doc = WordDeserializer().readBytes(saved);
        expect(doc.paragraphs.single.properties.lineSpacing, 1);
        expect(doc.paragraphs.single.properties.rightToLeft, isFalse);
        saved = WordSerializer().writeBytes(doc);
      }
    },
  );
  for (final (constant, multiple, nativeLine) in [
    ('wdLineSpaceSingle', 1.0, '240'),
    ('wdLineSpace1pt5', 1.5, '360'),
    ('wdLineSpaceDouble', 2.0, '480'),
  ]) {
    test(
      '$constant replaces exact spacing and preserves all other source groups',
      () async {
        final bytes = _fixture(
          '<w:spacing w:before="120" w:after="180" '
          'w:beforeLines="10" w:afterLines="20" w:beforeAutospacing="1" '
          'w:afterAutospacing="0" w:line="300" w:lineRule="exact" '
          'x:line="keep-line" x:before="keep-before" x:token="keep"/>'
          '<w:jc w:val="right"/><w:keepNext/>',
        );
        final session = OfficeMacroSession(
          bytes,
          format: OfficeMacroFormat.docx,
        );
        final plan = _compile(
          'ActiveDocument.Paragraphs(1).Format.LineSpacingRule = $constant',
        );
        await session.validate(plan);
        expect(session.bytes, bytes);
        expect(session.revision, 0);
        await session.run(plan);
        expect(session.revision, 1);
        var saved = session.bytes;
        for (var cycle = 0; cycle < 3; cycle++) {
          final spacing = _spacing(saved);
          expect(_w(spacing, 'line'), nativeLine);
          expect(_w(spacing, 'lineRule'), 'auto');
          expect(_w(spacing, 'before'), '120');
          expect(_w(spacing, 'after'), '180');
          expect(_w(spacing, 'beforeLines'), '10');
          expect(_w(spacing, 'afterLines'), '20');
          expect(_w(spacing, 'beforeAutospacing'), '1');
          expect(_w(spacing, 'afterAutospacing'), '0');
          expect(
            spacing.getAttribute('line', namespaceUri: 'urn:layout-test'),
            'keep-line',
          );
          expect(
            spacing.getAttribute('before', namespaceUri: 'urn:layout-test'),
            'keep-before',
          );
          expect(
            spacing.getAttribute('token', namespaceUri: 'urn:layout-test'),
            'keep',
          );
          expect(
            _properties(
              saved,
            ).firstChild('keepNext', namespaceUri: OfficeNamespaces.w),
            isNotNull,
          );
          final doc = WordDeserializer().readBytes(saved);
          final paragraph = doc.paragraphs.single;
          expect(paragraph.text, 'Original');
          expect(paragraph.properties.lineSpacing, multiple);
          expect(paragraph.properties.lineSpacingRule, WmlLineSpacingRule.auto);
          expect(paragraph.properties.justification, WmlJustification.right);
          expect(
            paragraph.inlines.whereType<WmlRun>().single.properties.italic,
            isTrue,
          );
          saved = WordSerializer().writeBytes(doc);
        }
      },
    );
  }

  test(
    'same-value inherited preset is explicit without freezing inherited spacing',
    () async {
      final session = OfficeMacroSession(
        _fixture('<w:pStyle w:val="Layout"/>', styles: _style),
        format: OfficeMacroFormat.docx,
      );
      await session.run(
        _compile(
          'ActiveDocument.Paragraphs(1).Format.LineSpacingRule = wdLineSpaceDouble',
        ),
      );
      final spacing = _spacing(session.bytes);
      expect(_w(spacing, 'line'), '480');
      expect(_w(spacing, 'lineRule'), 'auto');
      expect(_w(spacing, 'before'), isNull);
      expect(_w(spacing, 'after'), isNull);
      final package = OpcPackage.openBytes(session.bytes);
      final styles = package.getPart('/word/styles.xml')!;
      styles.writeText(
        styles
            .readText()
            .replaceAll('w:before="180"', 'w:before="400"')
            .replaceAll('w:after="240"', 'w:after="600"')
            .replaceAll('w:line="480"', 'w:line="240"'),
      );
      final restored = WordDeserializer().read(package);
      final properties = restored.paragraphs.single.properties;
      expect(properties.lineSpacing, 2);
      expect(properties.spacingBefore, 20);
      expect(properties.spacingAfter, 30);
      final again = _spacing(WordSerializer().writeBytes(restored));
      expect(_w(again, 'before'), isNull);
      expect(_w(again, 'after'), isNull);
    },
  );

  for (final (constant, value) in [
    ('wdReadingOrderRtl', true),
    ('wdReadingOrderLtr', false),
  ]) {
    test('$constant preserves alignment and bidi extension metadata', () async {
      final session = OfficeMacroSession(
        _fixture(
          '<w:bidi w:val="${value ? 0 : 1}" x:val="foreign" x:token="keep"/>'
          '<w:jc w:val="center"/>',
        ),
        format: OfficeMacroFormat.docx,
      );
      await session.run(
        _compile(
          'ActiveDocument.Paragraphs(1).Format.ReadingOrder = $constant',
        ),
      );
      var saved = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        final bidi = _properties(
          saved,
        ).firstChild('bidi', namespaceUri: OfficeNamespaces.w)!;
        expect(_w(bidi, 'val'), value ? '1' : '0');
        expect(
          bidi.getAttribute('val', namespaceUri: 'urn:layout-test'),
          'foreign',
        );
        expect(
          bidi.getAttribute('token', namespaceUri: 'urn:layout-test'),
          'keep',
        );
        final doc = WordDeserializer().readBytes(saved);
        expect(doc.paragraphs.single.properties.rightToLeft, value);
        expect(
          doc.paragraphs.single.properties.justification,
          WmlJustification.center,
        );
        saved = WordSerializer().writeBytes(doc);
      }
    });
  }

  test(
    'LTR overrides inherited RTL without changing inherited centered alignment',
    () async {
      final session = OfficeMacroSession(
        _fixture('<w:pStyle w:val="Layout"/>', styles: _style),
        format: OfficeMacroFormat.docx,
      );
      await session.run(
        _compile(
          'ActiveDocument.Paragraphs(1).Format.ReadingOrder = wdReadingOrderLtr',
        ),
      );
      var saved = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        final props = _properties(saved);
        expect(
          _w(
            props.firstChild('bidi', namespaceUri: OfficeNamespaces.w)!,
            'val',
          ),
          '0',
        );
        expect(
          props.firstChild('jc', namespaceUri: OfficeNamespaces.w),
          isNull,
        );
        final doc = WordDeserializer().readBytes(saved);
        expect(doc.paragraphs.single.properties.rightToLeft, isFalse);
        expect(
          doc.paragraphs.single.properties.justification,
          WmlJustification.center,
        );
        saved = WordSerializer().writeBytes(doc);
      }
    },
  );

  test('all same-value native spacing assignments retain direct intent', () {
    final doc = WordDeserializer().readBytes(
      _fixture('<w:pStyle w:val="Layout"/>', styles: _style),
    );
    OfficeOperationCatalog.apply(doc, 'docx.paragraphFormat', {
      'paragraph': 0,
      'before': 9,
      'after': 12,
      'lineSpacing': 2,
      'lineSpacingRule': 'auto',
    });
    final spacing = _spacing(WordSerializer().writeBytes(doc));
    expect(_w(spacing, 'before'), '180');
    expect(_w(spacing, 'after'), '240');
    expect(_w(spacing, 'line'), '480');
    expect(_w(spacing, 'lineRule'), 'auto');
  });

  for (final (property, native, opposite) in [
    ('SpaceBefore', 'before', 'after'),
    ('SpaceAfter', 'after', 'before'),
  ]) {
    test(
      '$property changes only its spacing group and preserves a prior preset',
      () async {
        final session = OfficeMacroSession(
          _fixture(
            '<w:spacing w:before="120" w:after="180" w:line="480" w:lineRule="auto" '
            'w:beforeLines="10" w:afterLines="20" w:beforeAutospacing="1" '
            'w:afterAutospacing="1" x:token="keep"/>',
          ),
          format: OfficeMacroFormat.docx,
        );
        await session.run(
          _compile('''
With ActiveDocument.Paragraphs(1).Format
  .LineSpacingRule = wdLineSpace1pt5
  .$property = 7.5
End With
'''),
        );
        final spacing = _spacing(session.bytes);
        expect(_w(spacing, native), '150');
        expect(_w(spacing, '${native}Lines'), isNull);
        expect(_w(spacing, '${native}Autospacing'), isNull);
        expect(_w(spacing, opposite), opposite == 'before' ? '120' : '180');
        expect(
          _w(spacing, '${opposite}Lines'),
          opposite == 'before' ? '10' : '20',
        );
        expect(_w(spacing, '${opposite}Autospacing'), '1');
        expect(_w(spacing, 'line'), '360');
        expect(_w(spacing, 'lineRule'), 'auto');
        expect(
          spacing.getAttribute('token', namespaceUri: 'urn:layout-test'),
          'keep',
        );
      },
    );
  }

  test('ordinary direct model line edits use granular ownership too', () {
    final doc = WordDeserializer().readBytes(
      _fixture(
        '<w:pStyle w:val="Layout"/><w:spacing x:token="keep"/>',
        styles: _style,
      ),
    );
    doc.paragraphs.single.properties.lineSpacing = 1.5;
    final spacing = _spacing(WordSerializer().writeBytes(doc));
    expect(_w(spacing, 'line'), '360');
    expect(_w(spacing, 'lineRule'), 'auto');
    expect(_w(spacing, 'before'), isNull);
    expect(_w(spacing, 'after'), isNull);
    expect(
      spacing.getAttribute('token', namespaceUri: 'urn:layout-test'),
      'keep',
    );
  });

  test(
    'spacing patch handles alternate/default namespaces and a conflicting w prefix',
    () {
      const extension = 'urn:foreign-w';
      final original = WmlParagraphProps(lineSpacing: 2);
      final imported = WordPropertyIo.paragraphValues(original)
        ..remove('spacing:line');
      final current = WordPropertyIo.paragraphValues(
        original..lineSpacing = 1.5,
      );
      for (final (prefix, declaration) in [
        ('a:', 'xmlns:a="${OfficeNamespaces.w}"'),
        ('', 'xmlns="${OfficeNamespaces.w}"'),
      ]) {
        final result = WordPropertyIo.preserve(
          WordPropertyIo.parse(
            '<w:pPr xmlns:w="${OfficeNamespaces.w}">'
                '<w:spacing w:before="0" w:after="160" w:line="360" w:lineRule="auto"/></w:pPr>',
            'pPr',
          ),
          '<${prefix}pPr $declaration xmlns:w="$extension">'
          '<${prefix}spacing xmlns:n="${OfficeNamespaces.w}" n:line="480" '
          'n:lineRule="auto" n:before="240" w:line="foreign" w:w="keep"/>'
          '</${prefix}pPr>',
          imported,
          current,
        );
        final xml = XmlDocument(root: result).toXmlString(declaration: false);
        final parsed = XmlDocument.parse(xml).root!;
        final spacing = parsed.firstChild(
          'spacing',
          namespaceUri: OfficeNamespaces.w,
        )!;
        expect(_w(spacing, 'line'), '360');
        expect(_w(spacing, 'lineRule'), 'auto');
        expect(_w(spacing, 'before'), '240');
        expect(_w(spacing, 'after'), isNull);
        expect(
          spacing.getAttribute('line', namespaceUri: extension),
          'foreign',
        );
        expect(spacing.getAttribute('w', namespaceUri: extension), 'keep');
        expect(
          spacing.attributes.where(
            (a) =>
                a.localName == 'line' && a.namespaceUri == OfficeNamespaces.w,
          ),
          hasLength(1),
        );
      }
    },
  );

  test('legacy aggregate snapshots retain explicit full spacing changes', () {
    final before = WmlParagraphProps(lineSpacing: 2);
    final imported = WordPropertyIo.paragraphValues(before)
      ..removeWhere((key, _) => key.startsWith('spacing:'));
    before.lineSpacing = 1;
    final result = WordPropertyIo.preserve(
      WordPropertyIo.parse(
        '<w:pPr><w:spacing w:before="0" w:after="160" '
            'w:line="240" w:lineRule="auto"/></w:pPr>',
        'pPr',
      ),
      '<w:pPr xmlns:w="${OfficeNamespaces.w}"><w:spacing w:line="480" '
      'w:lineRule="auto"/></w:pPr>',
      imported,
      WordPropertyIo.paragraphValues(before),
    );
    final spacing = result.firstChild(
      'spacing',
      namespaceUri: OfficeNamespaces.w,
    )!;
    expect(_w(spacing, 'line'), '240');
    expect(_w(spacing, 'before'), '0');
    expect(_w(spacing, 'after'), '160');
  });

  test(
    'late target failure rolls back layout and typed font changes and recording',
    () async {
      final bytes = _fixture('');
      final session = OfficeMacroSession(bytes, format: OfficeMacroFormat.docx);
      session.startRecording('Rejected layout');
      final plan = _compile('''
Dim face As Font
Dim layout As ParagraphFormat
Set face = ActiveDocument.Paragraphs(1).Range.Font
Set layout = ActiveDocument.Paragraphs(1).Format
face.Bold = True
layout.ReadingOrder = wdReadingOrderRtl
layout.LineSpacingRule = wdLineSpaceDouble
ActiveDocument.Paragraphs(99).Format.LineSpacingRule = wdLineSpaceSingle
''');
      final failure = isA<OfficeMacroException>().having(
        (e) => e.stepIndex,
        'step',
        3,
      );
      await expectLater(session.validate(plan), throwsA(failure));
      await expectLater(session.run(plan), throwsA(failure));
      expect(session.bytes, bytes);
      expect(session.revision, 0);
      expect(session.stopRecording().steps, isEmpty);
    },
  );

  test(
    'paragraph layout supports empty paragraphs without writing visible text',
    () async {
      final session = OfficeMacroSession(
        _fixture('', text: ''),
        format: OfficeMacroFormat.docx,
      );
      await session.run(
        _compile('''
Dim layout As ParagraphFormat
Set layout = ActiveDocument.Paragraphs(1).Format
layout.LineSpacingRule = wdLineSpace1pt5
layout.ReadingOrder = wdReadingOrderRtl
'''),
      );
      final paragraph = WordDeserializer()
          .readBytes(session.bytes)
          .paragraphs
          .single;
      expect(paragraph.text, isEmpty);
      expect(paragraph.properties.lineSpacing, 1.5);
      expect(paragraph.properties.rightToLeft, isTrue);
    },
  );
}
