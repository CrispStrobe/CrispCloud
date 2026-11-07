// test/widget/settings_quick_search_test.dart
//
// Widget tests for the Quick Search settings section (Total Commander /
// Double Commander behavior selection and options).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/theme_service.dart';
import 'package:crisp_cloud/providers/quick_search_provider.dart';
import 'package:crisp_cloud/widgets/settings_dialog.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
    ]);
  });

  tearDown(() {
    container.dispose();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SettingsDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('typing mode can be switched to quick filter', (tester) async {
    await pumpSettings(tester);
    expect(
      container.read(quickSearchSettingsProvider).mode,
      QuickSearchMode.jump,
    );

    await tester.ensureVisible(find.text('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();

    expect(
      container.read(quickSearchSettingsProvider).mode,
      QuickSearchMode.filter,
    );
  });


  testWidgets('typing mode can select matching files', (tester) async {
    await pumpSettings(tester);
    await tester.ensureVisible(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();

    expect(
      container.read(quickSearchSettingsProvider).mode,
      QuickSearchMode.select,
    );
  });

  testWidgets('file-list font family and size are configurable', (tester) async {
    await pumpSettings(tester);

    await tester.ensureVisible(find.byKey(const Key('settings_font_family')));
    await tester.pumpAndSettle();
    expect(container.read(fontFamilyProvider), 'system');
    final fontDropdown = find.descendant(
      of: find.byKey(const Key('settings_font_family')),
      matching: find.byType(DropdownButton<String>),
    );
    await tester.tap(fontDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monospaced (Roboto Mono)').last);
    await tester.pumpAndSettle();
    expect(container.read(fontFamilyProvider), 'AppMono');

    await tester.ensureVisible(find.byKey(const Key('settings_font_size')));
    await tester.pumpAndSettle();
    final double before = container.read(fontSizeProvider);
    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(container.read(fontSizeProvider), greaterThan(before));
  });

  testWidgets('language setting changes locale and persists', (tester) async {
    await pumpSettings(tester);

    await tester.ensureVisible(find.byKey(const Key('settings_language')));
    await tester.pumpAndSettle();
    final languageDropdown = find.descendant(
      of: find.byKey(const Key('settings_language')),
      matching: find.byType(DropdownButton<String>),
    );
    await tester.tap(languageDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deutsch').last);
    await tester.pumpAndSettle();

    expect(container.read(localeProvider)?.languageCode, 'de');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_locale'), 'de');
  });


  testWidgets('theme can be changed from Appearance', (tester) async {
    await pumpSettings(tester);

    await tester.ensureVisible(find.text('Nord'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nord'));
    await tester.pumpAndSettle();

    expect(container.read(themeProvider).currentMode, AppThemeMode.nord);
  });

  testWidgets('cache limit can be changed from unified settings', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.ensureVisible(find.text('100 MB'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('100 MB'));
    await tester.pumpAndSettle();

    expect(container.read(fileCacheProvider).maxSize, 100 * 1024 * 1024);
  });

  testWidgets('prefix, case and arrow toggles persist to the provider', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.ensureVisible(
      find.byKey(const Key('settings_quick_search_prefix')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_quick_search_prefix')));
    await tester.pump();
    expect(
      container.read(quickSearchSettingsProvider).matchFromStart,
      isFalse,
    );

    await tester.ensureVisible(
      find.byKey(const Key('settings_quick_search_case')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_quick_search_case')));
    await tester.pump();
    expect(
      container.read(quickSearchSettingsProvider).caseSensitive,
      isTrue,
    );

    await tester.ensureVisible(
      find.byKey(const Key('settings_quick_search_arrows')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_quick_search_arrows')));
    await tester.pump();
    expect(
      container.read(quickSearchSettingsProvider).arrowNavigation,
      isFalse,
    );
  });

  testWidgets('reset timeout can be disabled', (tester) async {
    await pumpSettings(tester);

    await tester.ensureVisible(
      find.byKey(const Key('settings_quick_search_reset')),
    );
    await tester.tap(find.byKey(const Key('settings_quick_search_reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Never').last);
    await tester.pumpAndSettle();

    expect(container.read(quickSearchSettingsProvider).resetSeconds, 0);
  });
}
