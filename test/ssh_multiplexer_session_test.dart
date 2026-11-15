import 'package:crisp_cloud/models/ssh_multiplexer_session.dart';
import 'package:crisp_cloud/models/screen_session_options.dart';
import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher fails(SshMultiplexerDiscoveryFailure reason) => throwsA(
  isA<SshMultiplexerDiscoveryException>().having(
    (error) => error.failure,
    'failure',
    reason,
  ),
);

String screenListing(List<String> rows) =>
    'There are screens on:\n${rows.map((row) => '\t$row').join('\n')}\n'
    '${rows.length} Sockets in /run/screen/S-alice.\n';

void main() {
  test('tmux preserves exact names, window counts and attach-only options', () {
    final rows = parseSshMultiplexerSessions(
      SshMultiplexer.tmux,
      'build-01\t3\t2\nother\t1\t0\n',
    );
    expect(rows.map((row) => row.target), ['build-01', 'other']);
    expect(rows.first.windowCount, 3);
    expect(rows.first.attachedClients, 2);
    expect(rows.first.state, SshMultiplexerSessionState.attached);
    expect(rows.last.state, SshMultiplexerSessionState.detached);
    expect(rows.first.tmuxOptions!.mode, TmuxSessionMode.attach);
    expect(
      rows.first.tmuxOptions!.command,
      "exec tmux attach-session -t '=build-01'",
    );
    expect(rows.first.screenOptions, isNull);
  });

  test('unsupported tmux names remain visible and cannot produce commands', () {
    for (final name in [
      'with.dot',
      'with:colon',
      'with space',
      '-leading',
      'x' * 65,
    ]) {
      final row = parseSshMultiplexerSessions(
        SshMultiplexer.tmux,
        '$name\t1\t0\n',
      ).single;
      expect(row.name, name);
      expect(row.selectable, isFalse);
      expect(row.tmuxOptions, isNull);
    }
  });

  test('duplicate or malformed tmux rows are rejected', () {
    for (final output in [
      'work\t1\t0\nwork\t1\t1\n',
      'work\tbad\t0\n',
      'work\t1\t-1\n',
      'incomplete\n',
      '\t1\t0\n',
    ]) {
      expect(
        () => parseSshMultiplexerSessions(SshMultiplexer.tmux, output),
        fails(SshMultiplexerDiscoveryFailure.invalidListing),
      );
    }
  });

  test('record, line and aggregate listing bounds are enforced', () {
    for (final output in [
      List.generate(513, (i) => 's$i\t1\t0\n').join(),
      '${'x' * 4097}\t1\t0\n',
      'x' * (sshMultiplexerMaxOutputBytes + 1),
      '\n' * 2049,
    ]) {
      expect(
        () => parseSshMultiplexerSessions(SshMultiplexer.tmux, output),
        fails(SshMultiplexerDiscoveryFailure.tooMuchOutput),
      );
    }
    expect(
      parseSshMultiplexerSessions(
        SshMultiplexer.tmux,
        List.generate(512, (i) => 's$i\t1\t0\n').join(),
      ),
      hasLength(512),
    );
  });

  test('screen timestamps and multi-display status preserve full IDs', () {
    final rows = parseSshMultiplexerSessions(
      SshMultiplexer.screen,
      screenListing([
        '123.work\t(11/15/26 20:15:00)\t(Detached)',
        '456.build\t(Attached)',
        '789.pts-1.host\t(11/15/2026 20:15:00)\t(Multi, attached)',
        '987.test\t(Multi, detached)',
      ]),
    );
    expect(rows.map((row) => row.target), [
      '123.work',
      '456.build',
      '789.pts-1.host',
      '987.test',
    ]);
    expect(rows.every((row) => row.selectable), isTrue);
    expect(rows.first.screenOptions!.mode, ScreenSessionMode.attach);
    expect(rows.first.screenOptions!.sessionName, '123.work');
    expect(rows.first.tmuxOptions, isNull);
    expect(rows[2].state, SshMultiplexerSessionState.attached);
  });

  test('duplicate screen names remain distinguishable by exact full ID', () {
    final rows = parseSshMultiplexerSessions(
      SshMultiplexer.screen,
      screenListing(['123.work\t(Detached)', '456.work\t(Attached)']),
    );
    expect(rows.map((row) => row.name), ['work', 'work']);
    expect(rows.map((row) => row.target), ['123.work', '456.work']);
    expect(rows.every((row) => row.selectable), isTrue);
  });

  test('dead and unsupported screen entries are never selectable', () {
    final rows = parseSshMultiplexerSessions(
      SshMultiplexer.screen,
      screenListing([
        '123.work\t(Dead ???)',
        '456.bad:name\t(Detached)',
        '789.unreachable\t(Remote or dead)',
      ]),
    );
    expect(rows.every((row) => !row.selectable), isTrue);
    expect(rows.every((row) => row.screenOptions == null), isTrue);
    expect(rows.first.state, SshMultiplexerSessionState.unavailable);
  });

  test('screen prefix collisions are disabled before the attach recheck', () {
    for (final other in ['456.123.work', '456.123.worker', '123.worker']) {
      final rows = parseSshMultiplexerSessions(
        SshMultiplexer.screen,
        screenListing(['123.work\t(Detached)', '$other\t(Detached)']),
      );
      expect(rows.first.selectable, isFalse, reason: other);
    }
  });

  test('unknown screen names are not trimmed into supported targets', () {
    for (final name in ['work (custom)', 'work (11/15/26 20:15:00)', 'work ']) {
      final row = parseSshMultiplexerSessions(
        SshMultiplexer.screen,
        screenListing(['123.$name\t(Detached)']),
      ).single;
      expect(row.target, '123.$name');
      expect(row.selectable, isFalse);
      expect(row.screenOptions, isNull);
    }
  });

  test('incomplete, duplicate or inconsistent screen listings fail closed', () {
    for (final output in [
      '\t123.work\t(Detached)\n',
      'There are screens on:\n\t123.work\t(Detached)\n2 Sockets in /run/screen.\n',
      screenListing(['123.work\t(Detached)', '123.work\t(Attached)']),
      'No Sockets found in /run/screen.\n1 Socket in /run/screen.\n',
      'unexpected banner\n',
    ]) {
      expect(
        () => parseSshMultiplexerSessions(SshMultiplexer.screen, output),
        fails(SshMultiplexerDiscoveryFailure.invalidListing),
      );
    }
  });

  test('only explicit empty screen states are accepted on exit one', () {
    expect(
      parseSshMultiplexerSessions(
        SshMultiplexer.screen,
        'No Sockets found in /run/screen/S-alice.\n',
        exitCode: 1,
      ),
      isEmpty,
    );
    expect(
      () => parseSshMultiplexerSessions(
        SshMultiplexer.screen,
        '',
        exitCode: 1,
        stderr: 'Permission denied',
      ),
      fails(SshMultiplexerDiscoveryFailure.commandFailed),
    );
  });

  test(
    'tmux missing socket is empty while inaccessible sockets remain errors',
    () {
      for (final stderr in [
        'no server running on /tmp/tmux-1000/default\n',
        'no sessions\n',
        'error connecting to /tmp/tmux-1000/default (No such file or directory)\n',
      ]) {
        expect(
          parseSshMultiplexerSessions(
            SshMultiplexer.tmux,
            '',
            exitCode: 1,
            stderr: stderr,
          ),
          isEmpty,
        );
      }
      expect(
        () => parseSshMultiplexerSessions(
          SshMultiplexer.tmux,
          '',
          exitCode: 1,
          stderr:
              'error connecting to /tmp/tmux-1000/default (Permission denied)',
        ),
        fails(SshMultiplexerDiscoveryFailure.commandFailed),
      );
    },
  );

  test('missing tools and unknown exit status never become empty success', () {
    for (final kind in SshMultiplexer.values) {
      expect(
        () => parseSshMultiplexerSessions(kind, '', exitCode: 127),
        fails(SshMultiplexerDiscoveryFailure.missingTool),
      );
      expect(
        () => parseSshMultiplexerSessions(kind, '', exitCode: null),
        fails(SshMultiplexerDiscoveryFailure.commandFailed),
      );
    }
    expect(
      () => parseSshMultiplexerSessions(
        SshMultiplexer.tmux,
        'work\t1\t0\n',
        exitCode: 1,
      ),
      fails(SshMultiplexerDiscoveryFailure.commandFailed),
    );
  });

  test('display labels remove controls but keep raw targets disabled', () {
    final row = parseSshMultiplexerSessions(
      SshMultiplexer.tmux,
      'work\x1b\u202eevil\t1\t0\n',
    ).single;
    expect(row.label, isNot(contains('\x1b')));
    expect(row.label, isNot(contains('\u202e')));
    expect(row.selectable, isFalse);
  });

  test(
    'commands are fixed listing-only requests with an explicit C locale',
    () {
      final tmux = sshMultiplexerListCommand(SshMultiplexer.tmux);
      final screen = sshMultiplexerListCommand(SshMultiplexer.screen);
      expect(tmux, contains('LC_ALL=C tmux list-sessions -F'));
      expect(
        tmux,
        contains('#{session_name}\t#{session_windows}\t#{session_attached}'),
      );
      expect(screen, contains('LC_ALL=C screen -ls'));
      for (final command in [tmux, screen]) {
        expect(command, startsWith('exec sh -c '));
        expect(command, isNot(contains('kill-')));
        expect(command, isNot(contains(' -d')));
        expect(command, isNot(contains(' -R')));
      }
    },
  );

  test('returned snapshots cannot be mutated by a picker consumer', () {
    final rows = parseSshMultiplexerSessions(
      SshMultiplexer.tmux,
      'work\t1\t0\n',
    );
    expect(() => rows.clear(), throwsUnsupportedError);
  });
}
