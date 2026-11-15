import 'dart:async';

import 'package:crisp_cloud/models/terminal_key_binding.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/terminal_key_bindings_provider.dart';
import 'package:crisp_cloud/providers/terminal_provider.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_key_bindings.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/widgets/terminal_key_bindings_dialog.dart';
import 'package:crisp_cloud/widgets/terminal_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm2/xterm.dart';

TerminalKeyBinding _textBinding({
  LogicalKeyboardKey key = LogicalKeyboardKey.keyK,
  bool ctrl = true,
  bool alt = true,
  bool shift = false,
  String text = 'echo café🙂',
}) => TerminalKeyBinding(
  chord: TerminalKeyChord(keyId: key.keyId, ctrl: ctrl, alt: alt, shift: shift),
  action: TerminalKeyBindingAction.text,
  text: text,
);

void main() {
  late String? raw;
  late TerminalKeyBindings store;
  late ProviderContainer container;
  late TerminalSession session;
  late _Connection connection;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    raw = null;
    store = TerminalKeyBindings(
      read: () async => raw,
      write: (value) async => raw = value,
    );
    container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        terminalKeyBindingsProvider.overrideWithValue(store),
      ],
    );
    container.read(focusAreaProvider.notifier).state = FocusArea.terminal;
    container.read(showTerminalProvider.notifier).state = true;
    session = TerminalSession();
    connection = _Connection();
  });

  tearDown(() {
    session.dispose();
    container.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1000, 900),
    KeyEventResult Function(KeyEvent)? onWorkspaceKey,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await session.connect(
      (_, __) async => connection,
      kind: TerminalSessionKind.ssh,
    );
    await container.read(terminalKeyBindingListProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: TerminalPanel(
              session: session,
              onWorkspaceKey: onWorkspaceKey,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    view.focusNode!.requestFocus();
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    List<LogicalKeyboardKey> modifiers = const [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.altLeft,
    ],
  }) async {
    for (final modifier in modifiers) {
      await tester.sendKeyDownEvent(modifier);
    }
    await tester.sendKeyEvent(key);
    for (final modifier in modifiers.reversed) {
      await tester.sendKeyUpEvent(modifier);
    }
    await tester.pump();
  }

  Future<void> openBindings(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('terminal-actions')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Key bindings').last);
    await tester.tap(find.text('Key bindings').last);
    await tester.pumpAndSettle();
  }

  Future<void> record(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    List<LogicalKeyboardKey> modifiers = const [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.altLeft,
    ],
  }) async {
    await tester.tap(find.byKey(const ValueKey('terminal-record-key-binding')));
    await tester.pump();
    await chord(tester, key, modifiers: modifiers);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'text mapping runs once and consumes repeat and modifier-changed release',
    (tester) async {
      final binding = _textBinding();
      await store.save(binding);
      await mount(tester);
      var origins = 0;
      session.onUserInput = (_) => origins++;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(connection.input, [binding.text]);
      expect(origins, 1);
      await chord(tester, LogicalKeyboardKey.keyK);
      expect(connection.input, [binding.text, binding.text]);
      expect(origins, 2);
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'mode-aware mapped tap completes once and disabling takes effect',
    (tester) async {
      final binding = TerminalKeyBinding(
        chord: _textBinding().chord,
        action: TerminalKeyBindingAction.key,
        key: TerminalKey.arrowUp,
      );
      await store.save(binding);
      await mount(tester);
      session.terminal.write('\x1b[>3u');
      await chord(tester, LogicalKeyboardKey.keyK);
      expect(connection.input, ['\x1b[A', '\x1b[1;1:3A']);
      await store.save(
        binding.copyWith(enabled: false),
        replacing: binding.chord,
      );
      container.invalidate(terminalKeyBindingListProvider);
      await container.read(terminalKeyBindingListProvider.future);
      await tester.pump();
      connection.input.clear();
      await chord(tester, LogicalKeyboardKey.keyK);
      expect(connection.input, isNot(contains('\x1b[A')));
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'workspace callbacks and built-in search win over stored mappings',
    (tester) async {
      await store.save(
        _textBinding(key: LogicalKeyboardKey.f7, ctrl: false, alt: false),
      );
      await store.save(
        _textBinding(key: LogicalKeyboardKey.keyF, alt: false, shift: true),
      );
      var workspacePresses = 0;
      await mount(
        tester,
        onWorkspaceKey: (event) {
          if (event.logicalKey != LogicalKeyboardKey.f7) {
            return KeyEventResult.ignored;
          }
          if (event is KeyDownEvent) workspacePresses++;
          return KeyEventResult.handled;
        },
      );
      await chord(tester, LogicalKeyboardKey.f7, modifiers: []);
      expect(workspacePresses, 1);
      expect(connection.input, isEmpty);
      await chord(
        tester,
        LogicalKeyboardKey.keyF,
        modifiers: [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.shiftLeft,
        ],
      );
      expect(
        find.byKey(const ValueKey('terminal-search-query')),
        findsOneWidget,
      );
      expect(connection.input, isEmpty);
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'held mapped keys cannot leak repeat or release into another pane',
    (tester) async {
      final binding = _textBinding();
      await store.save(binding);
      final other = TerminalSession();
      final otherConnection = _Connection();
      addTearDown(other.dispose);
      await session.connect(
        (_, __) async => connection,
        kind: TerminalSessionKind.ssh,
      );
      await other.connect(
        (_, __) async => otherConnection,
        kind: TerminalSessionKind.ssh,
      );
      await container.read(terminalKeyBindingListProvider.future);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var active = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => Row(
                  children: [
                    for (var index = 0; index < 2; index++)
                      Expanded(
                        child: TerminalPanel(
                          key: ValueKey('key-binding-pane-$index'),
                          session: index == 0 ? session : other,
                          active: active == index,
                          isActivePane: () => active == index,
                          onActivate: () => setState(() => active = index),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
      await tester.pump();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is TerminalView &&
              identical(widget.terminal, other.terminal),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(active, 1);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(connection.input, [binding.text]);
      expect(otherConnection.input, isEmpty);
      await chord(tester, LogicalKeyboardKey.keyK);
      expect(otherConnection.input, [binding.text]);
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('ordinary native IME text bypasses hardware mappings', (
    tester,
  ) async {
    await store.save(_textBinding());
    await mount(tester, size: const Size(360, 640));
    final editing = TextEditingValue.fromJSON(
      tester.testTextInput.editingState!,
    );
    const text = 'Grüße 中文🙂';
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: editing.text.replaceRange(
          editing.selection.start,
          editing.selection.end,
          text,
        ),
        selection: TextSelection.collapsed(
          offset: editing.selection.start + text.length,
        ),
      ),
    );
    await tester.pump();
    expect(connection.input.join(), contains(text));
    expect(connection.input.join(), isNot(contains('echo')));
    await finish(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'terminal menu supports capture, save, edit, disable and delete',
    (tester) async {
      await mount(tester);
      await openBindings(tester);
      expect(
        find.text('Mappings are stored locally as plain text.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('terminal-add-key-binding')));
      await tester.pumpAndSettle();
      await record(tester, LogicalKeyboardKey.keyK);
      await tester.enterText(
        find.byKey(const ValueKey('terminal-key-binding-text')),
        'pwd',
      );
      await tester.tap(find.byKey(const ValueKey('terminal-save-key-binding')));
      await tester.pumpAndSettle();
      expect(find.byType(EditTerminalKeyBindingDialog), findsNothing);
      final saved = (await store.load()).single;
      expect(saved.chord.label, 'Ctrl+Alt+K');
      expect(saved.text, 'pwd');
      final row = find.byKey(
        ValueKey('terminal-key-binding-${saved.chord.storageId}'),
      );
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('terminal-key-binding-text')),
        'echo updated',
      );
      await tester.tap(find.byKey(const ValueKey('terminal-save-key-binding')));
      await tester.pumpAndSettle();
      expect((await store.load()).single.text, 'echo updated');
      await tester.tap(
        find.byKey(
          ValueKey('terminal-key-binding-enabled-${saved.chord.storageId}'),
        ),
      );
      await tester.pumpAndSettle();
      expect((await store.load()).single.enabled, isFalse);
      await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.delete_outline)),
      );
      await tester.pumpAndSettle();
      expect(await store.load(), isEmpty);
      expect(
        connection.input,
        isEmpty,
        reason: 'Editing never sends a command',
      );
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'capture rejects reserved and duplicate keys without modifying storage',
    (tester) async {
      await store.save(_textBinding());
      await mount(tester);
      await openBindings(tester);
      await tester.tap(find.byKey(const ValueKey('terminal-add-key-binding')));
      await tester.pumpAndSettle();
      await record(
        tester,
        LogicalKeyboardKey.keyF,
        modifiers: [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.shiftLeft,
        ],
      );
      expect(
        find.text('This shortcut is reserved for terminal controls.'),
        findsOneWidget,
      );
      await record(tester, LogicalKeyboardKey.f9, modifiers: []);
      expect(
        find.text('This shortcut is reserved for terminal controls.'),
        findsOneWidget,
      );
      await record(tester, LogicalKeyboardKey.keyK);
      expect(find.text('This shortcut already has a binding.'), findsOneWidget);
      await record(tester, LogicalKeyboardKey.keyA, modifiers: []);
      expect(
        find.text('Use Ctrl, Alt or Meta, or a function/navigation key.'),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await store.load(), hasLength(1));
      expect(connection.input, isEmpty);
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('narrow editor validates text and preserves corrupt stores', (
    tester,
  ) async {
    await mount(tester, size: const Size(320, 640));
    await openBindings(tester);
    await tester.tap(find.byKey(const ValueKey('terminal-add-key-binding')));
    await tester.pumpAndSettle();
    await record(tester, LogicalKeyboardKey.f7, modifiers: []);
    await tester.ensureVisible(
      find.byKey(const ValueKey('terminal-save-key-binding')),
    );
    await tester.tap(find.byKey(const ValueKey('terminal-save-key-binding')));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter 1–4096 characters. Use Send key for control keys.'),
      findsOneWidget,
    );
    expect(raw, isNull);
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byKey(const ValueKey('terminal-key-binding-text')),
      'ready',
    );
    raw = '{bad json';
    await tester.ensureVisible(
      find.byKey(const ValueKey('terminal-save-key-binding')),
    );
    await tester.tap(find.byKey(const ValueKey('terminal-save-key-binding')));
    await tester.pumpAndSettle();
    expect(find.text('Could not save key binding.'), findsOneWidget);
    expect(raw, '{bad json');
    await finish(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}

class _Connection implements TerminalConnection {
  final controller = StreamController<String>(onCancel: () async {});
  final finished = Completer<int?>();
  final input = <String>[];
  @override
  bool get isSandbox => false;
  @override
  Stream<String> get output => controller.stream;
  @override
  Future<int?> get exitCode => finished.future;
  @override
  Future<void> write(String data) async => input.add(data);
  @override
  Future<void> resize(int columns, int rows) async {}
  @override
  Future<void> close() async {
    if (!finished.isCompleted) finished.complete(0);
    if (!controller.isClosed) unawaited(controller.close());
  }
}
