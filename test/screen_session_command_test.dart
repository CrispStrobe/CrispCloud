@TestOn('vm')
library;

import 'dart:io';

import 'package:crisp_cloud/models/screen_session_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('POSIX Screen command resolution', () {
    late Directory directory;
    late File listing;
    late File arguments;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('crisp-screen-test-');
      listing = File('${directory.path}/listing');
      arguments = File('${directory.path}/arguments');
      final executable = File('${directory.path}/screen');
      await executable.writeAsString(r'''#!/bin/sh
if [ "$1" = '-ls' ]; then
  cat "$CRISP_SCREEN_LISTING"
  exit "${CRISP_SCREEN_LIST_STATUS:-0}"
fi
printf '%s\n' "$@" > "$CRISP_SCREEN_ARGUMENTS"
exit "${CRISP_SCREEN_ATTACH_STATUS:-0}"
''');
      final chmod = await Process.run('chmod', ['700', executable.path]);
      expect(chmod.exitCode, 0);
    });

    tearDown(() async => directory.delete(recursive: true));

    Future<ProcessResult> run(
      String target,
      String output, {
      ScreenSessionMode mode = ScreenSessionMode.attach,
      int listStatus = 0,
      int attachStatus = 0,
    }) async {
      await listing.writeAsString(output);
      return Process.run(
        '/bin/sh',
        ['-c', ScreenSessionOptions(sessionName: target, mode: mode).command],
        environment: {
          'PATH': '${directory.path}:${Platform.environment['PATH']}',
          'CRISP_SCREEN_LISTING': listing.path,
          'CRISP_SCREEN_ARGUMENTS': arguments.path,
          'CRISP_SCREEN_LIST_STATUS': '$listStatus',
          'CRISP_SCREEN_ATTACH_STATUS': '$attachStatus',
        },
      ).timeout(const Duration(seconds: 5));
    }

    String sessions(List<String> rows) =>
        'There are screens on:\n${rows.map((row) => '\t$row').join('\n')}\n'
        '${rows.length} Sockets in /run/screen/S-alice.\n';

    test(
      'creates a new named session even inside an inherited Screen',
      () async {
        final result = await run('work', '', mode: ScreenSessionMode.create);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(await arguments.readAsLines(), ['-m', '-S', 'work']);
      },
    );

    test(
      'exact names cannot select longer names or a different prefix',
      () async {
        final result = await run(
          'work',
          sessions([
            '123.work\t(Detached)',
            '456.worker\t(Detached)',
            '789.prework\t(Detached)',
          ]),
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(await arguments.readAsLines(), ['-x', '123.work']);
      },
    );

    test(
      'missing exact names do not attach prefixes or create sessions',
      () async {
        final result = await run('work', sessions(['456.worker\t(Detached)']));
        expect(result.exitCode, 44);
        expect(await arguments.exists(), isFalse);
      },
    );

    test('numeric names use string equality', () async {
      final result = await run('1', sessions(['456.01\t(Detached)']));
      expect(result.exitCode, 44);
      expect(await arguments.exists(), isFalse);
    });

    test('duplicate exact names require a full ID', () async {
      final result = await run(
        'work',
        sessions(['123.work\t(Detached)', '456.work\t(Attached)']),
      );
      expect(result.exitCode, 45);
      expect(await arguments.exists(), isFalse);
    });

    test(
      'full IDs distinguish duplicate names and preserve other displays',
      () async {
        final result = await run(
          '456.work',
          sessions(['123.work\t(Detached)', '456.work\t(Attached)']),
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(await arguments.readAsLines(), ['-x', '456.work']);
      },
    );

    test(
      'missing full IDs do not fall back to a session with that name',
      () async {
        final result = await run(
          '123.work',
          sessions(['456.123.work\t(Detached)']),
        );
        expect(result.exitCode, 44);
        expect(await arguments.exists(), isFalse);
      },
    );

    test('rejects alternate candidates for Screen prefix fallback', () async {
      for (final other in ['456.123.work', '456.123.worker', '123.worker']) {
        final result = await run(
          '123.work',
          sessions(['123.work\t(Detached)', '$other\t(Detached)']),
        );
        expect(result.exitCode, 47, reason: other);
        expect(await arguments.exists(), isFalse);
      }
    });

    test(
      'unavailable exact matches are not replaced by live prefix matches',
      () async {
        final result = await run(
          'work',
          sessions(['123.work\t(Dead ???)', '456.worker\t(Detached)']),
        );
        expect(result.exitCode, 46);
        expect(await arguments.exists(), isFalse);
      },
    );

    test('a failed or incomplete listing cannot trigger an attach', () async {
      final output = sessions(['123.work\t(Detached)']);
      final failed = await run('work', output, listStatus: 1);
      expect(failed.exitCode, 48);
      expect(await arguments.exists(), isFalse);
      final incomplete = await run('work', '\t123.work\t(Detached)\n');
      expect(incomplete.exitCode, 48);
      expect(await arguments.exists(), isFalse);
    });

    test('oversized listings fail closed', () async {
      for (final output in [
        '${'x' * 1025}\n',
        '${'\n' * 4097}',
        List.filled(300, '${'x' * 1000}\n').join(),
      ]) {
        final result = await run('work', output);
        expect(result.exitCode, 75);
        expect(await arguments.exists(), isFalse);
      }
    });

    test(
      'attach failure is returned without shell or creation fallback',
      () async {
        final result = await run(
          'work',
          sessions(['123.work\t(Detached)']),
          attachStatus: 17,
        );
        expect(result.exitCode, 17);
        expect(await arguments.readAsLines(), ['-x', '123.work']);
      },
    );
  }, skip: !Platform.isLinux && !Platform.isMacOS);
}
