import 'package:flutter/material.dart' as host;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as editor;
import 'package:pro_image_editor/shared/widgets/overlays/editor_bottom_sheet.dart';

void main() {
  testWidgets('root-navigator sheet retains scoped editor localizations and theme', (tester) async {
    late host.BuildContext sourceContext;
    String? translatedClose;
    host.Color? sheetPrimary;
    await tester.pumpWidget(
      host.MaterialApp(
        home: host.Builder(
          builder: (context) => host.Localizations.override(
            context: context,
            locale: const host.Locale('de'),
            delegates: editor.GlobalMaterialLocalizations.delegates,
            child: editor.Theme(
              data: editor.ThemeData(colorSchemeSeed: host.Colors.green),
              child: host.Builder(
                builder: (context) {
                  sourceContext = context;
                  return editor.Scaffold(
                    body: editor.TextButton(
                      onPressed: () => showEditorModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        builder: (sheetContext) {
                          translatedClose = editor.MaterialLocalizations.of(sheetContext).closeButtonTooltip;
                          sheetPrimary = editor.Theme.of(sheetContext).colorScheme.primary;
                          return editor.TextButton(
                            onPressed: () => host.Navigator.of(sheetContext).pop(),
                            child: const host.Text('Dismiss sheet'),
                          );
                        },
                      ),
                      child: const host.Text('Open sheet'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    final sourcePrimary = editor.Theme.of(sourceContext).colorScheme.primary;
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(translatedClose, 'Schließen');
    expect(sheetPrimary, sourcePrimary);
    expect(host.ModalRoute.of(sourceContext)!.isCurrent, isFalse);
    await tester.tap(find.text('Dismiss sheet'));
    await tester.pumpAndSettle();
    expect(host.ModalRoute.of(sourceContext)!.isCurrent, isTrue);
    expect(find.text('Open sheet'), findsOneWidget);
  });
}
