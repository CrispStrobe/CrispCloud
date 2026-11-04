// test/widget/settings_quick_search_test.dart
//
// Widget tests for the Quick Search settings section (Total Commander /
// Double Commander behavior selection and options).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/providers/quick_search_provider.dart';
import 'package:crisp_cloud/widgets/settings_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer();
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

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();

    expect(
      container.read(quickSearchSettingsProvider).mode,
      QuickSearchMode.filter,
    );
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
