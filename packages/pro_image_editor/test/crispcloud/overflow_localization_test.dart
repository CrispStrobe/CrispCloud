import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pro_image_editor/features/text_editor/widgets/text_editor_appbar.dart';
import 'package:pro_image_editor/features/text_editor/widgets/text_editor_bottom_bar.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

void main() {
  testWidgets('text overflow sheet uses the supplied localized Cancel label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: TextEditorAppBar(
            textEditorConfigs: const TextEditorConfigs(),
            i18n: const I18nTextEditor(
              cancel: 'Abbrechen',
              smallScreenMoreTooltip: 'Weitere Optionen',
            ),
            constraints: const BoxConstraints(maxWidth: 180),
            designMode: ImageEditorDesignMode.cupertino,
            align: TextAlign.left,
            onClose: () {},
            onDone: () {},
            onToggleTextAlign: () {},
            onOpenFontScaleBottomSheet: () {},
            onToggleBackgroundMode: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Weitere Optionen'));
    await tester.pumpAndSettle();
    expect(find.text('Abbrechen'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);

    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.text('Abbrechen'), findsNothing);
  });

  testWidgets('font chooser displays the localized script sample', (
    tester,
  ) async {
    const style = TextStyle(fontFamily: 'ExampleFont');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextEditorBottomBar(
            configs: const ProImageEditorConfigs(
              i18n: I18n(
                textEditor: I18nTextEditor(fontFamilyExampleText: 'أب'),
              ),
              textEditor: TextEditorConfigs(customTextStyles: [style]),
            ),
            selectedStyle: style,
            onFontChange: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('أب'), findsOneWidget);
    expect(find.text('Aa'), findsNothing);
  });
}
