import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/external_drop_strings.dart';
import 'package:crisp_cloud/services/external_drop_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      'external drop errors and lifetime guidance render in ${locale.languageCode}',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                final strings = ExternalDropStrings(context);
                return Scaffold(
                  body: SingleChildScrollView(
                    child: Column(
                      children: [
                        Text(strings.text('files')),
                        Text(strings.text('foreground')),
                        for (final failure in ExternalDropFailure.values)
                          Text(strings.failure(ExternalDropException(failure))),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(Text),
          findsNWidgets(ExternalDropFailure.values.length + 2),
        );
        expect(tester.takeException(), isNull);
        final labels = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data!);
        expect(labels.every((label) => label.trim().isNotEmpty), isTrue);
        if (locale.languageCode != 'en') {
          expect(
            labels,
            isNot(contains(ExternalDropStrings.messages['foreground']!.first)),
          );
        }
      },
    );
  }
}
