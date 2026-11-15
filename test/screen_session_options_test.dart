import 'package:crisp_cloud/models/screen_session_options.dart';
import 'package:crisp_cloud/models/ssh_terminal_config.dart';
import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new screen sessions use explicit creation, never attach fallback', () {
    for (final name in ['a', '0', '_', 'build_2-linux', 'a' * 64]) {
      expect(ScreenSessionOptions.isValidSessionName(name), isTrue);
      expect(
        ScreenSessionOptions(sessionName: name).command,
        "exec screen -m -S '$name'",
      );
    }
  });

  test('attach accepts safe exact names and full screen listing IDs', () {
    for (final target in [
      'work',
      '123',
      '123.work',
      '123.pts-0.server',
      '2147483647.${'a' * 64}',
    ]) {
      final options = ScreenSessionOptions(
        sessionName: target,
        mode: ScreenSessionMode.attach,
      );
      expect(options.isValid, isTrue, reason: target);
      expect(options.command, contains("crispcloud-screen '$target'"));
      expect(options.command, contains('exec screen -x'));
    }
    expect(ScreenSessionOptions.isValidSessionName('123.work'), isFalse);
  });

  test('rejects screen options, shell syntax and malformed full IDs', () {
    for (final name in [
      '',
      'a' * 65,
      '-x',
      'two words',
      'work\n',
      'work\r',
      'work\t',
      'work\x00',
      ' work',
      'work ',
      r'$(id)',
      '`id`',
      "work'; id; #",
      'work;id',
      'work&&id',
      'work|id',
      'alice/work',
      r'a\b',
      '*',
      '?',
      '[work]',
      'café',
      '会議',
      '0.work',
      '01.work',
      '123.',
      '123.-work',
      '12345678901.work',
      '123.${'a' * 65}',
    ]) {
      for (final mode in ScreenSessionMode.values) {
        expect(
          () => ScreenSessionOptions(sessionName: name, mode: mode).command,
          throwsArgumentError,
          reason: '$mode: $name',
        );
      }
    }
  });

  test('reconnect preserves screen target and mode without secrets', () {
    const config = SshTerminalConfig(
      host: 'ssh.example',
      port: 2222,
      username: 'alice',
      password: 'password-secret',
      privateKey: 'key-secret',
      passphrase: 'phrase-secret',
      screen: ScreenSessionOptions(
        sessionName: '123.pts-0.server',
        mode: ScreenSessionMode.attach,
      ),
    );
    final reconnect = config.withoutSecrets();
    expect(reconnect.screen?.sessionName, '123.pts-0.server');
    expect(reconnect.screen?.mode, ScreenSessionMode.attach);
    expect(reconnect.tmux, isNull);
    expect(reconnect.password, isEmpty);
    expect(reconnect.privateKey, isEmpty);
    expect(reconnect.passphrase, isEmpty);
    expect(reconnect.validateSessionOptions, returnsNormally);
  });

  test('configuration rejects conflicting or invalid multiplexer options', () {
    for (final config in [
      const SshTerminalConfig(
        host: 'ssh.example',
        port: 22,
        username: 'alice',
        tmux: TmuxSessionOptions(sessionName: 'work'),
        screen: ScreenSessionOptions(sessionName: 'work'),
      ),
      const SshTerminalConfig(
        host: 'ssh.example',
        port: 22,
        username: 'alice',
        screen: ScreenSessionOptions(sessionName: '-R'),
      ),
    ]) {
      expect(config.validateSessionOptions, throwsArgumentError);
    }
  });
}
