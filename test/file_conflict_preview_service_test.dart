import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_conflict_preview_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'support/conflict_preview_backend.dart';

Uint8List _png(int width, int height, {int red = 120}) {
  final pixels = image.Image(width: width, height: height, numChannels: 4);
  image.fill(pixels, color: image.ColorRgba8(red, 30, 80, 255));
  return Uint8List.fromList(image.encodePng(pixels));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = FileConflictPreviewService();
  late ConflictPreviewBackend backend;

  setUp(() {
    final bytes = _png(24, 12);
    backend = ConflictPreviewBackend(
      file: FileItem(
        name: 'image.png',
        path: '/image.png',
        isFolder: false,
        size: bytes.length,
        uuid: 'original',
        updatedAt: DateTime.utc(2026, 1, 1),
        metadata: {'eTag': 'v1', 'mimeType': 'image/png'},
      ),
      bytes: bytes,
    );
  });
  tearDown(() => expect(backend.writes, 0));

  FileConflictPreviewTarget target() =>
      FileConflictPreviewTarget(backend, backend.file);
  Matcher problem(FileConflictPreviewProblem value) => throwsA(
    isA<FileConflictPreviewException>().having(
      (e) => e.problem,
      'problem',
      value,
    ),
  );

  test(
    'decodes real image bytes, retains dimensions and caps thumbnail pixels',
    () async {
      backend.bytes = _png(1200, 600);
      backend.file = backend.file.copyWith(size: backend.bytes.length);
      final result = await service.load(target());
      expect((result.width, result.height), (1200, 600));
      expect(result.animated, isFalse);
      final decoded = image.decodePng(result.png)!;
      expect((decoded.width, decoded.height), (384, 192));
      expect(
        result.png.length,
        lessThanOrEqualTo(FileConflictPreviewService.maxThumbnailBytes),
      );
      expect(backend.reads, 1);
      expect(backend.stats, 3);
    },
  );

  test(
    'identical paths on different captured sources do not share previews',
    () async {
      final otherBytes = _png(24, 12, red: 220);
      final other = ConflictPreviewBackend(
        file: backend.file.copyWith(size: otherBytes.length),
        bytes: otherBytes,
        storageLabel: 'Other account',
      );
      final left = await service.load(target());
      final right = await service.load(
        FileConflictPreviewTarget(other, other.file),
      );
      expect(image.decodePng(left.png)!.getPixel(0, 0).r, 120);
      expect(image.decodePng(right.png)!.getPixel(0, 0).r, 220);
      expect(other.reads, 1);
      expect(other.writes, 0);
    },
  );

  test('known byte limits stop before any source request', () async {
    backend.file = backend.file.copyWith(
      size: FileConflictPreviewService.maxInputBytes + 1,
    );
    await expectLater(
      service.load(target()),
      problem(FileConflictPreviewProblem.tooLarge),
    );
    expect(backend.stats, 0);
    expect(backend.reads, 0);
  });

  test('storage without bounded downloads is not read automatically', () async {
    backend.bounded = false;
    await expectLater(
      service.load(target()),
      problem(FileConflictPreviewProblem.unsupportedStorage),
    );
    expect(backend.stats, 0);
    expect(backend.reads, 0);
  });

  test('unknown-length stream is bounded and cancelled on overflow', () async {
    backend.file = FileItem(
      name: 'image.png',
      path: '/image.png',
      isFolder: false,
    );
    var cancelled = false;
    backend.readOverride = (_) async* {
      try {
        yield Uint8List(FileConflictPreviewService.maxInputBytes);
        yield [1];
        fail('Overflow must cancel the remaining source.');
      } finally {
        cancelled = true;
      }
    };
    await expectLater(
      service.load(target()),
      problem(FileConflictPreviewProblem.tooLarge),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cancelled, isTrue);
  });

  test(
    'dimension headers are rejected before decoding a large raster',
    () async {
      final bytes = _png(1, 1);
      final data = ByteData.sublistView(bytes);
      data.setUint32(16, 5000);
      data.setUint32(20, 4000);
      data.setUint32(29, archive.getCrc32(bytes.sublist(12, 29)));
      backend.bytes = bytes;
      backend.file = backend.file.copyWith(size: bytes.length);
      await expectLater(
        service.load(target()),
        problem(FileConflictPreviewProblem.dimensionsTooLarge),
      );
    },
  );

  test(
    'very long image edge is rejected even below the pixel budget',
    () async {
      backend.bytes = _png(8193, 1);
      backend.file = backend.file.copyWith(size: backend.bytes.length);
      await expectLater(
        service.load(target()),
        problem(FileConflictPreviewProblem.dimensionsTooLarge),
      );
    },
  );

  test('corrupt bytes are reported without a partial preview', () async {
    backend.bytes = Uint8List.fromList([1, 2, 3]);
    backend.file = backend.file.copyWith(size: 3);
    await expectLater(
      service.load(target()),
      problem(FileConflictPreviewProblem.invalidImage),
    );
  });

  for (final file in [
    FileItem(name: 'notes.txt', path: '/notes.txt', isFolder: false),
    FileItem(name: 'images.png', path: '/images.png', isFolder: true),
    FileItem(
      name: 'linked.png',
      path: '/linked.png',
      isFolder: false,
      isSymlink: true,
    ),
  ]) {
    test('unsupported entry ${file.name} does not read or follow it', () async {
      backend.file = file;
      await expectLater(
        service.load(target()),
        problem(FileConflictPreviewProblem.unsupported),
      );
      expect(backend.stats, 0);
      expect(backend.reads, 0);
    });
  }

  test('reported image content type enables an extensionless image', () async {
    backend.file = backend.file.copyWith(
      name: 'image',
      path: '/image',
      metadata: {'contentType': 'image/png'},
    );
    final result = await service.load(target());
    expect(result.width, 24);
  });

  test(
    'captured version cannot be mutated through provider metadata',
    () async {
      final metadata = {'eTag': 'v1'};
      backend.file = backend.file.copyWith(metadata: metadata);
      final captured = target();
      metadata['eTag'] = 'v2';
      expect(captured.file.metadata!['eTag'], 'v1');
      await expectLater(
        service.load(captured),
        problem(FileConflictPreviewProblem.sourceChanged),
      );
      expect(backend.reads, 0);
    },
  );

  for (final change in ['uuid', 'size', 'time', 'version']) {
    test('changed $change during a read discards the decoded result', () async {
      backend.readOverride = (_) async* {
        yield backend.bytes;
        backend.file = switch (change) {
          'uuid' => backend.file.copyWith(uuid: 'replacement'),
          'size' => backend.file.copyWith(size: backend.bytes.length + 1),
          'time' => backend.file.copyWith(updatedAt: DateTime.utc(2026, 1, 2)),
          _ => backend.file.copyWith(metadata: {'eTag': 'v2'}),
        };
      };
      await expectLater(
        service.load(target()),
        problem(FileConflictPreviewProblem.sourceChanged),
      );
    });
  }

  test('version is checked again after image decoding', () async {
    backend.statOverride = (_) async => backend.stats == 3
        ? backend.file.copyWith(metadata: {'eTag': 'after-decode'})
        : backend.file;
    await expectLater(
      service.load(target()),
      problem(FileConflictPreviewProblem.sourceChanged),
    );
  });

  test('a shorter stream cannot masquerade as the reviewed file', () async {
    backend.readOverride = (_) => Stream.value(backend.bytes.sublist(1));
    await expectLater(
      service.load(target()),
      problem(FileConflictPreviewProblem.sourceChanged),
    );
  });

  test('source loss before loading does not open a stream', () async {
    final captured = target();
    backend.current = false;
    await expectLater(
      service.load(captured),
      problem(FileConflictPreviewProblem.sourceUnavailable),
    );
    expect(backend.reads, 0);
  });

  test('a replacement session cannot deliver a same-path preview', () async {
    backend.readOverride = (_) async* {
      backend.session = Object();
      yield backend.bytes;
    };
    await expectLater(
      service.load(target()),
      problem(FileConflictPreviewProblem.sourceUnavailable),
    );
  });

  test('cancellation interrupts a stalled source read', () async {
    var cancelled = false;
    final input = StreamController<List<int>>(onCancel: () => cancelled = true);
    backend.readOverride = (_) => input.stream;
    final control = FileOperationControl();
    final pending = service.load(target(), control: control);
    final assertion = expectLater(
      pending,
      problem(FileConflictPreviewProblem.cancelled),
    );
    while (backend.reads == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    control.cancel();
    await assertion;
    expect(cancelled, isTrue);
    await input.close();
  });

  test(
    'deadline cancels a stalled stream without waiting for provider cleanup',
    () async {
      var cancelled = false;
      final input = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      backend.readOverride = (_) => input.stream;
      await expectLater(
        service.load(target(), timeout: const Duration(milliseconds: 20)),
        problem(FileConflictPreviewProblem.timedOut),
      );
      expect(cancelled, isTrue);
      await input.close();
    },
  );

  test(
    'cancellation also detaches a pending stat and ignores its late reply',
    () async {
      final delayed = Completer<FileItem?>();
      backend.statOverride = (_) => delayed.future;
      final control = FileOperationControl();
      final assertion = expectLater(
        service.load(target(), control: control),
        problem(FileConflictPreviewProblem.cancelled),
      );
      control.cancel();
      await assertion;
      delayed.complete(backend.file);
      await Future<void>.delayed(Duration.zero);
      expect(backend.reads, 0);
    },
  );

  test('provider errors never expose request URLs or secrets', () async {
    backend.statOverride = (_) =>
        Future.error(StateError('https://secret:password@host/?token=hidden'));
    try {
      await service.load(target());
      fail('Expected a preview failure.');
    } catch (error) {
      expect(error, isA<FileConflictPreviewException>());
      expect('$error', isNot(contains('hidden')));
      expect('$error', isNot(contains('password')));
    }
  });

  test('review details use a bounded allowlist rather than raw metadata', () {
    final file = backend.file.copyWith(
      metadata: {
        'mimeType': 'image/png',
        'storageClass': 'STANDARD',
        'eTag': 'version-1',
        'sha256Hash': 'abc123',
        'createdAt': DateTime.utc(2026, 1, 1),
        'password': 'hidden-password',
        'accessToken': 'hidden-token',
        'downloadUrl': 'https://example.test/?token=hidden',
        'metadata': {'privateKey': 'hidden-key', 'contentType': 'ignored'},
      },
    );
    final details = fileConflictReviewDetails(file);
    expect(details['Content type'], 'image/png');
    expect(details['Storage class'], 'STANDARD');
    expect(details['Version'], 'version-1');
    expect(details['Reported checksum'], 'SHA-256 abc123');
    expect(details['Created'], '2026-01-01T00:00:00.000Z');
    expect(details.toString(), isNot(contains('hidden')));
    final long = fileConflictReviewDetails(
      file.copyWith(metadata: {'eTag': '${'x' * 500}\nsecret'}),
    );
    expect(long['Version']!.length, lessThanOrEqualTo(161));
    expect(long['Version'], isNot(contains('\n')));
  });
}
