import 'dart:ui';

import 'package:crisp_cloud/l10n/office_preview_strings.dart';
import 'package:crisp_cloud/l10n/word_format_strings.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Word notes and safety failures translate in every application language',
    () {
      for (final code in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
        final strings = WordFormatStrings(Locale(code));
        for (final message in WordFormatStrings.english) {
          expect(
            strings.translate(message),
            isNotNull,
            reason: '$code: $message',
          );
          expect(
            strings.translate(message),
            isNot(message),
            reason: '$code: $message',
          );
          expect(
            strings.translate('FormatException: $message'),
            strings.translate(message),
          );
        }
        expect(
          strings.translate('Truncated Word binary document.'),
          strings.translate(WordFormatStrings.english.last),
        );
        final preview = OfficeDocument(
          kind: OfficeDocumentKind.document,
          markdown: '',
          plainText: 'Authored text stays as written.',
          note: WordFormatStrings.english.first,
        );
        expect(
          OfficePreviewStrings(Locale(code)).note(preview),
          strings.translate(preview.note!),
        );
        expect(
          OfficePreviewStrings(Locale(code)).text(preview),
          preview.plainText,
        );
      }
    },
  );

  test('unrelated messages retain their original meaning', () {
    expect(
      WordFormatStrings(const Locale('de')).translate('Provider disconnected'),
      isNull,
    );
    expect(
      WordFormatStrings(const Locale('en'))
          .translate(WordFormatStrings.english.first),
      WordFormatStrings.english.first,
    );
  });
}
