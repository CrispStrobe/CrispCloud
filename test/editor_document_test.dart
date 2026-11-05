// Tests for the editor's encoding and line-ending metadata.
//
// The editor works on LF internally; these tests pin the conversion back to
// the original bytes so saves do not silently change a file's encoding.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/editor_document.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  group('line endings', () {
    test('LF text round-trips exactly', () {
      const source = 'first\nsecond\n';
      final document = EditorDocument.decode(utf8.encode(source));

      expect(document.text, source);
      expect(document.lineEnding, EditorLineEnding.lf);
      expect(document.hadMixedLineEndings, isFalse);
      expect(document.encode(), utf8.encode(source));
    });

    test('CRLF is normalized for editing and restored on save', () {
      const source = 'first\r\nsecond\r\n';
      final document = EditorDocument.decode(utf8.encode(source));

      expect(document.text, 'first\nsecond\n');
      expect(document.lineEnding, EditorLineEnding.crlf);
      expect(document.encode(), utf8.encode(source));
    });

    test('CR-only text is detected and restored', () {
      const source = 'first\rsecond\r';
      final document = EditorDocument.decode(utf8.encode(source));

      expect(document.text, 'first\nsecond\n');
      expect(document.lineEnding, EditorLineEnding.cr);
      expect(document.encode(), utf8.encode(source));
    });

    test('mixed endings use the dominant style and are reported', () {
      const source = 'one\r\ntwo\nthree\r\n';
      final document = EditorDocument.decode(utf8.encode(source));

      expect(document.text, 'one\ntwo\nthree\n');
      expect(document.lineEnding, EditorLineEnding.crlf);
      expect(document.hadMixedLineEndings, isTrue);
      expect(
        document.encode(),
        utf8.encode('one\r\ntwo\r\nthree\r\n'),
        reason: 'A save must apply one documented style to the whole file.',
      );
    });

    test('a CRLF/LF tie prefers CRLF', () {
      final document = EditorDocument.decode(utf8.encode('one\r\ntwo\n'));
      expect(document.lineEnding, EditorLineEnding.crlf);
      expect(document.hadMixedLineEndings, isTrue);
    });

    test('a file without a final newline keeps that shape', () {
      const source = 'first\nsecond';
      final document = EditorDocument.decode(utf8.encode(source));
      expect(document.text, source);
      expect(document.encode(), utf8.encode(source));
    });

    test('a selected line ending applies to newly typed line breaks', () {
      final document = EditorDocument.decode(utf8.encode('a\nb\n'));
      final edited = document.copyWith(
        text: 'a\ninserted\nb\n',
        lineEnding: EditorLineEnding.crlf,
      );
      expect(edited.encode(), utf8.encode('a\r\ninserted\r\nb\r\n'));
    });
  });

  group('encoding detection', () {
    test('UTF-8 BOM is stripped from the text and restored on save', () {
      final source = _bytes(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode('hello\n')]);
      final document = EditorDocument.decode(source);

      expect(document.encoding, EditorEncoding.utf8Bom);
      expect(document.hadBom, isTrue);
      expect(document.text, 'hello\n');
      expect(document.encode(), source);
    });

    test('UTF-8 BOM and CRLF survive together', () {
      final source = _bytes(<int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('one\r\ntwo\r\n'),
      ]);
      final document = EditorDocument.decode(source);

      expect(document.encoding, EditorEncoding.utf8Bom);
      expect(document.lineEnding, EditorLineEnding.crlf);
      expect(document.text, 'one\ntwo\n');
      expect(document.encode(), source);
    });

    test('plain UTF-8 keeps Unicode, combining marks and emoji', () {
      const source = 'café e\u0301 日本語 😀 👩🏽‍💻\n';
      final document = EditorDocument.decode(utf8.encode(source));

      expect(document.encoding, EditorEncoding.utf8);
      expect(document.text, source);
      expect(document.encode(), utf8.encode(source));
    });

    test('UTF-16 LE with BOM round-trips', () {
      const source = 'hello 😀\n';
      final sourceBytes = _bytes(<int>[
        0xFF,
        0xFE,
        for (final unit in source.codeUnits) ...[
          unit & 0xFF,
          (unit >> 8) & 0xFF,
        ],
      ]);
      final document = EditorDocument.decode(sourceBytes);

      expect(document.encoding, EditorEncoding.utf16le);
      expect(document.text, source);
      expect(document.encode(), sourceBytes);
    });

    test('UTF-16 BE with BOM round-trips', () {
      const source = 'hello 日本\n';
      final sourceBytes = _bytes(<int>[
        0xFE,
        0xFF,
        for (final unit in source.codeUnits) ...[
          (unit >> 8) & 0xFF,
          unit & 0xFF,
        ],
      ]);
      final document = EditorDocument.decode(sourceBytes);

      expect(document.encoding, EditorEncoding.utf16be);
      expect(document.text, source);
      expect(document.encode(), sourceBytes);
    });

    test('UTF-32 LE with BOM round-trips', () {
      const source = 'hi 😀\n';
      final sourceBytes = _bytes(<int>[
        0xFF,
        0xFE,
        0x00,
        0x00,
        for (final rune in source.runes) ...[
          rune & 0xFF,
          (rune >> 8) & 0xFF,
          (rune >> 16) & 0xFF,
          (rune >> 24) & 0xFF,
        ],
      ]);
      final document = EditorDocument.decode(sourceBytes);

      expect(document.encoding, EditorEncoding.utf32le);
      expect(document.text, source);
      expect(document.encode(), sourceBytes);
    });

    test('UTF-32 BE with BOM round-trips', () {
      const source = 'hi 😀\n';
      final sourceBytes = _bytes(<int>[
        0x00,
        0x00,
        0xFE,
        0xFF,
        for (final rune in source.runes) ...[
          (rune >> 24) & 0xFF,
          (rune >> 16) & 0xFF,
          (rune >> 8) & 0xFF,
          rune & 0xFF,
        ],
      ]);
      final document = EditorDocument.decode(sourceBytes);

      expect(document.encoding, EditorEncoding.utf32be);
      expect(document.text, source);
      expect(document.encode(), sourceBytes);
    });

    test('invalid UTF-8 falls back to Latin-1 and preserves the bytes', () {
      final source = _bytes(<int>[0x63, 0x61, 0x66, 0xE9, 0x0A]);
      final document = EditorDocument.decode(source);

      expect(document.encoding, EditorEncoding.latin1);
      expect(document.text, 'café\n');
      expect(document.encode(), source);
    });

    test('Latin-1 cannot silently encode characters outside its range', () {
      final document = EditorDocument.decode(
        _bytes(<int>[0x63, 0x61, 0x66, 0xE9]),
      );

      expect(
        () => document.copyWith(text: 'café 😀').encode(),
        throwsA(isA<EditorEncodingException>()),
      );
      expect(
        document
            .copyWith(encoding: EditorEncoding.utf8)
            .copyWith(text: 'café 😀')
            .encode(),
        utf8.encode('café 😀'),
      );
    });

    test('empty input produces an empty UTF-8 LF document', () {
      final document = EditorDocument.decode(const <int>[]);
      expect(document.text, '');
      expect(document.encoding, EditorEncoding.utf8);
      expect(document.lineEnding, EditorLineEnding.lf);
      expect(document.encode(), isEmpty);
    });
  });
}
