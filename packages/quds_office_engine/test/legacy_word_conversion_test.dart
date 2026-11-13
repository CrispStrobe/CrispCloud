import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import 'support/legacy_word_fixture.dart';

void main() {
  test('converts Word 97 body text to an editable new DOCX', () {
    final source = legacyWordFixture(
      '  Unicode 世界 😀 <tag> & data\r\rCell\x07Next\rEnd\r',
      withOpaqueMacro: true,
    );
    final original = Uint8List.fromList(source);
    final copy = convertLegacyWordToDocx(source);
    final package = OpcPackage.openBytes(copy);
    final document = WordDeserializer().read(package);

    expect(package.kind, OpcPackageKind.word);
    expect(document.paragraphs.map((paragraph) => paragraph.text), [
      '  Unicode 世界 😀 <tag> & data',
      '',
      'Cell\tNext',
      'End',
    ]);
    expect(source, orderedEquals(original));
    expect(package.partNames, ['/word/document.xml']);
    expect(
      package.contentTypes.contentTypeFor('/word/document.xml'),
      OfficeContentTypes.wordMain,
    );
    expect(package.relationshipsFor('/word/document.xml').isEmpty, isTrue);
    expect(
      package.getPart('/word/document.xml')!.readText(),
      isNot(contains('DELETED SECRET')),
    );
    document.paragraphs.last.inlines.whereType<WmlRun>().single.text = 'Edited';
    final reopened = WordDeserializer().read(
      OpcPackage.openBytes(WordSerializer().writeBytes(document)),
    );
    expect(reopened.paragraphs.last.text, 'Edited');
    expect(source, orderedEquals(original));
  });

  test('empty main story creates a valid blank DOCX', () {
    final package = OpcPackage.openBytes(
      convertLegacyWordToDocx(legacyWordFixture('')),
    );
    expect(WordDeserializer().read(package).paragraphs.single.text, isEmpty);
  });

  test('rejects encrypted and malformed DOC without changing its bytes', () {
    for (final source in [
      legacyWordFixture('Secret\r', encrypted: true),
      Uint8List.fromList([1, 2, 3, 4]),
    ]) {
      final original = Uint8List.fromList(source);
      expect(() => convertLegacyWordToDocx(source), throwsFormatException);
      expect(source, orderedEquals(original));
    }
  });

  test('rejects illegal XML text before creating a DOCX', () {
    for (final invalid in [0xfffe, 0xffff]) {
      expect(
        () => convertLegacyWordToDocx(
          legacyWordFixture('Before${String.fromCharCode(invalid)}after\r'),
        ),
        throwsA(
          isA<LegacyWordConversionException>().having(
            (error) => error.issue,
            'issue',
            LegacyWordConversionIssue.invalidText,
          ),
        ),
      );
    }
  });

  test('malformed UTF-16 is rejected by the parser before conversion', () {
    final source = legacyWordFixture('Before\ud800after\r');
    final original = Uint8List.fromList(source);
    expect(
      () => convertLegacyWordToDocx(source),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Invalid UTF-16'),
        ),
      ),
    );
    expect(source, orderedEquals(original));
  });

  test('rejects excessive structural expansion before splitting text', () {
    final source = legacyWordFixture(
      '${'A\t' * (kLegacyWordDocxBreakLimit + 1)}End\r',
    );
    expect(
      () => convertLegacyWordToDocx(source),
      throwsA(
        isA<LegacyWordConversionException>().having(
          (error) => error.issue,
          'issue',
          LegacyWordConversionIssue.tooComplex,
        ),
      ),
    );
  });

  test('proposed and accepted copy names cannot redirect storage', () {
    expect(suggestedLegacyWordDocxName('report.DOC'), 'report (text).docx');
    expect(suggestedLegacyWordDocxName('template.dot'), 'template (text).docx');
    expect(suggestedLegacyWordDocxName('../folder/a:b.doc'), 'a_b (text).docx');
    expect(
      suggestedLegacyWordDocxName('${'a' * 199}😀.doc'),
      '${'a' * 199} (text).docx',
    );
    expect(validateLegacyWordDocxName(' New copy.DOCX '), 'New copy.DOCX');
    for (final invalid in [
      '',
      '.docx',
      '../other.docx',
      '/absolute.docx',
      r'folder\copy.docx',
      'copy.doc',
      'copy.dotm',
      'bad\x00.docx',
      '${'a' * 251}.docx',
    ]) {
      expect(
        () => validateLegacyWordDocxName(invalid),
        throwsA(isA<LegacyWordConversionException>()),
        reason: invalid,
      );
    }
  });
}
