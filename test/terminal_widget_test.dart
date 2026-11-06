import 'dart:async';

import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/terminal_provider.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_menu.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/widgets/terminal_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  late TerminalSession session;
  late _Connection connection;
  late ProviderContainer container;

  setUp(() {
    session = TerminalSession();
    connection = _Connection();
    container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
      ],
    );
  });

  // Connect inside testWidgets' FakeAsync zone so its pumps drain the session's
  // serialized input futures, just as the application's event loop does.
  Future<void> connectSession() => session.connect(
    (_, __) async => connection,
    kind: TerminalSessionKind.ssh,
    label: 'alice@example',
  );

  tearDown(() async {
    session.dispose();
    container.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  Future<void> mount(
    WidgetTester tester, {
    FocusOnKeyEventCallback? onParentKey,
  }) async {
    await connectSession();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Focus(
              onKeyEvent: onParentKey,
              child: TerminalPanel(session: session),
            ),
          ),
        ),
      ),
    );
    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    view.focusNode!.requestFocus();
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'raw keys reach the terminal without triggering ancestor file commands',
    (tester) async {
      final bubbled = <LogicalKeyboardKey>[];
      await mount(
        tester,
        onParentKey: (_, event) {
          if (event is KeyDownEvent) bubbled.add(event.logicalKey);
          return KeyEventResult.ignored;
        },
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      final output = connection.input.join();
      expect(output, contains('\x1b[A'));
      expect(output, contains('\t'));
      expect(output, contains('\r'));
      expect(output, contains('\x03'));
      expect(output, contains('\x1b[15~'));
      expect(output, contains('\x1b[3~'));
      expect(bubbled, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'hide preserves output and connection but removes keyboard focus',
    (tester) async {
      await connectSession();
      container.read(showTerminalProvider.notifier).state = true;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: TerminalPanelHost(session: session)),
          ),
        ),
      );
      final view = tester.widget<TerminalView>(find.byType(TerminalView));
      view.focusNode!.requestFocus();
      await tester.pump();
      connection.controller.add('before hide\r\n');
      await tester.pump();

      // Exercise the toolbar/menu toggle too, not just the panel's own hide key.
      container.read(showTerminalProvider.notifier).state = false;
      await tester.pump();
      await tester.pump();
      expect(find.byType(TerminalView), findsNothing);
      expect(view.focusNode!.hasFocus, isFalse);
      expect(container.read(terminalMenuProvider), isNull);
      final previousInput = connection.input.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(connection.input.length, previousInput);
      connection.controller.add('while hidden\r\n');
      await tester.pump();

      container.read(showTerminalProvider.notifier).state = true;
      await tester.pump();
      expect(connection.closeCount, 0);
      expect(session.isConnected, isTrue);
      expect(session.terminal.buffer.getText(), contains('before hide'));
      expect(session.terminal.buffer.getText(), contains('while hidden'));
      expect(find.byType(TerminalView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('showing the terminal focuses it without an extra click', (
    tester,
  ) async {
    await connectSession();
    container.read(showTerminalProvider.notifier).state = false;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: TerminalPanelHost(session: session)),
        ),
      ),
    );
    container.read(showTerminalProvider.notifier).state = true;
    container.read(focusAreaProvider.notifier).state = FocusArea.terminal;
    await tester.pump();
    await tester.pump();
    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.focusNode!.hasFocus, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'remote clipboard sequences are denied; explicit bracketed paste and copy work',
    (tester) async {
      var clipboardReads = 0;
      final clipboardWrites = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            clipboardReads++;
            return {'text': 'Grüße\nsecond line'};
          }
          if (call.method == 'Clipboard.setData') {
            clipboardWrites.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(tester);
      connection.controller.add('\x1b]52;c;?\x07\x1b]52;c;c2VjcmV0\x07');
      await tester.pump();
      expect(clipboardReads, 0);
      expect(clipboardWrites, isEmpty);
      expect(connection.input.where((data) => data.contains('52;')), isEmpty);

      connection.controller.add('\x1b[?2004h');
      await tester.pump();
      final view = tester.widget<TerminalView>(find.byType(TerminalView));
      await view.onPaste!();
      await tester.pump();
      expect(clipboardReads, 1);
      expect(
        connection.input,
        contains('\x1b[200~Grüße\nsecond line\x1b[201~'),
      );
      await view.onCopy!('selected text');
      expect(clipboardWrites, ['selected text']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'SSH form rejects invalid port instead of silently connecting to port 22',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byTooltip('Connect via SSH'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Host'),
        'example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'alice',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Port'),
        '65536',
      );
      if (kIsWeb) {
        await tester.enterText(
          find.byKey(const ValueKey('terminal-ssh-gateway')),
          'wss://gateway.example/ssh',
        );
      }
      await tester.tap(find.text('Connect').last);
      await tester.pumpAndSettle();
      expect(find.text('Enter a port from 1 to 65535'), findsOneWidget);
      expect(connection.closeCount, 0);
      expect(session.isConnected, isTrue);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'browser SSH form requires a secure gateway and preserves SSH target identity',
    (tester) async {
      SshTerminalConfig? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  submitted = await showDialog<SshTerminalConfig>(
                    context: context,
                    builder: (_) =>
                        const SshTerminalConnectDialog(requiresGateway: true),
                  );
                },
                child: const Text('Open connection'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open connection'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Host'),
        'ssh.example',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'alice',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Port'),
        '2222',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'test password',
      );

      const invalidGateways = <(String, String)>[
        ('', 'A secure WebSocket gateway is required in the browser.'),
        (
          'ws://gateway.example/ssh',
          'Use a complete wss:// URL with a valid host and port.',
        ),
        (
          'wss://gateway.example:0/ssh',
          'Use a complete wss:// URL with a valid host and port.',
        ),
        (
          'wss://gateway.example:65536/ssh',
          'Use a complete wss:// URL with a valid host and port.',
        ),
        (
          'wss://user:secret@gateway.example/ssh',
          'The gateway URL must not contain credentials, query parameters, or a fragment.',
        ),
        (
          'wss://gateway.example/ssh?token=secret',
          'The gateway URL must not contain credentials, query parameters, or a fragment.',
        ),
        (
          'wss://gateway.example/ssh#fragment',
          'The gateway URL must not contain credentials, query parameters, or a fragment.',
        ),
      ];
      final gatewayField = find.byKey(const ValueKey('terminal-ssh-gateway'));
      for (final (value, message) in invalidGateways) {
        await tester.enterText(gatewayField, value);
        await tester.tap(find.text('Connect').last);
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        expect(find.byType(SshTerminalConnectDialog), findsOneWidget);
        expect(submitted, isNull);
      }

      await tester.enterText(gatewayField, 'wss://gateway.example/ssh');
      await tester.tap(find.text('Connect').last);
      await tester.pumpAndSettle();
      expect(submitted, isNotNull);
      expect(submitted!.host, 'ssh.example');
      expect(submitted!.port, 2222);
      expect(submitted!.username, 'alice');
      expect(submitted!.password, 'test password');
      expect(submitted!.gateway, Uri.parse('wss://gateway.example/ssh'));
      expect(find.byType(SshTerminalConnectDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'native phone keyboard keeps a usable viewport and control keys',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      try {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);

        await mount(tester);
        expect(
          tester.getSize(find.byKey(const ValueKey('terminal-panel'))).height,
          lessThanOrEqualTo(160),
        );
        expect(session.rows, greaterThan(0));
        expect(find.text('Esc'), findsOneWidget);
        expect(find.text('Ctrl+C'), findsOneWidget);

        // A software keyboard inserts at the supplied selection; it does not
        // replace the terminal's entire editing buffer as enterText would.
        final editing = TextEditingValue.fromJSON(
          tester.testTextInput.editingState!,
        );
        const input = 'echo Grüße';
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: editing.text.replaceRange(
              editing.selection.start,
              editing.selection.end,
              input,
            ),
            selection: TextSelection.collapsed(
              offset: editing.selection.start + input.length,
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('Ctrl+C'));
        await tester.pump();
        expect(connection.input.join(), contains('echo Grüße'));
        expect(connection.input.join(), contains('\x03'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
    skip: kIsWeb,
  );
}

class _Connection implements TerminalConnection {
  final controller = StreamController<String>();
  final input = <String>[];
  int closeCount = 0;
  @override
  bool get isSandbox => false;
  @override
  Stream<String> get output => controller.stream;
  @override
  Future<int?> get exitCode async => null;
  @override
  Future<void> write(String data) async => input.add(data);
  @override
  Future<void> resize(int columns, int rows) async {}
  @override
  Future<void> close() async {
    closeCount++;
    unawaited(controller.close());
  }
}
