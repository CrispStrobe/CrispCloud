import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/terminal_provider.dart';
import 'package:crisp_cloud/services/sandbox_shell.dart';
import 'package:crisp_cloud/services/sandbox_shell_connection.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/widgets/terminal_panel.dart';
import 'package:crisp_cloud/widgets/terminal_process_native.dart' as proc;

class _Connection implements TerminalConnection {
  final controller = StreamController<String>();
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'built-in shell executes file commands inside its working directory',
    () async {
      final dir = await Directory.systemTemp.createTemp('builtin_terminal_');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/hello.txt').writeAsString('hello');
      final shell = SandboxShellConnection(
        await SandboxShell.create(startPath: dir.path),
      );
      final output = StringBuffer();
      shell.output.listen(output.write);
      await shell.write('pwd\r');
      await shell.write('ls\r');
      await shell.write('cat hello.txt\r');
      await Future<void>.delayed(Duration.zero);
      expect(output.toString(), contains(dir.path));
      expect(output.toString(), contains('hello.txt'));
      expect(output.toString(), contains('hello\r\n'));
      await shell.close();
    },
  );

  test('real PTY shell accepts a command on desktop', () async {
    final shell = await proc.startShell(Directory.systemTemp.path);
    expect(shell, isNotNull);
    final output = StringBuffer();
    final received = Completer<void>();
    final subscription = shell!.outputStream.listen((chunk) {
      output.write(chunk);
      if (output.toString().contains('crisp-terminal-test') &&
          !received.isCompleted) {
        received.complete();
      }
    });
    try {
      await shell.writeln('echo crisp-terminal-test');
      await received.future.timeout(const Duration(seconds: 4));
    } finally {
      await shell.dispose();
      await subscription.cancel();
    }
  }, skip: !Platform.isMacOS);

  testWidgets(
    'terminal sends raw typed input and cooperates with sticky pane focus',
    (tester) async {
      final session = TerminalSession();
      final connection = _Connection();
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        ],
      );
      await session.connect(
        (_, _) async => connection,
        kind: TerminalSessionKind.ssh,
        label: 'test@example',
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: TerminalPanel(session: session)),
          ),
        ),
      );
      await tester.pump();
      final view = tester.widget<TerminalView>(find.byType(TerminalView));
      view.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL, character: 'l');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS, character: 's');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(connection.input.join(), 'ls\r');
      expect(container.read(terminalInputFocusedProvider), isTrue);
      expect(container.read(focusAreaProvider), FocusArea.terminal);

      container.read(focusAreaProvider.notifier).state = FocusArea.local;
      await tester.pump();
      connection.controller.add('background output\r\n');
      await tester.pump();
      expect(view.focusNode!.hasFocus, isFalse);
      expect(container.read(terminalInputFocusedProvider), isFalse);
      expect(container.read(focusAreaProvider), FocusArea.local);

      await tester.tap(find.text('test@example'));
      await tester.pump();
      expect(view.focusNode!.hasFocus, isTrue);
      await tester.tap(find.byKey(const ValueKey('terminal-hide')));
      await tester.pump();
      expect(container.read(showTerminalProvider), isFalse);
      expect(container.read(terminalInputFocusedProvider), isFalse);
      expect(container.read(focusAreaProvider), FocusArea.local);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      // Stream cancellation can complete on the real event loop rather than
      // the widget clock; do not await that transport cleanup inside FakeAsync.
      await tester.runAsync(session.disconnect);
      session.dispose();
      container.dispose();
    },
  );
}
