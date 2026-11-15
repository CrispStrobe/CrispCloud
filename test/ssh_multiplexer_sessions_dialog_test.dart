import 'package:crisp_cloud/l10n/ssh_multiplexer_strings.dart';
import 'package:crisp_cloud/models/ssh_multiplexer_session.dart';
import 'package:crisp_cloud/widgets/ssh_multiplexer_sessions_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('filters without changing the exact attach target', (tester) async {
    final sessions = parseSshMultiplexerSessions(
      SshMultiplexer.tmux,
      'work\t2\t0\nOps-Build\t4\t2\n',
    );
    final selected = await _open(tester, sessions: sessions);
    expect(find.text('Detached · 2 windows · 0 attached clients'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('ssh-multiplexer-filter')),
      'OPS',
    );
    await tester.pumpAndSettle();
    expect(find.text('work'), findsNothing);
    await _tapSession(tester, 'Ops-Build');
    expect(selected.single, same(sessions.last));
    expect(selected.single!.tmuxOptions!.sessionName, 'Ops-Build');
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable and unsupported entries cannot be selected', (tester) async {
    final sessions = parseSshMultiplexerSessions(
      SshMultiplexer.screen,
      'There are screens on:\n'
      '\t123.good\t(Detached)\n'
      '\t456.bad:name\t(Attached)\n'
      '\t789.dead\t(Dead ???)\n'
      '3 Sockets in /run/screen/S-alice.\n',
    );
    final selected = await _open(
      tester, kind: SshMultiplexer.screen, sessions: sessions,
    );
    for (final target in ['456.bad:name', '789.dead']) {
      final tile = find.byKey(ValueKey('ssh-multiplexer-session-$target'));
      await tester.ensureVisible(tile);
      expect(tester.widget<ListTile>(tile).enabled, isFalse);
      expect(tester.widget<ListTile>(tile).onTap, isNull);
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }
    expect(selected, isEmpty);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Unsupported session name'), findsOneWidget);
    await _tapSession(tester, '123.good');
    expect(selected.single!.screenOptions!.sessionName, '123.good');
  });

  testWidgets('duplicate screen names display and return full IDs', (tester) async {
    final sessions = parseSshMultiplexerSessions(
      SshMultiplexer.screen,
      'There are screens on:\n'
      '\t123.work\t(Detached)\n'
      '\t456.work\t(Attached)\n'
      '2 Sockets in /run/screen/S-alice.\n',
    );
    final selected = await _open(
      tester, kind: SshMultiplexer.screen, sessions: sessions,
    );
    expect(find.text('123.work'), findsOneWidget);
    expect(find.text('456.work'), findsOneWidget);
    await _tapSession(tester, '456.work');
    expect(selected.single!.target, '456.work');
    expect(selected.single!.screenOptions!.mode.name, 'attach');
  });

  testWidgets('empty and filtered-empty states remain cancellable', (tester) async {
    final empty = await _open(tester, sessions: const []);
    expect(find.text('No sessions found.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ssh-multiplexer-cancel')));
    await tester.pumpAndSettle();
    expect(empty, [null]);

    final filtered = await _open(
      tester,
      sessions: parseSshMultiplexerSessions(SshMultiplexer.tmux, 'work\t1\t0\n'),
    );
    await tester.enterText(
      find.byKey(const ValueKey('ssh-multiplexer-filter')),
      'missing',
    );
    await tester.pumpAndSettle();
    expect(find.text('No sessions match this filter.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ssh-multiplexer-cancel')));
    await tester.pumpAndSettle();
    expect(filtered, [null]);
  });

  testWidgets('narrow layouts keep filtering, selection and cancellation usable', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final sessions = parseSshMultiplexerSessions(
      SshMultiplexer.tmux,
      List.generate(20, (i) => 'session-$i\t10\t2\n').join(),
    );
    final selected = await _open(tester, sessions: sessions);
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byKey(const ValueKey('ssh-multiplexer-filter')),
      'session-19',
    );
    await tester.pumpAndSettle();
    await _tapSession(tester, 'session-19');
    expect(selected.single!.target, 'session-19');
    expect(tester.takeException(), isNull);
  });

  testWidgets('German chrome translates titles, state and counts', (tester) async {
    await _open(
      tester,
      locale: const Locale('de'),
      sessions: parseSshMultiplexerSessions(SshMultiplexer.tmux, 'work\t2\t1\n'),
    );
    expect(find.text('tmux-Sitzungen'), findsOneWidget);
    expect(find.text('Sitzungen filtern'), findsOneWidget);
    expect(find.text('Verbunden · 2 Fenster · 1 verbundene Clients'), findsOneWidget);
    expect(find.text('Abbrechen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('localized errors retain bounded sanitized server details', (tester) async {
    String? message;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: const [Locale('en'), Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(builder: (context) {
        message = context.sshMultiplexerDiscoveryError(
          SshMultiplexerDiscoveryException(
            SshMultiplexer.screen,
            SshMultiplexerDiscoveryFailure.commandFailed,
            'Permission denied\x1b\u202e${'x' * 600}',
          ),
        );
        return const SizedBox.shrink();
      }),
    ));
    expect(message, startsWith('Impossible de lister les sessions screen.'));
    expect(message, contains('Permission denied'));
    expect(message, isNot(contains('\x1b')));
    expect(message, isNot(contains('\u202e')));
    expect(message!.length, lessThan(600));
  });
}

Future<void> _tapSession(WidgetTester tester, String target) async {
  final tile = find.byKey(ValueKey('ssh-multiplexer-session-$target'));
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<List<SshMultiplexerSession?>> _open(
  WidgetTester tester, {
  SshMultiplexer kind = SshMultiplexer.tmux,
  required List<SshMultiplexerSession> sessions,
  Locale locale = const Locale('en'),
}) async {
  final selected = <SshMultiplexerSession?>[];
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    supportedLocales: const [
      Locale('en'), Locale('de'), Locale('fr'), Locale('es'), Locale('pt'),
      Locale('zh'), Locale('ja'), Locale('ko'), Locale('ar'),
    ],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(
      body: Builder(builder: (context) => TextButton(
        onPressed: () async {
          selected.add(await showDialog<SshMultiplexerSession>(
            context: context,
            builder: (_) => SshMultiplexerSessionsDialog(
              kind: kind, sessions: sessions,
            ),
          ));
        },
        child: const Text('Open'),
      )),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return selected;
}
