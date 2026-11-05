import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/code_document_ui_strings.dart';
import 'package:crisp_cloud/services/editor_document.dart';
import 'package:crisp_cloud/widgets/code_editor_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'status bar translates state, position and warnings in nine locales',
    (tester) async {
      for (final locale in AppLocalizations.supportedLocales) {
        for (final state in ['saved', 'unsaved', 'saving']) {
          late CodeDocumentUiStrings strings;
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: Builder(
                builder: (context) {
                  strings = CodeDocumentUiStrings(context);
                  return Scaffold(
                    body: CodeEditorStatusBar(
                      cursorLine: 7,
                      cursorColumn: 3,
                      lineCount: 12,
                      language: null,
                      lineEnding: EditorLineEnding.crlf,
                      encoding: EditorEncoding.utf8,
                      isModified: state == 'unsaved',
                      isSaving: state == 'saving',
                      hadMixedLineEndings: true,
                      onLineEndingSelected: (_) {},
                      onEncodingSelected: (_) {},
                    ),
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(strings.text(state)), findsOneWidget);
          expect(find.text(strings.cursor(7, 3)), findsOneWidget);
          expect(find.text(strings.value('lines', 12)), findsOneWidget);
          expect(find.text(strings.text('plain')), findsOneWidget);
          expect(
            find.byTooltip(strings.value('mixed', 'CRLF')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          if (locale.languageCode != 'en') {
            expect(find.text('Plain text'), findsNothing);
            expect(strings.text('goLine'), isNot('Go to line'));
          }
          expect(
            strings.value('newer', 'sample.dart'),
            contains('sample.dart'),
          );
          expect(
            strings.value('encodingError', 'Latin-1'),
            contains('Latin-1'),
          );
          expect(
            strings.value('encodingError', 'Latin-1'),
            isNot(contains('{n}')),
          );
        }
      }
    },
  );

  testWidgets('format selection retains callback values after localization', (
    tester,
  ) async {
    EditorLineEnding? selected;
    late CodeDocumentUiStrings strings;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) {
            strings = CodeDocumentUiStrings(context);
            return Scaffold(
              body: CodeEditorStatusBar(
                cursorLine: 1,
                cursorColumn: 1,
                lineCount: 1,
                language: null,
                lineEnding: EditorLineEnding.lf,
                encoding: EditorEncoding.utf8,
                isModified: false,
                isSaving: false,
                hadMixedLineEndings: false,
                onLineEndingSelected: (value) => selected = value,
                onEncodingSelected: (_) {},
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(strings.text('endings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CRLF'));
    await tester.pumpAndSettle();
    expect(selected, EditorLineEnding.crlf);
  });
}
