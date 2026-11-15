import 'dart:async';

import 'package:crisp_cloud/models/screen_session_options.dart';
import 'package:crisp_cloud/models/ssh_terminal_profile.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/ssh_terminal_profiles_provider.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/ssh_terminal_profiles.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/widgets/ssh_terminal_profiles_dialog.dart';
import 'package:crisp_cloud/widgets/terminal_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = SshTerminalConfig(
    host: 'server.example',
    port: 2222,
    username: 'alice',
    authentication: SshTerminalAuthentication.privateKey,
    privateKey: 'KEY_SENTINEL',
    password: 'PASSWORD_SENTINEL',
    passphrase: 'PASSPHRASE_SENTINEL',
    screen: ScreenSessionOptions(
      sessionName: '1234.build',
      mode: ScreenSessionMode.attach,
    ),
  );
  String? raw;
  late SshTerminalProfiles store;

  setUp(() {
    raw = null;
    store = SshTerminalProfiles(
      read: () async => raw,
      write: (value) async {
        raw = value;
      },
    );
  });

  Future<void> open(WidgetTester tester, Widget dialog) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showDialog<void>(context: context, builder: (_) => dialog),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'saving a destination strips credentials and closes after successful storage',
    (tester) async {
      await open(
        tester,
        SaveSshTerminalProfileDialog(store: store, config: config),
      );
      await tester.enterText(
        find.byKey(const ValueKey('ssh-profile-name')),
        'Production',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(SaveSshTerminalProfileDialog), findsNothing);
      expect((await store.load()).single.name, 'Production');
      expect(
        (await store.load()).single.config.screen!.sessionName,
        '1234.build',
      );
      expect(raw, isNot(contains('SENTINEL')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'save errors stay visible without exposing storage exception contents',
    (tester) async {
      final broken = SshTerminalProfiles(
        read: () async => null,
        write: (_) async => throw StateError('SENSITIVE_INTERNAL_DETAIL'),
      );
      await open(
        tester,
        SaveSshTerminalProfileDialog(store: broken, config: config),
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Could not save SSH profile.'), findsOneWidget);
      expect(find.textContaining('SENSITIVE_INTERNAL_DETAIL'), findsNothing);
      expect(find.byType(SaveSshTerminalProfileDialog), findsOneWidget);
    },
  );

  testWidgets('cancel never creates a profile', (tester) async {
    await open(
      tester,
      SaveSshTerminalProfileDialog(store: store, config: config),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(raw, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting one profile leaves the other destination available', (
    tester,
  ) async {
    await store.save(SshTerminalProfile(name: 'One', config: config));
    await store.save(SshTerminalProfile(name: 'Two', config: config));
    await open(tester, SshTerminalProfilesDialog(store: store));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ssh-profile-One')),
        matching: find.byTooltip('Delete'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('One'), findsNothing);
    expect(find.text('Two'), findsOneWidget);
    expect((await store.load()).single.name, 'Two');
  });

  testWidgets('unreadable profiles show a bounded error and preserve storage', (
    tester,
  ) async {
    raw = 'invalid saved data';
    await open(tester, SshTerminalProfilesDialog(store: store));
    expect(find.text('Could not load SSH profiles.'), findsOneWidget);
    expect(raw, 'invalid saved data');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selecting a saved profile asks for credentials and cancel preserves live connection',
    (tester) async {
      await store.save(SshTerminalProfile(name: 'Production', config: config));
      final session = TerminalSession();
      final connection = _Connection();
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
          sshTerminalProfilesProvider.overrideWithValue(store),
        ],
      );
      addTearDown(() {
        session.dispose();
        container.dispose();
      });
      await session.connect(
        (_, __) async => connection,
        kind: TerminalSessionKind.ssh,
        label: 'existing@example',
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
      await tester.tap(find.byKey(const ValueKey('terminal-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved SSH profiles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Production'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<SshTerminalConnectDialog>(
        find.byType(SshTerminalConnectDialog),
      );
      expect(dialog.initialConfig!.host, 'server.example');
      expect(dialog.initialConfig!.screen!.mode, ScreenSessionMode.attach);
      expect(dialog.initialConfig!.password, isEmpty);
      expect(dialog.initialConfig!.privateKey, isEmpty);
      expect(dialog.initialConfig!.passphrase, isEmpty);
      expect(session.isConnected, isTrue);
      expect(connection.closed, isFalse);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(session.isConnected, isTrue);
      expect(connection.closed, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}

class _Connection implements TerminalConnection {
  final outputController = StreamController<String>();
  final finished = Completer<int?>();
  bool closed = false;
  @override
  bool get isSandbox => false;
  @override
  Stream<String> get output => outputController.stream;
  @override
  Future<int?> get exitCode => finished.future;
  @override
  Future<void> write(String data) async {}
  @override
  Future<void> resize(int columns, int rows) async {}
  @override
  Future<void> close() async {
    closed = true;
    if (!finished.isCompleted) finished.complete(0);
    if (!outputController.isClosed) unawaited(outputController.close());
  }
}
