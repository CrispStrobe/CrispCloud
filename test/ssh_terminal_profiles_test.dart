import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/models/screen_session_options.dart';
import 'package:crisp_cloud/models/ssh_terminal_config.dart';
import 'package:crisp_cloud/models/ssh_terminal_profile.dart';
import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:crisp_cloud/services/ssh_terminal_profiles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SshTerminalConfig config({
    TmuxSessionOptions? tmux,
    ScreenSessionOptions? screen,
    List<SshJumpHost> jumpHosts = const [],
  }) => SshTerminalConfig(
    host: 'ssh.example',
    port: 2222,
    username: 'alice',
    authentication: SshTerminalAuthentication.privateKey,
    password: 'PASSWORD_SENTINEL',
    privateKey: 'PRIVATE_KEY_SENTINEL',
    passphrase: 'PASSPHRASE_SENTINEL',
    gateway: Uri.parse('wss://gateway.example/ssh'),
    tmux: tmux,
    screen: screen,
    jumpHosts: jumpHosts,
  );

  test('profiles remove credentials in memory and use an explicit persisted allowlist', () {
    final profile = SshTerminalProfile(name: 'Build', config: config());
    expect(profile.config.password, isEmpty);
    expect(profile.config.privateKey, isEmpty);
    expect(profile.config.passphrase, isEmpty);
    final raw = jsonEncode(profile.toJson());
    expect(raw, isNot(contains('SENTINEL')));
    expect(profile.toJson().keys, isNot(contains('password')));
    expect(profile.toJson().keys, isNot(contains('privateKey')));
    expect(profile.toJson().keys, isNot(contains('passphrase')));
    final decoded = SshTerminalProfile.fromJson(jsonDecode(raw));
    expect(decoded.config.authentication, SshTerminalAuthentication.privateKey);
    expect(decoded.config.host, 'ssh.example');
    expect(decoded.config.port, 2222);
    expect(decoded.config.username, 'alice');
    expect(decoded.config.gateway, Uri.parse('wss://gateway.example/ssh'));
  });

  test('all tmux and screen modes survive a store round trip without changing intent', () {
    for (final mode in TmuxSessionMode.values) {
      final decoded = SshTerminalProfile.fromJson(
        SshTerminalProfile(
          name: 'tmux',
          config: config(
            tmux: TmuxSessionOptions(sessionName: 'build-01', mode: mode),
          ),
        ).toJson(),
      );
      expect(decoded.config.tmux!.mode, mode);
      expect(decoded.config.tmux!.sessionName, 'build-01');
      expect(decoded.config.screen, isNull);
    }
    for (final mode in ScreenSessionMode.values) {
      final target = mode == ScreenSessionMode.attach
          ? '1234.pts-1.host'
          : 'build-01';
      final decoded = SshTerminalProfile.fromJson(
        SshTerminalProfile(
          name: 'screen',
          config: config(
            screen: ScreenSessionOptions(sessionName: target, mode: mode),
          ),
        ).toJson(),
      );
      expect(decoded.config.screen!.mode, mode);
      expect(decoded.config.screen!.sessionName, target);
      expect(decoded.config.tmux, isNull);
    }
  });

  test(
    'unknown auth or session modes fail instead of falling back to a new shell',
    () {
      final data = SshTerminalProfile(name: 'Build', config: config()).toJson();
      for (final patch in <Map<String, dynamic>>[
        {'authentication': 'agent'},
        {
          'session': {'kind': 'unknown'},
        },
        {
          'session': {'kind': 'tmux', 'name': 'build', 'mode': 'unknown'},
        },
        {
          'session': {'kind': 'screen', 'name': 'build', 'mode': 'unknown'},
        },
        {
          'session': {
            'kind': 'screen',
            'name': "name'; exit",
            'mode': 'attach',
          },
        },
        {'port': '22'},
        {'port': 65536},
        {'host': 'host\nspoof'},
        {'username': 'user\x1b'},
        {'gateway': 'wss://user:secret@gateway.example/ssh'},
        {'gateway': 'wss://gateway.example/ssh?token=secret'},
      ]) {
        expect(
          () => SshTerminalProfile.fromJson({...data, ...patch}),
          throwsFormatException,
        );
      }
      expect(
        () => SshTerminalProfile(
          name: 'invalid',
          config: config(
            tmux: const TmuxSessionOptions(sessionName: 'build'),
            screen: const ScreenSessionOptions(sessionName: 'build'),
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test('extra credential fields in external records never populate config', () {
    final data = SshTerminalProfile(name: 'Build', config: config()).toJson();
    final decoded = SshTerminalProfile.fromJson({
      ...data,
      'password': 'external password',
      'privateKey': 'external key',
      'passphrase': 'external passphrase',
    });
    expect(decoded.config.password, isEmpty);
    expect(decoded.config.privateKey, isEmpty);
    expect(decoded.config.passphrase, isEmpty);
  });

  test('stored gateway text is validated before URI normalization', () {
    final data = SshTerminalProfile(name: 'Build', config: config()).toJson();
    for (final gateway in [
      'wss://gateway.example:0/ssh',
      'wss://[::1]:0/ssh',
      'wss://gateway.example:65536/ssh',
      'wss://gateway.example:invalid/ssh',
      'wss://[::1/ssh',
      '',
    ]) {
      expect(
        () => SshTerminalProfile.fromJson({...data, 'gateway': gateway}),
        throwsFormatException,
        reason: gateway,
      );
    }
    for (final gateway in [
      'wss://gateway.example:443/ssh',
      'wss://gateway.example:8443/ssh',
      'wss://[::1]:8443/ssh',
    ]) {
      final decoded = SshTerminalProfile.fromJson({
        ...data,
        'gateway': gateway,
      });
      expect(decoded.config.gateway, Uri.parse(gateway));
    }
    expect(
      SshTerminalProfile.fromJson({...data, 'gateway': null}).config.gateway,
      isNull,
    );
  });

  test(
    'simultaneous saves serialize read-modify-write and preserve both tabs',
    () async {
      String? raw;
      final firstWrite = Completer<void>();
      final releaseWrite = Completer<void>();
      var writes = 0;
      final store = SshTerminalProfiles(
        read: () async => raw,
        write: (value) async {
          writes++;
          if (writes == 1) {
            firstWrite.complete();
            await releaseWrite.future;
          }
          raw = value;
        },
      );
      final one = store.save(SshTerminalProfile(name: 'One', config: config()));
      await firstWrite.future;
      final two = store.save(SshTerminalProfile(name: 'Two', config: config()));
      releaseWrite.complete();
      await Future.wait([one, two]);
      expect((await store.load()).map((profile) => profile.name), [
        'One',
        'Two',
      ]);
      expect(raw, isNot(contains('SENTINEL')));
    },
  );

  test(
    'jump routes upgrade the envelope and never silently downgrade it',
    () async {
      final direct = SshTerminalProfile(name: 'Direct', config: config());
      String? raw = jsonEncode({
        'version': 1,
        'profiles': [direct.toJson()],
      });
      final store = SshTerminalProfiles(
        read: () async => raw,
        write: (value) async => raw = value,
      );
      expect((await store.load()).single.name, 'Direct');
      await store.save(
        SshTerminalProfile(
          name: 'Routed',
          config: config(
            jumpHosts: const [
              SshJumpHost(
                host: 'bastion.example',
                username: 'jump',
                password: 'JUMP_SENTINEL',
              ),
            ],
          ),
        ),
      );
      expect(jsonDecode(raw!)['version'], 2);
      expect(raw, isNot(contains('SENTINEL')));
      expect(
        (await store.load()).last.config.jumpHosts.single.host,
        'bastion.example',
      );

      // Old v1 readers must continue to reject/preserve an upgraded store,
      // including after the last route or the last profile is removed.
      await store.delete('Routed');
      expect(jsonDecode(raw!)['version'], 2);
      await store.save(direct);
      expect(jsonDecode(raw!)['version'], 2);
      await store.delete('Direct');
      expect(jsonDecode(raw!)['version'], 2);
      expect(await store.load(), isEmpty);
    },
  );

  test(
    'a direct-only legacy store retains its compatible v1 envelope',
    () async {
      String? raw;
      final store = SshTerminalProfiles(
        read: () async => raw,
        write: (value) async => raw = value,
      );
      await store.save(SshTerminalProfile(name: 'Direct', config: config()));
      expect(jsonDecode(raw!)['version'], 1);
      expect((await store.load()).single.config.jumpHosts, isEmpty);
    },
  );

  test(
    'a newer, malformed or duplicate store is preserved before a mutation',
    () async {
      final profile = SshTerminalProfile(name: 'Build', config: config());
      for (final raw in [
        '{invalid',
        jsonEncode({'version': 3, 'profiles': []}),
        jsonEncode({'version': 1.0, 'profiles': []}),
        jsonEncode({
          'version': 1,
          'profiles': [profile.toJson(), profile.toJson()],
        }),
        jsonEncode({
          'version': 1,
          'profiles': [
            {'name': 'incomplete'},
          ],
        }),
        'x' * (SshTerminalProfiles.maxStorageLength + 1),
      ]) {
        var writes = 0;
        final store = SshTerminalProfiles(
          read: () async => raw,
          write: (_) async {
            writes++;
          },
        );
        await expectLater(store.save(profile), throwsFormatException);
        await expectLater(store.delete('Build'), throwsFormatException);
        expect(writes, 0);
      }
    },
  );

  test(
    'a full store allows replacing one profile but does not drop entries',
    () async {
      String? raw;
      final store = SshTerminalProfiles(
        read: () async => raw,
        write: (value) async {
          raw = value;
        },
      );
      for (var i = 0; i < SshTerminalProfiles.maxProfiles; i++) {
        await store.save(
          SshTerminalProfile(name: 'Profile $i', config: config()),
        );
      }
      final before = raw;
      await expectLater(
        store.save(SshTerminalProfile(name: 'Overflow', config: config())),
        throwsStateError,
      );
      expect(raw, before);
      await store.save(
        SshTerminalProfile(
          name: 'Profile 0',
          config: const SshTerminalConfig(
            host: 'new.example',
            port: 22,
            username: 'bob',
          ),
        ),
      );
      final profiles = await store.load();
      expect(profiles, hasLength(50));
      expect(
        profiles.firstWhere((p) => p.name == 'Profile 0').config.host,
        'new.example',
      );
      await store.delete('Profile 1');
      expect(await store.load(), hasLength(49));
    },
  );

  test(
    'write failure is reported and does not poison later reads or saves',
    () async {
      String? raw;
      var fail = true;
      final store = SshTerminalProfiles(
        read: () async => raw,
        write: (value) async {
          if (fail) throw StateError('disk unavailable');
          raw = value;
        },
      );
      final profile = SshTerminalProfile(name: 'Build', config: config());
      await expectLater(store.save(profile), throwsStateError);
      expect(await store.load(), isEmpty);
      fail = false;
      await store.save(profile);
      expect((await store.load()).single.name, 'Build');
    },
  );
}
