import 'dart:convert';

import 'package:crisp_cloud/models/ssh_terminal_config.dart';
import 'package:crisp_cloud/models/ssh_terminal_profile.dart';
import 'package:crisp_cloud/models/terminal_arrangement.dart';
import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:crisp_cloud/services/ssh_terminal_profiles.dart';
import 'package:crisp_cloud/services/terminal_arrangements.dart';
import 'package:flutter_test/flutter_test.dart';

const _nativeConfig = SshTerminalConfig(
  host: 'server.example',
  port: 22,
  username: 'user',
  password: 'PASSWORD_SENTINEL',
  privateKey: 'KEY_SENTINEL',
  passphrase: 'PHRASE_SENTINEL',
  tmux: TmuxSessionOptions(
    sessionName: 'work',
    mode: TmuxSessionMode.attach,
    controlMode: true,
  ),
);

void main() {
  test(
    'native tmux profiles upgrade to v4 and preserve the envelope on deletion',
    () async {
      String? raw;
      final store = SshTerminalProfiles(
        read: () async => raw,
        write: (value) async => raw = value,
      );
      await store.save(SshTerminalProfile(name: 'Work', config: _nativeConfig));
      expect(jsonDecode(raw!)['version'], 4);
      expect(raw, isNot(contains('SENTINEL')));
      final config = (await store.load()).single.config;
      expect(config.tmux!.controlMode, isTrue);
      expect(config.tmux!.mode, TmuxSessionMode.attach);
      expect(config.withoutSecrets().tmux!.controlMode, isTrue);
      expect(config.password, isEmpty);
      await store.delete('Work');
      expect(jsonDecode(raw!)['version'], 4);
      expect(await store.load(), isEmpty);
    },
  );

  test('ordinary legacy tmux records retain their PTY behavior', () {
    final data = SshTerminalProfile(
      name: 'Work',
      config: _nativeConfig,
    ).toJson();
    (data['session'] as Map).remove('controlMode');
    final legacy = SshTerminalProfile.fromJson(data);
    expect(legacy.config.tmux!.controlMode, isFalse);
    expect(legacy.config.tmux!.command, "exec tmux attach-session -t '=work'");
  });

  test(
    'invalid native mode preserves a stored profile before save and delete',
    () async {
      final data = SshTerminalProfile(
        name: 'Work',
        config: _nativeConfig,
      ).toJson();
      (data['session'] as Map)['controlMode'] = 'true';
      final raw = jsonEncode({
        'version': 4,
        'profiles': [data],
      });
      var writes = 0;
      final store = SshTerminalProfiles(
        read: () async => raw,
        write: (_) async => writes++,
      );
      await expectLater(store.load(), throwsFormatException);
      await expectLater(store.delete('Work'), throwsFormatException);
      await expectLater(
        store.save(SshTerminalProfile(name: 'Work', config: _nativeConfig)),
        throwsFormatException,
      );
      expect(writes, 0);
    },
  );

  test(
    'arrangements retain native mode through a secret-free v4 round trip',
    () async {
      String? raw;
      final store = TerminalArrangements(
        read: () async => raw,
        write: (value) async => raw = value,
      );
      await store.save(
        TerminalArrangement(
          name: 'Work',
          tabs: [
            TerminalArrangementTab(
              paneState: TerminalPaneState(sshConfig: _nativeConfig),
            ),
          ],
        ),
      );
      expect(jsonDecode(raw!)['version'], 4);
      expect(raw, isNot(contains('SENTINEL')));
      final restored =
          (await store.load()).single.tabs.single.paneState.sshConfig!;
      expect(restored.tmux!.controlMode, isTrue);
      expect(restored.tmux!.mode, TmuxSessionMode.attach);
      await store.delete('Work');
      expect(jsonDecode(raw!)['version'], 4);
      expect(await store.load(), isEmpty);
    },
  );
}
