import 'package:crisp_cloud/l10n/ssh_agent_strings.dart';
import 'package:crisp_cloud/l10n/terminal_mount_error_strings.dart';
import 'package:crisp_cloud/services/ssh_agent.dart';
import 'package:crisp_cloud/widgets/ssh_terminal_connect_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const agentConfig = SshTerminalConfig(
    host: 'host.example',
    port: 22,
    username: 'user',
    authentication: SshTerminalAuthentication.agent,
  );

  testWidgets(
    'agent authentication has no password or private-key fields and forwarding defaults off',
    (tester) async {
      final values = await _open(tester, initial: agentConfig);
      expect(find.byKey(const ValueKey('terminal-ssh-password')), findsNothing);
      expect(
        find.byKey(const ValueKey('terminal-ssh-private-key')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('terminal-ssh-passphrase')),
        findsNothing,
      );
      final checkbox = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('terminal-ssh-forward-agent')),
      );
      expect(checkbox.value, isFalse);
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(values.single.authentication, SshTerminalAuthentication.agent);
      expect(values.single.forwardAgent, isFalse);
      expect(values.single.password, isEmpty);
      expect(values.single.privateKey, isEmpty);
      expect(values.single.passphrase, isEmpty);
    },
  );

  testWidgets(
    'explicit agent forwarding choice and server authority explanation are visible',
    (tester) async {
      final values = await _open(tester, initial: agentConfig);
      final checkbox = find.byKey(const ValueKey('terminal-ssh-forward-agent'));
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Programs on the final SSH server'),
        findsOneWidget,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(values.single.forwardAgent, isTrue);
    },
  );

  testWidgets('saved agent jumps reconnect without imaginary credentials', (
    tester,
  ) async {
    final values = await _open(
      tester,
      initial: const SshTerminalConfig(
        host: 'host.example',
        port: 22,
        username: 'user',
        authentication: SshTerminalAuthentication.agent,
        jumpHosts: [
          SshJumpHost(
            host: 'jump.example',
            username: 'jump',
            authentication: SshTerminalAuthentication.agent,
          ),
        ],
      ),
    );
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(
      values.single.jumpHosts.single.authentication,
      SshTerminalAuthentication.agent,
    );
  });

  testWidgets(
    'missing native agent blocks submission with actionable guidance',
    (tester) async {
      final values = await _open(
        tester,
        initial: agentConfig,
        available: false,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(values, isEmpty);
      expect(find.text(SshAgentException.unavailable), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unsupported saved forwarding can be explicitly disabled before password connection',
    (tester) async {
      final values = await _open(
        tester,
        supported: false,
        available: false,
        initial: const SshTerminalConfig(
          host: 'host.example',
          port: 22,
          username: 'user',
          forwardAgent: true,
        ),
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(values, isEmpty);
      expect(find.text(SshAgentException.unsupported), findsOneWidget);
      final checkbox = find.byKey(const ValueKey('terminal-ssh-forward-agent'));
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(values.single.forwardAgent, isFalse);
      expect(values.single.authentication, SshTerminalAuthentication.password);
    },
  );

  testWidgets(
    'agent jump editor never exposes agent forwarding to the jump host',
    (tester) async {
      await _open(tester, initial: agentConfig, jumpOnly: true);
      expect(
        find.byKey(const ValueKey('terminal-ssh-forward-agent')),
        findsNothing,
      );
    },
  );

  testWidgets('agent options and validation fit a 320 by 320 viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 320);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final values = await _open(tester, initial: agentConfig, available: false);
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(values, isEmpty);
    expect(tester.takeException(), isNull);
    expect(find.text('Connect').hitTestable(), findsOneWidget);
    expect(find.text('Cancel').hitTestable(), findsOneWidget);
  });

  test(
    'agent controls and errors are translated across all existing locales',
    () {
      const messages = [
        'SSH agent',
        'Forward SSH agent',
        'Uses the local SSH agent',
        'Use keys from the local SSH agent. Private keys stay in the agent.',
        'Programs on the final SSH server can request signatures from these agent keys while connected. Jump hosts do not receive agent access.',
        SshAgentException.unsupported,
        SshAgentException.unavailable,
        SshAgentException.connection,
        SshAgentException.empty,
        SshAgentException.refused,
        SshAgentException.invalid,
        SshAgentException.timeout,
        SshAgentException.closed,
        SshAgentException.busy,
      ];
      for (final locale in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
        for (final message in messages) {
          expect(
            sshAgentText(locale, message),
            isNot(message),
            reason: '$locale: $message',
          );
          expect(
            localizedTerminalMountErrorForLanguage(
              locale,
              SshAgentException(message),
            ),
            sshAgentText(locale, message),
          );
        }
      }
    },
  );
}

Future<List<SshTerminalConfig>> _open(
  WidgetTester tester, {
  SshTerminalConfig? initial,
  bool supported = true,
  bool available = true,
  bool jumpOnly = false,
}) async {
  final values = <SshTerminalConfig>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await showDialog<SshTerminalConfig>(
                context: context,
                builder: (_) => SshTerminalConnectDialog(
                  initialConfig: initial,
                  requiresGateway: false,
                  agentSupported: supported,
                  agentAvailable: available,
                  jumpHostOnly: jumpOnly,
                ),
              );
              if (result != null) values.add(result);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return values;
}
