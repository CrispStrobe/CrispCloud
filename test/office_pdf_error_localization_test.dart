import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/office_pdf_error_strings.dart';
import 'package:crisp_cloud/services/file_bytes_loader.dart';
import 'package:crisp_cloud/services/office_pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Office PDF failures are localized in all supported locales', (
    tester,
  ) async {
    const cause = FileBytesLoadException(
      'missing',
      code: FileBytesErrorCode.notFound,
      arguments: {'path': '/doc'},
    );
    const error = OfficePdfException(
      'Could not lay out this document: missing',
      cause: cause,
    );
    const large = OfficePdfException('too large', sizeBytes: 65 * 1024 * 1024);
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
      final rendered = localizedOfficePdfError(context, error);
      expect(rendered, contains('/doc'));
      expect(rendered, isNot(contains('{')));
      expect(localizedOfficePdfError(context, large), contains('65.0'));
      expect(localizedOfficePdfError(context, cause), contains('/doc'));
      if (locale.languageCode != 'en') {
        expect(rendered, isNot(startsWith('Could not lay out')));
      }
    }
    expect(error.cause, same(cause));
    expect(error.toString(), 'Could not lay out this document: missing');
  });
}
