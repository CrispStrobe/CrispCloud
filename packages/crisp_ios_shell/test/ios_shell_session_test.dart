import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:crisp_ios_shell/crisp_ios_shell.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class ReadFailure {
  ReadFailure(this.error);
  final Object error;
}

class NativeShellDouble {
  NativeShellDouble(this.channel);
  final MethodChannel channel;
  final List<MethodCall> calls = [];
  final Queue<Object?> _reads = Queue<Object?>();
  Completer<Object?>? _pendingRead;
  Completer<void>? closeGate;
  Completer<void>? writeGate;
  bool finishWriteOnClose = false;
  int closeFailures = 0;
  int closeCalls = 0;
  int readCalls = 0;
  Object? startReply = <String, Object?>{'sessionId': 'native-session'};
  Object? startError;
  bool _exited = false;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'start':
        if (startError case final Object error) throw error;
        return startReply;
      case 'read':
        readCalls++;
        Object? reply;
        if (_reads.isNotEmpty) {
          reply = _reads.removeFirst();
        } else {
          if (_pendingRead != null) throw StateError('Concurrent read');
          _pendingRead = Completer<Object?>();
          reply = await _pendingRead!.future;
        }
        if (reply is ReadFailure) throw reply.error;
        return reply;
      case 'close':
        closeCalls++;
        if (closeFailures > 0) {
          closeFailures--;
          throw PlatformException(
            code: 'channel_lost',
            message: 'Close did not receive acknowledgement',
          );
        }
        if (finishWriteOnClose && writeGate != null && !writeGate!.isCompleted) {
          writeGate!.complete();
        }
        await closeGate?.future;
        if (!_exited) emit([], exitCode: 130);
        return true;
      case 'write':
        await writeGate?.future;
        return true;
      case 'resize':
      case 'interrupt':
      case 'eof':
        return true;
      default:
        throw MissingPluginException(call.method);
    }
  }

  void push(Object? reply) {
    final pending = _pendingRead;
    if (pending != null) {
      _pendingRead = null;
      pending.complete(reply);
    } else {
      _reads.add(reply);
    }
  }

  void emit(List<int> data, {int? exitCode}) {
    if (exitCode != null) _exited = true;
    push(<String, Object?>{
      'data': Uint8List.fromList(data),
      if (exitCode != null) 'exitCode': exitCode,
    });
  }

  List<String> get writes => calls
      .where((call) => call.method == 'write')
      .map((call) => utf8.decode((call.arguments as Map)['data'] as Uint8List))
      .toList();
}

Future<void> turn() => Future<void>.delayed(Duration.zero);
Future<void> turns([int count = 4]) async {
  for (var index = 0; index < count; index++) {
    await turn();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('crisp_ios_shell/test');
  late NativeShellDouble native;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    native = NativeShellDouble(channel);
    messenger.setMockMethodCallHandler(channel, native.handle);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });
  Future<IosShellSession> start() => IosShellSession.start(
    workingDirectory: '/Documents/space Ω',
    columns: 80,
    rows: 24,
    channel: channel,
  );

  test(
    'start passes exact directory and dimensions without shell quoting',
    () async {
      final session = await start();
      expect(native.calls.single.arguments, {
        'workingDirectory': '/Documents/space Ω',
        'columns': 80,
        'rows': 24,
      });
      await session.close();
      expect(await session.exitCode, 130);
    },
  );

  test(
    'validates directories and dimensions before using native channel',
    () async {
      for (final directory in ['relative', '', '/bad\x00path']) {
        await expectLater(
          IosShellSession.start(workingDirectory: directory, channel: channel),
          throwsArgumentError,
        );
      }
      for (final size in [0, -1, 10000]) {
        await expectLater(
          IosShellSession.start(
            workingDirectory: '/ok',
            columns: size,
            channel: channel,
          ),
          throwsArgumentError,
        );
        await expectLater(
          IosShellSession.start(
            workingDirectory: '/ok',
            rows: size,
            channel: channel,
          ),
          throwsArgumentError,
        );
      }
      expect(native.calls, isEmpty);
    },
  );

  test(
    'start propagates native failure and rejects an invalid session identifier',
    () async {
      native.startError = PlatformException(code: 'session_busy');
      await expectLater(
        start(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'session_busy',
          ),
        ),
      );
      native.startError = null;
      for (final reply in [
        null,
        <String, Object?>{},
        {'sessionId': ''},
        {'sessionId': 7},
      ]) {
        native.startReply = reply;
        await expectLater(start(), throwsFormatException);
      }
    },
  );

  test(
    'buffers native output until subscribed and drains before exit',
    () async {
      final session = await start();
      native.emit(utf8.encode('hello\n'));
      native.emit(utf8.encode('tail'), exitCode: 7);
      await turns();
      expect(native.readCalls, 0);
      final output = await session.output.toList();
      expect(output.join(), 'hello\r\ntail');
      expect(await session.exitCode, 7);
      await session.close();
      expect(native.closeCalls, 0);
    },
  );

  test(
    'decodes split UTF8, tolerates binary bytes and flushes an incomplete tail',
    () async {
      final session = await start();
      final output = session.output.toList();
      for (final byte in utf8.encode('Ω漢字😀')) {
        native.emit([byte]);
      }
      native.emit([0xff, 0xe2]);
      native.emit([0x82], exitCode: 0);
      expect((await output).join(), 'Ω漢字😀\uFFFD\uFFFD');
      expect(await session.exitCode, 0);
      expect(native.closeCalls, 0);
    },
  );

  test(
    'normalizes LF across packet boundaries without duplicating CR',
    () async {
      final session = await start();
      final output = session.output.toList();
      native.emit(utf8.encode('a\r'));
      native.emit(utf8.encode('\nb\nc\r'));
      native.emit(utf8.encode('\nd'), exitCode: 0);
      expect((await output).join(), 'a\r\nb\r\nc\r\nd');
    },
  );

  test(
    'pauses native pulls and resumes without losing the pending read',
    () async {
      final session = await start();
      final output = <String>[];
      final subscription = session.output.listen(output.add);
      await turns();
      expect(native.readCalls, 1);
      subscription.pause();
      native.emit(utf8.encode('one'));
      await turns();
      expect(native.readCalls, 1);
      expect(output, isEmpty);
      subscription.resume();
      await turns();
      expect(output, ['one']);
      expect(native.readCalls, 2);
      native.emit(utf8.encode('two'), exitCode: 0);
      await session.exitCode;
      await turns();
      expect(output.join(), 'onetwo');
    },
  );

  test(
    'writes canonical command bytes and supports multiline pasted input',
    () async {
      final session = await start();
      final output = <String>[];
      session.output.listen(output.add);
      await session.write('ec');
      expect(native.writes, isEmpty);
      await session.write('ho Ω\r');
      await session.write("read value\nhello\nprintf '%s\\n' \"\$value\"\n");
      expect(native.writes, [
        'echo Ω\n',
        'read value\n',
        'hello\n',
        "printf '%s\\n' \"\$value\"\n",
      ]);
      await turns();
      final visible = output.join().replaceAll(
        RegExp(r'\x1b\[[0-9;]*[A-Za-z]'),
        '',
      );
      expect(visible, contains('echo Ω\r\n'));
      await session.close();
    },
  );

  test(
    'raw Ctrl-C/D keys and explicit control methods reach the native engine',
    () async {
      final session = await start();
      session.output.listen((_) {});
      await session.write('discard\x03');
      await session.write('\x04');
      await session.interrupt();
      await session.sendEof();
      expect(native.writes, isEmpty);
      expect(
        native.calls.where((call) => call.method == 'interrupt'),
        hasLength(2),
      );
      expect(native.calls.where((call) => call.method == 'eof'), hasLength(2));
      await session.close();
    },
  );

  test(
    'writes are serialized but close bypasses a blocked input writer',
    () async {
      final session = await start();
      session.output.listen((_) {});
      native.writeGate = Completer<void>();
      final first = session.write('first\n');
      final second = session.write('second\n');
      await turns();
      expect(native.writes, ['first\n']);
      native.finishWriteOnClose = true;
      await session.close().timeout(const Duration(seconds: 2));
      await Future.wait([first, second]);
      expect(native.closeCalls, 1);
      expect(native.writes, ['first\n']);
      expect(await session.exitCode, 130);
    },
  );

  test(
    'resize validates bounds, forwards valid values and is harmless after exit',
    () async {
      final session = await start();
      await session.resize(9999, 1);
      expect(native.calls.last.arguments, {
        'sessionId': 'native-session',
        'columns': 9999,
        'rows': 1,
      });
      for (final size in [0, -2, 10000]) {
        await expectLater(session.resize(size, 24), throwsArgumentError);
        await expectLater(session.resize(80, size), throwsArgumentError);
      }
      await session.close();
      final count = native.calls.length;
      await session.resize(80, 24);
      await session.write('ignored\n');
      await session.interrupt();
      await session.sendEof();
      expect(native.calls, hasLength(count));
    },
  );

  test('close is idempotent and finishes without an output listener', () async {
    final session = await start();
    native.closeGate = Completer<void>();
    native.emit(utf8.encode('unconsumed'));
    final first = session.close();
    final second = session.close();
    expect(identical(first, second), isTrue);
    await turns();
    expect(native.closeCalls, 1);
    native.closeGate!.complete();
    await first.timeout(const Duration(seconds: 2));
    expect(await session.exitCode, 130);
    await session.close();
    expect(native.closeCalls, 1);
  });

  test('close completes while output is paused', () async {
    final session = await start();
    final subscription = session.output.listen((_) {});
    subscription.pause();
    native.emit(utf8.encode('paused data'));
    await turns();
    await session.close().timeout(const Duration(seconds: 2));
    expect(await session.exitCode, 130);
    await subscription.cancel();
  });

  test(
    'cancelling output cancels native work and releases exit waiters',
    () async {
      final session = await start();
      final subscription = session.output.listen((_) {});
      await subscription.cancel().timeout(const Duration(seconds: 2));
      expect(native.closeCalls, 1);
      expect(await session.exitCode, 130);
    },
  );

  test(
    'a failed read retains the native lease until cleanup is acknowledged',
    () async {
      final session = await start();
      native.closeGate = Completer<void>();
      final errors = <Object>[];
      session.output.listen((_) {}, onError: errors.add);
      var exited = false;
      final checkedExit = expectLater(
        session.exitCode,
        throwsFormatException,
      ).then((_) => exited = true);
      native.push({'data': 'invalid-native-bytes'});
      await turns();
      expect(native.closeCalls, 1);
      expect(exited, isFalse);
      expect(errors, isEmpty);
      native.closeGate!.complete();
      await checkedExit;
      await turns();
      expect(errors.single, isA<FormatException>());
      expect(native.closeCalls, 1);
      await session.close();
    },
  );

  test(
    'read errors have an early exit observer and preserve the original failure',
    () async {
      final session = await start();
      final errors = <Object>[];
      session.output.listen((_) {}, onError: errors.add);
      native.push(ReadFailure(PlatformException(code: 'native_read_failed')));
      await turns();
      // Observe exit late: the test would fail on an unhandled async error if the
      // constructor had not attached its independent observer.
      await expectLater(
        session.exitCode,
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'native_read_failed',
          ),
        ),
      );
      expect(errors.single, isA<PlatformException>());
      expect(native.closeCalls, 1);
    },
  );

  test(
    'failed cleanup keeps exit pending and can be retried without losing the original read error',
    () async {
      final session = await start();
      native.closeFailures = 1;
      final errors = <Object>[];
      session.output.listen((_) {}, onError: errors.add);
      var exited = false;
      final checkedExit = expectLater(
        session.exitCode,
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'original_read_error',
          ),
        ),
      ).then((_) => exited = true);
      native.push(ReadFailure(PlatformException(code: 'original_read_error')));
      await turns();
      expect(native.closeCalls, 1);
      expect(exited, isFalse);
      expect(errors, hasLength(1));
      await session.close();
      await checkedExit;
      expect(native.closeCalls, 2);
      expect(errors, hasLength(1));
    },
  );

  test(
    'explicit close rejects an unacknowledged cleanup and retries later',
    () async {
      final session = await start();
      native.closeFailures = 1;
      var exited = false;
      unawaited(session.exitCode.then((_) => exited = true));
      await expectLater(
        session.close(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'cleanup_unconfirmed',
          ),
        ),
      );
      await turns();
      expect(exited, isFalse);
      await session.close();
      expect(await session.exitCode, 130);
      expect(native.closeCalls, 2);
    },
  );

  test(
    'concurrent read failure and explicit close share one cleanup request',
    () async {
      final session = await start();
      native.closeGate = Completer<void>();
      session.output.listen((_) {}, onError: (Object _) {});
      final checkedExit = expectLater(session.exitCode, throwsFormatException);
      native.push({'data': Uint8List(0), 'exitCode': 'invalid'});
      await turns();
      final closing = session.close();
      await turns();
      expect(native.closeCalls, 1);
      native.closeGate!.complete();
      await closing;
      await checkedExit;
      expect(native.closeCalls, 1);
    },
  );

  test('null read response fails explicitly after native cleanup', () async {
    final session = await start();
    session.output.listen((_) {}, onError: (Object _) {});
    native.push(null);
    await expectLater(session.exitCode, throwsFormatException);
    expect(native.closeCalls, 1);
  });
}
