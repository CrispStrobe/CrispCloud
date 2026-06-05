// test/widget/theme_picker_widget_test.dart
//
// Widget tests for ThemePickerDialog.
// Tests theme option rendering, selection, and accent color grid.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/theme_service.dart';
import 'package:crisp_cloud/widgets/theme_picker.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a testable [ThemePickerDialog] as an alert dialog inside a MaterialApp.
/// The dialog is shown in a full-size scaffold so the content has enough space.
Widget _wrap(ThemeService service) {
  return MaterialApp(
    home: Builder(builder: (context) {
      // We show the ThemePickerDialog directly as a dialog to get proper layout.
      return Scaffold(
        body: SingleChildScrollView(
          child: ThemePickerDialog(themeService: service),
        ),
      );
    }),
  );
}

/// Creates a [ThemeService] with mock SharedPreferences already set.
ThemeService _makeThemeService() => ThemeService();

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // -------------------------------------------------------------------------
  // Rendering — theme options
  // -------------------------------------------------------------------------

  group('ThemePickerDialog theme options', () {
    testWidgets('renders 7 AppThemeMode ListTiles', (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      // AppThemeMode has 7 values: system, light, dark, oledBlack, nord, dracula, materialYou
      expect(AppThemeMode.values.length, equals(7));
      expect(find.byType(ListTile), findsNWidgets(7));
    });

    testWidgets('renders "System" option', (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      expect(find.text('System'), findsOneWidget);
    });

    testWidgets('renders "Light" option', (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      expect(find.text('Light'), findsOneWidget);
    });

    testWidgets('renders "Dark" option', (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('renders "OLED Black" option', (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      expect(find.text('OLED Black'), findsOneWidget);
    });

    testWidgets('renders "Nord" option', (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      expect(find.text('Nord'), findsOneWidget);
    });

    testWidgets('renders "Dracula" option', (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      expect(find.text('Dracula'), findsOneWidget);
    });

    testWidgets('shows "Choose Theme" as dialog title', (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      expect(find.text('Choose Theme'), findsOneWidget);
    });

    testWidgets('shows "Done" action button', (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      expect(find.text('Done'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Theme selection
  // -------------------------------------------------------------------------

  group('ThemePickerDialog theme selection', () {
    testWidgets('tapping "Dark" calls setTheme(AppThemeMode.dark)',
        (tester) async {
      final service = _makeThemeService();
      expect(service.currentMode, equals(AppThemeMode.system));

      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      await tester.tap(find.text('Dark'));
      await tester.pump();

      expect(service.currentMode, equals(AppThemeMode.dark));
    });

    testWidgets('tapping "Light" calls setTheme(AppThemeMode.light)',
        (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      await tester.tap(find.text('Light'));
      await tester.pump();

      expect(service.currentMode, equals(AppThemeMode.light));
    });

    testWidgets('tapping "Nord" calls setTheme(AppThemeMode.nord)',
        (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      await tester.tap(find.text('Nord'));
      await tester.pump();

      expect(service.currentMode, equals(AppThemeMode.nord));
    });

    testWidgets('tapping "Dracula" calls setTheme(AppThemeMode.dracula)',
        (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      await tester.tap(find.text('Dracula'));
      await tester.pump();

      expect(service.currentMode, equals(AppThemeMode.dracula));
    });

    testWidgets('check icon appears next to the currently selected theme',
        (tester) async {
      final service = _makeThemeService();
      // Default is system.
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      // The selected "System" tile has a check icon trailing.
      final systemTile = find.ancestor(
        of: find.text('System'),
        matching: find.byType(ListTile),
      );
      expect(systemTile, findsOneWidget);

      final trailingIcon = find.descendant(
        of: systemTile,
        matching: find.byIcon(Icons.check),
      );
      expect(trailingIcon, findsOneWidget);
    });

    testWidgets('tapping theme updates service currentMode', (tester) async {
      // ThemePickerDialog is a StatelessWidget that reads themeService once.
      // We verify the service state changes on tap, not the UI rebuild.
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      expect(service.currentMode, equals(AppThemeMode.system));
      await tester.tap(find.text('Dark'));
      await tester.pump();

      expect(service.currentMode, equals(AppThemeMode.dark));
    });
  });

  // -------------------------------------------------------------------------
  // Accent color grid
  // -------------------------------------------------------------------------

  group('ThemePickerDialog accent color grid', () {
    testWidgets('shows "Accent Color" label', (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      expect(find.text('Accent Color'), findsOneWidget);
    });

    testWidgets('renders color dot grid as Wrap widget', (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      expect(find.byType(Wrap), findsOneWidget);
    });

    testWidgets('renders 11 color dots', (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      // 11 color dot InkWells in the Wrap
      final wrap = find.byType(Wrap);
      final dotsInsideWrap = find.descendant(
        of: wrap,
        matching: find.byType(InkWell),
      );
      expect(dotsInsideWrap, findsNWidgets(11));
    });

    testWidgets('tapping a color dot sets the accent color', (tester) async {
      final service = _makeThemeService();
      expect(service.customAccent, isNull);

      await tester.pumpWidget(_wrap(service));
      await tester.pumpAndSettle();

      // Tap "Blue" dot via tooltip
      await tester.tap(find.byTooltip('Blue'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(service.customAccent, isNotNull);
    });

    testWidgets('tapping "Default" dot clears the accent color', (tester) async {
      final service = _makeThemeService();
      await service.setAccentColor(Colors.red);
      expect(service.customAccent, isNotNull);

      await tester.pumpWidget(_wrap(service));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Default'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(service.customAccent, isNull);
    });

    testWidgets('auto_awesome icon appears on the Default dot', (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    });

    testWidgets('tapping "Green" color dot sets a non-null accent',
        (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Green'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(service.customAccent, isNotNull);
    });

    testWidgets('tapping "Purple" color dot sets a non-null accent',
        (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Purple'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(service.customAccent, isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  // Divider between themes and accent colors
  // -------------------------------------------------------------------------

  group('ThemePickerDialog layout', () {
    testWidgets('has a Divider between themes and accent section',
        (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('dialog content has SizedBox with 340px width', (tester) async {
      final service = _makeThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      // The content is wrapped in a SizedBox(width: 340). Find any with that width.
      final sizedBoxes = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((box) => box.width == 340)
          .toList();
      expect(sizedBoxes, isNotEmpty);
    });
  });
}
