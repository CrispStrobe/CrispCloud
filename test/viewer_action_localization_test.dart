import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/viewer_action_strings.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('viewer action feedback translates in all nine locales', (
    tester,
  ) async {
    final errors = <String>{};
    final restrictions = <String>{};
    for (final locale in AppLocalizations.supportedLocales) {
      late ViewerActionStrings strings;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) {
              strings = ViewerActionStrings(context);
              return const SizedBox();
            },
          ),
        ),
      );
      final message = strings.cannotView(
        'report-{error}.zip',
        'OS detail {name}',
      );
      expect(message, contains('report-{error}.zip'));
      expect(message, contains('OS detail {name}'));
      errors.add(message);
      restrictions.add(strings.archiveEditingUnsupported);
    }
    expect(errors, hasLength(9));
    expect(restrictions, hasLength(9));
  });

  testWidgets('archive viewer failures retain localized causes', (
    tester,
  ) async {
    late ViewerActionStrings strings;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) {
            strings = ViewerActionStrings(context);
            return const SizedBox();
          },
        ),
      ),
    );
    final error = ArchiveViewException(
      'diagnostic',
      code: ArchiveMessageCode.closed,
    );
    expect(
      strings.cannotView('test.zip', error),
      'test.zip kann nicht angezeigt werden: Dieses Archiv wurde geschlossen.',
    );
    expect(strings.archiveEditingUnsupported, contains('Entpacken'));
  });
}
