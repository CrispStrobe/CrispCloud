import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_external_packer.dart';
import 'package:crisp_cloud/services/archive_external_packer_io.dart';
import 'package:crisp_cloud/services/archive_external_packer_metadata_io.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:crisp_cloud/services/archive_writer_service.dart';
import 'package:crisp_cloud/services/native_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FixtureProcess {
  final invocations = <ArchiveExternalPackerInvocation>[];
  Future<void> Function(ArchiveExternalPackerInvocation)? mutate;
  int exit = 0;
  bool badTimes = false;
  Set<ArchiveExternalPackerFormat> supported = ArchiveExternalPackerFormat
      .values
      .toSet();

  Future<ArchiveExternalPackerProcessResult> call(
    ArchiveExternalPackerInvocation request,
  ) async {
    invocations.add(request);
    if (request.outputPath == null) {
      return ArchiveExternalPackerProcessResult(
        0,
        request.arguments.first == 'i' ? '7-Zip (z) 23.01 (x64)' : 'RAR 7.11',
      );
    }
    final format = request.outputPath!.endsWith('.rar')
        ? ArchiveExternalPackerFormat.rar
        : request.outputPath!.endsWith('.7z')
        ? ArchiveExternalPackerFormat.sevenZip
        : ArchiveExternalPackerFormat.zip;
    if (exit != 0 || !supported.contains(format)) {
      return ArchiveExternalPackerProcessResult(
        exit == 0 ? 2 : exit,
        'untrusted private log',
      );
    }
    final entries = <ArchiveWriteEntry>[];
    await for (final object in Directory(
      request.directory,
    ).list(recursive: true, followLinks: false)) {
      final stat = await object.stat();
      final file = File(object.path);
      entries.add(
        ArchiveWriteEntry(
          path: p
              .relative(object.path, from: request.directory)
              .split(p.separator)
              .join('/'),
          isDirectory: object is Directory,
          size: object is Directory ? 0 : stat.size,
          mode: Platform.isWindows ? null : stat.mode & 0xfff,
          modified: badTimes ? DateTime.utc(2001) : stat.modified.toUtc(),
          readChunks: object is File ? file.openRead : null,
        ),
      );
    }
    final bytes = await collectArchiveWrite(
      (sink) => writeArchiveEntries(
        switch (format) {
          ArchiveExternalPackerFormat.zip => ArchiveEndpointFormat.zip,
          ArchiveExternalPackerFormat.sevenZip =>
            ArchiveEndpointFormat.sevenZip,
          ArchiveExternalPackerFormat.rar => ArchiveEndpointFormat.rar,
        },
        entries,
        sink: sink,
        maxOutputBytes: request.maxOutputBytes,
      ),
    );
    await File(request.outputPath!).writeAsBytes(bytes, flush: true);
    await mutate?.call(request);
    return const ArchiveExternalPackerProcessResult(0, '');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, stages;
  late File executable;
  late _FixtureProcess process;
  late NativeArchiveExternalPackerEngine engine;
  late ArchiveExternalPackerConfiguration configuration;
  late ArchiveExternalPackerInstallation installation;

  Matcher failure(ArchiveExternalPackerFailure failure) => throwsA(
    isA<ArchiveExternalPackerException>().having(
      (e) => e.failure,
      'failure',
      failure,
    ),
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('packer-io-test-');
    root = Directory(await root.resolveSymbolicLinks());
    stages = Directory(p.join(root.path, 'stages'));
    executable = File(
      p.join(root.path, Platform.isWindows ? '7zz.exe' : '7zz'),
    );
    await executable.writeAsBytes([
      if (Platform.isWindows) ...[
        0x4d,
        0x5a,
        0,
        0,
      ] else if (Platform.isMacOS) ...[
        0xcf,
        0xfa,
        0xed,
        0xfe,
      ] else ...[
        0x7f,
        0x45,
        0x4c,
        0x46,
      ],
      ...utf8.encode('inert fixture executable; process calls are injected'),
    ]);
    if (!Platform.isWindows) {
      expect(setFileMode(executable.path, 0x1c0), isTrue);
    }
    final stat = await executable.stat();
    configuration = ArchiveExternalPackerConfiguration(
      platform: Platform.operatingSystem,
      kind: ArchiveExternalPackerKind.sevenZip,
      executable: executable.path,
    );
    installation = ArchiveExternalPackerInstallation(
      configuration: configuration,
      identity: ArchiveExternalPackerIdentity(
        path: executable.path,
        length: stat.size,
        mode: stat.mode,
        modified: stat.modified,
        changed: stat.changed,
        sha256: sha256.convert(await executable.readAsBytes()).toString(),
      ),
      version: '23.01',
      formats: {
        ArchiveExternalPackerFormat.zip,
        ArchiveExternalPackerFormat.sevenZip,
      },
    );
    process = _FixtureProcess();
    engine = NativeArchiveExternalPackerEngine(
      hasAccess: (_) async => true,
      runner: process.call,
      stagingRoot: () async => stages.path,
    );
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  List<ArchiveWriteEntry> entries() => [
    ArchiveWriteEntry(
      path: 'folder',
      isDirectory: true,
      size: 0,
      modified: DateTime.utc(2024, 1, 2, 3, 4, 5),
      mode: Platform.isWindows ? null : 0x1e8,
    ),
    ArchiveWriteEntry(
      path: 'folder/雪.txt',
      isDirectory: false,
      size: 3,
      modified: DateTime.utc(2024, 1, 2, 3, 4, 5),
      mode: Platform.isWindows ? null : 0x1a0,
      readChunks: () => Stream.value([1, 2, 3]),
    ),
  ];
  Future<void> write({
    List<ArchiveWriteEntry>? selected,
    int limit = 1024 * 1024,
    bool Function()? cancelled,
    Future<void> Function(List<int>)? sink,
  }) => engine.write(
    installation: installation,
    options: const ArchiveExternalPackerOptions(
      name: 'result.zip',
      format: ArchiveExternalPackerFormat.zip,
    ),
    entries: selected ?? entries(),
    sink: sink ?? (_) async {},
    maxOutputBytes: limit,
    isCancelled: cancelled,
  );
  Future<void> clean() async {
    if (await stages.exists()) expect(await stages.list().toList(), isEmpty);
  }

  test(
    'probe requires all compression levels to round-trip exact metadata',
    () async {
      final result = await engine.probe(configuration);
      expect(result.formats, {
        ArchiveExternalPackerFormat.zip,
        ArchiveExternalPackerFormat.sevenZip,
      });
      expect(process.invocations.length, 7);
      expect(
        process.invocations
            .skip(1)
            .map((i) => i.arguments.singleWhere((a) => a.startsWith('-mx='))),
        ['-mx=0', '-mx=5', '-mx=9', '-mx=0', '-mx=5', '-mx=9'],
      );
      await clean();
    },
  );
  test(
    'probe exposes only formats with a successful content and metadata profile',
    () async {
      process.supported = {ArchiveExternalPackerFormat.sevenZip};
      final result = await engine.probe(configuration);
      expect(result.formats, {ArchiveExternalPackerFormat.sevenZip});
      await clean();
    },
  );
  test('successful exit and valid bytes without exact metadata fail capability checks', () async {
    process.badTimes = true;
    await expectLater(
      engine.probe(configuration),
      failure(ArchiveExternalPackerFailure.capabilityCheckFailed),
    );
    await clean();
  });
  test(
    'private staged paths and fixed switches are the only process inputs',
    () async {
      process.mutate = (request) async {
        expect(p.isWithin(stages.path, request.directory), isTrue);
        expect(p.isWithin(stages.path, request.outputPath!), isTrue);
        expect(
          request.arguments,
          containsAll(['-r-', '-spd', '-sse', '-mtp=1']),
        );
        expect(request.arguments, isNot(contains('--')));
        expect(request.arguments.any((a) => a.contains('雪')), isFalse);
        expect(request.environment.containsKey('PATH'), isFalse);
        expect(request.environment.containsKey('RAR'), isFalse);
        final list = request.arguments
            .singleWhere((a) => a.startsWith('@'))
            .substring(1);
        expect(await File(list).readAsString(), './folder\n');
        expect(request.environment['HOME'], p.dirname(request.directory));
        if (!Platform.isWindows) {
          expect(
            (await Directory(request.environment['HOME']!).stat()).mode & 0x3f,
            0,
          );
          expect(
            (await File(
                  p.join(request.directory, 'folder/雪.txt'),
                ).stat()).mode &
                0xfff,
            0x1a0,
          );
        }
      };
      await write();
      await clean();
    },
  );

  test('RAR uses a complete literal list and no password switch', () async {
    final rar = ArchiveExternalPackerInstallation(
      configuration: ArchiveExternalPackerConfiguration(
        platform: configuration.platform,
        kind: ArchiveExternalPackerKind.rar,
        executable: configuration.executable,
      ),
      identity: installation.identity,
      version: '7.23',
      formats: {ArchiveExternalPackerFormat.rar},
    );
    process.mutate = (request) async {
      expect(
        request.arguments,
        containsAll(['-cfg-', '-ma5', '-s-', '-r-', '-scfl']),
      );
      expect(
        request.arguments.any(
          (value) => value.startsWith('-p') || value.startsWith('-hp'),
        ),
        isFalse,
      );
      final list = request.arguments
          .singleWhere((value) => value.startsWith('@'))
          .substring(1);
      expect(await File(list).readAsString(), './folder\n./folder/雪.txt\n');
    };
    await engine.write(
      installation: rar,
      options: const ArchiveExternalPackerOptions(
        name: 'result.rar',
        format: ArchiveExternalPackerFormat.rar,
      ),
      entries: entries(),
      sink: (_) async {},
      maxOutputBytes: 1024 * 1024,
    );
    await clean();
  });
  test('script wrappers are refused before launching a process', () async {
    await executable.writeAsString('#!/bin/sh\necho fake\n');
    await expectLater(
      engine.probe(configuration),
      failure(ArchiveExternalPackerFailure.unavailable),
    );
    expect(process.invocations, isEmpty);
    await clean();
  });
  test('executable changes after a probe prevent invocation', () async {
    await executable.writeAsBytes([1], mode: FileMode.append, flush: true);
    await expectLater(write(), failure(ArchiveExternalPackerFailure.changed));
    expect(process.invocations, isEmpty);
    await clean();
  });
  test('revoked executable access prevents invocation', () async {
    engine = NativeArchiveExternalPackerEngine(
      hasAccess: (_) async => false,
      runner: process.call,
      stagingRoot: () async => stages.path,
    );
    await expectLater(
      write(),
      failure(ArchiveExternalPackerFailure.unavailable),
    );
    expect(process.invocations, isEmpty);
    await clean();
  });
  test('oversized selected members fail before reading input or starting a process', () async {
    var read = false;
    await expectLater(
      write(
        selected: [
          ArchiveWriteEntry(
            path: 'large',
            isDirectory: false,
            size: kArchiveExternalPackerMemberLimit + 1,
            readChunks: () {
              read = true;
              return Stream.value([]);
            },
          ),
        ],
      ),
      failure(ArchiveExternalPackerFailure.unsupportedEntry),
    );
    expect(read, isFalse);
    expect(process.invocations, isEmpty);
    await clean();
  });
  test('implicit parents and privileged permission bits are not silently transformed', () async {
    await expectLater(
      write(selected: [entries().last]),
      failure(ArchiveExternalPackerFailure.unsupportedEntry),
    );
    if (!Platform.isWindows) {
      await expectLater(
        write(
          selected: [
            ArchiveWriteEntry(
              path: 'privileged',
              isDirectory: false,
              size: 0,
              mode: 0x9ed,
              readChunks: () => const Stream.empty(),
            ),
          ],
        ),
        failure(ArchiveExternalPackerFailure.unsupportedEntry),
      );
    }
    expect(process.invocations, isEmpty);
    await clean();
  });
  test('warning exit codes never reach the output sink', () async {
    process.exit = 1;
    var writes = 0;
    await expectLater(
      write(sink: (_) async => writes++),
      failure(ArchiveExternalPackerFailure.processFailed),
    );
    expect(writes, 0);
    await clean();
  });
  test('additional output files are refused before streaming', () async {
    process.mutate = (request) async =>
        File(p.join(p.dirname(request.outputPath!), 'extra.rar'))
            .writeAsString('unexpected');
    await expectLater(
      write(),
      failure(ArchiveExternalPackerFailure.invalidOutput),
    );
    await clean();
  });
  test('a replaced output symlink cannot be streamed', () async {
    if (Platform.isWindows) return;
    final outside = await File(p.join(root.path, 'outside'))
        .writeAsString('retain');
    process.mutate = (request) async {
      await File(request.outputPath!).delete();
      await Link(request.outputPath!).create(outside.path);
    };
    await expectLater(
      write(),
      failure(ArchiveExternalPackerFailure.invalidOutput),
    );
    expect(await outside.readAsString(), 'retain');
    await clean();
  });
  test('changed private input rejects otherwise valid output', () async {
    process.mutate = (request) async {
      await File(p.join(request.directory, 'folder/雪.txt'))
          .writeAsBytes([4, 5, 6]);
    };
    await expectLater(write(), failure(ArchiveExternalPackerFailure.changed));
    await clean();
  });
  test(
    'input reader length violations are cleaned without invoking a tool',
    () async {
      await expectLater(
        write(
          selected: [
            ArchiveWriteEntry(
              path: 'wrong-length',
              isDirectory: false,
              size: 3,
              readChunks: () => Stream.value([1, 2]),
            ),
          ],
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(process.invocations, isEmpty);
      await clean();
    },
  );
  test(
    'cancellation is checked before the first stage or invocation',
    () async {
      await expectLater(
        write(cancelled: () => true),
        failure(ArchiveExternalPackerFailure.cancelled),
      );
      expect(process.invocations, isEmpty);
      await clean();
    },
  );
  test('unconfirmed child shutdown retains the owned staging tree', () async {
    engine = NativeArchiveExternalPackerEngine(
      hasAccess: (_) async => true,
      stagingRoot: () async => stages.path,
      runner: (_) async {
        throw const ArchiveExternalPackerException(
          ArchiveExternalPackerFailure.cleanupFailed,
        );
      },
    );
    await expectLater(
      write(),
      failure(ArchiveExternalPackerFailure.cleanupFailed),
    );
    final retained = await stages.list().toList();
    expect(retained.length, 1);
    expect(
      await File(p.join(retained.single.path, 'input/folder/雪.txt'))
          .readAsBytes(),
      [1, 2, 3],
    );
  });
  test('the staging root cannot be replaced with a symlink', () async {
    if (Platform.isWindows) return;
    final outside = await Directory(p.join(root.path, 'outside')).create();
    await Link(stages.path).create(outside.path);
    await expectLater(write(), failure(ArchiveExternalPackerFailure.changed));
    expect(await outside.list().toList(), isEmpty);
    expect(process.invocations, isEmpty);
  });

  group('private directory time metadata', () {
    test('native directory modification time preserves microseconds without changing children', () async {
      final directory = await Directory(p.join(root.path, 'time')).create();
      final file = await File(p.join(directory.path, 'keep'))
          .writeAsString('unchanged');
      final time = DateTime.utc(2024, 1, 2, 3, 4, 5, 123, 456);
      await setArchiveExternalPackerModified(
        directory.path,
        time,
        isDirectory: true,
      );
      expect((await directory.stat()).modified.isAtSameMomentAs(time), isTrue);
      expect(await file.readAsString(), 'unchanged');
    });
    test('timestamps are not written through a symlink', () async {
      if (Platform.isWindows) return;
      final outside = await Directory(p.join(root.path, 'time-target'))
          .create();
      final before = (await outside.stat()).modified;
      final link = await Link(p.join(root.path, 'time-link'))
          .create(outside.path);
      await expectLater(
        setArchiveExternalPackerModified(
          link.path,
          DateTime.utc(2020),
          isDirectory: true,
        ),
        failure(ArchiveExternalPackerFailure.changed),
      );
      expect((await outside.stat()).modified, before);
    });
  });

  group('native owned process cancellation', () {
    test('cancellation awaits shutdown of a foreground process', () async {
      var cancelled = false;
      final timer = Timer(
        const Duration(milliseconds: 150),
        () => cancelled = true,
      );
      try {
        await expectLater(
          runArchiveExternalPackerProcess(
            ArchiveExternalPackerInvocation(
              executable: '/bin/sleep',
              arguments: ['10'],
              directory: root.path,
              environment: {'HOME': root.path, 'LANG': 'C'},
              timeout: const Duration(seconds: 3),
              isCancelled: () => cancelled,
            ),
          ),
          failure(ArchiveExternalPackerFailure.cancelled),
        );
      } finally {
        timer.cancel();
      }
    });
    test('a timed-out foreground process is closed before returning', () async {
      await expectLater(
        runArchiveExternalPackerProcess(
          ArchiveExternalPackerInvocation(
            executable: '/bin/sleep',
            arguments: ['10'],
            directory: root.path,
            environment: {'HOME': root.path, 'LANG': 'C'},
            timeout: const Duration(milliseconds: 80),
          ),
        ),
        failure(ArchiveExternalPackerFailure.timeout),
      );
    });
  }, skip: Platform.isWindows || !File('/bin/sleep').existsSync());
}
