import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/panel_error_strings.dart';
import 'package:crisp_cloud/providers/error_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'search failure queue localizes every mode and preserves diagnostics',
    (tester) async {
      final errors = ErrorNotifier();
      addTearDown(errors.dispose);
      const detail = 'request-482: /資料/report {provider}.txt';
      const codes = [
        PanelErrorCode.cloudSearchFailed,
        PanelErrorCode.fullTextSearchFailed,
        PanelErrorCode.findFailed,
        PanelErrorCode.searchUnsupported,
        PanelErrorCode.findUnsupported,
      ];
      final translations = {for (final code in codes) code: <String>{}};
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
        await tester.pumpAndSettle();
        for (final code in codes) {
          final unsupported =
              code == PanelErrorCode.searchUnsupported ||
              code == PanelErrorCode.findUnsupported;
          errors.addError(
            'original diagnostic $detail',
            code: code,
            arguments: unsupported ? {'provider': detail} : {'error': detail},
          );
          final message = localizedPanelError(context, errors.lastAppError!);
          expect(message, contains(detail));
          expect(message, isNot(contains('{error}')));
          expect(message, isNot(startsWith('original diagnostic')));
          expect(errors.lastError, 'original diagnostic $detail');
          translations[code]!.add(message);
          errors.clearLastError();
        }
        expect(errors.hasErrors, isFalse);
      }
      for (final values in translations.values) {
        expect(values, hasLength(9));
      }
    },
  );
}
