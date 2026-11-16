@TestOn('vm')
library;

// Opt-in production-widget captures. Agent availability is simulated: these
// establish layout and disclosure, not Unix socket or device acceptance.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crisp_cloud/widgets/ssh_terminal_connect_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _enabled = bool.fromEnvironment('SSH_AGENT_VISUALS');
const _directory = String.fromEnvironment(
  'SSH_AGENT_VISUAL_DIR',
  defaultValue: 'build/ssh-agent-visuals',
);
const _screen = ValueKey('ssh-agent-visual-screen');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!_enabled) return;
    await (FontLoader(
      'AgentRoboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<void> mount(
    WidgetTester tester,
    Size size, {
    bool available = true,
    bool withJump = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'AgentRoboto',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff265e89)),
        ),
        builder: (context, child) =>
            RepaintBoundary(key: _screen, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => SshTerminalConnectDialog(
                    requiresGateway: false,
                    agentSupported: true,
                    agentAvailable: available,
                    initialConfig: SshTerminalConfig(
                      host: 'build.example.net',
                      port: 22,
                      username: 'developer',
                      authentication: SshTerminalAuthentication.agent,
                      forwardAgent: true,
                      jumpHosts: withJump
                          ? const [
                              SshJumpHost(
                                host: 'bastion.example.net',
                                username: 'developer',
                                authentication: SshTerminalAuthentication.agent,
                              ),
                            ]
                          : const [],
                    ),
                  ),
                ),
                child: const Text('Connect with SSH agent'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Connect with SSH agent'));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
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

  testWidgets('agent authority disclosure on desktop', (tester) async {
    await mount(tester, const Size(800, 900), withJump: true);
    await tester.ensureVisible(
      find.byKey(const ValueKey('terminal-ssh-forward-agent')),
    );
    await capture(tester, 'agent-desktop');
  }, skip: !_enabled);

  testWidgets('agent authority disclosure on short narrow viewport', (
    tester,
  ) async {
    await mount(tester, const Size(320, 320));
    await tester.ensureVisible(
      find.byKey(const ValueKey('terminal-ssh-forward-agent')),
    );
    await capture(tester, 'agent-narrow');
  }, skip: !_enabled);

  testWidgets('agent unavailable guidance on short narrow viewport', (
    tester,
  ) async {
    await mount(tester, const Size(320, 320), available: false);
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.textContaining('No SSH agent is available.').last,
    );
    await capture(tester, 'agent-unavailable-narrow');
  }, skip: !_enabled);
}
