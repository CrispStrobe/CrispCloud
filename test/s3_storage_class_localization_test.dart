import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/s3_storage_class_strings.dart';
import 'package:crisp_cloud/services/s3_client_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all storage choices translate without changing upload values', (
    tester,
  ) async {
    const expectedRetrieval = {
      'en': 'Glacier Flexible Retrieval',
      'de': 'Glacier – flexibler Abruf',
      'fr': 'Glacier – récupération flexible',
      'es': 'Glacier – recuperación flexible',
      'pt': 'Glacier – recuperação flexível',
      'zh': 'Glacier – 灵活检索',
      'ja': 'Glacier – 柔軟な取り出し',
      'ko': 'Glacier – 유연한 검색',
      'ar': 'Glacier – استرجاع مرن',
    };
    for (final locale in AppLocalizations.supportedLocales) {
      late S3StorageClassStrings strings;
      S3StorageClass? selected;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) {
              strings = S3StorageClassStrings(context);
              return Scaffold(
                body: PopupMenuButton<S3StorageClass>(
                  tooltip: 'storage-class-test',
                  onSelected: (value) => selected = value,
                  itemBuilder: (_) => [
                    for (final value in S3StorageClass.values)
                      PopupMenuItem(
                        value: value,
                        child: Text(strings.label(value)),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        strings.label(S3StorageClass.glacier),
        expectedRetrieval[locale.languageCode],
      );
      expect(S3StorageClass.values.map(strings.label).toSet(), hasLength(8));
      for (final value in S3StorageClass.values) {
        expect(strings.label(value), isNotEmpty);
      }
      await tester.tap(find.byTooltip('storage-class-test'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(strings.label(S3StorageClass.glacier)));
      await tester.pumpAndSettle();
      expect(selected, S3StorageClass.glacier);
      expect(selected!.headerValue, 'GLACIER');
      expect(S3StorageClass.standardIa.headerValue, 'STANDARD_IA');
      expect(S3StorageClass.deepArchive.headerValue, 'DEEP_ARCHIVE');
    }
  });
}
