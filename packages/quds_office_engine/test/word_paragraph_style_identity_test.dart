import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:paragraph-style-identity';

Uint8List _fixture(
  String styles, {
  String properties = '',
  String prefix = 'w',
  bool table = false,
}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  final paragraph =
      '<$prefix:p><$prefix:pPr>$properties</$prefix:pPr>'
      '<$prefix:r><$prefix:t>Original</$prefix:t></$prefix:r></$prefix:p>';
  final body = table
      ? '<$prefix:tbl><$prefix:tblPr>'
            '<$prefix:tblStyle $prefix:val="TableStyle"/></$prefix:tblPr>'
            '<$prefix:tblGrid><$prefix:gridCol $prefix:w="2000"/></$prefix:tblGrid>'
            '<$prefix:tr><$prefix:tc>$paragraph</$prefix:tc></$prefix:tr>'
            '</$prefix:tbl>'
      : paragraph;
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<$prefix:document xmlns:$prefix="$_w" xmlns:x="$_x">'
        '<$prefix:body>$body<$prefix:sectPr/></$prefix:body></$prefix:document>',
      );
  package
      .getPart('/word/styles.xml')!
      .writeText(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<$prefix:styles xmlns:$prefix="$_w" xmlns:x="$_x">'
        '$styles</$prefix:styles>',
      );
  return package.save();
}

String _styles(Uint8List bytes) =>
    OpcPackage.openBytes(bytes).getPart('/word/styles.xml')!.readText();

void _checkBefore(Uint8List bytes, double expected, {double? afterToggle}) {
  final originalStyles = _styles(bytes);
  final document = WordDeserializer().readBytes(bytes);
  expect(document.paragraphs.single.properties.spacingBefore, expected);
  WordDeserializer().refreshStyles(document);
  expect(document.paragraphs.single.properties.spacingBefore, expected);
  final firstSave = WordSerializer().writeBytes(document);
  expect(_styles(firstSave), originalStyles);
  final reopened = WordDeserializer().readBytes(firstSave);
  expect(reopened.paragraphs.single.properties.spacingBefore, expected);
  if (afterToggle != null) {
    native.applyStep(reopened, {
      'op': 'paragraphSpaceBefore',
      'paragraph': 0,
      'action': 'toggle',
    });
    expect(reopened.paragraphs.single.properties.spacingBefore, afterToggle);
    var saved = WordSerializer().writeBytes(reopened);
    for (var cycle = 0; cycle < 2; cycle++) {
      expect(_styles(saved), originalStyles);
      final next = WordDeserializer().readBytes(saved);
      expect(next.paragraphs.single.properties.spacingBefore, afterToggle);
      expect(next.paragraphs.single.text, 'Original');
      saved = WordSerializer().writeBytes(next);
    }
  }
}

void main() {
  for (final prefix in ['w', 'word']) {
    for (final enabled in ['1', 'true', 'on']) {
      test('default style $enabled resolves with native prefix $prefix', () {
        _checkBefore(
          _fixture(
            '<$prefix:style $prefix:type="paragraph" '
            '$prefix:default="$enabled" $prefix:styleId="PositiveDefault">'
            '<$prefix:name $prefix:val="Positive default"/>'
            '<$prefix:pPr><$prefix:spacing $prefix:before="120" '
            'x:before="foreign"/></$prefix:pPr></$prefix:style>',
            prefix: prefix,
          ),
          6,
          afterToggle: 0,
        );
      });
    }
  }

  for (final disabled in ['0', 'false', 'off']) {
    test('disabled default marker $disabled cannot supply before spacing', () {
      _checkBefore(
        _fixture(
          '<w:style w:type="paragraph" w:default="$disabled" '
          'w:styleId="Inactive"><w:pPr><w:spacing w:before="120"/>'
          '</w:pPr></w:style>',
        ),
        0,
        afterToggle: 12,
      );
    });
  }

  for (final prefix in ['w', 'word']) {
    for (final enabled in ['1', 'true', 'on']) {
      test(
        'omitted style type defaults to paragraph with $prefix $enabled',
        () {
          _checkBefore(
            _fixture(
              '<$prefix:style $prefix:default="$enabled" '
              '$prefix:styleId="PositiveDefault"><$prefix:pPr>'
              '<$prefix:spacing $prefix:before="120"/>'
              '</$prefix:pPr></$prefix:style>',
              prefix: prefix,
            ),
            6,
            afterToggle: 0,
          );
        },
      );
    }
  }

  for (final foreignType in ['paragraph', 'character', 'table', 'numbering']) {
    test(
      'foreign type $foreignType does not override the paragraph default',
      () {
        _checkBefore(
          _fixture(
            '<w:style x:type="$foreignType" w:default="1" w:styleId="Native">'
            '<w:pPr><w:spacing w:before="120"/></w:pPr></w:style>',
          ),
          6,
          afterToggle: 0,
        );
      },
    );
  }

  for (final (parentType, childType) in <(String, String)>[
    ('', ''),
    (' w:type="paragraph"', ''),
    ('', ' w:type="paragraph"'),
  ]) {
    test(
      'omitted type remains paragraph in basedOn $parentType / $childType',
      () {
        _checkBefore(
          _fixture(
            '<w:style$parentType w:styleId="Positive">'
            '<w:pPr><w:spacing w:before="120"/></w:pPr></w:style>'
            '<w:style$childType w:styleId="Native">'
            '<w:basedOn w:val="Positive"/></w:style>',
            properties: '<w:pStyle w:val="Native"/>',
          ),
          6,
          afterToggle: 0,
        );
      },
    );
  }

  for (final (name, styles) in <(String, String)>[
    (
      'foreign style record',
      '<w:style w:type="paragraph" w:default="1" w:styleId="Native">'
          '<w:pPr><w:spacing w:before="0"/></w:pPr></w:style>'
          '<x:style x:type="paragraph" x:default="1" x:styleId="Foreign">'
          '<w:pPr><w:spacing w:before="120"/></w:pPr></x:style>',
    ),
    (
      'foreign style cannot replace the native id',
      '<w:style w:type="paragraph" w:default="1" w:styleId="Native">'
          '<w:pPr><w:spacing w:before="0"/></w:pPr></w:style>'
          '<x:style w:type="paragraph" w:default="1" w:styleId="Native">'
          '<w:pPr><w:spacing w:before="120"/></w:pPr></x:style>',
    ),
    (
      'foreign default attribute',
      '<w:style w:type="paragraph" x:default="1" w:styleId="Native">'
          '<w:pPr><w:spacing w:before="120"/></w:pPr></w:style>',
    ),
    (
      'foreign style id attribute',
      '<w:style w:type="paragraph" w:default="1" x:styleId="Foreign">'
          '<w:pPr><w:spacing w:before="120"/></w:pPr></w:style>',
    ),
    (
      'foreign basedOn element',
      '<w:style w:type="paragraph" w:styleId="Positive">'
          '<w:pPr><w:spacing w:before="120"/></w:pPr></w:style>'
          '<w:style w:type="paragraph" w:default="1" w:styleId="Native">'
          '<x:basedOn x:val="Positive"/></w:style>',
    ),
    (
      'foreign basedOn value attribute',
      '<w:style w:type="paragraph" w:styleId="Positive">'
          '<w:pPr><w:spacing w:before="120"/></w:pPr></w:style>'
          '<w:style w:type="paragraph" w:default="1" w:styleId="Native">'
          '<w:basedOn x:val="Positive"/></w:style>',
    ),
  ]) {
    test('$name stays opaque during the native cascade', () {
      // Malformed native identity records can be refused by edit admission;
      // plain import and save must still preserve them without activating them.
      _checkBefore(_fixture(styles), 0);
    });
  }

  for (final (name, styles, properties) in <(String, String, String)>[
    (
      'native default wins over a preceding foreign default',
      '<w:style w:type="paragraph" x:default="0" w:default="true" '
          'w:styleId="Native"><w:pPr><w:spacing w:before="120"/>'
          '</w:pPr></w:style>',
      '',
    ),
    (
      'native type wins over a preceding foreign type',
      '<w:style x:type="character" w:type="paragraph" w:default="on" '
          'w:styleId="Native"><w:pPr><w:spacing w:before="120"/>'
          '</w:pPr></w:style>',
      '',
    ),
    (
      'native id wins over a preceding foreign id',
      '<w:style w:type="paragraph" x:styleId="Foreign" w:styleId="Native">'
          '<w:pPr><w:spacing w:before="120"/></w:pPr></w:style>',
      '<w:pStyle w:val="Native"/>',
    ),
    (
      'native basedOn wins over a preceding foreign element',
      '<w:style w:type="paragraph" w:styleId="Positive">'
          '<w:pPr><w:spacing w:before="120"/></w:pPr></w:style>'
          '<w:style w:type="paragraph" w:default="1" w:styleId="Native">'
          '<x:basedOn x:val="Foreign"/><w:basedOn w:val="Positive"/>'
          '</w:style>',
      '',
    ),
    (
      'native basedOn value wins over a preceding foreign value',
      '<w:style w:type="paragraph" w:styleId="Positive">'
          '<w:pPr><w:spacing w:before="120"/></w:pPr></w:style>'
          '<w:style w:type="paragraph" w:default="1" w:styleId="Native">'
          '<w:basedOn x:val="Foreign" w:val="Positive"/></w:style>',
      '',
    ),
  ]) {
    test(name, () {
      _checkBefore(_fixture(styles, properties: properties), 6, afterToggle: 0);
    });
  }

  test(
    'alternate-prefix basedOn and default retain sparse property ownership',
    () {
      _checkBefore(
        _fixture(
          '<word:style word:type="paragraph" word:styleId="Positive">'
          '<word:pPr><word:spacing word:before="120" word:after="80"/>'
          '</word:pPr></word:style>'
          '<word:style word:type="paragraph" word:default="true" '
          'word:styleId="Native"><word:basedOn word:val="Positive"/>'
          '</word:style>',
          prefix: 'word',
        ),
        6,
        afterToggle: 0,
      );
    },
  );

  test(
    'foreign identity packets remain inert when default formatting toggles',
    () {
      _checkBefore(
        _fixture(
          '<w:style w:type="paragraph" w:default="1" w:styleId="Native">'
          '<w:pPr><w:spacing w:before="0"/></w:pPr>'
          '<x:basedOn x:val="Foreign"/></w:style>'
          '<x:style x:type="paragraph" x:default="1" x:styleId="Foreign">'
          '<w:pPr><w:spacing w:before="120"/></w:pPr></x:style>',
        ),
        0,
        afterToggle: 12,
      );
    },
  );

  for (final prefix in ['w', 'word']) {
    test('native wholeTable region resolves with prefix $prefix', () {
      _checkBefore(
        _fixture(
          '<$prefix:style $prefix:type="table" $prefix:styleId="TableStyle">'
          '<$prefix:tblStylePr $prefix:type="wholeTable"><$prefix:pPr>'
          '<$prefix:spacing $prefix:before="120"/></$prefix:pPr>'
          '</$prefix:tblStylePr></$prefix:style>',
          prefix: prefix,
          table: true,
        ),
        6,
        afterToggle: 0,
      );
    });
  }

  test('foreign table region stays opaque during import and toggle', () {
    _checkBefore(
      _fixture(
        '<w:style w:type="table" w:styleId="TableStyle">'
        '<x:tblStylePr x:type="wholeTable"><w:pPr>'
        '<w:spacing w:before="120"/></w:pPr></x:tblStylePr></w:style>',
        table: true,
      ),
      0,
      afterToggle: 12,
    );
  });

  test('foreign table region type cannot activate a native region', () {
    _checkBefore(
      _fixture(
        '<w:style w:type="table" w:styleId="TableStyle">'
        '<w:tblStylePr x:type="wholeTable"><w:pPr>'
        '<w:spacing w:before="120"/></w:pPr></w:tblStylePr></w:style>',
        table: true,
      ),
      0,
    );
  });

  test('native table region type wins over a foreign type attribute', () {
    _checkBefore(
      _fixture(
        '<w:style w:type="table" w:styleId="TableStyle">'
        '<w:tblStylePr x:type="lastRow" w:type="wholeTable"><w:pPr>'
        '<w:spacing w:before="120"/></w:pPr></w:tblStylePr></w:style>',
        table: true,
      ),
      6,
      afterToggle: 0,
    );
  });
}
