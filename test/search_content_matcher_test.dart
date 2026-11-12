import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_search_query.dart';
import 'package:crisp_cloud/services/internal_viewer_service.dart';
import 'package:crisp_cloud/services/legacy_text_encoding.dart';
import 'package:crisp_cloud/services/search_content_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

Stream<List<int>> chunks(List<int> bytes, int size) async* {
  for (var offset = 0; offset < bytes.length; offset += size) {
    yield bytes.sublist(offset, (offset + size).clamp(0, bytes.length));
  }
}

List<int> encode(String text, String encoding) {
  if (encoding == 'utf8') return utf8.encode(text);
  if (encoding == 'latin1') return latin1.encode(text);
  if (isLegacyTextEncoding(encoding)) return encodeLegacyText(text, encoding);
  final unit = encoding.startsWith('utf32') ? 4 : 2;
  final values = unit == 4 ? text.runes : text.codeUnits;
  return [
    for (final code in values)
      for (var i = 0; i < unit; i++)
        (code >> ((encoding.endsWith('be') ? unit - i - 1 : i) * 8)) & 0xff,
  ];
}

void main() {
  test(
    'literal streaming matches complete decoded text across every byte boundary',
    () async {
      for (final encoding in FileSearchQuery.contentEncodings.where(
        (e) => e != 'auto',
      )) {
        final needle = encoding == 'latin1' || isLegacyTextEncoding(encoding)
            ? 'Grüße'
            : 'Grüße 東京 😀';
        final content = '${'x' * 1073}$needle${'y' * 120}';
        final bytes = encode(content, encoding);
        final query = FileSearchQuery(
          contentPattern: needle,
          contentEncoding: encoding,
        );
        final expected = matchSearchText(
          InternalViewerService.decodeTextForView(
            Uint8List.fromList(bytes),
            encoding: encoding,
          ).text,
          query,
        );
        for (final size in [1, 3, 127, 1023, 1024, 32768]) {
          expect(
            await searchLiteralContent(
              chunks(bytes, size),
              query,
              check: () {},
            ),
            expected,
            reason: '$encoding / chunk $size',
          );
        }
      }
    },
  );

  test(
    'auto encoding agrees with full decoding for BOMs, sniffing and late invalid UTF-8',
    () async {
      final data = <List<int>>[
        [0xef, 0xbb, 0xbf, ...utf8.encode('café needle 東京')],
        [0xff, 0xfe, ...encode('needle ${'text ' * 210}東京', 'utf16le')],
        [0xfe, 0xff, ...encode('needle ${'text ' * 210}東京', 'utf16be')],
        [0xff, 0xfe, 0, 0, ...encode('needle 東京 😀', 'utf32le')],
        [0, 0, 0xfe, 0xff, ...encode('needle 東京 😀', 'utf32be')],
        encode('${'words ' * 200}needle', 'utf16le'),
        encode('${'words ' * 200}needle', 'utf16be'),
        [...utf8.encode('café ${'x' * 1500}'), 0xff],
        [0xef, 0xbb, 0xbf, ...utf8.encode('café ${'x' * 1500}'), 0xff],
        latin1.encode('café needle'),
      ];
      for (final bytes in data) {
        for (final needle in ['needle', 'café', 'cafÃ©']) {
          for (final negated in [false, true]) {
            final query = FileSearchQuery(
              contentPattern: needle,
              contentNegated: negated,
            );
            final expected = matchSearchText(
              InternalViewerService.decodeTextForView(
                Uint8List.fromList(bytes),
              ).text,
              query,
            );
            expect(
              await searchLiteralContent(chunks(bytes, 3), query, check: () {}),
              expected,
              reason: '$needle / negated=$negated / ${bytes.take(8)}',
            );
          }
        }
      }
    },
  );

  test(
    'matches, snippet context, and case-insensitivity cross decode chunks',
    () async {
      final content = '${'x' * 33780}MiXeD\nLiNeS${'y' * 200}';
      const query = FileSearchQuery(
        contentPattern: 'mixed\nlines',
        contentEncoding: 'utf8',
      );
      expect(
        await searchLiteralContent(
          chunks(utf8.encode(content), 29),
          query,
          check: () {},
        ),
        matchSearchText(content, query),
      );
    },
  );

  test(
    'a late read failure cannot produce a partial positive or negative result',
    () async {
      Stream<List<int>> broken() async* {
        yield utf8.encode('needle ${'x' * 1100}');
        throw StateError('Interrupted download');
      }

      for (final negative in [false, true]) {
        await expectLater(
          searchLiteralContent(
            broken(),
            FileSearchQuery(
              contentPattern: negative ? 'absent' : 'needle',
              contentNegated: negative,
            ),
            check: () {},
          ),
          throwsStateError,
        );
      }
    },
  );

  test('cancellation stops reading and closes the source stream', () async {
    var count = 0, closed = false;
    Stream<List<int>> source() async* {
      try {
        while (count < 100) {
          count++;
          yield List.filled(4096, 65);
        }
      } finally {
        closed = true;
      }
    }

    await expectLater(
      searchLiteralContent(
        source(),
        const FileSearchQuery(contentPattern: 'absent'),
        check: () {
          if (count >= 3) throw StateError('Cancelled');
        },
      ),
      throwsStateError,
    );
    expect(count, 3);
    expect(closed, isTrue);
  });

  test(
    'literal search reaches a match beyond 64 MiB without a full-file buffer',
    () async {
      var complete = false;
      Stream<List<int>> large() async* {
        final block = Uint8List(32 * 1024)..fillRange(0, 32 * 1024, 120);
        for (var i = 0; i < 2080; i++) {
          yield block;
        }
        yield utf8.encode('needle');
        complete = true;
      }

      final result = await searchLiteralContent(
        large(),
        const FileSearchQuery(contentPattern: 'needle', maxContentBytes: 2),
        check: () {},
      );
      expect(result, '${'…'}${'x' * 45}needle');
      expect(complete, isTrue);
    },
  );
}
