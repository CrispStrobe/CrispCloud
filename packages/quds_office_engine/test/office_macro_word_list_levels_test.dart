import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:list-level-test';
const _list = '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="71"/></w:numPr>';

String _level(
  int index, {
  String format = 'decimal',
  String? text,
  String? indent,
  String extra = '',
}) =>
    '<w:lvl w:ilvl="$index"><w:start w:val="1"/>'
    '<w:numFmt w:val="$format"/>'
    '<w:lvlText w:val="${text ?? (format == 'bullet' ? '•' : '${[for (var i = 0; i <= index; i++) '%${i + 1}'].join('.')}.')}"/>'
    '<w:lvlJc w:val="left"/><w:pPr>'
    '${indent ?? '<w:ind w:left="${(index + 1) * 360}" w:hanging="180"/>'}'
    '</w:pPr>$extra</w:lvl>';

String _definition({
  String? levels,
  String? type = 'multilevel',
  String extra = '',
  String overrides = '',
}) =>
    '<w:abstractNum w:abstractNumId="42">'
    '${type == null ? '' : '<w:multiLevelType w:val="$type"/>'}$extra'
    '${levels ?? [for (var i = 0; i < 9; i++) _level(i)].join()}'
    '</w:abstractNum><w:num w:numId="71">'
    '<w:abstractNumId w:val="42"/>$overrides</w:num>';

Uint8List _fixture({
  String properties = _list,
  String? numbering,
  String? styles,
  String? body,
  bool saveBaseline = false,
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
  final xml =
      '<w:numbering xmlns:w="$_w" xmlns:x="$_x">'
      '${numbering ?? _definition()}</w:numbering>';
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
  final relationships = package.relationshipsFor('/word/document.xml');
  if (relationships.firstByType(RelationshipTypes.numbering) == null) {
    relationships.add(
      type: RelationshipTypes.numbering,
      target: 'numbering.xml',
    );
  }
  if (styles != null) {
    package
        .getPart('/word/styles.xml')!
        .writeText('<w:styles xmlns:w="$_w" xmlns:x="$_x">$styles</w:styles>');
  }
  final bytes = package.save();
  return saveBaseline ? WordSerializer().writeBytes(_read(bytes)) : bytes;
}

WmlDocument _read(Uint8List bytes) => WordDeserializer().readBytes(bytes);
String _numbering(Uint8List bytes) =>
    OpcPackage.openBytes(bytes).getPart('/word/numbering.xml')!.readText();
XmlElement _properties(Uint8List bytes) =>
    XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!
        .firstChild('body', namespaceUri: _w)!
        .firstChild('p', namespaceUri: _w)!
        .firstChild('pPr', namespaceUri: _w)!;
String? _val(XmlElement node, String name) =>
    node.getAttribute(name, namespaceUri: _w);
Map<String, Uint8List> _parts(WmlDocument document) => {
  for (final part in document.package!.parts) part.uri: part.readBytes(),
};

OfficeMacroStep _outline({int paragraph = 0}) => OfficeMacroStep(
  tool: 'docx.listOutlineDefault',
  arguments: {'paragraph': paragraph},
);
OfficeMacroStep _select(int level, {int paragraph = 0}) => OfficeMacroStep(
  tool: 'docx.listLevel',
  arguments: {'paragraph': paragraph, 'level': level},
);
OfficeMacro _plan(List<OfficeMacroStep> steps) => OfficeMacro(
  name: 'List levels',
  format: OfficeMacroFormat.docx,
  steps: steps,
);

void _refuses(
  WmlDocument document,
  Map<String, Object?> operation, {
  Matcher? matcher,
}) {
  final properties = document.paragraphs.single.properties;
  final originalSource = properties.sourcePropertiesXml;
  final parts = _parts(document);
  expect(
    () => native.applyStep(document, operation),
    matcher ?? throwsUnsupportedError,
  );
  expect(identical(document.paragraphs.single.properties, properties), isTrue);
  expect(properties.sourcePropertiesXml, originalSource);
  expect(_parts(document), parts);
}

void main() {
  test(
    'new outline has nine distinct levels, shared identity and hierarchical counters',
    () async {
      final session = OfficeMacroSession(
        _fixture(
          properties: '',
          numbering: '',
          body: [
            for (var i = 0; i < 9; i++)
              '<w:p><w:r><w:t>Item $i</w:t></w:r></w:p>',
          ].join(),
        ),
        format: OfficeMacroFormat.docx,
      );
      await session.run(
        _plan([
          for (var i = 0; i < 9; i++) ...[
            _outline(paragraph: i),
            _select(i, paragraph: i),
          ],
        ]),
      );
      var bytes = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        final document = _read(bytes);
        final paragraphs = document.paragraphs.toList();
        expect(paragraphs.map((p) => p.properties.numId).toSet(), hasLength(1));
        for (var i = 0; i < 9; i++) {
          expect(paragraphs[i].properties.ilvl, i);
          expect(paragraphs[i].properties.indent.left, (i + 1) * 18);
          expect(paragraphs[i].properties.indent.hanging, 9);
          expect(
            paragraphs[i].properties.listLabel,
            '${List.filled(i + 1, '1').join('.')}. ',
          );
        }
        final root = XmlDocument.parse(_numbering(bytes)).root!;
        final outlines = root
            .childrenNamed('abstractNum', namespaceUri: _w)
            .where(
              (node) =>
                  node
                      .firstChild('name', namespaceUri: _w)
                      ?.getAttribute('val', namespaceUri: _w) ==
                  'Quds-VBA-decimal-outline-v1',
            )
            .toList();
        expect(outlines, hasLength(1));
        expect(
          outlines.single.childrenNamed('lvl', namespaceUri: _w),
          hasLength(9),
        );
        expect(
          root
              .childrenNamed('num', namespaceUri: _w)
              .where(
                (node) =>
                    node
                        .firstChild('abstractNumId', namespaceUri: _w)
                        ?.getAttribute('val', namespaceUri: _w) ==
                    outlines.single.getAttribute(
                      'abstractNumId',
                      namespaceUri: _w,
                    ),
              ),
          hasLength(1),
        );
        bytes = WordSerializer().writeBytes(document);
      }
    },
  );

  for (final type in ['multilevel', 'hybridMultilevel']) {
    for (final level in [0, 4, 8]) {
      test(
        'outline toggle recognizes $type at level ${level + 1} and preserves style',
        () async {
          final input = _fixture(
            properties:
                '<w:pStyle w:val="Heading1"/><w:numPr><w:ilvl w:val="$level"/>'
                '<w:numId w:val="71"/></w:numPr><w:ind w:left="900" w:right="240"/>',
            numbering: _definition(type: type),
            saveBaseline: true,
          );
          final session = OfficeMacroSession(
            input,
            format: OfficeMacroFormat.docx,
          );
          await session.run(_plan([_outline()]));
          expect(_numbering(session.bytes), _numbering(input));
          var bytes = session.bytes;
          for (var cycle = 0; cycle < 3; cycle++) {
            final document = _read(bytes);
            final properties = document.paragraphs.single.properties;
            expect(properties.numId, isNull);
            expect(properties.numberingSuppressed, isTrue);
            expect(properties.styleId, 'Heading1');
            expect(properties.indent.left, 45);
            expect(properties.indent.right, 12);
            bytes = WordSerializer().writeBytes(document);
          }
        },
      );
    }
  }

  for (final format in ['decimal', 'bullet']) {
    test(
      'outline applies over single-level $format without altering imported definitions',
      () async {
        final input = _fixture(
          numbering: _definition(
            type: 'singleLevel',
            levels: _level(0, format: format),
          ),
        );
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        await session.run(_plan([_outline(), _select(2)]));
        final properties = _read(session.bytes).paragraphs.single.properties;
        expect(properties.numId, isNot(71));
        expect(properties.ilvl, 2);
        expect(properties.listLabel, '1.1.1. ');
        expect(
          _numbering(session.bytes),
          contains('<w:abstractNumId w:val="42"'),
        );
        expect(_numbering(session.bytes), contains('w:numId="71"'));
        expect(
          _numbering(session.bytes),
          contains('Quds-VBA-decimal-outline-v1'),
        );
      },
    );
  }

  test(
    'existing VBA default remains single level and refuses missing target',
    () {
      final doc = _read(_fixture(properties: '', numbering: ''));
      native.applyStep(doc, {
        'op': 'listDefault',
        'paragraph': 0,
        'numbered': true,
      });
      expect(
        doc.package!.getPart('/word/numbering.xml')!.readText(),
        contains('Quds-VBA-decimal-single-v1'),
      );
      _refuses(doc, {'op': 'listLevel', 'paragraph': 0, 'delta': 1});
    },
  );

  test(
    'level changes preserve numbering bytes, explicit right indent and unrelated metadata',
    () async {
      final input = _fixture(
        saveBaseline: true,
        properties:
            '$_list<w:ind w:left="1440" w:right="240" x:keep="indent"/>'
            '<w:spacing w:before="120"/><x:opaque x:keep="yes"/>',
        numbering: _definition(
          levels:
              '${_level(0)}${_level(1, indent: '<w:ind w:left="913" w:hanging="127" x:keep="level"/>')}',
        ),
      );
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(_plan([_select(1)]));
      var bytes = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(_numbering(bytes), _numbering(input));
        final document = _read(bytes);
        final properties = document.paragraphs.single.properties;
        expect(properties.numId, 71);
        expect(properties.ilvl, 1);
        expect(properties.indent.left, 45.65);
        expect(properties.indent.hanging, 6.35);
        expect(properties.indent.right, 12);
        final pp = _properties(bytes);
        expect(
          pp
              .firstChild('ind', namespaceUri: _w)!
              .getAttribute('keep', namespaceUri: _x),
          'indent',
        );
        expect(
          pp
              .firstChild('opaque', namespaceUri: _x)!
              .getAttribute('keep', namespaceUri: _x),
          'yes',
        );
        expect(
          _val(pp.firstChild('spacing', namespaceUri: _w)!, 'before'),
          '120',
        );
        bytes = WordSerializer().writeBytes(document);
      }
    },
  );

  for (final type in ['singleLevel', 'multilevel', 'hybridMultilevel', null]) {
    test(
      'actual target definition is available independently of type $type',
      () async {
        final session = OfficeMacroSession(
          _fixture(numbering: _definition(type: type)),
          format: OfficeMacroFormat.docx,
        );
        await session.run(_plan([_select(2)]));
        final properties = _read(session.bytes).paragraphs.single.properties;
        expect(properties.numId, 71);
        expect(properties.ilvl, 2);
        expect(properties.listLabel, '1.1.1. ');
      },
    );
  }

  test('complete target override owns its geometry, format and start', () async {
    final input = _fixture(
      saveBaseline: true,
      numbering: _definition(
        levels: '${_level(0, format: 'upperRoman')}${_level(1)}',
        overrides:
            '<w:lvlOverride w:ilvl="0"><w:startOverride w:val="3"/></w:lvlOverride>'
            '<w:lvlOverride w:ilvl="1"><w:startOverride w:val="4"/>'
            '${_level(1, format: 'lowerLetter', indent: '<w:ind w:left="1600" w:hanging="300"/>')}'
            '</w:lvlOverride>',
      ),
    );
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    await session.run(_plan([_select(1)]));
    final properties = _read(session.bytes).paragraphs.single.properties;
    expect(properties.listLabel, 'III.d. ');
    expect(properties.indent.left, 80);
    expect(properties.indent.hanging, 15);
    expect(_numbering(session.bytes), _numbering(input));
  });

  for (final format in [
    'decimal',
    'decimalZero',
    'upperRoman',
    'lowerRoman',
    'upperLetter',
    'lowerLetter',
    'bullet',
  ]) {
    test(
      'level writes support native $format without guessing from IDs or cache',
      () async {
        final document = _read(
          _fixture(
            numbering: _definition(
              levels:
                  '${_level(0, format: format, text: format == 'bullet' ? '◆' : '%1.')}'
                  '${_level(1, format: format, text: format == 'bullet' ? '◇' : '%2.')}',
            ),
          ),
        );
        document.paragraphs.single.properties.listLabel =
            'misleading cached label';
        native.applyStep(document, {
          'op': 'listLevel',
          'paragraph': 0,
          'level': 1,
        });
        expect(document.paragraphs.single.properties.listLabel, isNull);
        final reopened = _read(WordSerializer().writeBytes(document));
        expect(reopened.paragraphs.single.properties.numId, 71);
        expect(reopened.paragraphs.single.properties.ilvl, 1);
        expect(
          reopened.paragraphs.single.properties.listLabel,
          {
            'decimal': '1. ',
            'decimalZero': '01. ',
            'upperRoman': 'I. ',
            'lowerRoman': 'i. ',
            'upperLetter': 'A. ',
            'lowerLetter': 'a. ',
            'bullet': '◇ ',
          }[format],
        );
      },
    );
  }

  test(
    'positive firstLine target serializes without hanging and survives reopen',
    () async {
      final session = OfficeMacroSession(
        _fixture(
          numbering: _definition(
            levels:
                '${_level(0)}${_level(1, indent: '<w:ind w:left="-200" w:firstLine="140"/>')}',
          ),
        ),
        format: OfficeMacroFormat.docx,
      );
      await session.run(_plan([_select(1)]));
      var bytes = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        final indent = _properties(bytes).firstChild('ind', namespaceUri: _w)!;
        expect(_val(indent, 'hanging'), isNull);
        expect(_val(indent, 'firstLine'), '140');
        final document = _read(bytes);
        expect(document.paragraphs.single.properties.indent.firstLine, 7);
        expect(document.paragraphs.single.properties.indent.hanging, 0);
        expect(document.paragraphs.single.properties.indent.left, -10);
        bytes = WordSerializer().writeBytes(document);
      }
    },
  );

  test(
    'inherited numbering becomes direct while inherited right stays inherited',
    () async {
      final session = OfficeMacroSession(
        _fixture(
          properties: '<w:pStyle w:val="P"/>',
          styles:
              '<w:style w:type="paragraph" w:styleId="P"><w:pPr>$_list'
              '<w:ind w:right="240"/></w:pPr></w:style>',
        ),
        format: OfficeMacroFormat.docx,
      );
      await session.run(_plan([_select(2)]));
      final pp = _properties(session.bytes);
      expect(
        _val(
          pp
              .firstChild('numPr', namespaceUri: _w)!
              .firstChild('ilvl', namespaceUri: _w)!,
          'val',
        ),
        '2',
      );
      expect(_val(pp.firstChild('ind', namespaceUri: _w)!, 'right'), isNull);
      expect(
        _read(session.bytes).paragraphs.single.properties.indent.right,
        12,
      );
      await session.run(
        _plan([
          OfficeMacroStep(
            tool: 'docx.styleDefinition',
            arguments: {
              'style': 'P',
              'pPr': {
                'numPr': null,
                'ind': {'right': '400'},
              },
            },
          ),
        ]),
      );
      final properties = _read(session.bytes).paragraphs.single.properties;
      expect(properties.ilvl, 2);
      expect(properties.numId, 71);
      expect(properties.indent.right, 20);
      expect(properties.indent.left, 54);
    },
  );

  for (final foreignWordPrefix in [false, true]) {
    for (final operation in ['listLevel', 'listOutlineDefault']) {
      test('$operation preserves x:w/x:w1 and rebound w: $foreignWordPrefix', () async {
        const extension = 'urn:word-level-prefix-extension';
        final prefix = foreignWordPrefix ? 'q' : 'w';
        final collision = foreignWordPrefix ? 'w1' : 'w';
        final pp =
            '<$prefix:pPr xmlns:$prefix="$_w" xmlns:x="$_x" x:$collision="root" '
            '${foreignWordPrefix ? 'xmlns:w="$extension" w:keep="extension"' : ''}>'
            '<$prefix:numPr x:$collision="num"><$prefix:ilvl $prefix:val="0" x:$collision="level"/>'
            '<$prefix:numId $prefix:val="71" x:$collision="id"/></$prefix:numPr>'
            '<$prefix:ind $prefix:left="1440" $prefix:right="240" x:$collision="indent"/>'
            '${foreignWordPrefix ? '<w:opaque w:keep="child"/>' : ''}</$prefix:pPr>';
        final input = _fixture(
          body: '<w:p>$pp<w:r><w:t>Original</w:t></w:r></w:p>',
          numbering: operation == 'listOutlineDefault'
              ? _definition(type: 'singleLevel', levels: _level(0))
              : null,
        );
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        await session.run(
          _plan([operation == 'listLevel' ? _select(1) : _outline()]),
        );
        var bytes = session.bytes;
        for (var cycle = 0; cycle < 3; cycle++) {
          final saved = _properties(bytes);
          expect(saved.getAttribute(collision, namespaceUri: _x), 'root');
          final number = saved.firstChild('numPr', namespaceUri: _w)!;
          expect(number.getAttribute(collision, namespaceUri: _x), 'num');
          expect(
            number
                .firstChild('ilvl', namespaceUri: _w)!
                .getAttribute(collision, namespaceUri: _x),
            'level',
          );
          expect(
            number
                .firstChild('numId', namespaceUri: _w)!
                .getAttribute(collision, namespaceUri: _x),
            'id',
          );
          expect(
            saved
                .firstChild('ind', namespaceUri: _w)!
                .getAttribute(collision, namespaceUri: _x),
            'indent',
            reason:
                'Reopen cycle $cycle: ${XmlDocument(root: saved.copy()).toXmlString()}',
          );
          if (foreignWordPrefix) {
            expect(
              saved.getAttribute('keep', namespaceUri: extension),
              'extension',
            );
            expect(
              saved
                  .firstChild('opaque', namespaceUri: extension)!
                  .getAttribute('keep', namespaceUri: extension),
              'child',
            );
          }
          bytes = WordSerializer().writeBytes(_read(bytes));
        }
      });
    }
  }

  final malformedLevels = <String, String>{
    'missing target': _definition(levels: _level(0)),
    'duplicate target': _definition(
      levels: '${_level(0)}${_level(1)}${_level(1)}',
    ),
    'duplicate override': _definition(
      overrides: '<w:lvlOverride w:ilvl="1"/><w:lvlOverride w:ilvl="1"/>',
    ),
    'mismatched override': _definition(
      overrides: '<w:lvlOverride w:ilvl="1">${_level(2)}</w:lvlOverride>',
    ),
    'partial override': _definition(
      overrides:
          '<w:lvlOverride w:ilvl="1"><w:lvl w:ilvl="1"><w:numFmt w:val="decimal"/></w:lvl></w:lvlOverride>',
    ),
    'duplicate ancestor start override': _definition(
      overrides:
          '<w:lvlOverride w:ilvl="0"><w:startOverride w:val="1"/><w:startOverride w:val="2"/></w:lvlOverride>',
    ),
    'invalid ancestor start override': _definition(
      overrides:
          '<w:lvlOverride w:ilvl="0"><w:startOverride w:val="bad"/></w:lvlOverride>',
    ),
    'missing referenced ancestor': _definition(levels: _level(1)),
    'future counter': _definition(
      levels: '${_level(0)}${_level(1, text: '%2.%3.')}',
    ),
    'repeated counter': _definition(
      levels: '${_level(0)}${_level(1, text: '%1.%2.%2.')}',
    ),
    'unrendered format': _definition(
      levels: '${_level(0)}${_level(1, format: 'ordinal')}',
    ),
    'linked numbering': _definition(extra: '<w:numStyleLink w:val="P"/>'),
    'picture bullet': _definition(
      levels:
          '${_level(0)}${_level(1, extra: '<w:lvlPicBulletId w:val="1"/>')}',
    ),
    'legal numbering': _definition(
      levels: '${_level(0)}${_level(1, extra: '<w:isLgl/>')}',
    ),
    'level restart': _definition(
      levels: '${_level(0)}${_level(1, extra: '<w:lvlRestart w:val="0"/>')}',
    ),
    'style linked level': _definition(
      levels: '${_level(0)}${_level(1, extra: '<w:pStyle w:val="P"/>')}',
    ),
    'legacy level': _definition(
      levels: '${_level(0)}${_level(1, extra: '<w:legacy/>')}',
    ),
    for (final (name, indent) in <(String, String)>[
      ('missing indent', ''),
      ('missing left', '<w:ind w:hanging="180"/>'),
      ('malformed left', '<w:ind w:left="5.5"/>'),
      ('overflow left', '<w:ind w:left="2147483648"/>'),
      ('negative hanging', '<w:ind w:left="720" w:hanging="-1"/>'),
      ('logical start', '<w:ind w:start="720"/>'),
      ('character units', '<w:ind w:left="720" w:leftChars="200"/>'),
      ('target right', '<w:ind w:left="720" w:right="240"/>'),
      (
        'competing positive indents',
        '<w:ind w:left="720" w:firstLine="140" w:hanging="180"/>',
      ),
      (
        'zero hanging suppresses firstLine',
        '<w:ind w:left="720" w:firstLine="140" w:hanging="0"/>',
      ),
      ('other paragraph formatting', '<w:ind w:left="720"/><w:tabs/>'),
    ])
      name: _definition(levels: '${_level(0)}${_level(1, indent: indent)}'),
  };
  for (final entry in malformedLevels.entries) {
    test('${entry.key} is refused without native mutation', () {
      _refuses(_read(_fixture(numbering: entry.value)), {
        'op': 'listLevel',
        'paragraph': 0,
        'level': 1,
      });
    });
  }

  for (final arguments in <Map<String, Object?>>[
    {},
    {'level': 0, 'delta': 1},
    {'delta': 0},
    {'delta': 2},
    {'delta': -2},
    {'level': -1},
    {'level': 9},
    {'level': 1.5},
    {'level': true},
    {'delta': '1'},
  ]) {
    test(
      'invalid native argument shape $arguments refuses before mutation',
      () {
        _refuses(_read(_fixture()), {
          'op': 'listLevel',
          'paragraph': 0,
          ...arguments,
        }, matcher: throwsArgumentError);
      },
    );
  }

  for (final properties in ['', '<w:numPr><w:numId w:val="0"/></w:numPr>']) {
    test('no active list $properties refuses without creating numbering', () {
      _refuses(_read(_fixture(properties: properties, numbering: '')), {
        'op': 'listLevel',
        'paragraph': 0,
        'level': 0,
      });
    });
  }

  for (final (level, delta) in [(0, -1), (8, 1)]) {
    test('boundary $level plus $delta refuses instead of clamping', () {
      _refuses(
        _read(
          _fixture(
            properties:
                '<w:numPr><w:ilvl w:val="$level"/>'
                '<w:numId w:val="71"/></w:numPr>',
          ),
        ),
        {'op': 'listLevel', 'paragraph': 0, 'delta': delta},
      );
    });
  }

  test('pending restart is refused without relocating or discarding it', () {
    final document = _read(_fixture());
    document.paragraphs.single.properties.listRestart = 7;
    _refuses(document, {'op': 'listLevel', 'paragraph': 0, 'level': 1});
    expect(document.paragraphs.single.properties.listRestart, 7);
  });

  for (final direct in [false, true]) {
    test(
      'plain import and list edits retain ${direct ? 'direct' : 'inherited'} rebound-prefix geometry',
      () async {
        const extension = 'urn:list-level-style-extension';
        final original =
            '<q:ind q:left="1440" ${direct ? '' : 'q:right="240"'} '
            'x:w1="source-indent"/>';
        final styles =
            '<w:style w:type="paragraph" w:styleId="P">'
            '<q:pPr xmlns:q="$_w" xmlns:w="$extension" xmlns:x="$_x">'
            '${direct ? '<q:ind q:right="240"/>' : original}'
            '</q:pPr></w:style>';
        final input = _fixture(
          styles: styles,
          body:
              '<w:p><q:pPr xmlns:q="$_w" xmlns:w="$extension" xmlns:x="$_x">'
              '<q:pStyle q:val="P"/><q:numPr><q:ilvl q:val="0"/><q:numId q:val="71"/></q:numPr>'
              '${direct ? original : ''}</q:pPr><w:r><w:t>Original</w:t></w:r></w:p>',
        );
        var bytes = input;
        for (var cycle = 0; cycle < 3; cycle++) {
          final document = _read(bytes);
          expect(document.paragraphs.single.properties.indent.left, 72);
          expect(document.paragraphs.single.properties.indent.right, 12);
          bytes = WordSerializer().writeBytes(document);
        }
        final session = OfficeMacroSession(
          bytes,
          format: OfficeMacroFormat.docx,
        );
        await session.run(_plan([_select(2)]));
        bytes = session.bytes;
        for (var cycle = 0; cycle < 3; cycle++) {
          final document = _read(bytes);
          expect(document.paragraphs.single.properties.indent.left, 54);
          expect(document.paragraphs.single.properties.indent.right, 12);
          expect(
            _val(
              _properties(bytes).firstChild('ind', namespaceUri: _w)!,
              'right',
            ),
            isNull,
          );
          if (direct) {
            expect(
              _properties(bytes)
                  .firstChild('ind', namespaceUri: _w)!
                  .getAttribute('w1', namespaceUri: _x),
              'source-indent',
            );
          } else {
            expect(
              OpcPackage.openBytes(
                bytes,
              ).getPart('/word/styles.xml')!.readText(),
              contains('source-indent'),
            );
          }
          bytes = WordSerializer().writeBytes(document);
        }
      },
    );
  }

  test(
    'foreign indentation lookalike stays opaque during effective projection',
    () async {
      final input = _fixture(
        properties:
            '$_list'
            '<w:ind w:left="1440" w:right="240"/>'
            '<x:ind x:left="99999" x:right="88888" x:keep="opaque"/>',
      );
      final document = _read(input);
      expect(document.paragraphs.single.properties.indent.left, 72);
      expect(document.paragraphs.single.properties.indent.right, 12);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(_plan([_select(2)]));
      var bytes = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        final reopened = _read(bytes);
        expect(reopened.paragraphs.single.properties.indent.left, 54);
        expect(reopened.paragraphs.single.properties.indent.right, 12);
        expect(
          _properties(bytes)
              .firstChild('ind', namespaceUri: _x)!
              .getAttribute('keep', namespaceUri: _x),
          'opaque',
        );
        bytes = WordSerializer().writeBytes(reopened);
      }
    },
  );

  test(
    'direct relative level moves preserve every package part and list identity',
    () {
      final document = _read(_fixture());
      final parts = _parts(document);
      native.applyStep(document, {
        'op': 'listLevel',
        'paragraph': 0,
        'delta': 1,
      });
      expect(document.paragraphs.single.properties.numId, 71);
      expect(document.paragraphs.single.properties.ilvl, 1);
      expect(_parts(document), parts);
      native.applyStep(document, {
        'op': 'listLevel',
        'paragraph': 0,
        'delta': -1,
      });
      expect(document.paragraphs.single.properties.ilvl, 0);
      expect(_parts(document), parts);
    },
  );

  test(
    'a preceding explicit right-indent write remains direct after level edit',
    () async {
      final session = OfficeMacroSession(
        _fixture(
          properties: '<w:pStyle w:val="P"/>',
          styles:
              '<w:style w:type="paragraph" w:styleId="P"><w:pPr>$_list'
              '<w:ind w:right="240"/></w:pPr></w:style>',
        ),
        format: OfficeMacroFormat.docx,
      );
      await session.run(
        _plan([
          OfficeMacroStep(
            tool: 'docx.paragraphFormat',
            arguments: {'paragraph': 0, 'right': 33},
          ),
          _select(2),
        ]),
      );
      expect(
        _val(
          _properties(session.bytes).firstChild('ind', namespaceUri: _w)!,
          'right',
        ),
        '660',
      );
      expect(
        _read(session.bytes).paragraphs.single.properties.indent.right,
        33,
      );
    },
  );

  test(
    'new outline geometry preserves inherited right against later style edits',
    () async {
      final session = OfficeMacroSession(
        _fixture(
          properties: '<w:pStyle w:val="P"/>',
          numbering: _definition(type: 'singleLevel', levels: _level(0)),
          styles:
              '<w:style w:type="paragraph" w:styleId="P"><w:pPr>$_list'
              '<w:ind w:right="240"/></w:pPr></w:style>',
        ),
        format: OfficeMacroFormat.docx,
      );
      await session.run(_plan([_outline()]));
      expect(
        _val(
          _properties(session.bytes).firstChild('ind', namespaceUri: _w)!,
          'right',
        ),
        isNull,
      );
      await session.run(
        _plan([
          OfficeMacroStep(
            tool: 'docx.styleDefinition',
            arguments: {
              'style': 'P',
              'pPr': {
                'numPr': null,
                'ind': {'right': '400'},
              },
            },
          ),
        ]),
      );
      final properties = _read(session.bytes).paragraphs.single.properties;
      expect(properties.indent.right, 20);
      expect(properties.indent.left, 18);
      expect(properties.numId, isNot(71));
    },
  );

  for (final attribute in [
    'leftChars',
    'start',
    'startChars',
    'hangingChars',
    'firstLineChars',
  ]) {
    for (final operation in ['listLevel', 'listOutlineDefault']) {
      test('$operation rejects inherited $attribute precedence', () {
        final document = _read(
          _fixture(
            properties: operation == 'listLevel' ? _list : '',
            styles:
                '<w:docDefaults><w:pPrDefault><w:pPr><w:ind w:$attribute="200"/>'
                '</w:pPr></w:pPrDefault></w:docDefaults>',
          ),
        );
        _refuses(document, {
          'op': operation,
          'paragraph': 0,
          if (operation == 'listLevel') 'level': 1,
        });
      });
    }
  }

  for (final hanging in ['0', '180']) {
    test('positive firstLine refuses inherited hanging=$hanging ambiguity', () {
      _refuses(
        _read(
          _fixture(
            properties: '$_list<w:pStyle w:val="P"/>',
            styles:
                '<w:style w:type="paragraph" w:styleId="P"><w:pPr><w:ind w:hanging="$hanging"/></w:pPr></w:style>',
            numbering: _definition(
              levels:
                  '${_level(0)}${_level(1, indent: '<w:ind w:left="720" w:firstLine="140"/>')}',
            ),
          ),
        ),
        {'op': 'listLevel', 'paragraph': 0, 'level': 1},
      );
    });
  }

  for (final numbering in <String>[
    _definition(type: null),
    _definition(type: 'unknown'),
    _definition(levels: _level(0)),
    _definition(levels: '${_level(0)}${_level(1, format: 'bullet')}'),
  ]) {
    test(
      'outline refuses ambiguous type or mixed template ${numbering.hashCode}',
      () {
        _refuses(_read(_fixture(numbering: numbering)), {
          'op': 'listOutlineDefault',
          'paragraph': 0,
        });
      },
    );
  }

  for (final extra in [
    '<w:isLgl/>',
    '<w:rPr><w:b/></w:rPr>',
    '<w:suff w:val="space"/>',
  ]) {
    test('outline marker with extra semantics $extra cannot be reused', () {
      final document = _read(_fixture(properties: '', numbering: ''));
      native.applyStep(document, {'op': 'listOutlineDefault', 'paragraph': 0});
      native.applyStep(document, {
        'op': 'removeNumbers',
        'paragraph': 0,
        'numberType': 'paragraph',
      });
      final part = document.package!.getPart('/word/numbering.xml')!;
      part.writeText(
        part.readText().replaceFirst('</w:lvl>', '$extra</w:lvl>'),
      );
      _refuses(document, {'op': 'listOutlineDefault', 'paragraph': 0});
    });
  }

  test(
    'outline allocation reserves opaque source and unsaved other-story IDs',
    () {
      final document = _read(_fixture(properties: '', numbering: ''));
      document.sections.single.header.add(
        WmlParagraph(properties: WmlParagraphProps(numId: 1)),
      );
      const uri = '/word/unused-level-comments.xml';
      final xml =
          '<w:comments xmlns:w="$_w"><w:comment w:id="4"><w:p><w:pPr>'
          '<w:numPr><w:numId w:val="2"/></w:numPr></w:pPr></w:p></w:comment></w:comments>';
      document.package!.createPart(
        uri,
        OfficeContentTypes.wordComments,
        utf8.encode(xml),
      );
      native.applyStep(document, {'op': 'listOutlineDefault', 'paragraph': 0});
      expect(document.paragraphs.single.properties.numId, 3);
      expect(document.package!.getPart(uri)!.readText(), xml);
      expect(document.sections.single.header.single.properties.numId, 1);
    },
  );

  for (final operation in ['listLevel', 'listOutlineDefault']) {
    test(
      '$operation preserves balanced fields and rejects unrelated unbalanced fields',
      () async {
        final input = _fixture(
          body:
              '<w:p><w:pPr>$_list</w:pPr>'
              '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
              '<w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
              '<w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>1</w:t></w:r>'
              '<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>',
        );
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        await session.run(
          _plan([operation == 'listLevel' ? _select(1) : _outline()]),
        );
        final xml = OpcPackage.openBytes(
          session.bytes,
        ).getPart('/word/document.xml')!.readText();
        for (final token in [
          'fldCharType="begin"',
          ' PAGE ',
          'fldCharType="separate"',
          'fldCharType="end"',
        ]) {
          expect(xml, contains(token));
        }
        final document = _read(input);
        document.sections.single.header.add(
          WmlParagraph(
            inlines: [WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin)],
          ),
        );
        _refuses(document, {
          'op': operation,
          'paragraph': 0,
          if (operation == 'listLevel') 'level': 1,
        });
      },
    );
  }

  test(
    'late invalid level rolls back prior outline creation and recording',
    () async {
      final input = _fixture(properties: '', numbering: '');
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      session.startRecording('Rejected level changes');
      final macro = _plan([
        _outline(),
        _select(8),
        OfficeMacroStep(
          tool: 'docx.listLevel',
          arguments: {'paragraph': 0, 'delta': 1},
        ),
      ]);
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(macro),
          throwsA(
            isA<OfficeMacroException>().having(
              (error) => error.stepIndex,
              'stepIndex',
              2,
            ),
          ),
        );
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
      expect(session.stopRecording().steps, isEmpty);
    },
  );
}
