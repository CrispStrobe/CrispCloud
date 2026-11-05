import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/custom_toolbar_command_service.dart';

const local = StorageReference(
  kind: 'local',
  provider: 'local',
  accountKey: 'fixture',
);
CommandInvocationContext selection(
  List<String> paths, {
  bool Function()? current,
  StorageReference storage = local,
  String? target,
  bool Function()? targetCurrent,
}) => CommandInvocationContext(
  storage: storage,
  currentPath: '/work',
  selectedPaths: paths,
  isCurrent: current ?? () => true,
  targetPath: target,
  targetIsCurrent: targetCurrent,
);
CustomToolbarCommand command(List<String> args, {int seconds = 300}) =>
    CustomToolbarCommand(
      id: 'cmd',
      label: 'Tool',
      executable: '/tool',
      arguments: args,
      timeoutSeconds: seconds,
    );

class _Process extends Fake implements Process {
  final out = StreamController<List<int>>();
  final err = StreamController<List<int>>();
  final exit = Completer<int>();
  final signals = <ProcessSignal>[];
  bool ignoreKill = false;
  @override
  Stream<List<int>> get stdout => out.stream;
  @override
  Stream<List<int>> get stderr => err.stream;
  @override
  Future<int> get exitCode => exit.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    if (!ignoreKill && !exit.isCompleted) finish(143);
    return true;
  }

  void finish(int code) {
    out.close();
    err.close();
    if (!exit.isCompleted) exit.complete(code);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'selected names are separate literal arguments and never expanded twice',
    () {
      final paths = [
        '/work/space name',
        '/work/";touch x;\$(id)',
        '/work/{TARGET}',
      ];
      final invocation = prepareToolbarCommand(
        command(['--', '{SELECTED}']),
        selection(paths),
      );
      expect(invocation.executable, '/tool');
      expect(invocation.arguments, ['--', ...paths]);
      expect(invocation.workingDirectory, '/work');
      expect(() => invocation.arguments.add('x'), throwsUnsupportedError);
    },
  );
  test('single item and target placeholders use the captured source', () {
    final invocation = prepareToolbarCommand(
      command([
        '{FILE}',
        '{NAME}',
        '{BASENAME}',
        '{EXT}',
        '{CURRENT}',
        '--destination={TARGET}',
      ]),
      selection(
        ['/work/café.tar.gz'],
        target: '/other',
        targetCurrent: () => true,
      ),
    );
    expect(invocation.arguments, [
      '/work/café.tar.gz',
      'café.tar.gz',
      'café.tar',
      'gz',
      '/work',
      '--destination=/other',
    ]);
  });
  test('missing selection, multiple single-file rows and stale target are rejected', () {
    expect(
      () => prepareToolbarCommand(command(['{SELECTED}']), selection([])),
      throwsStateError,
    );
    expect(
      () => prepareToolbarCommand(command(['{FILE}']), selection(['/a', '/b'])),
      throwsStateError,
    );
    expect(
      () => prepareToolbarCommand(
        command(['{TARGET}']),
        selection([], target: '/b', targetCurrent: () => false),
      ),
      throwsStateError,
    );
  });
  test('remote and stale local origins cannot reach process launch', () async {
    var launches = 0;
    final service = CustomToolbarCommandService(
      processStarter: (_, _, _) async {
        launches++;
        return _Process();
      },
    );
    await expectLater(
      service.start(command([]), selection([], current: () => false)),
      throwsStateError,
    );
    await expectLater(
      service.start(
        command([]),
        selection(
          [],
          storage: const StorageReference(
            kind: 'remote',
            provider: 'cloud',
            accountKey: 'fixture',
          ),
        ),
      ),
      throwsStateError,
    );
    expect(launches, 0);
  });
  test(
    'legacy shell definitions survive persistence but require review to run',
    () async {
      SharedPreferences.setMockInitialValues({
        'custom_toolbar_commands_v1': jsonEncode([
          {'id': 'legacy', 'label': 'Old', 'command': 'echo {SELECTED} | sort'},
        ]),
      });
      final service = CustomToolbarCommandService();
      await service.load();
      expect(service.commands.single.command, 'echo {SELECTED} | sort');
      expect(service.commands.single.requiresReview, isTrue);
      expect(
        () => service.prepare(service.commands.single, selection(['/a'])),
        throwsFormatException,
      );
      await service.updateCommand(
        const CustomToolbarCommand(
          id: 'legacy',
          label: 'New',
          executable: '/tool',
          arguments: ['{SELECTED}'],
        ),
      );
      final restored = CustomToolbarCommandService();
      await restored.load();
      expect(restored.commands.single.executable, '/tool');
      expect(restored.commands.single.requiresReview, isFalse);
    },
  );
  test(
    'configuration rejects embedded list expansion and unknown placeholders',
    () {
      expect(() => command(['x={SELECTED}']).validate(), throwsFormatException);
      expect(() => command(['{UNKNOWN}']).validate(), throwsFormatException);
    },
  );
  test('concurrent load and edits preserve every saved command', () async {
    final service = CustomToolbarCommandService();
    await Future.wait([
      service.load(),
      service.addCommand(command([])),
      service.addCommand(
        const CustomToolbarCommand(
          id: 'other',
          label: 'Other',
          executable: '/other',
        ),
      ),
    ]);
    final restored = CustomToolbarCommandService();
    await restored.load();
    expect(restored.commands.map((c) => c.id), ['cmd', 'other']);
    await expectLater(service.addCommand(command([])), throwsStateError);
  });
  test(
    'runner passes argv unchanged and captures bounded Unicode output',
    () async {
      final process = _Process();
      final service = CustomToolbarCommandService(
        processStarter: (executable, args, directory) async {
          expect(executable, '/tool');
          expect(args, ['/work/a " \$(id)']);
          expect(directory, '/work');
          return process;
        },
      );
      final run = await service.start(
        command(['{SELECTED}']),
        selection(['/work/a " \$(id)']),
        maxOutputBytes: 8,
      );
      addTearDown(run.dispose);
      process.out.add([0xc3]);
      process.out.add([0xa9, 97, 98, 99, 100, 101, 102, 103]);
      process.finish(7);
      final result = await run.completed;
      expect(result.exitCode, 7);
      expect(result.output, startsWith('éabcdef'));
      expect(result.truncated, isTrue);
      expect(result.output.length, lessThan(50));
    },
  );
  test(
    'cancel stops its owned process and records a cancelled outcome',
    () async {
      final process = _Process();
      final service = CustomToolbarCommandService(
        processStarter: (_, _, _) async => process,
      );
      final run = await service.start(command([]), selection([]));
      addTearDown(run.dispose);
      run.cancel();
      final result = await run.completed;
      expect(result.cancelled, isTrue);
      expect(process.signals, [ProcessSignal.sigterm]);
    },
  );
  test('timeout stops a command without unbounded waiting', () async {
    final process = _Process();
    final service = CustomToolbarCommandService(
      processStarter: (_, _, _) async => process,
    );
    final run = await service.start(command([], seconds: 1), selection([]));
    addTearDown(run.dispose);
    final result = await run.completed;
    expect(result.timedOut, isTrue);
    expect(result.cancelled, isTrue);
  });
  test(
    'uncooperative command and inherited pipes cannot block cancellation',
    () async {
      final process = _Process()..ignoreKill = true;
      final service = CustomToolbarCommandService(
        processStarter: (_, _, _) async => process,
      );
      final run = await service.start(command([]), selection([]));
      addTearDown(run.dispose);
      run.cancel();
      final result = await run.completed;
      expect(result.cancelled, isTrue);
      expect(result.exitCode, -1);
      expect(process.signals, [ProcessSignal.sigterm, ProcessSignal.sigkill]);
      process.finish(137);
    },
  );
}
