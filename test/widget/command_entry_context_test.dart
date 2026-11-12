import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/custom_command_provider.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/screens/keyboard_shortcuts.dart';
import 'package:crisp_cloud/services/command_entry_service.dart';
import 'package:crisp_cloud/services/custom_toolbar_command_service.dart';
import 'package:crisp_cloud/services/keyboard_shortcut_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/widgets/command_entry_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/command_entry_fixture.dart';
import '../support/external_drop_fixture.dart';

class _GrantedLocal extends DropTestLocal implements LocalFileSourceIdentity {
  _GrantedLocal(this.root) : super(root);
  final String root;
  Object token = Object();
  @override
  String get grantedBasePath => root;
  @override
  Object? sourceIdentityForPath(String path) =>
      p.equals(root, path) || p.isWithin(root, path) ? token : null;
}

void main() {
  late Directory temporary;
  late String sourcePath, targetPath;
  late _GrantedLocal local;
  late DropTestCloud cloud;
  late ProviderContainer container;
  late PanelNotifier source, target;
  late WidgetRef widgetRef;
  CommandEntryContext? captured;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temporary = await Directory.systemTemp.createTemp('command-entry-');
    sourcePath = (await Directory(
      p.join(temporary.path, 'source'),
    ).create()).path;
    targetPath = (await Directory(
      p.join(temporary.path, 'target'),
    ).create()).path;
    await File(p.join(sourcePath, 'first café.txt')).writeAsString('first');
    await File(p.join(sourcePath, 'second.txt')).writeAsString('second');
    local = _GrantedLocal(temporary.path);
    cloud = DropTestCloud('actual-account');
    final commands = CustomToolbarCommandService();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => DropTestAuth(cloud)),
        localFileServiceProvider.overrideWithValue(local),
        customToolbarCommandServiceProvider.overrideWith((_) => commands),
        commandEntryServiceProvider.overrideWithValue(
          CommandEntryService(host: CommandEntryTestHost()),
        ),
      ],
    );
    source = container.read(panelProvider(PanelSide.remote));
    target = container.read(panelProvider(PanelSide.local));
    await Future<void>.delayed(Duration.zero);
    await target.navigateToPath(
      targetPath,
      origin: target.captureLocalClipboardOrigin(targetPath),
    );
    await source.navigateToPath(
      sourcePath,
      origin: source.captureLocalClipboardOrigin(sourcePath),
    );
    source.toggleSelection(
      source.files!.firstWhere((file) => file.name == 'first café.txt'),
    );
    container.read(activePanelProvider.notifier).state = PanelSide.remote;
    container.read(focusAreaProvider.notifier).state = FocusArea.remote;
  });
  tearDown(() async {
    captured?.dispose();
    captured = null;
    container.dispose();
    await temporary.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester, {bool editing = false}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                widgetRef = ref;
                return Focus(
                  autofocus: !editing,
                  onKeyEvent: (_, event) => handleKeyEvent(context, ref, event),
                  child: editing
                      ? const TextField(autofocus: true)
                      : const SizedBox.expand(),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> opener(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('capture uses actual local source in the opposite visual pane', (
    tester,
  ) async {
    await mount(tester);
    captured = captureCommandEntryContext(widgetRef);
    expect(commandEntryAvailable(widgetRef), isTrue);
    expect(captured!.invocation.currentPath, sourcePath);
    expect(captured!.invocation.targetPath, targetPath);
    expect(captured!.invocation.selectedPaths, [
      p.join(sourcePath, 'first café.txt'),
    ]);
    expect(captured!.selection.single.name, 'first café.txt');
    expect(captured!.invocation.storage.isLocal, isTrue);
    expect(captured!.invocation.isCurrent(), isTrue);
  });

  for (final mutation in [
    'selection',
    'navigation',
    'tab',
    'grant',
    'active pane',
  ]) {
    testWidgets('$mutation invalidates the captured command context', (
      tester,
    ) async {
      await mount(tester);
      captured = captureCommandEntryContext(widgetRef);
      switch (mutation) {
        case 'selection':
          source.clearSelection();
          source.toggleSelection(
            source.files!.firstWhere((file) => file.name == 'second.txt'),
          );
        case 'navigation':
          await tester.runAsync(() => source.navigateToPath(targetPath));
        case 'tab':
          source.addTab();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        case 'grant':
          local.token = Object();
        case 'active pane':
          container.read(activePanelProvider.notifier).state = PanelSide.local;
      }
      expect(captured!.invocation.isCurrent(), isFalse);
      expect(captured!.invocation.currentPath, sourcePath);
      expect(captured!.invocation.selectedPaths, [
        p.join(sourcePath, 'first café.txt'),
      ]);
    });
  }

  testWidgets(
    'selection change then restoration cannot revive a stale capture',
    (tester) async {
      await mount(tester);
      captured = captureCommandEntryContext(widgetRef);
      final original = source.selection.single;
      source.clearSelection();
      source.toggleSelection(
        source.files!.firstWhere((file) => file.name == 'second.txt'),
      );
      source.clearSelection();
      source.toggleSelection(original);
      expect(captured!.invocation.isCurrent(), isFalse);
    },
  );

  testWidgets('opposite pane changes invalidate a captured saved target', (
    tester,
  ) async {
    await mount(tester);
    captured = captureCommandEntryContext(widgetRef);
    await tester.runAsync(() => target.navigateToPath(sourcePath));
    expect(captured!.invocation.isCurrent(), isTrue);
    expect(captured!.invocation.targetIsCurrent!(), isFalse);
  });

  testWidgets(
    'actual remote source with local-looking paths cannot be captured',
    (tester) async {
      await tester.runAsync(
        () => source.navigateToPath(
          '/',
          origin: source.resolveStorageReference(
            storageReferenceForClient(cloud),
            '/',
          ),
        ),
      );
      await mount(tester);
      expect(commandEntryAvailable(widgetRef), isFalse);
      expect(
        () => captureCommandEntryContext(widgetRef),
        throwsA(isA<CommandEntryException>()),
      );
      await opener(tester);
      final dialog = tester.widget<CommandEntryDialog>(
        find.byType(CommandEntryDialog),
      );
      expect(dialog.captured, isNull);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('command-entry-review')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('browser opener honors default then customised shortcuts', (
    tester,
  ) async {
    await mount(tester);
    await opener(tester);
    expect(find.byType(CommandEntryDialog), findsOneWidget);
    expect(
      tester
          .widget<CommandEntryDialog>(find.byType(CommandEntryDialog))
          .captured!
          .invocation
          .currentPath,
      sourcePath,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    await container
        .read(shortcutBindingsProvider.notifier)
        .setBinding(
          ShortcutAction.commandEntry,
          const ShortcutBinding(key: 'F9'),
        );
    await opener(tester);
    expect(find.byType(CommandEntryDialog), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
    expect(find.byType(CommandEntryDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final owner in ['text input', 'terminal']) {
    testWidgets('$owner retains the command-entry opener keys', (tester) async {
      await mount(tester, editing: owner == 'text input');
      await container
          .read(shortcutBindingsProvider.notifier)
          .setBinding(
            ShortcutAction.commandEntry,
            const ShortcutBinding(key: 'F9'),
          );
      if (owner == 'terminal') {
        container.read(focusAreaProvider.notifier).state = FocusArea.terminal;
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await opener(tester);
      expect(find.byType(CommandEntryDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
