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
    await tester.tap(find.text(strings.value('convertEndings', 'CRLF')));
    await tester.pumpAndSettle();
    expect(selected, EditorLineEnding.crlf);
  });

  testWidgets('normalization warning describes the explicit future save', (
    tester,
  ) async {
    for (final locale in AppLocalizations.supportedLocales) {
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
                  cursorLine: 1,
                  cursorColumn: 1,
                  lineCount: 2,
                  language: null,
                  lineEnding: EditorLineEnding.lf,
                  lineEndingPolicy: EditorLineEndingPolicy.normalize,
                  encoding: EditorEncoding.utf8,
                  isModified: true,
                  isSaving: false,
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
      expect(find.byTooltip(strings.value('converted', 'LF')), findsOneWidget);
      expect(find.byTooltip(strings.value('mixed', 'LF')), findsNothing);
      expect(strings.value('converted', 'LF'), isNot(contains('{n}')));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('preservation, new-break and BOM controls remain distinct', (
    tester,
  ) async {
    late CodeDocumentUiStrings strings;
    EditorLineEndingPolicy? policy;
    EditorLineEnding? converted;
    EditorLineEnding? newBreak;
    var bomToggles = 0;
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
                lineCount: 2,
                language: null,
                lineEnding: EditorLineEnding.lf,
                lineEndingPolicy: EditorLineEndingPolicy.normalize,
                encoding: EditorEncoding.utf8,
                isModified: false,
                isSaving: false,
                hadMixedLineEndings: true,
                onPolicySelected: (value) => policy = value,
                onLineEndingSelected: (value) => converted = value,
                onNewLineEndingSelected: (value) => newBreak = value,
                onEncodingSelected: (_) {},
                writesBom: true,
                onToggleBom: () => bomToggles++,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(strings.text('endings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.text('preserveEndings')));
    await tester.pumpAndSettle();
    expect(policy, EditorLineEndingPolicy.preserve);
    expect(converted, isNull);
    expect(newBreak, isNull);

    await tester.tap(find.byTooltip(strings.text('endings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.value('newEndings', 'CRLF')));
    await tester.pumpAndSettle();
    expect(newBreak, EditorLineEnding.crlf);
    expect(converted, isNull);

    await tester.tap(find.byTooltip(strings.text('encoding')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.text('removeBom')));
    await tester.pumpAndSettle();
    expect(bomToggles, 1);
    expect(tester.takeException(), isNull);
  });
}
