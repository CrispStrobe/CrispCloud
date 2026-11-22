import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:style-assignment-tests';
const _styles = '''
<w:style w:type="paragraph" w:styleId="Base" w:default="1"><w:name w:val="Normal"/><w:pPr><w:spacing w:after="0"/></w:pPr><w:rPr><w:sz w:val="22"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Target" w:customStyle="1"><w:name w:val="Report Body"/><w:basedOn w:val="Base"/><w:pPr><w:spacing w:after="180"/></w:pPr><w:rPr><w:sz w:val="32"/><w:b/></w:rPr></w:style>
<w:style w:type="character" w:styleId="Emphasis"><w:name w:val="Emphasis"/><w:rPr><w:i/></w:rPr></w:style>
''';
const _body = '''
<w:p><w:pPr><w:pStyle w:val="Base"/></w:pPr><w:r><w:t>Selected</w:t></w:r></w:p>
<w:p><w:r><w:t>Other</w:t></w:r></w:p>
''';

OpcPackage _package({
  String styles = _styles,
  String body = _body,
  String prefix = 'w',
}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<$prefix:document xmlns:$prefix="$_w" xmlns:x="$_x">'
        '<$prefix:body>${body.replaceAll('w:', '$prefix:')}</$prefix:body></$prefix:document>',
      );
  package
      .createPart('/word/styles.xml', OfficeContentTypes.wordStyles)
      .writeText(
        '<$prefix:styles xmlns:$prefix="$_w" xmlns:x="$_x">'
        '${styles.replaceAll('w:', '$prefix:')}</$prefix:styles>',
      );
  package
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.styles, target: 'styles.xml');
  return package;
}

void _assign(
  WmlDocument document, {
  String? name = 'Report Body',
  int? builtin,
}) => WordDeserializer().editParagraphStyle(
  document,
  document.paragraphs.first,
  name: builtin == null ? name : null,
  builtin: builtin,
);

void _refusesWithoutMutation(
  WmlDocument document, {
  String? name = 'Report Body',
  int? builtin,
  Matcher? matcher,
}) {
  final paragraph = document.paragraphs.first;
  final properties = paragraph.properties;
  final inlines = paragraph.inlines;
  final runProperties = paragraph.inlines
      .whereType<WmlRun>()
      .map((run) => run.properties)
      .toList();
  expect(
    () => _assign(document, name: name, builtin: builtin),
    throwsA(matcher ?? isA<UnsupportedError>()),
  );
  expect(paragraph.properties, same(properties));
  expect(paragraph.inlines, same(inlines));
  for (final (index, run) in paragraph.inlines.whereType<WmlRun>().indexed) {
    expect(run.properties, same(runProperties[index]));
  }
}

void main() {
  test(
    'primary names resolve case-insensitively and preserve live identities',
    () {
      final document = WordDeserializer().read(_package());
      final selected = document.paragraphs.first;
      final run = selected.inlines.single as WmlRun;
      final other = document.paragraphs.last;
      final otherProperties = other.properties;
      final otherRun = (other.inlines.single as WmlRun).properties;
      final styles = document.package!.getPart('/word/styles.xml')!.readText();
      _assign(document, name: 'rEPORT bODY');
      expect(document.paragraphs.first, same(selected));
      expect(selected.inlines.single, same(run));
      expect(selected.properties.styleId, 'Target');
      expect(selected.properties.spacingAfter, 9);
      expect(run.properties.fontSizePoints, 16);
      expect(run.properties.bold, isTrue);
      expect(other.properties, same(otherProperties));
      expect((other.inlines.single as WmlRun).properties, same(otherRun));
      expect(document.package!.getPart('/word/styles.xml')!.readText(), styles);
      for (final missing in [
        'Target',
        ' Report Body',
        'Report Body ',
        'Report  Body',
      ]) {
        _refusesWithoutMutation(
          document,
          name: missing,
          matcher: isA<ArgumentError>(),
        );
      }
    },
  );

  test('same-value default assignment writes an explicit sparse reference', () {
    var document = WordDeserializer().read(
      _package(body: '<w:p><w:r><w:t>Text</w:t></w:r></w:p>'),
    );
    expect(document.paragraphs.single.properties.styleId, isNull);
    _assign(document, builtin: -1);
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(document.paragraphs.single.properties.styleId, 'Base');
      final xml = document.paragraphs.single.properties.sourcePropertiesXml!;
      final root = XmlDocument.parse(xml).root!;
      expect(
        root
            .firstChild('pStyle', namespaceUri: _w)!
            .getAttribute('val', namespaceUri: _w),
        'Base',
      );
      expect(root.firstChild('spacing', namespaceUri: _w), isNull);
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
    }
  });

  for (final packet in ['pPr', 'rPr']) {
    test('$packet preserves a foreign w binding on a native alias root', () {
      final properties =
          '<s:$packet xmlns:s="$_w" xmlns:w="$_x" w:token="root">'
          '${packet == 'pPr' ? '<s:pStyle s:val="Base"/>' : '<s:rStyle s:val="Emphasis"/>'}'
          '<w:extension w:token="child"/></s:$packet>';
      var document = WordDeserializer().read(
        _package(
          body:
              '<w:p>${packet == 'pPr' ? properties : ''}'
              '<w:r>${packet == 'rPr' ? properties : ''}'
              '<w:t>Selected</w:t></w:r></w:p>',
        ),
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        _assign(document);
        final target = document.paragraphs.single;
        final run = target.inlines.single as WmlRun;
        expect(target.properties.styleId, 'Target');
        expect(run.properties.bold, isTrue);
        expect(run.properties.italic, packet == 'rPr');
        final source = packet == 'pPr'
            ? target.properties.sourcePropertiesXml!
            : run.properties.sourcePropertiesXml!;
        final root = XmlDocument.parse(source).root!;
        expect(root.namespaceUri, _w);
        expect(root.getAttribute('token', namespaceUri: _x), 'root');
        expect(
          root
              .firstChild('extension', namespaceUri: _x)!
              .getAttribute('token', namespaceUri: _x),
          'child',
        );
        expect(root.firstChild('extension', namespaceUri: _w), isNull);
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
      }
    });
  }

  const builtins = <int, String>{
    -1: 'Normal',
    -2: 'heading 1',
    -3: 'heading 2',
    -4: 'heading 3',
    -5: 'heading 4',
    -6: 'heading 5',
    -7: 'heading 6',
    -8: 'heading 7',
    -9: 'heading 8',
    -10: 'heading 9',
    -35: 'caption',
    -63: 'title',
    -75: 'subtitle',
  };
  for (final entry in builtins.entries) {
    test(
      'builtin ${entry.key} resolves existing primary name independent of ID',
      () {
        final catalog = builtins.entries
            .map(
              (entry) =>
                  '<w:style w:type="paragraph" w:styleId="Native${-entry.key}"><w:name w:val="${entry.value}"/></w:style>',
            )
            .join();
        final document = WordDeserializer().read(
          _package(
            styles: catalog,
            body: '<w:p><w:r><w:t>Text</w:t></w:r></w:p>',
          ),
        );
        _assign(document, builtin: entry.key);
        expect(
          document.paragraphs.single.properties.styleId,
          'Native${-entry.key}',
        );
      },
    );
  }

  test('custom primary name cannot impersonate a built-in constant', () {
    final document = WordDeserializer().read(
      _package(styles: _styles.replaceAll('Report Body', 'heading 1')),
    );
    _refusesWithoutMutation(document, builtin: -2);
    _assign(document, name: 'heading 1');
    expect(document.paragraphs.first.properties.styleId, 'Target');
  });

  for (final prefix in ['w', 'word']) {
    test(
      'native prefix $prefix preserves foreign and nested style lookalikes',
      () {
        var document = WordDeserializer().read(
          _package(
            prefix: prefix,
            body: '''
<w:p><w:pPr><x:pStyle x:val="foreign" w:val="Target"/>
<w:pStyle x:val="decoy" w:val="Base" x:tag="keep"><x:annotation x:value="retained"/></w:pStyle>
<x:metadata><w:pStyle w:val="Target"/></x:metadata>
<w:spacing w:before="60"/></w:pPr>
<w:r><w:rPr><x:rStyle w:val="Missing"/><w:rStyle w:val="Emphasis"/>
<x:metadata><w:rStyle w:val="Missing"/></x:metadata><w:color w:val="AABBCC"/></w:rPr><w:t>Styled</w:t></w:r></w:p>''',
          ),
        );
        expect(document.paragraphs.single.properties.styleId, 'Base');
        expect(
          (document.paragraphs.single.inlines.single as WmlRun)
              .properties
              .styleId,
          'Emphasis',
        );
        _assign(document);
        for (var cycle = 0; cycle < 3; cycle++) {
          final paragraph = document.paragraphs.single;
          final run = paragraph.inlines.single as WmlRun;
          expect(paragraph.properties.styleId, 'Target');
          expect(paragraph.properties.spacingBefore, 3);
          expect(paragraph.properties.spacingAfter, 9);
          expect(run.properties.fontSizePoints, 16);
          expect(run.properties.italic, isTrue);
          expect(run.properties.bold, isTrue);
          expect(run.properties.color, 'AABBCC');
          final direct = XmlDocument.parse(
            paragraph.properties.sourcePropertiesXml!,
          ).root!;
          final pStyle = direct.firstChild('pStyle', namespaceUri: _w)!;
          expect(pStyle.getAttribute('val', namespaceUri: _x), 'decoy');
          expect(pStyle.getAttribute('tag', namespaceUri: _x), 'keep');
          expect(pStyle.firstChild('annotation', namespaceUri: _x), isNotNull);
          expect(direct.firstChild('pStyle', namespaceUri: _x), isNotNull);
          expect(direct.firstChild('metadata', namespaceUri: _x), isNotNull);
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
      },
    );
  }

  test(
    'table context and direct run overrides survive targeted style changes',
    () {
      final package = _package(
        styles:
            '$_styles<w:style w:type="table" w:styleId="TableTheme"><w:name w:val="Table Theme"/><w:pPr><w:spacing w:before="180"/></w:pPr><w:rPr><w:i/></w:rPr></w:style>',
        body: '''
<w:tbl><w:tblPr><w:tblStyle w:val="TableTheme"/></w:tblPr><w:tblGrid><w:gridCol w:w="2000"/></w:tblGrid>
<w:tr><w:tc><w:p><w:r><w:rPr><w:b w:val="0"/></w:rPr><w:t>Cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
<w:p><w:r><w:t>Outside</w:t></w:r></w:p>''',
      );
      var document = WordDeserializer().read(package);
      _assign(document);
      for (var cycle = 0; cycle < 3; cycle++) {
        final paragraph = document.paragraphs.first;
        final run = paragraph.inlines.single as WmlRun;
        expect(paragraph.properties.spacingBefore, 9);
        expect(paragraph.properties.spacingAfter, 9);
        expect(run.properties.italic, isTrue);
        expect(run.properties.bold, isFalse);
        expect(run.properties.fontSizePoints, 16);
        expect(document.paragraphs.last.properties.styleId, isNull);
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
      }
    },
  );

  test(
    'changing a table paragraph style drops obsolete inherited spacing immediately',
    () {
      final package = _package(
        styles: '''
<w:style w:type="paragraph" w:styleId="Old"><w:name w:val="Old"/><w:pPr><w:spacing w:after="240" w:line="360"/></w:pPr></w:style>
<w:style w:type="paragraph" w:styleId="Target"><w:name w:val="Report Body"/></w:style>
<w:style w:type="table" w:styleId="TableTheme"><w:name w:val="Table Theme"/><w:rPr><w:i/></w:rPr></w:style>''',
        body: '''
<w:tbl><w:tblPr><w:tblStyle w:val="TableTheme"/></w:tblPr><w:tblGrid><w:gridCol w:w="2000"/></w:tblGrid>
<w:tr><w:tc><w:p><w:pPr><w:pStyle w:val="Old"/></w:pPr><w:r><w:t>Cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl>''',
      );
      var document = WordDeserializer().read(package);
      expect(document.paragraphs.single.properties.spacingAfter, 12);
      expect(document.paragraphs.single.properties.lineSpacing, 1.5);
      _assign(document);
      for (var cycle = 0; cycle < 3; cycle++) {
        final paragraph = document.paragraphs.single;
        expect(paragraph.properties.spacingAfter, 0);
        expect(paragraph.properties.lineSpacing, 1);
        final source = XmlDocument.parse(
          paragraph.properties.sourcePropertiesXml!,
        ).root!;
        expect(source.firstChild('spacing', namespaceUri: _w), isNull);
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
      }
    },
  );

  test(
    'direct outline levels do not require a synthesized Heading style definition',
    () {
      var document = WordDeserializer().read(
        _package(
          body:
              '<w:p><w:pPr><w:outlineLvl w:val="0"/></w:pPr><w:r><w:t>Outline</w:t></w:r></w:p>',
        ),
      );
      expect(document.paragraphs.single.properties.styleId, 'Heading1');
      _assign(document);
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(document.paragraphs.single.properties.styleId, 'Target');
        expect(document.paragraphs.single.properties.headingLevel, 1);
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
      }
    },
  );

  test(
    'unresolved explicitly authored and pending styles are still refused',
    () {
      final source = WordDeserializer().read(
        _package(body: _body.replaceFirst('w:val="Base"', 'w:val="Missing"')),
      );
      _refusesWithoutMutation(source);
      final pending = WordDeserializer().read(_package());
      pending.paragraphs.first.properties.styleId = 'Missing';
      _refusesWithoutMutation(pending);
    },
  );

  final invalidStyles = <String, String>{
    'duplicate ID':
        '$_styles<w:style w:styleId="Target"><w:name w:val="Another"/></w:style>',
    'duplicate name case':
        '$_styles<w:style w:styleId="Other"><w:name w:val="REPORT BODY"/></w:style>',
    'duplicate primary name element': _styles.replaceFirst(
      '<w:name w:val="Report Body"/>',
      '<w:name w:val="Report Body"/><w:name w:val="Another"/>',
    ),
    'missing base': _styles.replaceAll('w:val="Base"', 'w:val="Missing"'),
    'cycle': _styles.replaceFirst(
      '<w:basedOn w:val="Base"/>',
      '<w:basedOn w:val="Target"/>',
    ),
    'wrong base type': _styles.replaceFirst(
      '<w:basedOn w:val="Base"/>',
      '<w:basedOn w:val="Emphasis"/>',
    ),
    'duplicate pPr': _styles.replaceFirst(
      '<w:pPr><w:spacing w:after="180"/></w:pPr>',
      '<w:pPr/><w:pPr/>',
    ),
    'style pStyle': _styles.replaceFirst(
      '<w:pPr><w:spacing w:after="180"/></w:pPr>',
      '<w:pPr><w:pStyle w:val="Base"/></w:pPr>',
    ),
    'invalid scalar': _styles.replaceFirst('<w:b/>', '<w:b w:val="perhaps"/>'),
    'invalid measurement': _styles.replaceFirst(
      'w:after="180"',
      'w:after="NaN"',
    ),
    'invalid font size': _styles.replaceFirst('w:val="32"', 'w:val="huge"'),
    'multiple paragraph defaults': _styles.replaceFirst(
      'w:customStyle="1"',
      'w:default="1"',
    ),
    'invalid custom marker': _styles.replaceFirst(
      'w:customStyle="1"',
      'w:customStyle="maybe"',
    ),
  };
  for (final entry in invalidStyles.entries) {
    test('rejects ${entry.key} atomically', () {
      final document = WordDeserializer().read(_package(styles: entry.value));
      _refusesWithoutMutation(document);
    });
  }

  test('selected character style is not accepted as paragraph style', () {
    _refusesWithoutMutation(
      WordDeserializer().read(_package()),
      name: 'Emphasis',
      matcher: isA<ArgumentError>(),
    );
  });

  test('missing active styles relationship cannot use a catalog fallback', () {
    final package = _package();
    final rels = package.relationshipsFor('/word/document.xml');
    rels.removeById(rels.firstByType(RelationshipTypes.styles)!.id);
    _refusesWithoutMutation(WordDeserializer().read(package));
  });

  test('duplicate active styles relationships are refused', () {
    final package = _package();
    package
        .relationshipsFor('/word/document.xml')
        .add(type: RelationshipTypes.styles, target: 'styles.xml');
    _refusesWithoutMutation(WordDeserializer().read(package));
  });

  test(
    'duplicate source pPr packets are refused before the lost packet is rewritten',
    () {
      final document = WordDeserializer().read(
        _package(body: _body.replaceFirst('<w:pPr>', '<w:pPr/><w:pPr>')),
      );
      _refusesWithoutMutation(document);
    },
  );

  test(
    'duplicate pending direct pStyle packets are refused without publication',
    () {
      final document = WordDeserializer().read(_package());
      document.paragraphs.first.properties.sourcePropertiesXml =
          '<w:pPr xmlns:w="$_w"><w:pStyle w:val="Base"/><w:pStyle w:val="Base"/></w:pPr>';
      _refusesWithoutMutation(document);
    },
  );

  test('style-bearing markup-compatibility alternatives are refused', () {
    final package = _package();
    final part = package.getPart('/word/styles.xml')!;
    part.writeText(
      part.readText().replaceFirst(
        '</w:styles>',
        '<mc:AlternateContent xmlns:mc="${OfficeNamespaces.mc}"><mc:Choice Requires="w"><w:style w:styleId="Alternative"><w:name w:val="Alternative"/></w:style></mc:Choice></mc:AlternateContent></w:styles>',
      ),
    );
    _refusesWithoutMutation(WordDeserializer().read(package));
  });

  test('shared paragraph ownership is refused', () {
    final document = WordDeserializer().read(_package());
    document.sections.first.blocks.add(document.paragraphs.first);
    _refusesWithoutMutation(document, matcher: isA<StateError>());
  });

  test(
    'shared live run ownership is refused without affecting either paragraph',
    () {
      final document = WordDeserializer().read(_package());
      document.paragraphs.last.inlines = [
        document.paragraphs.first.inlines.single,
      ];
      _refusesWithoutMutation(document, matcher: isA<StateError>());
    },
  );

  test(
    'shared property objects on distinct runs stay independent after assignment',
    () {
      final document = WordDeserializer().read(_package());
      final first = document.paragraphs.first.inlines.single as WmlRun;
      final other = document.paragraphs.last.inlines.single as WmlRun;
      other.properties = first.properties;
      final original = other.properties;
      _assign(document);
      expect(other.properties, same(original));
      expect(first.properties, isNot(same(original)));
      expect(other.properties.fontSizePoints, 11);
      expect(first.properties.fontSizePoints, 16);
    },
  );

  test(
    'effective numbering changes are refused and existing list metadata stays untouched',
    () {
      final styles = _styles.replaceFirst(
        '<w:pPr><w:spacing w:after="180"/></w:pPr>',
        '<w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="7"/></w:numPr></w:pPr>',
      );
      final document = WordDeserializer().read(_package(styles: styles));
      _refusesWithoutMutation(document);
    },
  );

  test('unchanged direct numbering preserves labels and restart metadata', () {
    var document = WordDeserializer().read(
      _package(
        body: _body.replaceFirst(
          '<w:pStyle w:val="Base"/>',
          '<w:pStyle w:val="Base"/><w:numPr><w:ilvl w:val="1"/><w:numId w:val="7"/></w:numPr>',
        ),
      ),
    );
    final originalLabel = document.paragraphs.first.properties.listLabel;
    _assign(document);
    expect(document.paragraphs.first.properties.numId, 7);
    expect(document.paragraphs.first.properties.ilvl, 1);
    expect(document.paragraphs.first.properties.listLabel, originalLabel);
    document = WordDeserializer().readBytes(
      WordSerializer().writeBytes(document),
    );
    expect(document.paragraphs.first.properties.styleId, 'Target');
    expect(document.paragraphs.first.properties.listLabel, originalLabel);
  });

  test(
    'style-linked numbering is refused even when modeled IDs and levels match',
    () {
      final styleNumber = '<w:numPr><w:numId w:val="7"/></w:numPr>';
      final styles = _styles.replaceAll('<w:pPr>', '<w:pPr>$styleNumber');
      final package = _package(styles: styles);
      package
          .createPart('/word/numbering.xml', OfficeContentTypes.wordNumbering)
          .writeText(
            '''
<w:numbering xmlns:w="$_w"><w:abstractNum w:abstractNumId="2">
<w:lvl w:ilvl="0"><w:pStyle w:val="Base"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl>
<w:lvl w:ilvl="1"><w:pStyle w:val="Target"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1.%2."/></w:lvl>
</w:abstractNum><w:num w:numId="7"><w:abstractNumId w:val="2"/></w:num></w:numbering>''',
          );
      package
          .relationshipsFor('/word/document.xml')
          .add(type: RelationshipTypes.numbering, target: 'numbering.xml');
      final document = WordDeserializer().read(package);
      expect(document.paragraphs.first.properties.numId, 7);
      expect(document.paragraphs.first.properties.ilvl, 0);
      _refusesWithoutMutation(document);
    },
  );

  test('cyclic block ownership is refused before field traversal', () {
    final document = WordDeserializer().read(_package());
    final frame = WmlFrame();
    frame.blocks.add(frame);
    document.sections.first.blocks.add(frame);
    _refusesWithoutMutation(document, matcher: isA<StateError>());
  });

  test('a body run shared with a generated TOC is refused', () {
    final document = WordDeserializer().read(_package());
    final toc = WmlToc();
    toc.titleParagraph.inlines = [document.paragraphs.first.inlines.single];
    document.sections.first.blocks.add(toc);
    _refusesWithoutMutation(document, matcher: isA<StateError>());
  });

  test('a body run shared with a native TOC cache is refused', () {
    final document = WordDeserializer().read(_package());
    final source = WmlParagraph(
      inlines: [document.paragraphs.first.inlines.single],
    );
    final toc = WmlToc(
      sourcePresentation: WmlTocPresentation(
        configuration: (1, 3, true, null, null, null),
        paragraphs: [WmlTocSourceParagraph(paragraph: source)],
      ),
    );
    document.sections.first.blocks.add(toc);
    final original = (source.inlines.single as WmlRun).properties;
    _refusesWithoutMutation(document, matcher: isA<StateError>());
    expect((source.inlines.single as WmlRun).properties, same(original));
  });

  test('an independent native TOC cache does not block body restyling', () {
    final document = WordDeserializer().read(_package());
    final source = WmlParagraph(inlines: [WmlRun(text: 'Cached result')]);
    final toc = WmlToc(
      sourcePresentation: WmlTocPresentation(
        configuration: (1, 3, true, null, null, null),
        paragraphs: [WmlTocSourceParagraph(paragraph: source)],
      ),
    );
    document.sections.first.blocks.add(toc);
    final original = (source.inlines.single as WmlRun).properties;
    _assign(document);
    expect(document.paragraphs.first.properties.styleId, 'Target');
    expect((source.inlines.single as WmlRun).properties, same(original));
    expect(source.text, 'Cached result');
  });

  test('generated TOC paragraph targets are explicitly refused', () {
    final document = WordDeserializer().read(_package());
    final toc = WmlToc();
    document.sections.first.blocks.add(toc);
    final properties = toc.titleParagraph.properties;
    expect(
      () => WordDeserializer().editParagraphStyle(
        document,
        toc.titleParagraph,
        name: 'Report Body',
      ),
      throwsUnsupportedError,
    );
    expect(toc.titleParagraph.properties, same(properties));
  });

  for (final selector in <Map<String, Object?>>[
    {},
    {'name': 'Report Body', 'builtin': -1},
    {'name': ''},
    {'name': 'A\tB'},
    {'name': 'A\nB'},
    {'name': '\ud800'},
    {'name': true},
    {'builtin': -2.0},
    {'builtin': 1},
    {'builtin': -11},
  ]) {
    test('native operation rejects invalid selector $selector', () {
      final document = WordDeserializer().read(_package());
      final properties = document.paragraphs.first.properties;
      expect(
        () => native.applyStep(document, {
          'op': 'paragraphStyle',
          'paragraph': 0,
          ...selector,
        }),
        throwsArgumentError,
      );
      expect(document.paragraphs.first.properties, same(properties));
    });
  }
}
