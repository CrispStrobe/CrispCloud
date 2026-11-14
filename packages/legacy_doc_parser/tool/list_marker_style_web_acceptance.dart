// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/list_marker_style_fixture.dart';
import '../test/support/list_boolean_style_fixture.dart';
import '../test/support/list_sparse_style_fixture.dart';
import 'list_sparse_style_web_acceptance.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

Map<String, Object> verifyListMarkerStyleWebAcceptance() {
  for (final name in listMarkerStyleCases) {
    if (listSparseStyleCases.contains(name)) {
      verifyListSparseStyleCase(name);
      continue;
    }
    void check(bool condition, String message) {
      if (!condition) throw StateError('$name: $message');
    }

    final source = listMarkerStyleFixture(name), before = source.toList();
    final document = parseLegacyWordDocument(source);
    final result = convertLegacyWordDocument(document);
    final archive = ZipDecoder().decodeBytes(result.bytes);
    XmlDocument part(String path) =>
        XmlDocument.parse(utf8.decode(archive.findFile(path)!.content));
    final native = part(
      'word/numbering.xml',
    ).findAllElements('rPr', namespace: _w).single;
    final paragraph = part(
      'word/document.xml',
    ).findAllElements('p', namespace: _w).single;
    final materialized = !name.startsWith('native-');
    final style = materialized
        ? paragraph
              .findElements('r', namespace: _w)
              .first
              .getElement('rPr', namespace: _w)!
        : native;
    String? value(String name) => style
        .getElement(name, namespace: _w)
        ?.getAttribute('val', namespace: _w);
    final expected = switch (name) {
      'inherited-nullable' => {
        'sz': '48',
        'color': 'AA1122',
        'highlight': 'yellow',
        'position': '6',
        'spacing': '30',
      },
      'explicit-overrides' => {
        'sz': '20',
        'color': '112233',
        'highlight': 'green',
        'position': '2',
        'spacing': '10',
      },
      'explicit-resets' => {
        'sz': '48',
        'color': null,
        'highlight': null,
        'position': '0',
        'spacing': '0',
      },
      'native-all-properties' => {
        'b': '1',
        'i': '1',
        'caps': '1',
        'smallCaps': '1',
        'strike': '1',
        'dstrike': '1',
        'u': 'double',
        'sz': '30',
        'kern': '8',
        'color': '123456',
        'vertAlign': 'subscript',
        'position': '2',
        'spacing': '-15',
      },
      'native-color-reset' => {'color': 'auto'},
      _ => <String, String?>{},
    };
    for (final property in expected.entries) {
      check(
        value(property.key) == property.value,
        'exact ${property.key} property',
      );
    }
    if (name == 'native-all-properties' || name == 'native-named-highlight') {
      check(
        native.getElement('highlight', namespace: _w) == null,
        'no prohibited numbering highlight',
      );
      check(
        native
                .getElement('shd', namespace: _w)
                ?.getAttribute('fill', namespace: _w) ==
            'FFFF00',
        'exact named-highlight RGB retained as permitted shading',
      );
    }
    if (name == 'native-font-slots') {
      final fonts = native.getElement('rFonts', namespace: _w)!;
      for (final (slot, face) in [
        ('ascii', 'Marker ASCII'),
        ('hAnsi', 'Marker NonASCII'),
        ('eastAsia', 'Marker EastAsia'),
        ('cs', 'Marker Complex'),
      ]) {
        check(
          fonts.getAttribute(slot, namespace: _w) == face,
          'independent $slot font',
        );
      }
    }
    if (name == 'native-hidden') {
      check(
        native.getElement('vanish', namespace: _w) != null,
        'native hidden marker',
      );
    }
    final html = XmlDocument.parse(document.safeHtml);
    final labels = html
        .findAllElements('span')
        .where((node) => node.getAttribute('data-word-list-label') == 'true')
        .toList();
    check(
      name == 'native-hidden'
          ? labels.isEmpty
          : labels.single.innerText == (materialized ? '%1' : '7.'),
      'exact visible HTML label',
    );
    if (name == 'inherited-nullable') {
      final css = labels.single.toXmlString();
      final size = RegExp(r'font-size:([0-9.]+)pt').firstMatch(css)?.group(1);
      check(
        size != null &&
            double.parse(size) == 24 &&
            css.contains('color:#AA1122') &&
            css.contains('background-color:#FFFF00'),
        'HTML inherits paragraph mark properties',
      );
    }
    if (name == 'explicit-resets') {
      final overrides =
          document.numbering.single.levels.single.characterStyleOverrides;
      check(
        overrides.containsAll({
          LegacyWordNumberingCharacterProperty.color,
          LegacyWordNumberingCharacterProperty.highlight,
          LegacyWordNumberingCharacterProperty.position,
          LegacyWordNumberingCharacterProperty.spacing,
        }),
        'binary explicit reset identity',
      );
      check(
        !labels.single.toXmlString().contains('color:#AA1122') &&
            !labels.single.toXmlString().contains('background-color:#FFFF00'),
        'HTML respects explicit resets',
      );
    }
    if (listBooleanStyleCases.contains(name)) {
      final absent = name.endsWith('-absent');
      final enabled = absent || name.endsWith('-1') || name.endsWith('-81');
      final level = document.numbering.single.levels.single;
      check(level.characterStyleIsSparse, 'binary sparse marker formatting');
      for (final property in [
        LegacyWordNumberingCharacterProperty.bold,
        LegacyWordNumberingCharacterProperty.italic,
      ]) {
        check(
          level.characterStyleOverrides.contains(property) != absent,
          'exact ${property.name} override presence',
        );
      }
      for (final property in ['b', 'i']) {
        check(
          value(property) ==
              (!materialized && absent
                  ? null
                  : enabled
                  ? '1'
                  : '0'),
          'exact sparse or materialized $property',
        );
      }
      final labelCss = labels.single.toXmlString();
      check(
        labelCss.contains('font-weight:bold') == enabled &&
            labelCss.contains('font-style:italic') == enabled,
        'HTML marker bold/italic inherit without altering body',
      );
      final bodyRun = paragraph.findElements('r', namespace: _w).last;
      for (final property in ['b', 'i']) {
        check(
          bodyRun
                  .getElement('rPr', namespace: _w)
                  ?.getElement(property, namespace: _w)
                  ?.getAttribute('val', namespace: _w) ==
              '0',
          'body $property stays explicitly off',
        );
      }
    }
    check(
      (result.preservedCounts['materializedNumberingLabels'] ?? 0) ==
          (materialized ? 1 : 0),
      'materialization count',
    );
    check(source.length == before.length, 'source length');
    for (var i = 0; i < source.length; i++) {
      check(source[i] == before[i], 'immutable source byte $i');
    }
  }
  return {
    'cases': listMarkerStyleCases.length,
    'nullableInheritance': true,
    'sparseBooleanInheritance': true,
    'explicitResets': true,
    'nativeMarkerProperties': true,
    'numberingHighlightUsesShading': true,
    'sourceUnchanged': true,
  };
}

void main() => print(jsonEncode(verifyListMarkerStyleWebAcceptance()));
