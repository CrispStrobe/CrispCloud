// test/widget/theme_picker_widget_test.dart
//
// Widget tests for ThemePickerDialog / ThemeSettingsPanel: the theme and
// accent dropdowns, selection, and the dialog chrome.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/theme_service.dart';
import 'package:crisp_cloud/widgets/theme_picker.dart';

Widget _wrap(ThemeService service) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ThemePickerDialog(themeService: service),
      ),
    ),
  );
}

final _themeDropdown = find.byKey(const ValueKey('settings-theme'));
final _accentDropdown = find.byKey(const ValueKey('settings-accent'));

Future<void> _pickTheme(WidgetTester tester, String label) async {
  await tester.tap(_themeDropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _pickAccent(WidgetTester tester, String label) async {
  await tester.tap(_accentDropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ThemePickerDialog theme options', () {
    testWidgets('theme dropdown offers every AppThemeMode', (tester) async {
      final service = ThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      final dropdown = tester.widget<DropdownButton<AppThemeMode>>(
        _themeDropdown,
      );
      expect(
        dropdown.items!.map((item) => item.value),
        orderedEquals(AppThemeMode.values),
      );
      expect(dropdown.value, service.currentMode);
    });

    testWidgets('opened dropdown lists every theme label', (tester) async {
      await tester.pumpWidget(_wrap(ThemeService()));
      await tester.pump();
      await tester.tap(_themeDropdown);
      await tester.pumpAndSettle();

      for (final label in [
        'System',
        'Light',
        'Dark',
        'OLED Black',
        'Nord',
        'Dracula',
        'Material You',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });

    testWidgets('shows "Choose Theme" title and "Done" action', (tester) async {
      await tester.pumpWidget(_wrap(ThemeService()));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Choose Theme'),
        ),
        findsWidgets,
      );
      expect(find.widgetWithText(TextButton, 'Done'), findsOneWidget);
    });
  });

  group('ThemePickerDialog theme selection', () {
    for (final (label, mode) in [
      ('Dark', AppThemeMode.dark),
      ('Light', AppThemeMode.light),
      ('Nord', AppThemeMode.nord),
      ('Dracula', AppThemeMode.dracula),
    ]) {
      testWidgets('choosing "$label" sets $mode', (tester) async {
        final service = ThemeService();
        await tester.pumpWidget(_wrap(service));
        await tester.pump();

        await _pickTheme(tester, label);

        expect(service.currentMode, mode);
        expect(
          tester.widget<DropdownButton<AppThemeMode>>(_themeDropdown).value,
          mode,
        );
      });
    }
  });

  group('ThemePickerDialog accent color', () {
    testWidgets('shows "Accent Color" label', (tester) async {
      await tester.pumpWidget(_wrap(ThemeService()));
      await tester.pump();

      expect(find.text('Accent Color'), findsOneWidget);
    });

    testWidgets('accent dropdown offers Default plus 9 colors', (tester) async {
      await tester.pumpWidget(_wrap(ThemeService()));
      await tester.pump();

      final dropdown = tester.widget<DropdownButton<int>>(_accentDropdown);
      expect(dropdown.items, hasLength(10));
      expect(dropdown.value, -1);
    });

    testWidgets('choosing a color sets the accent color', (tester) async {
      final service = ThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      await _pickAccent(tester, 'Green');
      expect(service.customAccent?.toARGB32(), Colors.green.toARGB32());

      await _pickAccent(tester, 'Purple');
      expect(service.customAccent?.toARGB32(), Colors.purple.toARGB32());
    });

    testWidgets('choosing "Default" clears the accent color', (tester) async {
      final service = ThemeService();
      await tester.pumpWidget(_wrap(service));
      await tester.pump();

      await _pickAccent(tester, 'Blue');
      expect(service.customAccent, isNotNull);

      await _pickAccent(tester, 'Default');
      expect(service.customAccent, isNull);
    });
  });

  group('ThemePickerDialog layout', () {
    testWidgets('dialog content has SizedBox with 340px width', (tester) async {
      await tester.pumpWidget(_wrap(ThemeService()));
      await tester.pump();

      expect(
        find.byWidgetPredicate((w) => w is SizedBox && w.width == 340),
        findsOneWidget,
      );
    });
  });
}
