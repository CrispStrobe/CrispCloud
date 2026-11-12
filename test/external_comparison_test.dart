import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/l10n/external_comparison_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/command_entry_service.dart';
import 'package:crisp_cloud/services/external_comparison_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/private_tool_staging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/external_comparison_fixture.dart';
import 'support/gathering_stack_fixture.dart';

Matcher failure(ExternalComparisonFailure value) =>
    isA<ExternalComparisonException>().having(
      (error) => error.failure,
      'failure',
      value,
    );

void main() {
  late ComparisonHost host;
  late ComparisonMemoryStages stages;
  late ComparisonBackend left, right;
  late ExternalComparisonService service;
  final services = <ExternalComparisonService>[];
  ExternalComparisonService createService({
    int maxBytes = 256 * 1024 * 1024,
    Duration timeout = const Duration(minutes: 15),
    PrivateToolStagingStore? staging,
  }) {
    final result = ExternalComparisonService(
      host: host,
      staging: staging ?? stages,
      maxInputBytes: maxBytes,
      preparationTimeout: timeout,
    );
    services.add(result);
    return result;
  }

  void disposeService(ExternalComparisonService value) {
    services.remove(value);
    value.dispose();
  }

  Future<PreparedExternalComparison> prepare({
    ExternalComparisonPair? pair,
    FileOperationControl? control,
    ExternalComparisonConfiguration? configuration,
    bool Function()? current,
  }) => service.prepare(
    configuration ?? comparisonConfiguration(),
    pair ?? comparisonPair(left, right),
    control: control ?? FileOperationControl(),
    isCurrent: current ?? () => true,
  );
  Future<void> launch(
    PreparedExternalComparison prepared, {
    FileOperationControl? control,
    bool Function()? current,
  }) => service.launch(
    prepared,
    control: control ?? FileOperationControl(),
    isReviewCurrent: current ?? () => true,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = ComparisonHost();
    stages = ComparisonMemoryStages();
    left = ComparisonBackend(gatheringAccountA)
      ..file(
        '/same/name.txt',
        'first account',
        objectId: 'object-a',
        version: 'a1',
      );
    right = ComparisonBackend(gatheringAccountB)
      ..file(
        '/same/name.txt',
        'second account',
        objectId: 'object-b',
        version: 'b1',
      );
    service = createService();
    await service.ready;
  });
  tearDown(() {
    for (final value in services) {
      value.dispose();
    }
    services.clear();
  });

  test('same names and paths retain both actual accounts and distinct private copies', () async {
    final prepared = await prepare();
    final stage = stages.entries[prepared.session.id]!;
    expect(utf8.decode(stage.files['left.txt']!), 'first account');
    expect(utf8.decode(stage.files['right.txt']!), 'second account');
    expect(prepared.left.path, isNot(prepared.right.path));
    expect(prepared.session.sourceLabel('left'), contains('account-a'));
    expect(prepared.session.sourceLabel('right'), contains('account-b'));
    expect(host.launches, isEmpty);
    await launch(prepared);
    expect(host.launches.single.arguments, [
      '--',
      prepared.left.path,
      prepared.right.path,
    ]);
    expect(host.launches.single.arguments, isNot(contains('/same/name.txt')));
    expect(host.launches.single.directory, stage.directoryPath);
    expect(left.writes, isEmpty);
    expect(right.writes, isEmpty);
  });

  test('local inputs are also copies and a tool change cannot publish to originals', () async {
    left = ComparisonBackend(
      const StorageReference(
        kind: 'local',
        provider: 'Local',
        accountKey: 'machine',
      ),
    )..file('/same/name.txt', 'original');
    final prepared = await prepare();
    host.beforeLaunch = () async {
      stages.entries[prepared.session.id]!.files['left.txt'] = utf8.encode(
        'tool edit',
      );
    };
    await launch(prepared);
    expect(utf8.decode(left.contents['/same/name.txt']!), 'original');
    expect(left.writes, isEmpty);
    expect(
      utf8.decode(stages.entries[prepared.session.id]!.files['left.txt']!),
      'tool edit',
    );
  });

  test(
    'unicode, spaces and shell characters remain separate literal arguments',
    () async {
      final prepared = await prepare(
        configuration: comparisonConfiguration(
          arguments: [
            r'$(touch forbidden); *.txt',
            'café with spaces',
            '--',
            '{left}',
            '{right}',
          ],
        ),
      );
      await launch(prepared);
      expect(host.launches.single.executable, '/apps/compare tool');
      expect(host.launches.single.arguments, [
        r'$(touch forbidden); *.txt',
        'café with spaces',
        '--',
        prepared.left.path,
        prepared.right.path,
      ]);
      final config = comparisonConfiguration();
      expect(config.expand('/private/{right}.txt', '/private/right'), [
        '--',
        '/private/{right}.txt',
        '/private/right',
      ]);
    },
  );

  test(
    'text and image preferences persist independently without launching',
    () async {
      await service.saveConfiguration(comparisonConfiguration());
      await service.saveConfiguration(
        comparisonConfiguration(
          kind: ExternalComparisonKind.image,
          arguments: ['--images', '{right}', '{left}'],
        ),
      );
      final restored = createService();
      await restored.ready;
      expect(restored.configuration(ExternalComparisonKind.text)!.arguments, [
        '--',
        '{left}',
        '{right}',
      ]);
      expect(restored.configuration(ExternalComparisonKind.image)!.arguments, [
        '--images',
        '{right}',
        '{left}',
      ]);
      expect(host.launches, isEmpty);
      expect(stages.entries, isEmpty);
    },
  );

  test(
    'corrupt preferences are retained and never silently overwritten',
    () async {
      final prefs = await SharedPreferences.getInstance();
      const raw = '{malformed';
      await prefs.setString('external_comparison_v1_linux', raw);
      final restored = createService();
      await restored.ready;
      expect(
        restored.loadError,
        failure(ExternalComparisonFailure.storageFailed),
      );
      await expectLater(
        restored.saveConfiguration(comparisonConfiguration()),
        throwsA(failure(ExternalComparisonFailure.storageFailed)),
      );
      expect(prefs.getString('external_comparison_v1_linux'), raw);
      expect(host.launches, isEmpty);
    },
  );

  test('template validation refuses ambiguous substitutions and executable launchers', () {
    for (final args in [
      <String>[],
      ['{left}'],
      ['{left}', '{right}', '{left}'],
      ['prefix{left}', '{right}'],
      ['{left}', '{right}', '{file}'],
      ['{left}', '{right}', 'nul\u0000'],
    ]) {
      expect(
        () => comparisonConfiguration(arguments: args),
        throwsA(failure(ExternalComparisonFailure.invalidConfiguration)),
      );
    }
    for (final exe in [
      'tool',
      '/usr/bin/bash',
      '/usr/bin/python3.14',
      '/usr/bin/node',
      '/bin/pwsh',
    ]) {
      expect(
        () => ExternalComparisonConfiguration(
          platform: 'linux',
          kind: ExternalComparisonKind.text,
          executable: exe,
          arguments: const ['{left}', '{right}'],
        ),
        throwsA(failure(ExternalComparisonFailure.invalidConfiguration)),
      );
    }
    expect(
      () => ExternalComparisonConfiguration(
        platform: 'windows',
        kind: ExternalComparisonKind.text,
        executable: r'C:\Tools\compare.cmd',
        arguments: const ['{left}', '{right}'],
      ),
      throwsA(failure(ExternalComparisonFailure.invalidConfiguration)),
    );
    final windows = ExternalComparisonConfiguration(
      platform: 'windows',
      kind: ExternalComparisonKind.image,
      executable: r'C:\Tools\Image compare.exe',
      arguments: const ['{left}', '{right}'],
    );
    expect(windows.expand(r'C:\private\left.png', r'C:\private\right.png'), [
      r'C:\private\left.png',
      r'C:\private\right.png',
    ]);
  });

  test(
    'unsupported host and missing or non-executable tool fail before staging',
    () async {
      host.platform = null;
      await expectLater(
        prepare(),
        throwsA(failure(ExternalComparisonFailure.unsupported)),
      );
      host.platform = 'linux';
      host.identity = null;
      await expectLater(
        prepare(),
        throwsA(failure(ExternalComparisonFailure.executableUnavailable)),
      );
      host.identity = CommandEntryFileIdentity(
        resolvedPath: '/apps/compare tool',
        isDirectory: false,
        size: 99,
        modified: DateTime.utc(2026),
        changed: DateTime.utc(2026),
        mode: 0x180,
      );
      await expectLater(
        prepare(),
        throwsA(failure(ExternalComparisonFailure.executableUnavailable)),
      );
      expect(stages.entries, isEmpty);
    },
  );

  test('resolved executable aliases cannot bypass launcher checks', () async {
    host.identity = CommandEntryFileIdentity(
      resolvedPath: '/usr/bin/bash',
      isDirectory: false,
      size: 99,
      modified: DateTime.utc(2026),
      changed: DateTime.utc(2026),
      mode: 0x1ed,
    );
    await expectLater(
      prepare(),
      throwsA(failure(ExternalComparisonFailure.invalidConfiguration)),
    );
    expect(stages.entries, isEmpty);
  });

  test(
    'missing and revised originals reject the immutable capture before staging',
    () async {
      final pair = comparisonPair(left, right);
      left.items.remove('/same/name.txt');
      await expectLater(
        prepare(pair: pair),
        throwsA(failure(ExternalComparisonFailure.changed)),
      );
      left.file(
        '/same/name.txt',
        'first account',
        objectId: 'object-a',
        version: 'a2',
      );
      await expectLater(
        prepare(pair: pair),
        throwsA(failure(ExternalComparisonFailure.changed)),
      );
      expect(stages.entries, isEmpty);
      expect(host.launches, isEmpty);
    },
  );

  test('both source identities are captured before any await and loss stays latched', () async {
    var current = true;
    final pair = comparisonPair(left, right, isCurrent: () => current);
    final entered = Completer<void>(), wait = Completer<void>();
    host.beforeInspect = () {
      entered.complete();
      return wait.future;
    };
    final future = prepare(pair: pair);
    final rejected = expectLater(
      future,
      throwsA(failure(ExternalComparisonFailure.changed)),
    );
    await entered.future;
    current = false;
    expect(pair.isCurrent, isFalse);
    current = true;
    wait.complete();
    await rejected;
    expect(pair.isCurrent, isFalse);
    expect(pair.right.storage, gatheringAccountB);
    expect(stages.entries, isEmpty);
  });

  test('a revision change during reading deletes unlaunched copies', () async {
    left.read = (file) async* {
      yield left.contents[file.path]!;
      left.file(
        file.path!,
        'first account',
        objectId: 'object-a',
        version: 'a2',
      );
    };
    await expectLater(
      prepare(),
      throwsA(failure(ExternalComparisonFailure.changed)),
    );
    expect(stages.entries, isEmpty);
    expect(host.launches, isEmpty);
  });

  test('a first source change during the second copy is detected', () async {
    right.read = (file) async* {
      yield right.contents[file.path]!;
      left.file(
        '/same/name.txt',
        'first account',
        objectId: 'object-a',
        version: 'a2',
      );
    };
    await expectLater(
      prepare(),
      throwsA(failure(ExternalComparisonFailure.changed)),
    );
    expect(stages.entries, isEmpty);
  });

  test('fresh stat metadata remains the launch baseline when listing metadata was incomplete', () async {
    left.file('/same/name.txt', 'one');
    final pair = ExternalComparisonPair(
      left: ExternalComparisonInput(
        backend: left,
        file: FileItem(
          name: 'name.txt',
          path: '/same/name.txt',
          isFolder: false,
        ),
        isCurrent: () => true,
      ),
      right: ExternalComparisonInput(
        backend: right,
        file: right.items['/same/name.txt']!,
        isCurrent: () => true,
      ),
    );
    final prepared = await prepare(pair: pair);
    left.file('/same/name.txt', 'changed length');
    await expectLater(
      launch(prepared),
      throwsA(failure(ExternalComparisonFailure.changed)),
    );
    expect(host.launches, isEmpty);
    await service.discard(prepared);
    expect(stages.entries, isEmpty);
  });

  test(
    'canceling a hung stat resolves without staging or a later launch',
    () async {
      final entered = Completer<void>(), wait = Completer<void>();
      left.beforeStat = (_) {
        entered.complete();
        return wait.future;
      };
      final control = FileOperationControl();
      final pending = prepare(control: control);
      final rejected = expectLater(
        pending,
        throwsA(failure(ExternalComparisonFailure.cancelled)),
      );
      await entered.future;
      control.cancel();
      await rejected;
      expect(stages.entries, isEmpty);
      wait.complete();
      await Future<void>.delayed(Duration.zero);
      expect(host.launches, isEmpty);
    },
  );

  test('canceling a stalled source read cancels its subscription and removes its private stage', () async {
    final listened = Completer<void>(), cancelled = Completer<void>();
    final input = StreamController<List<int>>(
      onListen: listened.complete,
      onCancel: cancelled.complete,
    );
    left.read = (_) => input.stream;
    final control = FileOperationControl();
    final pending = prepare(control: control);
    final rejected = expectLater(
      pending,
      throwsA(failure(ExternalComparisonFailure.cancelled)),
    );
    await listened.future;
    control.cancel();
    await rejected;
    await cancelled.future;
    await input.close();
    expect(stages.entries, isEmpty);
    expect(host.launches, isEmpty);
  });

  test(
    'source loss cancels a stalled read without waiting for the provider',
    () async {
      final listened = Completer<void>(), cancelled = Completer<void>();
      final input = StreamController<List<int>>(
        onListen: listened.complete,
        onCancel: cancelled.complete,
      );
      left.read = (_) => input.stream;
      final pending = prepare();
      final rejected = expectLater(
        pending,
        throwsA(failure(ExternalComparisonFailure.changed)),
      );
      await listened.future;
      right.current = false;
      await rejected;
      await cancelled.future;
      await input.close();
      expect(stages.entries, isEmpty);
    },
  );

  test(
    'preparation timeout cancels a stalled stream and releases the stage',
    () async {
      disposeService(service);
      service = createService(timeout: const Duration(milliseconds: 60));
      await service.ready;
      final input = StreamController<List<int>>();
      left.read = (_) => input.stream;
      await expectLater(
        prepare(),
        throwsA(failure(ExternalComparisonFailure.timedOut)),
      );
      await input.close();
      expect(stages.entries, isEmpty);
    },
  );

  test('a newer preparation invalidates an older pending intent', () async {
    final entered = Completer<void>(), wait = Completer<void>();
    left.beforeStat = (_) {
      entered.complete();
      return wait.future;
    };
    final first = prepare();
    final rejected = expectLater(
      first,
      throwsA(failure(ExternalComparisonFailure.changed)),
    );
    await entered.future;
    left.beforeStat = null;
    final second = await prepare();
    await rejected;
    wait.complete();
    await launch(second);
    expect(host.launches, hasLength(1));
    expect(stages.entries, hasLength(1));
  });

  test('declared and unknown stream lengths are bounded and partial copies removed', () async {
    disposeService(service);
    service = createService(maxBytes: 8);
    await service.ready;
    await expectLater(
      prepare(),
      throwsA(failure(ExternalComparisonFailure.tooLarge)),
    );
    left.items['/same/name.txt'] = FileItem(
      name: 'name.txt',
      path: '/same/name.txt',
      isFolder: false,
    );
    right.file('/same/name.txt', 'short');
    await expectLater(
      prepare(),
      throwsA(failure(ExternalComparisonFailure.tooLarge)),
    );
    expect(stages.entries, isEmpty);
  });

  test('a truncated stream never reaches review or launch', () async {
    left.read = (_) => Stream.value([1]);
    await expectLater(prepare(), throwsA(isA<ExternalComparisonException>()));
    expect(stages.entries, isEmpty);
    expect(host.launches, isEmpty);
  });

  for (final mutation in ['source', 'executable', 'stage', 'review', 'pair']) {
    test('$mutation change after review prevents launch', () async {
      final pair = comparisonPair(left, right);
      final prepared = await prepare(pair: pair);
      var current = true;
      switch (mutation) {
        case 'source':
          right.file(
            '/same/name.txt',
            'second account',
            objectId: 'object-b',
            version: 'b2',
          );
        case 'executable':
          host.identity = CommandEntryFileIdentity(
            resolvedPath: '/apps/compare tool',
            isDirectory: false,
            size: 100,
            modified: DateTime.utc(2026),
            changed: DateTime.utc(2026),
            mode: 0x1ed,
          );
        case 'stage':
          stages.entries[prepared.session.id]!.files['left.txt']![0] ^= 1;
        case 'review':
          current = false;
        case 'pair':
          pair.dispose();
      }
      await expectLater(
        launch(prepared, current: () => current),
        throwsA(
          failure(
            mutation == 'stage'
                ? ExternalComparisonFailure.stageChanged
                : ExternalComparisonFailure.changed,
          ),
        ),
      );
      expect(host.launches, isEmpty);
      await service.discard(prepared);
      expect(stages.entries, isEmpty);
    });
  }

  test('launch failure conservatively retains copies until explicit tool-closed cleanup', () async {
    final prepared = await prepare();
    host.launchError = StateError('OS acknowledgement failed');
    await expectLater(
      launch(prepared),
      throwsA(failure(ExternalComparisonFailure.launchFailed)),
    );
    await service.discard(prepared);
    expect(stages.entries, hasLength(1));
    expect(prepared.session.state, 'launchFailed');
    await expectLater(
      service.release(prepared.session.id, toolClosed: false),
      throwsA(failure(ExternalComparisonFailure.changed)),
    );
    await service.release(prepared.session.id, toolClosed: true);
    expect(stages.entries, isEmpty);
  });

  test('failure to persist launch intent prevents the OS call and retains uncertain copies', () async {
    final prepared = await prepare();
    stages.failManifest = true;
    await expectLater(
      launch(prepared),
      throwsA(failure(ExternalComparisonFailure.launchFailed)),
    );
    expect(host.launches, isEmpty);
    await service.discard(prepared);
    expect(stages.entries, hasLength(1));
    stages.failManifest = false;
    await service.release(prepared.session.id, toolClosed: true);
  });

  test('cancellation during final validation prevents a handoff', () async {
    final prepared = await prepare();
    final entered = Completer<void>(), wait = Completer<void>();
    stages.beforeInspect = (_) {
      entered.complete();
      return wait.future;
    };
    final control = FileOperationControl();
    final pending = launch(prepared, control: control);
    final rejected = expectLater(
      pending,
      throwsA(failure(ExternalComparisonFailure.cancelled)),
    );
    await entered.future;
    control.cancel();
    wait.complete();
    await rejected;
    expect(host.launches, isEmpty);
    await service.discard(prepared);
    expect(stages.entries, isEmpty);
  });

  test('a successful handoff is single-use and persists after dispose/reload without replay', () async {
    final prepared = await prepare();
    await launch(prepared);
    await expectLater(
      launch(prepared),
      throwsA(failure(ExternalComparisonFailure.changed)),
    );
    disposeService(service);
    expect(stages.entries[prepared.session.id]!.closed, isTrue);
    service = createService();
    await service.ready;
    expect(service.sessions.single.id, prepared.session.id);
    expect(service.sessions.single.launchRequested, isTrue);
    expect(host.launches, hasLength(1));
    await service.release(prepared.session.id, toolClosed: true);
    expect(stages.entries, isEmpty);
  });

  test('dispose while OS launch acknowledgement is pending retains files and later releases the lease', () async {
    final prepared = await prepare();
    final entered = Completer<void>(), wait = Completer<void>();
    host.beforeLaunch = () {
      entered.complete();
      return wait.future;
    };
    final pending = launch(prepared);
    await entered.future;
    final stage = stages.entries[prepared.session.id]!;
    disposeService(service);
    expect(stage.closed, isFalse);
    expect(stage.files, hasLength(2));
    wait.complete();
    await pending;
    expect(stage.closed, isTrue);
    expect(stage.files, hasLength(2));
    expect(stage.manifest!['launchRequested'], isTrue);
  });

  test(
    'failed explicit cleanup after disposal also releases the retained lease',
    () async {
      final prepared = await prepare();
      await launch(prepared);
      final entered = Completer<void>(), wait = Completer<void>();
      stages.beforeDelete = () {
        entered.complete();
        return wait.future;
      };
      stages.failDelete = true;
      final pending = service.release(prepared.session.id, toolClosed: true);
      final rejected = expectLater(pending, throwsStateError);
      await entered.future;
      final stage = stages.entries[prepared.session.id]!;
      disposeService(service);
      wait.complete();
      await rejected;
      expect(stage.closed, isTrue);
      expect(stage.files, hasLength(2));
    },
  );

  test(
    'retained-session cap prevents unbounded copying until explicit cleanup',
    () async {
      for (
        var index = 0;
        index < ExternalComparisonService.maxSessions;
        index++
      ) {
        await launch(await prepare());
      }
      await expectLater(
        prepare(),
        throwsA(failure(ExternalComparisonFailure.sessionLimit)),
      );
      expect(stages.entries, hasLength(ExternalComparisonService.maxSessions));
      await service.release(service.sessions.first.id, toolClosed: true);
      await launch(await prepare());
      expect(stages.entries, hasLength(ExternalComparisonService.maxSessions));
    },
  );

  test('malformed retained manifests remain removable and do not gain launch authority', () async {
    final stage = await stages.create(
      kind: ExternalComparisonService.stageKind,
    );
    await stage.writeManifest({
      'version': 1,
      'id': stage.id,
      'kind': stage.kind,
      'state': ['bad'],
      'tool': 42,
      'launchRequested': false,
    });
    service = createService();
    await service.ready;
    final restored = service.sessions.single;
    expect(restored.state, 'unavailable');
    expect(restored.executable, isEmpty);
    expect(restored.sourceLabel('left'), isEmpty);
    await expectLater(
      service.release(restored.id, toolClosed: false),
      throwsA(failure(ExternalComparisonFailure.changed)),
    );
    await service.release(restored.id, toolClosed: true);
    expect(host.launches, isEmpty);
  });

  test('nine catalogs include every message and every error', () {
    expect(ExternalComparisonStrings.languages.toSet(), {
      'en',
      'de',
      'fr',
      'es',
      'pt',
      'zh',
      'ja',
      'ko',
      'ar',
    });
    for (final item in ExternalComparisonStrings.messages.entries) {
      expect(item.value, hasLength(9), reason: item.key);
      expect(
        item.value.every((translation) => translation.trim().isNotEmpty),
        isTrue,
        reason: item.key,
      );
    }
    for (final value in ExternalComparisonFailure.values) {
      expect(
        ExternalComparisonStrings.messages.containsKey(value.name),
        isTrue,
      );
    }
  });

  test('native private copies survive service restart and explicit cleanup leaves originals intact', () async {
    final root = await Directory.systemTemp.createTemp(
      'external-compare-native-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final original = File('${root.path}/original.txt');
    await original.writeAsString('untouched local input');
    left = ComparisonBackend(
      const StorageReference(
        kind: 'local',
        provider: 'Local',
        accountKey: 'machine',
      ),
    );
    left.file(original.path, 'untouched local input');
    left.read = (_) => original.openRead();
    final store = PrivateToolStagingStore(
      rootDirectory: () async => '${root.path}/private',
    );
    disposeService(service);
    service = createService(staging: store);
    await service.ready;
    final prepared = await prepare(
      pair: comparisonPair(left, right, leftPath: original.path),
    );
    await launch(prepared);
    final copied = File(prepared.left.path);
    expect(await copied.readAsString(), 'untouched local input');
    await copied.writeAsString('edited private input');
    disposeService(service);
    // close() runs asynchronously to flush and release the native lease.
    await prepared.session.stage.close();
    service = createService(staging: store);
    await service.ready;
    expect(service.loadError, isNull);
    expect(service.sessions.single.launchRequested, isTrue);
    expect(await copied.readAsString(), 'edited private input');
    expect(await original.readAsString(), 'untouched local input');
    await service.release(prepared.session.id, toolClosed: true);
    expect(
      await Directory(prepared.session.stage.directoryPath).exists(),
      isFalse,
    );
    expect(await original.readAsString(), 'untouched local input');
    expect(host.launches, hasLength(1));
  });
}
