import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as legacy;
import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_service.dart';
import 'package:crisp_cloud/services/archive_streaming_writer.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('streamed-extraction-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  for (final format in <ArchiveEndpointFormat, String>{
    ArchiveEndpointFormat.zip: 'zip',
    ArchiveEndpointFormat.sevenZip: '7z',
    ArchiveEndpointFormat.tarGzip: 'tgz',
  }.entries) {
    test(
      '${format.value} extracts and lists a 65 MiB member while byte APIs stay bounded',
      () async {
        const size = 65 * 1024 * 1024 + 17;
        final packed = await _writeArchive(
          temp,
          'large.${format.value}',
          format.key,
          [_entry('large.bin', size: size)],
        );
        final listed = await ArchiveService.listArchiveContents(
          packed.path,
          '',
        );
        expect(listed, hasLength(1));
        expect(listed.single.name, 'large.bin');
        expect(listed.single.size, size);

        final progress = <List<int>>[];
        final target = p.join(temp.path, 'native');
        final result = await ArchiveService.extractArchive(
          packed.path,
          target,
          onProgress: (completed, total) => progress.add([completed, total]),
        );
        expect(result, [p.join(target, 'large.bin')]);
        expect(await File(result.single).length(), size);
        expect(
          await sha256.bind(File(result.single).openRead()).single,
          await sha256.bind(_payload(size)).single,
        );
        expect(progress, [
          [1, 1],
        ]);
        expect(await _privateStages(Directory(target)), isEmpty);

        // The compressed fixture is small; only native disk extraction opts
        // into a large decoded member. Byte and preview APIs retain 64 MiB.
        final bytes = await packed.readAsBytes();
        expect(bytes.length, lessThan(kArchiveReadLimit));
        final boundedTarget = p.join(temp.path, 'bounded');
        await expectLater(
          ArchiveService.extractArchiveBytes(packed.path, bytes, boundedTarget),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(await Directory(boundedTarget).exists(), isFalse);
        await expectLater(
          ArchiveService.extractArchiveEntry(packed.path, 'large.bin'),
          throwsA(isA<ArchiveViewException>()),
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }

  test(
    'folder selection keeps its full hierarchy and empty directories',
    () async {
      final packed = await _writeArchive(
        temp,
        'selected.zip',
        ArchiveEndpointFormat.zip,
        [
          _entry('docs/sub/report.txt', bytes: [1, 2, 3]),
          ArchiveWriteEntry(path: 'docs/empty', isDirectory: true, size: 0),
          _entry('outside.txt', bytes: [9]),
        ],
      );
      final target = p.join(temp.path, 'out');
      final progress = <List<int>>[];
      final result = await ArchiveService.extractArchive(
        packed.path,
        target,
        selectedPaths: {'docs/'},
        onProgress: (completed, total) => progress.add([completed, total]),
      );
      expect(result, [p.join(target, 'docs', 'sub', 'report.txt')]);
      expect(await File(result.single).readAsBytes(), [1, 2, 3]);
      expect(await Directory(p.join(target, 'docs', 'empty')).exists(), isTrue);
      expect(await File(p.join(target, 'outside.txt')).exists(), isFalse);
      expect(progress, [
        [1, 2],
        [2, 2],
      ]);

      final singleTarget = p.join(temp.path, 'single');
      expect(
        await ArchiveService.extractArchive(
          packed.path,
          singleTarget,
          selectedPaths: {'docs/sub/report.txt'},
        ),
        [p.join(singleTarget, 'docs', 'sub', 'report.txt')],
      );
    },
  );

  test(
    'filenames with spaces, Unicode and shell characters remain literal',
    () async {
      const name = r"$(touch unexpected); 'quoted' [a] 🚀.txt";
      final packed = await _writeArchive(
        temp,
        'literal.zip',
        ArchiveEndpointFormat.zip,
        [
          _entry(name, bytes: [3, 1, 4]),
        ],
      );
      final target = Directory(p.join(temp.path, 'literal'));
      final result = await ArchiveService.extractArchive(
        packed.path,
        target.path,
      );
      expect(result, [p.join(target.path, name)]);
      expect(await File(result.single).readAsBytes(), [3, 1, 4]);
      expect(
        (await target.list().toList()).map((entry) => p.basename(entry.path)),
        [name],
      );
    },
  );

  for (final invalid in <String, List<String>>{
    'traversal': ['safe.txt', '../escape.txt'],
    'duplicate destination': ['same.txt', './same.txt'],
    'file as parent': ['parent', 'parent/child.txt'],
  }.entries) {
    test('${invalid.key} is rejected before creating any output', () async {
      final archive = legacy.Archive();
      for (final name in invalid.value) {
        archive.addFile(legacy.ArchiveFile(name, 1, [1]));
      }
      final packed = File(p.join(temp.path, 'unsafe.zip'));
      await packed.writeAsBytes(legacy.ZipEncoder().encode(archive));
      final target = p.join(temp.path, 'out');
      await expectLater(
        ArchiveService.extractArchive(packed.path, target),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(await Directory(target).exists(), isFalse);
      expect(await File(p.join(temp.path, 'escape.txt')).exists(), isFalse);
    });
  }

  test('unsafe selection is rejected before creating any output', () async {
    final packed = await _writeArchive(
      temp,
      'selection.zip',
      ArchiveEndpointFormat.zip,
      [
        _entry('safe.txt', bytes: [1]),
      ],
    );
    final target = p.join(temp.path, 'out');
    await expectLater(
      ArchiveService.extractArchive(
        packed.path,
        target,
        selectedPaths: {'../safe.txt'},
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(await Directory(target).exists(), isFalse);
  });

  test(
    'a symbolic link in the selected destination is refused',
    () async {
      final packed = await _writeArchive(
        temp,
        'link.zip',
        ArchiveEndpointFormat.zip,
        [
          _entry('linked/file.txt', bytes: [1]),
        ],
      );
      final target = await Directory(p.join(temp.path, 'out')).create();
      final outside = await Directory(p.join(temp.path, 'outside')).create();
      await Link(p.join(target.path, 'linked')).create(outside.path);
      await expectLater(
        ArchiveService.extractArchive(packed.path, target.path),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(await outside.list().toList(), isEmpty);
    },
    skip: Platform.isWindows ? 'Creating symlinks requires privileges.' : false,
  );

  test('existing files require explicit overwrite and successful staged verification', () async {
    final packed = await _writeArchive(
      temp,
      'replace.zip',
      ArchiveEndpointFormat.zip,
      [
        _entry('victim.txt', bytes: [4, 5, 6]),
      ],
    );
    final target = await Directory(p.join(temp.path, 'out')).create();
    final original = File(p.join(target.path, 'victim.txt'));
    await original.writeAsString('original');
    await expectLater(
      ArchiveService.extractArchive(packed.path, target.path),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(await original.readAsString(), 'original');
    expect(
      await ArchiveService.extractArchive(
        packed.path,
        target.path,
        overwrite: true,
      ),
      [original.path],
    );
    expect(await original.readAsBytes(), [4, 5, 6]);
    expect(await _privateStages(target), isEmpty);
  });

  for (final damage in ['payload CRC', 'truncated container']) {
    test('$damage cannot replace an existing destination', () async {
      final packed = await _writeArchive(
        temp,
        'broken.zip',
        ArchiveEndpointFormat.zip,
        [
          _entry('victim.txt', bytes: [1, 2, 3, 4]),
        ],
        level: 0,
      );
      final bytes = await packed.readAsBytes();
      if (damage == 'payload CRC') {
        final header = ByteData.sublistView(bytes);
        final body =
            30 +
            header.getUint16(26, Endian.little) +
            header.getUint16(28, Endian.little);
        bytes[body] ^= 0xff;
        await packed.writeAsBytes(bytes);
      } else {
        await packed.writeAsBytes(bytes.sublist(0, bytes.length - 9));
      }
      final target = await Directory(p.join(temp.path, 'out')).create();
      final original = File(p.join(target.path, 'victim.txt'));
      await original.writeAsString('original');
      await expectLater(
        ArchiveService.extractArchive(
          packed.path,
          target.path,
          overwrite: true,
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(await original.readAsString(), 'original');
      expect(await _privateStages(target), isEmpty);
    });
  }

  test('cancelling an active stage keeps the existing destination', () async {
    final packed = await _writeArchive(
      temp,
      'cancel.zip',
      ArchiveEndpointFormat.zip,
      [_entry('victim.bin', size: 8 * 1024 * 1024)],
      level: 0,
    );
    final target = await Directory(p.join(temp.path, 'out')).create();
    final original = File(p.join(target.path, 'victim.bin'));
    await original.writeAsString('original');
    var cancelled = false;
    var stagedBytesObserved = 0;
    bool isCancelled() {
      if (cancelled) return true;
      for (final entity in target.listSync(followLinks: false)) {
        if (entity is! Directory ||
            !p.basename(entity.path).startsWith('.crisp-transfer-')) {
          continue;
        }
        final payload = File(p.join(entity.path, 'payload'));
        if (payload.existsSync() && payload.lengthSync() >= 128 * 1024) {
          stagedBytesObserved = payload.lengthSync();
          cancelled = true;
          return true;
        }
      }
      return false;
    }

    expect(
      await ArchiveService.extractArchive(
        packed.path,
        target.path,
        overwrite: true,
        isCancelled: isCancelled,
      ),
      isEmpty,
    );
    expect(stagedBytesObserved, greaterThan(0));
    expect(await original.readAsString(), 'original');
    expect(await _privateStages(target), isEmpty);
  });

  test('cancellation between members returns completed files only', () async {
    final packed = await _writeArchive(
      temp,
      'between.zip',
      ArchiveEndpointFormat.zip,
      [
        _entry('first.txt', bytes: [1]),
        _entry('second.txt', bytes: [2]),
      ],
    );
    final target = await Directory(p.join(temp.path, 'out')).create();
    final second = File(p.join(target.path, 'second.txt'));
    await second.writeAsString('original');
    var cancelled = false;
    final progress = <List<int>>[];
    final result = await ArchiveService.extractArchive(
      packed.path,
      target.path,
      overwrite: true,
      isCancelled: () => cancelled,
      onProgress: (completed, total) {
        progress.add([completed, total]);
        cancelled = true;
      },
    );
    expect(result, [p.join(target.path, 'first.txt')]);
    expect(await File(result.single).readAsBytes(), [1]);
    expect(await second.readAsString(), 'original');
    expect(progress, [
      [1, 2],
    ]);
    expect(await _privateStages(target), isEmpty);
  });

  test('extraction cannot overwrite its own source archive', () async {
    final packed = await _writeArchive(
      temp,
      'source.zip',
      ArchiveEndpointFormat.zip,
      [
        _entry('source.zip', bytes: [1]),
      ],
    );
    final original = await sha256.bind(packed.openRead()).single;
    await expectLater(
      ArchiveService.extractArchive(packed.path, temp.path, overwrite: true),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(await sha256.bind(packed.openRead()).single, original);
    expect(await _privateStages(temp), isEmpty);
  });
}

ArchiveWriteEntry _entry(String path, {List<int>? bytes, int? size}) {
  final length = size ?? bytes!.length;
  return ArchiveWriteEntry(
    path: path,
    isDirectory: false,
    size: length,
    modified: DateTime.utc(2026, 11, 12, 1, 2, 3),
    mode: 0x1a4,
    readChunks: bytes == null
        ? () => _payload(length)
        : () => Stream.value(bytes),
  );
}

Stream<List<int>> _payload(int size) async* {
  final chunk = Uint8List.fromList(List.generate(64 * 1024, (i) => i % 251));
  for (var offset = 0; offset < size; offset += chunk.length) {
    final remaining = size - offset;
    yield remaining >= chunk.length
        ? chunk
        : Uint8List.sublistView(chunk, 0, remaining);
  }
}

Future<File> _writeArchive(
  Directory directory,
  String name,
  ArchiveEndpointFormat format,
  List<ArchiveWriteEntry> entries, {
  int level = 6,
}) async {
  final file = File(p.join(directory.path, name));
  final writer = await file.open(mode: FileMode.write);
  try {
    await writeStreamingArchiveEntries(
      format,
      entries,
      maxOutputBytes: kArchiveStreamingLimit,
      level: level,
      sink: (chunk) async {
        await writer.writeFrom(chunk);
      },
    );
    await writer.flush();
  } finally {
    await writer.close();
  }
  return file;
}

Future<List<FileSystemEntity>> _privateStages(Directory directory) async =>
    (await directory.list(recursive: true, followLinks: false).toList())
        .where((entry) => p.basename(entry.path).startsWith('.crisp-transfer-'))
        .toList();
