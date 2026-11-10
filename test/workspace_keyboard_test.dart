import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/screens/keyboard_shortcuts.dart';
import 'package:crisp_cloud/services/keyboard_shortcut_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/workflow_fake_client.dart';

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/landing';
  @override
  String? get grantedBasePath => currentPath;
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  @override
  final WorkflowFakeClient client = WorkflowFakeClient()..current = false;
  @override
  bool get isConnected => false;
  @override
  String? userEmail;
  @override
  String get providerName => client.providerName;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
      localFileServiceProvider.overrideWithValue(_Local()),
      authProvider.overrideWith((_) => _Auth()),
    ]);
  });
  tearDown(() => container.dispose());

  Future<void> mount(WidgetTester tester, {bool editing = false}) async {
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Consumer(builder: (context, ref, _) => Focus(
          autofocus: !editing,
          onKeyEvent: (_, event) => handleKeyEvent(context, ref, event),
          child: editing ? const TextField(autofocus: true) : const SizedBox.expand(),
        ))),
      ),
    ));
    await tester.pumpAndSettle();
    container.read(activePanelProvider.notifier).state = PanelSide.local;
    container.read(focusAreaProvider.notifier).state = FocusArea.local;
  }

  Future<void> chord(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('modified function keys sort without opening file operations', (tester) async {
    await mount(tester);
    final panel = container.read(panelProvider(PanelSide.local));
    for (final entry in {
      LogicalKeyboardKey.f4: SortBy.extension,
      LogicalKeyboardKey.f6: SortBy.size,
      LogicalKeyboardKey.f5: SortBy.date,
      LogicalKeyboardKey.f3: SortBy.name,
    }.entries) {
      await chord(tester, entry.key);
      expect(panel.sortBy, entry.value);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a custom binding executes and disables its old default', (tester) async {
    await mount(tester);
    final panel = container.read(panelProvider(PanelSide.local));
    final before = panel.showHiddenFiles;
    await container.read(shortcutBindingsProvider.notifier).setBinding(
      ShortcutAction.toggleHidden, const ShortcutBinding(key: 'F9'));
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pump();
    expect(panel.showHiddenFiles, !before);
    await chord(tester, LogicalKeyboardKey.period);
    expect(panel.showHiddenFiles, !before);
    await container.read(shortcutBindingsProvider.notifier).resetBinding(ShortcutAction.toggleHidden);
    await chord(tester, LogicalKeyboardKey.period);
    expect(panel.showHiddenFiles, before);
  });

  testWidgets('text fields retain custom function keys and sorting keys', (tester) async {
    await mount(tester, editing: true);
    await container.read(shortcutBindingsProvider.notifier).setBinding(
      ShortcutAction.toggleHidden, const ShortcutBinding(key: 'F9'));
    final panel = container.read(panelProvider(PanelSide.local));
    final hidden = panel.showHiddenFiles;
    final sort = panel.sortBy;
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await chord(tester, LogicalKeyboardKey.f6);
    await tester.enterText(find.byType(TextField), 'draft.txt');
    expect(panel.showHiddenFiles, hidden);
    expect(panel.sortBy, sort);
    expect(find.text('draft.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('terminal focus retains function keys', (tester) async {
    await mount(tester);
    final panel = container.read(panelProvider(PanelSide.local));
    final sort = panel.sortBy;
    container.read(focusAreaProvider.notifier).state = FocusArea.terminal;
    await chord(tester, LogicalKeyboardKey.f6);
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
    expect(panel.sortBy, sort);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('saved bindings hydrate observable provider state', () async {
    SharedPreferences.setMockInitialValues({'keyboard_shortcuts':
      '{"refresh":{"key":"F9","ctrl":false,"shift":false,"alt":false,"meta":false}}'});
    container.read(shortcutBindingsProvider);
    await container.read(keyboardShortcutServiceProvider).load();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(shortcutBindingsProvider)[ShortcutAction.refresh]!.key, 'F9');
  });

  test('Command defaults and explicit Control overrides remain distinct', () async {
    final service = KeyboardShortcutService();
    final event = KeyDownEvent(logicalKey: LogicalKeyboardKey.keyT,
      physicalKey: PhysicalKeyboardKey.keyT, timeStamp: Duration.zero);
    expect(service.resolveBrowser(event, isCtrl: false, isMeta: true,
      isShift: false, isAlt: false), ShortcutAction.newTab);
    await service.setBinding(ShortcutAction.newTab, const ShortcutBinding(key: 'T', ctrl: true));
    expect(service.resolveBrowser(event, isCtrl: false, isMeta: true,
      isShift: false, isAlt: false), isNull);
    expect(service.suppressesDefault(event, isCtrl: false, isMeta: true,
      isShift: false, isAlt: false), isTrue);
  });
}
