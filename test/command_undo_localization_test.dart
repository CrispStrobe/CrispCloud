import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/command_strings.dart';
import 'package:crisp_cloud/l10n/undo_presentation.dart';
import 'package:crisp_cloud/services/action_history_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('action descriptions and undo results are localized in German',
      (tester) async {
    late UndoPresentation presentation;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) {
        presentation = UndoPresentation(context);
        return const SizedBox();
      }),
    ));
    final service = ActionHistoryService();
    final action = ActionRecord(
        id: 'x',
        timestamp: DateTime(2020),
        type: ActionType.rename,
        originalPath: '/old.txt',
        newPath: '/new.txt',
        provider: 'remote');
    service.record(action);
    expect(presentation.description(action), 'old.txt → new.txt umbenannt');
    final result =
        await service.undo('x', UndoContext(remoteRename: (_, __) async {}));
    expect(result.success, isTrue);
    expect(presentation.result(result), 'new.txt zurück in old.txt umbenannt.');
    expect(result.message, 'Renamed new.txt back to old.txt.');
  });

  testWidgets('undo errors and command search translate in all locales',
      (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
            builder: (context) => Column(children: [
                  Text(UndoPresentation(context).result(
                      const UndoResult.failure('fallback',
                          code: UndoResultCode.undoFailed,
                          arguments: {'error': 'reason-42'}))),
                  Text(CommandStrings(context).text('query')),
                ])),
      ));
      expect(find.textContaining('reason-42'), findsOneWidget);
      expect(find.textContaining('fallback'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
