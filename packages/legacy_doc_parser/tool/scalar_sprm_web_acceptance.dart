// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/scalar_sprm_fixture.dart';

Map<String, Object?> verifyScalarSprmWebAcceptance() {
  var rejected = 0, preserved = 0;
  for (final property in scalarSprmProperties) {
    for (final scope in property.scopes) {
      for (final value in property.invalidValues) {
        verifyScalarSprmCase(property, value, scope, valid: false);
        rejected++;
      }
      for (final value in property.validValues) {
        verifyScalarSprmCase(property, value, scope, valid: true);
        preserved++;
      }
    }
  }
  return {
    'operandKinds': scalarSprmProperties.length,
    'invalidSourcesRejected': rejected,
    'validSourcesPreserved': preserved,
    'sourceBytesUnchanged': true,
    'exactXmlAndTypedValues': true,
  };
}

void verifyScalarSprmCase(
  ScalarSprmProperty property,
  int value,
  String scope, {
  required bool valid,
}) {
  final source = scalarSprmFixture(property, value, scope);
  final original = source.toList();
  final name = '${property.name}/$scope/$value';
  try {
    if (extractLegacyWordText(source) != 'AB') {
      throw StateError('$name changed text-only extraction');
    }
    if (!valid) {
      try {
        parseLegacyWordDocument(source);
      } on FormatException {
        return;
      }
      throw StateError('$name accepted invalid MS-DOC scalar operand');
    }
    final parsed = parseLegacyWordDocument(source);
    final paragraph = parsed.blocks.whereType<LegacyWordParagraph>().single;
    if (parsed.plainText != 'AB' || property.read(paragraph) != value) {
      throw StateError('$name lost source text or typed scalar');
    }
    if (property.multiple != null &&
        paragraph.style.lineSpacingMultiple != property.multiple) {
      throw StateError('$name lost fMultLinespace');
    }
    final zip = ZipDecoder().decodeBytes(
      convertLegacyWordDocument(parsed).bytes,
    );
    final xml = XmlDocument.parse(
      utf8.decode(zip.findFile('word/document.xml')!.content),
    );
    if (xml.findAllElements('w:t').map((e) => e.innerText).join() != 'AB') {
      throw StateError('$name changed native body text');
    }
    final (tag, attribute, expected) = switch (property.property) {
      'spacing' => ('spacing', 'val', value),
      'left' => ('ind', 'left', value),
      'right' => ('ind', 'right', value),
      'first' => ('ind', value < 0 ? 'hanging' : 'firstLine', value.abs()),
      'before' => ('spacing', 'before', value),
      'after' => ('spacing', 'after', value),
      'line' => ('spacing', 'line', value.abs()),
      _ => throw StateError('Unknown scalar fixture property'),
    };
    _attribute(xml, tag, attribute, expected, name);
    if (property.multiple != null) {
      _attribute(
        xml,
        'spacing',
        'lineRule',
        value < 0
            ? 'exact'
            : property.multiple!
            ? 'auto'
            : 'atLeast',
        name,
      );
      if (value != 0) {
        final css = property.multiple! && value > 0
            ? 'line-height:${value / 240}'
            : 'line-height:${value.abs() / 20}pt';
        // Preview formatting uses compact integer point values when possible.
        final compactCss = css.replaceAll('.0pt', 'pt');
        if (!parsed.safeHtml.contains(css) &&
            !parsed.safeHtml.contains(compactCss)) {
          throw StateError('$name lost $css in HTML preview');
        }
      }
    }
  } finally {
    if (source.length != original.length) {
      throw StateError('$name changed source byte length');
    }
    for (var i = 0; i < source.length; i++) {
      if (source[i] != original[i]) {
        throw StateError('$name mutated source byte $i');
      }
    }
  }
}

void _attribute(
  XmlDocument xml,
  String tag,
  String attribute,
  Object expected,
  String name,
) {
  if (!xml
      .findAllElements('w:$tag')
      .any((e) => e.getAttribute('w:$attribute') == '$expected')) {
    throw StateError('$name lost $tag/@$attribute=$expected');
  }
}
