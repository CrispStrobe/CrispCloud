import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/native_preview_error_strings.dart';
import 'package:crisp_cloud/services/pdf_text_service.dart';
import 'package:crisp_cloud/services/system_preview_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('native preview and PDF errors follow each selected language', (
    tester,
  ) async {
    const preview = SystemPreviewException(
      'Quick Look preview is unavailable',
      code: 'preview_failed',
    );
    const pdf = PdfTextException(
      'Could not open the PDF document',
      code: 'pdf_open_failed',
    );
    const external = SystemPreviewException(
      'external detail 42',
      code: 'unknown_native_error',
    );
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
              return const SizedBox();
            },
          ),
        ),
      );
      final previewText = localizedNativePreviewError(context, preview);
      final pdfText = localizedNativePreviewError(context, pdf);
      expect(previewText, isNotEmpty);
      expect(pdfText, isNotEmpty);
      if (locale.languageCode != 'en') {
        expect(previewText, isNot('Quick Look preview is unavailable.'));
        expect(pdfText, isNot('Could not open the PDF document.'));
      }
      expect(
        localizedNativePreviewError(context, external),
        'external detail 42',
      );
    }
  });
}
