import 'dart:typed_data';
import 'dart:convert';

import 'package:archive/archive.dart';

import 'dart:ui';

import 'package:crisp_cloud/l10n/office_preview_strings.dart';
import 'package:crisp_cloud/services/locale_preference.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'parser marks legacy and extraction fallback prose for translation',
    () async {
      final legacy = await parseOfficeDocument(Uint8List(0), 'old.ppt');
      final invalid = await parseOfficeDocument(Uint8List(0), 'bad.docx');
      expect(legacy.fallback, OfficePreviewFallback.extractionFailed);
      expect(legacy.notice, OfficePreviewNotice.powerPointMalformed);
      expect(invalid.fallback, OfficePreviewFallback.extractionFailed);
      final english = OfficePreviewStrings(const Locale('en'));
      for (final language in LocalePreference.supported.difference({'en'})) {
        final strings = OfficePreviewStrings(Locale(language));
        expect(
          strings.text(legacy),
          isNot(english.text(legacy)),
          reason: language,
        );
        expect(
          strings.note(legacy),
          isNot(english.note(legacy)),
          reason: language,
        );
        expect(
          strings.text(invalid),
          isNot(english.text(invalid)),
          reason: language,
        );
      }
    },
  );

  test(
    'every portable-preview notice is translated in all supported locales',
    () {
      final english = OfficePreviewStrings(const Locale('en'));
      for (final notice in OfficePreviewNotice.values) {
        final document = OfficeDocument(
          kind: OfficeDocumentKind.document,
          markdown: '',
          plainText: '',
          notice: notice,
        );
        expect(english.note(document), isNotEmpty);
        for (final language in LocalePreference.supported.difference({'en'})) {
          expect(
            OfficePreviewStrings(Locale(language)).note(document),
            isNot(english.note(document)),
            reason: '$language ${notice.name}',
          );
        }
      }
    },
  );

  test(
    'document text and external error notes are never translated by content',
    () {
      const document = OfficeDocument(
        kind: OfficeDocumentKind.document,
        markdown: '',
        plainText: '(Could not extract text from this document)',
        note: 'external server detail',
      );
      final strings = OfficePreviewStrings(const Locale('es'));
      expect(strings.text(document), document.plainText);
      expect(strings.note(document), document.note);
    },
  );

  test('only parser-generated headings are translated in each output', () async {
    const xml =
        '<worksheet><sheetData><row><c r="A1" t="inlineStr"><is><t>Sheet 1</t></is></c></row></sheetData></worksheet>';
    final archive = Archive()
      ..addFile(
        ArchiveFile.bytes('xl/worksheets/sheet1.xml', utf8.encode(xml)),
      );
    final document = await parseOfficeDocument(
      Uint8List.fromList(ZipEncoder().encode(archive)),
      'test.xlsx',
    );
    final locale = const Locale('es');
    final strings = OfficePreviewStrings(locale);
    final markdown = strings.headings(
      document.markdown,
      document.markdownHeadings,
      locale,
    );
    final text = strings.headings(
      document.plainText,
      document.textHeadings,
      locale,
    );
    final csv = strings.headings(document.csv!, document.csvHeadings, locale);
    expect(markdown, contains('## Hoja 1'));
    expect(markdown, contains('| Sheet 1 |'));
    expect(text, contains('Hoja 1'));
    expect(text, contains('Sheet 1'));
    expect(csv, contains('# Hoja 1'));
    expect(csv, contains('Sheet 1'));
    for (final language in LocalePreference.supported) {
      final translated = strings.headings(
        document.markdown,
        document.markdownHeadings,
        Locale(language),
      );
      expect(translated, contains('| Sheet 1 |'));
    }
  });

  test('missing part messages preserve the format and part names', () {
    const document = OfficeDocument(
      kind: OfficeDocumentKind.spreadsheet,
      markdown: '',
      plainText: '',
      fallback: OfficePreviewFallback.missingOds,
    );
    for (final language in LocalePreference.supported) {
      final message = OfficePreviewStrings(Locale(language)).text(document);
      expect(message, contains('ODS'));
      expect(message, contains('content.xml'));
    }
  });
}
