@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/widgets/terminal_process_native.dart';
import 'package:crisp_cloud/widgets/terminal_process_stub.dart' as web_stub;
import 'package:flutter_test/flutter_test.dart';

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
      final shell = (await startShell('${directory.path}/removed-directory'))!;
      addTearDown(shell.dispose);
      final output = shell.outputStream.join();

      await shell.write('echo CrispCloud ConPTY\rexit 7\r');

      expect(await shell.exitCode.timeout(const Duration(seconds: 10)), 7);
      expect(await output, contains('CrispCloud ConPTY'));
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
