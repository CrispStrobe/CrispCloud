// test/widget/office_paragraph_dialog_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'package:crisp_cloud/widgets/office_editor_dialogs.dart';

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
    expect(find.text('Tab stops (pt, comma separated)'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Drop cap lines'),
      '2',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Paragraph border (RRGGBB)'),
      'C00000',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Tab stops (pt, comma separated)'),
      '72, 144',
    );
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final choice = await result;
    expect(choice, isNotNull);
    expect(choice!.dropCapLines, 2);
    expect(choice.borderColor, 'C00000');
    expect(choice.tabStops, <double>[72, 144]);
  });
}
