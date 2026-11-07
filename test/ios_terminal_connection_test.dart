import 'dart:async';

import 'package:crisp_cloud/services/ios_terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_backends.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_ios_shell/crisp_ios_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session extends Fake implements IosShellSession {
  final controller = StreamController<String>();
  final ended = Completer<int>();
  final writes = <String>[];
  final sizes = <(int, int)>[];
  int closes = 0;
  @override
  Stream<String> get output => controller.stream;
  @override
  Future<int> get exitCode => ended.future;
  @override
  Future<void> write(String data) async => writes.add(data);
  @override
  Future<void> resize(int columns, int rows) async =>
      sizes.add((columns, rows));
  @override
  Future<void> close() async {
    closes++;
    if (!ended.isCompleted) ended.complete(0);
    unawaited(controller.close());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'starts Dash in the captured directory with bounded dimensions',
    () async {
      final native = _Session();
      final connection = await IosTerminalConnection.open(
        '/Documents/work with spaces',
        10000,
        0,
        start: ({required workingDirectory, columns = 80, rows = 24}) async {
          expect(workingDirectory, '/Documents/work with spaces');
          expect((columns, rows), (9999, 1));
          return native;
        },
      );
      expect(connection.terminalBackend, TerminalBackend.ios);
      expect(connection.isSandbox, isFalse);
      await connection.close();
    },
  );

  test('preserves terminal output, input, exit status and resize', () async {
    final native = _Session();
    final connection = IosTerminalConnection(native);
    final output = connection.output.toList();
    native.controller.add('\x1b[32mGrüße 中\x1b[0m\r\n');
    await connection.write('printf "x" | cat\r\x03');
    await connection.resize(120, 38);
    await connection.resize(-1, 10000);
    expect(native.writes, ['printf "x" | cat\r\x03']);
    expect(native.sizes, [(120, 38), (1, 9999)]);
    native.ended.complete(7);
    await native.controller.close();
    expect(await output, ['\x1b[32mGrüße 中\x1b[0m\r\n']);
    expect(await connection.exitCode, 7);
    await connection.close();
  });

  test('close is idempotent and stops late layout/input', () async {
    final native = _Session();
    final connection = IosTerminalConnection(native);
    final first = connection.close();
    expect(connection.close(), same(first));
    await first;
    await connection.write('late');
    await connection.resize(90, 30);
    expect(native.closes, 1);
    expect(native.writes, isEmpty);
    expect(native.sizes, isEmpty);
  });

  test(
    'iOS routing uses the embedded engine and never starts a host process',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final native = _Session();
      final expected = IosTerminalConnection(native);
      final connection = await openLocalTerminal(
        '/Documents',
        100,
        30,
        startHostShell: (_, {columns = 80, rows = 24}) async =>
            throw StateError('host process'),
        startIosShell: (path, columns, rows) async {
          expect((path, columns, rows), ('/Documents', 100, 30));
          return expected;
        },
      );
      expect(connection, same(expected));
      await connection.close();
    },
  );

  test(
    'iOS startup failures remain visible without switching interpreters',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final error = PlatformException(code: 'session_busy');
      await expectLater(
        openLocalTerminal(
          '/Documents',
          80,
          24,
          startIosShell: (_, _, _) async => throw error,
        ),
        throwsA(same(error)),
      );
      await expectLater(
        IosTerminalConnection.open(
          '/Documents',
          80,
          24,
          start: ({required workingDirectory, columns = 80, rows = 24}) async =>
              throw error,
        ),
        throwsA(same(error)),
      );
    },
  );
}
