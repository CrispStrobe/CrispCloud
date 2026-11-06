import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/multi_rename_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

FileItem _file(String path, {bool folder = false, DateTime? modified}) =>
    FileItem(
      name: p.posix.basename(path),
      path: path,
      isFolder: folder,
      updatedAt: modified,
    );

void main() {
  const service = MultiRenameService();
  MultiRenamePlan plan(
    List<FileItem> files, [
    MultiRenameOptions options = const MultiRenameOptions(),
  ]) => service.preview(files, options, directory: '/photos');

  group('Commander rename masks', () {
    test('combines name and extension masks with counter controls', () {
      final result = plan(
        [_file('/photos/IMG_01.JPG'), _file('/photos/IMG_02.JPG')],
        const MultiRenameOptions(
          nameMask: 'Trip_[N5-]_[C]',
          extensionMask: '[E]',
          counterStart: 7,
          counterStep: 2,
          counterWidth: 4,
          extensionCase: RenameCase.lower,
        ),
      );
      expect(result.isValid, isTrue);
      expect(result.entries.map((entry) => entry.newName), [
        'Trip_01_0007.jpg',
        'Trip_02_0009.jpg',
      ]);
      expect(result.entries.first.targetPath, '/photos/Trip_01_0007.jpg');
    });

    test('date and parent tokens use original metadata and parent path', () {
      final result = plan([
        _file('/photos/Trip/IMG.jpg', modified: DateTime(2024, 2, 3, 4, 5, 6)),
      ], const MultiRenameOptions(nameMask: '[P]_[Y][M][D]_[h][m][s]_[C:2]'));
      expect(result.entries.single.newName, 'Trip_20240203_040506_01.jpg');
      expect(result.isValid, isTrue);
    });

    test('missing modified time is an error, never the current date', () {
      final result = plan([
        _file('/photos/a.txt'),
      ], const MultiRenameOptions(nameMask: '[Y]-[N]'));
      expect(result.isValid, isFalse);
      expect(result.entries.single.errors.single, contains('no modified time'));
    });

    test(
      'substrings count Unicode code points and support negative ranges',
      () {
        final result = plan([
          _file('/photos/a😀cdef.txt'),
        ], const MultiRenameOptions(nameMask: '[N2]_[N-3--1]_[N3-]'));
        expect(result.entries.single.newName, '😀_def_cdef.txt');
      },
    );

    test('escaped brackets are literal and do not re-expand source names', () {
      final result = plan([
        _file('/photos/[C].txt'),
      ], const MultiRenameOptions(nameMask: '[[[N]]]'));
      expect(result.entries.single.newName, '[[C]].txt');
      expect(result.isValid, isTrue);
    });

    test('empty extension mask removes extensions; dotfiles stay names', () {
      final result = plan([
        _file('/photos/.gitignore'),
        _file('/photos/README'),
        _file('/photos/file.tar.gz'),
      ], const MultiRenameOptions(nameMask: '[N]_old', extensionMask: ''));
      expect(result.entries.map((entry) => entry.newName), [
        '.gitignore_old',
        'README_old',
        'file.tar_old',
      ]);
    });

    test('directory names with dots have no extension', () {
      final result = plan([
        _file('/photos/archive.v1', folder: true),
      ], const MultiRenameOptions(nameMask: '[N]_new', extensionMask: 'zip'));
      expect(result.entries.single.newName, 'archive.v1_new');
    });

    test('independent case settings follow replacement', () {
      final result = plan(
        [_file('/photos/MY_FILE.TxT')],
        const MultiRenameOptions(
          find: '_',
          replace: ' ',
          nameCase: RenameCase.title,
          extensionCase: RenameCase.upper,
        ),
      );
      expect(result.entries.single.newName, 'My File.TXT');
    });

    test('invalid masks, counters, and regexes prevent execution', () {
      for (final options in [
        const MultiRenameOptions(nameMask: '[unknown]'),
        const MultiRenameOptions(nameMask: '[N'),
        const MultiRenameOptions(nameMask: '[N0]'),
        const MultiRenameOptions(nameMask: '[C:20]'),
        const MultiRenameOptions(counterWidth: 0),
        const MultiRenameOptions(counterStart: -1),
        const MultiRenameOptions(useRegex: true, find: '('),
      ]) {
        final result = plan([_file('/photos/a.txt')], options);
        expect(result.canExecute, isFalse);
        expect(result.isValid, isFalse);
      }
    });

    test('descending counters report underflow on affected row', () {
      final result = plan(
        [_file('/photos/a.txt'), _file('/photos/b.txt')],
        const MultiRenameOptions(
          nameMask: '[C]',
          counterStart: 0,
          counterStep: -1,
        ),
      );
      expect(result.entries.first.newName, '000.txt');
      expect(result.entries.last.errors.single, contains('outside'));
      expect(result.canExecute, isFalse);
    });
  });

  group('search and replacement', () {
    test('expands numbered, named and literal-dollar regex replacements', () {
      final result = plan(
        [_file('/photos/report-2026.txt')],
        const MultiRenameOptions(
          useRegex: true,
          find: r'(?<word>report)-(\d+)',
          replace: r'${word}_$2_$$',
        ),
      );
      expect(result.entries.single.newName, r'report_2026_$.txt');
    });

    test('literal replacement keeps dollar references as literal text', () {
      final result = plan([
        _file('/photos/a(1).txt'),
      ], const MultiRenameOptions(find: '(1)', replace: r'$1'));
      expect(result.entries.single.newName, r'a$1.txt');
    });

    test(
      'case-insensitive first-match replacement only changes requested scope',
      () {
        final result = plan(
          [_file('/photos/AA.aa')],
          const MultiRenameOptions(
            find: 'a',
            replace: 'b',
            caseSensitive: false,
            firstMatchOnly: true,
            replaceScope: RenameReplaceScope.name,
          ),
        );
        expect(result.entries.single.newName, 'bA.aa');
      },
    );

    test('extension-only replacement does not rename dotted directories', () {
      final result = plan(
        [_file('/photos/a.JPG'), _file('/photos/folder.JPG', folder: true)],
        const MultiRenameOptions(
          find: 'JPG',
          replace: 'jpeg',
          replaceScope: RenameReplaceScope.extension,
        ),
      );
      expect(result.entries.map((entry) => entry.newName), [
        'a.jpeg',
        'folder.JPG',
      ]);
    });
  });

  group('safe plans and full paths', () {
    test('duplicate basenames in different folders remain distinct', () {
      final result = plan([
        _file('/a/image.jpg'),
        _file('/b/image.jpg'),
      ], const MultiRenameOptions(nameMask: 'holiday'));
      expect(result.isValid, isTrue);
      expect(result.entries.map((entry) => entry.targetPath), [
        '/a/holiday.jpg',
        '/b/holiday.jpg',
      ]);
    });

    test(
      'Windows paths use their native parent rather than the active folder',
      () {
        final result = service.preview(
          [
            FileItem(
              name: 'file.txt',
              path: r'C:\one\file.txt',
              isFolder: false,
            ),
            FileItem(
              name: 'file.txt',
              path: r'D:\two\file.txt',
              isFolder: false,
            ),
          ],
          const MultiRenameOptions(nameMask: 'new'),
          directory: r'C:\unused',
          pathContext: p.windows,
        );
        expect(result.isValid, isTrue);
        expect(result.entries.map((entry) => entry.targetPath), [
          r'C:\one\new.txt',
          r'D:\two\new.txt',
        ]);
      },
    );

    test('same-directory duplicate target names block the whole batch', () {
      final result = plan([
        _file('/a/one.txt'),
        _file('/a/two.txt'),
      ], const MultiRenameOptions(nameMask: 'same'));
      expect(result.isValid, isFalse);
      expect(result.entries.every((entry) => entry.errors.isNotEmpty), isTrue);
    });

    test('case collisions and overwriting another source are blocked', () {
      final result = plan([
        _file('/a/a.txt'),
        _file('/a/b.txt'),
      ], const MultiRenameOptions(nameMask: 'B'));
      expect(result.isValid, isFalse);
      expect(
        result.entries.first.errors.join(),
        contains('another selected item'),
      );
    });

    test('changing an ancestor folder in a mixed list is blocked', () {
      final result = plan([
        _file('/a/folder', folder: true),
        _file('/a/folder/file.txt'),
      ], const MultiRenameOptions(nameMask: '[N]_new'));
      expect(result.isValid, isFalse);
      expect(result.entries.every((entry) => entry.errors.isNotEmpty), isTrue);
    });

    test('unsafe and invalid names never become an executable plan', () {
      for (final name in [
        '',
        '.',
        '..',
        '../escape',
        r'..\escape',
        'CON',
        'name.',
        'name ',
        'a/b',
        'a\nb',
        'a\u0000b',
        'a' * 256,
      ]) {
        final result = plan([
          _file('/a/original'),
        ], MultiRenameOptions(nameMask: name, extensionMask: ''));
        expect(result.canExecute, isFalse, reason: name);
      }
    });

    test('an incoherent source name/path is rejected', () {
      final result = plan([
        FileItem(name: 'report.txt', path: '/a/other.txt', isFolder: false),
      ], const MultiRenameOptions(nameMask: 'new'));
      expect(result.isValid, isFalse);
    });

    test('unchanged plans perform no work', () async {
      final result = plan([_file('/a/original')]);
      expect(result.isValid, isTrue);
      expect(result.canExecute, isFalse);
      final outcome = await service.execute(
        result,
        exists: (_) async => throw StateError('must not check'),
        rename: (_, __) async => throw StateError('must not rename'),
      );
      expect(outcome.unchanged, 1);
      expect(outcome.renamed, 0);
    });
  });

  group('execution preflight and truthful outcomes', () {
    late MultiRenamePlan preview;
    late Set<String> paths;
    late List<String> renamed;

    setUp(() {
      preview = plan([
        _file('/a/first.txt'),
        _file('/b/second.txt'),
      ], const MultiRenameOptions(nameMask: '[N]_new'));
      paths = {'/a/first.txt', '/b/second.txt'};
      renamed = [];
    });

    Future<void> rename(FileItem file, String name) async {
      final target = p.posix.join(p.posix.dirname(file.path!), name);
      expect(paths.contains(target), isFalse);
      paths.remove(file.path);
      paths.add(target);
      renamed.add(file.path!);
    }

    test('checks every destination before touching the first source', () async {
      paths.add('/b/second_new.txt');
      await expectLater(
        service.execute(
          preview,
          exists: (path) async => paths.contains(path),
          rename: rename,
        ),
        throwsA(isA<MultiRenamePreflightException>()),
      );
      expect(renamed, isEmpty);
      expect(paths.contains('/a/first.txt'), isTrue);
    });

    test(
      'permission and listing errors are never treated as empty targets',
      () async {
        await expectLater(
          service.execute(
            preview,
            exists: (path) async {
              if (path == '/b/second_new.txt') {
                throw StateError('access denied');
              }
              return paths.contains(path);
            },
            rename: rename,
          ),
          throwsA(isA<MultiRenamePreflightException>()),
        );
        expect(renamed, isEmpty);
      },
    );

    test('a vanished original blocks all writes during preflight', () async {
      paths.remove('/b/second.txt');
      await expectLater(
        service.execute(
          preview,
          exists: (path) async => paths.contains(path),
          rename: rename,
        ),
        throwsA(isA<MultiRenamePreflightException>()),
      );
      expect(renamed, isEmpty);
    });

    test(
      'returns actual old/new full-path mapping after successful renames',
      () async {
        final result = await service.execute(
          preview,
          exists: (path) async => paths.contains(path),
          rename: rename,
        );
        expect(result.renamed, 2);
        expect(result.failed, 0);
        expect(result.changes.keys, ['/a/first.txt', '/b/second.txt']);
        expect(result.changes['/b/second.txt']!.path, '/b/second_new.txt');
        expect(paths, {'/a/first_new.txt', '/b/second_new.txt'});
      },
    );

    test('rechecks destinations that appear after preflight', () async {
      final result = await service.execute(
        preview,
        exists: (path) async => paths.contains(path),
        rename: (file, name) async {
          await rename(file, name);
          paths.add('/b/second_new.txt');
        },
      );
      expect(result.renamed, 1);
      expect(result.failed, 1);
      expect(renamed, ['/a/first.txt']);
      expect(paths.contains('/b/second.txt'), isTrue);
    });

    test(
      'failure is reported and unattempted items are not marked successful',
      () async {
        final result = await service.execute(
          preview,
          exists: (path) async => paths.contains(path),
          rename: (_, __) async => throw StateError('provider refused'),
        );
        expect(result.renamed, 0);
        expect(result.failed, 1);
        expect(result.notRun, 1);
        expect(result.outcomes.first.message, contains('provider refused'));
        expect(result.changes, isEmpty);
      },
    );

    test(
      'continue-on-error only counts successful individual operations',
      () async {
        final result = await service.execute(
          preview,
          exists: (path) async => paths.contains(path),
          continueOnError: true,
          rename: (file, name) async {
            if (file.path == '/a/first.txt') throw StateError('refused');
            await rename(file, name);
          },
        );
        expect(result.failed, 1);
        expect(result.renamed, 1);
        expect(result.notRun, 0);
        expect(result.changes.keys, ['/b/second.txt']);
      },
    );

    test(
      'cancellation after one operation preserves its success and stops',
      () async {
        var cancelled = false;
        final result = await service.execute(
          preview,
          exists: (path) async => paths.contains(path),
          isCancelled: () => cancelled,
          rename: (file, name) async {
            await rename(file, name);
            cancelled = true;
          },
        );
        expect(result.cancelled, isTrue);
        expect(result.renamed, 1);
        expect(result.notRun, 1);
        expect(paths.contains('/b/second.txt'), isTrue);
      },
    );

    test('cancellation during preflight produces no writes', () async {
      var cancelled = false;
      final result = await service.execute(
        preview,
        exists: (path) async {
          cancelled = true;
          return paths.contains(path);
        },
        isCancelled: () => cancelled,
        rename: rename,
      );
      expect(result.cancelled, isTrue);
      expect(result.renamed, 0);
      expect(renamed, isEmpty);
    });

    test('case-only existing aliases require an intermediate name', () async {
      final casePlan = plan([
        _file('/a/File.txt'),
      ], const MultiRenameOptions(nameCase: RenameCase.lower));
      await expectLater(
        service.execute(
          casePlan,
          exists: (path) async => path.toLowerCase() == '/a/file.txt',
          rename: rename,
        ),
        throwsA(
          isA<MultiRenamePreflightException>().having(
            (error) => error.toString(),
            'message',
            contains('intermediate'),
          ),
        ),
      );
      expect(renamed, isEmpty);
    });
  });

  group('presets', () {
    test('round-trips every user option', () {
      const options = MultiRenameOptions(
        nameMask: 'Photo_[C]',
        extensionMask: 'jpeg',
        find: '(A)',
        replace: r'$1B',
        useRegex: true,
        caseSensitive: false,
        firstMatchOnly: true,
        replaceScope: RenameReplaceScope.name,
        nameCase: RenameCase.title,
        extensionCase: RenameCase.lower,
        counterStart: 7,
        counterStep: 3,
        counterWidth: 4,
      );
      expect(
        MultiRenameOptions.fromJson(options.toJson()).toJson(),
        options.toJson(),
      );
    });

    test(
      'malformed stored fields fall back to defaults without type errors',
      () {
        final options = MultiRenameOptions.fromJson({
          'nameMask': 123,
          'useRegex': 'yes',
          'counterStart': 'bad',
          'nameCase': 'invalid',
        });
        expect(options.toJson(), const MultiRenameOptions().toJson());
      },
    );
  });
}
