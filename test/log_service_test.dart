import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/log_service.dart';

void main() {
  setUp(() {
    LogConfig.clear();
    LogConfig.minLevel = LogLevel.trace; // capture everything in tests
    LogConfig.maxBufferSize = 1000;
  });

  group('Log', () {
    test('captures info messages in buffer', () {
      final log = Log('TestLogger');
      log.info('hello world');

      expect(LogConfig.entries.length, 1);
      expect(LogConfig.entries.first.level, LogLevel.info);
      expect(LogConfig.entries.first.logger, 'TestLogger');
      expect(LogConfig.entries.first.message, 'hello world');
    });

    test('captures all log levels', () {
      final log = Log('Test');
      log.trace('t');
      log.debug('d');
      log.info('i');
      log.warn('w');
      log.error('e');

      expect(LogConfig.entries.length, 5);
      expect(LogConfig.entries.map((e) => e.level).toList(), [
        LogLevel.trace,
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warn,
        LogLevel.error,
      ]);
    });

    test('respects minLevel filter', () {
      LogConfig.minLevel = LogLevel.warn;
      final log = Log('Test');

      log.trace('should be dropped');
      log.debug('should be dropped');
      log.info('should be dropped');
      log.warn('should appear');
      log.error('should appear');

      expect(LogConfig.entries.length, 2);
      expect(LogConfig.entries[0].level, LogLevel.warn);
      expect(LogConfig.entries[1].level, LogLevel.error);
    });

    test('captures data map', () {
      final log = Log('Test');
      log.info('with data', {'key': 'value', 'count': 42});

      expect(LogConfig.entries.first.data, {'key': 'value', 'count': 42});
    });

    test('captures error and stack trace', () {
      final log = Log('Test');
      final error = Exception('boom');
      final stack = StackTrace.current;
      log.error('failed', error, stack);

      final entry = LogConfig.entries.first;
      expect(entry.error, error);
      expect(entry.stackTrace, stack);
    });

    test('ring buffer evicts oldest entries', () {
      LogConfig.maxBufferSize = 3;
      final log = Log('Test');

      log.info('1');
      log.info('2');
      log.info('3');
      log.info('4');

      expect(LogConfig.entries.length, 3);
      expect(LogConfig.entries.first.message, '2');
      expect(LogConfig.entries.last.message, '4');
    });

    test('disabled buffer (maxBufferSize=0) captures nothing', () {
      LogConfig.maxBufferSize = 0;
      final log = Log('Test');
      log.info('test');

      expect(LogConfig.entries.length, 0);
    });

    test('clear empties the buffer', () {
      final log = Log('Test');
      log.info('a');
      log.info('b');
      expect(LogConfig.entries.length, 2);

      LogConfig.clear();
      expect(LogConfig.entries.length, 0);
    });
  });

  group('LogEntry', () {
    test('toString includes logger and message', () {
      final entry = LogEntry(
        timestamp: DateTime(2026, 5, 29),
        level: LogLevel.info,
        logger: 'MyClass',
        message: 'something happened',
      );

      final str = entry.toString();
      expect(str, contains('MyClass'));
      expect(str, contains('something happened'));
    });

    test('toString includes data', () {
      final entry = LogEntry(
        timestamp: DateTime(2026, 5, 29),
        level: LogLevel.debug,
        logger: 'X',
        message: 'msg',
        data: {'foo': 'bar'},
      );

      expect(entry.toString(), contains('{foo: bar}'));
    });

    test('toString includes error', () {
      final entry = LogEntry(
        timestamp: DateTime(2026, 5, 29),
        level: LogLevel.error,
        logger: 'X',
        message: 'fail',
        error: Exception('kaboom'),
      );

      expect(entry.toString(), contains('kaboom'));
    });
  });

  group('LogConfig.export', () {
    test('produces readable export', () {
      final log = Log('Export');
      log.info('entry one');
      log.error('entry two', Exception('oops'));

      final output = LogConfig.export();
      expect(output, contains('CrispCloud Log Export'));
      expect(output, contains('entry one'));
      expect(output, contains('entry two'));
      expect(output, contains('oops'));
      expect(output, contains('Entries: 2'));
    });

    test('export is empty when buffer is empty', () {
      final output = LogConfig.export();
      expect(output, contains('Entries: 0'));
    });
  });
}
