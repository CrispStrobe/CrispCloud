import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import 'support/list_word_fixture.dart';
import 'support/media_word_fixture.dart';
import 'support/paragraph_style_transition_fixture.dart';

// `recover: true` is for opening a document for a person: damage confined to
// an auxiliary feature omits or normalizes that feature with a disclosed
// warning instead of refusing the document. The default (strict) behaviour is
// pinned by the existing rejection tests and is unchanged.
void main() {
  group('recover mode', () {
    for (final kind in paragraphTransientStyleKinds.keys) {
      test('final $kind paragraph style falls back to Normal', () {
        final bytes = paragraphStyleTransitionFixture(
          kind,
          finalSelection: false,
        );
        expect(() => parseLegacyWordDocument(bytes), throwsFormatException);
        final document = parseLegacyWordDocument(bytes, recover: true);
        expect(document.warnings, contains(LegacyWordWarning.recoveredMissingStyle));
        expect(document.plainText, isNotEmpty);
        final conversion = convertLegacyWord(bytes, recover: true);
        expect(
          conversion.limitations,
          contains(LegacyWordConversionLimitation.partialFormatting),
        );
      });
    }

    test('invalid list tables keep the text without numbering', () {
      final bytes = listWordFixture(
        instances: listFixtureInstances(sourceId: 99),
      );
      expect(() => parseLegacyWordDocument(bytes), throwsFormatException);
      final document = parseLegacyWordDocument(bytes, recover: true);
      expect(document.numbering, isEmpty);
      expect(
        document.warnings,
        contains(LegacyWordWarning.numberingNotReconstructed),
      );
      expect(document.plainText, contains('Item'));
    });

    test('an overlong picture record omits only that picture', () {
      final picf = inlinePictureData();
      ByteData.sublistView(picf).setUint32(0, 0x7fffffff, Endian.little);
      final bytes = inlinePictureWordFixture(picture: picf);
      expect(() => parseLegacyWordDocument(bytes), throwsFormatException);
      final document = parseLegacyWordDocument(bytes, recover: true);
      expect(document.media.pictures, isEmpty);
      expect(
        document.media.notices.map((n) => n.issue),
        contains(LegacyWordMediaIssue.unsupportedImage),
      );
    });

    test('a well-formed document is identical in both modes', () {
      final bytes = listWordFixture();
      final strict = parseLegacyWordDocument(bytes);
      final recovered = parseLegacyWordDocument(bytes, recover: true);
      expect(recovered.plainText, strict.plainText);
      expect(recovered.warnings, strict.warnings);
      expect(
        convertLegacyWord(bytes, recover: true).bytes,
        convertLegacyWord(bytes).bytes,
      );
    });
  });
}
