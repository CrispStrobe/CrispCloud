import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/fidelity/office_steps.dart' as commands;
import '../tool/fidelity/word_steps.dart' as cli;

const _fixtures = 'test/fixtures/fidelity';

List<XmlElement> _elements(XmlElement root, String localName) => [
  for (final child in root.childElements) ...[
    if (child.localName == localName) child,
    ..._elements(child, localName),
  ],
];

XmlElement _part(OpcPackage package, String uri) =>
    XmlDocument.parse(package.getPart(uri)!.readText()).root!;

WmlDocument _styledDocument({
  bool alias = false,
  bool existingRunProperties = true,
}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>'
        '<w:p><w:pPr><w:pStyle w:val="Article"/></w:pPr>'
        '<w:r><w:t>Styled text</w:t></w:r></w:p><w:sectPr/>'
        '</w:body></w:document>',
      );
  final prefix = alias ? 'n' : 'w';
  final namespace = alias ? ' xmlns:w="urn:unrelated-extension"' : '';
  package.createPart(
    '/word/styles.xml',
    OfficeContentTypes.wordStyles,
    utf8.encode(
      '<$prefix:styles xmlns:$prefix="${OfficeNamespaces.w}"$namespace>'
      '<$prefix:style $prefix:type="paragraph" $prefix:styleId="Article">'
      '<$prefix:name $prefix:val="Article"/>'
      '${existingRunProperties ? '<$prefix:rPr><$prefix:color $prefix:val="000000"/><$prefix:sz $prefix:val="22"/></$prefix:rPr>' : ''}'
      '</$prefix:style>'
      '<$prefix:style $prefix:type="character" $prefix:styleId="Accent">'
      '<$prefix:name $prefix:val="Accent"/><$prefix:rPr>'
      '<$prefix:b/><$prefix:color $prefix:val="CC5500"/>'
      '<$prefix:sz $prefix:val="36"/></$prefix:rPr></$prefix:style>'
      '</$prefix:styles>',
    ),
  );
  package
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.styles, target: 'styles.xml');
  return WordDeserializer().read(package);
}

WmlDocument _listedDocument({required bool inherited}) {
  final package = OpcPackage.openBytes(
    File('$_fixtures/word.docx').readAsBytesSync(),
  );
  if (!inherited) {
    final root = _part(package, '/word/document.xml');
    final paragraph = root
        .firstChild('body')!
        .childrenNamed('p')
        .firstWhere((paragraph) => paragraph.text == 'List item');
    final properties = paragraph.firstChild('pPr')!;
    properties.children.removeWhere(
      (node) => node is XmlElement && node.localName == 'pStyle',
    );
    properties.addChild(
      XmlDocument.parse(
        '<w:numPr xmlns:w="${OfficeNamespaces.w}">'
        '<w:ilvl w:val="0"/><w:numId w:val="5"/></w:numPr>',
      ).root!,
    );
    package
        .getPart('/word/document.xml')!
        .writeText(XmlDocument(root: root).toXmlString());
  }
  return WordDeserializer().read(package);
}

void main() {
  for (final inherited in [false, true]) {
    test(
      'list clear suppresses imported numbering for three cycles, inherited=$inherited',
      () async {
        var document = _listedDocument(inherited: inherited);
        final original = document.paragraphs.elementAt(3).properties.copy();
        expect(original.numId, 5);
        cli.applyStep(document, {'op': 'listClear', 'paragraph': 3});
        final cleared = document.paragraphs.elementAt(3);
        expect(cleared.properties.numId, isNull);
        expect(cleared.properties.numberingSuppressed, isTrue);
        expect(original.numberingSuppressed, isFalse);
        expect(
          WmlClone.paragraph(cleared).properties.numberingSuppressed,
          isTrue,
        );
        // Both style resolution paths must retain the direct removal.
        WordStyles.resolveOntoParagraph(cleared, document: document);
        WordDeserializer().refreshStyles(document);
        for (var cycle = 0; cycle < 3; cycle++) {
          final bytes = await OfficeIsolateSave.word(document);
          final package = OpcPackage.openBytes(bytes);
          final paragraph = _part(package, '/word/document.xml')
              .firstChild('body')!
              .childrenNamed('p')
              .firstWhere((paragraph) => paragraph.text == 'List item');
          expect(
            paragraph
                .firstChild('pPr')!
                .firstChild('numPr')!
                .firstChild('numId')!
                .getAttribute('val'),
            '0',
          );
          final sourceStyle = _part(package, '/word/styles.xml')
              .childrenNamed('style')
              .firstWhere(
                (style) => style.getAttribute('styleId') == 'ListCustom',
              );
          expect(
            sourceStyle
                .firstChild('pPr')!
                .firstChild('numPr')!
                .firstChild('numId')!
                .getAttribute('val'),
            '5',
          );
          document = WordDeserializer().readBytes(bytes);
          final properties = document.paragraphs.elementAt(3).properties;
          expect(properties.numId, isNull);
          expect(properties.listLabel, isNull);
          expect(properties.numberingSuppressed, isTrue);
          expect(properties.styleId, inherited ? 'ListCustom' : isNull);
        }
        cli.applyStep(
          document,
          inherited
              ? {'op': 'applyStyle', 'paragraph': 3, 'style': 'ListCustom'}
              : {'op': 'list', 'paragraph': 3, 'numbered': true},
        );
        expect(
          document.paragraphs.elementAt(3).properties.numberingSuppressed,
          isFalse,
        );
        document = WordDeserializer().readBytes(
          await OfficeIsolateSave.word(document),
        );
        expect(
          document.paragraphs.elementAt(3).properties.numId,
          greaterThan(0),
        );
        expect(
          document.paragraphs.elementAt(3).properties.listLabel,
          isNotNull,
        );
      },
    );
  }

  test(
    'new styled paragraph keeps explicit list removal during refresh',
    () async {
      var document = _listedDocument(inherited: true);
      final paragraph = WmlParagraph(
        properties: WmlParagraphProps(styleId: 'ListCustom', numId: 5),
        inlines: [WmlRun(text: 'New unnumbered paragraph')],
      );
      document.sections.first.blocks.add(paragraph);
      WordLists.clear(paragraph);
      WordDeserializer().refreshStyles(document);
      for (var cycle = 0; cycle < 3; cycle++) {
        final properties = document.paragraphs.last.properties;
        expect(properties.numId, isNull);
        expect(properties.numberingSuppressed, isTrue);
        expect(properties.listLabel, isNull);
        document = WordDeserializer().readBytes(
          await OfficeIsolateSave.word(document),
        );
      }
    },
  );

  test(
    'runFormat rejects empty ranges and empty paragraphs without typing state',
    () {
      for (final text in ['', 'Existing text']) {
        final document = WmlDocument.empty(text: text);
        expect(
          () => cli.applyStep(document, {
            'op': 'runFormat',
            'paragraph': 0,
            'start': 0,
            'end': 0,
            'bold': true,
          }),
          throwsA(
            isA<ArgumentError>().having(
              (error) => '$error',
              'message',
              contains('non-empty text range'),
            ),
          ),
        );
        expect(
          document.paragraphs.single.inlines.whereType<WmlRun>().every(
            (run) => !run.properties.bold,
          ),
          isTrue,
        );
      }
    },
  );

  test(
    'empty range reports its indexed CLI step and leaves output untouched',
    () async {
      final directory = Directory.systemTemp.createTempSync('office-range-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final output = File('${directory.path}/result.docx')
        ..writeAsStringSync('existing output');
      final script = File('${directory.path}/steps.json')
        ..writeAsStringSync(
          jsonEncode([
            {'op': 'replaceText', 'paragraph': 2, 'text': 'Replacement'},
            {
              'op': 'runFormat',
              'paragraph': 2,
              'start': 3,
              'end': 3,
              'italic': true,
            },
          ]),
        );
      await expectLater(
        commands.execute([
          'modify',
          '$_fixtures/word.docx',
          script.path,
          output.path,
        ]),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Step 2 (runFormat)'),
              contains('non-empty text range'),
            ),
          ),
        ),
      );
      expect(output.readAsStringSync(), 'existing output');
    },
  );

  test(
    'image add is observable before removal and preserves the original',
    () async {
      var document = WordDeserializer().readBytes(
        File('$_fixtures/word.docx').readAsBytesSync(),
      );
      final original = document.visuals.single.visual;
      final originalBytes = List<int>.of(original.imageBytes!);
      final originalWidth = original.width;
      final originalHeight = original.height;
      final addedBytes = File(
        '$_fixtures/scripts/replacement.png',
      ).readAsBytesSync();
      cli.applyStep(document, {
        'op': 'imageAdd',
        'file': '$_fixtures/scripts/replacement.png',
        'width': 41.5,
        'height': 23.25,
        'title': 'Intermediate picture',
      });
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = await OfficeIsolateSave.word(document);
        final package = OpcPackage.openBytes(bytes);
        final root = _part(package, '/word/document.xml');
        final inline = _elements(root, 'inline');
        expect(inline, hasLength(2));
        final extent = inline.last.firstChild('extent')!;
        expect(extent.getAttribute('cx'), '${(41.5 * 12700).round()}');
        expect(extent.getAttribute('cy'), '${(23.25 * 12700).round()}');
        final id = _elements(inline.last, 'blip').single.getAttribute('embed');
        final relationships = package.relationshipsFor('/word/document.xml');
        final relationship = relationships.byId(id!)!;
        expect(relationship.type, RelationshipTypes.image);
        expect(
          package.getPart(relationships.resolve(relationship))!.readBytes(),
          addedBytes,
        );
        document = WordDeserializer().readBytes(bytes);
        final pictures = document.visuals.toList();
        expect(pictures, hasLength(2));
        expect(pictures.first.visual.imageBytes, originalBytes);
        expect(pictures.last.visual.imageBytes, addedBytes);
        expect(pictures.last.visual.width, closeTo(41.5, 0.001));
        expect(pictures.last.visual.height, closeTo(23.25, 0.001));
      }
      cli.applyStep(document, {'op': 'imageRemove', 'image': 1});
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = await OfficeIsolateSave.word(document);
        expect(
          _elements(
            _part(OpcPackage.openBytes(bytes), '/word/document.xml'),
            'blip',
          ),
          hasLength(1),
        );
        document = WordDeserializer().readBytes(bytes);
        final remaining = document.visuals.single.visual;
        expect(remaining.imageBytes, originalBytes);
        expect(remaining.width, closeTo(originalWidth, 0.001));
        expect(remaining.height, closeTo(originalHeight, 0.001));
      }
    },
  );

  test('split retains the right half of a formatted hyperlink run', () async {
    var document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(
              inlines: [
                WmlRun(text: 'Lead '),
                WmlRun(
                  text: 'styled right',
                  properties: WmlRunProps(
                    italic: true,
                    bold: true,
                    color: '123456',
                    fontSizeHalfPoints: 29,
                    underline: WmlUnderline.double,
                  ),
                  hyperlink: WmlHyperlink.fromTarget(
                    'https://example.test/rich',
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    cli.applyStep(document, {
      'op': 'paragraphSplit',
      'paragraph': 0,
      'offset': 8,
    });
    for (var cycle = 0; cycle < 3; cycle++) {
      final paragraphs = document.paragraphs.toList();
      expect(paragraphs.map((p) => p.text), ['Lead sty', 'led right']);
      final right = paragraphs.last.inlines.whereType<WmlRun>().single;
      expect(right.properties.italic, isTrue);
      expect(right.properties.bold, isTrue);
      expect(right.properties.color, '123456');
      expect(right.properties.fontSizeHalfPoints, 29);
      expect(right.properties.underline, WmlUnderline.double);
      expect(right.hyperlink?.url, 'https://example.test/rich');
      final bytes = await OfficeIsolateSave.word(document);
      final package = OpcPackage.openBytes(bytes);
      final last = _part(
        package,
        '/word/document.xml',
      ).firstChild('body')!.childrenNamed('p').last;
      final hyperlink = last.firstChild('hyperlink')!;
      final runProperties = hyperlink.firstChild('r')!.firstChild('rPr')!;
      expect(runProperties.firstChild('color')!.getAttribute('val'), '123456');
      expect(runProperties.firstChild('sz')!.getAttribute('val'), '29');
      expect(runProperties.firstChild('u')!.getAttribute('val'), 'double');
      document = WordDeserializer().readBytes(bytes);
    }
  });

  test(
    'explicit false and default values survive subsequent style refresh',
    () async {
      var document = _styledDocument();
      cli.applyStep(document, {
        'op': 'runFormat',
        'paragraph': 0,
        'bold': false,
        'color': '000000',
        'size': 11,
      });
      cli.applyStep(document, {
        'op': 'styleDefinition',
        'style': 'Article',
        'rPr': {
          'b': <String, Object?>{},
          'color': {'val': '0055CC'},
          'sz': {'val': '40'},
        },
      });
      cli.applyStep(document, {
        'op': 'characterStyle',
        'paragraph': 0,
        'run': 0,
        'style': 'Accent',
      });
      for (var cycle = 0; cycle < 3; cycle++) {
        final run = document.paragraphs.first.inlines
            .whereType<WmlRun>()
            .single;
        expect(run.properties.bold, isFalse);
        expect(run.properties.color, '000000');
        expect(run.properties.fontSizeHalfPoints, 22);
        final bytes = await OfficeIsolateSave.word(document);
        final root = _part(OpcPackage.openBytes(bytes), '/word/document.xml');
        final properties = _elements(root, 'rPr').single;
        expect(properties.firstChild('b')!.getAttribute('val'), '0');
        expect(properties.firstChild('color')!.getAttribute('val'), '000000');
        expect(properties.firstChild('sz')!.getAttribute('val'), '22');
        document = WordDeserializer().readBytes(bytes);
      }
    },
  );

  for (final existingProperties in [false, true]) {
    test(
      'style edit binds Word namespace in aliased source, existing=$existingProperties',
      () async {
        var document = _styledDocument(
          alias: true,
          existingRunProperties: existingProperties,
        );
        cli.applyStep(document, {
          'op': 'styleDefinition',
          'style': 'Article',
          'rPr': {
            'color': {'val': '0077AA'},
          },
        });
        for (var cycle = 0; cycle < 3; cycle++) {
          final bytes = await OfficeIsolateSave.word(document);
          final root = _part(OpcPackage.openBytes(bytes), '/word/styles.xml');
          final style = root
              .childrenNamed('style')
              .firstWhere((s) => s.getAttribute('styleId') == 'Article');
          final properties = style.firstChild('rPr')!;
          final color = properties.firstChild('color')!;
          expect(properties.namespaceUri, OfficeNamespaces.w);
          expect(color.namespaceUri, OfficeNamespaces.w);
          expect(
            color.getAttribute('val', namespaceUri: OfficeNamespaces.w),
            '0077AA',
          );
          expect(
            root.attributes
                .firstWhere((attribute) => attribute.qualifiedName == 'xmlns:w')
                .value,
            'urn:unrelated-extension',
          );
          document = WordDeserializer().readBytes(bytes);
          expect(
            document.paragraphs.first.inlines
                .whereType<WmlRun>()
                .single
                .properties
                .color,
            '0077AA',
          );
        }
      },
    );
  }

  test(
    'heading split keeps one bookmark identity through three exports',
    () async {
      var document = WmlDocument.empty(text: 'Alpha Beta');
      cli.applyStep(document, {'op': 'heading', 'paragraph': 0, 'level': 2});
      final bookmark = document.paragraphs.first.properties.bookmarkName;
      cli.applyStep(document, {
        'op': 'paragraphSplit',
        'paragraph': 0,
        'offset': 5,
      });
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = await OfficeIsolateSave.word(document);
        final root = _part(OpcPackage.openBytes(bytes), '/word/document.xml');
        final starts = _elements(root, 'bookmarkStart');
        final ends = _elements(root, 'bookmarkEnd');
        expect(starts, hasLength(1));
        expect(ends, hasLength(1));
        expect(starts.single.getAttribute('name'), bookmark);
        expect(
          starts.single.getAttribute('id'),
          ends.single.getAttribute('id'),
        );
        document = WordDeserializer().readBytes(bytes);
        expect(document.paragraphs.map((p) => p.text), ['Alpha', ' Beta']);
        expect(document.paragraphs.map((p) => p.properties.headingLevel), [
          2,
          2,
        ]);
      }
    },
  );

  test(
    'splitting a restarted list continues numbering in the new paragraph',
    () async {
      var document = WmlDocument.empty(text: 'First second');
      cli.applyStep(document, {'op': 'list', 'paragraph': 0, 'numbered': true});
      cli.applyStep(document, {'op': 'listRestart', 'paragraph': 0, 'at': 4});
      cli.applyStep(document, {
        'op': 'paragraphSplit',
        'paragraph': 0,
        'offset': 5,
      });
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = await OfficeIsolateSave.word(document);
        document = WordDeserializer().readBytes(bytes);
        expect(document.paragraphs.map((p) => p.properties.listLabel?.trim()), [
          '4.',
          '5.',
        ]);
        expect(
          document.paragraphs.map((p) => p.properties.numId).toSet(),
          hasLength(1),
        );
        expect(document.paragraphs.map((p) => p.text), ['First', ' second']);
      }
    },
  );
}
