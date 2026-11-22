import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/serial/odt_reader_styles.dart';
import 'package:test/test.dart';

import 'support/zotero_converter_fixtures.dart';

const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _loext =
    'urn:org:documentfoundation:names:experimental:office:xmlns:loext:1.0';
const _alignment =
    '<style:list-level-properties '
    'text:list-level-position-and-space-mode="label-alignment">'
    '<style:list-level-label-alignment text:label-followed-by="nothing"/>'
    '</style:list-level-properties>';

String _level({int number = 2, bool template = false, String? children}) =>
    '<text:outline-level-style text:level="$number" style:num-format="" '
    '${template ? 'loext:num-list-format="%$number%"' : ''}>'
    '${children ?? _alignment}</text:outline-level-style>';

String _outline(String levels) =>
    '<text:outline-style style:name="Outline">$levels</text:outline-style>';

XmlElement _definitions(String outline) => XmlDocument.parse(
  '<office:document-styles '
  'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
  'xmlns:text="$_text" xmlns:style="$_style" xmlns:fo="$_fo" '
  'xmlns:loext="$_loext" xmlns:foreign="urn:foreign">'
  '<office:styles>$outline</office:styles></office:document-styles>',
).root!;

void _validate(String levels) => OdtReaderStyles(
  _definitions(_outline(levels)),
).validateHeadingConfiguration();

String _textStyle(String name, String properties, {String parent = ''}) =>
    '<style:style style:name="$name" style:family="text" '
    '${parent.isEmpty ? '' : 'style:parent-style-name="$parent"'}>'
    '<style:text-properties $properties/></style:style>';

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> arguments = const [],
]) => session.handle(command, ['odt-converter-refresh', ...arguments]);

Uint8List _replaceStyles(Uint8List source, String from, String to) {
  final archive = ZipReader.fromBytes(source);
  final writer = ZipWriter();
  var replaced = false;
  for (final entry in archive.entries) {
    var bytes = archive.read(entry.fileName);
    if (entry.fileName == 'styles.xml') {
      final text = utf8.decode(bytes);
      expect(text, contains(from));
      bytes = Uint8List.fromList(utf8.encode(text.replaceFirst(from, to)));
      replaced = true;
    }
    writer.addFile(entry.fileName, bytes, store: entry.fileName == 'mimetype');
  }
  expect(replaced, isTrue);
  return writer.close();
}

void main() {
  test(
    'clear character shading retains explicit RGB and transparent resets',
    () {
      final styles = OdtReaderStyles(
        _definitions(
          _textStyle(
                'Color',
                'fo:background-color="#fae696" loext:char-shading-value="0"',
              ) +
              _textStyle('Inherited', 'fo:color="#123456"', parent: 'Color') +
              _textStyle(
                'Reset',
                'fo:background-color="transparent" loext:char-shading-value="0"',
                parent: 'Color',
              ) +
              _textStyle(
                'Override',
                'fo:background-color="#ccddee" loext:char-shading-value="0"',
                parent: 'Color',
              ),
        ),
      );
      expect(
        styles.runProperties('Color').nativeProperties().highlight,
        'FAE696',
      );
      expect(
        styles.runProperties('Inherited').nativeProperties().highlight,
        'FAE696',
      );
      expect(
        styles.runProperties('Reset').nativeProperties().highlight,
        isNull,
      );
      expect(
        styles.runProperties('Override').nativeProperties().highlight,
        'CCDDEE',
      );
    },
  );
  for (final value in ['1', '14', '65535', '-1', '00', '0.0', 'clear', '']) {
    test(
      'refuses unrepresented or noncanonical character shading "$value"',
      () {
        final styles = OdtReaderStyles(
          _definitions(
            _textStyle(
              'Pattern',
              'fo:background-color="#fae696" loext:char-shading-value="$value"',
            ),
          ),
        );
        expect(() => styles.runProperties('Pattern'), throwsUnsupportedError);
      },
    );
  }
  for (final inherited in [false, true]) {
    test(
      'refuses shading-only compound brush reset (inherited=$inherited)',
      () {
        final styles = OdtReaderStyles(
          _definitions(
            _textStyle('Parent', 'fo:background-color="#fae696"') +
                _textStyle(
                  'Only',
                  'loext:char-shading-value="0"',
                  parent: inherited ? 'Parent' : '',
                ),
          ),
        );
        expect(() => styles.runProperties('Only'), throwsUnsupportedError);
      },
    );
  }
  test('refuses same-named shading in an unrelated namespace', () {
    final styles = OdtReaderStyles(
      _definitions(
        _textStyle(
          'Foreign',
          'fo:background-color="#fae696" foreign:char-shading-value="0"',
        ),
      ),
    );
    expect(() => styles.runProperties('Foreign'), throwsUnsupportedError);
  });
  test('accepts Writer unnumbered alignment over all ten outline levels', () {
    for (final template in [false, true]) {
      _validate(
        [
          for (var n = 1; n <= 10; n++) _level(number: n, template: template),
        ].join(),
      );
    }
  });

  test('keeps the existing child-free empty-numbering representation', () {
    _validate(_level(children: ''));
    _validate(_level(template: true, children: ''));
  });

  test('allows harmless XML whitespace and comments', () {
    _validate(
      '\n<!-- empty labels -->${_level(children: '\n$_alignment\t')}\r',
    );
  });

  final unsupported = <String, String>{
    'number sequence': _level().replaceFirst('num-format=""', 'num-format="1"'),
    'omitted number format': _level().replaceFirst('style:num-format=""', ''),
    'number prefix': _level().replaceFirst(
      'style:num-format=""',
      'style:num-format="" style:num-prefix="("',
    ),
    'number suffix': _level().replaceFirst(
      'style:num-format=""',
      'style:num-format="" style:num-suffix=")"',
    ),
    'literal extension': _level(template: true).replaceFirst('%2%', 'Appendix'),
    'extension punctuation': _level(template: true).replaceFirst('%2%', '%2%.'),
    'different level': _level(template: true).replaceFirst('%2%', '%1%'),
    'multilevel template': _level(
      template: true,
    ).replaceFirst('%2%', '%1%.%2%'),
    'unknown extension': _level(
      template: true,
    ).replaceFirst('loext:num-list-format', 'loext:other'),
    'wrong extension namespace': _level(
      template: true,
    ).replaceFirst('loext:num-list-format', 'foreign:num-list-format'),
    'following tab': _level().replaceFirst(
      'followed-by="nothing"',
      'followed-by="listtab"',
    ),
    'following space': _level().replaceFirst(
      'followed-by="nothing"',
      'followed-by="space"',
    ),
    'following default': _level().replaceFirst(
      'text:label-followed-by="nothing"',
      '',
    ),
    'positioning mode': _level().replaceFirst(
      'space-mode="label-alignment"',
      'space-mode="label-width-and-position"',
    ),
    'omitted positioning mode': _level().replaceFirst(
      'text:list-level-position-and-space-mode="label-alignment"',
      '',
    ),
    'left margin': _level().replaceFirst(
      'text:label-followed-by',
      'fo:margin-left="12pt" text:label-followed-by',
    ),
    'first line indent': _level().replaceFirst(
      'text:label-followed-by',
      'fo:text-indent="-12pt" text:label-followed-by',
    ),
    'tab stop': _level().replaceFirst(
      'text:label-followed-by',
      'text:list-tab-stop-position="12pt" text:label-followed-by',
    ),
    'legacy spacing': _level().replaceFirst(
      'text:list-level-position',
      'text:space-before="12pt" text:list-level-position',
    ),
    'text formatting': _level(
      children: '$_alignment<style:text-properties fo:color="#FF0000"/>',
    ),
    'duplicate property blocks': _level(children: '$_alignment$_alignment'),
    'duplicate alignments': _level().replaceFirst(
      '</style:list-level-properties>',
      '<style:list-level-label-alignment text:label-followed-by="nothing"/></style:list-level-properties>',
    ),
    'omitted alignment': _level().replaceFirst(
      '<style:list-level-label-alignment text:label-followed-by="nothing"/>',
      '',
    ),
    'nested alignment content': _level().replaceFirst(
      'text:label-followed-by="nothing"/>',
      'text:label-followed-by="nothing"><foreign:opaque/></style:list-level-label-alignment>',
    ),
    'foreign level': _level().replaceAll(
      'text:outline-level-style',
      'foreign:outline-level-style',
    ),
    'foreign alignment': _level().replaceAll(
      'style:list-level-label-alignment',
      'foreign:list-level-label-alignment',
    ),
    'authored level text': _level(children: 'lost$_alignment'),
    'authored alignment text': _level().replaceFirst(
      'text:label-followed-by="nothing"/>',
      'text:label-followed-by="nothing">lost</style:list-level-label-alignment>',
    ),
    'authored CDATA': _level(children: '<![CDATA[lost]]>$_alignment'),
  };
  for (final entry in unsupported.entries) {
    test('refuses active or unrepresented outline ${entry.key}', () {
      expect(() => _validate(entry.value), throwsUnsupportedError);
    });
  }

  for (final number in [0, 11]) {
    test('refuses outline level $number', () {
      expect(() => _validate(_level(number: number)), throwsFormatException);
    });
  }
  test('refuses duplicate levels and conflicting outline definitions', () {
    expect(() => _validate('${_level()}${_level()}'), throwsFormatException);
    expect(
      () => OdtReaderStyles(
        _definitions('${_outline(_level())}${_outline(_level())}'),
      ).validateHeadingConfiguration(),
      throwsFormatException,
    );
  });

  for (final cycle in [1, 2]) {
    for (final kind in ['body', 'footnote', 'cell']) {
      test(
        'refreshes retained Writer ODT cycle $cycle $kind transactionally',
        () async {
          final source = File(
            '$zoteroConverterFixtureRoot/odt-cycle-$cycle/$kind.odt',
          ).readAsBytesSync();
          final original = Uint8List.fromList(source);
          var document = await OdtDocumentReader.readBytes(source);
          final before = converterSnapshot(document, kind);
          final preferences = WordZoteroDocumentData.read(document);
          final originalFields = WordZotero.fields(document);
          final items = originalFields
              .map(
                (field) =>
                    field.citation!.items.map((item) => item.toJson()).toList(),
              )
              .toList();
          final originalText = converterStory(
            document,
            kind,
          ).map((p) => p.text.trim()).toList();
          final session = WordZoteroCitingSession(
            document: document,
            documentId: 'odt-converter-refresh',
            insertionParagraph: document.paragraphs.first,
          );
          final fields =
              (_call(session, 'Document.getFields', ['Http']) as List<Object?>)
                  .cast<Map<String, Object>>();
          expect(fields, hasLength(2));
          for (var i = 0; i < fields.length; i++) {
            final updated = originalFields[i].citation!.withItems(
              originalFields[i].citation!.items,
              plainCitation: '(Updated ${i + 1})',
              noteIndex: fields[i]['noteIndex'] as int,
            );
            _call(session, 'Field.setCode', [
              fields[i]['id'],
              'ITEM CSL_CITATION ${jsonEncode(updated.toJson())}',
            ]);
            _call(session, 'Field.setText', [
              fields[i]['id'],
              '<i>(Updated ${i + 1})</i>',
              true,
            ]);
          }
          expect(converterSnapshot(document, kind), before);
          _call(session, 'Document.complete');
          expect(converterSnapshot(document, kind), before);
          session.apply();
          for (var save = 0; save < 3; save++) {
            final actualFields = WordZotero.fields(document);
            expect(actualFields.map((f) => f.cachedText), [
              '(Updated 1)',
              '(Updated 2)',
            ]);
            expect(actualFields.map((f) => f.citation!.citationId), [
              'FIRST1',
              'SECOND2',
            ]);
            expect(
              actualFields.map(
                (f) => f.citation!.items.map((item) => item.toJson()).toList(),
              ),
              items,
            );
            expect(
              actualFields.every(
                (f) =>
                    f.canEdit &&
                    converterStory(document, kind).contains(f.paragraph),
              ),
              isTrue,
            );
            expect(WordFieldSpans.unbalanced(document), isEmpty);
            expect(WordZoteroDocumentData.read(document), preferences);
            expect(
              converterStory(document, kind).map((p) => p.text.trim()),
              originalText.map(
                (text) => text
                    .replaceFirst('(FIRST1)', '(Updated 1)')
                    .replaceFirst('(SECOND2)', '(Updated 2)'),
              ),
            );
            expect(
              converterSnapshot(document, kind)['colors'],
              before['colors'],
            );
            expect(converterSnapshot(document, kind)['empty'], before['empty']);
            document = save.isEven
                ? WordDeserializer().readBytes(
                    WordSerializer().writeBytes(document),
                  )
                : await OdtDocumentReader.readBytes(
                    OdtDocumentWriter.writeEditableZoteroBytes(document),
                  );
          }
          expect(source, original);
        },
      );
      test(
        'reopens retained Writer ODT cycle $cycle $kind without semantic loss',
        () async {
          final source = File(
            '$zoteroConverterFixtureRoot/odt-cycle-$cycle/$kind.odt',
          ).readAsBytesSync();
          final original = Uint8List.fromList(source);
          var document = await OdtDocumentReader.readBytes(source);
          expectConverterSnapshot(document, kind);
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
          expectConverterSnapshot(document, kind);
          document = await OdtDocumentReader.readBytes(
            OdtDocumentWriter.writeEditableZoteroBytes(document),
          );
          expectConverterSnapshot(document, kind);
          expect(source, original);
        },
      );
    }
  }

  test(
    'refuses active outline geometry in an otherwise eligible real ODT',
    () async {
      final source = File(
        '$zoteroConverterFixtureRoot/odt-cycle-2/body.odt',
      ).readAsBytesSync();
      final original = Uint8List.fromList(source);
      final changed = _replaceStyles(
        source,
        'text:label-followed-by="nothing"',
        'text:label-followed-by="nothing" fo:margin-left="12pt"',
      );
      await expectLater(
        OdtDocumentReader.readBytes(changed),
        throwsUnsupportedError,
      );
      expect(source, original);
    },
  );
}
