import 'package:crisp_cloud/widgets/ssh_terminal_connect_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('adding a hop keeps target credentials separate', (tester) async {
    final submitted = await _open(tester);
    await _enter(tester, 'terminal-ssh-host', 'target.example');
    await _enter(tester, 'terminal-ssh-username', 'target');
    await _enter(tester, 'terminal-ssh-password', 'target-secret');
    await _tapKey(tester, 'terminal-ssh-add-jump');
    expect(find.text('SSH jump host'), findsOneWidget);
    await _enter(tester, 'terminal-ssh-host', 'bastion.example');
    await _enter(tester, 'terminal-ssh-username', 'outer');
    await _enter(tester, 'terminal-ssh-port', '2222');
    await _enter(tester, 'terminal-ssh-password', 'outer-secret');
    await tester.tap(find.text('Use jump host'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    final config = submitted.single!;
    expect(config.host, 'target.example');
    expect(config.password, 'target-secret');
    expect(config.jumpHosts.single.host, 'bastion.example');
    expect(config.jumpHosts.single.port, 2222);
    expect(config.jumpHosts.single.username, 'outer');
    expect(config.jumpHosts.single.password, 'outer-secret');
    expect(
      config.jumpHosts.single.authentication,
      SshTerminalAuthentication.password,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('restored routes require explicit credentials for every hop', (
    tester,
  ) async {
    final submitted = await _open(
      tester,
      initial: const SshTerminalConfig(
        host: 'target.example',
        port: 22,
        username: 'target',
        jumpHosts: [
          SshJumpHost(
            host: 'outer.example',
            username: 'outer',
            password: 'old',
          ),
          SshJumpHost(
            host: 'inner.example',
            username: 'inner',
            authentication: SshTerminalAuthentication.privateKey,
            privateKey: 'old-key',
            passphrase: 'old-passphrase',
          ),
        ],
      ),
    );
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(submitted, isEmpty);
    expect(find.text('Enter credentials for each jump host.'), findsOneWidget);

    await _tapKey(tester, 'terminal-ssh-jump-0-edit');
    expect(_field(tester, 'terminal-ssh-password').controller!.text, isEmpty);
    await _enter(tester, 'terminal-ssh-password', 'new-outer');
    await tester.tap(find.text('Use jump host'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(submitted, isEmpty);

    await _tapKey(tester, 'terminal-ssh-jump-1-edit');
    expect(
      _field(tester, 'terminal-ssh-private-key').controller!.text,
      isEmpty,
    );
    expect(_field(tester, 'terminal-ssh-passphrase').controller!.text, isEmpty);
    await _tapKey(tester, 'terminal-ssh-reveal-key');
    await _enter(tester, 'terminal-ssh-private-key', 'new-key\nwith-newlines');
    await _enter(tester, 'terminal-ssh-passphrase', 'new-passphrase');
    await tester.tap(find.text('Use jump host'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(submitted.single!.jumpHosts.first.password, 'new-outer');
    expect(
      submitted.single!.jumpHosts.last.privateKey,
      'new-key\nwith-newlines',
    );
    expect(submitted.single!.jumpHosts.last.passphrase, 'new-passphrase');
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicate target endpoint is rejected in the actual dialog', (
    tester,
  ) async {
    final submitted = await _open(
      tester,
      initial: const SshTerminalConfig(
        host: 'target.example',
        port: 22,
        username: 'target',
      ),
    );
    await _tapKey(tester, 'terminal-ssh-add-jump');
    await _enter(tester, 'terminal-ssh-host', 'TARGET.EXAMPLE.');
    await _enter(tester, 'terminal-ssh-username', 'outer');
    await tester.tap(find.text('Use jump host'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(submitted, isEmpty);
    expect(
      find.text('Jump hosts and the destination must be distinct.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'removing a hop discards its credential requirement and caps additions',
    (tester) async {
      final submitted = await _open(
        tester,
        initial: SshTerminalConfig(
          host: 'target.example',
          port: 22,
          username: 'target',
          jumpHosts: [
            for (var i = 0; i < 3; i++)
              SshJumpHost(host: 'hop$i.example', username: 'u'),
          ],
        ),
      );
      final add = find.byKey(const ValueKey('terminal-ssh-add-jump'));
      expect(tester.widget<TextButton>(add).onPressed, isNull);
      for (var i = 2; i >= 0; i--) {
        await _tapKey(tester, 'terminal-ssh-jump-$i-remove');
      }
      expect(tester.widget<TextButton>(add).onPressed, isNotNull);
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(submitted.single!.jumpHosts, isEmpty);
    },
  );

  testWidgets(
    'hop credentials fit a narrow layout and never ask for a gateway',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await _open(tester, requiresGateway: true);
      await _tapKey(tester, 'terminal-ssh-add-jump');
      final dialog = find.byType(SshTerminalConnectDialog).last;
      expect(
        find.descendant(
          of: dialog,
          matching: find.byKey(const ValueKey('terminal-ssh-gateway')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.byKey(const ValueKey('terminal-ssh-add-jump')),
        ),
        findsNothing,
      );
      await _enter(tester, 'terminal-ssh-host', 'bastion.example');
      await _enter(tester, 'terminal-ssh-username', 'alice');
      await tester.tap(find.text('Use jump host'));
      await tester.pumpAndSettle();
      expect(
        find.text('The gateway must forward to the first jump host.'),
        findsOneWidget,
      );
      expect(find.text('Connect').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<List<SshTerminalConfig?>> _open(
  WidgetTester tester, {
  SshTerminalConfig? initial,
  bool requiresGateway = false,
}) async {
  final submitted = <SshTerminalConfig?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              submitted.add(
                await showDialog<SshTerminalConfig>(
                  context: context,
                  builder: (_) => SshTerminalConnectDialog(
                    requiresGateway: requiresGateway,
                    initialConfig: initial,
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return submitted;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key)).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final target = find.byKey(ValueKey(key)).last;
  await tester.ensureVisible(target);
  await tester.enterText(target, value);
  await tester.pumpAndSettle();
}

TextField _field(WidgetTester tester, String key) => tester.widget<TextField>(
  find.descendant(
    of: find.byKey(ValueKey(key)).last,
    matching: find.byType(TextField),
  ),
);
