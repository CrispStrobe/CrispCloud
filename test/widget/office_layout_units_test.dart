import 'package:crisp_cloud/services/office_measurement_preferences.dart';
import 'package:crisp_cloud/widgets/office_page_layout_dialog.dart';
import 'package:crisp_cloud/widgets/office_dimension_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _host(
  WidgetTester tester,
  VoidCallback Function(BuildContext) action,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: action(context),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'measurement preference persists and rejects unknown stored values',
    () async {
      SharedPreferences.setMockInitialValues({});
      expect(
        await OfficeMeasurementPreferences.read(),
        OfficeLengthUnit.millimeters,
      );
      await OfficeMeasurementPreferences.write(OfficeLengthUnit.inches);
      expect(
        await OfficeMeasurementPreferences.read(),
        OfficeLengthUnit.inches,
      );
    },
  );
  testWidgets(
    'metric layout dialog preserves exact imported geometry on untouched Apply',
    (tester) async {
      OfficePageLayoutChoice? result;
      const size = WmlPageSize(width: 595.276, height: 841.89);
      const margins = WmlPageMargins(
        top: 72.05,
        bottom: 72.123,
        left: 72.765,
        right: 76.55,
        header: 36.25,
        footer: 35.75,
      );
      await _host(
        tester,
        (context) => () async {
          result = await showOfficePageLayoutDialog(
            context,
            size: size,
            margins: margins,
            unit: OfficeLengthUnit.millimeters,
          );
        },
      );
      expect(find.text('Top (mm)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('page-layout-apply')));
      await tester.pumpAndSettle();
      expect(result!.size.width, size.width);
      expect(result!.margins.left, margins.left);
      expect(result!.margins.bottom, margins.bottom);
      expect(result!.margins.header, margins.header);
    },
  );
  testWidgets('layout accepts decimal comma and blocks impossible geometry', (
    tester,
  ) async {
    OfficePageLayoutChoice? result;
    await _host(
      tester,
      (context) => () async {
        result = await showOfficePageLayoutDialog(
          context,
          size: const WmlPageSize(width: 612, height: 792),
          margins: const WmlPageMargins(),
          unit: OfficeLengthUnit.centimeters,
        );
      },
    );
    final left = find.byKey(const ValueKey('page-layout-left'));
    await tester.ensureVisible(left);
    await tester.enterText(left, '999 cm');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('page-layout-apply')))
          .onPressed,
      isNull,
    );
    await tester.enterText(left, '25,4 mm');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('page-layout-apply')));
    await tester.pumpAndSettle();
    expect(result!.margins.left, closeTo(72, 1e-10));
  });
  testWidgets(
    'sheet dimension dialog accepts physical suffixes and cancellation',
    (tester) async {
      double? result;
      await _host(
        tester,
        (context) => () async {
          result = await showOfficeDimensionDialog(
            context,
            title: 'Column width',
            points: 48,
            unit: OfficeLengthUnit.centimeters,
          );
        },
      );
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.enterText(find.byType(TextField), '25,4 mm');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(result, closeTo(72, 1e-10));
    },
  );
}
