import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:list-edit-test';

Uint8List _fixture({
  String properties = '',
  String? numbering,
  String? styles,
  String? body,
}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w" xmlns:x="$_x" xmlns:mc="${OfficeNamespaces.mc}">'
        '<w:body>${body ?? '<w:p><w:pPr>$properties</w:pPr><w:r><w:t>Original</w:t></w:r></w:p>'}'
        '<w:sectPr/></w:body></w:document>',
      );
  if (numbering != null) {
    final xml =
        '<w:numbering xmlns:w="$_w" xmlns:x="$_x">$numbering</w:numbering>';
    final part = package.getPart('/word/numbering.xml');
    if (part == null) {
      package.createPart(
        '/word/numbering.xml',
        OfficeContentTypes.wordNumbering,
        utf8.encode(xml),
      );
    } else {
      part.writeText(xml);
    }
    final rels = package.relationshipsFor('/word/document.xml');
    if (rels.firstByType(RelationshipTypes.numbering) == null) {
      rels.add(type: RelationshipTypes.numbering, target: 'numbering.xml');
    }
  }
  if (styles != null) {
    package
        .getPart('/word/styles.xml')!
        .writeText('<w:styles xmlns:w="$_w" xmlns:x="$_x">$styles</w:styles>');
  }
  return package.save();
}

String _definition({
  String format = 'decimal',
  String text = '%1.',
  String extra = '',
  String override = '',
}) =>
    '<w:abstractNum w:abstractNumId="42"><w:multiLevelType w:val="singleLevel"/>$extra'
    '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="$format"/>'
    '<w:lvlText w:val="$text"/></w:lvl></w:abstractNum>'
    '<w:num w:numId="71"><w:abstractNumId w:val="42"/>$override</w:num>';
const _list = '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="71"/></w:numPr>';

OfficeMacroStep _default(bool numbered, {int paragraph = 0}) => OfficeMacroStep(
  tool: 'docx.listDefault',
  arguments: {'paragraph': paragraph, 'numbered': numbered},
);
OfficeMacroStep _remove({String type = 'all'}) => OfficeMacroStep(
  tool: 'docx.removeNumbers',
  arguments: {'paragraph': 0, 'numberType': type},
);
OfficeMacro _plan(List<OfficeMacroStep> steps) => OfficeMacro(
  name: 'List formatting',
  format: OfficeMacroFormat.docx,
  steps: steps,
);
WmlDocument _read(Uint8List bytes) => WordDeserializer().readBytes(bytes);
XmlElement _properties(Uint8List bytes) =>
    XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!
        .firstChild('body', namespaceUri: _w)!
        .firstChild('p', namespaceUri: _w)!
        .firstChild('pPr', namespaceUri: _w)!;
String? _val(XmlElement? node, String name) =>
    node?.getAttribute(name, namespaceUri: _w);

List<String> _fieldTokens(Uint8List bytes) {
  final tokens = <String>[];
  void visit(XmlElement node) {
    if (node.namespaceUri == _w) {
      if (node.localName == 'fldChar') {
        tokens.add(
          'boundary:${node.getAttribute('fldCharType', namespaceUri: _w)}',
        );
      } else if (node.localName == 'instrText') {
        tokens.add('instruction:${node.text}');
      }
    }
    for (final child in node.childElements) {
      visit(child);
    }
  }

  visit(
    XmlDocument.parse(
      OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
    ).root!,
  );
  return tokens;
}

void main() {
  for (final numbered in [false, true]) {
    test(
      'default ${numbered ? 'number' : 'bullet'} applies and toggles off across save/reopen',
      () async {
        final session = OfficeMacroSession(
          _fixture(),
          format: OfficeMacroFormat.docx,
        );
        await session.run(_plan([_default(numbered)]));
        var bytes = session.bytes;
        for (var cycle = 0; cycle < 3; cycle++) {
          final doc = _read(bytes);
          final p = doc.paragraphs.single;
          expect(p.text, 'Original');
          expect(p.properties.numId, isNotNull);
          expect(p.properties.ilvl, 0);
          expect(p.properties.listLabel, numbered ? '1. ' : '• ');
          expect(p.properties.indent.left, 18);
          expect(p.properties.indent.hanging, 9);
          bytes = WordSerializer().writeBytes(doc);
        }
        final toggled = OfficeMacroSession(
          bytes,
          format: OfficeMacroFormat.docx,
        );
        await toggled.run(_plan([_default(numbered)]));
        final off = _read(toggled.bytes).paragraphs.single.properties;
        expect(off.numId, isNull);
        expect(off.numberingSuppressed, isTrue);
        expect(off.indent.left, 18);
        expect(off.indent.hanging, 9);
        expect(
          _val(
            _properties(toggled.bytes).firstChild('numPr')!.firstChild('numId'),
            'val',
          ),
          '0',
        );
      },
    );
  }

  test(
    'separate default-number calls share one definition and continue counters',
    () async {
      final session = OfficeMacroSession(
        _fixture(
          body:
              '<w:p><w:r><w:t>First</w:t></w:r></w:p><w:p><w:r><w:t>Second</w:t></w:r></w:p>',
        ),
        format: OfficeMacroFormat.docx,
      );
      await session.run(_plan([_default(true), _default(true, paragraph: 1)]));
      final paras = _read(session.bytes).paragraphs.toList();
      expect(paras.map((p) => p.properties.listLabel), ['1. ', '2. ']);
      expect(paras.map((p) => p.properties.numId).toSet(), hasLength(1));
    },
  );

  test(
    'applying the other kind does not overwrite imported definitions',
    () async {
      final input = _fixture(
        properties: _list,
        numbering: _definition(format: 'upperRoman'),
      );
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(_plan([_default(false)]));
      final p = _read(session.bytes).paragraphs.single.properties;
      expect(p.numId, isNot(71));
      expect(p.listLabel, '• ');
      final xml = OpcPackage.openBytes(
        session.bytes,
      ).getPart('/word/numbering.xml')!.readText();
      expect(xml, contains('w:numId="71"'));
      expect(xml, contains('w:abstractNumId="42"'));
      expect(xml, contains('w:val="upperRoman"'));
    },
  );

  for (final format in [
    'decimal',
    'decimalZero',
    'upperRoman',
    'lowerRoman',
    'upperLetter',
    'lowerLetter',
  ]) {
    test(
      'number toggle classifies native $format independently of labels and IDs',
      () async {
        final session = OfficeMacroSession(
          _fixture(
            properties: _list,
            numbering: _definition(format: format),
          ),
          format: OfficeMacroFormat.docx,
        );
        await session.run(_plan([_default(true)]));
        expect(_read(session.bytes).paragraphs.single.properties.numId, isNull);
      },
    );
  }

  test('bullet toggle honors selected instance level override', () async {
    final numbering = _definition(
      override:
          '<w:lvlOverride w:ilvl="0"><w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/><w:lvlText w:val="☞"/></w:lvl></w:lvlOverride>',
    );
    final session = OfficeMacroSession(
      _fixture(properties: _list, numbering: numbering),
      format: OfficeMacroFormat.docx,
    );
    await session.run(_plan([_default(false)]));
    expect(_read(session.bytes).paragraphs.single.properties.numId, isNull);
  });

  for (final step in [_default(true), _remove()]) {
    test(
      '${step.tool} suppresses inherited numbering through repeated reopens and style refresh',
      () async {
        const styles =
            '<w:style w:type="paragraph" w:styleId="Base"><w:pPr>$_list</w:pPr></w:style><w:style w:type="paragraph" w:styleId="Derived"><w:basedOn w:val="Base"/></w:style>';
        final input = _fixture(
          properties: '<w:pStyle w:val="Derived"/>',
          numbering: _definition(),
          styles: styles,
        );
        expect(_read(input).paragraphs.single.properties.numId, 71);
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        await session.run(_plan([step]));
        var bytes = session.bytes;
        for (var cycle = 0; cycle < 3; cycle++) {
          final doc = _read(bytes);
          WordDeserializer().refreshStyles(doc);
          expect(doc.paragraphs.single.properties.numId, isNull);
          expect(doc.paragraphs.single.properties.numberingSuppressed, isTrue);
          bytes = WordSerializer().writeBytes(doc);
        }
      },
    );
  }

  test(
    'sparse edits preserve right indentation, numPr extensions and unrelated formatting',
    () async {
      final input = _fixture(
        properties:
            '<w:numPr x:keep="container"><w:ilvl w:val="0" x:keep="level"/><w:numId w:val="71" x:val="foreign"><x:child/></w:numId><x:extra/></w:numPr><w:ind w:left="1440" w:right="240" w:firstLine="120" x:keep="indent"/><w:keepNext/><w:spacing w:before="60"/><w:tabs><w:tab w:pos="720" w:val="right"/></w:tabs>',
        numbering: _definition(),
      );
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(_plan([_default(false)]));
      var bytes = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        final pp = _properties(bytes);
        final np = pp.firstChild('numPr', namespaceUri: _w)!;
        final id = np.firstChild('numId', namespaceUri: _w)!;
        expect(np.getAttribute('keep', namespaceUri: _x), 'container');
        expect(id.getAttribute('val', namespaceUri: _x), 'foreign');
        expect(id.firstChild('child', namespaceUri: _x), isNotNull);
        expect(np.firstChild('extra', namespaceUri: _x), isNotNull);
        expect(_val(pp.firstChild('ind', namespaceUri: _w), 'right'), '240');
        expect(
          pp
              .firstChild('ind', namespaceUri: _w)!
              .getAttribute('keep', namespaceUri: _x),
          'indent',
        );
        expect(pp.firstChild('keepNext', namespaceUri: _w), isNotNull);
        expect(
          _val(pp.firstChild('spacing', namespaceUri: _w), 'before'),
          '60',
        );
        expect(pp.firstChild('tabs', namespaceUri: _w), isNotNull);
        bytes = WordSerializer().writeBytes(_read(bytes));
      }
    },
  );

  test(
    'default writes preserve inherited right indentation as inherited',
    () async {
      final session = OfficeMacroSession(
        _fixture(
          properties: '<w:pStyle w:val="P"/>',
          styles:
              '<w:style w:type="paragraph" w:styleId="P"><w:pPr><w:ind w:right="240"/></w:pPr></w:style>',
        ),
        format: OfficeMacroFormat.docx,
      );
      await session.run(_plan([_default(true)]));
      final indent = _properties(
        session.bytes,
      ).firstChild('ind', namespaceUri: _w)!;
      expect(_val(indent, 'right'), isNull);
      expect(
        _read(session.bytes).paragraphs.single.properties.indent.right,
        12,
      );
    },
  );

  for (final foreignWordPrefix in [false, true]) {
    for (final (label, step) in [
      ('apply bullets', _default(false)),
      ('toggle numbers', _default(true)),
      ('remove numbers', _remove(type: 'paragraph')),
    ]) {
      test(
        '$label preserves foreign namespace metadata with '
        '${foreignWordPrefix ? 'a rebound w prefix' : 'w-named attributes'}',
        () async {
          const extension = 'urn:word-list-prefix-extension';
          final prefix = foreignWordPrefix ? 'q' : 'w';
          final collision = foreignWordPrefix ? 'w1' : 'w';
          final properties =
              '<$prefix:pPr x:$collision="root" xmlns:x="$_x" '
              'xmlns:$prefix="$_w" '
              '${foreignWordPrefix ? 'xmlns:w="$extension" w:keep="root-extension"' : ''}>'
              '<$prefix:numPr x:$collision="numbering">'
              '<$prefix:ilvl $prefix:val="0" x:$collision="level"/>'
              '<$prefix:numId $prefix:val="71" x:$collision="number"/>'
              '</$prefix:numPr>'
              '<$prefix:ind $prefix:left="1440" $prefix:right="240" '
              'x:$collision="indent"/>'
              '${foreignWordPrefix ? '<w:opaque w:keep="child-extension"/>' : ''}'
              '</$prefix:pPr>';
          final session = OfficeMacroSession(
            _fixture(
              body: '<w:p>$properties<w:r><w:t>Original</w:t></w:r></w:p>',
              numbering: _definition(),
            ),
            format: OfficeMacroFormat.docx,
          );
          await session.run(_plan([step]));
          var bytes = session.bytes;
          for (var cycle = 0; cycle < 3; cycle++) {
            final pp = _properties(bytes);
            expect(
              pp.getAttribute(collision, namespaceUri: _x),
              'root',
              reason: 'Foreign metadata after save/reopen cycle $cycle',
            );
            final number = pp.firstChild('numPr', namespaceUri: _w)!;
            expect(
              number.getAttribute(collision, namespaceUri: _x),
              'numbering',
            );
            for (final (name, expected) in [
              ('ilvl', 'level'),
              ('numId', 'number'),
            ]) {
              expect(
                number
                    .firstChild(name, namespaceUri: _w)!
                    .getAttribute(collision, namespaceUri: _x),
                expected,
              );
            }
            final indent = pp.firstChild('ind', namespaceUri: _w)!;
            expect(indent.getAttribute(collision, namespaceUri: _x), 'indent');
            expect(indent.getAttribute('right', namespaceUri: _w), '240');
            if (foreignWordPrefix) {
              expect(
                pp.getAttribute('keep', namespaceUri: extension),
                'root-extension',
              );
              expect(pp.getAttribute('keep', namespaceUri: _w), isNull);
              expect(
                pp
                    .firstChild('opaque', namespaceUri: extension)!
                    .getAttribute('keep', namespaceUri: extension),
                'child-extension',
              );
            }
            final reopened = _read(bytes);
            expect(reopened.paragraphs.single.text, 'Original');
            final formatted = reopened.paragraphs.single.properties;
            if (label == 'apply bullets') {
              expect(formatted.numId, isNotNull);
              expect(formatted.listLabel, '• ');
            } else {
              expect(formatted.numId, isNull);
              expect(formatted.numberingSuppressed, isTrue);
            }
            bytes = WordSerializer().writeBytes(reopened);
          }
        },
      );
    }
  }

  final rejected = <String, ({String properties, String numbering})>{
    'missing number ID': (
      properties: '<w:numPr><w:ilvl w:val="0"/></w:numPr>',
      numbering: _definition(),
    ),
    'duplicate numPr': (properties: '$_list$_list', numbering: _definition()),
    'duplicate numId': (
      properties:
          '<w:numPr><w:numId w:val="71"/><w:numId w:val="72"/></w:numPr>',
      numbering: _definition(),
    ),
    'noninteger numId': (
      properties: '<w:numPr><w:numId w:val="71.5"/></w:numPr>',
      numbering: _definition(),
    ),
    'invalid level': (
      properties: '<w:numPr><w:numId w:val="71"/><w:ilvl w:val="9"/></w:numPr>',
      numbering: _definition(),
    ),
    'tracked numbering': (
      properties:
          '<w:numPr><w:numId w:val="71"/><w:numberingChange/></w:numPr>',
      numbering: _definition(),
    ),
    'missing instance': (properties: _list, numbering: ''),
    'duplicate abstract ID': (
      properties: _list,
      numbering: '${_definition()}<w:abstractNum w:abstractNumId="42"/>',
    ),
    'duplicate instance ID': (
      properties: _list,
      numbering:
          '${_definition()}<w:num w:numId="71"><w:abstractNumId w:val="42"/></w:num>',
    ),
    'linked definition': (
      properties: _list,
      numbering: _definition(extra: '<w:numStyleLink w:val="P"/>'),
    ),
    'unknown format': (
      properties: _list,
      numbering: _definition(format: 'unknown'),
    ),
    'hidden number format': (
      properties: _list,
      numbering: _definition(format: 'none'),
    ),
    'outline number text': (
      properties: _list,
      numbering: _definition(text: '%1.%2'),
    ),
    'duplicate override': (
      properties: _list,
      numbering: _definition(
        override: '<w:lvlOverride w:ilvl="0"/><w:lvlOverride w:ilvl="0"/>',
      ),
    ),
    'mismatched override level': (
      properties: _list,
      numbering: _definition(
        override:
            '<w:lvlOverride w:ilvl="0"><w:lvl w:ilvl="1"><w:numFmt w:val="bullet"/></w:lvl></w:lvlOverride>',
      ),
    ),
  };
  for (final entry in rejected.entries) {
    test(
      '${entry.key} refuses before direct paragraph or package mutation',
      () {
        final doc = _read(
          _fixture(
            properties: entry.value.properties,
            numbering: entry.value.numbering,
          ),
        );
        final originalProperties = doc.paragraphs.single.properties;
        final originalSource = originalProperties.sourcePropertiesXml;
        final originalParts = {
          for (final part in doc.package!.parts)
            part.uri: Uint8List.fromList(part.readBytes()),
        };
        expect(
          () => native.applyStep(doc, {
            'op': 'listDefault',
            'paragraph': 0,
            'numbered': false,
          }),
          throwsUnsupportedError,
        );
        expect(
          identical(doc.paragraphs.single.properties, originalProperties),
          isTrue,
        );
        expect(
          doc.paragraphs.single.properties.sourcePropertiesXml,
          originalSource,
        );
        expect({
          for (final part in doc.package!.parts) part.uri: part.readBytes(),
        }, originalParts);
      },
    );
  }

  test(
    'remove paragraph does not require a resolvable list definition',
    () async {
      final session = OfficeMacroSession(
        _fixture(properties: _list, numbering: ''),
        format: OfficeMacroFormat.docx,
      );
      await session.run(_plan([_remove(type: 'paragraph')]));
      expect(_read(session.bytes).paragraphs.single.properties.numId, isNull);
    },
  );

  test(
    'list-bearing compatibility alternatives are refused before mutation',
    () async {
      final input = _fixture(
        body:
            '<mc:AlternateContent><mc:Choice Requires="x"><w:p><w:pPr>$_list</w:pPr><w:r><w:t>Native</w:t></w:r></w:p></mc:Choice><mc:Fallback><w:p><w:r><w:t>Fallback</w:t></w:r></w:p></mc:Fallback></mc:AlternateContent>',
        numbering: _definition(),
      );
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await expectLater(
        session.run(_plan([_default(false)])),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
    },
  );

  test('native schema rejects invalid fields and argument values', () {
    for (final values in <Map<String, Object?>>[
      {'op': 'listDefault', 'paragraph': 0, 'numbered': 'yes'},
      {'op': 'listDefault', 'paragraph': 0, 'numbered': false, 'level': 2},
      {'op': 'removeNumbers', 'paragraph': 0, 'numberType': 'listNum'},
      {'op': 'removeNumbers', 'paragraph': 0, 'numberType': 3},
    ]) {
      final doc = _read(_fixture());
      final before = doc.paragraphs.single.properties;
      expect(() => native.applyStep(doc, values), throwsArgumentError);
      expect(identical(doc.paragraphs.single.properties, before), isTrue);
    }
  });

  for (final (label, extra) in <(String, String)>[
    ('run formatting', '<w:rPr><w:b/></w:rPr>'),
    ('suffix', '<w:suff w:val="nothing"/>'),
    ('legal numbering', '<w:isLgl/>'),
    ('legacy geometry', '<w:legacy w:legacy="1" w:legacySpace="99"/>'),
  ]) {
    test('default-marker $label conflict is refused before mutation', () {
      final doc = _read(_fixture(numbering: ''));
      native.applyStep(doc, {
        'op': 'listDefault',
        'paragraph': 0,
        'numbered': false,
      });
      native.applyStep(doc, {'op': 'removeNumbers', 'paragraph': 0});
      final part = doc.package!.getPart('/word/numbering.xml')!;
      part.writeText(
        part.readText().replaceFirst('</w:lvl>', '$extra</w:lvl>'),
      );
      final original = part.readText();
      final properties = doc.paragraphs.single.properties;
      expect(
        () => native.applyStep(doc, {
          'op': 'listDefault',
          'paragraph': 0,
          'numbered': false,
        }),
        throwsUnsupportedError,
      );
      expect(part.readText(), original);
      expect(identical(doc.paragraphs.single.properties, properties), isTrue);
    });
  }

  for (final (name, type, tag) in <(String, String, String)>[
    ('header', OfficeContentTypes.wordHeader, 'hdr'),
    ('footnotes', OfficeContentTypes.wordFootnotes, 'footnotes'),
    ('comments', OfficeContentTypes.wordComments, 'comments'),
  ]) {
    test('unreferenced $name numbering IDs are reserved during allocation', () {
      final doc = _read(_fixture(numbering: ''));
      final xml =
          '<w:$tag xmlns:w="$_w"><w:p><w:pPr><w:numPr><w:numId w:val="1"/></w:numPr></w:pPr></w:p></w:$tag>';
      doc.package!.createPart(
        '/word/unreferenced-$name.xml',
        type,
        utf8.encode(xml),
      );
      native.applyStep(doc, {
        'op': 'listDefault',
        'paragraph': 0,
        'numbered': true,
      });
      expect(doc.paragraphs.single.properties.numId, isNot(1));
      expect(
        doc.package!.getPart('/word/unreferenced-$name.xml')!.readText(),
        xml,
      );
    });
  }

  test('new unsaved header numbering IDs are reserved during allocation', () {
    final doc = _read(_fixture(numbering: ''));
    doc.sections.single.header.add(
      WmlParagraph(properties: WmlParagraphProps(numId: 1)),
    );
    native.applyStep(doc, {
      'op': 'listDefault',
      'paragraph': 0,
      'numbered': true,
    });
    expect(doc.paragraphs.single.properties.numId, isNot(1));
    expect(doc.sections.single.header.single.properties.numId, 1);
  });

  for (final instruction in [r'LISTNUM\l 1', 'LISTNUM"LegalDefault"']) {
    test(
      'LISTNUM keyword boundary refuses $instruction without whitespace',
      () {
        final doc = _read(_fixture());
        doc.paragraphs.single.inlines.add(
          WmlRun(text: '1', fieldInstruction: instruction),
        );
        final before = doc.paragraphs.single.properties;
        expect(
          () => native.applyStep(doc, {'op': 'removeNumbers', 'paragraph': 0}),
          throwsUnsupportedError,
        );
        expect(identical(doc.paragraphs.single.properties, before), isTrue);
      },
    );
  }

  for (final wrapper in ['customXml', 'smartTag']) {
    for (final opaqueEnd in [false, true]) {
      test(
        'all removal refuses $wrapper field spans with ${opaqueEnd ? 'opaque' : 'modeled'} end atomically',
        () async {
          final input = _fixture(
            body:
                '<w:$wrapper w:uri="urn:example" w:element="wrapped"><w:p>'
                '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
                '<w:r><w:instrText xml:space="preserve"> LISTNUM LegalDefault </w:instrText></w:r>'
                '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
                '<w:r><w:t>Start</w:t></w:r></w:p></w:$wrapper>'
                '<w:p><w:r><w:t>Selected result</w:t></w:r>'
                '${opaqueEnd ? '' : '<w:r><w:fldChar w:fldCharType="end"/></w:r>'}</w:p>'
                '${opaqueEnd ? '<w:$wrapper w:uri="urn:example" w:element="wrapped"><w:p><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p></w:$wrapper>' : ''}',
          );
          final doc = _read(input);
          expect(doc.sections.single.blocks.first, isA<WmlOpaqueBlock>());
          final properties = doc.paragraphs.single.properties;
          final parts = {
            for (final part in doc.package!.parts)
              part.uri: Uint8List.fromList(part.readBytes()),
          };
          expect(
            () =>
                native.applyStep(doc, {'op': 'removeNumbers', 'paragraph': 0}),
            throwsUnsupportedError,
          );
          expect(
            identical(doc.paragraphs.single.properties, properties),
            isTrue,
          );
          expect({
            for (final part in doc.package!.parts) part.uri: part.readBytes(),
          }, parts);

          final session = OfficeMacroSession(
            input,
            format: OfficeMacroFormat.docx,
          );
          session.startRecording('Rejected opaque field removal');
          final macro = _plan([
            OfficeMacroStep(
              tool: 'docx.paragraphFormat',
              arguments: {'paragraph': 0, 'after': 12},
            ),
            _remove(),
          ]);
          for (final action in [session.validate, session.run]) {
            await expectLater(
              action(macro),
              throwsA(
                isA<OfficeMacroException>().having(
                  (error) => error.stepIndex,
                  'stepIndex',
                  1,
                ),
              ),
            );
            expect(session.bytes, input);
            expect(session.revision, 0);
          }
          expect(session.stopRecording().steps, isEmpty);

          if (!opaqueEnd) {
            expect(
              () => native.applyStep(doc, {
                'op': 'removeNumbers',
                'paragraph': 0,
                'numberType': 'paragraph',
              }),
              throwsUnsupportedError,
            );
            expect(
              identical(doc.paragraphs.single.properties, properties),
              isTrue,
            );
            expect({
              for (final part in doc.package!.parts) part.uri: part.readBytes(),
            }, parts);
            await expectLater(
              session.run(_plan([_remove(type: 'paragraph')])),
              throwsA(isA<OfficeMacroException>()),
            );
            expect(session.bytes, input);
            expect(session.revision, 0);
            return;
          }

          await session.run(_plan([_remove(type: 'paragraph')]));
          final originalTokens = _fieldTokens(input);
          var saved = session.bytes;
          for (var cycle = 0; cycle < 3; cycle++) {
            final reopened = _read(saved);
            expect(reopened.paragraphs.single.text, 'Selected result');
            expect(
              reopened.paragraphs.single.properties.numberingSuppressed,
              isTrue,
            );
            expect(_fieldTokens(saved), originalTokens);
            saved = WordSerializer().writeBytes(reopened);
          }
        },
      );
    }
  }

  test('all removal checks field-bearing opaque inlines outside selector', () {
    final doc = _read(
      _fixture(
        body:
            '<w:p><w:r><w:t>Earlier</w:t></w:r></w:p><w:p><w:r><w:t>Selected</w:t></w:r></w:p>',
      ),
    );
    final paragraphs = doc.paragraphs.toList();
    paragraphs.first.inlines.add(
      WmlOpaqueInline(
        content: WmlOpaqueBlock(
          xml:
              '<w:customXml xmlns:w="$_w"><w:r><w:fldChar w:fldCharType="begin"/></w:r>'
              '<w:r><w:instrText> LISTNUM LegalDefault </w:instrText></w:r>'
              '<w:r><w:fldChar w:fldCharType="separate"/></w:r></w:customXml>',
          sourcePartUri: '/word/document.xml',
          relationships: const [],
        ),
      ),
    );
    final properties = paragraphs.last.properties;
    expect(
      () => native.applyStep(doc, {'op': 'removeNumbers', 'paragraph': 1}),
      throwsUnsupportedError,
    );
    expect(identical(paragraphs.last.properties, properties), isTrue);
    native.applyStep(doc, {
      'op': 'removeNumbers',
      'paragraph': 1,
      'numberType': 'paragraph',
    });
    expect(paragraphs.last.properties.numberingSuppressed, isTrue);
    expect(paragraphs.first.inlines.last, isA<WmlOpaqueInline>());
  });

  for (final kind in [
    WmlFieldBoundaryKind.separate,
    WmlFieldBoundaryKind.end,
  ]) {
    test('all removal refuses selected orphan ${kind.name}', () {
      final doc = _read(_fixture());
      doc.paragraphs.single.inlines.add(WmlFieldBoundary(kind: kind));
      final properties = doc.paragraphs.single.properties;
      expect(
        () => native.applyStep(doc, {'op': 'removeNumbers', 'paragraph': 0}),
        throwsUnsupportedError,
      );
      expect(identical(doc.paragraphs.single.properties, properties), isTrue);
    });
  }

  test(
    'all removal retains ordinary opaque body content without fields',
    () async {
      final session = OfficeMacroSession(
        _fixture(
          body:
              '<w:customXml w:uri="urn:example" w:element="wrapped"><w:p><w:r><w:t>Opaque text</w:t></w:r></w:p></w:customXml>'
              '<w:p><w:r><w:t>Selected</w:t></w:r></w:p>',
        ),
        format: OfficeMacroFormat.docx,
      );
      await session.run(_plan([_remove()]));
      expect(_read(session.bytes).paragraphs.single.text, 'Selected');
      expect(
        OpcPackage.openBytes(
          session.bytes,
        ).getPart('/word/document.xml')!.readText(),
        contains('Opaque text'),
      );
    },
  );

  final stories = <String, void Function(WmlDocument, WmlParagraph)>{
    'unselected body': (doc, paragraph) =>
        doc.sections.single.blocks.add(paragraph),
    'header': (doc, paragraph) => doc.sections.single.header.add(paragraph),
    'footer': (doc, paragraph) => doc.sections.single.footer.add(paragraph),
    'first header': (doc, paragraph) =>
        doc.sections.single.firstHeader.add(paragraph),
    'first footer': (doc, paragraph) =>
        doc.sections.single.firstFooter.add(paragraph),
    'even header': (doc, paragraph) =>
        doc.sections.single.evenHeader.add(paragraph),
    'even footer': (doc, paragraph) =>
        doc.sections.single.evenFooter.add(paragraph),
    'footnote': (doc, paragraph) => doc.footnotes.add(
      WmlNote(id: 1, endnote: false, paragraphs: [paragraph]),
    ),
    'endnote': (doc, paragraph) => doc.endnotes.add(
      WmlNote(id: 1, endnote: true, paragraphs: [paragraph]),
    ),
    'comment': (doc, paragraph) =>
        doc.comments.add(WmlComment(id: 1, paragraphs: [paragraph])),
  };
  for (final story in stories.entries) {
    test(
      'all new list edits refuse unbalanced ${story.key} fields atomically',
      () {
        final doc = _read(_fixture());
        final target = doc.paragraphs.single;
        final unbalanced = WmlParagraph(
          inlines: [WmlFieldBoundary(kind: WmlFieldBoundaryKind.end)],
        );
        story.value(doc, unbalanced);
        final properties = target.properties;
        final parts = {
          for (final part in doc.package!.parts)
            part.uri: Uint8List.fromList(part.readBytes()),
        };
        for (final operation in <Map<String, Object?>>[
          {'op': 'listDefault', 'paragraph': 0, 'numbered': false},
          {'op': 'listDefault', 'paragraph': 0, 'numbered': true},
          {'op': 'removeNumbers', 'paragraph': 0, 'numberType': 'all'},
          {'op': 'removeNumbers', 'paragraph': 0, 'numberType': 'paragraph'},
        ]) {
          expect(
            () => native.applyStep(doc, operation),
            throwsUnsupportedError,
          );
          expect(identical(target.properties, properties), isTrue);
          expect(unbalanced.inlines, hasLength(1));
          expect({
            for (final part in doc.package!.parts) part.uri: part.readBytes(),
          }, parts);
        }
      },
    );
  }
}
