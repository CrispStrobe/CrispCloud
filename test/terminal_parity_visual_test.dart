// Opt-in real-widget captures, using synthetic sessions and local in-memory
// settings only. Run with --dart-define=TERMINAL_PARITY_VISUALS=true.
// PNGs go to build/terminal-parity-visuals unless TERMINAL_PARITY_VISUAL_DIR
// selects another output directory. These are inspection fixtures, not goldens
// or proof of real SSH/native device acceptance.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crisp_cloud/models/ssh_terminal_config.dart';
import 'package:crisp_cloud/models/ssh_terminal_profile.dart';
import 'package:crisp_cloud/models/terminal_key_binding.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/terminal_key_bindings_provider.dart';
import 'package:crisp_cloud/providers/terminal_provider.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/ssh_terminal_profiles.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_key_bindings.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/widgets/ssh_config_import_dialog.dart';
import 'package:crisp_cloud/widgets/ssh_terminal_profiles_dialog.dart';
import 'package:crisp_cloud/widgets/terminal_key_bindings_dialog.dart';
import 'package:crisp_cloud/widgets/terminal_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm2/xterm.dart';

const _capture = bool.fromEnvironment('TERMINAL_PARITY_VISUALS');
const _directory = String.fromEnvironment(
  'TERMINAL_PARITY_VISUAL_DIR',
  defaultValue: 'build/terminal-parity-visuals',
);
const _screen = ValueKey('terminal-parity-visual-screen');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!_capture) return;
    for (final family in ['StoreRoboto', 'Roboto']) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
      await loader.load();
    }
    await (FontLoader(
      'AppMono',
    )..addFont(rootBundle.load('assets/fonts/RobotoMono-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  late ProviderContainer container;
  late SshTerminalProfiles profiles;
  late TerminalKeyBindings keys;
  final sessions = <TerminalSession>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    String? profileData;
    String? keyData;
    profiles = SshTerminalProfiles(
      read: () async => profileData,
      write: (value) async => profileData = value,
    );
    keys = TerminalKeyBindings(
      read: () async => keyData,
      write: (value) async => keyData = value,
    );
    container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        terminalKeyBindingsProvider.overrideWithValue(keys),
      ],
    );
    container.read(showTerminalProvider.notifier).state = true;
    container.read(focusAreaProvider.notifier).state = FocusArea.terminal;
    container.read(terminalHeightProvider.notifier).state = 720;
  });
  tearDown(() async {
    for (final session in sessions) {
      session.dispose();
    }
    sessions.clear();
    container.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  Future<void> mount(WidgetTester tester, Widget body, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'StoreRoboto',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff265e89),
            ),
          ),
          builder: (context, child) =>
              RepaintBoundary(key: _screen, child: child!),
          home: Scaffold(body: body),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dialog(WidgetTester tester, Widget widget, Size size) async {
    await mount(
      tester,
      Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () =>
                showDialog<void>(context: context, builder: (_) => widget),
            child: const Text('Open terminal controls'),
          ),
        ),
      ),
      size,
    );
    await tester.tap(find.text('Open terminal controls'));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_screen),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(_directory)..createSync(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('capture saved profiles at short narrow size', (tester) async {
    await profiles.save(
      SshTerminalProfile(
        name: 'Production',
        config: const SshTerminalConfig(
          host: 'build.example.net',
          port: 2222,
          username: 'developer',
        ),
      ),
    );
    await dialog(
      tester,
      SshTerminalProfilesDialog(store: profiles),
      const Size(320, 320),
    );
    await capture(tester, 'ssh-profiles-narrow');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('ssh-profile-Production')),
      80,
      scrollable: find
          .descendant(
            of: find.byType(SshTerminalProfilesDialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await capture(tester, 'ssh-profiles-scrolled-narrow');
    await finish(tester);
  }, skip: !_capture);

  testWidgets('capture nested panes desktop compact and restored', (
    tester,
  ) async {
    TerminalSession createSession() {
      final session = TerminalSession();
      final number = sessions.length + 1;
      sessions.add(session);
      unawaited(
        session.connect(
          (_, __) async => _Connection(),
          kind: TerminalSessionKind.ssh,
          label: 'workspace-$number@example.net',
        ),
      );
      return session;
    }

    final first = createSession();
    await mount(
      tester,
      TerminalTabs(session: first, sessionFactory: createSession),
      const Size(1280, 960),
    );
    Future<void> action(String label) async {
      await tester.tap(find.byKey(const ValueKey('terminal-layout')));
      await tester.pumpAndSettle();
      final item = find.text(label).last;
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pumpAndSettle();
    }

    Future<void> activate(int id) async {
      final tab = find.byKey(ValueKey('terminal-tab-$id'));
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
    }

    await action('Split side by side');
    await action('Split top and bottom');
    await activate(1);
    await action('Split top and bottom');
    for (var i = 0; i < sessions.length; i++) {
      sessions[i].terminal.write(
        '\x1b[1;36mWorkspace ${i + 1}\x1b[0m\r\n'
        '\x1b[32mdeveloper@build\x1b[0m ~/crispcloud\r\n'
        '\$ git status --short\r\n'
        ' M lib/widgets/terminal_tabs.dart\r\n'
        '?? test/terminal_pane_layout_test.dart\r\n\r\n'
        '\$ flutter test terminal_tests\r\n'
        '\x1b[32mAll checks passed\x1b[0m\r\n'
        '\$ ',
      );
    }
    await tester.pumpAndSettle();
    expect(find.byType(TerminalView), findsNWidgets(4));
    await capture(tester, 'nested-panes-desktop');
    await action('Zoom active pane');
    await capture(tester, 'nested-pane-zoom');
    await action('Restore panes');
    tester.view.physicalSize = const Size(390, 720);
    await tester.pumpAndSettle();
    expect(find.byType(TerminalView), findsOneWidget);
    await capture(tester, 'nested-panes-narrow');
    tester.view.physicalSize = const Size(1280, 960);
    await tester.pumpAndSettle();
    expect(find.byType(TerminalView), findsNWidgets(4));
    await capture(tester, 'nested-panes-restored');
    await finish(tester);
  }, skip: !_capture);

  testWidgets('capture OpenSSH import desktop and narrow preview', (
    tester,
  ) async {
    await profiles.save(
      SshTerminalProfile(
        name: 'build',
        config: const SshTerminalConfig(
          host: 'existing.example.net',
          port: 22,
          username: 'previous',
        ),
      ),
    );
    await dialog(
      tester,
      SshConfigImportDialog(store: profiles),
      const Size(1000, 960),
    );
    await tester.enterText(find.byKey(const ValueKey('ssh-config-source')), '''
Host build
  HostName build.example.net
  User developer
  ProxyJump gateway
  IdentityFile ~/.ssh/work_key
Host gateway
  HostName gateway.example.net
  User operator
  Port 2222
Host legacy
  User developer
  ProxyCommand custom-route
''');
    await capture(tester, 'ssh-import-source-desktop');
    await tester.ensureVisible(
      find.byKey(const ValueKey('ssh-config-preview')),
    );
    await tester.tap(find.byKey(const ValueKey('ssh-config-preview')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('ssh-config-select-build')),
    );
    await tester.tap(find.byKey(const ValueKey('ssh-config-select-build')));
    await tester.pumpAndSettle();
    await capture(tester, 'ssh-import-desktop');
    tester.view.physicalSize = const Size(390, 720);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('ssh-config-select-build')),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'ssh-import-narrow');
    await tester.ensureVisible(
      find.byKey(const ValueKey('ssh-config-entry-legacy')),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'ssh-import-blocked-narrow');
    await finish(tester);
  }, skip: !_capture);

  testWidgets('capture key bindings list and editor desktop and narrow', (
    tester,
  ) async {
    final binding = TerminalKeyBinding(
      chord: TerminalKeyChord(
        keyId: LogicalKeyboardKey.keyK.keyId,
        ctrl: true,
        alt: true,
      ),
      action: TerminalKeyBindingAction.text,
      text: 'git status --short',
    );
    await keys.save(binding);
    await dialog(
      tester,
      const TerminalKeyBindingsDialog(),
      const Size(1000, 900),
    );
    await capture(tester, 'key-bindings-desktop');
    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpAndSettle();
    await capture(tester, 'key-bindings-narrow');
    tester.view.physicalSize = const Size(1000, 900);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('terminal-key-binding-${binding.chord.storageId}')),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'key-binding-editor-desktop');
    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpAndSettle();
    await capture(tester, 'key-binding-editor-narrow');
    await tester.tap(find.byKey(const ValueKey('terminal-key-binding-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send key').last);
    await tester.pumpAndSettle();
    await capture(tester, 'key-binding-key-action-narrow');
    await finish(tester);
  }, skip: !_capture);
}

class _Connection implements TerminalConnection {
  final _output = StreamController<String>(onCancel: () async {});
  final _exit = Completer<int?>();
  @override
  bool get isSandbox => false;
  @override
  Stream<String> get output => _output.stream;
  @override
  Future<int?> get exitCode => _exit.future;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> resize(int columns, int rows) async {}
  @override
  Future<void> close() async {
    if (!_exit.isCompleted) _exit.complete(0);
    if (!_output.isClosed) unawaited(_output.close());
  }
}
