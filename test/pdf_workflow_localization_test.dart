import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/pdf_operations_strings.dart';
import 'package:crisp_cloud/l10n/pdf_workflow_translations.dart';
import 'package:crisp_cloud/l10n/pdf_operations_romance.dart';
import 'package:crisp_cloud/l10n/pdf_operations_cjk.dart';
import 'package:crisp_cloud/l10n/pdf_operations_ko_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every PDF operation key is covered by all translated locales', () {
    for (final locale in ['fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      final messages = {
        ...?pdfWorkflowTranslations[locale],
        ...?pdfOperationsRomance[locale],
        ...?pdfOperationsCjk[locale],
        ...?pdfOperationsKoAr[locale],
      };
      expect(
        messages.keys.toSet(),
        PdfOperationsStrings.sourceKeys,
        reason: 'PDF messages for $locale',
      );
      expect(messages.values, everyElement(isNot(isEmpty)));
    }
  });
  test('PDF workflow tables cover the same preview and output messages', () {
    final keys = pdfWorkflowTranslations['fr']!.keys.toSet();
    expect(keys, hasLength(31));
    for (final translations in pdfWorkflowTranslations.values) {
      expect(translations.keys.toSet(), keys);
      expect(translations.values, everyElement(isNot(isEmpty)));
    }
  });

  testWidgets('PDF preview and save workflow follows all nine app locales', (
    tester,
  ) async {
    const saveLabels = {
      'en': 'Save new copy',
      'de': 'Neue Kopie speichern',
      'fr': 'Enregistrer une nouvelle copie',
      'es': 'Guardar nueva copia',
      'pt': 'Guardar nova cópia',
      'zh': '保存新副本',
      'ja': '新しいコピーを保存',
      'ko': '새 사본 저장',
      'ar': 'حفظ نسخة جديدة',
    };
    final closeConfirmations = <String>{};
    final passwords = <String>{};
    final searchLabels = <String>{};
    for (final locale in AppLocalizations.supportedLocales) {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (value) {
              context = value;
              return Text(value.pdfOpTr('Save new copy'));
            },
          ),
        ),
      );
      expect(find.text(saveLabels[locale.languageCode]!), findsOneWidget);
      closeConfirmations.add(context.pdfOpTr('Close without saving?'));
      passwords.add(context.pdfOpTr('Incorrect password. Try again.'));
      searchLabels.add(context.pdfOpTr('Search preview text'));
      // Output filenames and external diagnostics pass through unchanged.
      expect(context.pdfOpTr('report-{name}.pdf'), 'report-{name}.pdf');
      if (locale.languageCode != 'en' && locale.languageCode != 'de') {
        final translations = {
          ...?pdfOperationsKoAr[locale.languageCode],
          ...?pdfOperationsCjk[locale.languageCode],
          ...?pdfOperationsRomance[locale.languageCode],
          ...?pdfWorkflowTranslations[locale.languageCode],
        };
        for (final entry in translations.entries) {
          expect(context.pdfOpTr(entry.key), entry.value);
        }
      }
    }
    expect(closeConfirmations, hasLength(9));
    expect(passwords, hasLength(9));
    expect(searchLabels, hasLength(9));
  });
}
