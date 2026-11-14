// SPDX-License-Identifier: MPL-2.0
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../tool/cached_field_web_acceptance.dart';
import '../tool/generated_field_tree_web_acceptance.dart';
import 'support/field_visibility_fixture.dart';
import 'support/generated_field_tree_fixture.dart';

void main() {
  for (final name in fieldVisibilityCases) {
    test(
      'cached mode retains independent display and field evidence: $name',
      () {
        verifyCachedFieldSource(
          fieldVisibilityFixture(name),
          fieldVisibilityExpectedText[name]!,
        );
      },
    );
  }
  for (var seed = 1; seed <= 96; seed++) {
    test('cached mode retains generated field tree $seed', () {
      final fixture = GeneratedFieldTreeCase(seed);
      verifyCachedFieldSource(fixture.bytes(), fixture.expected);
    });
  }
  test('cached policy is explicit at all public conversion entry points', () {
    final source = fieldVisibilityFixture('formula');
    final ordinary = convertLegacyWordToStructuredDocx(source);
    expect(ordinary.fieldMode, LegacyWordFieldMode.preserve);
    expect(ordinary.preservedCounts['fields'], 1);
    final structured = convertLegacyWordToStructuredDocx(
      source,
      fieldMode: LegacyWordFieldMode.cachedResults,
    );
    final generic = convertLegacyWord(
      source,
      fieldMode: LegacyWordFieldMode.cachedResults,
    );
    expect(structured.bytes, orderedEquals(generic.bytes));
    expect(structured.preservedCounts['cachedResultFields'], 1);
  });
  test(
    'shared cached gate also checks alternate layouts, DOCM and malformed public models',
    () {
      expect(verifyCachedFieldWebAcceptance()['malformedOwnershipRejected'], 7);
    },
  );
  for (final marker in [
    '<w:fldChar w:fldCharType="bad"/>',
    '<w:fldChar w:fldCharType="begin"/><w:fldChar w:fldCharType="separate"/><w:fldChar w:fldCharType="separate"/><w:fldChar w:fldCharType="end"/>',
  ]) {
    test(
      'independent field oracle rejects an invalid marker stream: $marker',
      () {
        final xml = XmlDocument.parse(
          '<w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:r>$marker</w:r></w:p>',
        );
        expect(() => generatedFieldTreeXmlText(xml), throwsStateError);
      },
    );
  }
}
