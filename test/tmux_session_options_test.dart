import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts short names and the 64-character boundary', () {
    for (final name in ['a', '0', '_', 'build_2-linux', 'a' * 64]) {
      expect(TmuxSessionOptions.isValidSessionName(name), isTrue, reason: name);
      expect(
        TmuxSessionOptions(sessionName: name).command,
        "exec tmux new-session -A -s '$name'",
      );
    }
  });

  test('attach targets the exact session without detaching other clients', () {
    const options = TmuxSessionOptions(
      sessionName: 'build_2-linux',
      mode: TmuxSessionMode.attach,
    );
    expect(options.command, "exec tmux attach-session -t '=build_2-linux'");
  });

  test(
    'rejects shell syntax, tmux targets, whitespace and oversized names',
    () {
      final invalid = [
        '',
        'a' * 65,
        '-detach',
        'two words',
        'session\n',
        'session\r',
        'session\t',
        'session\x00',
        ' work',
        'work ',
        'a.b',
        'a:b',
        '=session',
        r'$1',
        r'$(touch /tmp/injected)',
        '`id`',
        "work'; kill-server; #",
        'work;kill-server',
        'work&&id',
        'work|id',
        'a/b',
        r'a\b',
        '*',
        '?',
        '[work]',
        '{work}',
        'café',
        '会議',
        'session🙂',
      ];
      for (final name in invalid) {
        expect(
          TmuxSessionOptions.isValidSessionName(name),
          isFalse,
          reason: name,
        );
        for (final mode in TmuxSessionMode.values) {
          expect(
            () => TmuxSessionOptions(sessionName: name, mode: mode).command,
            throwsArgumentError,
            reason: '$mode: $name',
          );
        }
      }
    },
  );
}
