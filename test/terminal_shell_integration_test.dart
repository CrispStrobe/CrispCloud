import 'package:crisp_cloud/services/terminal_shell_integration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  late Terminal terminal;
  late TerminalShellIntegration shell;
  late DateTime now;

  setUp(() {
    now = DateTime.utc(2026, 11, 15);
    terminal = Terminal(maxLines: 1000)..resize(80, 24);
    shell = TerminalShellIntegration(terminal, now: () => now);
  });
  tearDown(() {
    shell.dispose();
    terminal.dispose();
  });

  void start(String command, {String protocol = '133'}) {
    terminal.write(
      '\x1b]$protocol;A\x07user> \x1b]$protocol;B\x07$command\r\n\x1b]$protocol;C\x07',
    );
  }

  test('fragmented OSC maps Unicode command, output and status', () {
    terminal.write('\x1b]7;file:///tmp/Gr%C3%BC%C3%9Fe%20%E4%B8%AD\x1b');
    terminal.write('\\\x1b]133;A\x07中> \x1b]133;');
    terminal.write('B\x07printf Grüße\r\n\x1b]133;C\x07hello 中\r\n');
    final mark = shell.latestCommand!;
    expect(mark.command, 'printf Grüße');
    expect(mark.directory, '/tmp/Grüße 中');
    expect(mark.running, isTrue);
    now = now.add(const Duration(seconds: 4));
    terminal.write('\x1b]133;D;7\x07');
    expect(mark.running, isFalse);
    expect(mark.exitCode, 7);
    expect(mark.elapsed, const Duration(seconds: 4));
    expect(
      terminal.buffer.getText(shell.outputRange(mark)!, true).trim(),
      'hello 中',
    );
  });

  test('OSC633 equal previous status does not complete a new command', () {
    start('first', protocol: '633');
    terminal.write('\x1b]633;D;0\x07\r\n');
    start('second', protocol: '633');
    final mark = shell.latestCommand!;
    expect(mark.running, isTrue);
    expect(mark.exitCode, isNull);
    terminal.write('\x1b]633;D;0\x07');
    expect(mark.running, isFalse);
    expect(mark.exitCode, 0);
  });

  test('orphan and duplicate completion cannot invent commands or alerts', () {
    shell.notifyOnCompletion = true;
    terminal.write('\x1b]133;D;9\x07\x1b]133;C\x07');
    expect(shell.marks, isEmpty);
    expect(shell.notificationSerial, 0);
    start('work');
    terminal.write('\x1b]133;D;0\x07\x1b]133;D;1\x07');
    expect(shell.notificationSerial, 1);
    expect(shell.completionNotification!.exitCode, 0);
    expect(shell.notifyOnCompletion, isFalse);
  });

  test('new prompt closes an unterminated command with unknown status', () {
    start('work');
    final mark = shell.latestCommand!;
    terminal.write('output\r\n\x1b]133;A\x07');
    expect(mark.running, isFalse);
    expect(mark.finishedAt, isNotNull);
    expect(mark.exitCode, isNull);
  });

  test('continuation and right prompts do not split history', () {
    terminal.write(
      '\x1b]133;A\x07first\r\n\x1b]133;P;k=c\x07continued\r\n'
      '\x1b]133;P;k=r\x07right',
    );
    expect(shell.marks, hasLength(1));
  });

  test('alternate screen cannot create marks, completion or a directory', () {
    start('vim');
    final mark = shell.latestCommand!;
    terminal.write(
      '\x1b[?1049h\x1b]133;A\x07\x1b]133;B\x07bad'
      '\x1b]133;C\x07\x1b]133;D;1\x07\x1b]1337;SetMark\x07'
      '\x1b]7;file:///bad\x07',
    );
    expect(shell.marks, hasLength(1));
    expect(shell.currentDirectory, isNull);
    expect(shell.lineBefore(100), isNull);
    expect(mark.running, isTrue);
    terminal.write('\x1b[?1049l\x1b]133;D;0\x07');
    expect(mark.exitCode, 0);
  });

  test('manual and iTerm marks need no setup and send no input', () {
    final output = <String>[];
    terminal.onOutput = output.add;
    terminal.write('one\r\n');
    shell.addMark();
    terminal.write('two\r\n\x1b]1337;SetMark\x07three');
    expect(shell.marks, hasLength(2));
    expect(shell.detected, isFalse);
    expect(shell.marks.every((mark) => mark.manual), isTrue);
    expect(shell.lineBefore(2), 1);
    expect(shell.lineAfter(1), 2);
    expect(output, isEmpty);
  });

  test('anchors follow wide wrapped reflow and expire with scrollback', () {
    terminal.resize(10, 4);
    start('echo 中中中中中中中中');
    final mark = shell.latestCommand!;
    terminal.write('result\r\n\x1b]133;D;0\x07');
    terminal.resize(40, 4);
    expect(shell.contains(mark), isTrue);
    expect(mark.command, contains('中中中'));
    expect(shell.outputRange(mark), isNotNull);
    terminal.write(List.generate(1100, (i) => '$i\r\n').join());
    expect(shell.contains(mark), isFalse);
    expect(shell.marks, isEmpty);
    expect(shell.outputRange(mark), isNull);
  });

  test('mark count and directory metadata stay bounded', () {
    for (var i = 0; i < 550; i++) {
      terminal.write('line$i\r\n');
      shell.addMark();
    }
    expect(shell.marks, hasLength(TerminalShellIntegration.maximumMarks));
    terminal.write('\x1b]7;file:///${'a' * 2050}\x07');
    expect(shell.currentDirectory, isNull);
    terminal.write('\x1b]7;https://example.com/private\x07');
    expect(shell.currentDirectory, isNull);
    terminal.write('\x1b]7;file:///good\x07');
    expect(shell.currentDirectory, '/good');
    terminal.write('\x1b]7;file://user@host/private\x07');
    expect(shell.currentDirectory, '/good');
  });

  test('completion survives long output evicting the current prompt', () {
    start('large output');
    final mark = shell.latestCommand!;
    shell.notifyOnCompletion = true;
    terminal.write(List.generate(1100, (i) => '$i\r\n').join());
    expect(shell.marks, isEmpty);
    expect(shell.latestCommand, same(mark));
    terminal.write('\x1b]133;D;3\x07');
    expect(mark.exitCode, 3);
    expect(shell.notificationSerial, 1);
    expect(shell.outputRange(mark), isNull);
    terminal.write('\x1b]133;A\x07');
    expect(shell.latestCommand, same(mark));
  });

  test('disposal restores callback ownership', () {
    shell.dispose();
    var seen = 0;
    void previous(String code, List<String> args) => seen++;
    terminal.onPrivateOSC = previous;
    shell = TerminalShellIntegration(terminal);
    start('test');
    expect(seen, 3);
    shell.dispose();
    expect(terminal.onPrivateOSC, same(previous));
    terminal.write('\x1b]133;A\x07');
    expect(seen, 4);
  });
}
