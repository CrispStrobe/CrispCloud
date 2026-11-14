// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/legacy_word_numbering.dart';
import 'package:test/test.dart';

import '../tool/list_marker_style_web_acceptance.dart';
import '../tool/list_sparse_style_web_acceptance.dart';
import 'support/list_marker_style_fixture.dart';
import 'support/list_sparse_style_fixture.dart';

void main() {
  for (final name in listSparseStyleCases) {
    test(
      'sparse marker formatting: $name',
      () => verifyListSparseStyleCase(name),
    );
  }
  test(
    'marker inheritance and native properties share VM and JS acceptance',
    () {
      expect(verifyListMarkerStyleWebAcceptance(), {
        'cases': 66,
        'nullableInheritance': true,
        'sparseBooleanInheritance': true,
        'explicitResets': true,
        'nativeMarkerProperties': true,
        'numberingHighlightUsesShading': true,
        'sourceUnchanged': true,
      });
    },
  );

  test('binary nullable override metadata is immutable', () {
    final level = parseLegacyWordDocument(
      listMarkerStyleFixture('explicit-resets'),
    ).numbering.single.levels.single;
    expect(() => level.characterStyleOverrides.clear(), throwsUnsupportedError);
  });

  test('public false marker values retain explicit reset compatibility', () {
    const mark = LegacyWordCharacterStyle(
      bold: true,
      italic: true,
      allCaps: true,
      smallCaps: true,
      strike: true,
      doubleStrike: true,
      hidden: true,
      underline: true,
      underlineStyle: 'double',
      kerningThresholdHalfPoints: 8,
      verticalAlign: LegacyWordVerticalAlignment.subscript,
    );
    for (final sparse in [false, true]) {
      for (final reset in [false, true]) {
        final level = LegacyWordNumberingLevel(
          level: 0,
          format: 'decimal',
          text: '%1',
          characterStyleIsSparse: sparse,
          characterStyleOverrides: reset
              ? LegacyWordNumberingCharacterProperty.values.toSet()
              : {},
        );
        final style = resolveLegacyWordMarkerStyle(level, mark);
        expect(style.bold, sparse && !reset);
        expect(style.italic, sparse && !reset);
        expect(style.allCaps, sparse && !reset);
        expect(style.smallCaps, sparse && !reset);
        expect(style.strike, sparse && !reset);
        expect(style.doubleStrike, sparse && !reset);
        expect(style.hidden, sparse && !reset);
        expect(style.underline, sparse && !reset);
        expect(style.underlineStyle, sparse && !reset ? 'double' : null);
        expect(style.kerningThresholdHalfPoints, sparse && !reset ? 8 : 0);
        expect(
          style.verticalAlign,
          sparse && !reset
              ? LegacyWordVerticalAlignment.subscript
              : LegacyWordVerticalAlignment.baseline,
        );
      }
    }
  });
}
