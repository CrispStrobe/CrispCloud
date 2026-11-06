import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_bytes_loader.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Backend extends Fake implements FileOperationBackend {
  @override
  bool isCurrent = true;
  bool closed = false;
  int reads = 0;
  void Function(int)? onChunk;
  @override
  Stream<List<int>> readFile(FileItem file) async* {
    try {
      for (var i = 0; i < 5; i++) {
        reads++;
        onChunk?.call(i);
        yield [i, i];
      }
    } finally {
      closed = true;
    }
  }
}

void main() {
  final file = FileItem(name: 'data', path: '/data', isFolder: false);
  test(
    'overflow stops and closes a stream even when listing size is wrong',
    () async {
      final backend = _Backend();
      await expectLater(
        readFileBytesBounded(backend, file.copyWith(size: 1), maxBytes: 5),
        throwsA(isA<FileBytesTooLargeException>()),
      );
      expect(backend.reads, 3);
      expect(backend.closed, isTrue);
    },
  );
  test('account changes and cancellation stop the captured stream', () async {
    final backend = _Backend()..onChunk = (_) {};
    backend.onChunk = (i) {
      if (i == 1) backend.isCurrent = false;
    };
    await expectLater(
      readFileBytesBounded(backend, file, maxBytes: 100),
      throwsA(isA<FileBytesLoadException>()),
    );
    expect(backend.reads, 2);
    expect(backend.closed, isTrue);
    final cancelled = _Backend();
    await expectLater(
      readFileBytesBounded(
        cancelled,
        file,
        maxBytes: 100,
        isCancelled: () => true,
      ),
      throwsA(isA<FileBytesLoadException>()),
    );
    expect(cancelled.reads, 0);
  });
  test('normal reads retain exact bytes and reject known oversized items before I/O', () async {
    final backend = _Backend();
    expect(await readFileBytesBounded(backend, file, maxBytes: 10), [
      0,
      0,
      1,
      1,
      2,
      2,
      3,
      3,
      4,
      4,
    ]);
    final large = _Backend();
    await expectLater(
      readFileBytesBounded(large, file.copyWith(size: 100), maxBytes: 10),
      throwsA(isA<FileBytesTooLargeException>()),
    );
    expect(large.reads, 0);
  });
}
