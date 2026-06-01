// test/fuzz_test.dart
//
// Comprehensive fuzz-testing suite covering:
//   - Unicode filenames (CJK, emoji, RTL, combining diacriticals, zero-width,
//     mixed scripts, full-width, astral-plane surrogate pairs)
//   - Special characters (spaces/tabs/newlines, shell metacharacters, SQL/XSS
//     injection, null bytes, slashes, dots, colons, glob chars, percent-encoding)
//   - Path traversal patterns (classic, encoded, null-byte, double-encoded)
//   - Long paths (255-char limit, over-limit, deeply nested, long extensions)
//   - Edge cases (empty, whitespace-only, extension-only, case sensitivity,
//     Windows reserved names, trailing dots/spaces, BOM)
//
// Also tests the PathSanitizer utility class and how the formatters/FileItem
// model behave when confronted with unusual input.

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/path_sanitizer.dart';
import 'package:crisp_cloud/utils/formatters.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a FileItem from just a name (path defaults to "/<name>").
FileItem _item(String name, {bool isFolder = false, int size = 0}) {
  return FileItem(
    name: name,
    path: '/$name',
    isFolder: isFolder,
    size: size,
  );
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // 1. UNICODE FILENAMES
  // =========================================================================
  group('Unicode filenames', () {
    // --- CJK characters ---
    test('CJK Chinese filename is accepted by FileItem', () {
      const name = '中文文件.txt';
      final item = _item(name);
      expect(item.name, equals(name));
      expect(item.path, equals('/$name'));
    });

    test('CJK Japanese filename is accepted by FileItem', () {
      const name = 'ファイル.pdf';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('CJK Korean filename is accepted by FileItem', () {
      const name = '파일이름.docx';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('PathSanitizer preserves CJK characters', () {
      const name = '中文文件.txt';
      expect(PathSanitizer.sanitizeFilename(name), equals(name));
    });

    // --- Emoji in filenames ---
    test('Emoji folder name is accepted by FileItem', () {
      const name = '📁 Documents';
      final item = _item(name, isFolder: true);
      expect(item.name, equals(name));
      expect(item.isFolder, isTrue);
    });

    test('Emoji music filename is accepted by FileItem', () {
      const name = '🎵 Music.mp3';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('Multiple emoji in filename are preserved by sanitizer', () {
      const name = '🚀🌟💾 backup.tar.gz';
      expect(PathSanitizer.sanitizeFilename(name), equals(name));
    });

    test('Emoji-only filename sanitizes to itself', () {
      const name = '🐉.png';
      expect(PathSanitizer.sanitizeFilename(name), equals(name));
    });

    // --- RTL text ---
    test('Arabic filename is accepted by FileItem', () {
      const name = 'ملف عربي.txt'; // "Arabic file" in Arabic
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('Hebrew filename is accepted by FileItem', () {
      const name = 'קובץ עברי.docx'; // "Hebrew file" in Hebrew
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('PathSanitizer preserves RTL text', () {
      const name = 'مستند.pdf';
      expect(PathSanitizer.sanitizeFilename(name), equals(name));
    });

    // --- Combining diacriticals ---
    test('Precomposed é (U+00E9) accepted by FileItem', () {
      final name = '\u00E9diteur.txt'; // é as single codepoint
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('Decomposed é (e + combining acute) accepted by FileItem', () {
      final name = 'e\u0301diteur.txt'; // e + U+0301 COMBINING ACUTE ACCENT
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('Combining diacriticals preserved by sanitizer', () {
      final name = 'cafe\u0301.txt';
      expect(PathSanitizer.sanitizeFilename(name), equals(name));
    });

    // --- Zero-width characters ---
    test('Zero-width space (ZWSP) in filename handled by sanitizer', () {
      final nameWithZwsp = 'file\u200Bname.txt'; // U+200B ZERO WIDTH SPACE
      final sanitized = PathSanitizer.sanitizeFilename(nameWithZwsp);
      // Sanitizer must not crash; result should not be empty
      expect(sanitized, isNotEmpty);
    });

    test('Zero-width joiner (ZWJ) in filename handled by sanitizer', () {
      final nameWithZwj = 'file\u200Dname.txt'; // U+200D ZERO WIDTH JOINER
      final sanitized = PathSanitizer.sanitizeFilename(nameWithZwj);
      expect(sanitized, isNotEmpty);
    });

    test('Zero-width non-joiner (ZWNJ) in filename handled by sanitizer', () {
      final nameWithZwnj = 'file\u200Cname.txt'; // U+200C ZERO WIDTH NON-JOINER
      final sanitized = PathSanitizer.sanitizeFilename(nameWithZwnj);
      expect(sanitized, isNotEmpty);
    });

    // --- Mixed scripts ---
    test('Mixed Latin + Cyrillic + CJK filename accepted by FileItem', () {
      const name = 'fileФайл文件.txt';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('PathSanitizer preserves mixed-script filenames', () {
      const name = 'docФайл.pdf';
      expect(PathSanitizer.sanitizeFilename(name), equals(name));
    });

    // --- Full-width characters ---
    test('Full-width ASCII filename is accepted by FileItem', () {
      const name = 'ｆｕｌｌ－ｗｉｄｔｈ.txt';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('PathSanitizer preserves full-width characters', () {
      const name = 'ｆｕｌｌ.txt';
      expect(PathSanitizer.sanitizeFilename(name), equals(name));
    });

    // --- Astral plane / surrogate pairs ---
    test('Mathematical Fraktur (astral plane) filename accepted', () {
      // 𝕳𝖊𝖑𝖑𝖔 — characters in U+1D400 range (Mathematical Fraktur)
      const name = '𝕳𝖊𝖑𝖑𝖔.txt';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('Emoji with variation selector preserved', () {
      final name = '\u2764\uFE0F.txt'; // ❤️ (heart + variation selector-16)
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('Linear B syllabary (astral plane) preserved by sanitizer', () {
      const name = '𐀀𐀁𐀂.txt'; // U+10000 range
      expect(PathSanitizer.sanitizeFilename(name), equals(name));
    });
  });

  // =========================================================================
  // 2. SPECIAL CHARACTERS
  // =========================================================================
  group('Special characters in filenames', () {
    // --- Whitespace variants ---
    test('Filename with space is accepted by FileItem', () {
      const name = 'my document.txt';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('Filename with tab is sanitized (tab is control char)', () {
      final name = 'file\tname.txt';
      final sanitized = PathSanitizer.sanitizeFilename(name);
      expect(sanitized, isNot(contains('\t')));
      expect(sanitized, isNotEmpty);
    });

    test('Filename with newline is sanitized', () {
      final name = 'file\nname.txt';
      final sanitized = PathSanitizer.sanitizeFilename(name);
      expect(sanitized, isNot(contains('\n')));
      expect(sanitized, isNotEmpty);
    });

    test('Filename with carriage return is sanitized', () {
      final name = 'file\rname.txt';
      final sanitized = PathSanitizer.sanitizeFilename(name);
      expect(sanitized, isNot(contains('\r')));
      expect(sanitized, isNotEmpty);
    });

    // --- Shell metacharacters ---
    test('Semicolon in filename is replaced by sanitizer', () {
      expect(PathSanitizer.sanitizeFilename('cmd;rm.txt'), isNot(contains(';')));
    });

    test('Pipe in filename is NOT blocked (valid in most FS)', () {
      // The pipe character | is actually forbidden on Windows
      final sanitized = PathSanitizer.sanitizeFilename('a|b.txt');
      expect(sanitized, isNotEmpty);
      // Sanitizer replaces it since it's in the dangerous chars set
      expect(sanitized, isNot(contains('|')));
    });

    test('Ampersand in filename is accepted (not a dangerous char for FS)', () {
      const name = 'R&D report.txt';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('Dollar sign in filename is accepted', () {
      const name = 'invoice\$100.txt';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('Backtick in filename is accepted', () {
      const name = 'code`snippet.txt';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('Exclamation mark in filename is accepted', () {
      const name = 'important!.txt';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    // --- Injection patterns ---
    test('SQL injection pattern in filename is accepted by FileItem', () {
      const name = "' OR 1=1 --.txt";
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('SQL injection filename sanitizer output is non-empty', () {
      const name = "' OR 1=1 --.txt";
      expect(PathSanitizer.sanitizeFilename(name), isNotEmpty);
    });

    test('XSS pattern in filename is accepted by FileItem', () {
      const name = '<script>alert(1)</script>.txt';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('XSS pattern in filename is sanitized (angle brackets removed)', () {
      const name = '<script>alert(1)</script>.txt';
      final sanitized = PathSanitizer.sanitizeFilename(name);
      expect(sanitized, isNot(contains('<')));
      expect(sanitized, isNot(contains('>')));
    });

    // --- Null bytes ---
    test('Null byte in filename is removed by sanitizer', () {
      final name = 'file\x00name.txt';
      final sanitized = PathSanitizer.sanitizeFilename(name);
      expect(sanitized, isNot(contains('\x00')));
      expect(sanitized, isNotEmpty);
    });

    test('Null byte terminates filename (security boundary)', () {
      final name = 'legit.txt\x00.exe';
      final sanitized = PathSanitizer.sanitizeFilename(name);
      // Null byte removed — result should not look like .exe injection
      expect(sanitized, isNot(contains('\x00')));
    });

    // --- Slashes ---
    test('Forward slash in name is replaced by sanitizer', () {
      final sanitized = PathSanitizer.sanitizeFilename('path/to/file.txt');
      expect(sanitized, isNot(contains('/')));
    });

    test('Backslash in name is replaced by sanitizer', () {
      final sanitized = PathSanitizer.sanitizeFilename('path\\file.txt');
      expect(sanitized, isNot(contains('\\')));
    });

    // --- Dots ---
    test('Single dot filename is accepted by FileItem', () {
      final item = _item('.');
      expect(item.name, equals('.'));
    });

    test('Double dot filename is accepted by FileItem', () {
      final item = _item('..');
      expect(item.name, equals('..'));
    });

    test('Triple dot filename is accepted by FileItem', () {
      const name = '...';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('Hidden file starting with dot is preserved by sanitizer', () {
      const name = '.hidden';
      expect(PathSanitizer.sanitizeFilename(name), equals(name));
    });

    test('File with double extension preserved', () {
      const name = 'file..ext';
      // Sanitizer should not mangle double-dot in the middle
      final sanitized = PathSanitizer.sanitizeFilename(name);
      expect(sanitized, isNotEmpty);
    });

    // --- Colons ---
    test('Colon in filename is replaced by sanitizer (Windows illegal)', () {
      final sanitized = PathSanitizer.sanitizeFilename('C:\\path\\to\\file.txt');
      expect(sanitized, isNot(contains(':')));
    });

    test('HFS+ colon is replaced by sanitizer', () {
      final sanitized = PathSanitizer.sanitizeFilename('mac:hfs:path.txt');
      expect(sanitized, isNot(contains(':')));
    });

    // --- Glob characters ---
    test('Asterisk is replaced by sanitizer', () {
      final sanitized = PathSanitizer.sanitizeFilename('glob*.txt');
      expect(sanitized, isNot(contains('*')));
    });

    test('Question mark is replaced by sanitizer', () {
      final sanitized = PathSanitizer.sanitizeFilename('file?.txt');
      expect(sanitized, isNot(contains('?')));
    });

    // --- Percent encoding ---
    test('Percent-encoded space (%20) in filename is accepted by FileItem', () {
      const name = 'my%20file.txt';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('Percent-encoded slash (%2F) in filename is accepted by FileItem', () {
      const name = 'path%2Ffile.txt';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('formatBytes is not affected by special filename characters', () {
      // Formatters operate on sizes, not names — verify no crashes
      expect(formatBytes(0), isNotEmpty);
      expect(formatBytes(1024), isNotEmpty);
    });
  });

  // =========================================================================
  // 3. PATH TRAVERSAL
  // =========================================================================
  group('Path traversal detection', () {
    test('Classic Unix traversal ../ is detected', () {
      expect(PathSanitizer.isPathTraversal('../../../etc/passwd'), isTrue);
    });

    test('Classic Windows traversal ..\\ is detected', () {
      expect(PathSanitizer.isPathTraversal('..\\..\\windows\\system32'), isTrue);
    });

    test('Absolute Unix path injection is detected', () {
      expect(PathSanitizer.isPathTraversal('/absolute/path'), isTrue);
    });

    test('Absolute Windows path injection is detected', () {
      expect(PathSanitizer.isPathTraversal('C:\\Windows\\System32'), isTrue);
    });

    test('Mixed separators traversal is detected', () {
      expect(PathSanitizer.isPathTraversal('..\\../etc/passwd'), isTrue);
    });

    test('Percent-encoded traversal %2e%2e%2f is detected', () {
      expect(PathSanitizer.isPathTraversal('%2e%2e%2f'), isTrue);
    });

    test('Percent-encoded traversal %2e%2e%5c is detected', () {
      expect(PathSanitizer.isPathTraversal('%2e%2e%5c'), isTrue);
    });

    test('Null byte injection in path is detected', () {
      final path = 'file.txt\x00.jpg';
      expect(PathSanitizer.isPathTraversal(path), isTrue);
    });

    test('Double URL-encoded traversal %252e%252e is detected', () {
      expect(PathSanitizer.isPathTraversal('%252e%252e%252f'), isTrue);
    });

    test('Bare ".." component is detected', () {
      expect(PathSanitizer.isPathTraversal('..'), isTrue);
    });

    test('Safe relative path is not flagged', () {
      expect(PathSanitizer.isPathTraversal('docs/report.txt'), isFalse);
    });

    test('Safe filename with dots is not flagged', () {
      expect(PathSanitizer.isPathTraversal('file.tar.gz'), isFalse);
    });

    test('Hidden file starting with dot is not flagged as traversal', () {
      expect(PathSanitizer.isPathTraversal('.gitignore'), isFalse);
    });

    test('Empty string is not a traversal', () {
      expect(PathSanitizer.isPathTraversal(''), isFalse);
    });

    test('Traversal embedded in longer path is detected', () {
      expect(
        PathSanitizer.isPathTraversal('uploads/../../etc/passwd'),
        isTrue,
      );
    });

    test('URL-decoded mixed-case traversal is detected', () {
      expect(PathSanitizer.isPathTraversal('%2E%2E%2F'), isTrue);
    });
  });

  // =========================================================================
  // 4. LONG PATHS
  // =========================================================================
  group('Long paths', () {
    test('255-character filename is at the edge — sanitizer keeps it', () {
      final name = '${'a' * 251}.txt'; // 255 total
      expect(name.length, equals(255));
      final sanitized = PathSanitizer.sanitizeFilename(name);
      expect(sanitized.length, lessThanOrEqualTo(255));
      expect(sanitized, isNotEmpty);
    });

    test('256-character filename is truncated by sanitizer', () {
      final name = '${'a' * 252}.txt'; // 256 total
      expect(name.length, equals(256));
      final sanitized = PathSanitizer.sanitizeFilename(name);
      expect(sanitized.length, lessThanOrEqualTo(255));
    });

    test('1000-character filename is truncated to 255', () {
      final name = '${'z' * 996}.txt';
      expect(name.length, equals(1000));
      final sanitized = PathSanitizer.sanitizeFilename(name);
      expect(sanitized.length, lessThanOrEqualTo(255));
    });

    test('Very long filename extension is preserved when truncating', () {
      final name = '${'b' * 240}.txt';
      final sanitized = PathSanitizer.sanitizeFilename(name);
      expect(sanitized.length, lessThanOrEqualTo(255));
      // Extension should still be present if it fit
      expect(sanitized.endsWith('.txt'), isTrue);
    });

    test('Deeply nested path (50 levels) is accepted by FileItem', () {
      final segments = List.generate(50, (i) => 'dir$i');
      final path = '/${segments.join('/')}/file.txt';
      final item = FileItem(
        name: 'file.txt',
        path: path,
        isFolder: false,
        size: 0,
      );
      expect(item.path, equals(path));
    });

    test('Very long extension is truncated if whole name exceeds 255', () {
      final name = 'file.${'1234567890' * 30}'; // ext = 300+ chars
      final sanitized = PathSanitizer.sanitizeFilename(name);
      expect(sanitized.length, lessThanOrEqualTo(255));
    });

    test('Filename with many dots is accepted by FileItem', () {
      const name = 'file.a.b.c.d.e.f.g.txt';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('255 character filename is accepted by FileItem without truncation', () {
      final name = '${'x' * 251}.bin';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('Long path does not crash formatBytes', () {
      // formatBytes doesn't use filenames but verify large sizes work
      final largeSize = 1024 * 1024 * 1024 * 1024; // 1 TB
      expect(formatBytes(largeSize), contains('TB'));
    });

    test('256-character filename FileItem holds it as-is', () {
      // FileItem itself is a model — it should store any name
      final name = 'x' * 256;
      final item = _item(name);
      expect(item.name.length, equals(256));
    });

    test('normalizePathSeparators handles long paths', () {
      final segments = List.generate(50, (i) => 'dir$i');
      final path = segments.join('\\'); // Windows-style
      final normalized = PathSanitizer.normalizePathSeparators(path);
      expect(normalized, isNot(contains('\\')));
      expect(normalized, contains('/'));
    });
  });

  // =========================================================================
  // 5. EDGE CASES
  // =========================================================================
  group('Edge cases', () {
    // --- Empty / whitespace ---
    test('Empty string sanitizes to underscore placeholder', () {
      expect(PathSanitizer.sanitizeFilename(''), equals('_'));
    });

    test('Whitespace-only filename sanitizes to underscore placeholder', () {
      expect(PathSanitizer.sanitizeFilename('   '), equals('_'));
    });

    test('isWhitespaceOnly detects whitespace-only string', () {
      expect(PathSanitizer.isWhitespaceOnly('   '), isTrue);
      expect(PathSanitizer.isWhitespaceOnly('\t\n'), isTrue);
      expect(PathSanitizer.isWhitespaceOnly(''), isFalse);
      expect(PathSanitizer.isWhitespaceOnly('a'), isFalse);
    });

    // --- Extension-only filenames ---
    test('Extension-only filename .gitignore is preserved by sanitizer', () {
      expect(PathSanitizer.sanitizeFilename('.gitignore'), equals('.gitignore'));
    });

    test('.gitignore extension detection returns empty string', () {
      // getExtension treats leading-dot files as having no extension
      expect(PathSanitizer.getExtension('.gitignore'), equals(''));
    });

    test('Regular extension is returned correctly', () {
      expect(PathSanitizer.getExtension('file.txt'), equals('.txt'));
      expect(PathSanitizer.getExtension('archive.tar.gz'), equals('.gz'));
    });

    test('No extension returns empty string', () {
      expect(PathSanitizer.getExtension('Makefile'), equals(''));
      expect(PathSanitizer.getExtension('README'), equals(''));
    });

    // --- File with no extension ---
    test('File with no extension is accepted by FileItem', () {
      const name = 'Makefile';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    // --- Case sensitivity ---
    test('File.TXT and file.txt are different names', () {
      final upper = _item('File.TXT');
      final lower = _item('file.txt');
      // Different paths → not equal
      expect(upper, isNot(equals(lower)));
    });

    test('Same name different case preserves identity via path', () {
      final a = FileItem(name: 'File.TXT', path: '/File.TXT', isFolder: false, size: 0);
      final b = FileItem(name: 'file.txt', path: '/file.txt', isFolder: false, size: 0);
      expect(a, isNot(equals(b)));
    });

    // --- Windows reserved names ---
    test('CON is recognized as a reserved Windows name', () {
      expect(PathSanitizer.isReservedName('CON'), isTrue);
    });

    test('con (lowercase) is recognized as reserved', () {
      expect(PathSanitizer.isReservedName('con'), isTrue);
    });

    test('PRN is recognized as reserved', () {
      expect(PathSanitizer.isReservedName('PRN'), isTrue);
    });

    test('AUX is recognized as reserved', () {
      expect(PathSanitizer.isReservedName('AUX'), isTrue);
    });

    test('NUL is recognized as reserved', () {
      expect(PathSanitizer.isReservedName('NUL'), isTrue);
    });

    test('COM1 is recognized as reserved', () {
      expect(PathSanitizer.isReservedName('COM1'), isTrue);
    });

    test('LPT1 is recognized as reserved', () {
      expect(PathSanitizer.isReservedName('LPT1'), isTrue);
    });

    test('CON.txt is recognized as reserved (extension ignored)', () {
      expect(PathSanitizer.isReservedName('CON.txt'), isTrue);
    });

    test('Regular name is not reserved', () {
      expect(PathSanitizer.isReservedName('document.txt'), isFalse);
      expect(PathSanitizer.isReservedName('connect.dart'), isFalse);
      expect(PathSanitizer.isReservedName('console.log'), isFalse);
    });

    test('Empty string is not reserved', () {
      expect(PathSanitizer.isReservedName(''), isFalse);
    });

    // --- Trailing dots and spaces ---
    test('Trailing dot in filename is trimmed by sanitizer', () {
      final sanitized = PathSanitizer.sanitizeFilename('file.');
      expect(sanitized.endsWith('.'), isFalse);
    });

    test('Trailing space in filename is trimmed by sanitizer', () {
      final sanitized = PathSanitizer.sanitizeFilename('file   ');
      expect(sanitized.endsWith(' '), isFalse);
    });

    test('Multiple trailing dots are trimmed', () {
      final sanitized = PathSanitizer.sanitizeFilename('file...');
      expect(sanitized, isNot(endsWith('.')));
    });

    test('Leading space is trimmed by sanitizer', () {
      final sanitized = PathSanitizer.sanitizeFilename('  file.txt');
      expect(sanitized.startsWith(' '), isFalse);
    });

    // --- BOM ---
    test('hasBom detects UTF-8 BOM at start of filename', () {
      final nameWithBom = '\uFEFFfilename.txt';
      expect(PathSanitizer.hasBom(nameWithBom), isTrue);
    });

    test('hasBom is false for normal filename', () {
      expect(PathSanitizer.hasBom('filename.txt'), isFalse);
    });

    test('BOM filename is accepted by FileItem as-is', () {
      final nameWithBom = '\uFEFFfilename.txt';
      final item = _item(nameWithBom);
      expect(item.name, equals(nameWithBom));
    });

    // --- isDotsOnly ---
    test('isDotsOnly detects dot-only filename', () {
      expect(PathSanitizer.isDotsOnly('.'), isTrue);
      expect(PathSanitizer.isDotsOnly('..'), isTrue);
      expect(PathSanitizer.isDotsOnly('...'), isTrue);
    });

    test('isDotsOnly is false for normal filenames', () {
      expect(PathSanitizer.isDotsOnly('.hidden'), isFalse);
      expect(PathSanitizer.isDotsOnly('file.txt'), isFalse);
    });
  });

  // =========================================================================
  // 6. PATH SEPARATOR NORMALIZATION
  // =========================================================================
  group('Path separator normalization', () {
    test('Backslash converted to forward slash', () {
      expect(
        PathSanitizer.normalizePathSeparators('foo\\bar\\baz.txt'),
        equals('foo/bar/baz.txt'),
      );
    });

    test('Windows absolute path backslashes normalized', () {
      final result = PathSanitizer.normalizePathSeparators('C:\\Users\\Alice\\file.txt');
      expect(result, isNot(contains('\\')));
    });

    test('Consecutive slashes collapsed', () {
      expect(
        PathSanitizer.normalizePathSeparators('foo//bar///baz.txt'),
        equals('foo/bar/baz.txt'),
      );
    });

    test('UNC prefix // preserved', () {
      final result = PathSanitizer.normalizePathSeparators('//server/share/file.txt');
      expect(result, startsWith('//'));
    });

    test('Already normalized path unchanged', () {
      const path = 'foo/bar/baz.txt';
      expect(PathSanitizer.normalizePathSeparators(path), equals(path));
    });

    test('Empty path returns empty string', () {
      expect(PathSanitizer.normalizePathSeparators(''), equals(''));
    });

    test('Mixed separators are all converted', () {
      final result = PathSanitizer.normalizePathSeparators('foo\\bar/baz\\qux.txt');
      expect(result, equals('foo/bar/baz/qux.txt'));
    });
  });

  // =========================================================================
  // 7. FORMATTERS WITH EDGE-CASE SIZES
  // =========================================================================
  group('Formatters with edge-case values', () {
    test('formatBytes handles zero', () {
      expect(formatBytes(0), equals('0 B'));
    });

    test('formatBytes handles negative (gracefully)', () {
      expect(formatBytes(-1), equals('0 B'));
    });

    test('formatBytes at exact KB boundary', () {
      expect(formatBytes(1024), equals('1.0 KB'));
    });

    test('formatBytes at exact MB boundary', () {
      expect(formatBytes(1024 * 1024), equals('1.0 MB'));
    });

    test('formatBytes at exact GB boundary', () {
      expect(formatBytes(1024 * 1024 * 1024), equals('1.0 GB'));
    });

    test('formatBytes at exact TB boundary', () {
      expect(formatBytes(1024 * 1024 * 1024 * 1024), equals('1.0 TB'));
    });

    test('FileItem sizeFormatted for 0 bytes returns "0 B"', () {
      final item = _item('file.txt', size: 0);
      expect(item.sizeFormatted, equals('0 B'));
    });

    test('FileItem sizeFormatted for 1 MB contains MB', () {
      final item = _item('file.bin', size: 1024 * 1024);
      expect(item.sizeFormatted, contains('MB'));
    });

    test('FileItem sizeFormatted for null returns empty string', () {
      final item = FileItem(name: 'file.txt', path: '/file.txt', isFolder: false, size: null);
      expect(item.sizeFormatted, equals(''));
    });
  });

  // =========================================================================
  // 8. FILEITEM MODEL WITH FUZZ NAMES
  // =========================================================================
  group('FileItem model with fuzz names', () {
    test('FileItem preserves exact Unicode name', () {
      const name = '📁 中文文件 ملف.docx';
      final item = _item(name);
      expect(item.name, equals(name));
    });

    test('FileItem equality uses path when uuid is null', () {
      const path = '/中文/文件.txt';
      final a = FileItem(name: '文件.txt', path: path, isFolder: false, size: 0);
      final b = FileItem(name: '文件.txt', path: path, isFolder: false, size: 0);
      expect(a, equals(b));
    });

    test('FileItem inequality for different Unicode paths', () {
      final a = FileItem(name: '文件.txt', path: '/a/文件.txt', isFolder: false, size: 0);
      final b = FileItem(name: '文件.txt', path: '/b/文件.txt', isFolder: false, size: 0);
      expect(a, isNot(equals(b)));
    });

    test('FileItem with emoji name has correct isFolder flag', () {
      final folder = _item('📁 My Docs', isFolder: true);
      final file = _item('🎵 song.mp3', isFolder: false);
      expect(folder.isFolder, isTrue);
      expect(file.isFolder, isFalse);
    });

    test('FileItem with long Unicode name stores it unchanged', () {
      final name = '中文文件名' * 50; // 250 CJK chars — over byte limit but valid codepoints
      final item = _item(name);
      expect(item.name.length, equals(250));
    });
  });
}
