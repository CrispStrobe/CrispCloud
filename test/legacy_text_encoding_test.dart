import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_search_query.dart';
import 'package:crisp_cloud/services/editor_document.dart';
import 'package:crisp_cloud/services/file_bytes_loader.dart';
import 'package:crisp_cloud/services/internal_viewer_service.dart';
import 'package:crisp_cloud/services/legacy_text_encoding.dart';
import 'package:crisp_cloud/services/search_content_matcher.dart';
import 'package:crisp_cloud/services/viewer_search_service.dart';
import 'package:crisp_cloud/services/viewer_text_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DOS accents and box drawing match the CP437 character assignments', () {
    expect(
      decodeLegacyText([
        0x82,
        0x81,
        0x9c,
        0xda,
        0xc4,
        0xbf,
        0xb3,
        0xe0,
      ], 'cp437'),
      'éü£┌─┐│α',
    );
    expect(encodeLegacyText('éü£┌─┐│α', 'cp437'), [
      0x82,
      0x81,
      0x9c,
      0xda,
      0xc4,
      0xbf,
      0xb3,
      0xe0,
    ]);
  });

  test('Windows punctuation and euro are distinct from Latin-1 controls', () {
    expect(
      decodeLegacyText([
        0x80,
        0x93,
        0x94,
        0x91,
        0x92,
        0x96,
        0x97,
        0x9c,
      ], 'windows1252'),
      '€“”‘’–—œ',
    );
    expect(encodeLegacyText('€“”‘’–—œ', 'windows1252'), [
      0x80,
      0x93,
      0x94,
      0x91,
      0x92,
      0x96,
      0x97,
      0x9c,
    ]);
    expect(
      decodeLegacyText([0x81, 0x8d, 0x8f, 0x90, 0x9d], 'windows1252').codeUnits,
      [0x81, 0x8d, 0x8f, 0x90, 0x9d],
    );
  });

  for (final encoding in [EditorEncoding.cp437, EditorEncoding.windows1252]) {
    test('${encoding.label} preserves every byte through codec and editor', () {
      final bytes = Uint8List.fromList(List.generate(256, (index) => index));
      final text = decodeLegacyText(bytes, encoding.name);
      expect(encodeLegacyText(text, encoding.name), bytes);
      final document = EditorDocument.decode(bytes, encodingOverride: encoding);
      expect(document.encoding, encoding);
      expect(document.hadBom, isFalse);
      expect(document.writesBom, isFalse);
      expect(document.encode(), bytes);
      expect(
        document.copyWith(writeBom: true, hadBom: true).writesBom,
        isFalse,
      );
      expect(document.copyWith(writeBom: true, hadBom: true).encode(), bytes);
    });

    test(
      '${encoding.label} refuses lossy edits and supports explicit UTF-8 conversion',
      () {
        final original = encodeLegacyText('café\r\nline\nend\r', encoding.name);
        final document = EditorDocument.decode(
          original,
          encodingOverride: encoding,
        );
        final edited = document.copyWith(text: '${document.text}東京');
        expect(() => edited.encode(), throwsA(isA<EditorEncodingException>()));
        expect(
          () => encodeViewerSearchText('東京', encoding.name),
          throwsFormatException,
        );
        expect(
          utf8.decode(edited.copyWith(encoding: EditorEncoding.utf8).encode()),
          'café\r\nline\nend\r東京',
        );
        // An unsuccessful encoding attempt cannot mutate the loaded document.
        expect(document.encode(), original);
      },
    );

    test('${encoding.label} has no BOM and never guesses from input bytes', () {
      final legacy = EditorDocument.decode(
        utf8.encode('plain'),
      ).copyWith(encoding: encoding, hadBom: true);
      expect(legacy.writesBom, isFalse);
      expect(legacy.encode(), 'plain'.codeUnits);
      final prefix = [0xef, 0xbb, 0xbf];
      expect(
        EditorDocument.decode(prefix, encodingOverride: encoding).encode(),
        prefix,
      );
      expect(EditorDocument.decode([0x80]).encoding, EditorEncoding.latin1);
    });

    test(
      '${encoding.label} keeps streaming decode and byte offsets consistent',
      () {
        final bytes = Uint8List.fromList(List.generate(256, (index) => index));
        final expected = InternalViewerService.decodeTextForView(
          bytes,
          encoding: encoding.name,
        );
        expect(expected.encoding, encoding.name);
        for (final chunkSize in [1, 3, 31, 128]) {
          final decoder = ViewerTextDecoder(encoding.name);
          final text = StringBuffer();
          final starts = <int>[], ends = <int>[];
          for (var offset = 0; offset < bytes.length; offset += chunkSize) {
            final result = decoder.add(
              Uint8List.sublistView(
                bytes,
                offset,
                (offset + chunkSize).clamp(0, bytes.length),
              ),
              offset,
            );
            text.write(result.text);
            starts.addAll(result.starts);
            ends.addAll(result.ends);
          }
          expect(
            decoder.add(Uint8List(0), bytes.length, last: true).text,
            isEmpty,
          );
          expect(text.toString(), expected.text, reason: '$chunkSize');
          expect(starts, List.generate(256, (index) => index));
          expect(ends, List.generate(256, (index) => index + 1));
        }
      },
    );

    test(
      '${encoding.label} viewer search crosses a decode window with exact offsets',
      () async {
        final needle = encoding == EditorEncoding.cp437 ? 'café ──' : 'café €—';
        final text = '${'x' * (128 * 1024 - 2)}$needle tail';
        final source = ViewBytesSource.memory(
          encodeLegacyText(text, encoding.name),
        );
        await source.open();
        addTearDown(source.dispose);
        final matches = await searchViewerText(
          source,
          needle,
          encoding: encoding.name,
        );
        expect(matches.offsets, [128 * 1024 - 2]);
        expect(matches.endOffsets, [128 * 1024 - 2 + needle.length]);
        expect(matches.textOffsets, matches.offsets);
        expect(
          alignViewerTextOffset(source, 128 * 1024, encoding.name),
          128 * 1024,
        );
      },
    );

    test(
      '${encoding.label} recursive literal and regex search use the selected page',
      () async {
        final needle = encoding == EditorEncoding.cp437 ? 'café ──' : 'café €—';
        final text = '${'x' * 33790}$needle tail';
        final bytes = encodeLegacyText(text, encoding.name);
        final query = FileSearchQuery(
          contentPattern: needle,
          contentEncoding: encoding.name,
        );
        query.validate();
        expect(
          FileSearchQuery.fromJson(query.toJson()).contentEncoding,
          encoding.name,
        );
        Stream<List<int>> chunks() async* {
          for (var offset = 0; offset < bytes.length; offset += 29) {
            yield bytes.sublist(offset, (offset + 29).clamp(0, bytes.length));
          }
        }

        expect(
          await searchLiteralContent(chunks(), query, check: () {}),
          matchSearchText(text, query),
        );
        final regex = FileSearchQuery(
          contentPattern: RegExp.escape(needle),
          contentEncoding: encoding.name,
          contentRegex: true,
        );
        expect(
          matchSearchText(
            InternalViewerService.decodeTextForView(
              bytes,
              encoding: encoding.name,
            ).text,
            regex,
          ),
          matchSearchText(text, regex),
        );
      },
    );
  }

  test(
    'legacy conversion rejects unknown encodings and invalid input values',
    () {
      expect(() => decodeLegacyText([65], 'cp999'), throwsFormatException);
      expect(() => encodeLegacyText('A', 'cp999'), throwsFormatException);
      expect(() => decodeLegacyText([-1], 'cp437'), throwsRangeError);
      expect(() => decodeLegacyText([256], 'windows1252'), throwsRangeError);
      expect(() => encodeLegacyText('\ud800', 'cp437'), throwsFormatException);
    },
  );
}
