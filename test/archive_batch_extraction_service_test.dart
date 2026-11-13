import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_batch_extraction_service.dart';
import 'package:crisp_cloud/services/archive_service.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/archive_creation_backend.dart';
import 'support/archive_volume_fixtures.dart';

Uint8List _zip(
  Map<String, List<int>> files, {
  List<String> directories = const [],
  String? password,
}) {
  final archive = ar.Archive();
  for (final name in directories) {
    archive.addFile(ar.ArchiveFile.directory(name));
  }
  for (final entry in files.entries) {
    archive.addFile(ar.ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ar.ZipEncoder(password: password).encode(archive));
}

class _Backend extends ArchiveCreationBackend {
  int reads = 0;
  bool failLate = false;
  void Function(FileItem file)? duringRead;
  Completer<void>? statGate, readGate;
  String? storageIdentity;
  @override
  String? get persistentStorageId => storageIdentity;
  @override
  Future<FileItem?> stat(String path) async {
    await statGate?.future;
    return super.stat(path);
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    reads++;
    await readGate?.future;
    await for (final chunk in super.readFile(file)) {
      yield chunk;
      duringRead?.call(file);
    }
    if (failLate) throw StateError('Late source failure.');
  }
}

class _HeldStageLocal extends Fake
    implements LocalFileService, ScopedLocalFileOperations {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() action,
  ) async {
    if (p.basename(path) == 'payload' &&
        p.basename(p.dirname(path)).startsWith('.crisp-transfer-') &&
        !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return action();
  }
}

Future<List<FileItem>> _files(_Backend backend, List<String> names) async => [
  for (final name in names) (await backend.stat('/input/$name'))!,
];
Future<ArchiveBatchExtractionPlan> _plan(
  _Backend backend,
  List<String> names,
  String target, {
  ArchiveBatchExtractionOptions options = const ArchiveBatchExtractionOptions(),
  ArchiveExtractionPasswordRequest? password,
  int maxInputBytes = kArchiveStreamingLimit,
  int maxOutputBytes = kArchiveStreamingLimit,
  bool Function()? isCancelled,
}) async => ArchiveBatchExtractionPlan.prepare(
  source: backend,
  files: await _files(backend, names),
  targetDirectory: target,
  options: options,
  requestPassword: password,
  maxInputBytes: maxInputBytes,
  maxOutputBytes: maxOutputBytes,
  isCancelled: isCancelled,
);

Future<List<String>> _stages(Directory directory) async =>
    !await directory.exists()
    ? []
    : [
        await for (final item in directory.list(
          recursive: true,
          followLinks: false,
        ))
          if (p.basename(item.path).startsWith('.crisp-') ||
              p.basename(item.path).contains('.partial'))
            item.path,
      ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late String output;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('batch-extraction-');
    output = p.join(temp.path, 'out');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test(
    'native pane storage-scoped rows preview and extract real local archives',
    () async {
      final bytes = _zip({'hello.txt': utf8.encode('native pane payload')});
      final file = await File(p.join(temp.path, 'native.zip'))
          .writeAsBytes(bytes);
      final local = LocalFileService();
      final source = LocalOperationBackend(local, isCurrent: () => true);
      final stat = (await source.stat(file.path))!;
      expect(stat.storageId, isNull);
      expect(source.persistentStorageId, isNotNull);
      final selected = stat.copyWith(storageId: source.persistentStorageId);
      final plan = await ArchiveBatchExtractionPlan.prepare(
        source: source,
        files: [selected],
        targetDirectory: output,
        local: local,
      );
      expect(
        plan.entries.single.archiveFile.storageId,
        source.persistentStorageId,
      );
      expect(await Directory(output).exists(), isFalse);
      final report = await plan.extract();
      expect(report.completedCount, 1);
      expect(report.stopReason, isNull);
      expect(
        await File(p.join(output, 'native/hello.txt')).readAsString(),
        'native pane payload',
      );
      expect(await file.readAsBytes(), bytes);
    },
  );

  test(
    'a native pane row from another storage account is refused before capture',
    () async {
      final file = await File(p.join(temp.path, 'native.zip')).writeAsBytes(
        _zip({
          'hello.txt': [1],
        }),
      );
      final local = LocalFileService();
      final source = LocalOperationBackend(local, isCurrent: () => true);
      final selected = (await source.stat(file.path))!
          .copyWith(storageId: 'different-account');
      await expectLater(
        ArchiveBatchExtractionPlan.prepare(
          source: source,
          files: [selected],
          targetDirectory: output,
          local: local,
        ),
        throwsA(
          isA<ArchiveViewException>().having(
            (error) => error.toString(),
            'message',
            contains('another storage account'),
          ),
        ),
      );
      expect(await Directory(output).exists(), isFalse);
    },
  );

  test(
    'changing persistent account identity after preview prevents publication',
    () async {
      final source = _Backend()
        ..storageIdentity = 'captured-account'
        ..put(
          '/input/a.zip',
          _zip({
            'a': [1],
          }),
        );
      final plan = await _plan(source, ['a.zip'], output);
      source.storageIdentity = 'replacement-account';
      expect(plan.isCurrent, isFalse);
      final report = await plan.extract();
      expect(report.stopReason, ArchiveBatchExtractionStopReason.unavailable);
      expect(report.unprocessedCount, 1);
      expect(await Directory(output).exists(), isFalse);
    },
  );

  test(
    'default preview captures both archives and writes only after execution',
    () async {
      final first = _zip(
        {'docs/a.txt': utf8.encode('alpha')},
        directories: ['empty/'],
      );
      final second = _zip({
        'b.bin': [1, 2, 3],
      });
      final backend = _Backend()
        ..put('/input/first.zip', first)
        ..put('/input/second.zip', second);
      final plan = await _plan(backend, ['first.zip', 'second.zip'], output);
      expect(plan.entries.map((entry) => entry.relativePath), [
        'first/empty',
        'first/docs/a.txt',
        'second/b.bin',
      ]);
      expect(plan.outputBytes, 8);
      expect(plan.inputBytes, first.length + second.length);
      expect(await Directory(output).exists(), isFalse);
      backend.put(
        '/input/first.zip',
        _zip({
          'replacement.txt': [9],
        }),
      );
      final report = await plan.extract();
      expect(report.stopReason, isNull);
      expect(report.completedCount, 2);
      expect(report.publishedFileCount, 2);
      expect(report.unprocessedCount, 0);
      expect(
        report.items.first.snapshotSha256,
        sha256.convert(first).toString(),
      );
      expect(
        await File(p.join(output, 'first/docs/a.txt')).readAsString(),
        'alpha',
      );
      expect(await File(p.join(output, 'second/b.bin')).readAsBytes(), [
        1,
        2,
        3,
      ]);
      expect(await Directory(p.join(output, 'first/empty')).exists(), isTrue);
      expect(
        await File(p.join(output, 'first/replacement.txt')).exists(),
        isFalse,
      );
      expect(backend.writes, isEmpty);
      expect(backend.contents['/input/second.zip'], second);
      expect(plan.isClosed, isTrue);
      await expectLater(plan.extract(), throwsStateError);
      expect(await _stages(Directory(output)), isEmpty);
    },
  );

  test('compound archive suffix becomes one clear output folder', () async {
    final tar = ar.TarEncoder().encode(
      ar.Archive()..addFile(ar.ArchiveFile.bytes('a.txt', [1])),
    );
    final backend = _Backend()
      ..put('/input/example.tar.gz', const ar.GZipEncoder().encode(tar));
    final plan = await _plan(backend, ['example.tar.gz'], output);
    addTearDown(plan.close);
    expect(plan.entries.single.relativePath, 'example/a.txt');
  });

  test(
    'shared folders merge directory structure without colliding files',
    () async {
      final backend = _Backend()
        ..put(
          '/input/a.zip',
          _zip(
            {
              'docs/a': [1],
            },
            directories: ['docs/'],
          ),
        )
        ..put(
          '/input/b.zip',
          _zip(
            {
              'docs/b': [2],
            },
            directories: ['docs/'],
          ),
        );
      final plan = await _plan(
        backend,
        ['a.zip', 'b.zip'],
        output,
        options: const ArchiveBatchExtractionOptions(
          folderMode: ArchiveExtractionFolderMode.shared,
        ),
      );
      expect(plan.entries.where((entry) => entry.isDirectory).length, 1);
      final report = await plan.extract();
      expect(report.completedCount, 2);
      expect(await File(p.join(output, 'docs/a')).readAsBytes(), [1]);
      expect(await File(p.join(output, 'docs/b')).readAsBytes(), [2]);
    },
  );

  test('smart mode keeps one top-level item and wraps mixed roots', () async {
    final backend = _Backend()
      ..put(
        '/input/folder.zip',
        _zip({
          'release/a': [1],
          'release/b': [2],
        }),
      )
      ..put(
        '/input/single.zip',
        _zip({
          'alone.txt': [3],
        }),
      )
      ..put(
        '/input/mixed.zip',
        _zip({
          'x': [4],
          'y': [5],
        }),
      );
    final plan = await _plan(
      backend,
      ['folder.zip', 'single.zip', 'mixed.zip'],
      output,
      options: const ArchiveBatchExtractionOptions(
        folderMode: ArchiveExtractionFolderMode.smart,
      ),
    );
    addTearDown(plan.close);
    expect(plan.entries.map((entry) => entry.relativePath), [
      'release/a',
      'release/b',
      'alone.txt',
      'mixed/x',
      'mixed/y',
    ]);
    expect(await Directory(output).exists(), isFalse);
  });

  test('wildcard inclusions and exclusions select exact files without broadening folders', () async {
    final backend = _Backend()
      ..put(
        '/input/photos.zip',
        _zip(
          {
            'docs/one.TXT': [1],
            'docs/thumb.txt': [2],
            'other/photo.png': [3],
            'readme': [4],
          },
          directories: ['empty/'],
        ),
      );
    final plan = await _plan(
      backend,
      ['photos.zip'],
      output,
      options: const ArchiveBatchExtractionOptions(mask: '*.txt;*.png|thumb*'),
    );
    expect(plan.entries.map((entry) => entry.memberPath), [
      'docs/one.TXT',
      'other/photo.png',
    ]);
    final report = await plan.extract();
    expect(report.publishedFileCount, 2);
    expect(
      await File(p.join(output, 'photos/docs/thumb.txt')).exists(),
      isFalse,
    );
    expect(await Directory(p.join(output, 'photos/empty')).exists(), isFalse);
  });

  test(
    'full-path case-sensitive masks use the existing Commander matcher',
    () async {
      final backend = _Backend()
        ..put(
          '/input/a.zip',
          _zip({
            'docs/A.txt': [1],
            'Docs/B.txt': [2],
            'docs/C.png': [3],
          }),
        );
      final plan = await _plan(
        backend,
        ['a.zip'],
        output,
        options: const ArchiveBatchExtractionOptions(
          mask: 'docs/*.txt',
          matchFullPath: true,
          caseSensitive: true,
        ),
      );
      addTearDown(plan.close);
      expect(plan.entries.single.memberPath, 'docs/A.txt');
    },
  );

  test(
    'flattening previews exact basenames and omits empty directories',
    () async {
      final backend = _Backend()
        ..put(
          '/input/a.zip',
          _zip(
            {
              'docs/a': [1],
              'more/b': [2],
            },
            directories: ['empty/'],
          ),
        );
      final plan = await _plan(
        backend,
        ['a.zip'],
        output,
        options: const ArchiveBatchExtractionOptions(flatten: true),
      );
      expect(plan.entries.map((entry) => entry.relativePath), ['a/a', 'a/b']);
      await plan.extract();
      expect(await Directory(p.join(output, 'a/docs')).exists(), isFalse);
      expect(await Directory(p.join(output, 'a/empty')).exists(), isFalse);
    },
  );

  final collisionCases = <String, Map<String, Map<String, List<int>>>>{
    'same name across archives': {
      'a.zip': {
        'same': [1],
      },
      'b.zip': {
        'same': [2],
      },
    },
    'file before descendant': {
      'a.zip': {
        'node': [1],
      },
      'b.zip': {
        'node/child': [2],
      },
    },
    'descendant before file': {
      'a.zip': {
        'node/child': [1],
      },
      'b.zip': {
        'node': [2],
      },
    },
  };
  for (final collision in collisionCases.entries) {
    test('${collision.key} is rejected before any destination write', () async {
      final backend = _Backend();
      for (final archive in collision.value.entries) {
        backend.put('/input/${archive.key}', _zip(archive.value));
      }
      await expectLater(
        _plan(
          backend,
          collision.value.keys.toList(),
          output,
          options: const ArchiveBatchExtractionOptions(
            folderMode: ArchiveExtractionFolderMode.shared,
          ),
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(await Directory(output).exists(), isFalse);
      expect(backend.writes, isEmpty);
    });
  }
  test('flattening collision within one archive is refused', () async {
    final backend = _Backend()
      ..put(
        '/input/a.zip',
        _zip({
          'one/same': [1],
          'two/same': [2],
        }),
      );
    await expectLater(
      _plan(
        backend,
        ['a.zip'],
        output,
        options: const ArchiveBatchExtractionOptions(flatten: true),
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(await Directory(output).exists(), isFalse);
  });

  test('unsafe members cannot be hidden by a nonmatching mask', () async {
    final backend = _Backend()
      ..put(
        '/input/a.zip',
        _zip({
          'safe.txt': [1],
          '../escape': [2],
        }),
      );
    await expectLater(
      _plan(
        backend,
        ['a.zip'],
        output,
        options: const ArchiveBatchExtractionOptions(mask: '*.txt'),
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(await Directory(output).exists(), isFalse);
    expect(await File(p.join(temp.path, 'escape')).exists(), isFalse);
  });

  test(
    'existing destination in the last archive blocks the entire preview',
    () async {
      final backend = _Backend()
        ..put(
          '/input/a.zip',
          _zip({
            'first': [1],
          }),
        )
        ..put(
          '/input/b.zip',
          _zip({
            'last': [2],
          }),
        );
      final existing = File(p.join(output, 'b/last'));
      await existing.parent.create(recursive: true);
      await existing.writeAsString('keep');
      await expectLater(
        _plan(backend, ['a.zip', 'b.zip'], output),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(await File(p.join(output, 'a/first')).exists(), isFalse);
      expect(await existing.readAsString(), 'keep');
    },
  );

  test('symbolic-link destinations are refused before writes', () async {
    final backend = _Backend()
      ..put(
        '/input/a.zip',
        _zip({
          'folder/file': [1],
        }),
      );
    final outside = await Directory(p.join(temp.path, 'elsewhere')).create();
    await Directory(p.join(output, 'a')).create(recursive: true);
    await Link(p.join(output, 'a/folder')).create(outside.path);
    await expectLater(
      _plan(backend, ['a.zip'], output),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(await outside.list().isEmpty, isTrue);
  });

  test(
    'destination revalidation before execution blocks every new write',
    () async {
      final backend = _Backend()
        ..put(
          '/input/a.zip',
          _zip({
            'first': [1],
          }),
        )
        ..put(
          '/input/b.zip',
          _zip({
            'last': [2],
          }),
        );
      final plan = await _plan(backend, ['a.zip', 'b.zip'], output);
      final conflict = File(p.join(output, 'b/last'));
      await conflict.parent.create(recursive: true);
      await conflict.writeAsString('other');
      final report = await plan.extract();
      expect(report.stopReason, ArchiveBatchExtractionStopReason.failed);
      expect(report.publishedFileCount, 0);
      expect(report.unprocessedCount, 2);
      expect(report.detail, contains('Destination exists'));
      expect(await File(p.join(output, 'a/first')).exists(), isFalse);
      expect(await conflict.readAsString(), 'other');
    },
  );

  test(
    'later runtime conflict reports already published files exactly',
    () async {
      final backend = _Backend()
        ..put(
          '/input/a.zip',
          _zip({
            'first': [1],
          }),
        )
        ..put(
          '/input/b.zip',
          _zip({
            'last': [2],
          }),
        );
      final plan = await _plan(backend, ['a.zip', 'b.zip'], output);
      final conflict = File(p.join(output, 'b/last'));
      final report = await plan.extract(
        onProgress: (progress) {
          if (progress.currentFile?.name == 'a.zip' &&
              progress.completedMembers == progress.totalMembers) {
            conflict.parent.createSync(recursive: true);
            conflict.writeAsStringSync('other');
          }
        },
      );
      expect(report.stopReason, ArchiveBatchExtractionStopReason.failed);
      expect(report.completedCount, 1);
      expect(report.publishedFileCount, 1);
      expect(report.items.last.status, ArchiveBatchExtractionStatus.failed);
      expect(await conflict.readAsString(), 'other');
      expect(await File(p.join(output, 'a/first')).readAsBytes(), [1]);
      expect(await _stages(Directory(output)), isEmpty);
    },
  );

  test('cancelling after a committed file preserves it and leaves later archives unprocessed', () async {
    final backend = _Backend()
      ..put(
        '/input/a.zip',
        _zip({
          'first': [1],
        }),
      )
      ..put(
        '/input/b.zip',
        _zip({
          'last': [2],
        }),
      );
    final plan = await _plan(backend, ['a.zip', 'b.zip'], output);
    var cancelled = false;
    final report = await plan.extract(
      isCancelled: () => cancelled,
      onProgress: (progress) {
        if (progress.publishedFiles == 1) cancelled = true;
      },
    );
    expect(report.stopReason, ArchiveBatchExtractionStopReason.cancelled);
    expect(report.completedCount, 1);
    expect(report.publishedFileCount, 1);
    expect(report.unprocessedCount, 1);
    expect(await File(p.join(output, 'a/first')).exists(), isTrue);
    expect(await File(p.join(output, 'b/last')).exists(), isFalse);
  });

  test('closing a running plan drains its owned verification before snapshot cleanup', () async {
    final backend = _Backend()
      ..put('/input/held.zip', _zip({'payload.txt': utf8.encode('held read')}));
    final local = _HeldStageLocal();
    final plan = await ArchiveBatchExtractionPlan.prepare(
      source: backend,
      files: await _files(backend, ['held.zip']),
      targetDirectory: output,
      local: local,
    );
    addTearDown(() {
      if (!local.release.isCompleted) local.release.complete();
      return plan.close();
    });
    final extraction = plan.extract();
    await local.entered.future.timeout(const Duration(seconds: 5));
    var closeCompleted = false;
    final closing = plan.close().then((_) => closeCompleted = true);
    expect(plan.isClosed, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(closeCompleted, isFalse);
    local.release.complete();
    final report = await extraction;
    await closing;
    expect(report.stopReason, ArchiveBatchExtractionStopReason.cancelled);
    expect(report.publishedFileCount, 0);
    expect(closeCompleted, isTrue);
    expect(await File(p.join(output, 'held/payload.txt')).exists(), isFalse);
    expect(await _stages(Directory(output)), isEmpty);
  });

  test('a corrupt later member never publishes its stage or erases the completed file', () async {
    final bytes = _zip({
      'good.txt': utf8.encode('good'),
      'bad.txt': utf8.encode('bad data'),
    });
    final view = ByteData.sublistView(bytes);
    var corrupted = false;
    for (var offset = 0; offset + 30 <= bytes.length; offset++) {
      if (view.getUint32(offset, Endian.little) != 0x04034b50) continue;
      final nameLength = view.getUint16(offset + 26, Endian.little);
      final extraLength = view.getUint16(offset + 28, Endian.little);
      if (offset + 30 + nameLength > bytes.length) continue;
      final name = utf8.decode(
        bytes.sublist(offset + 30, offset + 30 + nameLength),
      );
      if (name == 'bad.txt') {
        bytes[offset + 30 + nameLength + extraLength] ^= 0x40;
        corrupted = true;
        break;
      }
    }
    expect(corrupted, isTrue);
    final backend = _Backend()..put('/input/damaged.zip', bytes);
    final plan = await _plan(backend, ['damaged.zip'], output);
    final report = await plan.extract();
    expect(report.stopReason, ArchiveBatchExtractionStopReason.failed);
    expect(report.items.single.status, ArchiveBatchExtractionStatus.failed);
    expect(report.items.single.publishedFiles, [
      p.join(output, 'damaged/good.txt'),
    ]);
    expect(
      await File(p.join(output, 'damaged/good.txt')).readAsString(),
      'good',
    );
    expect(await File(p.join(output, 'damaged/bad.txt')).exists(), isFalse);
    expect(await _stages(Directory(output)), isEmpty);
    expect(backend.contents['/input/damaged.zip'], bytes);
  });

  test('declined password, duplicate selections and unmatched archives are explicit skips', () async {
    final backend = _Backend()
      ..put(
        '/input/plain.zip',
        _zip({
          'hello': [1],
        }),
      )
      ..put(
        '/input/protected.zip',
        _zip({
          'hello': [2],
        }, password: 'secret'),
      )
      ..put(
        '/input/unmatched.zip',
        _zip({
          'else': [3],
        }),
      );
    final plan = await _plan(
      backend,
      ['plain.zip', 'plain.zip', 'protected.zip', 'unmatched.zip'],
      output,
      options: const ArchiveBatchExtractionOptions(mask: 'hello'),
      password: (_, {required wrongPassword}) async => null,
    );
    expect(plan.skipped.map((skip) => skip.reason), [
      ArchiveBatchExtractionSkipReason.duplicate,
      ArchiveBatchExtractionSkipReason.passwordDeclined,
      ArchiveBatchExtractionSkipReason.noMatches,
    ]);
    final report = await plan.extract();
    expect(report.completedCount, 1);
    expect(report.skippedCount, 3);
    expect(report.unprocessedCount, 0);
    expect(report.items.map((item) => item.file.name), [
      'plain.zip',
      'plain.zip',
      'protected.zip',
      'unmatched.zip',
    ]);
  });

  test('wrong password can be retried before preview without persisting it in reports', () async {
    final backend = _Backend()
      ..put(
        '/input/protected.zip',
        _zip({
          'hello': [1, 2, 3],
        }, password: 'secret'),
      );
    final prompts = <bool>[];
    final plan = await _plan(
      backend,
      ['protected.zip'],
      output,
      password: (_, {required wrongPassword}) async {
        prompts.add(wrongPassword);
        return prompts.length == 1 ? 'wrong' : 'secret';
      },
    );
    expect(prompts, [false, true]);
    expect(backend.reads, 1);
    final report = await plan.extract();
    expect(report.completedCount, 1);
    expect(report.items.single.detail, isNull);
    expect(await File(p.join(output, 'protected/hello')).readAsBytes(), [
      1,
      2,
      3,
    ]);
  });

  test('three wrong passwords stop before creating the destination', () async {
    final backend = _Backend()
      ..put(
        '/input/protected.zip',
        _zip({
          'hello': [1],
        }, password: 'secret'),
      );
    var prompts = 0;
    await expectLater(
      _plan(
        backend,
        ['protected.zip'],
        output,
        password: (_, {required wrongPassword}) async {
          prompts++;
          return 'wrong';
        },
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(prompts, 3);
    expect(await Directory(output).exists(), isFalse);
  });

  test(
    'split 7z snapshots extract all parts through the same read-only plan',
    () async {
      final backend = _Backend();
      final parts = volumeSplitBytes(volumeReferenceSevenZip());
      for (var index = 0; index < parts.length; index++) {
        backend.put(
          '/input/fixture.7z.${(index + 1).toString().padLeft(3, '0')}',
          parts[index],
        );
      }
      final plan = await _plan(backend, ['fixture.7z.001'], output);
      expect(plan.inputBytes, 320);
      final report = await plan.extract();
      expect(report.completedCount, 1);
      expect(
        await File(p.join(output, 'fixture/first.txt')).readAsBytes(),
        volumeReferenceFirstFile(),
      );
      expect(backend.contents.length, 4);
    },
  );

  test('invalid mask, selection count, input and output budgets fail before writes', () async {
    final backend = _Backend()
      ..put('/input/a.zip', _zip({'a': List.filled(50, 1)}))
      ..put('/input/b.zip', _zip({'b': List.filled(50, 2)}));
    await expectLater(
      _plan(
        backend,
        ['a.zip'],
        output,
        options: const ArchiveBatchExtractionOptions(mask: 'a||b'),
      ),
      throwsFormatException,
    );
    await expectLater(
      _plan(backend, List.filled(129, 'a.zip'), output),
      throwsA(isA<ArchiveViewException>()),
    );
    await expectLater(
      _plan(
        backend,
        ['a.zip', 'b.zip'],
        output,
        maxInputBytes: backend.contents['/input/a.zip']!.length + 1,
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    await expectLater(
      _plan(backend, ['a.zip', 'b.zip'], output, maxOutputBytes: 75),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(await Directory(output).exists(), isFalse);
  });

  test('source revocation after preview prevents publication', () async {
    final backend = _Backend()
      ..put(
        '/input/a.zip',
        _zip({
          'a': [1],
        }),
      );
    final plan = await _plan(backend, ['a.zip'], output);
    backend.current = false;
    final report = await plan.extract();
    expect(report.stopReason, ArchiveBatchExtractionStopReason.unavailable);
    expect(report.unprocessedCount, 1);
    expect(await Directory(output).exists(), isFalse);
  });

  test(
    'pending metadata cancellation returns without waiting for a provider',
    () async {
      final backend = _Backend()
        ..put(
          '/input/a.zip',
          _zip({
            'a': [1],
          }),
        );
      final files = await _files(backend, ['a.zip']);
      backend.statGate = Completer<void>();
      var cancelled = false;
      final pending = ArchiveBatchExtractionPlan.prepare(
        source: backend,
        files: files,
        targetDirectory: output,
        isCancelled: () => cancelled,
      );
      final assertion = expectLater(pending, throwsA(isA<Exception>()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      cancelled = true;
      await assertion.timeout(const Duration(seconds: 2));
      backend.statGate!.complete();
      expect(await Directory(output).exists(), isFalse);
    },
  );

  test(
    'public snapshot seam validates without writes and reports committed files',
    () async {
      final archive = await openViewerArchive(
        _zip({
          'a': [1],
        }),
        name: 'a.zip',
      );
      addTearDown(archive.close);
      final destinations = await ArchiveService.extractOpenedSnapshot(
        archive,
        output,
        validateOnly: true,
      );
      expect(destinations, [p.join(output, 'a')]);
      expect(await Directory(output).exists(), isFalse);
      final published = <String>[];
      expect(
        await ArchiveService.extractOpenedSnapshot(
          archive,
          output,
          onFilePublished: published.add,
        ),
        destinations,
      );
      expect(published, destinations);
      expect(archive.isClosed, isFalse);
    },
  );
}
