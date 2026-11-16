import 'dart:convert';

import 'package:crisp_cloud/models/ssh_terminal_config.dart';
import 'package:crisp_cloud/models/ssh_terminal_profile.dart';
import 'package:crisp_cloud/models/terminal_arrangement.dart';
import 'package:crisp_cloud/services/ssh_terminal_profiles.dart';
import 'package:crisp_cloud/services/terminal_arrangements.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const plain = SshTerminalConfig(
    host: 'host.example',
    port: 22,
    username: 'user',
  );
  final configs = [
    const SshTerminalConfig(
      host: 'host.example',
      port: 22,
      username: 'user',
      authentication: SshTerminalAuthentication.agent,
    ),
    const SshTerminalConfig(
      host: 'host.example',
      port: 22,
      username: 'user',
      forwardAgent: true,
      password: 'password-SENTINEL',
      privateKey: 'key-SENTINEL',
      passphrase: 'phrase-SENTINEL',
    ),
    const SshTerminalConfig(
      host: 'host.example',
      port: 22,
      username: 'user',
      jumpHosts: [
        SshJumpHost(
          host: 'jump.example',
          username: 'jump',
          authentication: SshTerminalAuthentication.agent,
        ),
      ],
    ),
  ];

  test('agent authentication and forwarding intent survive secret-free round trips', () {
    for (final config in configs) {
      final profile = SshTerminalProfile(name: 'Agent', config: config);
      final raw = jsonEncode(profile.toJson());
      expect(raw, isNot(contains('SENTINEL')));
      expect(raw, isNot(contains('SSH_AUTH_SOCK')));
      final decoded = SshTerminalProfile.fromJson(jsonDecode(raw)).config;
      expect(decoded.usesAgent, isTrue);
      expect(decoded.authentication, config.authentication);
      expect(decoded.forwardAgent, config.forwardAgent);
      expect(
        decoded.jumpHosts.map((jump) => jump.authentication),
        config.jumpHosts.map((jump) => jump.authentication),
      );
      expect(decoded.password, isEmpty);
      expect(decoded.privateKey, isEmpty);
      expect(decoded.passphrase, isEmpty);
    }
    final legacy = SshTerminalProfile.fromJson(
      SshTerminalProfile(name: 'Legacy', config: plain).toJson(),
    ).config;
    expect(legacy.usesAgent, isFalse);
    expect(legacy.forwardAgent, isFalse);
  });

  test('agent profile settings upgrade to v3 and never downgrade after deleting them', () async {
    for (final config in configs) {
      String? raw = jsonEncode({'version': 2, 'profiles': []});
      final store = SshTerminalProfiles(
        read: () async => raw,
        write: (value) async => raw = value,
      );
      await store.save(SshTerminalProfile(name: 'Agent', config: config));
      expect(jsonDecode(raw!)['version'], 3);
      expect((await store.load()).single.config.usesAgent, isTrue);
      await store.delete('Agent');
      expect(jsonDecode(raw!)['version'], 3);
      await store.save(SshTerminalProfile(name: 'Plain', config: plain));
      expect(jsonDecode(raw!)['version'], 3);
    }
  });

  test(
    'arrangements preserve forwarding permission under a v3 envelope',
    () async {
      for (final config in configs) {
        String? raw;
        final store = TerminalArrangements(
          read: () async => raw,
          write: (value) async => raw = value,
        );
        await store.save(
          TerminalArrangement(
            name: 'Agent',
            tabs: [
              TerminalArrangementTab(
                paneState: TerminalPaneState(sshConfig: config),
              ),
            ],
          ),
        );
        expect(jsonDecode(raw!)['version'], 3);
        expect(raw, isNot(contains('SENTINEL')));
        final restored =
            (await store.load()).single.tabs.single.paneState.sshConfig!;
        expect(restored.usesAgent, isTrue);
        expect(restored.forwardAgent, config.forwardAgent);
        await store.delete('Agent');
        expect(jsonDecode(raw!)['version'], 3);
        await store.save(
          TerminalArrangement(name: 'Plain', tabs: [TerminalArrangementTab()]),
        );
        expect(jsonDecode(raw!)['version'], 3);
      }
    },
  );

  test('unrecognized agent permission values reject instead of enabling forwarding', () {
    final data = SshTerminalProfile(name: 'Plain', config: plain).toJson();
    for (final value in ['true', 1, [], {}]) {
      expect(
        () => SshTerminalProfile.fromJson({...data, 'forwardAgent': value}),
        throwsFormatException,
      );
    }
    expect(
      SshJumpHost.fromJson({
        'host': 'jump.example',
        'port': 22,
        'username': 'jump',
        'authentication': 'agent',
        'password': 'SENTINEL',
        'privateKey': 'SENTINEL',
        'passphrase': 'SENTINEL',
        'forwardAgent': true,
      }).toJson(),
      {
        'host': 'jump.example',
        'port': 22,
        'username': 'jump',
        'authentication': 'agent',
      },
    );
  });

  test(
    'unknown future agent profile and arrangement stores remain untouched',
    () async {
      final rawProfiles = jsonEncode({'version': 99, 'profiles': []});
      final rawArrangements = jsonEncode({'version': 99, 'arrangements': []});
      var writes = 0;
      final profiles = SshTerminalProfiles(
        read: () async => rawProfiles,
        write: (_) async => writes++,
      );
      final arrangements = TerminalArrangements(
        read: () async => rawArrangements,
        write: (_) async => writes++,
      );
      await expectLater(
        profiles.save(SshTerminalProfile(name: 'Agent', config: configs.first)),
        throwsFormatException,
      );
      await expectLater(arrangements.delete('Agent'), throwsFormatException);
      expect(writes, 0);
    },
  );

  test(
    'separate default stores serialize mutations without losing agent settings',
    () async {
      SharedPreferences.setMockInitialValues({});
      final one = SshTerminalProfiles();
      final two = SshTerminalProfiles();
      await Future.wait([
        one.save(SshTerminalProfile(name: 'Agent', config: configs[1])),
        two.save(SshTerminalProfile(name: 'Plain', config: plain)),
      ]);
      final profiles = await one.load();
      expect(profiles.map((profile) => profile.name), ['Agent', 'Plain']);
      expect(profiles.first.config.forwardAgent, isTrue);
      final stored = (await SharedPreferences.getInstance()).getString(
        SshTerminalProfiles.preferencesKey,
      )!;
      expect(jsonDecode(stored)['version'], 3);
    },
  );
}
