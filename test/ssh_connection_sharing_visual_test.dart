@TestOn('vm')
library;

// Opt-in captures of production tabs, shared-shell controls and disclosure.
// In-memory channels establish layout only, not SSH transport acceptance.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crisp_cloud/models/terminal_arrangement.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/terminal_provider.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/widgets/terminal_panel.dart';
import 'package:crisp_cloud/widgets/terminal_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = bool.fromEnvironment('SSH_SHARING_VISUALS');
const _directory = String.fromEnvironment(
  'SSH_SHARING_VISUAL_DIR',
  defaultValue: 'build/ssh-sharing-visuals',
);
const _screen = ValueKey('ssh-sharing-visual-screen');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_enabled) return;
    await (FontLoader(
      'SharingRoboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'AppMono',
    )..addFont(rootBundle.load('assets/fonts/RobotoMono-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<void> capture(WidgetTester tester, String name) async {
    FocusManager.instance.primaryFocus?.unfocus();
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

  testWidgets(
    'capture shared SSH tabs and controls at desktop and compact sizes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final route = <_Connection>[];
      final sessions = <TerminalSession>[TerminalSession()];
      final providers = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        ],
      );
      providers.read(showTerminalProvider.notifier).state = true;
      providers.read(terminalHeightProvider.notifier).state = 540;
      providers.read(focusAreaProvider.notifier).state = FocusArea.terminal;
      await sessions.first.connect(
        (_, _) async => _Connection(route),
        kind: TerminalSessionKind.ssh,
        label: 'developer@build.example.net',
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(() {
        for (final session in sessions) {
          session.dispose();
        }
        providers.dispose();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: providers,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              fontFamily: 'SharingRoboto',
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff265e89),
              ),
            ),
            builder: (context, child) =>
                RepaintBoundary(key: _screen, child: child!),
            home: Scaffold(
              body: TerminalTabs(
                session: sessions.first,
                sessionFactory: () {
                  final session = TerminalSession();
                  sessions.add(session);
                  return session;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<TerminalPanel>(find.byType(TerminalPanel))
          .onPaneStateChanged!(
        TerminalPaneState(
          sshConfig: const SshTerminalConfig(
            host: 'build.example.net',
            port: 22,
            username: 'developer',
            forwardAgent: true,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('terminal-layout')));
      await tester.pumpAndSettle();
      await capture(tester, 'shared-shell-menu-desktop');
      await tester.tap(find.text('Split SSH side by side'));
      await tester.pumpAndSettle();
      route.first.controller.add(
        '\x1b[36mdeveloper@build\x1b[0m \x1b[34m~/crispcloud\x1b[0m\r\n'
        '\$ tail -f build.log\r\n'
        '10:42:10  Build started\r\n'
        '10:42:11  Compiling terminal services\r\n'
        '10:42:12  Watching for changes\r\n',
      );
      route.last.controller.add(
        '\x1b[36mdeveloper@build\x1b[0m \x1b[34m~\x1b[0m\r\n'
        '\$ pwd\r\n/home/developer\r\n'
        '\r\n\x1b[32mIndependent shell, shared SSH connection\x1b[0m\r\n'
        '\$ ',
      );
      await capture(tester, 'shared-shell-split-desktop');
      await tester.tap(find.byKey(const ValueKey('terminal-close-tab-1')));
      await tester.pumpAndSettle();
      await capture(tester, 'shared-shell-close-desktop');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      tester.view.physicalSize = const Size(320, 320);
      await tester.pumpAndSettle();
      await capture(tester, 'shared-shell-compact');
      await tester.tap(find.byKey(const ValueKey('terminal-layout')));
      await tester.pumpAndSettle();
      await capture(tester, 'shared-shell-menu-compact');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    skip: !_enabled,
  );
}

class _Connection implements TerminalConnection, TerminalConnectionSharing {
  _Connection(this.route) {
    route.add(this);
  }

  final List<_Connection> route;
  final controller = StreamController<String>();
  final ended = Completer<int?>();
  bool closed = false;

  @override
  bool get isSandbox => false;
  @override
  Stream<String> get output => controller.stream;
  @override
  Future<int?> get exitCode => ended.future;
  @override
  bool get canOpenSibling => !closed && sharedSessionCount < 8;
  @override
  int get sharedSessionCount =>
      route.where((connection) => !connection.closed).length;
  @override
  Future<TerminalConnection> openSibling(
    int columns,
    int rows, {
    TerminalConnectionCancellation? cancellation,
  }) async => _Connection(route);
  @override
  Future<void> write(String data) async {}
  @override
  Future<void> resize(int columns, int rows) async {}
  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    ended.complete(0);
    unawaited(controller.close());
  }
}
