import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _meta = 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _namespaces =
    'xmlns:office="$_office" xmlns:text="$_text" xmlns:style="$_style" '
    'xmlns:meta="$_meta" xmlns:fo="$_fo" xmlns:x="urn:note-style-extension"';

ZoteroCitation _citation(String id) => ZoteroCitation.fromJson({
  'citationID': id,
  'citationItems': [
    {
      'id': 'http://zotero.org/users/42/items/ABCD1234',
      'uris': ['http://zotero.org/users/42/items/ABCD1234'],
      'locator': '17',
      'label': 'page',
      'futureItem': {'keep': true},
    },
  ],
  'properties': {'plainCitation': '(Author, 17)'},
  'futureRoot': [42, null, 'retained'],
});

String _data({String fieldType = 'ReferenceMark'}) => jsonEncode({
  'dataVersion': 4,
  'style': {'styleID': 'http://www.zotero.org/styles/apa'},
  'prefs': {'fieldType': fieldType, 'noteType': 0},
  'futurePreferences': 'retained',
});

String _mark(String id) {
  final name = encodeXmlAttribute(
    'ZOTERO_ITEM CSL_CITATION ${jsonEncode(_citation(id).toJson())} RND0123456789',
  );
  return '<text:reference-mark-start text:name="$name"/>'
      '(Author, 17)<text:reference-mark-end text:name="$name"/>';
}

String _markerStyle(
  String name, {
  String? parent,
  String? properties = 'style:text-position="super 65%"',
  String extra = '',
}) =>
    '<style:style style:family="text" style:name="$name"'
    '${parent == null ? '' : ' style:parent-style-name="$parent"'}>'
    '${properties == null ? '' : '<style:text-properties $properties/>'}'
    '$extra</style:style>';

String _defaultText(String properties, {String extra = ''}) =>
    '<style:default-style style:family="text">'
    '<style:text-properties $properties>$extra</style:text-properties>'
    '</style:default-style>';

String _layout(
  String name, {
  String width = '612pt',
  String height = '792pt',
  String margin = '72pt',
  String children = '',
}) =>
    '<style:page-layout style:name="$name"><style:page-layout-properties '
    'fo:page-width="$width" fo:page-height="$height" fo:margin="$margin">'
    '$children</style:page-layout-properties></style:page-layout>';

String _master(
  String name,
  String layout, {
  String next = '',
  String content = '',
}) =>
    '<style:master-page style:name="$name" style:page-layout-name="$layout"'
    '${next.isEmpty ? '' : ' style:next-style-name="$next"'}>'
    '$content</style:master-page>';

Uint8List _package({
  bool endnote = true,
  String? markerStyles,
  String symbol = 'Marker',
  String anchor = 'Marker',
  String configurationAttributes = '',
  String configurationContent = '',
  String? bodyMaster,
  String layouts = '',
  String masters = '',
}) {
  final kind = endnote ? 'endnote' : 'footnote';
  final writer = ZipWriter();
  writer.addFile(
    'mimetype',
    utf8.encode('application/vnd.oasis.opendocument.text'),
    store: true,
  );
  writer.addFile(
    'content.xml',
    utf8.encode(
      '<office:document-content $_namespaces><office:body><office:text>'
      '<text:p${bodyMaster == null ? '' : ' text:style-name="Body"'}>Before '
      '<text:note text:id="note-one" text:note-class="$kind">'
      '<text:note-citation>1</text:note-citation><text:note-body>'
      '<text:p>${_mark('note-citation')} tail</text:p>'
      '</text:note-body></text:note> after</text:p>'
      '</office:text></office:body></office:document-content>',
    ),
  );
  writer.addFile(
    'styles.xml',
    utf8.encode(
      '<office:document-styles $_namespaces><office:styles>'
      '${markerStyles ?? _markerStyle('Marker')}'
      '${bodyMaster == null ? '' : '<style:style style:name="Body" style:family="paragraph" style:master-page-name="$bodyMaster"/>'}'
      '<text:notes-configuration text:note-class="$kind" style:num-format="1" '
      'text:start-value="1" text:citation-style-name="$symbol" '
      'text:citation-body-style-name="$anchor" $configurationAttributes>'
      '$configurationContent</text:notes-configuration>'
      '</office:styles><office:automatic-styles>$layouts</office:automatic-styles>'
      '<office:master-styles>$masters</office:master-styles>'
      '</office:document-styles>',
    ),
  );
  writer.addFile(
    'meta.xml',
    utf8.encode(
      '<office:document-meta $_namespaces><office:meta>'
      '<meta:user-defined meta:name="ZOTERO_PREF_1">'
      '${encodeXmlText(_data())}</meta:user-defined>'
      '</office:meta></office:document-meta>',
    ),
  );
  return writer.close();
}

void _checkNote(WmlDocument document, {required bool endnote}) {
  final note = (endnote ? document.endnotes : document.footnotes).single;
  final reference = document.paragraphs.single.inlines
      .whereType<WmlRun>()
      .singleWhere((run) => run.noteRefId != null);
  expect(reference.noteRefId, note.id);
  expect(reference.noteRefEndnote, endnote);
  expect(reference.properties.vertAlign, WmlVertAlign.superscript);
  final marker = note.paragraphs.single.inlines
      .whereType<WmlNoteMarker>()
      .single;
  expect(marker.endnote, endnote);
  expect(marker.properties.vertAlign, WmlVertAlign.superscript);
  expect(WordNoteNumbering(document).labelFor(note), '1');
  final field = WordZotero.fields(document).single;
  expect(identical(field.paragraph, note.paragraphs.single), isTrue);
  expect(field.start, 0);
  expect(field.end, '(Author, 17)'.length);
  expect(field.cachedText, '(Author, 17)');
  expect(field.canEdit, isTrue);
  expect(field.citation!.toJson(), _citation('note-citation').toJson());
  expect(note.paragraphs.single.text, '(Author, 17) tail');
}

Future<void> _reject(Uint8List bytes, {bool malformed = false}) async {
  final original = Uint8List.fromList(bytes);
  await expectLater(
    OdtDocumentReader.readBytes(bytes),
    malformed ? throwsA(isA<FormatException>()) : throwsUnsupportedError,
  );
  expect(bytes, original);
}

Iterable<XmlElement> _elements(XmlElement root, String ns, String name) sync* {
  if (root.namespaceUri == ns && root.localName == name) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, ns, name);
  }
}

WmlDocument _native({
  int sectionCount = 1,
  WmlSectionBreakKind finalBreak = WmlSectionBreakKind.nextPage,
}) {
  WmlParagraph noteParagraph(String id) => WmlParagraph(
    inlines: [
      WmlRun(
        text: '(Author, 17)',
        fieldInstruction: _citation(id).fieldInstruction,
      ),
    ],
  );
  return WmlDocument(
    zoteroDocumentData: _data(fieldType: 'Field'),
    footnotes: [
      WmlNote(
        id: 1,
        endnote: false,
        paragraphs: [noteParagraph('foot-citation')],
      ),
    ],
    endnotes: [
      WmlNote(
        id: 1,
        endnote: true,
        paragraphs: [noteParagraph('end-citation')],
      ),
    ],
    sections: [
      for (var index = 0; index < sectionCount; index++)
        WmlSection(
          sourceProperties: WmlSectionSource(
            xml:
                '<w:sectPr xmlns:w="${OfficeNamespaces.w}">'
                '<w:endnotePr><w:numFmt w:val="decimal"/></w:endnotePr>'
                '</w:sectPr>',
            values: const {},
          ),
          breakKind: index == sectionCount - 1
              ? finalBreak
              : WmlSectionBreakKind.nextPage,
          pageSize: WmlPageSize(
            width: 612 + 20.0 * index,
            height: 792 + 20.0 * index,
          ),
          blocks: [
            WmlParagraph(
              inlines: [
                WmlRun(text: 'Section $index '),
                if (index == sectionCount - 1) ...[
                  WmlRun(
                    text: '1',
                    noteRefId: 1,
                    properties: WmlRunProps(
                      vertAlign: WmlVertAlign.superscript,
                    ),
                  ),
                  WmlRun(text: ' between '),
                  WmlRun(
                    text: '1',
                    noteRefId: 1,
                    noteRefEndnote: true,
                    properties: WmlRunProps(
                      vertAlign: WmlVertAlign.superscript,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
    ],
  );
}

List<Object?> _nativeSnapshot(WmlDocument document) => [
  document.zoteroDocumentData,
  for (final section in document.sections)
    [
      section.breakKind,
      section.sourceProperties?.xml,
      section.pageSize.width,
      section.pageSize.height,
      for (final paragraph in section.blocks.whereType<WmlParagraph>())
        [
          paragraph.text,
          for (final run in paragraph.inlines.whereType<WmlRun>())
            [run.noteRefId, run.noteRefEndnote, run.properties.vertAlign],
        ],
    ],
  for (final note in [...document.footnotes, ...document.endnotes])
    [
      note.id,
      note.endnote,
      note.addReference,
      note.addReferenceSpace,
      note.text,
      note.hasReferenceMarkers,
    ],
  for (final field in WordZotero.fields(document))
    [field.instruction, field.cachedText, field.start, field.end],
];

void main() {
  group('configured note marker style resolution', () {
    for (final endnote in [false, true]) {
      test(
        'independent $endnote marker names retain native markers and fields',
        () async {
          final bytes = _package(
            endnote: endnote,
            symbol: 'RenamedSymbol',
            anchor: 'RenamedAnchor',
            markerStyles:
                '${_markerStyle('RenamedSymbol')}${_markerStyle('RenamedAnchor')}',
          );
          final original = Uint8List.fromList(bytes);
          var document = await OdtDocumentReader.readBytes(bytes);
          for (var cycle = 0; cycle < 3; cycle++) {
            _checkNote(document, endnote: endnote);
            document = WordDeserializer().readBytes(
              WordSerializer().writeBytes(document),
            );
          }
          expect(bytes, original);
        },
      );
    }

    final supported = <String, String>{
      'named parent':
          '${_markerStyle('Parent')}${_markerStyle('Marker', parent: 'Parent', properties: null)}',
      'text family default':
          '${_defaultText('style:text-position="super 65%"')}${_markerStyle('Marker', properties: null)}',
      'parent 58 percent overridden by 65':
          '${_markerStyle('Parent', properties: 'style:text-position="super 58%"')}${_markerStyle('Marker', parent: 'Parent')}',
      'default 58 percent overridden by 65':
          '${_defaultText('style:text-position="super 58%"')}${_markerStyle('Marker')}',
      'whitespace separated explicit position': _markerStyle(
        'Marker',
        properties: 'style:text-position="  super   65%  "',
      ),
    };
    for (final entry in supported.entries) {
      test('${entry.key} resolves to the exact supported marker', () async {
        final bytes = _package(markerStyles: entry.value);
        final original = Uint8List.fromList(bytes);
        final document = await OdtDocumentReader.readBytes(bytes);
        _checkNote(document, endnote: true);
        expect(bytes, original);
      });
    }

    for (final position in [
      'super',
      'super 58%',
      '0%',
      'sub 65%',
      'super 65.0%',
    ]) {
      for (final role in ['symbol', 'anchor']) {
        test('$role refuses unrepresented position $position', () async {
          await _reject(
            _package(
              symbol: role == 'symbol' ? 'Unsupported' : 'Marker',
              anchor: role == 'anchor' ? 'Unsupported' : 'Marker',
              markerStyles:
                  '${_markerStyle('Marker')}${_markerStyle('Unsupported', properties: 'style:text-position="$position"')}',
            ),
          );
        });
      }
    }
    test('an empty marker style cannot silently become superscript', () async {
      await _reject(
        _package(markerStyles: _markerStyle('Marker', properties: null)),
      );
    });
    test('a missing configured marker name is malformed', () async {
      await _reject(_package(symbol: 'Missing'), malformed: true);
    });
    for (final role in ['symbol', 'anchor']) {
      test('an empty configured $role reference is malformed', () async {
        await _reject(
          _package(
            symbol: role == 'symbol' ? '' : 'Marker',
            anchor: role == 'anchor' ? '' : 'Marker',
          ),
          malformed: true,
        );
      });
    }
    test('a missing marker parent is malformed', () async {
      await _reject(
        _package(markerStyles: _markerStyle('Marker', parent: 'Missing')),
        malformed: true,
      );
    });
    test('cyclic marker parents are malformed', () async {
      await _reject(
        _package(
          markerStyles:
              '${_markerStyle('Marker', parent: 'Parent')}${_markerStyle('Parent', parent: 'Marker')}',
        ),
        malformed: true,
      );
    });

    for (final property in [
      'fo:color="#123456"',
      'fo:font-family="Arial"',
      'fo:font-weight="bold"',
    ]) {
      for (final inherited in ['default', 'parent']) {
        test('$inherited $property cannot be dropped from a marker', () async {
          final styles = inherited == 'default'
              ? '${_defaultText(property)}${_markerStyle('Marker')}'
              : '${_markerStyle('Parent', properties: property)}${_markerStyle('Marker', parent: 'Parent')}';
          await _reject(_package(markerStyles: styles));
        });
      }
    }

    final invalidStyles = <String, String>{
      'nested marker properties': _markerStyle(
        'Marker',
        properties: null,
        extra:
            '<style:text-properties style:text-position="super 65%"><text:span/></style:text-properties>',
      ),
      'foreign marker properties': _markerStyle(
        'Marker',
        properties: null,
        extra: '<x:text-properties style:text-position="super 65%"/>',
      ),
      'foreign marker attribute': _markerStyle(
        'Marker',
        properties: 'style:text-position="super 65%" x:color="keep"',
      ),
      'authored style text': _markerStyle('Marker', extra: 'authored'),
      'authored property text': _markerStyle(
        'Marker',
        properties: null,
        extra:
            '<style:text-properties style:text-position="super 65%">authored</style:text-properties>',
      ),
      'nested default properties':
          '${_defaultText('', extra: '<text:span/>')}${_markerStyle('Marker')}',
      'foreign parent properties':
          '${_markerStyle('Parent', properties: null, extra: '<x:text-properties/>')}${_markerStyle('Marker', parent: 'Parent')}',
      'authored parent text':
          '${_markerStyle('Parent', extra: 'authored')}${_markerStyle('Marker', parent: 'Parent')}',
    };
    for (final entry in invalidStyles.entries) {
      test('${entry.key} is not flattened', () async {
        await _reject(_package(markerStyles: entry.value));
      });
    }
    test('configured note paragraph styling stays guarded', () async {
      await _reject(
        _package(
          configurationAttributes: 'text:default-style-name="NoteParagraph"',
          markerStyles:
              '${_markerStyle('Marker')}<style:style style:name="NoteParagraph" style:family="paragraph"/>',
        ),
      );
    });
    test(
      'an empty configured note paragraph reference stays guarded',
      () async {
        await _reject(
          _package(configurationAttributes: 'text:default-style-name=""'),
        );
      },
    );
    test('authored note configuration text is not dropped', () async {
      await _reject(_package(configurationContent: 'authored'));
    });
  });

  group('configured endnote page layout compatibility', () {
    final page = _layout('BodyLayout');
    final body = _master('BodyMaster', 'BodyLayout');
    final compatible = <String, ({String name, String layouts, String masters})>{
      'same master': (name: 'BodyMaster', layouts: page, masters: body),
      'distinct master same layout': (
        name: 'NoteMaster',
        layouts: page,
        masters: '$body${_master('NoteMaster', 'BodyLayout')}',
      ),
      'distinct equivalent layout': (
        name: 'NoteMaster',
        layouts:
            '$page${_layout('NoteLayout', width: '8.5in', height: '11in', margin: '1in')}',
        masters:
            '$body${_master('NoteMaster', 'NoteLayout', next: 'NoteMaster')}',
      ),
    };
    for (final entry in compatible.entries) {
      test('${entry.key} retains the body and endnote page geometry', () async {
        final bytes = _package(
          bodyMaster: 'BodyMaster',
          configurationAttributes:
              'text:master-page-name="${entry.value.name}"',
          layouts: entry.value.layouts,
          masters: entry.value.masters,
        );
        final original = Uint8List.fromList(bytes);
        var document = await OdtDocumentReader.readBytes(bytes);
        for (var cycle = 0; cycle < 2; cycle++) {
          final section = document.sections.single;
          expect(section.pageSize.width, 612);
          expect(section.pageSize.height, 792);
          expect(
            [
              section.margins.top,
              section.margins.bottom,
              section.margins.left,
              section.margins.right,
            ],
            [72, 72, 72, 72],
          );
          _checkNote(document, endnote: true);
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
        expect(bytes, original);
      });
    }
    final incompatible = <String, ({String layout, String master})>{
      'different margin': (
        layout: _layout('NoteLayout', margin: '71pt'),
        master: _master('NoteMaster', 'NoteLayout'),
      ),
      'different size': (
        layout: _layout('NoteLayout', width: '610pt'),
        master: _master('NoteMaster', 'NoteLayout'),
      ),
      'different columns': (
        layout: _layout(
          'NoteLayout',
          children: '<style:columns fo:column-count="2" fo:column-gap="18pt"/>',
        ),
        master: _master('NoteMaster', 'NoteLayout'),
      ),
      'header story': (
        layout: _layout('NoteLayout'),
        master: _master(
          'NoteMaster',
          'NoteLayout',
          content: '<style:header><text:p>Header</text:p></style:header>',
        ),
      ),
      'footer story': (
        layout: _layout('NoteLayout'),
        master: _master(
          'NoteMaster',
          'NoteLayout',
          content: '<style:footer><text:p>Footer</text:p></style:footer>',
        ),
      ),
      'alternating master': (
        layout: _layout('NoteLayout'),
        master: _master('NoteMaster', 'NoteLayout', next: 'BodyMaster'),
      ),
    };
    for (final entry in incompatible.entries) {
      test(
        '${entry.key} cannot be discarded from the endnote master',
        () async {
          await _reject(
            _package(
              bodyMaster: 'BodyMaster',
              configurationAttributes: 'text:master-page-name="NoteMaster"',
              layouts: '$page${entry.value.layout}',
              masters: '$body${entry.value.master}',
            ),
          );
        },
      );
    }
    test('a missing configured endnote master is malformed', () async {
      await _reject(
        _package(
          bodyMaster: 'BodyMaster',
          configurationAttributes: 'text:master-page-name="Missing"',
          layouts: page,
          masters: body,
        ),
        malformed: true,
      );
    });
    test('an empty configured endnote master is malformed', () async {
      await _reject(
        _package(
          bodyMaster: 'BodyMaster',
          configurationAttributes: 'text:master-page-name=""',
          layouts: page,
          masters: body,
        ),
        malformed: true,
      );
    });
    test('authored endnote master text is not dropped', () async {
      await _reject(
        _package(
          bodyMaster: 'BodyMaster',
          configurationAttributes: 'text:master-page-name="NoteMaster"',
          layouts: page,
          masters:
              '$body${_master('NoteMaster', 'BodyLayout', content: 'authored')}',
        ),
      );
    });
    test('a configured endnote master must resolve its layout', () async {
      await _reject(
        _package(
          bodyMaster: 'BodyMaster',
          configurationAttributes: 'text:master-page-name="NoteMaster"',
          layouts: page,
          masters: '$body${_master('NoteMaster', 'Missing')}',
        ),
        malformed: true,
      );
    });
    test('footnote master page configuration remains unsupported', () async {
      await _reject(
        _package(
          endnote: false,
          bodyMaster: 'BodyMaster',
          configurationAttributes: 'text:master-page-name="BodyMaster"',
          layouts: page,
          masters: body,
        ),
      );
    });
  });

  group('editable note configuration output', () {
    test(
      'separate marker roles resolve exact common styles and preserve source',
      () async {
        final source = _native();
        final before = _nativeSnapshot(source);
        final bytes = OdtDocumentWriter.writeEditableZoteroBytes(source);
        final package = OpcPackage.openBytes(bytes);
        final styles = XmlDocument.parse(
          package.getPart('/styles.xml')!.readText(),
        ).root!;
        final common = styles.firstChild('styles', namespaceUri: _office)!;
        final configurations = common
            .childrenNamed('notes-configuration', namespaceUri: _text)
            .toList();
        expect(configurations, hasLength(2));
        final allMarkerNames = <String?>{};
        for (final configuration in configurations) {
          final names = [
            configuration.getAttribute(
              'citation-style-name',
              namespaceUri: _text,
            ),
            configuration.getAttribute(
              'citation-body-style-name',
              namespaceUri: _text,
            ),
          ];
          expect(names.toSet(), hasLength(2));
          allMarkerNames.addAll(names);
          for (final name in names) {
            expect(name, isNotNull);
            final definition = common
                .childrenNamed('style', namespaceUri: _style)
                .singleWhere(
                  (style) =>
                      style.getAttribute('name', namespaceUri: _style) == name,
                );
            expect(
              definition.getAttribute('family', namespaceUri: _style),
              'text',
            );
            final properties = definition.childElements.single;
            expect(properties.namespaceUri, _style);
            expect(properties.localName, 'text-properties');
            expect(
              properties.attributes.map(
                (attribute) => (
                  attribute.namespaceUri,
                  attribute.localName,
                  attribute.value,
                ),
              ),
              [(_style, 'text-position', 'super 65%')],
            );
          }
        }
        expect(allMarkerNames, hasLength(4));
        final endnote = configurations.singleWhere(
          (configuration) =>
              configuration.getAttribute('note-class', namespaceUri: _text) ==
              'endnote',
        );
        expect(
          endnote.getAttribute('master-page-name', namespaceUri: _text),
          'Standard',
        );
        expect(_nativeSnapshot(source), before);
        var reopened = await OdtDocumentReader.readBytes(bytes);
        for (var cycle = 0; cycle < 3; cycle++) {
          expect(
            WordZotero.fields(
              reopened,
            ).map((field) => field.citation!.citationId),
            ['foot-citation', 'end-citation'],
          );
          expect(
            WordZotero.fields(reopened).every((field) => field.canEdit),
            isTrue,
          );
          for (final note in [...reopened.footnotes, ...reopened.endnotes]) {
            expect(
              note.paragraphs.single.inlines
                  .whereType<WmlNoteMarker>()
                  .single
                  .properties
                  .vertAlign,
              WmlVertAlign.superscript,
            );
          }
          reopened = WordDeserializer().readBytes(
            WordSerializer().writeBytes(reopened),
          );
        }
      },
    );

    for (final count in [2, 3]) {
      for (final kind in [
        WmlSectionBreakKind.oddPage,
        WmlSectionBreakKind.evenPage,
      ]) {
        test(
          '$count sections with ${kind.name} use the final regular note master',
          () {
            final document = _native(sectionCount: count, finalBreak: kind);
            final before = _nativeSnapshot(document);
            final package = OpcPackage.openBytes(
              OdtDocumentWriter.writeEditableZoteroBytes(document),
            );
            final styles = XmlDocument.parse(
              package.getPart('/styles.xml')!.readText(),
            ).root!;
            final config = _elements(styles, _text, 'notes-configuration')
                .singleWhere(
                  (configuration) =>
                      configuration.getAttribute(
                        'note-class',
                        namespaceUri: _text,
                      ) ==
                      'endnote',
                );
            final name = config.getAttribute(
              'master-page-name',
              namespaceUri: _text,
            );
            expect(name, 'mp${count - 1}');
            final master = _elements(styles, _style, 'master-page').singleWhere(
              (master) =>
                  master.getAttribute('name', namespaceUri: _style) == name,
            );
            expect(
              master.getAttribute('page-layout-name', namespaceUri: _style),
              'pm${count - 1}',
            );
            final layout = _elements(styles, _style, 'page-layout').singleWhere(
              (layout) =>
                  layout.getAttribute('name', namespaceUri: _style) ==
                  'pm${count - 1}',
            );
            expect(
              layout.getAttribute('page-usage', namespaceUri: _style),
              isNull,
            );
            expect(
              layout
                  .firstChild('page-layout-properties', namespaceUri: _style)!
                  .getAttribute('page-width', namespaceUri: _fo),
              '${document.sections.last.pageSize.width.toStringAsFixed(2)}pt',
            );
            expect(
              _elements(styles, _style, 'master-page').where(
                (master) =>
                    master.getAttribute('name', namespaceUri: _style) ==
                    'mp${count - 1}Start',
              ),
              hasLength(1),
            );
            expect(_nativeSnapshot(document), before);
          },
        );
      }
    }
  });
}
