import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_package_readers.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_viewer_source.dart';
import 'package:crisp_cloud/services/file_bytes_loader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_package_fixtures.dart';

class _InstrumentedSource extends ViewBytesSource {
  _InstrumentedSource(int length, {this.prefix}) : super.memory(Uint8List(0)) {
    size = length;
  }
  final Uint8List? prefix;
  final reads = <({int offset, int length})>[];
  int validations = 0, disposals = 0;
  bool shortRead = false;
  Future<void> Function(int call)? onValidate;
  void Function(int call)? onRead;

  @override
  bool get isStreamed => true;
  @override
  Future<void> validateUnchanged() async {
    if (disposals != 0) throw StateError('Owner was disposed.');
    final call = ++validations;
    await onValidate?.call(call);
  }

  @override
  Uint8List readSync(int offset, int length) {
    if (disposals != 0) throw StateError('Owner was disposed.');
    reads.add((offset: offset, length: length));
    onRead?.call(reads.length);
    final result = Uint8List(shortRead && length > 0 ? length - 1 : length);
    for (var at = 0; at < result.length; at++) {
      final absolute = offset + at;
      result[at] = prefix != null && absolute < prefix!.length
          ? prefix![absolute]
          : absolute % 251;
    }
    return result;
  }

  @override
  void dispose() {
    disposals++;
  }
}

void main() {
  test(
    'borrows memory without disposing it and returns independent bytes',
    () async {
      final data = Uint8List.fromList([1, 2, 3, 4]);
      final owner = ViewBytesSource.memory(data);
      await owner.open();
      addTearDown(owner.dispose);
      final source = ArchiveViewerSource(
        owner,
        isCurrent: () => true,
        name: 'memory.ar',
      );
      expect(source.name, 'memory.ar');
      expect(source.length, 4);
      final bytes = await source.read(1, 2);
      data[1] = 90;
      expect(bytes, [2, 3]);
      bytes[1] = 80;
      expect(data[2], 3);
      await source.close();
      await source.close();
      expect(owner.readSync(0, 4), [1, 90, 3, 4]);
      await expectLater(
        source.read(0, 1),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );

  test('captures the original length and rejects source resizing', () async {
    final owner = _InstrumentedSource(100);
    final source = ArchiveViewerSource(owner, isCurrent: () => true);
    addTearDown(source.close);
    owner.size = 101;
    expect(source.length, 100);
    await expectLater(source.read(0, 1), throwsA(isA<ArchiveViewException>()));
    expect(owner.reads, isEmpty);
  });

  test('validates exact ranges instead of using viewer clamping', () async {
    final owner = _InstrumentedSource(100);
    final source = ArchiveViewerSource(owner, isCurrent: () => true);
    addTearDown(source.close);
    await expectLater(source.read(-1, 1), throwsArgumentError);
    await expectLater(source.read(0, -1), throwsArgumentError);
    await expectLater(source.read(99, 2), throwsA(isA<ArchiveViewException>()));
    await expectLater(
      source.read(101, 0),
      throwsA(isA<ArchiveViewException>()),
    );
    await expectLater(
      source.read(9007199254740991, 2),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(owner.reads, isEmpty);
    expect(await source.read(100, 0), isEmpty);
    expect(await source.read(98, 2), [98, 99]);
  });

  test('bounds each request before allocation or owner I/O', () async {
    final owner = _InstrumentedSource(200);
    final source = ArchiveViewerSource(
      owner,
      isCurrent: () => true,
      maxReadBytes: 16,
    );
    addTearDown(source.close);
    await expectLater(source.read(0, 17), throwsA(isA<ArchiveViewException>()));
    expect(owner.validations, 0);
    expect(owner.reads, isEmpty);
    expect((await source.read(0, 16)).length, 16);
  });

  test('uses bounded windows for a larger request', () async {
    final owner = _InstrumentedSource(1024 * 1024);
    final source = ArchiveViewerSource(owner, isCurrent: () => true);
    addTearDown(source.close);
    const count = 600 * 1024;
    final bytes = await source.read(13, count);
    expect(owner.reads, [
      (offset: 13, length: 256 * 1024),
      (offset: 13 + 256 * 1024, length: 256 * 1024),
      (offset: 13 + 512 * 1024, length: 88 * 1024),
    ]);
    expect(bytes.length, count);
    expect(bytes.first, 13);
    expect(bytes.last, (13 + count - 1) % 251);
    expect(owner.validations, 2);
  });

  test(
    'serializes overlapping positional requests across async validation',
    () async {
      final owner = _InstrumentedSource(1000);
      var active = 0, maximumActive = 0;
      owner.onValidate = (_) async {
        active++;
        if (active > maximumActive) maximumActive = active;
        await Future<void>.delayed(Duration.zero);
        active--;
      };
      final source = ArchiveViewerSource(owner, isCurrent: () => true);
      addTearDown(source.close);
      final results = await Future.wait([
        source.read(50, 10),
        source.read(3, 8),
        source.read(55, 5),
      ]);
      expect(results[0], List.generate(10, (i) => 50 + i));
      expect(results[1], List.generate(8, (i) => 3 + i));
      expect(results[2], List.generate(5, (i) => 55 + i));
      expect(maximumActive, 1);
      expect(owner.reads.map((r) => r.offset), [50, 3, 55]);
    },
  );

  test('close invalidates immediately and drains pending work without disposing owner', () async {
    final owner = _InstrumentedSource(100);
    final entered = Completer<void>(), resume = Completer<void>();
    owner.onValidate = (call) async {
      if (call == 1) {
        entered.complete();
        await resume.future;
      }
    };
    final source = ArchiveViewerSource(owner, isCurrent: () => true);
    final first = expectLater(
      source.read(0, 1),
      throwsA(isA<ArchiveViewException>()),
    );
    await entered.future;
    final second = expectLater(
      source.read(1, 1),
      throwsA(isA<ArchiveViewException>()),
    );
    var drained = false;
    final closed = source.close().then((_) {
      drained = true;
    });
    expect(source.isClosed, isTrue);
    expect(drained, isFalse);
    expect(owner.disposals, 0);
    resume.complete();
    await Future.wait([first, second, closed]);
    expect(drained, isTrue);
    expect(owner.reads, isEmpty);
    expect(owner.disposals, 0);
  });

  test('mode or load change during validation prevents owner reads', () async {
    var current = true;
    final owner = _InstrumentedSource(100);
    owner.onValidate = (_) async {
      current = false;
    };
    final source = ArchiveViewerSource(owner, isCurrent: () => current);
    addTearDown(source.close);
    await expectLater(source.read(0, 10), throwsA(isA<ArchiveViewException>()));
    expect(owner.reads, isEmpty);
  });

  test('source identity change between windows stops large reads', () async {
    var current = true;
    final owner = _InstrumentedSource(1024 * 1024);
    owner.onRead = (_) {
      current = false;
    };
    final source = ArchiveViewerSource(owner, isCurrent: () => current);
    addTearDown(source.close);
    await expectLater(
      source.read(0, 512 * 1024),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(owner.reads.length, 1);
    expect(owner.reads.single.length, 256 * 1024);
  });

  test('post-read validation refuses changed file data', () async {
    final owner = _InstrumentedSource(100);
    owner.onValidate = (call) async {
      if (call == 2) {
        throw StateError('File changed after its bytes were read.');
      }
    };
    final source = ArchiveViewerSource(owner, isCurrent: () => true);
    addTearDown(source.close);
    await expectLater(source.read(0, 10), throwsA(isA<ArchiveViewException>()));
    expect(owner.reads.length, 1);
    expect(owner.validations, 2);
  });

  test('late close after reading prevents returning obsolete bytes', () async {
    final owner = _InstrumentedSource(100);
    late ArchiveViewerSource source;
    owner.onValidate = (call) async {
      if (call == 2) unawaited(source.close());
    };
    source = ArchiveViewerSource(owner, isCurrent: () => true);
    await expectLater(source.read(0, 10), throwsA(isA<ArchiveViewException>()));
    await source.close();
    expect(owner.reads.length, 1);
    expect(owner.disposals, 0);
  });

  test('owner disposal is reported as an archive error', () async {
    final owner = _InstrumentedSource(100);
    final source = ArchiveViewerSource(owner, isCurrent: () => true);
    addTearDown(source.close);
    owner.dispose();
    await expectLater(source.read(0, 1), throwsA(isA<ArchiveViewException>()));
  });

  test('short reads fail without poisoning subsequent requests', () async {
    final owner = _InstrumentedSource(100)..shortRead = true;
    final source = ArchiveViewerSource(owner, isCurrent: () => true);
    addTearDown(source.close);
    await expectLater(source.read(1, 4), throwsA(isA<ArchiveViewException>()));
    owner.shortRead = false;
    expect(await source.read(1, 4), [1, 2, 3, 4]);
  });

  test('a failed parser closes only its borrowed adapter, allowing a fresh attempt', () async {
    final bytes = Uint8List.fromList(ascii.encode('broken!!'));
    final owner = ViewBytesSource.memory(bytes);
    await owner.open();
    addTearDown(owner.dispose);
    final first = ArchiveViewerSource(owner, isCurrent: () => true);
    await expectLater(
      openArArchive(first, maxMemberBytes: 1024),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(first.isClosed, isTrue);
    expect(owner.readSync(0, 8), bytes);
    final retry = ArchiveViewerSource(owner, isCurrent: () => true);
    addTearDown(retry.close);
    expect(await retry.read(0, 8), bytes);
  });

  test('closing one borrowing adapter leaves a second one usable', () async {
    final owner = _InstrumentedSource(100);
    final first = ArchiveViewerSource(owner, isCurrent: () => true);
    final second = ArchiveViewerSource(owner, isCurrent: () => true);
    addTearDown(second.close);
    await first.close();
    expect(await second.read(5, 2), [5, 6]);
    expect(owner.disposals, 0);
  });

  test(
    'lists a large container without reading or allocating its payload',
    () async {
      const payloadSize = 256 * 1024 * 1024;
      final prefix = arFixture([const PackageFixtureEntry('payload.bin', [])]);
      prefix.setRange(
        56,
        66,
        ascii.encode(payloadSize.toString().padRight(10)),
      );
      final owner = _InstrumentedSource(
        prefix.length + payloadSize,
        prefix: prefix,
      );
      final source = ArchiveViewerSource(
        owner,
        isCurrent: () => true,
        name: 'large.ar',
      );
      final archive = await openArArchive(
        source,
        maxMemberBytes: kArchiveReadLimit,
      );
      expect(source.length, greaterThan(kArchiveReadLimit));
      expect(archive.members.single.size, payloadSize);
      expect(owner.reads.every((read) => read.length <= 60), isTrue);
      await expectLater(
        archive.readMember(archive.members.single),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(owner.reads.every((read) => read.length <= 60), isTrue);
      await archive.close();
      expect(source.isClosed, isTrue);
      expect(owner.disposals, 0);
    },
  );

  test(
    'refuses invalid adapter configuration without taking source ownership',
    () {
      final owner = _InstrumentedSource(100);
      expect(
        () =>
            ArchiveViewerSource(owner, isCurrent: () => true, maxReadBytes: 0),
        throwsArgumentError,
      );
      owner.size = -1;
      expect(
        () => ArchiveViewerSource(owner, isCurrent: () => true),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(owner.disposals, 0);
    },
  );
}
