// test/widget/office_paragraph_dialog_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'package:crisp_cloud/widgets/office_editor_dialogs.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';

void main() {
  testWidgets('paragraph dialog exposes spacing, borders, drop caps and tabs', (
    tester,
  ) async {
    late Future<WordParagraphChoice?> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                result = showWordParagraphDialog(
                  context,
                  current: WmlParagraphProps(),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Line spacing rule'), findsOneWidget);
    expect(find.text('Drop cap lines'), findsOneWidget);
    expect(find.text('Paragraph border (RRGGBB)'), findsOneWidget);
    expect(find.text('Custom tab stops'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Drop cap lines'),
      '2',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Paragraph border (RRGGBB)'),
      'C00000',
    );
    final add = find.byKey(const ValueKey<String>('word-tab-add'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('word-tab-position-0')),
      '72',
    );
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    final second = find.byKey(const ValueKey<String>('word-tab-position-1'));
    await tester.ensureVisible(second);
    await tester.enterText(second, '144');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final choice = await result;
    expect(choice, isNotNull);
    expect(choice!.dropCapLines, 2);
    expect(choice.borderColor, 'C00000');
    expect(choice.tabStops.map((tab) => tab.position), <double>[72, 144]);
  });
  testWidgets(
    'host translates the shared tab controls and accepts decimal commas',
    (tester) async {
      late Future<WordParagraphChoice?> result;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  result = showWordParagraphDialog(
                    context,
                    current: WmlParagraphProps(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Benutzerdefinierte Tabstopps'), findsOneWidget);
      final add = find.text('Tabstopp hinzufügen');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      final position = find.byKey(
        const ValueKey<String>('word-tab-position-0'),
      );
      await tester.ensureVisible(position);
      await tester.enterText(position, '36,25');
      expect(find.text('Tabstoppposition (pt)'), findsOneWidget);
      expect(find.text('Tabstoppausrichtung'), findsOneWidget);
      expect(find.text('Füllzeichen'), findsOneWidget);
      final alignment = find.byKey(
        const ValueKey<String>('word-tab-alignment-0'),
      );
      await tester.ensureVisible(alignment);
      await tester.tap(alignment);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dezimal').last);
      await tester.pumpAndSettle();
      final leader = find.byKey(const ValueKey<String>('word-tab-leader-0'));
      await tester.ensureVisible(leader);
      await tester.tap(leader);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Punkte').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Anwenden'));
      await tester.pumpAndSettle();
      final tab = (await result)!.tabStops.single;
      expect(
        (tab.position, tab.alignment, tab.leader),
        (36.25, WmlTabAlignment.decimal, WmlTabLeader.dot),
      );
    },
  );
}
