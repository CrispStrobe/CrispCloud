import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/file_bytes_loader.dart';
import 'package:crisp_cloud/services/viewer_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('viewer-search-'),
  );
  tearDown(() => root.delete(recursive: true));
  Uint8List pattern(String text) => Uint8List.fromList(utf8.encode(text));

  test(
    'a real disk match after 64 MiB is found with its absolute offset',
    () async {
      final file = File('${root.path}/large.txt');
      final writer = await file.open(mode: FileMode.write);
      const offset = 65 * 1024 * 1024 + 19;
      await writer.setPosition(offset);
      await writer.writeFrom(pattern('needle beyond old limit'));
      await writer.close();
      final source = ViewBytesSource.file(file.path);
      await source.open();
      addTearDown(source.dispose);
      final result = await searchViewerBytes(source, pattern('needle'));
      expect(result.offsets, [offset]);
      expect(result.totalMatches, 1);
      expect(result.scannedBytes, await file.length());
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test(
    'search handles chunk-boundary and overlapping matches without duplicates',
    () async {
      final bytes = Uint8List(128 * 1024 + 20)
        ..fillRange(0, 128 * 1024 + 20, 32);
      bytes.setRange(128 * 1024 - 2, 128 * 1024 + 3, 'aaaaa'.codeUnits);
      final source = ViewBytesSource.memory(bytes);
      await source.open();
      final result = await searchViewerBytes(source, pattern('aaa'));
      expect(result.offsets, [128 * 1024 - 2, 128 * 1024 - 1, 128 * 1024]);
    },
  );

  test(
    'a bounded offset index still counts and scans the entire file',
    () async {
      final source = ViewBytesSource.memory(pattern('x x x x x'));
      await source.open();
      final result = await searchViewerBytes(
        source,
        pattern('x'),
        maximumOffsets: 2,
      );
      expect(result.offsets, [0, 2]);
      expect(result.totalMatches, 5);
      expect(result.scannedBytes, source.size);
    },
  );

  test(
    'cancellation after an early hit never returns a partial successful scan',
    () async {
      final source = ViewBytesSource.memory(Uint8List(512 * 1024));
      await source.open();
      var cancelled = false;
      await expectLater(
        searchViewerBytes(
          source,
          Uint8List.fromList([0]),
          isCancelled: () => cancelled,
          onProgress: (_, _) => cancelled = true,
        ),
        throwsA(isA<ViewerSearchCancelled>()),
      );
      expect(source.readSync(0, 1), [0]);
    },
  );

  test('late file edits invalidate earlier search hits', () async {
    final file = await File('${root.path}/changing')
        .writeAsBytes(Uint8List(256 * 1024));
    final source = ViewBytesSource.file(file.path);
    await source.open();
    addTearDown(source.dispose);
    var changed = false;
    await expectLater(
      searchViewerBytes(
        source,
        Uint8List.fromList([0]),
        onProgress: (_, _) {
          if (!changed) {
            changed = true;
            file.setLastModifiedSync(DateTime.utc(2001));
          }
        },
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'range reads larger than the scroll cache cover the requested length',
    () async {
      final data = Uint8List(2 * 1024 * 1024);
      for (var i = 0; i < data.length; i++) {
        data[i] = i % 251;
      }
      final file = await File('${root.path}/window').writeAsBytes(data);
      final source = ViewBytesSource.file(file.path);
      await source.open();
      addTearDown(source.dispose);
      expect(
        source.readSync(321, 1024 * 1024),
        data.sublist(321, 321 + 1024 * 1024),
      );
    },
  );

  test('UTF-16 and UTF-32 patterns use the selected byte order and code-unit alignment', () async {
    for (final encoding in ['utf16le', 'utf16be', 'utf32le', 'utf32be']) {
      final data = encodeViewerSearchText('A café 🙂 Z', encoding);
      final source = ViewBytesSource.memory(data);
      await source.open();
      final result = await searchViewerBytes(
        source,
        encodeViewerSearchText('café 🙂', encoding),
        alignment: viewerCodeUnitBytes(encoding),
      );
      expect(result.offsets, [
        2 * viewerCodeUnitBytes(encoding),
      ], reason: encoding);
    }
    final source = ViewBytesSource.memory(Uint8List.fromList([0, 65, 0, 66]));
    await source.open();
    expect(
      (await searchViewerBytes(
        source,
        Uint8List.fromList([65, 0]),
        alignment: 2,
      )).offsets,
      isEmpty,
    );
  });

  test(
    'auto-detection does not mistake a split UTF-8 sample tail for Latin-1',
    () async {
      final text = '${'a' * 4095}é trailing';
      final source = ViewBytesSource.memory(pattern(text));
      await source.open();
      expect(viewerSourceEncoding(source), 'utf8');
      expect(encodeViewerSearchText('é', 'latin1'), [0xe9]);
      final latinSource = ViewBytesSource.memory(
        Uint8List.fromList([99, 97, 102, 233]),
      );
      await latinSource.open();
      expect(viewerSourceEncoding(latinSource), 'latin1');
    },
  );
}
