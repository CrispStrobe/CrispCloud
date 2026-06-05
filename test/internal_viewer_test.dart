// test/internal_viewer_test.dart
//
// Tests for InternalViewerService — mode detection, hex dump, text preview,
// encoding detection, search, and edge cases.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/internal_viewer_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _svc = InternalViewerService();

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);
Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));
Uint8List _latin1Bytes(List<int> values) => Uint8List.fromList(values);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ---- Mode detection by extension -----------------------------------------

  group('detectMode — by extension', () {
    test('.txt → text', () {
      expect(_svc.detectMode('readme.txt'), ViewerMode.text);
    });

    test('.dart → text', () {
      expect(_svc.detectMode('main.dart'), ViewerMode.text);
    });

    test('.log → text', () {
      expect(_svc.detectMode('app.log'), ViewerMode.text);
    });

    test('.json → text', () {
      expect(_svc.detectMode('config.json'), ViewerMode.text);
    });

    test('.yaml → text', () {
      expect(_svc.detectMode('pubspec.yaml'), ViewerMode.text);
    });

    test('.py → text', () {
      expect(_svc.detectMode('script.py'), ViewerMode.text);
    });

    test('.sh → text', () {
      expect(_svc.detectMode('install.sh'), ViewerMode.text);
    });

    test('.html → text', () {
      expect(_svc.detectMode('index.html'), ViewerMode.text);
    });

    test('.png → image', () {
      expect(_svc.detectMode('photo.png'), ViewerMode.image);
    });

    test('.jpg → image', () {
      expect(_svc.detectMode('photo.jpg'), ViewerMode.image);
    });

    test('.jpeg → image', () {
      expect(_svc.detectMode('photo.jpeg'), ViewerMode.image);
    });

    test('.gif → image', () {
      expect(_svc.detectMode('anim.gif'), ViewerMode.image);
    });

    test('.webp → image', () {
      expect(_svc.detectMode('img.webp'), ViewerMode.image);
    });

    test('.bmp → image', () {
      expect(_svc.detectMode('icon.bmp'), ViewerMode.image);
    });

    test('.svg → image', () {
      expect(_svc.detectMode('logo.svg'), ViewerMode.image);
    });

    test('.pdf → pdf', () {
      expect(_svc.detectMode('document.pdf'), ViewerMode.pdf);
    });

    test('.md → markdown', () {
      expect(_svc.detectMode('README.md'), ViewerMode.markdown);
    });

    test('.markdown → markdown', () {
      expect(_svc.detectMode('notes.markdown'), ViewerMode.markdown);
    });

    test('.exe → binary', () {
      expect(_svc.detectMode('setup.exe'), ViewerMode.binary);
    });

    test('.dll → binary', () {
      expect(_svc.detectMode('lib.dll'), ViewerMode.binary);
    });

    test('.so → binary', () {
      expect(_svc.detectMode('libfoo.so'), ViewerMode.binary);
    });

    test('unknown extension → binary', () {
      expect(_svc.detectMode('file.xyz'), ViewerMode.binary);
    });

    test('no extension → binary', () {
      expect(_svc.detectMode('Makefile'), ViewerMode.binary);
    });

    test('mixed-case extension is detected correctly', () {
      expect(_svc.detectMode('Image.PNG'), ViewerMode.image);
      expect(_svc.detectMode('Doc.PDF'), ViewerMode.pdf);
    });
  });

  // ---- Mode detection by magic bytes ----------------------------------------

  group('detectMode — by magic bytes', () {
    test('PNG magic header → image', () {
      final header = _bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(_svc.detectMode('unknown.dat', header: header), ViewerMode.image);
    });

    test('JPEG magic header → image', () {
      final header = _bytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      expect(_svc.detectMode('photo.bin', header: header), ViewerMode.image);
    });

    test('PDF magic header → pdf', () {
      final header = _bytes([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34]);
      expect(_svc.detectMode('file.bin', header: header), ViewerMode.pdf);
    });

    test('GIF magic header → image', () {
      final header = _bytes([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
      expect(_svc.detectMode('anim.bin', header: header), ViewerMode.image);
    });

    test('BMP magic header → image', () {
      final header = _bytes([0x42, 0x4D, 0x46, 0x00, 0x00, 0x00]);
      expect(_svc.detectMode('image.bin', header: header), ViewerMode.image);
    });

    test('ELF magic header → binary', () {
      final header = _bytes([0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01]);
      expect(_svc.detectMode('program', header: header), ViewerMode.binary);
    });

    test('PE (MZ) magic header → binary', () {
      final header = _bytes([0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00]);
      expect(_svc.detectMode('app.dll', header: header), ViewerMode.binary);
    });

    test('UTF-8 BOM magic → text', () {
      final header = _bytes([0xEF, 0xBB, 0xBF, 0x48, 0x65, 0x6C]);
      expect(_svc.detectMode('notes.bin', header: header), ViewerMode.text);
    });

    test('magic bytes override extension (PNG bytes on .txt file)', () {
      final header = _bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(_svc.detectMode('disguised.txt', header: header), ViewerMode.image);
    });
  });

  // ---- Hex dump formatting -------------------------------------------------

  group('formatHexDump', () {
    test('single 16-byte line has correct offset 0', () {
      final data = _bytes(List.generate(16, (i) => i));
      final lines = _svc.formatHexDump(data);
      expect(lines.length, 1);
      expect(lines.first.offset, 0);
    });

    test('16-byte line has 16 hexParts', () {
      final data = _bytes(List.generate(16, (i) => i));
      final lines = _svc.formatHexDump(data);
      expect(lines.first.hexParts.length, 16);
    });

    test('hex parts are upper-case two-char strings', () {
      final data = _bytes([0x00, 0x0F, 0xFF, 0xAB]);
      final lines = _svc.formatHexDump(data);
      expect(lines.first.hexParts, containsAll(['00', '0F', 'FF', 'AB']));
    });

    test('ASCII column uses printable chars', () {
      final data = _utf8('Hello');
      final lines = _svc.formatHexDump(data);
      expect(lines.first.asciiPart, contains('H'));
      expect(lines.first.asciiPart, contains('e'));
    });

    test('non-printable bytes become "." in ASCII column', () {
      final data = _bytes([0x00, 0x01, 0x1F, 0x7F, 0x80]);
      final lines = _svc.formatHexDump(data);
      expect(lines.first.asciiPart, equals('.....'));
    });

    test('32-byte data produces 2 lines', () {
      final data = _bytes(List.generate(32, (i) => i));
      final lines = _svc.formatHexDump(data);
      expect(lines.length, 2);
    });

    test('second line offset is 16', () {
      final data = _bytes(List.generate(32, (i) => i));
      final lines = _svc.formatHexDump(data);
      expect(lines[1].offset, 16);
    });

    test('partial last line — 20 bytes → 2 lines (16 + 4)', () {
      final data = _bytes(List.generate(20, (i) => i));
      final lines = _svc.formatHexDump(data);
      expect(lines.length, 2);
      expect(lines[0].hexParts.length, 16);
      expect(lines[1].hexParts.length, 4);
    });

    test('partial last line ASCII column has correct length', () {
      final data = _bytes(List.generate(20, (i) => i + 0x41));
      final lines = _svc.formatHexDump(data);
      expect(lines[1].asciiPart.length, 4);
    });

    test('empty data → empty list', () {
      expect(_svc.formatHexDump(Uint8List(0)), isEmpty);
    });

    test('offset parameter shifts displayed offset', () {
      final data = _bytes(List.generate(16, (i) => i));
      final lines = _svc.formatHexDump(data, offset: 16);
      // offset=16 means we start reading from data[16] which is past the end
      expect(lines, isEmpty);
    });

    test('limit parameter caps bytes processed', () {
      final data = _bytes(List.generate(64, (i) => i));
      final lines = _svc.formatHexDump(data, limit: 16);
      expect(lines.length, 1);
    });

    test('toString produces offset + hex + ASCII columns', () {
      final data = _utf8('ABCDEFGHIJKLMNOP'); // 16 printable chars
      final lines = _svc.formatHexDump(data);
      final str = lines.first.toString();
      expect(str, contains('00000000'));
      expect(str, contains('41')); // 'A' in hex
      expect(str, contains('ABCDEFGHIJKLMNOP'));
    });

    test('HexLine equality is based on offset and asciiPart', () {
      final a = HexLine(offset: 0, hexParts: ['41'], asciiPart: 'A');
      final b = HexLine(offset: 0, hexParts: ['41'], asciiPart: 'A');
      expect(a, equals(b));
    });
  });

  // ---- Text preview --------------------------------------------------------

  group('getTextPreview', () {
    test('empty data → empty string', () {
      expect(_svc.getTextPreview(Uint8List(0)), isEmpty);
    });

    test('UTF-8 text decodes correctly', () {
      const text = 'Hello, world!\nSecond line.';
      final preview = _svc.getTextPreview(_utf8(text));
      expect(preview, contains('Hello, world!'));
      expect(preview, contains('Second line.'));
    });

    test('maxLines truncates output', () {
      final lines = List.generate(10, (i) => 'Line $i').join('\n');
      final preview = _svc.getTextPreview(_utf8(lines), maxLines: 5);
      final count = '\n'.allMatches(preview).length + 1;
      expect(count, 5);
    });

    test('maxLines 0 returns empty string', () {
      expect(_svc.getTextPreview(_utf8('hello'), maxLines: 0), isEmpty);
    });

    test('text shorter than maxLines is returned in full', () {
      const text = 'One\nTwo\nThree';
      final preview = _svc.getTextPreview(_utf8(text), maxLines: 1000);
      expect(preview, text);
    });

    test('UTF-8 BOM is stripped from preview', () {
      final withBom = _bytes([0xEF, 0xBB, 0xBF, ...utf8.encode('Hello')]);
      final preview = _svc.getTextPreview(withBom);
      expect(preview, 'Hello');
      expect(preview, isNot(startsWith('\uFEFF')));
    });

    test('Latin-1 fallback for non-UTF-8 data', () {
      // 0xE9 = 'é' in Latin-1; not valid UTF-8 as a standalone byte.
      final latinData = _latin1Bytes([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0xE9]);
      final preview = _svc.getTextPreview(latinData, encoding: 'latin1');
      expect(preview, 'Helloé');
    });

    test('explicit encoding=latin1 decodes as latin1', () {
      final data = _latin1Bytes([0xC0, 0xE9, 0xFC]);
      final preview = _svc.getTextPreview(data, encoding: 'latin1');
      expect(preview, equals(latin1.decode([0xC0, 0xE9, 0xFC])));
    });
  });

  // ---- loadContent ---------------------------------------------------------

  group('loadContent', () {
    test('text file has text mode', () {
      final content = _svc.loadContent(_utf8('hello'), 'readme.txt');
      expect(content.mode, ViewerMode.text);
    });

    test('filename stored as basename only', () {
      final content = _svc.loadContent(_utf8('hi'), '/home/user/docs/note.txt');
      expect(content.filename, 'note.txt');
    });

    test('sizeBytes matches data length', () {
      final data = _utf8('hello world');
      final content = _svc.loadContent(data, 'test.txt');
      expect(content.sizeBytes, data.length);
    });

    test('lineCount is set for text mode', () {
      final content = _svc.loadContent(_utf8('a\nb\nc'), 'file.txt');
      expect(content.lineCount, 3);
    });

    test('lineCount is null for image mode', () {
      final pngHeader = _bytes([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      ]);
      final content = _svc.loadContent(pngHeader, 'image.png');
      expect(content.lineCount, isNull);
    });

    test('encoding is set for text mode', () {
      final content = _svc.loadContent(_utf8('hello'), 'file.txt');
      expect(content.encoding, 'utf8');
    });

    test('mimeType is text/plain for .txt', () {
      final content = _svc.loadContent(_utf8('hi'), 'file.txt');
      expect(content.mimeType, 'text/plain');
    });

    test('mimeType is text/markdown for .md', () {
      final content = _svc.loadContent(_utf8('# Title'), 'README.md');
      expect(content.mimeType, 'text/markdown');
    });

    test('mimeType is application/pdf for .pdf', () {
      final pdfHeader = _bytes([0x25, 0x50, 0x44, 0x46, 0x2D]);
      final content = _svc.loadContent(pdfHeader, 'doc.pdf');
      expect(content.mimeType, 'application/pdf');
    });

    test('max file size guard throws StateError', () {
      // Create data slightly over 50 MB.
      final bigData = Uint8List(50 * 1024 * 1024 + 1);
      expect(
        () => _svc.loadContent(bigData, 'huge.bin'),
        throwsA(isA<StateError>()),
      );
    });

    test('exactly 50 MB is allowed', () {
      final maxData = Uint8List(50 * 1024 * 1024);
      expect(() => _svc.loadContent(maxData, 'max.bin'), returnsNormally);
    });

    test('empty file is handled gracefully', () {
      final content = _svc.loadContent(Uint8List(0), 'empty.txt');
      expect(content.sizeBytes, 0);
    });

    test('toJson contains required fields', () {
      final content = _svc.loadContent(_utf8('hello\nworld'), 'file.txt');
      final json = content.toJson();
      expect(json['filename'], 'file.txt');
      expect(json['mode'], 'text');
      expect(json['sizeBytes'], isA<int>());
      expect(json['lineCount'], isA<int>());
      expect(json['encoding'], 'utf8');
    });

    test('toJson omits null fields', () {
      final pngHeader = _bytes([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      ]);
      final content = _svc.loadContent(pngHeader, 'img.png');
      final json = content.toJson();
      expect(json.containsKey('lineCount'), isFalse);
      expect(json.containsKey('encoding'), isFalse);
    });
  });

  // ---- Search in content ---------------------------------------------------

  group('searchInContent', () {
    test('search in text finds case-insensitive matches', () {
      final content = _svc.loadContent(_utf8('Hello World hello'), 'file.txt');
      final offsets = _svc.searchInContent(content, 'hello');
      expect(offsets.length, 2);
    });

    test('search in text returns character offsets', () {
      final content = _svc.loadContent(_utf8('abcABC'), 'file.txt');
      final offsets = _svc.searchInContent(content, 'abc');
      expect(offsets, contains(0));
      expect(offsets, contains(3));
    });

    test('search with empty query returns empty list', () {
      final content = _svc.loadContent(_utf8('hello'), 'file.txt');
      expect(_svc.searchInContent(content, ''), isEmpty);
    });

    test('search in binary finds byte pattern', () {
      final data = _bytes([0x00, 0x41, 0x42, 0x43, 0x00, 0x41, 0x42]);
      final content = _svc.loadContent(data, 'dump.bin');
      final offsets = _svc.searchInContent(content, 'AB');
      // 'AB' as UTF-8 = [0x41, 0x42]; appears at index 1 and 5
      expect(offsets, containsAll([1, 5]));
    });

    test('search that finds nothing returns empty list', () {
      final content = _svc.loadContent(_utf8('hello'), 'file.txt');
      expect(_svc.searchInContent(content, 'xyz'), isEmpty);
    });
  });

  // ---- getSupportedExtensions completeness ---------------------------------

  group('getSupportedExtensions', () {
    final map = _svc.getSupportedExtensions();

    test('map is non-empty', () {
      expect(map, isNotEmpty);
    });

    test('text mode has multiple extensions', () {
      expect(map[ViewerMode.text]!.length, greaterThan(5));
    });

    test('image mode includes .png .jpg .gif .webp', () {
      final exts = map[ViewerMode.image]!;
      expect(exts, containsAll(['.png', '.jpg', '.gif', '.webp']));
    });

    test('markdown mode includes .md', () {
      expect(map[ViewerMode.markdown], contains('.md'));
    });

    test('pdf mode includes .pdf', () {
      expect(map[ViewerMode.pdf], contains('.pdf'));
    });

    test('all extension values are lower-case starting with dot', () {
      for (final list in map.values) {
        for (final ext in list) {
          expect(ext, startsWith('.'), reason: '$ext should start with a dot');
          expect(ext, ext.toLowerCase(), reason: '$ext should be lower-case');
        }
      }
    });
  });

  // ---- ViewerMode enum completeness ----------------------------------------

  group('ViewerMode enum', () {
    test('has 7 values', () {
      expect(ViewerMode.values.length, 7);
    });

    test('contains expected modes', () {
      expect(
        ViewerMode.values.map((m) => m.name),
        containsAll([
          'text',
          'hex',
          'image',
          'binary',
          'markdown',
          'pdf',
          'unsupported',
        ]),
      );
    });
  });
}
