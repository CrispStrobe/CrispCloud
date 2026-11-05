import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/multi_rename_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

FileItem file(
  String path, {
  bool folder = false,
  Map<String, dynamic>? metadata,
}) => FileItem(
  name: p.posix.basename(path),
  path: path,
  isFolder: folder,
  size: folder ? null : 24,
  updatedAt: DateTime.utc(2024, 2, 3, 4, 5, 6),
  metadata: metadata,
);

void main() {
  const service = MultiRenameService();
  final referenceTime = DateTime.utc(2026, 11, 5, 12, 13, 14);
  MultiRenamePlan preview(
    List<FileItem> files,
    MultiRenameOptions options, {
    Map<String, String> names = const {},
    Iterable<String> existing = const [],
    bool sensitive = false,
  }) => service.preview(
    files,
    options,
    directory: '/',
    targetNames: names,
    existingPaths: existing,
    allowDependencies: true,
    caseSensitivePaths: sensitive,
    referenceTime: referenceTime,
  );

  group('versioned mask dialects', () {
    test(
      'TC combined date fields, inline case and custom counters compose',
      () {
        final result = preview(
          [file('/photos/report.txt')],
          const MultiRenameOptions(
            dialect: RenameMaskDialect.totalCommander,
            nameMask: '[U][N][n]_[YMD]_[hms]_[C7+2:4]',
          ),
        );
        expect(
          result.entries.single.newName,
          'REPORT_20240203_040506_0007.txt',
        );
        expect(result.isValid, isTrue);
      },
    );

    test('DC ranges, padded dates, ancestor fields and escaped brackets', () {
      final complete = preview(
        [file('/audio/podcasts/abcdef.mp3')],
        const MultiRenameOptions(
          dialect: RenameMaskDialect.doubleCommander,
          nameMask: '[[][N2:4][]]_[N2,2]_[P-1]_[YYYY][MM][DD]_[hh][nn][ss]',
        ),
      );
      expect(
        complete.entries.single.newName,
        '[bcd]_bc_podcasts_20240203_040506.mp3',
      );
      expect(complete.isValid, isTrue);
    });

    test(
      'DC negative counters and backwards ranges retain their semantics',
      () {
        final result = preview(
          [file('/abcdef.txt'), file('/uvwxyz.txt')],
          const MultiRenameOptions(
            dialect: RenameMaskDialect.doubleCommander,
            counterStart: -1,
            nameMask: '[N-2:-3]_[N-2,2]_[C]',
          ),
        );
        expect(result.entries.map((entry) => entry.newName), [
          'de_de_-001.txt',
          'xy_xy_000.txt',
        ]);
      },
    );

    test(
      'metadata, captured date, variables and UTC offset use captured values',
      () {
        final result = preview(
          [
            file(
              '/photo.jpg',
              metadata: {
                'exif': {
                  'DateTimeOriginal': DateTime.utc(2024, 12, 31, 23, 30),
                },
                'artist': 'Avery',
              },
            ),
          ],
          const MultiRenameOptions(
            nameMask: '[T4+60m][YMD]_[meta:artist]_[V:Event]',
            variables: {'Event': 'Trip'},
            dateZone: RenameDateZone.utc,
          ),
        );
        expect(result.entries.single.newName, '20250101_Avery_Trip.jpg');
      },
    );

    test(
      'current time and generated identifiers remain fixed for a preview',
      () {
        const options = MultiRenameOptions(nameMask: '[T5][YMD]_[G]');
        final first = preview([file('/a.txt')], options).entries.single.newName;
        final second = preview([
          file('/a.txt'),
        ], options).entries.single.newName;
        expect(second, first);
        expect(first, startsWith('20261105_{'));
        expect(
          preview([file('/b.txt')], options).entries.single.newName,
          isNot(first),
        );
      },
    );

    test('missing metadata and variables are explicit preview errors', () {
      for (final mask in ['[meta:artist]', '[T2][Y]', '[V:Project]']) {
        final result = preview([
          file('/a.txt'),
        ], MultiRenameOptions(nameMask: mask));
        expect(result.canExecute, isFalse, reason: mask);
        expect(result.entries.single.errors, isNotEmpty);
      }
    });
  });

  group('editable pipelines', () {
    test('steps consume the preceding virtual name without any file I/O', () {
      final result = preview(
        [file('/a/IMG_09.JPG')],
        const MultiRenameOptions(
          find: 'IMG_',
          replace: 'Trip-',
          additionalSteps: [
            MultiRenameOptions(
              nameMask: '[N]_[C:2]',
              extensionCase: RenameCase.lower,
            ),
            MultiRenameOptions(
              find: '-',
              replace: ' ',
              nameCase: RenameCase.lower,
            ),
          ],
        ),
      );
      expect(result.entries.single.newName, 'trip 09_01.jpg');
      expect(result.entries.single.sourcePath, '/a/IMG_09.JPG');
    });

    test(
      'multiple literal pairs replace simultaneously and do not cascade',
      () {
        final result = preview(
          [file('/ab-aa.txt')],
          const MultiRenameOptions(
            find: 'a|b',
            replace: 'b|c',
            multipleLiteralPairs: true,
          ),
        );
        expect(result.entries.single.newName, 'bc-bb.txt');
        final invalid = preview(
          [file('/a.txt')],
          const MultiRenameOptions(
            find: 'a|b',
            replace: '1|2|3',
            multipleLiteralPairs: true,
          ),
        );
        expect(invalid.isValid, isFalse);
      },
    );

    test('per-row targets follow original full paths after order changes', () {
      final a = file('/a/same.txt');
      final b = file('/b/same.txt');
      final result = preview(
        [b, a],
        const MultiRenameOptions(nameMask: '[C]'),
        names: {'/a/same.txt': 'manual.txt'},
      );
      expect(result.entries.map((entry) => entry.newName), [
        '001.txt',
        'manual.txt',
      ]);
    });

    test('invalid later steps block the entire pipeline before execution', () {
      final result = preview(
        [file('/a.txt')],
        const MultiRenameOptions(
          additionalSteps: [MultiRenameOptions(useRegex: true, find: '(')],
        ),
      );
      expect(result.isValid, isFalse);
      expect(result.errors.single, contains('Step 2'));
    });

    test('versioned presets round-trip every step, dialect and variable', () {
      const options = MultiRenameOptions(
        dialect: RenameMaskDialect.totalCommander,
        dateSource: RenameDateSource.current,
        dateZone: RenameDateZone.utc,
        dateOffsetMinutes: -60,
        variables: {'X': 'Y'},
        multipleLiteralPairs: true,
        collisionPolicy: RenameCollisionPolicy.number,
        additionalSteps: [MultiRenameOptions(nameMask: '[N]_final')],
      );
      expect(
        MultiRenameOptions.fromJson(options.toJson()).toJson(),
        options.toJson(),
      );
    });
  });

  group('reviewable final paths', () {
    test(
      'numbering accounts for duplicates, existing targets and unchanged rows',
      () {
        final result = preview(
          [file('/first.txt'), file('/second.txt'), file('/keep.txt')],
          const MultiRenameOptions(
            nameMask: 'same',
            collisionPolicy: RenameCollisionPolicy.number,
          ),
          names: {'/keep.txt': 'keep.txt'},
          existing: ['/same.txt', '/same (1).txt', '/keep.txt'],
        );
        expect(result.entries.map((entry) => entry.newName), [
          'same (2).txt',
          'same (3).txt',
          'keep.txt',
        ]);
        expect(result.isValid, isTrue);
      },
    );

    test('case-sensitive storage can retain case-distinct source names', () {
      final result = preview(
        [file('/a.txt'), file('/A.txt')],
        const MultiRenameOptions(nameMask: '[N]_new'),
        sensitive: true,
      );
      expect(result.isValid, isTrue);
      expect(result.entries.map((entry) => entry.targetPath), [
        '/a_new.txt',
        '/A_new.txt',
      ]);
    });

    test(
      'swaps and occupied chains become staged plans, never direct overwrites',
      () {
        final swap = preview(
          [file('/a.txt'), file('/b.txt')],
          const MultiRenameOptions(),
          names: {'/a.txt': 'b.txt', '/b.txt': 'a.txt'},
        );
        expect(swap.isValid, isTrue);
        expect(swap.requiresStaging, isTrue);
        final chain = preview(
          [file('/a.txt'), file('/b.txt')],
          const MultiRenameOptions(),
          names: {'/a.txt': 'b.txt', '/b.txt': 'c.txt'},
        );
        expect(chain.isValid, isTrue);
        expect(chain.requiresStaging, isTrue);
      },
    );

    test('parent and child final paths include every renamed ancestor', () {
      final result = preview([
        file('/a', folder: true),
        file('/a/b', folder: true),
        file('/a/b/c.txt'),
      ], const MultiRenameOptions(nameMask: '[N]_new'));
      expect(result.entries.map((entry) => entry.targetPath), [
        '/a_new',
        '/a_new/b_new',
        '/a_new/b_new/c_new.txt',
      ]);
      expect(result.isValid, isTrue);
      expect(result.requiresStaging, isTrue);
    });

    test(
      'a child with an unchanged basename still follows its renamed parent',
      () {
        final result = preview(
          [file('/a', folder: true), file('/a/c.txt')],
          const MultiRenameOptions(),
          names: {'/a': 'b'},
        );
        expect(result.entries.last.targetPath, '/b/c.txt');
        expect(result.entries.last.directChange, isFalse);
        expect(result.entries.last.changed, isTrue);
      },
    );
  });
}
