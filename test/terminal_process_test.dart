@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/terminal_backends.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/widgets/terminal_process_native.dart';
import 'package:crisp_cloud/widgets/terminal_process_stub.dart' as web_stub;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  test('web cannot start a local shell', () async {
    expect(await web_stub.startShell('/', columns: 120, rows: 30), isNull);
  });

  group('Local desktop PTY', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'crisp_cloud_terminal_',
      );
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test(
      'dispose is safe before attaching output and can be repeated',
      () async {
        final shell = (await startShell(directory.path))!;
        addTearDown(shell.dispose);

        await Future.wait([shell.dispose(), shell.dispose()])
            .timeout(const Duration(seconds: 10));
        await shell.exitCode.timeout(const Duration(seconds: 10));
        await expectLater(shell.write('ignored'), throwsStateError);
      },
    );

    test('Windows ConPTY accepts input and reports the shell exit', () async {
      // flutter_test defaults to Android even on a Windows host. Exercise the
      // same Windows emulator and input encoding as the desktop application.
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = previousPlatform);
      final session = TerminalSession();
      addTearDown(() async {
        await session.disconnect();
        session.dispose();
      });
      final rawOutput = StringBuffer();

      await session.connect((columns, rows) async {
        final connection = await openLocalTerminal(
          '${directory.path}/removed-directory',
          columns,
          rows,
        );
        return _RecordingConnection(connection, rawOutput);
      }, kind: TerminalSessionKind.local);

      // ConPTY can request terminal attributes before accepting normal input.
      // A bare output collector never answers; TerminalSession does, just as
      // in the app. Wait for cmd's rendered prompt, not a startup sleep.
      await _waitForSession(
        session,
        () => session.terminal.buffer.getText().trimRight().endsWith('>'),
        rawOutput,
        'initial command prompt',
      );
      session.terminal.textInput('echo CrispCloud ConPTY');
      session.terminal.keyInput(TerminalKey.enter);
      session.terminal.textInput('exit 7');
      session.terminal.keyInput(TerminalKey.enter);

      await _waitForSession(
        session,
        () => session.status == TerminalSessionStatus.exited,
        rawOutput,
        'shell exit',
      );
      expect(session.exitCode, 7);
      // An echoed input line contains the same marker but is not evidence that
      // the shell ran it. Require a separate rendered command-output line.
      expect(
        session.terminal.buffer
            .getText()
            .split('\n')
            .map((line) => line.trim()),
        contains('CrispCloud ConPTY'),
        reason: 'Raw ConPTY output: ${jsonEncode(rawOutput.toString())}',
      );
    }, skip: !Platform.isWindows);

    group('POSIX PTY', () {
      test('allocates a TTY and retains ANSI output through process exit', () async {
        final script = await _script(directory, '''
test -t 0 && test -t 1 && test -t 2 || exit 42
test -f './terminal fixture.sh' || exit 43
printf '\\033[31mreal-pty\\033[0m\\n'
stty size
pwd
exit 7
''');
        final shell = (await startShell(
          directory.path,
          columns: 103,
          rows: 37,
        ))!;
        addTearDown(shell.dispose);

        // Write before subscribing: output produced during startup must remain
        // available, even if the child exits before the listener is attached.
        await shell.write('exec /bin/sh ${_quote(script.path)}\r');
        final output = shell.outputStream.join();

        expect(await shell.exitCode.timeout(const Duration(seconds: 10)), 7);
        final text = await output;
        expect(text, contains('\x1b[31mreal-pty\x1b[0m'));
        expect(text, contains('37 103'));
        expect(text, contains(directory.path));
      });

      test('resizing changes the size seen by the running process', () async {
        final script = await _script(directory, '''
stty -echo
printf 'RESIZE_READY\\n'
IFS= read -r reply
stty size
exit 0
''');
        final shell = (await startShell(directory.path))!;
        addTearDown(shell.dispose);
        final capture = _OutputCapture(shell.outputStream);
        addTearDown(capture.cancel);
        await shell.write('exec /bin/sh ${_quote(script.path)}\r');
        await capture.waitFor('RESIZE_READY');

        shell.resize(91, 29);
        await shell.write('\r');
        final output = capture.readToEnd();

        expect(await shell.exitCode.timeout(const Duration(seconds: 10)), 0);
        expect(await output, contains('29 91'));
      });

      test(
        'streams split UTF-8 output and sends non-ASCII input unchanged',
        () async {
          final script = await _script(directory, r'''
stty -echo
printf 'UTF8_READY:'
printf '\303'
IFS= read -r reply
printf '\251\n'
printf 'input:%s\n' "$reply"
exit 23
''');
          final shell = (await startShell(directory.path))!;
          addTearDown(shell.dispose);
          final capture = _OutputCapture(shell.outputStream);
          addTearDown(capture.cancel);
          await shell.write('exec /bin/sh ${_quote(script.path)}\r');
          await capture.waitFor('UTF8_READY:');

          // The second byte of é is emitted only after this terminal input.
          await shell.write('漢字 😀\r');
          final output = capture.readToEnd();

          expect(await shell.exitCode.timeout(const Duration(seconds: 10)), 23);
          final text = await output;
          expect(text, contains('UTF8_READY:é'));
          expect(text, contains('input:漢字 😀'));
          expect(text, isNot(contains('\uFFFD')));
        },
      );

      test('Ctrl+C reaches the terminal foreground process', () async {
        final script = await _script(directory, '''
stty -echo
trap 'printf "INT_HANDLED\\n"; exit 0' INT
printf 'INT_READY\\n'
while IFS= read -r reply; do :; done
''');
        final shell = (await startShell(directory.path))!;
        addTearDown(shell.dispose);
        final capture = _OutputCapture(shell.outputStream);
        addTearDown(capture.cancel);
        await shell.write('exec /bin/sh ${_quote(script.path)}\r');
        await capture.waitFor('INT_READY');

        await shell.write('\x03');
        final output = capture.readToEnd();

        expect(await shell.exitCode.timeout(const Duration(seconds: 10)), 0);
        expect(await output, contains('INT_HANDLED'));
      });
    }, skip: !(Platform.isLinux || Platform.isMacOS));
  }, skip: !(Platform.isLinux || Platform.isMacOS || Platform.isWindows));
}

Future<File> _script(Directory directory, String contents) =>
    File('${directory.path}/terminal fixture.sh').writeAsString(contents);

String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

Future<void> _waitForSession(
  TerminalSession session,
  bool Function() ready,
  StringBuffer rawOutput,
  String phase,
) async {
  final completed = Completer<void>();
  void changed() {
    if (completed.isCompleted) return;
    if (session.error case final error?) {
      completed.completeError(
        StateError(
          'ConPTY failed while waiting for $phase: $error. '
          'Raw output: ${jsonEncode(rawOutput.toString())}',
        ),
      );
    } else if (ready()) {
      completed.complete();
    }
  }

  final terminal = session.terminal;
  session.addListener(changed);
  terminal.addListener(changed);
  try {
    changed();
    await completed.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException(
        'ConPTY did not reach $phase. '
        'Raw output: ${jsonEncode(rawOutput.toString())}',
        const Duration(seconds: 10),
      ),
    );
  } finally {
    session.removeListener(changed);
    terminal.removeListener(changed);
  }
}

/// Observes raw diagnostics while preserving the production transport/lifecycle.
class _RecordingConnection implements TerminalConnection {
  _RecordingConnection(this._connection, StringBuffer rawOutput)
    : output = _connection.output.map((data) {
        rawOutput.write(data);
        return data;
      });

  final TerminalConnection _connection;
  @override
  final Stream<String> output;
  @override
  Future<int?> get exitCode => _connection.exitCode;
  @override
  Future<void> write(String data) => _connection.write(data);
  @override
  Future<void> resize(int columns, int rows) =>
      _connection.resize(columns, rows);
  @override
  Future<void> close() => _connection.close();
}

/// A single subscription that lets tests synchronize with the child instead of
/// sleeping or guessing when the PTY has delivered a prompt.
class _OutputCapture {
  _OutputCapture(Stream<String> stream) : _iterator = StreamIterator(stream);

  final StreamIterator<String> _iterator;
  final StringBuffer _output = StringBuffer();

  Future<void> waitFor(String marker) =>
      _readUntil(marker).timeout(const Duration(seconds: 10));

  Future<void> _readUntil(String marker) async {
    while (!_output.toString().contains(marker)) {
      if (!await _iterator.moveNext()) {
        throw StateError('PTY closed before $marker: $_output');
      }
      _output.write(_iterator.current);
    }
  }

  Future<String> readToEnd() async {
    while (await _iterator.moveNext()) {
      _output.write(_iterator.current);
    }
    return _output.toString();
  }

  Future<void> cancel() => _iterator.cancel();
}
