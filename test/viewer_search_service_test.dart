import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/file_bytes_loader.dart';
import 'package:crisp_cloud/services/viewer_search_service.dart';
import 'package:crisp_cloud/services/viewer_text_decoder.dart';
import 'package:crisp_cloud/services/internal_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('viewer-search-'),
  );
  tearDown(() => root.delete(recursive: true));
  Uint8List pattern(String text) => Uint8List.fromList(utf8.encode(text));

  test('decoded literal search preserves whitespace, Unicode case and exact encoded ranges', () async {
    const text = 'x KELVIN café CAFÉ 0x41 A  x ';
    final source = ViewBytesSource.memory(pattern(text));
    await source.open();
    final kelvin = await searchViewerText(source, 'kelvin', encoding: 'utf8');
    expect(kelvin.offsets, [2]);
    expect(kelvin.endOffsets, [10]);
    expect(kelvin.textOffsets, [2]);
    expect(kelvin.textEndOffsets, [8]);
    expect(
      (await searchViewerText(
        source,
        'kelvin',
        encoding: 'utf8',
        caseSensitive: true,
      )).totalMatches,
      0,
    );
    expect(
      (await searchViewerText(source, 'café', encoding: 'utf8')).totalMatches,
      2,
    );
    for (final query in ['0x41', ' x ', ' ']) {
      final result = await searchViewerText(source, query, encoding: 'utf8');
      final expected = RegExp('(?=(${RegExp.escape(query)}))')
          .allMatches(text)
          .map((m) => m.start);
      expect(result.textOffsets, expected, reason: query);
    }
  });

  test('text decoding matches the viewer across every code-unit split and malformed UTF-8', () {
    for (final encoding in [
      'utf8',
      'utf16le',
      'utf16be',
      'utf32le',
      'utf32be',
      'latin1',
    ]) {
      final data = encodeViewerSearchText(
        encoding == 'latin1' ? 'Café\ntext' : 'Café 🙂 東京\ntext',
        encoding,
      );
      for (final split in [1, 2, 3, 7, 17]) {
        final decoder = ViewerTextDecoder(encoding, skipBom: false);
        final chunks = <ViewerDecodedText>[];
        for (var offset = 0; offset < data.length; offset += split) {
          chunks.add(
            decoder.add(
              Uint8List.sublistView(
                data,
                offset,
                (offset + split).clamp(0, data.length),
              ),
              offset,
            ),
          );
        }
        chunks.add(decoder.add(Uint8List(0), data.length, last: true));
        expect(
          chunks.map((c) => c.text).join(),
          InternalViewerService.decodeTextForView(
            data,
            encoding: encoding,
          ).text,
          reason: '$encoding/$split',
        );
        for (final chunk in chunks) {
          expect(chunk.starts.length, chunk.text.length);
          expect(chunk.ends.length, chunk.text.length);
        }
      }
    }
    for (final data in <List<int>>[
      [0xe2, 0x82],
      [0xe2, 0x82, 0x20],
      [0xe0, 0x80, 0x80],
      [0xf4, 0x90, 0x80, 0x80],
      [0xc0, 0xaf],
      [0xed, 0xa0, 0x80],
    ]) {
      final decoder = ViewerTextDecoder('utf8');
      final actual = StringBuffer();
      for (var offset = 0; offset < data.length; offset++) {
        actual.write(
          decoder.add(Uint8List.fromList([data[offset]]), offset).text,
        );
      }
      actual.write(decoder.add(Uint8List(0), data.length, last: true).text);
      expect(
        actual.toString(),
        utf8.decode(data, allowMalformed: true),
        reason: '$data',
      );
    }
  });

  test(
    'Unicode text matches span chunk boundaries in every supported encoding',
    () async {
      for (final encoding in [
        'utf8',
        'utf16le',
        'utf16be',
        'utf32le',
        'utf32be',
        'latin1',
      ]) {
        final unit = viewerCodeUnitBytes(encoding);
        final prefix = 'x' * ((128 * 1024 - unit) ~/ unit);
        final query = encoding == 'latin1' ? 'café' : '🙂café';
        final original = '$prefix${query.toUpperCase()} end';
        final source = ViewBytesSource.memory(
          encodeViewerSearchText(original, encoding),
        );
        await source.open();
        final result = await searchViewerText(
          source,
          query,
          encoding: encoding,
        );
        expect(result.offsets, [128 * 1024 - unit], reason: encoding);
        expect(result.textOffsets, [prefix.length], reason: encoding);
        expect(result.endOffsets, [
          encodeViewerSearchText(
            '$prefix${query.toUpperCase()}',
            encoding,
          ).length,
        ], reason: encoding);
      }
    },
  );

  test('bounded text result pages continue through overlaps and navigate back or to the last page', () async {
    final source = ViewBytesSource.memory(pattern('aaaaaa'));
    await source.open();
    final first = await searchViewerText(
      source,
      'aa',
      encoding: 'utf8',
      maximumOffsets: 2,
    );
    expect(first.offsets, [0, 1]);
    expect(first.totalMatches, 5);
    final next = await searchViewerText(
      source,
      'aa',
      encoding: 'utf8',
      maximumOffsets: 2,
      startOffset: first.nextOffset!,
      startTextOffset: first.nextTextOffset!,
    );
    expect(next.offsets, [2, 3]);
    expect(next.textOffsets, [2, 3]);
    expect(next.totalMatches, 3);
    final last = await searchViewerText(
      source,
      'aa',
      encoding: 'utf8',
      maximumOffsets: 2,
      skipMatches: 4,
    );
    expect(last.offsets, [4]);
    expect(last.totalMatches, 5);
    final previous = await searchViewerBytes(
      source,
      pattern('aa'),
      maximumOffsets: 2,
      skipMatches: 2,
    );
    expect(previous.offsets, [2, 3]);
    expect(previous.nextOffset, 4);
  });

  test('text continuation never starts inside a surrogate or malformed UTF-8 replacement', () async {
    for (final encoding in ['utf8', 'utf16le', 'utf16be', 'utf32le']) {
      final source = ViewBytesSource.memory(
        encodeViewerSearchText('🙂🙂🙂', encoding),
      );
      await source.open();
      final first = await searchViewerText(
        source,
        '🙂',
        encoding: encoding,
        maximumOffsets: 1,
      );
      final next = await searchViewerText(
        source,
        '🙂',
        encoding: encoding,
        maximumOffsets: 1,
        startOffset: first.nextOffset!,
        startTextOffset: first.nextTextOffset!,
      );
      expect(next.offsets, [4], reason: encoding);
      expect(next.textOffsets, [2], reason: encoding);
    }
    final malformed = ViewBytesSource.memory(
      Uint8List.fromList([0xe0, 0x80, 0x80]),
    );
    await malformed.open();
    final first = await searchViewerText(
      malformed,
      '\ufffd',
      encoding: 'utf8',
      maximumOffsets: 1,
    );
    final next = await searchViewerText(
      malformed,
      '\ufffd',
      encoding: 'utf8',
      maximumOffsets: 2,
      startOffset: first.nextOffset!,
      startTextOffset: first.nextTextOffset!,
    );
    expect(next.offsets, [1, 2]);
  });

  test('decoded search cancellation and source revocation cannot publish early matches', () async {
    final source = ViewBytesSource.memory(
      Uint8List(512 * 1024)..fillRange(0, 512 * 1024, 97),
    );
    await source.open();
    var cancelled = false;
    await expectLater(
      searchViewerText(
        source,
        'a',
        encoding: 'utf8',
        isCancelled: () => cancelled,
        onProgress: (_, _) => cancelled = true,
      ),
      throwsA(isA<ViewerSearchCancelled>()),
    );
    var current = true;
    await expectLater(
      searchViewerText(
        source,
        'a',
        encoding: 'utf8',
        checkSource: () {
          if (!current) throw StateError('Disconnected');
        },
        onProgress: (_, _) => current = false,
      ),
      throwsStateError,
    );
  });

  test(
    'text boundary alignment preserves complete UTF-8 and UTF-16 scalars',
    () async {
      for (final encoding in ['utf8', 'utf16le', 'utf16be', 'utf32le']) {
        final source = ViewBytesSource.memory(
          encodeViewerSearchText('🙂x', encoding),
        );
        await source.open();
        for (var position = 1; position < 4; position++) {
          expect(
            alignViewerTextOffset(source, position, encoding),
            0,
            reason: '$encoding/$position',
          );
          expect(
            alignViewerTextOffset(source, position, encoding, forward: true),
            4,
            reason: '$encoding/$position',
          );
        }
      }
    },
  );

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
