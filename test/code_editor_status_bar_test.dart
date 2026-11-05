// Layout regression tests for the responsive editor status bar.

import 'package:crisp_cloud/services/editor_document.dart';
import 'package:crisp_cloud/widgets/code_editor_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(double width, {bool mixed = false}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: CodeEditorStatusBar(
            cursorLine: 12,
            cursorColumn: 34,
            lineCount: 120,
            language: 'Dart',
            lineEnding: EditorLineEnding.crlf,
            encoding: EditorEncoding.utf8,
            isModified: true,
            isSaving: false,
            hadMixedLineEndings: mixed,
            onLineEndingSelected: (_) {},
            onEncodingSelected: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('wide status bar shows document information', (tester) async {
    await tester.pumpWidget(_host(800));

    expect(find.text('Ln 12, Col 34'), findsOneWidget);
    expect(find.text('120 lines'), findsOneWidget);
    expect(find.text('Dart'), findsOneWidget);
    expect(find.text('CRLF'), findsOneWidget);
    expect(find.text('UTF-8'), findsOneWidget);
    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow status bar drops optional information without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(_host(320));

    expect(find.text('Ln 12, Col 34'), findsOneWidget);
    expect(find.text('120 lines'), findsNothing);
    expect(find.text('Dart'), findsNothing);
    expect(find.text('CRLF'), findsOneWidget);
    expect(find.text('UTF-8'), findsOneWidget);
    expect(find.text('Unsaved changes'), findsNothing);
    expect(find.byIcon(Icons.edit), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mixed line endings add a warning without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(_host(320, mixed: true));

    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
