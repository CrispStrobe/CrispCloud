import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pro_image_editor/features/paint_editor/widgets/paint_editor_layer_editor.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/shared/utils/format_editor_number.dart';
import 'package:pro_image_editor/shared/widgets/slider_bottom_sheet.dart';

Widget _app(Widget child, {Locale locale = const Locale('de')}) => MaterialApp(
  locale: locale,
  supportedLocales: const [Locale('en'), Locale('de')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('editor numbers follow the active locale and fraction precision', (
    tester,
  ) async {
    Widget numbers() => Builder(
      builder: (context) => Text(
        formatEditorNumber(context, 1234.5, fractionDigits: 2),
      ),
    );

    await tester.pumpWidget(_app(numbers()));
    await tester.pumpAndSettle();
    expect(find.text('1.234,50'), findsOneWidget);

    await tester.pumpWidget(_app(numbers(), locale: const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('1,234.50'), findsOneWidget);
  });

  testWidgets('font-scale sheet localizes the value, close and reset controls', (
    tester,
  ) async {
    final updates = <double>[];
    final stream = StreamController<void>.broadcast();
    addTearDown(stream.close);
    await tester.pumpWidget(
      _app(
        SliderBottomSheet<Object>(
          title: 'Schriftgröße',
          headerTextStyle: null,
          min: 0.5,
          max: 5,
          divisions: 45,
          closeButton: null,
          customSlider: null,
          state: Object(),
          value: 1.5,
          designMode: ImageEditorDesignMode.material,
          theme: ThemeData(),
          rebuildController: stream,
          onValueChanged: updates.add,
          resetIcon: Icons.restart_alt,
          resetLabel: 'Zurücksetzen',
          showFactorInTitle: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Schriftgröße 1,5×'), findsOneWidget);
    expect(find.byTooltip('Schließen'), findsOneWidget);

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.semanticFormatterCallback!(1.5), '1,5×');
    slider.onChanged!(2);
    await tester.pumpAndSettle();
    expect(find.text('Schriftgröße 2,0×'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurücksetzen'));
    await tester.pumpAndSettle();
    expect(updates, <double>[2, 1.5]);
    expect(find.text('Schriftgröße 1,5×'), findsOneWidget);
  });

  testWidgets('paint layer sliders localize visible and spoken decimal values', (
    tester,
  ) async {
    final layer = PaintLayer(
      rawSize: const Size.square(100),
      opacity: 0.5,
      item: PaintedModel(
        color: Colors.blue,
        strokeWidth: 1.5,
        fill: false,
        mode: PaintMode.rect,
        offsets: [Offset.zero, const Offset(100, 100)],
        erasedOffsets: [],
        opacity: 1,
      ),
    );
    await tester.pumpWidget(
      _app(
        PaintEditorLayerEditor(
          layer: layer,
          configs: const ProImageEditorConfigs(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders.map((slider) => slider.label), containsAll(['0,50', '1,5']));
    for (final slider in sliders) {
      expect(slider.semanticFormatterCallback!(slider.value), slider.label);
    }
  });
}
