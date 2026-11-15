import 'dart:convert';

import 'package:crisp_cloud/models/ssh_terminal_config.dart';
import 'package:crisp_cloud/models/ssh_terminal_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const first = SshJumpHost(
    host: 'bastion.example',
    port: 2222,
    username: 'outer',
    password: 'JUMP_PASSWORD_SENTINEL',
  );
  const second = SshJumpHost(
    host: 'inner.example',
    username: 'inner',
    authentication: SshTerminalAuthentication.privateKey,
    privateKey: 'JUMP_KEY_SENTINEL',
    passphrase: 'JUMP_PASSPHRASE_SENTINEL',
  );
  SshTerminalConfig config(List<SshJumpHost> jumps) => SshTerminalConfig(
    host: 'target.example',
    port: 22,
    username: 'target',
    password: 'TARGET_PASSWORD_SENTINEL',
    jumpHosts: jumps,
  );

  test('reconnect strips all hop secrets and snapshots the caller list', () {
    final jumps = [first, second];
    final sanitized = config(jumps).withoutSecrets();
    jumps.clear();
    expect(sanitized.jumpHosts, hasLength(2));
    expect(sanitized.password, isEmpty);
    for (final hop in sanitized.jumpHosts) {
      expect(hop.password, isEmpty);
      expect(hop.privateKey, isEmpty);
      expect(hop.passphrase, isEmpty);
    }
    expect(sanitized.jumpHosts.first.host, first.host);
    expect(sanitized.jumpHosts.first.port, first.port);
    expect(sanitized.jumpHosts.last.authentication, second.authentication);
    expect(() => sanitized.jumpHosts.clear(), throwsUnsupportedError);
  });

  test('profile round trips ordered routes through a credential allowlist', () {
    final profile = SshTerminalProfile(
      name: 'Work',
      config: config([first, second]),
    );
    final encoded = jsonEncode(profile.toJson());
    expect(encoded, isNot(contains('SENTINEL')));
    final restored = SshTerminalProfile.fromJson(jsonDecode(encoded)).config;
    expect(restored.jumpHosts.map((hop) => hop.host), [
      'bastion.example',
      'inner.example',
    ]);
    expect(restored.jumpHosts.first.port, 2222);
    expect(
      restored.jumpHosts.last.authentication,
      SshTerminalAuthentication.privateKey,
    );
    expect(restored.jumpHosts.last.privateKey, isEmpty);
  });

  test('legacy profiles without jumpHosts remain direct connections', () {
    final data = SshTerminalProfile(
      name: 'Direct',
      config: config([]),
    ).toJson();
    expect(data.containsKey('jumpHosts'), isFalse);
    expect(SshTerminalProfile.fromJson(data).config.jumpHosts, isEmpty);
  });

  test('external hop credential fields never become in-memory credentials', () {
    final data = SshTerminalProfile(name: 'Work', config: config([])).toJson();
    final restored = SshTerminalProfile.fromJson({
      ...data,
      'jumpHosts': [
        {
          ...first.toJson(),
          'password': 'injected password',
          'privateKey': 'injected key',
          'passphrase': 'injected passphrase',
        },
      ],
    });
    expect(restored.config.jumpHosts.single.password, isEmpty);
    expect(restored.config.jumpHosts.single.privateKey, isEmpty);
    expect(restored.config.jumpHosts.single.passphrase, isEmpty);
  });

  test('rejects a repeated hop or target regardless of DNS case/root dot', () {
    for (final jumps in [
      [first, first],
      [
        first,
        const SshJumpHost(
          host: 'BASTION.EXAMPLE.',
          port: 2222,
          username: 'different-user',
        ),
      ],
      [const SshJumpHost(host: 'TARGET.EXAMPLE.', username: 'outer')],
    ]) {
      expect(() => config(jumps).validateSessionOptions(), throwsArgumentError);
      expect(
        () => SshTerminalProfile(name: 'Loop', config: config(jumps)),
        throwsFormatException,
      );
    }
  });

  test('allows distinct ports and limits routes to three hops', () {
    final jumps = [
      for (var port = 2222; port <= 2224; port++)
        SshJumpHost(host: 'bastion.example', port: port, username: 'alice'),
    ];
    expect(() => config(jumps).validateSessionOptions(), returnsNormally);
    expect(
      () => config([
        ...jumps,
        const SshJumpHost(host: 'fourth.example', username: 'alice'),
      ]).validateSessionOptions(),
      throwsArgumentError,
    );
  });

  test('invalid hosts, usernames and ports fail before route construction', () {
    for (final host in [
      '',
      ' leading',
      'x y',
      'x\nspoof',
      'x\x1b',
      'x\u0085',
      'user@host',
      'host/path',
      '[::1]',
      'h' * 254,
    ]) {
      expect(SshJumpHost.isValidHost(host), isFalse, reason: host);
    }
    for (final username in ['', ' leading', 'alice\nroot', 'u' * 129]) {
      expect(SshJumpHost.isValidUsername(username), isFalse);
    }
    for (final port in [0, -1, 65536]) {
      expect(
        () => config([
          SshJumpHost(host: 'bastion.example', port: port, username: 'alice'),
        ]).validateSessionOptions(),
        throwsArgumentError,
      );
    }
    for (final host in ['bastion.example', '192.0.2.1', '2001:db8::1', '::1']) {
      expect(SshJumpHost.isValidHost(host), isTrue);
    }
  });

  test('malformed stored routes never silently fall back to direct SSH', () {
    final data = SshTerminalProfile(name: 'Work', config: config([])).toJson();
    for (final route in <Object>[
      'not-a-list',
      [false],
      [for (var i = 0; i < 4; i++) first.toJson()],
      [
        {...first.toJson(), 'port': '22'},
      ],
      [
        {...first.toJson(), 'host': 'bad\nhost'},
      ],
      [
        {...first.toJson(), 'authentication': 'unknown'},
      ],
      [first.toJson(), first.toJson()],
    ]) {
      expect(
        () => SshTerminalProfile.fromJson({...data, 'jumpHosts': route}),
        throwsFormatException,
      );
    }
  });
}
