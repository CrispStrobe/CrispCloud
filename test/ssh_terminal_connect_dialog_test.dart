import 'dart:async';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/screen_terminal_strings.dart';
import 'package:crisp_cloud/l10n/terminal_strings.dart';
import 'package:crisp_cloud/models/screen_session_options.dart';
import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:crisp_cloud/widgets/ssh_terminal_connect_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _host = ValueKey('terminal-ssh-host');
const _username = ValueKey('terminal-ssh-username');
const _port = ValueKey('terminal-ssh-port');
const _password = ValueKey('terminal-ssh-password');
const _authentication = ValueKey('terminal-ssh-authentication');
const _privateKey = ValueKey('terminal-ssh-private-key');
const _passphrase = ValueKey('terminal-ssh-passphrase');
const _gateway = ValueKey('terminal-ssh-gateway');
const _sessionMode = ValueKey('terminal-ssh-session-mode');
const _tmuxName = ValueKey('terminal-ssh-tmux-name');
const _screenName = ValueKey('terminal-ssh-screen-name');

void main() {
  test('reconnect details retain the target and mode but no credentials', () {
    final config = SshTerminalConfig(
      host: 'ssh.example',
      port: 2222,
      username: 'alice',
      authentication: SshTerminalAuthentication.privateKey,
      password: 'password-secret',
      privateKey: 'key-secret',
      passphrase: 'passphrase-secret',
      gateway: Uri.parse('wss://relay.example/ssh'),
      tmux: const TmuxSessionOptions(
        sessionName: 'builds',
        mode: TmuxSessionMode.attach,
      ),
    );

    final reconnect = config.withoutSecrets();
    expect(reconnect.host, config.host);
    expect(reconnect.port, config.port);
    expect(reconnect.username, config.username);
    expect(reconnect.gateway, config.gateway);
    expect(reconnect.authentication, SshTerminalAuthentication.privateKey);
    expect(reconnect.tmux?.sessionName, 'builds');
    expect(reconnect.tmux?.mode, TmuxSessionMode.attach);
    expect(reconnect.password, isEmpty);
    expect(reconnect.privateKey, isEmpty);
    expect(reconnect.passphrase, isEmpty);
    expect(config.privateKey, 'key-secret');
  });

  testWidgets('password connections preserve the existing form behavior', (
    tester,
  ) async {
    final submitted = await _open(tester);
    await _enter(tester, _host, ' ssh.example ');
    await _enter(tester, _username, ' alice ');
    await _enter(tester, _port, '2222');
    await _enter(tester, _password, ' secret with spaces ');
    await _submit(tester);

    final config = submitted.single!;
    expect(config.host, 'ssh.example');
    expect(config.username, 'alice');
    expect(config.port, 2222);
    expect(config.authentication, SshTerminalAuthentication.password);
    expect(config.password, ' secret with spaces ');
    expect(config.privateKey, isEmpty);
    expect(config.passphrase, isEmpty);
    expect(config.tmux, isNull);
    expect(config.gateway, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('private-key mode validates the key and submits its passphrase', (
    tester,
  ) async {
    final submitted = await _open(tester);
    await _enterTarget(tester);
    await _enter(tester, _password, 'discarded-password');
    await _select(tester, _authentication, 'Private key');
    expect(find.byKey(_password), findsNothing);
    await _submit(tester);
    expect(submitted, isEmpty);
    expect(find.text('Required'), findsOneWidget);

    final hiddenField = _editable(tester, _privateKey);
    expect(hiddenField.obscureText, isTrue);
    expect(hiddenField.enableSuggestions, isFalse);
    expect(hiddenField.autofillHints, isNull);
    expect(hiddenField.enableIMEPersonalizedLearning, isFalse);
    await tester.ensureVisible(find.byKey(_privateKey));
    await tester.tap(find.byKey(const ValueKey('terminal-ssh-reveal-key')));
    await tester.pumpAndSettle();
    expect(_editable(tester, _privateKey).obscureText, isFalse);
    expect(_editable(tester, _privateKey).maxLines, 6);

    const key =
        '-----BEGIN OPENSSH PRIVATE KEY-----\nkey-data\n'
        '-----END OPENSSH PRIVATE KEY-----\n';
    await _enter(tester, _privateKey, key);
    await _enter(tester, _passphrase, ' passphrase with spaces ');
    await _submit(tester);

    final config = submitted.single!;
    expect(config.authentication, SshTerminalAuthentication.privateKey);
    expect(config.privateKey, key);
    expect(config.passphrase, ' passphrase with spaces ');
    expect(config.password, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switching authentication discards credentials from the old mode',
    (tester) async {
      final submitted = await _open(tester);
      await _enterTarget(tester);
      await _select(tester, _authentication, 'Private key');
      await _enter(tester, _privateKey, 'discarded-key');
      await _enter(tester, _passphrase, 'discarded-passphrase');
      await _select(tester, _authentication, 'Password');
      expect(_editable(tester, _password).controller!.text, isEmpty);
      await _enter(tester, _password, 'new-password');
      await _submit(tester);

      expect(submitted.single!.password, 'new-password');
      expect(submitted.single!.privateKey, isEmpty);
      expect(submitted.single!.passphrase, isEmpty);
    },
  );

  testWidgets('explicit private-key paste preserves the exact multiline PEM', (
    tester,
  ) async {
    const key =
        '-----BEGIN OPENSSH PRIVATE KEY-----\r\n'
        'first-base64-line\r\nsecond-base64-line\r\n'
        '-----END OPENSSH PRIVATE KEY-----\r\n';
    var reads = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          reads++;
          return {'text': key};
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    final submitted = await _open(tester);
    await _enterTarget(tester);
    await _select(tester, _authentication, 'Private key');
    expect(reads, 0, reason: 'Opening the form must not read the clipboard');
    expect(_editable(tester, _privateKey).readOnly, isTrue);
    expect(_editable(tester, _privateKey).obscureText, isTrue);
    final paste = find.byKey(const ValueKey('terminal-ssh-paste-key'));
    await tester.ensureVisible(paste);
    await tester.tap(paste);
    await tester.pumpAndSettle();

    expect(reads, 1);
    expect(_editable(tester, _privateKey).controller!.text, key);
    expect(_editable(tester, _privateKey).obscureText, isTrue);
    await _submit(tester);
    expect(submitted.single!.privateKey, key);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late clipboard results cannot restore cleared key credentials', (
    tester,
  ) async {
    final clipboard = Completer<Map<String, String>>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? await clipboard.future : null,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await _open(tester);
    await _select(tester, _authentication, 'Private key');
    final paste = find.byKey(const ValueKey('terminal-ssh-paste-key'));
    await tester.ensureVisible(paste);
    await tester.tap(paste);
    await tester.pump();
    await _select(tester, _authentication, 'Password');
    await _select(tester, _authentication, 'Private key');
    clipboard.complete({'text': 'stale-secret-key'});
    await tester.pumpAndSettle();
    expect(_editable(tester, _privateKey).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a manual key edit supersedes a pending clipboard paste', (
    tester,
  ) async {
    final clipboard = Completer<Map<String, String>>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? await clipboard.future : null,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    final submitted = await _open(tester);
    await _enterTarget(tester);
    await _select(tester, _authentication, 'Private key');
    final paste = find.byKey(const ValueKey('terminal-ssh-paste-key'));
    await tester.ensureVisible(paste);
    await tester.tap(paste);
    await tester.pump();

    const manualKey =
        '-----BEGIN OPENSSH PRIVATE KEY-----\n'
        'newer-manually-entered-key\n'
        '-----END OPENSSH PRIVATE KEY-----\n';
    await _enter(tester, _privateKey, manualKey);
    clipboard.complete({'text': 'old-clipboard-key'});
    await tester.pumpAndSettle();

    expect(_editable(tester, _privateKey).controller!.text, manualKey);
    await _submit(tester);
    expect(submitted.single!.privateKey, manualKey);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reconnect prefills endpoint and tmux settings, never secrets', (
    tester,
  ) async {
    final submitted = await _open(
      tester,
      initial: SshTerminalConfig(
        host: 'previous.example',
        port: 2222,
        username: 'alice',
        authentication: SshTerminalAuthentication.privateKey,
        privateKey: 'old-private-key',
        password: 'old-password',
        passphrase: 'old-passphrase',
        gateway: Uri.parse('wss://relay.example/ssh'),
        tmux: const TmuxSessionOptions(
          sessionName: 'work-2',
          mode: TmuxSessionMode.attach,
        ),
      ),
    );

    expect(_editable(tester, _host).controller!.text, 'previous.example');
    expect(_editable(tester, _port).controller!.text, '2222');
    expect(_editable(tester, _username).controller!.text, 'alice');
    expect(
      _editable(tester, _gateway).controller!.text,
      'wss://relay.example/ssh',
    );
    expect(_editable(tester, _privateKey).controller!.text, isEmpty);
    expect(_editable(tester, _passphrase).controller!.text, isEmpty);
    expect(_editable(tester, _tmuxName).controller!.text, 'work-2');
    await _enter(tester, _privateKey, 'replacement-key');
    await _submit(tester);

    final config = submitted.single!;
    expect(config.gateway, Uri.parse('wss://relay.example/ssh'));
    expect(config.tmux?.sessionName, 'work-2');
    expect(config.tmux?.mode, TmuxSessionMode.attach);
    expect(config.password, isEmpty);
    expect(config.passphrase, isEmpty);
    expect(config.privateKey, 'replacement-key');
  });

  testWidgets('password reconnect also leaves the password empty', (
    tester,
  ) async {
    await _open(
      tester,
      initial: const SshTerminalConfig(
        host: 'previous.example',
        port: 22,
        username: 'alice',
        password: 'old-password',
      ),
    );
    expect(_editable(tester, _password).controller!.text, isEmpty);
    expect(find.byKey(_privateKey), findsNothing);
  });

  testWidgets(
    'tmux validates names before returning a create-or-attach request',
    (tester) async {
      final submitted = await _open(tester);
      await _enterTarget(tester);
      await _select(tester, _sessionMode, 'Create or attach tmux');
      for (final name in [
        '',
        '-flag',
        'two words',
        'work;id',
        'équipe',
        'a' * 65,
      ]) {
        await _enter(tester, _tmuxName, name);
        await _submit(tester);
        expect(submitted, isEmpty, reason: name);
        expect(
          find.text(
            'Use 1–64 ASCII letters, digits, _ or -; do not start with -.',
          ),
          findsOneWidget,
        );
      }
      await _enter(tester, _tmuxName, ' build_2-live ');
      await _submit(tester);
      expect(submitted.single!.tmux?.sessionName, 'build_2-live');
      expect(submitted.single!.tmux?.mode, TmuxSessionMode.createOrAttach);
    },
  );

  testWidgets('plain shell mode does not accidentally reuse a tmux target', (
    tester,
  ) async {
    final submitted = await _open(
      tester,
      initial: const SshTerminalConfig(
        host: 'ssh.example',
        port: 22,
        username: 'alice',
        tmux: TmuxSessionOptions(sessionName: 'old-session'),
      ),
    );
    await _select(tester, _sessionMode, 'Remote shell');
    expect(find.byKey(_tmuxName), findsNothing);
    await _submit(tester);
    expect(submitted.single!.tmux, isNull);
  });

  testWidgets(
    'screen create validates names and discards a previous tmux choice',
    (tester) async {
      final submitted = await _open(tester);
      await _enterTarget(tester);
      await _select(tester, _sessionMode, 'Create or attach tmux');
      await _enter(tester, _tmuxName, 'old-tmux');
      await _select(tester, _sessionMode, 'Create new screen');
      expect(find.byKey(_tmuxName), findsNothing);
      for (final name in ['-R', 'two words', 'work;id', '123.work']) {
        await _enter(tester, _screenName, name);
        await _submit(tester);
        expect(submitted, isEmpty, reason: name);
      }
      await _enter(tester, _screenName, ' build_2 ');
      await _submit(tester);
      expect(submitted.single!.screen?.sessionName, 'build_2');
      expect(submitted.single!.screen?.mode, ScreenSessionMode.create);
      expect(submitted.single!.tmux, isNull);
    },
  );

  testWidgets(
    'screen attach accepts full IDs and reconnect preserves mode without secrets',
    (tester) async {
      final submitted = await _open(
        tester,
        initial: const SshTerminalConfig(
          host: 'ssh.example',
          port: 2222,
          username: 'alice',
          password: 'old-secret',
          screen: ScreenSessionOptions(
            sessionName: '123.pts-0.server',
            mode: ScreenSessionMode.attach,
          ),
        ),
      );
      expect(
        _editable(tester, _screenName).controller!.text,
        '123.pts-0.server',
      );
      expect(_editable(tester, _password).controller!.text, isEmpty);
      expect(find.byKey(_tmuxName), findsNothing);
      await _enter(tester, _screenName, 'alice/work');
      await _submit(tester);
      expect(submitted, isEmpty);
      await _enter(tester, _screenName, '456.work');
      await _submit(tester);
      expect(submitted.single!.screen?.sessionName, '456.work');
      expect(submitted.single!.screen?.mode, ScreenSessionMode.attach);
      expect(submitted.single!.tmux, isNull);
    },
  );

  testWidgets('switching from screen to plain shell discards its target', (
    tester,
  ) async {
    final submitted = await _open(
      tester,
      initial: const SshTerminalConfig(
        host: 'ssh.example',
        port: 22,
        username: 'alice',
        screen: ScreenSessionOptions(sessionName: 'work'),
      ),
    );
    await _select(tester, _sessionMode, 'Remote shell');
    expect(find.byKey(_screenName), findsNothing);
    await _submit(tester);
    expect(submitted.single!.screen, isNull);
    expect(submitted.single!.tmux, isNull);
  });

  testWidgets('screen controls fit narrow screens', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await _open(tester);
    await _select(tester, _sessionMode, 'Attach existing screen');
    await _enter(tester, _screenName, '123.pts-0.server');
    expect(tester.takeException(), isNull);
    expect(find.text('Connect').hitTestable(), findsOneWidget);
    expect(find.text('Cancel').hitTestable(), findsOneWidget);
  });

  test('Screen controls are translated in every supported locale', () {
    const keys = [
      'Create new screen',
      'Attach existing screen',
      'screen session name',
      'screen session name or PID.name',
      'Detach from screen',
      'screen must be installed on the server. New sessions keep running when you disconnect.',
      'Attach uses an exact name or full PID.name from screen -ls. Other displays stay connected.',
      'Use a session name (1–64 ASCII letters, digits, _ or -), or a full PID.name.',
    ];
    for (final locale in AppLocalizations.supportedLocales) {
      final strings = ScreenTerminalStrings(locale.languageCode);
      for (final key in keys) {
        expect(strings.text(key), isNotEmpty);
        if (locale.languageCode != 'en') {
          expect(strings.text(key), isNot(key), reason: '$locale: $key');
        }
      }
    }
  });

  testWidgets('key and tmux mode still require a safe browser gateway', (
    tester,
  ) async {
    final submitted = await _open(tester, requiresGateway: true);
    await _enterTarget(tester);
    await _select(tester, _authentication, 'Private key');
    await _enter(tester, _privateKey, 'test-key');
    await _select(tester, _sessionMode, 'Attach existing tmux');
    await _enter(tester, _tmuxName, 'work');
    for (final gateway in [
      '',
      'ws://relay.example',
      'wss://relay.example?token=x',
    ]) {
      await _enter(tester, _gateway, gateway);
      await _submit(tester);
      expect(submitted, isEmpty);
    }
    await _enter(tester, _gateway, 'wss://relay.example/ssh');
    await _submit(tester);
    expect(submitted.single!.host, 'ssh.example');
    expect(submitted.single!.gateway, Uri.parse('wss://relay.example/ssh'));
    expect(submitted.single!.tmux?.mode, TmuxSessionMode.attach);
  });

  testWidgets('expanded key and tmux form fits a narrow viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await _open(tester);
    await _select(tester, _authentication, 'Private key');
    await tester.ensureVisible(find.byKey(_privateKey));
    await tester.tap(find.byKey(const ValueKey('terminal-ssh-reveal-key')));
    await tester.pumpAndSettle();
    await _select(tester, _sessionMode, 'Create or attach tmux');
    await _enter(tester, _tmuxName, 'mobile');
    expect(tester.takeException(), isNull);
    expect(find.text('Connect').hitTestable(), findsOneWidget);
    expect(find.text('Cancel').hitTestable(), findsOneWidget);
  });

  testWidgets('SSH extension labels are translated in every supported locale', (
    tester,
  ) async {
    const keys = [
      'Authentication',
      'Private key',
      'Paste private key',
      'Key passphrase (optional)',
      'Create or attach tmux',
      'Attach existing tmux',
      'Reconnect SSH',
      'Detach from tmux',
    ];
    for (final locale in AppLocalizations.supportedLocales) {
      final labels = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) {
              labels
                ..clear()
                ..addAll(keys.map(context.terminalTr));
              return Text(labels.join('\n'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(labels, hasLength(keys.length));
      if (locale.languageCode != 'en') {
        for (var i = 0; i < keys.length; i++) {
          expect(labels[i], isNot(keys[i]), reason: '$locale: ${keys[i]}');
        }
      }
    }
  });
}

Future<List<SshTerminalConfig?>> _open(
  WidgetTester tester, {
  bool requiresGateway = false,
  SshTerminalConfig? initial,
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
            child: const Text('Open connection'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open connection'));
  await tester.pumpAndSettle();
  return submitted;
}

TextField _editable(WidgetTester tester, Key key) => tester.widget<TextField>(
  find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
);

Future<void> _enter(WidgetTester tester, Key key, String value) async {
  await tester.ensureVisible(find.byKey(key));
  if (key == _privateKey && _editable(tester, key).readOnly) {
    await tester.tap(find.byKey(const ValueKey('terminal-ssh-reveal-key')));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byKey(key), value);
  await tester.pumpAndSettle();
}

Future<void> _enterTarget(WidgetTester tester) async {
  await _enter(tester, _host, 'ssh.example');
  await _enter(tester, _username, 'alice');
}

Future<void> _select(WidgetTester tester, Key key, String label) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.text('Connect').last);
  await tester.pumpAndSettle();
}
