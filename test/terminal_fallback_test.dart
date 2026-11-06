import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/terminal_backends.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a denied PTY falls back to the built-in sandbox shell', () async {
    final connection = await openLocalTerminal(
      '/tmp',
      80,
      24,
      startHostShell: (directory, {columns = 80, rows = 24}) async {
        throw ProcessException(
          '/bin/zsh',
          const <String>['-l'],
          'setting PTY terminal attributes failed: Operation not permitted',
          1,
        );
      },
    );
    expect(connection.isSandbox, isTrue);

    final output = StringBuffer();
    final done = Completer<void>();
    connection.output.listen(output.write, onDone: done.complete);
    await connection.write('echo sandbox-fallback\r');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(output.toString(), contains('sandbox-fallback'));
    expect(output.toString(), contains('built-in shell'));

    await connection.write('exit\r');
    await done.future.timeout(const Duration(seconds: 2));
    expect(await connection.exitCode, 0);
  });
}
