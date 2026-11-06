import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/file_search_query.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/file_selection_pattern.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const service = FileOperationService();
  late _MemoryBackend source;
  late _MemoryBackend target;

  setUp(() {
    source = _MemoryBackend('source');
    target = _MemoryBackend('target')..directory('/target');
  });

  Future<FileOperationPlan> prepare(
    List<String> paths, {
    FileOperationOptions options = const FileOperationOptions(),
    String destination = '/target',
    _MemoryBackend? targetBackend,
  }) => service.prepare(
    files: paths.map(source.item).toList(),
    source: source,
    destination: targetBackend ?? target,
    targetDirectory: destination,
    options: options,
  );

  Future<void> execute(
    FileOperationPlan plan, {
    FileOperationControl? control,
    FileConflictResolver? resolveConflict,
  }) => service.execute(
    plan,
    control: control ?? FileOperationControl(),
    resolveConflict: resolveConflict,
  );

  test(
    'destination directory whitespace remains part of its exact path',
    () async {
      source.file('/source/file.txt', 'copied contents');
      target.directory('/folder ');
      target.file('/folder/file.txt', 'other destination');
      final plan = await prepare(['/source/file.txt'], destination: '/folder ');
      expect(plan.targetDirectory, '/folder ');
      expect(plan.errors, isEmpty);
    expect(plan.entries.single.destination, '/folder /file.txt');
      await execute(plan);
      expect(target.text('/folder /file.txt'), 'copied contents');
      expect(target.text('/folder/file.txt'), 'other destination');
    },
  );

  group('bounded preview', () {
    test('entry budget disables a partial plan before any writes', () async {
      for (var i = 0; i < 100; i++) {
        source.file('/source/tree/$i.txt', 'payload');
      }
      final plan = await service.prepare(
        files: [source.item('/source/tree')],
        source: source,
        destination: target,
        targetDirectory: '/target',
        maxEntries: 10,
      );
      expect(plan.canExecute, isFalse);
      expect(plan.entries.length, lessThanOrEqualTo(10));
      expect(plan.errors.join(), contains('preview budget'));
      await expectLater(execute(plan), throwsStateError);
      expect(target.writeAttempts, isEmpty);
    });

    test('depth budget stops traversal and never follows beyond it', () async {
      source.file('/source/a/b/c/d/file.txt', 'contents');
      final plan = await service.prepare(
        files: [source.item('/source/a')],
        source: source,
        destination: target,
        targetDirectory: '/target',
        maxDepth: 1,
      );
      expect(plan.canExecute, isFalse);
      expect(plan.errors.join(), contains('1 folder levels'));
      expect(source.listedPaths, isNot(contains('/source/a/b/c')));
    });

    test(
      'planning progress can cancel a large scan before it writes',
      () async {
        for (var i = 0; i < 200; i++) {
          source.file('/source/tree/$i.txt', 'data');
        }
        final control = FileOperationControl();
        final progress = <int>[];
        await expectLater(
          service.prepare(
            files: [source.item('/source/tree')],
            source: source,
            destination: target,
            targetDirectory: '/target',
            control: control,
            onPlanningProgress: (count, path) {
              progress.add(count);
              if (count == 3) control.cancel();
            },
          ),
          throwsA(isA<FileOperationCancelled>()),
        );
        expect(progress, [1, 2, 3]);
        expect(target.writeAttempts, isEmpty);
      },
    );

    test(
      'fresh child listings avoid a second metadata scan per source file',
      () async {
        for (var i = 0; i < 1000; i++) {
          source.file('/source/tree/$i.txt', 'data');
        }
        final plan = await prepare(['/source/tree']);
        expect(plan.entries, hasLength(1001));
        expect(source.statCalls, 1);
        expect(source.listedPaths, ['/source/tree']);
      },
    );

    test(
      'cloud-style selected files share each fresh preview directory',
      () async {
        source.listingBackedStat = target.listingBackedStat = true;
        for (var i = 0; i < 300; i++) {
          source.file('/source/$i.txt', 'data');
        }
        final plan = await prepare([
          for (var i = 0; i < 300; i++) '/source/$i.txt',
        ]);
        expect(plan.canExecute, isTrue);
        expect(source.statCalls, 1);
        expect(target.statCalls, 1);
        expect(source.listedPaths, ['/', '/source']);
        expect(target.listedPaths, ['/', '/target']);
        target.file('/target/0.txt', 'concurrent writer');
        await execute(plan);
        expect(plan.entries.first.outcome, FileOperationOutcome.needsDecision);
        expect(target.text('/target/0.txt'), 'concurrent writer');
        expect(target.statCalls, greaterThan(1));
      },
    );

    test('oversized directory metadata is rejected before making an executable plan', () async {
      source.file('/source/one.txt', 'data');
      target.listingBackedStat = true;
      for (var i = 0; i < 20; i++) {
        target.file('/target/$i.txt', 'existing');
      }
      final plan = await service.prepare(
        files: [source.item('/source/one.txt')],
        source: source,
        destination: target,
        targetDirectory: '/target',
        maxEntries: 10,
      );
      expect(plan.canExecute, isFalse);
      expect(plan.errors.join(), contains('Directory metadata exceeds'));
      expect(target.writeAttempts, isEmpty);
    });
  });

  group('copy method contracts', () {
    for (final method in FileCopyMethod.values) {
      test('${method.name} honors a filesystem that refuses cloning', () async {
        final native = _DecliningCloneBackend()
          ..file('/source/a.txt', 'copy contents')
          ..directory('/target');
        final plan = await service.prepare(
          files: [native.item('/source/a.txt')],
          source: native,
          destination: native,
          targetDirectory: '/target',
          options: FileOperationOptions(copyMethod: method),
        );
        expect(plan.canExecute, isTrue);
        await execute(plan);
        if (method == FileCopyMethod.copyOnWrite) {
          expect(plan.entries.single.outcome, FileOperationOutcome.failed);
          expect(native.contains('/target/a.txt'), isFalse);
          expect(native.writeAttempts, isEmpty);
        } else {
          expect(plan.entries.single.outcome, FileOperationOutcome.copied);
          expect(native.text('/target/a.txt'), 'copy contents');
        }
        expect(native.cloneAttempts, method == FileCopyMethod.stream ? 0 : 1);
        expect(native.text('/source/a.txt'), 'copy contents');
      });
    }

    test(
      'incompatible allocation and required clone settings fail in preview',
      () async {
        final native = _DecliningCloneBackend()
          ..file('/source/a.txt', 'contents')
          ..directory('/target');
        final plan = await service.prepare(
          files: [native.item('/source/a.txt')],
          source: native,
          destination: native,
          targetDirectory: '/target',
          options: const FileOperationOptions(
            copyMethod: FileCopyMethod.copyOnWrite,
            preallocate: true,
          ),
        );
        expect(plan.canExecute, isFalse);
        expect(
          plan.errors.join(),
          contains('Full allocation cannot be combined'),
        );
        expect(native.writeAttempts, isEmpty);
      },
    );
  });

  group('selected sources on the destination account', () {
    for (final path in [
      '/target/report.txt',
      '/target',
      '/target/report.txt/child',
    ]) {
      test('planning rejects overlap with protected root $path', () async {
        source.file('/source/report.txt', 'new contents');
        final plan = await service.prepare(
          files: [source.item('/source/report.txt')],
          source: source,
          destination: target,
          targetDirectory: '/target',
          protectedDestinationPaths: [path],
          options: const FileOperationOptions(
            fileConflict: FileConflictPolicy.replace,
          ),
        );
        expect(plan.canExecute, isFalse);
        expect(plan.errors.join(), contains('another selected source'));
        expect(target.writeAttempts, isEmpty);
      });
    }

    for (final decision in [
      FileConflictDecision.renameSource,
      FileConflictDecision.renameDestination,
    ]) {
      test(
        'dynamic ${decision.name} cannot touch a protected selected path',
        () async {
          source.file('/source/report.txt', 'new contents');
          target.file('/target/report.txt', 'old contents');
          final plan = await service.prepare(
            files: [source.item('/source/report.txt')],
            source: source,
            destination: target,
            targetDirectory: '/target',
            protectedDestinationPaths: ['/target/selected.txt'],
          );
          expect(plan.canExecute, isTrue);
          await service.execute(
            plan,
            control: FileOperationControl(),
            resolveDetailedConflict: (entry, existing) async =>
                FileConflictResolution(decision, name: 'selected.txt'),
          );
          expect(plan.entries.single.failed, isTrue);
          expect(
            plan.entries.single.message,
            contains('another selected source'),
          );
          expect(target.writeAttempts, isEmpty);
          expect(target.text('/target/report.txt'), 'old contents');
          expect(source.text('/source/report.txt'), 'new contents');
        },
      );
    }

    test('keep-both allocation rechecks protected selected paths', () async {
      source.file('/source/report.txt', 'new contents');
      final plan = await service.prepare(
        files: [source.item('/source/report.txt')],
        source: source,
        destination: target,
        targetDirectory: '/target',
        protectedDestinationPaths: ['/target/report (1).txt'],
        options: const FileOperationOptions(
          fileConflict: FileConflictPolicy.keepBoth,
        ),
      );
      target.file('/target/report.txt', 'appeared after preview');
      await execute(plan);
      expect(plan.entries.single.failed, isTrue);
      expect(plan.entries.single.message, contains('another selected source'));
      expect(target.writeAttempts, isEmpty);
      expect(target.text('/target/report.txt'), 'appeared after preview');
    });

    test('staged writes cannot use another selected source as scratch space', () async {
      source.file('/source/report.txt', 'new contents');
      final guarded = _StagedPathBackend('/target/selected.txt')
        ..directory('/target')
        ..file('/target/selected.txt', 'protected contents');
      final plan = await service.prepare(
        files: [source.item('/source/report.txt')],
        source: source,
        destination: guarded,
        targetDirectory: '/target',
        protectedDestinationPaths: ['/target/selected.txt'],
      );
      expect(plan.canExecute, isTrue);
      await execute(plan);
      expect(plan.entries.single.failed, isTrue);
      expect(plan.entries.single.message, contains('another selected source'));
      expect(guarded.writeAttempts, isEmpty);
      expect(guarded.text('/target/selected.txt'), 'protected contents');
      expect(guarded.contains('/target/report.txt'), isFalse);
      expect(source.text('/source/report.txt'), 'new contents');
    });
  });

  group('shared search criteria', () {
    test(
      'extension, name, size, date, hidden and folder criteria all apply',
      () async {
        final date = DateTime.utc(2026, 2, 1);
        source.file('/tree/keep/report.txt', '12345', modified: date);
        source.file('/tree/keep/image.jpg', '12345', modified: date);
        source.file('/tree/keep/small.txt', '1', modified: date);
        source.file(
          '/tree/keep/old.txt',
          '12345',
          modified: DateTime.utc(2020),
        );
        source.file('/tree/.hidden/secret.txt', '12345', modified: date);
        source.file('/tree/cache/cached.txt', '12345', modified: date);
        source.directory('/tree/empty');
        final prepared = await prepare(
          ['/tree'],
          options: FileOperationOptions(
            searchCriteria: FileSearchQuery(
              namePattern: '*.txt',
              includeFolders: false,
              includeHidden: false,
              extensions: const ['txt'],
              minSize: 3,
              modifiedAfter: DateTime.utc(2026),
              excludeDirectories: 'cache',
            ),
          ),
        );
        expect(prepared.canExecute, isTrue);
        expect(
          prepared.entries
              .where((entry) => entry.outcome == FileOperationOutcome.pending)
              .map((entry) => entry.source.path),
          ['/tree/keep/report.txt'],
        );
        await execute(prepared);
        expect(target.text('/target/tree/keep/report.txt'), '12345');
        expect(target.contains('/target/tree/empty'), isFalse);
        expect(target.contains('/target/tree/cache'), isFalse);
        expect(target.contains('/target/tree/.hidden'), isFalse);
      },
    );

    test('folders-only criteria retain source directories containing excluded files', () async {
      source.file('/tree/keep.txt', 'retained');
      source.directory('/tree/empty');
      final prepared = await prepare(
        ['/tree'],
        options: const FileOperationOptions(
          kind: FileOperationKind.move,
          searchCriteria: FileSearchQuery(includeFiles: false),
        ),
      );
      await execute(prepared);
      expect(target.contains('/target/tree/empty'), isTrue);
      expect(target.contains('/target/tree/keep.txt'), isFalse);
      expect(source.text('/tree/keep.txt'), 'retained');
      expect(source.contains('/tree'), isTrue);
      expect(source.contains('/tree/empty'), isFalse);
    });

    test(
      'shared regular expressions can match complete source paths',
      () async {
        source.file('/tree/one/a.txt', 'selected');
        source.file('/tree/two/a.txt', 'excluded');
        final prepared = await prepare(
          ['/tree'],
          options: const FileOperationOptions(
            searchCriteria: FileSearchQuery(
              namePattern: r'^/tree/one/.*\.txt$',
              nameMode: FilePatternMode.regex,
              matchFullPath: true,
              includeFolders: false,
            ),
          ),
        );
        await execute(prepared);
        expect(target.text('/target/tree/one/a.txt'), 'selected');
        expect(target.contains('/target/tree/two'), isFalse);
      },
    );

    for (final criteria in [
      const FileSearchQuery(contentPattern: 'secret'),
      const FileSearchQuery(searchArchives: true),
    ]) {
      test('content/archive queries require Search before transfer', () async {
        source.file('/a', 'data');
        await expectLater(
          prepare([
            '/a',
          ], options: FileOperationOptions(searchCriteria: criteria)),
          throwsFormatException,
        );
        expect(target.writeAttempts, isEmpty);
      });
    }
  });

  group('advanced transfer options', () {
    test(
      'an exact file name composes with preserved relative parent paths',
      () async {
        source.file('/base/sub/old.txt', 'payload');
        final plan = await prepare(
          ['/base/sub/old.txt'],
          options: const FileOperationOptions(
            destinationName: 'renamed.txt',
            preserveRelativePaths: true,
            relativeBase: '/base',
          ),
        );
        expect(plan.errors, isEmpty);
        expect(plan.entries.single.destination, '/target/sub/renamed.txt');
        await execute(plan);
        expect(target.text('/target/sub/renamed.txt'), 'payload');
        expect(target.contains('/target/sub/old.txt'), isFalse);
      },
    );

    test(
      'an exact folder name preserves relative parents and descendant names',
      () async {
        source.file('/base/sub/tree/nested/a.txt', 'payload');
        final plan = await prepare(
          ['/base/sub/tree'],
          options: const FileOperationOptions(
            destinationName: 'renamed',
            preserveRelativePaths: true,
            relativeBase: '/base',
          ),
        );
        expect(plan.errors, isEmpty);
        await execute(plan);
        expect(target.text('/target/sub/renamed/nested/a.txt'), 'payload');
        expect(target.contains('/target/sub/tree'), isFalse);
      },
    );

    for (final kind in FileOperationKind.values) {
      test(
        '${kind.name} rejects masks that overwrite another selected source',
        () async {
          source.file('/source/a.txt', 'first source');
          source.file('/source/a.txt.bak', 'second source');
          final plan = await prepare(
            ['/source/a.txt', '/source/a.txt.bak'],
            targetBackend: source,
            destination: '/source',
            options: FileOperationOptions(
              kind: kind,
              destinationMask: '*.*.bak',
              fileConflict: FileConflictPolicy.replace,
            ),
          );
          expect(plan.canExecute, isFalse);
          expect(plan.errors.join(), contains('overlaps a selected source'));
          await expectLater(execute(plan), throwsStateError);
          expect(source.writeAttempts, isEmpty);
          expect(source.text('/source/a.txt'), 'first source');
          expect(source.text('/source/a.txt.bak'), 'second source');
        },
      );
    }

    test(
      'a filtered selected source is protected from destination masks',
      () async {
        source.file('/source/a.txt', 'copy');
        source.file('/source/a.txt.bak', 'retain');
        final plan = await prepare(
          ['/source/a.txt', '/source/a.txt.bak'],
          targetBackend: source,
          destination: '/source',
          options: FileOperationOptions(
            destinationMask: '*.*.bak',
            fileConflict: FileConflictPolicy.replace,
            pattern: FileSelectionPattern('*.txt'),
          ),
        );
        expect(plan.canExecute, isFalse);
        expect(plan.errors.join(), contains('overlaps a selected source'));
        expect(source.writeAttempts, isEmpty);
        expect(source.text('/source/a.txt.bak'), 'retain');
      },
    );

    test(
      'destination masks are planned recursively and collisions are rejected',
      () async {
        source.file('/tree/alpha.txt', 'one');
        source.file('/tree/deep/beta.jpg', 'two');
        final plan = await prepare(
          ['/tree'],
          options: const FileOperationOptions(
            destinationMask: '[N]_[C:000].[E]',
          ),
        );
        expect(plan.errors, isEmpty);
        expect(
          plan.entries
              .where((entry) => !entry.source.isFolder)
              .map((entry) => entry.destination),
          ['/target/tree/alpha_001.txt', '/target/tree/deep/beta_002.jpg'],
        );
        await execute(plan);
        expect(target.text('/target/tree/alpha_001.txt'), 'one');
        await expectLater(
          prepare([
            '/tree',
          ], options: const FileOperationOptions(destinationName: '../escape')),
          throwsFormatException,
        );
      },
    );

    test(
      'filters prune directories and exclude directories empty after filtering',
      () async {
        source.file('/tree/keep/a.txt', '12345');
        source.file('/tree/small/b.txt', '1');
        source.file('/tree/cache/c.txt', '123456');
        final plan = await prepare(
          ['/tree'],
          options: FileOperationOptions(
            minimumSize: 3,
            maximumSize: 5,
            excludedDirectories: FileSelectionPattern('cache'),
            excludeEmptyDirectories: true,
          ),
        );
        await execute(plan);
        expect(target.text('/target/tree/keep/a.txt'), '12345');
        expect(target.nodes.containsKey('/target/tree/small'), isFalse);
        expect(target.nodes.containsKey('/target/tree/cache'), isFalse);
        expect(
          plan.entries.any((entry) => entry.source.name == 'c.txt'),
          isFalse,
        );
      },
    );

    test('a verified resume validates the entire old prefix and preserves source on mismatch', () async {
      source.file('/source/a.txt', 'abcdefgh');
      target.file('/target/a.txt', 'abcd');
      final plan = await prepare(
        ['/source/a.txt'],
        options: const FileOperationOptions(
          fileConflict: FileConflictPolicy.resumeVerified,
        ),
      );
      await execute(plan);
      expect(target.text('/target/a.txt'), 'abcdefgh');
      expect(plan.entries.single.outcome, FileOperationOutcome.copied);
      target.file('/target/a.txt', 'wrong');
      final mismatch = await prepare(
        ['/source/a.txt'],
        options: const FileOperationOptions(
          kind: FileOperationKind.move,
          fileConflict: FileConflictPolicy.resumeVerified,
        ),
      );
      await execute(mismatch);
      expect(mismatch.entries.single.failed, isTrue);
      expect(target.text('/target/a.txt'), 'wrong');
      expect(source.text('/source/a.txt'), 'abcdefgh');
    });

    test('append stages complete combined content before replacing', () async {
      source.file('/source/a.txt', 'new');
      target.file('/target/a.txt', 'old');
      final plan = await prepare(
        ['/source/a.txt'],
        options: const FileOperationOptions(
          fileConflict: FileConflictPolicy.append,
        ),
      );
      await execute(plan);
      expect(target.text('/target/a.txt'), 'oldnew');
      expect(plan.entries.single.outcome, FileOperationOutcome.copied);
    });

    test('apply-to-all asks once and manual incoming names are confined to the directory', () async {
      source.file('/source/a.txt', 'new a');
      source.file('/source/b.txt', 'new b');
      target.file('/target/a.txt', 'old a');
      target.file('/target/b.txt', 'old b');
      final plan = await prepare(['/source/a.txt', '/source/b.txt']);
      var asked = 0;
      await service.execute(
        plan,
        control: FileOperationControl(),
        resolveDetailedConflict: (entry, existing) async {
          asked++;
          return const FileConflictResolution(
            FileConflictDecision.skip,
            applyToAll: true,
          );
        },
      );
      expect(asked, 1);
      expect(
        plan.entries.every(
          (entry) => entry.outcome == FileOperationOutcome.skipped,
        ),
        isTrue,
      );
      final renamed = await prepare(['/source/a.txt']);
      await service.execute(
        renamed,
        control: FileOperationControl(),
        resolveDetailedConflict: (entry, existing) async =>
            const FileConflictResolution(
              FileConflictDecision.renameSource,
              name: 'renamed.txt',
            ),
      );
      expect(target.text('/target/renamed.txt'), 'new a');
      expect(target.text('/target/a.txt'), 'old a');
    });

    test('background ask enters needs-decision without silently skipping remaining work', () async {
      source.file('/source/a.txt', 'new a');
      source.file('/source/b.txt', 'new b');
      target.file('/target/a.txt', 'old a');
      final plan = await prepare(['/source/a.txt', '/source/b.txt']);
      await execute(plan);
      expect(plan.entries.first.outcome, FileOperationOutcome.needsDecision);
      expect(plan.entries.last.outcome, FileOperationOutcome.pending);
      expect(target.text('/target/a.txt'), 'old a');
      expect(target.nodes.containsKey('/target/b.txt'), isFalse);
    });
  });

  group('selection and destination planning', () {
    test('custom keep-both template reserves every selected duplicate', () async {
      source.file('/first/a.txt', 'first');
      source.file('/second/a.txt', 'second');
      target.file('/target/a.txt', 'old');
      final plan = await prepare(
        ['/first/a.txt', '/second/a.txt'],
        options: const FileOperationOptions(
          fileConflict: FileConflictPolicy.keepBoth,
          duplicateNameTemplate: '{name}_copy-{counter:000}{ext}',
        ),
      );
      expect(plan.entries.map((entry) => entry.destination), [
        '/target/a_copy-001.txt',
        '/target/a_copy-002.txt',
      ]);
      // An independently created target after preview must use the original
      // base, and must not take the name reserved for the second selected file.
      target.file('/target/a_copy-001.txt', 'arrived after preview');
      await execute(plan);
      expect(target.text('/target/a.txt'), 'old');
      expect(target.text('/target/a_copy-001.txt'), 'arrived after preview');
      expect(target.text('/target/a_copy-002.txt'), 'second');
      expect(target.text('/target/a_copy-003.txt'), 'first');
      expect(plan.entries.every((entry) => entry.completed), isTrue);
      expect(target.contains('/target/a_copy-001_copy-001.txt'), isFalse);
    });

    test('custom same-directory names respect case-insensitive collisions', () async {
      source = _CaseInsensitiveMemoryBackend('source');
      source.file('/tree/a.txt', 'source');
      source.file('/tree/A_COPY-001.TXT', 'retain');
      final plan = await prepare(
        ['/tree/a.txt'],
        targetBackend: source,
        destination: '/tree',
        options: const FileOperationOptions(
          fileConflict: FileConflictPolicy.keepBoth,
          duplicateNameTemplate: '{name}_copy-{counter:000}{ext}',
        ),
      );
      expect(plan.entries.single.destination, '/tree/a_copy-002.txt');
      await execute(plan);
      expect(source.text('/tree/A_COPY-001.TXT'), 'retain');
      expect(source.text('/tree/a_copy-002.txt'), 'source');
    });

    test('invalid template cannot preview or execute a forged plan', () async {
      source.file('/a', 'retain');
      const invalid = FileOperationOptions(duplicateNameTemplate: '../{counter}');
      await expectLater(prepare(['/a'], options: invalid), throwsFormatException);
      final forged = FileOperationPlan(
        source: source,
        destination: target,
        targetDirectory: '/target',
        options: invalid,
        entries: [FileOperationEntry(source.item('/a'), '/target/a')],
        errors: [],
      );
      await expectLater(execute(forged), throwsFormatException);
      expect(target.writeAttempts, isEmpty);
    });

    test('saved duplicate-name bases cannot redirect a late conflict', () async {
      source.file('/a', 'retain');
      target.file('/target/a', 'old');
      final plan = await prepare(
        ['/a'],
        options: const FileOperationOptions(fileConflict: FileConflictPolicy.keepBoth),
      );
      target.file(plan.entries.single.destination, 'late conflict');
      plan.entries.single.recovery!['duplicateNameBase'] = '/elsewhere/a';
      await execute(plan);
      expect(plan.entries.single.outcome, FileOperationOutcome.failed);
      expect(plan.entries.single.message, contains('duplicate-name base'));
      expect(target.writeAttempts, isEmpty);
    });

    test('same-directory Keep both creates a distinct copy and preserves the source', () async {
      source.file('/tree/a.txt', 'original');
      source.file('/tree/a (1).txt', 'earlier copy');
      final plan = await prepare(
        ['/tree/a.txt'],
        targetBackend: source,
        destination: '/tree',
        options: const FileOperationOptions(
          fileConflict: FileConflictPolicy.keepBoth,
        ),
      );
      expect(plan.canExecute, isTrue);
      expect(plan.entries.single.destination, '/tree/a (2).txt');
      await execute(plan);
      expect(source.text('/tree/a.txt'), 'original');
      expect(source.text('/tree/a (1).txt'), 'earlier copy');
      expect(source.text('/tree/a (2).txt'), 'original');
      expect(plan.entries.single.outcome, FileOperationOutcome.copied);
    });

    test('case-insensitive aliases cannot move a file onto itself', () async {
      source = _CaseInsensitiveMemoryBackend('case-insensitive source');
      source.file('/Tree/Name.txt', 'retain');
      final plan = await prepare(
        ['/Tree/Name.txt'],
        targetBackend: source,
        destination: '/tree',
        options: const FileOperationOptions(
          kind: FileOperationKind.move,
          fileConflict: FileConflictPolicy.keepBoth,
        ),
      );
      expect(plan.canExecute, isFalse);
      expect(plan.errors.join(), contains('into itself'));
      expect(source.text('/Tree/Name.txt'), 'retain');
      expect(source.writeAttempts, isEmpty);
    });

    test(
      'case-insensitive aliases cannot copy a folder inside itself',
      () async {
        source = _CaseInsensitiveMemoryBackend('case-insensitive source');
        source.file('/Tree/Name.txt', 'retain');
        final plan = await prepare(
          ['/Tree'],
          targetBackend: source,
          destination: '/tree/archive',
        );
        expect(plan.canExecute, isFalse);
        expect(plan.errors.join(), contains('into itself'));
        expect(source.writeAttempts, isEmpty);
      },
    );

    test(
      'case-insensitive destination reservations prevent flattened collisions',
      () async {
        source.file('/one/Name.txt', 'one');
        source.file('/two/name.txt', 'two');
        target = _CaseInsensitiveMemoryBackend('case-insensitive destination')
          ..directory('/target');
        final collision = await prepare(['/one/Name.txt', '/two/name.txt']);
        expect(collision.canExecute, isFalse);
        final keepBoth = await prepare(
          ['/one/Name.txt', '/two/name.txt'],
          options: const FileOperationOptions(
            fileConflict: FileConflictPolicy.keepBoth,
          ),
        );
        expect(keepBoth.canExecute, isTrue);
        await execute(keepBoth);
        expect(
          keepBoth.entries
              .map((entry) => target.pathKey(entry.destination))
              .toSet(),
          hasLength(2),
        );
        expect(
          keepBoth.entries
              .map((entry) => target.text(entry.destination))
              .toSet(),
          {'one', 'two'},
        );
      },
    );

    test(
      'copies a list spanning source directories without changing sources',
      () async {
        source.file('/one/a.txt', 'alpha');
        source.file('/two/b.txt', 'beta');
        final plan = await prepare(['/one/a.txt', '/two/b.txt']);

        expect(plan.canExecute, isTrue);
        expect(plan.fileCount, 2);
        expect(plan.totalBytes, 9);
        await execute(plan);

        expect(target.text('/target/a.txt'), 'alpha');
        expect(target.text('/target/b.txt'), 'beta');
        expect(source.text('/one/a.txt'), 'alpha');
        expect(source.text('/two/b.txt'), 'beta');
        expect(
          plan.entries.map((e) => e.outcome),
          everyElement(FileOperationOutcome.copied),
        );
      },
    );

    test('rejects duplicate destination names before writing', () async {
      source.file('/one/same.txt', 'one');
      source.file('/two/same.txt', 'two');
      final plan = await prepare(['/one/same.txt', '/two/same.txt']);

      expect(plan.canExecute, isFalse);
      expect(plan.errors.join(), contains('Several source items'));
      await expectLater(execute(plan), throwsStateError);
      expect(target.writeAttempts, isEmpty);
    });

    test(
      'keep both reserves unique names across the selection and existing files',
      () async {
        source.file('/one/same.txt', 'one');
        source.file('/two/same.txt', 'two');
        target.file('/target/same.txt', 'original');
        final firstPreview = await prepare(
          ['/one/same.txt'],
          options: const FileOperationOptions(
            fileConflict: FileConflictPolicy.keepBoth,
          ),
        );
        expect(firstPreview.entries.single.destination, '/target/same (1).txt');
        target.file('/target/same (1).txt', 'earlier copy');
        final plan = await prepare(
          ['/one/same.txt', '/two/same.txt'],
          options: const FileOperationOptions(
            fileConflict: FileConflictPolicy.keepBoth,
          ),
        );
        expect(plan.entries.map((entry) => entry.destination), [
          '/target/same (2).txt',
          '/target/same (3).txt',
        ]);
        await execute(plan);

        expect(target.text('/target/same.txt'), 'original');
        expect(target.text('/target/same (1).txt'), 'earlier copy');
        expect(plan.entries.map((e) => e.destination).toSet(), hasLength(2));
        expect(plan.entries.map((e) => target.text(e.destination)).toSet(), {
          'one',
          'two',
        });
        expect(
          plan.entries.map((e) => e.outcome),
          everyElement(FileOperationOutcome.copied),
        );
      },
    );

    test(
      'a selected parent and repeated selected descendants are processed once',
      () async {
        source.file('/tree/nested/a.txt', 'alpha');
        final plan = await prepare([
          '/tree',
          '/tree/nested',
          '/tree/nested/a.txt',
          '/tree/nested/a.txt',
        ]);
        await execute(plan);

        expect(
          plan.entries.where((e) => e.source.path == '/tree/nested/a.txt'),
          hasLength(1),
        );
        expect(target.writeAttempts['/target/tree/nested/a.txt'], 1);
      },
    );

    test(
      'preserves relative paths for equal names in separate source directories',
      () async {
        source.file('/root/one/same.txt', 'one');
        source.file('/root/two/same.txt', 'two');
        final plan = await prepare(
          ['/root/one/same.txt', '/root/two/same.txt'],
          options: const FileOperationOptions(
            preserveRelativePaths: true,
            relativeBase: '/root',
          ),
        );
        await execute(plan);

        expect(target.text('/target/one/same.txt'), 'one');
        expect(target.text('/target/two/same.txt'), 'two');
      },
    );

    test('refuses an item outside the relative base', () async {
      source.file('/outside/a.txt', 'a');
      final plan = await prepare(
        ['/outside/a.txt'],
        options: const FileOperationOptions(
          preserveRelativePaths: true,
          relativeBase: '/root',
        ),
      );
      expect(plan.canExecute, isFalse);
      expect(plan.errors.join(), contains('outside the relative base'));
      expect(target.writeAttempts, isEmpty);
    });

    test(
      'refuses copy and move into the source itself or its descendants',
      () async {
        source.file('/tree/a.txt', 'a');
        for (final kind in FileOperationKind.values) {
          final folderPlan = await prepare(
            ['/tree'],
            options: FileOperationOptions(kind: kind),
            destination: '/tree/archive',
            targetBackend: source,
          );
          final filePlan = await prepare(
            ['/tree/a.txt'],
            options: FileOperationOptions(kind: kind),
            destination: '/tree',
            targetBackend: source,
          );
          expect(folderPlan.canExecute, isFalse);
          expect(filePlan.canExecute, isFalse);
        }
        expect(source.text('/tree/a.txt'), 'a');
      },
    );

    test('refuses file/folder conflicts in either direction', () async {
      source.file('/source/file', 'a');
      source.directory('/source/folder');
      target.directory('/target/file');
      target.file('/target/folder', 'keep');
      for (final path in ['/source/file', '/source/folder']) {
        final plan = await prepare(
          [path],
          options: const FileOperationOptions(
            fileConflict: FileConflictPolicy.replace,
          ),
        );
        expect(plan.canExecute, isFalse);
        expect(plan.errors.join(), contains('incompatible type'));
      }
      expect(target.text('/target/folder'), 'keep');
    });

    test('rejects a symbolic-link destination ancestor', () async {
      source.file('/source/a.txt', 'a');
      target.link('/target/link', '/elsewhere');
      final plan = await prepare([
        '/source/a.txt',
      ], destination: '/target/link');
      expect(plan.canExecute, isFalse);
      expect(plan.errors.join(), contains('not a regular directory'));
      expect(target.writeAttempts, isEmpty);
    });
  });

  group('conflicts, recursion, and filtering', () {
    test('skipping one list folder does not skip another source sharing its destination', () async {
      source.file('/left/common/a.txt', 'left');
      source.file('/right/common/b.txt', 'right');
      target.directory('/target/common');
      final plan = await prepare(
        ['/left/common', '/right/common'],
        options: const FileOperationOptions(
          directoryConflict: DirectoryConflictPolicy.ask,
        ),
      );
      final asked = <String>[];
      await execute(
        plan,
        resolveConflict: (entry, _) async {
          asked.add(entry.source.path!);
          return entry.source.path == '/left/common'
              ? FileConflictDecision.skip
              : FileConflictDecision.merge;
        },
      );
      expect(asked, ['/left/common', '/right/common']);
      expect(target.contains('/target/common/a.txt'), isFalse);
      expect(target.text('/target/common/b.txt'), 'right');
    });

    test('file-only decisions cannot redirect a folder away from its planned children', () async {
      source.file('/tree/a.txt', 'source');
      target.directory('/target/tree');
      final plan = await prepare(
        ['/tree'],
        options: const FileOperationOptions(
          directoryConflict: DirectoryConflictPolicy.ask,
        ),
      );
      await execute(
        plan,
        resolveConflict: (_, __) async => FileConflictDecision.keepBoth,
      );
      expect(plan.entries.first.outcome, FileOperationOutcome.failed);
      expect(plan.entries.first.message, contains('not valid for this item'));
      expect(target.writeAttempts, isEmpty);
      expect(source.text('/tree/a.txt'), 'source');
    });

    final older = DateTime.utc(2025, 1, 1);
    final newer = DateTime.utc(2025, 2, 1);
    final cases =
        <
          ({
            String name,
            DateTime? sourceDate,
            DateTime? targetDate,
            bool replace,
          })
        >[
          (
            name: 'newer source',
            sourceDate: newer,
            targetDate: older,
            replace: true,
          ),
          (
            name: 'older source',
            sourceDate: older,
            targetDate: newer,
            replace: false,
          ),
          (
            name: 'equal timestamps',
            sourceDate: newer,
            targetDate: newer,
            replace: false,
          ),
          (
            name: 'unknown source timestamp',
            sourceDate: null,
            targetDate: older,
            replace: false,
          ),
          (
            name: 'unknown destination timestamp',
            sourceDate: newer,
            targetDate: null,
            replace: false,
          ),
        ];
    for (final example in cases) {
      test('replace if newer handles ${example.name}', () async {
        source.file('/source/a.txt', 'new', modified: example.sourceDate);
        target.file('/target/a.txt', 'old', modified: example.targetDate);
        final plan = await prepare(
          ['/source/a.txt'],
          options: const FileOperationOptions(
            fileConflict: FileConflictPolicy.replaceIfNewer,
          ),
        );
        await execute(plan);
        expect(target.text('/target/a.txt'), example.replace ? 'new' : 'old');
        expect(
          plan.entries.single.outcome,
          example.replace
              ? FileOperationOutcome.copied
              : FileOperationOutcome.skipped,
        );
      });
    }

    test('ask honors per-item skip and replacement decisions', () async {
      source.file('/source/a.txt', 'new a');
      source.file('/source/b.txt', 'new b');
      target.file('/target/a.txt', 'old a');
      target.file('/target/b.txt', 'old b');
      final plan = await prepare(['/source/a.txt', '/source/b.txt']);
      final asked = <String>[];
      await execute(
        plan,
        resolveConflict: (entry, existing) async {
          asked.add(entry.source.path!);
          return entry.source.name == 'a.txt'
              ? FileConflictDecision.skip
              : FileConflictDecision.replace;
        },
      );
      expect(asked, ['/source/a.txt', '/source/b.txt']);
      expect(target.text('/target/a.txt'), 'old a');
      expect(target.text('/target/b.txt'), 'new b');
    });

    test(
      'skipping an existing directory skips all descendants during move',
      () async {
        source.file('/tree/nested/a.txt', 'source');
        target.file('/target/tree/keep.txt', 'target');
        final plan = await prepare(
          ['/tree'],
          options: const FileOperationOptions(
            kind: FileOperationKind.move,
            directoryConflict: DirectoryConflictPolicy.skip,
          ),
        );
        await execute(plan);
        expect(source.text('/tree/nested/a.txt'), 'source');
        expect(target.text('/target/tree/keep.txt'), 'target');
        expect(target.contains('/target/tree/nested/a.txt'), isFalse);
        expect(
          plan.entries.map((e) => e.outcome),
          everyElement(FileOperationOutcome.skipped),
        );
      },
    );

    test(
      'filtered recursive move retains excluded files and their source folders',
      () async {
        source.file('/tree/nested/keep.txt', 'move');
        source.file('/tree/nested/stay.bin', 'retain');
        final plan = await prepare(
          ['/tree'],
          options: FileOperationOptions(
            kind: FileOperationKind.move,
            pattern: FileSelectionPattern('*.txt'),
          ),
        );
        await execute(plan);
        expect(target.text('/target/tree/nested/keep.txt'), 'move');
        expect(source.contains('/tree/nested/keep.txt'), isFalse);
        expect(source.text('/tree/nested/stay.bin'), 'retain');
        expect(source.contains('/tree/nested'), isTrue);
        expect(source.contains('/tree'), isTrue);
        expect(target.contains('/target/tree/nested/stay.bin'), isFalse);
        expect(
          plan.entries.singleWhere((e) => e.source.name == 'stay.bin').outcome,
          FileOperationOutcome.filtered,
        );
      },
    );

    test('turning recursion off leaves directories untouched', () async {
      source.file('/tree/keep.txt', 'retain');
      source.file('/loose.txt', 'copy');
      final plan = await prepare([
        '/tree',
        '/loose.txt',
      ], options: const FileOperationOptions(recursive: false));
      await execute(plan);
      expect(source.text('/tree/keep.txt'), 'retain');
      expect(target.contains('/target/tree'), isFalse);
      expect(target.text('/target/loose.txt'), 'copy');
    });

    test(
      'an explicitly selected child still copies when recursion is off',
      () async {
        source.file('/tree/keep.txt', 'copy');
        final plan = await prepare([
          '/tree',
          '/tree/keep.txt',
        ], options: const FileOperationOptions(recursive: false));
        expect(plan.canExecute, isTrue);
        await execute(plan);
        expect(target.text('/target/keep.txt'), 'copy');
        expect(target.contains('/target/tree'), isFalse);
      },
    );

    test('modification times are preserved only when supported', () async {
      final modified = DateTime.utc(2024, 2, 3, 4, 5, 6);
      source.file('/source/a.txt', 'a', modified: modified);
      final plan = await prepare([
        '/source/a.txt',
      ], options: const FileOperationOptions(preserveModified: true));
      await execute(plan);
      expect(target.item('/target/a.txt').updatedAt, modified);

      target.modifiedTimesSupported = false;
      final unsupported = await prepare([
        '/source/a.txt',
      ], options: const FileOperationOptions(preserveModified: true));
      expect(unsupported.canExecute, isFalse);
      expect(
        unsupported.errors.join(),
        contains('cannot preserve modification times'),
      );
    });
  });

  group('failure, cancellation, and authentication safety', () {
    test(
      'a destination edited during conflict inspection is never replaced',
      () async {
        source.file('/source/a.txt', 'incoming');
        target.file('/target/a.txt', 'original');
        final plan = await prepare(['/source/a.txt']);
        await execute(
          plan,
          resolveConflict: (_, __) async {
            target.file('/target/a.txt', 'concurrent edit');
            return FileConflictDecision.replace;
          },
        );
        expect(plan.entries.single.outcome, FileOperationOutcome.failed);
        expect(
          plan.entries.single.message,
          contains('Destination changed while resolving'),
        );
        expect(target.text('/target/a.txt'), 'concurrent edit');
        expect(target.writeAttempts, isEmpty);
        expect(source.text('/source/a.txt'), 'incoming');
      },
    );

    test(
      'a source edited during conflict inspection is retained without copying',
      () async {
        source.file('/source/a.txt', 'incoming');
        target.file('/target/a.txt', 'original');
        final plan = await prepare([
          '/source/a.txt',
        ], options: const FileOperationOptions(kind: FileOperationKind.move));
        await execute(
          plan,
          resolveConflict: (_, __) async {
            source.file('/source/a.txt', 'concurrent source edit');
            return FileConflictDecision.replace;
          },
        );
        expect(plan.entries.single.outcome, FileOperationOutcome.failed);
        expect(
          plan.entries.single.message,
          contains('Source changed while resolving'),
        );
        expect(target.text('/target/a.txt'), 'original');
        expect(target.writeAttempts, isEmpty);
        expect(source.text('/source/a.txt'), 'concurrent source edit');
        expect(source.deleted, isEmpty);
      },
    );

    for (final stopOnError in [true, false]) {
      test(
        'partial move retains failed files (stop on error: $stopOnError)',
        () async {
          source.file('/tree/a.txt', 'a');
          source.file('/tree/b.txt', 'b');
          source.file('/tree/c.txt', 'c');
          target.failingWrites.add('/target/tree/b.txt');
          final plan = await prepare(
            ['/tree'],
            options: FileOperationOptions(
              kind: FileOperationKind.move,
              stopOnError: stopOnError,
            ),
          );
          await execute(plan);

          expect(source.contains('/tree/a.txt'), isFalse);
          expect(target.text('/target/tree/a.txt'), 'a');
          expect(source.text('/tree/b.txt'), 'b');
          expect(source.contains('/tree'), isTrue);
          expect(source.contains('/tree/c.txt'), stopOnError);
          expect(target.contains('/target/tree/c.txt'), !stopOnError);
          expect(
            plan.entries.singleWhere((e) => e.source.name == 'b.txt').outcome,
            FileOperationOutcome.failed,
          );
          expect(
            plan.entries.singleWhere((e) => e.source.name == 'c.txt').outcome,
            stopOnError
                ? FileOperationOutcome.cancelled
                : FileOperationOutcome.moved,
          );
        },
      );
    }

    test(
      'failed replacement does not delete source or alter existing destination',
      () async {
        source.file('/source/a.txt', 'new contents');
        target.file('/target/a.txt', 'original');
        target.failingWrites.add('/target/a.txt');
        final plan = await prepare(
          ['/source/a.txt'],
          options: const FileOperationOptions(
            kind: FileOperationKind.move,
            fileConflict: FileConflictPolicy.replace,
          ),
        );
        await execute(plan);
        expect(plan.entries.single.outcome, FileOperationOutcome.failed);
        expect(source.text('/source/a.txt'), 'new contents');
        expect(target.text('/target/a.txt'), 'original');
      },
    );

    test(
      'cancellation while streaming retains source and previous destination',
      () async {
        source.file('/source/a.txt', 'several chunks');
        target.file('/target/a.txt', 'original');
        final control = FileOperationControl();
        target.onWriteChunk = (_, __) => control.cancel();
        final plan = await prepare(
          ['/source/a.txt'],
          options: const FileOperationOptions(
            kind: FileOperationKind.move,
            fileConflict: FileConflictPolicy.replace,
          ),
        );
        await execute(plan, control: control);
        expect(plan.entries.single.outcome, FileOperationOutcome.cancelled);
        expect(source.text('/source/a.txt'), 'several chunks');
        expect(target.text('/target/a.txt'), 'original');
      },
    );

    test(
      'cancellation after destination commit still retains the source',
      () async {
        source.file('/source/a.txt', 'contents');
        final control = FileOperationControl();
        target.onWriteCommitted = (_) => control.cancel();
        final plan = await prepare([
          '/source/a.txt',
        ], options: const FileOperationOptions(kind: FileOperationKind.move));
        await execute(plan, control: control);
        expect(plan.entries.single.outcome, FileOperationOutcome.cancelled);
        expect(source.text('/source/a.txt'), 'contents');
        expect(target.text('/target/a.txt'), 'contents');
        expect(source.deleted, isEmpty);
      },
    );

    test(
      'pausing does not write and cancelling a paused operation unblocks it',
      () async {
        source.file('/source/a.txt', 'contents');
        final plan = await prepare(['/source/a.txt']);
        final control = FileOperationControl()..pause();
        final running = execute(plan, control: control);
        await Future<void>.delayed(Duration.zero);
        expect(target.writeAttempts, isEmpty);
        control.cancel();
        await running;
        expect(plan.entries.single.outcome, FileOperationOutcome.cancelled);
        expect(source.text('/source/a.txt'), 'contents');
      },
    );

    test('authentication changes before execution prevent writes', () async {
      source.file('/source/a.txt', 'contents');
      final plan = await prepare(['/source/a.txt']);
      target.current = false;
      await execute(plan);
      expect(plan.entries.single.outcome, FileOperationOutcome.failed);
      expect(plan.entries.single.message, contains('account changed'));
      expect(target.writeAttempts, isEmpty);
      expect(source.contains('/source/a.txt'), isTrue);
    });

    test(
      'authentication changes after upload never authorize source deletion',
      () async {
        source.file('/source/a.txt', 'contents');
        final plan = await prepare([
          '/source/a.txt',
        ], options: const FileOperationOptions(kind: FileOperationKind.move));
        target.onWriteCommitted = (_) => source.current = false;
        await execute(plan);
        expect(plan.entries.single.outcome, FileOperationOutcome.failed);
        expect(source.contains('/source/a.txt'), isTrue);
        expect(source.deleted, isEmpty);
      },
    );

    test('source changed after preview is retained without writing', () async {
      source.file('/source/a.txt', 'old', modified: DateTime.utc(2025));
      final plan = await prepare([
        '/source/a.txt',
      ], options: const FileOperationOptions(kind: FileOperationKind.move));
      source.file('/source/a.txt', 'new', modified: DateTime.utc(2026));
      await execute(plan);
      expect(plan.entries.single.outcome, FileOperationOutcome.failed);
      expect(target.writeAttempts, isEmpty);
      expect(source.text('/source/a.txt'), 'new');
    });

    test(
      'source changed during upload is retained despite successful copy',
      () async {
        source.file('/source/a.txt', 'old', modified: DateTime.utc(2025));
        final plan = await prepare([
          '/source/a.txt',
        ], options: const FileOperationOptions(kind: FileOperationKind.move));
        target.onWriteCommitted = (_) =>
            source.file('/source/a.txt', 'new', modified: DateTime.utc(2026));
        await execute(plan);
        expect(plan.entries.single.outcome, FileOperationOutcome.failed);
        expect(source.text('/source/a.txt'), 'new');
        expect(target.text('/target/a.txt'), 'old');
        expect(source.deleted, isEmpty);
      },
    );

    test(
      'content verification detects same-length corruption and keeps source',
      () async {
        source.file('/source/a.txt', 'original');
        target.corruptWrites.add('/target/a.txt');
        final plan = await prepare(
          ['/source/a.txt'],
          options: const FileOperationOptions(
            kind: FileOperationKind.move,
            verifyContents: true,
          ),
        );
        await execute(plan);
        expect(plan.entries.single.outcome, FileOperationOutcome.failed);
        expect(
          plan.entries.single.message,
          contains('SHA-256 verification failed'),
        );
        expect(source.text('/source/a.txt'), 'original');
        expect(source.deleted, isEmpty);
      },
    );

    test(
      'verified successful move deletes source only after a complete copy',
      () async {
        source.file('/tree/nested/a.txt', 'original');
        final plan = await prepare(
          ['/tree'],
          options: const FileOperationOptions(
            kind: FileOperationKind.move,
            verifyContents: true,
          ),
        );
        await execute(plan);
        expect(target.text('/target/tree/nested/a.txt'), 'original');
        expect(source.contains('/tree'), isFalse);
        expect(
          plan.entries.map((e) => e.outcome),
          everyElement(FileOperationOutcome.moved),
        );
      },
    );
  });

  group('symbolic links', () {
    test(
      'links are skipped by default and their targets are never traversed',
      () async {
        source.file('/secret/keep.txt', 'secret');
        source.link('/tree/link', '/secret');
        final plan = await prepare(['/tree']);
        await execute(plan);
        expect(
          plan.entries.singleWhere((e) => e.source.name == 'link').outcome,
          FileOperationOutcome.skipped,
        );
        expect(target.contains('/target/tree/link'), isFalse);
        expect(source.reads, isEmpty);
      },
    );

    test(
      'explicit link copying copies the link rather than target content',
      () async {
        source.link('/tree/link', '../outside');
        final plan = await prepare([
          '/tree/link',
        ], options: const FileOperationOptions(copySymbolicLinks: true));
        await execute(plan);
        expect(target.item('/target/link').isSymlink, isTrue);
        expect(target.item('/target/link').symlinkTarget, '../outside');
        expect(source.reads, isEmpty);
      },
    );

    test('a link retargeted after preview is retained instead of moving stale data', () async {
      source.link('/tree/link', '../old-target');
      final plan = await prepare(
        ['/tree/link'],
        options: const FileOperationOptions(
          kind: FileOperationKind.move,
          copySymbolicLinks: true,
        ),
      );
      source.link('/tree/link', '../new-target');
      await execute(plan);
      expect(plan.entries.single.outcome, FileOperationOutcome.failed);
      expect(source.item('/tree/link').symlinkTarget, '../new-target');
      expect(source.deleted, isEmpty);
      expect(target.contains('/target/link'), isFalse);
    });
  });
}

class _DecliningCloneBackend extends _MemoryBackend {
  _DecliningCloneBackend() : super('clone');
  int cloneAttempts = 0;
  @override
  StorageTransferCapabilities get capabilities =>
      const StorageTransferCapabilities(copyOnWrite: true, preallocate: true);
  @override
  Future<bool> clonePreparedFile(
    FileItem source,
    String destination, {
    required bool replace,
    Future<void> Function(FileItem)? verifyStaged,
    Future<void> Function(Map<String, dynamic>)? checkpoint,
  }) async {
    cloneAttempts++;
    return false;
  }
}

class _MemoryNode {
  _MemoryNode(this.item, [this.bytes = const []]);
  FileItem item;
  final List<int> bytes;
}

class _CaseInsensitiveMemoryBackend extends _MemoryBackend {
  _CaseInsensitiveMemoryBackend(super.label);

  @override
  String pathKey(String path) => super.pathKey(path).toLowerCase();

  @override
  Future<FileItem?> stat(String path) async {
    _check();
    for (final entry in nodes.entries) {
      if (pathKey(entry.key) == pathKey(path)) return entry.value.item;
    }
    return null;
  }
}

/// Reports its proposed staging path before writing any file content.
class _StagedPathBackend extends _MemoryBackend {
  _StagedPathBackend(this.stagedPath) : super('target');

  final String stagedPath;

  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem staged)? verifyStaged,
    Future<void> Function(Map<String, dynamic> state)? checkpoint,
  }) async {
    await checkpoint?.call({
      'phase': 'writing',
      'stagedPath': stagedPath,
      'destination': path,
    });
    await super.writePreparedFile(
      path,
      data,
      length,
      replace: replace,
      verifyStaged: verifyStaged,
      checkpoint: checkpoint,
    );
  }
}

/// Models the backend's staged-write contract and records externally visible
/// effects. Failure hooks let tests exercise races without wall-clock timing.
class _MemoryBackend extends FileOperationBackend {
  _MemoryBackend(this.label) {
    directory('/');
  }

  @override
  final String label;
  @override
  final Object identity = Object();
  @override
  p.Context get paths => p.posix;
  bool current = true;
  bool listingBackedStat = false;
  int statCalls = 0;
  final listedPaths = <String>[];
  @override
  bool get statRequiresDirectoryListing => listingBackedStat;
  bool modifiedTimesSupported = true;
  @override
  bool get isCurrent => current;
  @override
  bool get supportsModifiedTime => modifiedTimesSupported;
  @override
  bool get supportsSymbolicLinks => true;

  final nodes = <String, _MemoryNode>{};
  final writeAttempts = <String, int>{};
  final failingWrites = <String>{};
  final corruptWrites = <String>{};
  final deleted = <String>[];
  final reads = <String>[];
  FutureOr<void> Function(String path, List<int> chunk)? onWriteChunk;
  FutureOr<void> Function(String path)? onWriteCommitted;

  bool contains(String path) => nodes.containsKey(path);
  FileItem item(String path) => nodes[path]!.item;
  String text(String path) => utf8.decode(nodes[path]!.bytes);

  void directory(String path) {
    final parent = paths.dirname(path);
    if (path != parent && !nodes.containsKey(parent)) directory(parent);
    nodes[path] = _MemoryNode(
      FileItem(
        name: paths.basename(path),
        path: path,
        isFolder: true,
        isSymlink: false,
      ),
    );
  }

  void file(String path, String contents, {DateTime? modified}) {
    final parent = paths.dirname(path);
    if (!nodes.containsKey(parent)) directory(parent);
    final bytes = utf8.encode(contents);
    nodes[path] = _MemoryNode(
      FileItem(
        name: paths.basename(path),
        path: path,
        isFolder: false,
        isSymlink: false,
        size: bytes.length,
        updatedAt: modified,
      ),
      bytes,
    );
  }

  void link(String path, String target) {
    final parent = paths.dirname(path);
    if (!nodes.containsKey(parent)) directory(parent);
    nodes[path] = _MemoryNode(
      FileItem(
        name: paths.basename(path),
        path: path,
        isFolder: false,
        isSymlink: true,
        symlinkTarget: target,
      ),
    );
  }

  void _check() {
    if (!current) throw StateError('Backend account changed');
  }

  @override
  Future<FileItem?> stat(String path) async {
    _check();
    statCalls++;
    return nodes[path]?.item;
  }

  @override
  Future<List<FileItem>> list(String path) async {
    _check();
    listedPaths.add(path);
    if (nodes[path]?.item.isFolder != true) {
      throw StateError('Not a directory: $path');
    }
    return nodes.entries
        .where((entry) => entry.key != path && paths.dirname(entry.key) == path)
        .map((entry) => entry.value.item)
        .toList();
  }

  @override
  Future<void> createDirectory(String path) async {
    _check();
    if (nodes.containsKey(path)) throw StateError('Destination exists: $path');
    if (nodes[paths.dirname(path)]?.item.isFolder != true) {
      throw StateError('Missing parent: $path');
    }
    directory(path);
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    _check();
    reads.add(file.path!);
    if (file.isSymlink == true) {
      throw StateError('Cannot follow symbolic links');
    }
    final bytes = List<int>.of(nodes[file.path!]!.bytes);
    for (var start = 0; start < bytes.length; start += 2) {
      _check();
      yield bytes.sublist(start, (start + 2).clamp(0, bytes.length));
    }
  }

  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async {
    _check();
    writeAttempts.update(path, (count) => count + 1, ifAbsent: () => 1);
    if (nodes.containsKey(path) && !replace) {
      throw StateError('Destination exists');
    }
    final staged = <int>[];
    await for (final chunk in data) {
      _check();
      staged.addAll(chunk);
      await onWriteChunk?.call(path, chunk);
      if (failingWrites.contains(path)) {
        throw StateError('Simulated write failure');
      }
    }
    _check();
    if (length != null && staged.length != length) {
      throw StateError('Wrong source length');
    }
    if (corruptWrites.contains(path) && staged.isNotEmpty) staged[0] ^= 1;
    nodes[path] = _MemoryNode(
      FileItem(
        name: paths.basename(path),
        path: path,
        isFolder: false,
        isSymlink: false,
        size: staged.length,
      ),
      staged,
    );
    await onWriteCommitted?.call(path);
  }

  @override
  Future<void> deleteFile(FileItem file) async {
    _check();
    if (nodes[file.path!]?.item.isFolder == true) {
      throw StateError('Refusing recursive deletion');
    }
    nodes.remove(file.path!);
    deleted.add(file.path!);
  }

  @override
  Future<void> deleteEmptyDirectory(String path) async {
    _check();
    if ((await list(path)).isNotEmpty) throw StateError('Directory not empty');
    nodes.remove(path);
    deleted.add(path);
  }

  @override
  Future<void> setModified(String path, DateTime modified) async {
    _check();
    nodes[path]!.item = nodes[path]!.item.copyWith(updatedAt: modified);
  }

  @override
  Future<void> copySymbolicLink(
    FileItem source,
    String destination, {
    required bool replace,
  }) async {
    _check();
    if (nodes.containsKey(destination)) throw StateError('Destination exists');
    link(destination, source.symlinkTarget!);
  }
}
