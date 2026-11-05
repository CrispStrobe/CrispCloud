import 'package:crisp_cloud/services/file_list_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'imports quoted, relative and absolute paths and removes duplicates',
    () {
      expect(
        FileListPaths.parse(
          '\uFEFF"/docs/a b.txt"\r\n./a b.txt\nsub/../report.pdf\n\n',
          basePath: '/docs',
          local: true,
        ),
        ['/docs/a b.txt', '/docs/report.pdf'],
      );
    },
  );

  test('Windows paths preserve their filesystem syntax', () {
    expect(
      FileListPaths.parse(
        'C:\\Docs\\a.txt\r\na.txt\r\nsub\\b.txt',
        basePath: r'C:\Docs',
        local: true,
      ),
      [r'C:\Docs\a.txt', r'C:\Docs\sub\b.txt'],
    );
  });

  test('native file URLs are accepted only for a local source', () {
    expect(
      FileListPaths.parse(
        'file:///docs/a%20b.txt',
        basePath: '/docs',
        local: true,
      ),
      ['/docs/a b.txt'],
    );
    expect(
      () => FileListPaths.parse(
        'file:///docs/a.txt',
        basePath: '/',
        local: false,
      ),
      throwsFormatException,
    );
  });

  test(
    'cloud imports cannot silently reinterpret account URLs or Windows paths',
    () {
      for (final text in [
        'sftp://other.example/private/file',
        r'C:\private\file',
      ]) {
        expect(
          () => FileListPaths.parse(text, basePath: '/docs', local: false),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'refuses roots, control characters, empty input and oversized lists',
    () {
      for (final text in ['/', '/docs/..', '/docs/a\u0000.txt', '\n']) {
        expect(
          () => FileListPaths.parse(text, basePath: '/docs', local: true),
          throwsFormatException,
        );
      }
      expect(
        () => FileListPaths.parse(
          'a\nb',
          basePath: '/docs',
          local: true,
          maxItems: 1,
        ),
        throwsFormatException,
      );
    },
  );

  test('path lists round-trip and preserve punctuation', () {
    final paths = ['/docs/a,b.txt', '/docs/#1.txt', '/docs/[x].txt'];
    expect(
      FileListPaths.parse(
        FileListPaths.encode(paths),
        basePath: '/',
        local: false,
      ),
      paths,
    );
    expect(FileListPaths.encode([...paths, paths.first]), paths.join('\n'));
  });

  test('quoted export preserves filename whitespace', () {
    final paths = ['/docs/name with trailing space '];
    expect(
      FileListPaths.parse(
        FileListPaths.encode(paths),
        basePath: '/',
        local: true,
      ),
      paths,
    );
  });

  test('export refuses unrepresentable embedded newline rather than splitting a path', () {
    expect(
      () => FileListPaths.encode(['/docs/line\nbreak.txt']),
      throwsFormatException,
    );
  });
}
