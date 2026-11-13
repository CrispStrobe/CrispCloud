// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../tool/list_metadata_web_acceptance.dart';
import 'support/list_metadata_fixture.dart';

List<String> _labels(LegacyWordDocument document) =>
    XmlDocument.parse(document.safeHtml)
        .findAllElements('span')
        .where(
          (element) => element.getAttribute('data-word-list-label') == 'true',
        )
        .map((element) => element.innerText)
        .toList();

void main() {
  test('shared VM and JavaScript list metadata acceptance', () {
    expect(verifyListMetadataWebAcceptance(), {
      'cases': 21,
      'supportedCases': 15,
      'unsupportedLiteralLabelsRejected': 5,
      'invalidNumberedRestartsRejected': 1,
      'literalLabelsPreserved': true,
      'sourceUnchanged': true,
    });
  });

  for (final name in unsupportedListMetadataCases) {
    test('declines an unrepresentable literal list label: $name', () {
      final source = listMetadataFixture(name);
      final before = source.toList();
      expect(
        () => parseLegacyWordDocument(source),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('literal percent-number sequence'),
          ),
        ),
      );
      expect(source, before);
    });
  }

  for (final (name, labels) in [
    ('none-literal', ['Appendix']),
    ('none-empty-placeholder', ['Appendix .']),
    ('none-ancestor-placeholder', ['3.', '3 Appendix ']),
    ('literal-percent-text', ['% %0 %x 50%']),
    ('percent-before-placeholder', ['%7 %']),
  ]) {
    test('retains the exact list label: $name', () {
      final source = listMetadataFixture(name);
      final before = source.toList();
      final document = parseLegacyWordDocument(source);
      expect(_labels(document), labels);
      expect(source, before);
      expect(
        document.warnings,
        isNot(contains(LegacyWordWarning.numberingNotReconstructed)),
      );
      expect(convertLegacyWordDocument(document).bytes, isNotEmpty);
    });
  }
}
