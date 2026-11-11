import 'dart:ui' show SemanticsAction, Tristate;

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/file_list_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/file_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('file list labels preserve translations and placeholders', () {
    final translations = FileListStrings.translations;
    expect(translations.keys.toSet(), {
      'de',
      'fr',
      'es',
      'pt',
      'zh',
      'ja',
      'ko',
      'ar',
    });
    final keys = translations['de']!.keys.toSet();
    for (final locale in translations.entries) {
      expect(locale.value.keys.toSet(), keys, reason: locale.key);
      for (final entry in locale.value.entries) {
        expect(entry.value, isNotEmpty, reason: '${locale.key}: ${entry.key}');
        for (final match in RegExp(r'\{[^}]+\}').allMatches(entry.key)) {
          expect(entry.value, contains(match.group(0)), reason: locale.key);
        }
      }
    }
    final strings = FileListStrings.forLanguage('de');
    expect(
      strings.semantic(folder: false, name: 'a.txt', selected: true),
      'Datei a.txt, unbekannte Größe, ausgewählt',
    );
  });

  testWidgets('compact file tile exposes localized screen reader text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final semantics = tester.ensureSemantics();
    try {
      final file = FileItem(name: 'a.txt', isFolder: false, size: 100);
      var taps = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: CompactFileTile(
                file: file,
                side: PanelSide.local,
                isSelected: true,
                onTap: (_, __) => taps++,
                onDoubleTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final semanticRow = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            (widget.properties.label?.startsWith('Datei a.txt,') ?? false) &&
            (widget.properties.label?.endsWith('ausgewählt') ?? false),
      );
      expect(semanticRow, findsOneWidget);
      final node = tester.getSemantics(semanticRow);
      final data = node.getSemanticsData();
      expect(data.label, startsWith('Datei a.txt,'));
      expect(data.label, contains('ausgewählt'));
      expect(data.flagsCollection.isSelected, Tristate.isTrue);
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      expect(taps, 1);
      expect(find.byType(Draggable<PanelDragData>), findsNothing);
      expect(find.byType(LongPressDraggable<PanelDragData>), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });

  for (final path in <String?>[null, '']) {
    testWidgets(
      'a folder row with ${path == null ? 'no' : 'an empty'} path keeps localized focus semantics',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                locale: const Locale('de'),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                home: Scaffold(
                  body: CompactFileTile(
                    file: FileItem(
                      name: 'Entwürfe',
                      path: path,
                      isFolder: true,
                    ),
                    side: PanelSide.local,
                    isSelected: false,
                    isCursor: true,
                    onTap: (_, __) {},
                    onDoubleTap: () {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final semanticRow = find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Ordner Entwürfe',
          );
          expect(semanticRow, findsOneWidget);
          final data = tester.getSemantics(semanticRow).getSemanticsData();
          expect(data.label, startsWith('Ordner Entwürfe'));
          expect(data.flagsCollection.isSelected, Tristate.isFalse);
          expect(data.flagsCollection.isFocused, Tristate.isTrue);
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.hasAction(SemanticsAction.tap), isTrue);
          expect(find.byType(Draggable<PanelDragData>), findsNothing);
          expect(find.byType(LongPressDraggable<PanelDragData>), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
