import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_selection_pattern.dart';
import 'package:flutter_test/flutter_test.dart';

FileItem file(String name, {String? path, bool folder = false}) =>
    FileItem(name: name, path: path ?? '/$name', isFolder: folder);

void main() {
  group('Commander masks', () {
    test('alternatives and exclusions are applied together', () {
      final pattern = FileSelectionPattern('*.jpg;*.png|thumb*;private*');
      expect(pattern.matches(file('photo.JPG')), isTrue);
      expect(pattern.matches(file('figure.png')), isTrue);
      expect(pattern.matches(file('thumb-photo.jpg')), isFalse);
      expect(pattern.matches(file('private.png')), isFalse);
      expect(pattern.matches(file('readme.txt')), isFalse);
    });

    test('question mark matches exactly one Unicode character', () {
      final pattern = FileSelectionPattern('photo-?.png');
      expect(pattern.matches(file('photo-1.png')), isTrue);
      expect(pattern.matches(file('photo-😀.png')), isTrue);
      expect(pattern.matches(file('photo-12.png')), isFalse);
      expect(pattern.matches(file('photo-.png')), isFalse);
    });

    test('wildcards anchor the full filename, including repeated suffixes', () {
      final pattern = FileSelectionPattern('a*b');
      expect(pattern.matches(file('abb')), isTrue);
      expect(pattern.matches(file('xxab')), isFalse);
      expect(pattern.matches(file('abxx')), isFalse);
    });

    test('regex metacharacters are literal in wildcard mode', () {
      final pattern = FileSelectionPattern('a[1]+(x).txt');
      expect(pattern.matches(file('a[1]+(x).txt')), isTrue);
      expect(pattern.matches(file('a1x.txt')), isFalse);
    });

    test('Commander *.* includes extensionless files and dotfiles', () {
      final pattern = FileSelectionPattern('*.*');
      expect(pattern.matches(file('README')), isTrue);
      expect(pattern.matches(file('.gitignore')), isTrue);
      expect(pattern.matches(file('file.txt')), isTrue);
    });

    test('an exclusions-only expression includes everything else', () {
      final pattern = FileSelectionPattern('|*.tmp;*.bak');
      expect(pattern.matches(file('report.pdf')), isTrue);
      expect(pattern.matches(file('report.tmp')), isFalse);
    });

    test('case sensitivity is explicit', () {
      final pattern = FileSelectionPattern('*.TXT', caseSensitive: true);
      expect(pattern.matches(file('file.TXT')), isTrue);
      expect(pattern.matches(file('file.txt')), isFalse);
    });

    test('full-path matching distinguishes duplicate basenames', () {
      final pattern = FileSelectionPattern(
        '/photos/*|*/private/*',
        matchFullPath: true,
      );
      expect(
        pattern.matches(file('same.jpg', path: '/photos/a/same.jpg')),
        isTrue,
      );
      expect(
        pattern.matches(file('same.jpg', path: '/photos/private/same.jpg')),
        isFalse,
      );
      expect(
        pattern.matches(file('same.jpg', path: '/elsewhere/same.jpg')),
        isFalse,
      );
      expect(
        pattern.matches(FileItem(name: 'same.jpg', isFolder: false)),
        isFalse,
      );
    });

    test('file/folder scope and parent exclusion are independent of masks', () {
      final files = FileSelectionPattern('*', includeFolders: false);
      final folders = FileSelectionPattern('*', includeFiles: false);
      expect(files.matches(file('docs', folder: true)), isFalse);
      expect(folders.matches(file('docs', folder: true)), isTrue);
      expect(folders.matches(file('docs.txt')), isFalse);
      expect(
        FileSelectionPattern('*').matches(file('..', folder: true)),
        isFalse,
      );
      expect(
        FileSelectionPattern('*').matches(file('.', folder: true)),
        isFalse,
      );
    });

    test('invalid masks fail before selection can be changed', () {
      for (final expression in ['', ' ', ';', '*.jpg|', '*|a|b']) {
        expect(
          () => FileSelectionPattern(expression),
          throwsFormatException,
          reason: expression,
        );
      }
      expect(
        () => FileSelectionPattern(
          '*',
          includeFiles: false,
          includeFolders: false,
        ),
        throwsFormatException,
      );
    });
  });

  group('regex selection', () {
    test(
      'supports alternation and anchors without treating | as exclusions',
      () {
        final pattern = FileSelectionPattern(
          r'^(invoice|report)-\d{4}\.pdf$',
          mode: FilePatternMode.regex,
        );
        expect(pattern.matches(file('invoice-2026.pdf')), isTrue);
        expect(pattern.matches(file('report-2025.PDF')), isTrue);
        expect(pattern.matches(file('report-25.pdf')), isFalse);
        expect(pattern.matches(file('prefix-report-2025.pdf')), isFalse);
      },
    );

    test('unanchored regex searches within the name', () {
      final pattern = FileSelectionPattern(
        r'\d{4}',
        mode: FilePatternMode.regex,
      );
      expect(pattern.matches(file('report-2026-final.pdf')), isTrue);
      expect(pattern.matches(file('report-final.pdf')), isFalse);
    });

    test(
      'invalid regex is reported rather than silently selecting nothing',
      () {
        expect(
          () => FileSelectionPattern('[', mode: FilePatternMode.regex),
          throwsFormatException,
        );
      },
    );
  });
}
