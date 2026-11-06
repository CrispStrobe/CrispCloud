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
    DateTime? optionsChangedAt,
  }) => service.preview(
    files,
    options,
    directory: '/',
    targetNames: names,
    existingPaths: existing,
    allowDependencies: true,
    caseSensitivePaths: sensitive,
    referenceTime: referenceTime,
    optionsChangedAt: optionsChangedAt,
  );

  group('versioned mask dialects', () {
    test('original and UTC time zones preserve explicit captured offsets', () {
      final image = file(
        '/photo.jpg',
        metadata: {'dateTaken': '2024-12-31T23:30:00-02:00'},
      );
      const original = MultiRenameOptions(
        nameMask: '[YMD]_[hms]',
        dateSource: RenameDateSource.captured,
      );
      expect(
        preview([image], original).entries.single.newName,
        '20241231_233000.jpg',
      );
      expect(
        preview(
          [image],
          original.copyWith(dateZone: RenameDateZone.utc),
        ).entries.single.newName,
        '20250101_013000.jpg',
      );
    });

    test('TC title-case directives retain word state across literal and token fragments', () {
      final result = preview(
        [file('/HELLO.txt')],
        const MultiRenameOptions(
          dialect: RenameMaskDialect.totalCommander,
          nameMask: '[F]my [N] WORLD[n]',
        ),
      );
      expect(result.entries.single.newName, 'My Hello World.txt');
    });
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

    test('TC date switches retain their documented time sources', () {
      final source = file('/photo.jpg', metadata: {
        'createdAt': DateTime.utc(2001, 1, 1),
        'accessedAt': DateTime.utc(2002, 1, 1),
        'dateTaken': DateTime.utc(2020, 6, 7, 8, 9, 10),
      });
      final result = preview(
        [source],
        const MultiRenameOptions(
          dialect: RenameMaskDialect.totalCommander,
          nameMask: '[T1][YMD]_[T2][YMD]_[T3][YMD]_[T4][YMD]',
        ),
        optionsChangedAt: DateTime.utc(2026, 11, 6),
      );
      expect(result.isValid, isTrue);
      expect(
        result.entries.single.newName,
        '20240203_20261105_20261106_20200607.jpg',
      );

      final defaultTime = preview(
        [source],
        const MultiRenameOptions(
          dialect: RenameMaskDialect.totalCommander,
          nameMask: '[T2][hms]_[T3][hms]',
        ),
      );
      expect(defaultTime.entries.single.newName, '121314_121314.jpg');
    });

    test('CrispCloud date switches retain their previous meanings', () {
      final result = preview(
        [
          file('/photo.jpg', metadata: {
            'createdAt': DateTime.utc(2001, 1, 1),
            'accessedAt': DateTime.utc(2002, 2, 2),
            'dateTaken': DateTime.utc(2020, 6, 7),
          }),
        ],
        const MultiRenameOptions(
          nameMask: '[T2][YMD]_[T3][YMD]_[T4][YMD]_[T5][YMD]',
        ),
        optionsChangedAt: DateTime.utc(2026, 11, 6),
      );
      expect(result.isValid, isTrue);
      expect(
        result.entries.single.newName,
        '20010101_20020202_20200607_20261105.jpg',
      );
    });

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

    test('oversized offsets become preview errors without integer overflow', () {
      for (final options in [
        const MultiRenameOptions(
          nameMask: '[Y]',
          dateOffsetMinutes: 150000000000,
        ),
        const MultiRenameOptions(nameMask: '[T1+150000000000m][Y]'),
        const MultiRenameOptions(nameMask: '[T1-150000000000m][Y]'),
        const MultiRenameOptions(
          nameMask: '[T1+999999999999999999999999d][Y]',
        ),
        const MultiRenameOptions(
          nameMask: '[T1+100000000000m][Y]',
          dateOffsetMinutes: 100000000000,
        ),
      ]) {
        final result = preview([file('/a.txt')], options);
        expect(result.canExecute, isFalse);
        expect(result.entries.single.errors.single, contains('date offset'));
      }
    });

    test('offsets cannot wrap a date past either supported epoch limit', () {
      for (final sign in [-1, 1]) {
        final source = file('/a.txt').copyWith(
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            sign * 8640000000000000,
            isUtc: true,
          ),
        );
        final result = preview(
          [source],
          MultiRenameOptions(
            nameMask: '[Y]',
            dateOffsetMinutes: sign * 100000000000,
          ),
        );
        expect(result.canExecute, isFalse);
        expect(
          result.entries.single.errors.single,
          contains('outside the supported date range'),
        );
      }
    });

    test('invalid numeric metadata dates remain explicit preview errors', () {
      for (final value in <num>[
        9000000000000000,
        -9000000000000000,
        double.infinity,
        double.negativeInfinity,
        double.nan,
      ]) {
        final result = preview(
          [file('/a.txt', metadata: {'createdAt': value})],
          const MultiRenameOptions(
            nameMask: '[Y]',
            dateSource: RenameDateSource.created,
          ),
        );
        expect(result.canExecute, isFalse);
        expect(
          result.entries.single.errors.single,
          contains('outside the supported date range'),
        );
      }
      final valid = preview(
        [
          file('/a.txt', metadata: {
            'createdAt': DateTime.utc(2024, 1, 2).millisecondsSinceEpoch,
          }),
        ],
        const MultiRenameOptions(
          nameMask: '[YMD]',
          dateSource: RenameDateSource.created,
          dateZone: RenameDateZone.utc,
        ),
      );
      expect(valid.isValid, isTrue);
      expect(valid.entries.single.newName, '20240102.txt');
    });
  });

  group('editable pipelines', () {
    test('manual row targets can replace unavailable metadata transforms', () {
      final result = preview(
        [file('/a.txt')],
        const MultiRenameOptions(nameMask: '[meta:artist]'),
        names: {'/a.txt': 'manual.txt'},
      );
      expect(result.isValid, isTrue);
      expect(result.entries.single.newName, 'manual.txt');
    });
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

    test('literal pairs retain Unicode regexp case-folding semantics', () {
      final result = preview(
        [file('/ſ_ς_S_Σ.txt')],
        const MultiRenameOptions(
          find: 's|σ',
          replace: 'one|two',
          multipleLiteralPairs: true,
          caseSensitive: false,
        ),
      );
      expect(result.isValid, isTrue);
      expect(result.entries.single.newName, 'one_two_one_two.txt');

      final firstOnly = preview(
        [file('/ſ_ς_S_Σ.txt')],
        const MultiRenameOptions(
          find: 's|σ',
          replace: 'one|two',
          multipleLiteralPairs: true,
          caseSensitive: false,
          firstMatchOnly: true,
        ),
      );
      expect(firstOnly.entries.single.newName, 'one_ς_S_Σ.txt');
    });

    test('literal pairs still escape regexp syntax and prefer the first pair', () {
      final escaped = preview(
        [file('/a.b_(x).txt')],
        const MultiRenameOptions(
          find: 'a.b|(x)',
          replace: 'point|parens',
          multipleLiteralPairs: true,
        ),
      );
      expect(escaped.entries.single.newName, 'point_parens.txt');
      final ordered = preview(
        [file('/ſ.txt')],
        const MultiRenameOptions(
          find: 's|ſ',
          replace: 'first|second',
          multipleLiteralPairs: true,
          caseSensitive: false,
        ),
      );
      expect(ordered.entries.single.newName, 'first.txt');
    });

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

    test('manual targets rescue only rows with unavailable metadata', () {
      final result = preview(
        [
          file('/a.jpg', metadata: {'artist': 'Avery'}),
          file('/b.jpg'),
        ],
        const MultiRenameOptions(nameMask: '[meta:artist]_[N]'),
        names: {'/b.jpg': 'manual.jpg'},
      );
      expect(result.isValid, isTrue);
      expect(result.entries.map((entry) => entry.newName), [
        'Avery_a.jpg',
        'manual.jpg',
      ]);
      final invalidName = preview(
        [file('/a.jpg')],
        const MultiRenameOptions(nameMask: '[meta:artist]'),
        names: {'/a.jpg': '../escape.jpg'},
      );
      expect(invalidName.isValid, isFalse);
      expect(invalidName.entries.single.errors, isNotEmpty);
    });

    test('manual targets cannot hide invalid masks or global syntax errors', () {
      for (final options in [
        const MultiRenameOptions(nameMask: '[meta:missing][UNKNOWN]'),
        const MultiRenameOptions(
          nameMask: '[meta:missing]',
          extensionMask: '[UNKNOWN]',
        ),
        const MultiRenameOptions(
          nameMask: '[meta:missing]',
          additionalSteps: [MultiRenameOptions(nameMask: '[UNKNOWN]')],
        ),
        const MultiRenameOptions(nameMask: '[meta:missing]', useRegex: true, find: '('),
        const MultiRenameOptions(nameMask: '[V:Project]'),
      ]) {
        final result = preview(
          [file('/a.jpg')],
          options,
          names: {'/a.jpg': 'manual.jpg'},
        );
        expect(result.canExecute, isFalse, reason: options.toJson().toString());
      }
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
    test('case-only changes use temporary names even when the host is case sensitive', () {
      final result = preview(
        [file('/a.txt')],
        const MultiRenameOptions(nameCase: RenameCase.upper),
        sensitive: true,
      );
      expect(result.requiresStaging, isTrue);
    });
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
