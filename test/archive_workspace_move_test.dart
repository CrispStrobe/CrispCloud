import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codec;
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_package_writers.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_service.dart';
import 'package:crisp_cloud/services/archive_tar_writer.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_endpoint_backend.dart';
import 'support/archive_package_fixtures.dart';
import 'support/archive_package_writer_fixtures.dart';
import 'support/archive_tar_writer_fixtures.dart';

Uint8List _zip(Map<String, List<int>?> files) {
  final archive = codec.Archive();
  for (final entry in files.entries) {
    archive.addFile(
      (entry.value == null
            ? codec.ArchiveFile.directory(entry.key)
            : codec.ArchiveFile.bytes(entry.key, entry.value!))
        ..mode = entry.value == null ? 0x1e8 : 0x1a0
        ..lastModTime = 1700000000,
    );
  }
  return Uint8List.fromList(codec.ZipEncoder().encode(archive));
}

Future<Uint8List> _protected(koni.ArchiveWriteFormat format) async {
  final sink = koni.BytesBuilderSink();
  final writer = koni.Archive.create(
    sink,
    format: format,
    options: const koni.ArchiveWriteOptions(
      password: 'original-secret',
      encryptHeader: true,
    ),
  );
  await writer.addEntry(
    koni.ArchiveEntrySpec(
      path: 'destination',
      type: koni.ArchiveEntryType.directory,
      posixMode: 0x1e8,
      modified: DateTime.utc(2025, 2, 3, 4, 5, 6),
    ),
  );
  await writer.addBytes(
    koni.ArchiveEntrySpec(
      path: 'secret.txt',
      posixMode: 0x1a0,
      modified: DateTime.utc(2025, 2, 3, 4, 5, 6),
    ),
    Uint8List.fromList([1, 2, 3]),
  );
  await writer.close();
  await sink.close();
  return sink.takeBytes();
}

String _name(ViewerArchiveMember member) => member.name == '/' && !member.isFile
    ? '/'
    : ArchiveService.safeMemberPath(member.name);

Map<String, Object?> _retainedMetadata(Map<String, Object?> attributes) => {
  for (final entry in attributes.entries)
    if (!entry.key.startsWith('package.') && entry.key != 'cpio.storedPath')
      entry.key: entry.value,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ArchiveEndpointTestBackend backend;
  late ArchivePublicationJournal journal;

  setUp(() {
    backend = ArchiveEndpointTestBackend();
    journal = ArchivePublicationJournal(storage: MemoryFileCollectionStorage());
  });

  Future<ArchiveWorkspace> open(
    Uint8List bytes, {
    String name = 'files.zip',
    List<String> nested = const [],
    List<String?>? passwords,
  }) async {
    final path = '/out/$name';
    backend.put(path, bytes);
    final workspace = await ArchiveWorkspace.openNested(
      backend,
      (await backend.stat(path))!,
      nested,
      passwords: passwords,
      journal: journal,
    );
    addTearDown(workspace.close);
    return workspace;
  }

  Future<ViewerArchive> published(String name, {String? password}) async {
    final reader = await openViewerArchive(
      backend.files['/out/$name']!,
      name: name,
      password: password,
    );
    addTearDown(reader.close);
    return reader;
  }

  test(
    'one grouped move preserves trees, empty folders, order and bytes',
    () async {
      final original = _zip({
        'source/first.txt': [1, 2],
        'source/empty/': null,
        'second.txt': [3, 4],
        'destination/': null,
        'unchanged.txt': [9],
      });
      final originalReader = await openViewerArchive(
        original,
        name: 'files.zip',
      );
      addTearDown(originalReader.close);
      final workspace = await open(original);
      final revision = workspace.revision;
      final result = workspace.moveMembers([
        '/second.txt',
        '/source',
      ], '/destination');
      expect(result.moved, {
        '/second.txt': '/destination/second.txt',
        '/source': '/destination/source',
      });
      expect(result.skipped, isEmpty);
      expect(result.unchanged, isEmpty);
      expect(workspace.revision, revision + 1);
      expect(workspace.dirty, isTrue);
      expect(await workspace.read('/destination/source/first.txt'), [1, 2]);
      expect(workspace.list('/destination/source').map((file) => file.name), [
        'empty',
        'first.txt',
      ]);
      expect(backend.files['/out/files.zip'], original);
      expect(backend.mutations, isEmpty);
      final review = await workspace.review();
      expect(review.changes, hasLength(3));
      expect(
        review.changes.every(
          (change) => change.kind == ArchiveWorkspaceChangeKind.rename,
        ),
        isTrue,
      );
      expect(await workspace.save(reviewed: review), isNotNull);
      final reader = await published('files.zip');
      expect(reader.members.map(_name), [
        'destination/source/first.txt',
        'destination/source/empty',
        'destination/second.txt',
        'destination',
        'unchanged.txt',
      ]);
      expect(await reader.readMember(reader.members.first), [1, 2]);
      // This MS-DOS ZIP fixture has no Unix mode; the writer supplies its
      // ordinary-file default. Protected fixtures below store explicit modes.
      expect(originalReader.members.first.posixMode, isNull);
      expect(reader.members.first.posixMode! & 0xfff, 0x1a4);
      expect(
        reader.members.first.modified?.millisecondsSinceEpoch,
        1700000000000,
      );
      expect(await reader.readMember(reader.members.last), [9]);
      expect(backend.files.keys, ['/out/files.zip']);
    },
  );

  test(
    'canonical overlapping selections collapse and results are immutable',
    () async {
      final workspace = await open(
        _zip({
          'a/child.txt': [1],
          'a/empty/': null,
          'destination/': null,
        }),
      );
      final result = workspace.moveMembers([
        '/a/./child.txt',
        'a/',
        '/a',
        'a/empty',
      ], 'destination/');
      expect(result.moved, {'/a': '/destination/a'});
      expect(() => result.moved['/new'] = '/other', throwsUnsupportedError);
      expect(() => result.skipped.add('/new'), throwsUnsupportedError);
      expect(() => result.unchanged.add('/new'), throwsUnsupportedError);
    },
  );

  test(
    'moves to the same parent do not dirty the workspace or revision',
    () async {
      final workspace = await open(
        _zip({
          'folder/a.txt': [1],
          'folder/empty/': null,
        }),
      );
      final revision = workspace.revision;
      final result = workspace.moveMembers([
        '/folder/empty',
        '/folder/a.txt',
      ], '/folder');
      expect(result.moved, isEmpty);
      expect(result.unchanged, ['/folder/a.txt', '/folder/empty']);
      expect(workspace.revision, revision);
      expect(workspace.dirty, isFalse);
    },
  );

  for (final conflict in ArchiveMemberMoveConflict.values) {
    test(
      '${conflict.name} handles existing files without overwriting',
      () async {
        final workspace = await open(
          _zip({
            'a.txt': [1],
            'destination/a.txt': [2],
            'destination/a (2).txt': [3],
          }),
        );
        final revision = workspace.revision;
        if (conflict == ArchiveMemberMoveConflict.fail) {
          expect(
            () => workspace.moveMembers(
              ['/a.txt'],
              '/destination',
              conflict: conflict,
            ),
            throwsStateError,
          );
          expect(workspace.revision, revision);
          expect(workspace.dirty, isFalse);
        } else {
          final result = workspace.moveMembers(
            ['/a.txt'],
            '/destination',
            conflict: conflict,
          );
          if (conflict == ArchiveMemberMoveConflict.skip) {
            expect(result.skipped, ['/a.txt']);
            expect(result.moved, isEmpty);
            expect(workspace.revision, revision);
            expect(workspace.dirty, isFalse);
            expect(await workspace.read('/a.txt'), [1]);
          } else {
            expect(result.moved, {'/a.txt': '/destination/a (3).txt'});
            expect(await workspace.read('/destination/a (3).txt'), [1]);
          }
        }
        expect(await workspace.read('/destination/a.txt'), [2]);
        expect(await workspace.read('/destination/a (2).txt'), [3]);
      },
    );

    test(
      '${conflict.name} resolves several selected roots with the same basename',
      () async {
        final workspace = await open(
          _zip({
            'b/item.txt': [2],
            'a/item.txt': [1],
            'destination/': null,
          }),
        );
        final revision = workspace.revision;
        if (conflict == ArchiveMemberMoveConflict.fail) {
          expect(
            () => workspace.moveMembers([
              '/b/item.txt',
              '/a/item.txt',
            ], '/destination'),
            throwsStateError,
          );
          expect(workspace.revision, revision);
          expect(workspace.list('/destination'), isEmpty);
          expect(await workspace.read('/a/item.txt'), [1]);
        } else {
          final result = workspace.moveMembers(
            ['/b/item.txt', '/a/item.txt'],
            '/destination',
            conflict: conflict,
          );
          expect(await workspace.read('/destination/item.txt'), [1]);
          if (conflict == ArchiveMemberMoveConflict.skip) {
            expect(result.skipped, ['/b/item.txt']);
            expect(await workspace.read('/b/item.txt'), [2]);
          } else {
            expect(result.moved['/b/item.txt'], '/destination/item (2).txt');
            expect(await workspace.read('/destination/item (2).txt'), [2]);
          }
          expect(workspace.revision, revision + 1);
        }
      },
    );

    for (final targetIsFolder in [false, true]) {
      test(
        '${conflict.name} keeps colliding folder trees whole (folder=$targetIsFolder)',
        () async {
          final workspace = await open(
            _zip({
              'source/tree.name/a.txt': [1],
              'source/tree.name/empty/': null,
              if (targetIsFolder) 'destination/tree.name/retained.txt': [2],
              if (!targetIsFolder) 'destination/tree.name': [2],
            }),
          );
          final revision = workspace.revision;
          if (conflict == ArchiveMemberMoveConflict.fail) {
            expect(
              () =>
                  workspace.moveMembers(['/source/tree.name'], '/destination'),
              throwsStateError,
            );
            expect(workspace.revision, revision);
          } else {
            final result = workspace.moveMembers(
              ['/source/tree.name'],
              '/destination',
              conflict: conflict,
            );
            if (conflict == ArchiveMemberMoveConflict.skip) {
              expect(result.skipped, ['/source/tree.name']);
              expect(await workspace.read('/source/tree.name/a.txt'), [1]);
              expect(workspace.revision, revision);
            } else {
              expect(result.moved, {
                '/source/tree.name': '/destination/tree.name (2)',
              });
              expect(await workspace.read('/destination/tree.name (2)/a.txt'), [
                1,
              ]);
              expect(
                workspace
                    .list('/destination/tree.name (2)')
                    .where((file) => file.isFolder)
                    .single
                    .name,
                'empty',
              );
            }
          }
          expect(
            await workspace.read(
              targetIsFolder
                  ? '/destination/tree.name/retained.txt'
                  : '/destination/tree.name',
            ),
            [2],
          );
        },
      );
    }
  }

  test('a no-op selected root remains occupied for Keep both', () async {
    final workspace = await open(
      _zip({
        'a.txt': [1],
        'destination/a.txt': [2],
      }),
    );
    final result = workspace.moveMembers(
      ['/destination/a.txt', '/a.txt'],
      '/destination',
      conflict: ArchiveMemberMoveConflict.keepBoth,
    );
    expect(result.unchanged, ['/destination/a.txt']);
    expect(result.moved, {'/a.txt': '/destination/a (2).txt'});
    expect(await workspace.read('/destination/a.txt'), [2]);
  });

  test(
    'Keep both handles dotfiles and reserves names within a batch',
    () async {
      final workspace = await open(
        _zip({
          'a/.hidden': [1],
          'b/.hidden': [2],
          'c/.hidden': [3],
          'destination/.hidden': [4],
        }),
      );
      final result = workspace.moveMembers(
        ['/c/.hidden', '/b/.hidden', '/a/.hidden'],
        '/destination',
        conflict: ArchiveMemberMoveConflict.keepBoth,
      );
      expect(result.moved, {
        '/a/.hidden': '/destination/.hidden (2)',
        '/b/.hidden': '/destination/.hidden (3)',
        '/c/.hidden': '/destination/.hidden (4)',
      });
    },
  );

  for (final selection in <List<String>>[
    [],
    ['/'],
    ['../a'],
    ['/a/../../escape'],
    ['C:/a'],
    ['a\u0000'],
    ['/missing'],
    ['/a', '/a/missing'],
  ]) {
    test(
      'invalid selection $selection leaves the entire draft unchanged',
      () async {
        final workspace = await open(
          _zip({
            'a/child': [1],
            'destination/': null,
          }),
        );
        final revision = workspace.revision;
        expect(
          () => workspace.moveMembers(selection, '/destination'),
          throwsA(anyOf(isA<StateError>(), isA<ArchiveViewException>())),
        );
        expect(workspace.revision, revision);
        expect(workspace.dirty, isFalse);
        expect(await workspace.read('/a/child'), [1]);
        expect(workspace.list('/destination'), isEmpty);
      },
    );
  }

  for (final directory in [
    '',
    '.',
    '/missing',
    '/a/child',
    '../escape',
    '/a',
    '/a/deeper',
  ]) {
    test('invalid or overlapping destination "$directory" is atomic', () async {
      final workspace = await open(
        _zip({
          'a/child': [1],
          'a/deeper/': null,
          'other': [2],
        }),
      );
      final revision = workspace.revision;
      expect(
        () => workspace.moveMembers(['/other', '/a'], directory),
        throwsA(anyOf(isA<StateError>(), isA<ArchiveViewException>())),
      );
      expect(workspace.revision, revision);
      expect(workspace.dirty, isFalse);
      expect(await workspace.read('/other'), [2]);
      expect(await workspace.read('/a/child'), [1]);
    });
  }

  test('a late collision leaves earlier planned moves unapplied', () async {
    final workspace = await open(
      _zip({
        'a.txt': [1],
        'z.txt': [2],
        'destination/z.txt': [3],
      }),
    );
    final revision = workspace.revision;
    expect(
      () => workspace.moveMembers(['/a.txt', '/z.txt'], '/destination'),
      throwsStateError,
    );
    expect(workspace.revision, revision);
    expect(workspace.list('/destination').map((file) => file.name), ['z.txt']);
    expect(await workspace.read('/a.txt'), [1]);
    expect(await workspace.read('/z.txt'), [2]);
  });

  for (final depthBound in [false, true]) {
    test(
      'moving beyond the ${depthBound ? 'depth' : 'path byte'} limit is atomic',
      () async {
        final name = depthBound
            ? '${List.filled(199, 'a').join('/')}/file'
            : '${'a' * 4090}.txt';
        final workspace = await open(
          _zip({
            name: [1],
            'destination/': null,
          }),
        );
        final selected = depthBound ? 'a' : name;
        final revision = workspace.revision;
        expect(
          () => workspace.moveMembers([selected], '/destination'),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(workspace.revision, revision);
        expect(workspace.dirty, isFalse);
        expect(await workspace.read('/$name'), [1]);
      },
    );
  }

  test('aggregate path expansion is bounded before draft adoption', () async {
    final directory = 'd' * 4080;
    final files = {
      for (var i = 0; i < 2100; i++) 'f${i.toString().padLeft(4, '0')}': [1],
    };
    final workspace = await open(_zip({...files, '$directory/': null}));
    final revision = workspace.revision;
    expect(
      () => workspace.moveMembers(files.keys.toList(), directory),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(workspace.revision, revision);
    expect(workspace.dirty, isFalse);
    expect(workspace.list(directory), isEmpty);
  });

  test('moving dirty entries preserves staged data and invalidates an older review', () async {
    final workspace = await open(
      _zip({
        'a.txt': [1],
        'destination/': null,
      }),
    );
    workspace.replace('/a.txt', Uint8List.fromList([2, 3]));
    workspace.replace('/new.txt', Uint8List.fromList([4]));
    final oldReview = await workspace.review();
    workspace.moveMembers(['/new.txt', '/a.txt'], '/destination');
    expect(await workspace.read('/destination/a.txt'), [2, 3]);
    expect(await workspace.read('/destination/new.txt'), [4]);
    await expectLater(workspace.save(reviewed: oldReview), throwsStateError);
    expect(backend.mutations, isEmpty);
    await workspace.save();
    final reader = await published('files.zip');
    expect(
      reader.members.map(_name),
      containsAll(['destination/a.txt', 'destination/new.txt']),
    );
  });

  test('review in progress blocks even a no-op move', () async {
    final workspace = await open(
      _zip({
        'a.txt': [1],
        'destination/': null,
      }),
    );
    final review = workspace.review();
    expect(() => workspace.moveMembers(['/a.txt'], '/'), throwsStateError);
    await review;
    expect(workspace.dirty, isFalse);
  });

  test(
    'closed or replaced source capabilities refuse moving members',
    () async {
      final workspace = await open(
        _zip({
          'a.txt': [1],
          'destination/': null,
        }),
      );
      backend.current = false;
      expect(
        () => workspace.moveMembers(['/a.txt'], '/destination'),
        throwsStateError,
      );
      backend.current = true;
      await workspace.close();
      expect(
        () => workspace.moveMembers(['/a.txt'], '/destination'),
        throwsStateError,
      );
      expect(backend.mutations, isEmpty);
    },
  );

  test(
    'a changed physical archive is never overwritten by a reviewed move',
    () async {
      final workspace = await open(
        _zip({
          'a.txt': [1],
          'destination/': null,
        }),
      );
      workspace.moveMembers(['/a.txt'], '/destination');
      final review = await workspace.review();
      final external = _zip({
        'external.txt': [9],
      });
      backend.put('/out/files.zip', external);
      await expectLater(workspace.save(reviewed: review), throwsStateError);
      expect(backend.files['/out/files.zip'], external);
      expect(
        backend.mutations.where((value) => value.startsWith('move:')),
        isEmpty,
      );
    },
  );

  test('late install failure restores the original and blocks new moves until recovery', () async {
    final original = _zip({
      'a.txt': [1],
      'destination/': null,
    });
    final workspace = await open(original);
    workspace.moveMembers(['/a.txt'], '/destination');
    final review = await workspace.review();
    var fail = true;
    backend.before = (action, path, destination) {
      if (fail && action == 'move' && path.endsWith('.candidate')) {
        fail = false;
        throw StateError('Simulated install failure.');
      }
    };
    await expectLater(
      workspace.save(reviewed: review),
      throwsA(isA<ArchivePublicationException>()),
    );
    expect(backend.files['/out/files.zip'], original);
    expect(workspace.pendingPublication, isNotNull);
    expect(
      () => workspace.moveMembers(['/destination/a.txt'], '/'),
      throwsStateError,
    );
    expect(await workspace.save(reviewed: review), isNotNull);
    expect(backend.files.keys, ['/out/files.zip']);
    final reader = await published('files.zip');
    expect(reader.members.map(_name), contains('destination/a.txt'));
    expect(reader.members.map(_name), isNot(contains('a.txt')));
  });

  test(
    'nested moves publish one outer archive and preserve its other members',
    () async {
      final inner = _zip({
        'a.txt': [1],
        'destination/': null,
      });
      final original = _zip({
        'nested/inner.zip': inner,
        'outer.txt': [9],
      });
      final workspace = await open(original, nested: ['nested/inner.zip']);
      final parentReview = workspace.outermost.review();
      expect(
        () => workspace.moveMembers(['/a.txt'], '/destination'),
        throwsStateError,
      );
      await parentReview;
      workspace.moveMembers(['/a.txt'], '/destination');
      await workspace.save();
      final outer = await published('files.zip');
      expect(
        await outer.readMember(
          outer.members.firstWhere((member) => member.name == 'outer.txt'),
        ),
        [9],
      );
      final reader = await openViewerArchive(
        await outer.readMember(
          outer.members.firstWhere(
            (member) => member.name == 'nested/inner.zip',
          ),
        ),
        name: 'inner.zip',
      );
      addTearDown(reader.close);
      expect(reader.members.map(_name), ['destination/a.txt', 'destination']);
      expect(backend.files.keys, ['/out/files.zip']);
      expect(
        backend.mutations.any((value) => value.contains('/nested/')),
        isFalse,
      );
    },
  );

  for (final kind in <(String, koni.ArchiveWriteFormat)>[
    ('zip', const koni.ZipWriteFormat()),
    ('7z', const koni.SevenZWriteFormat()),
  ]) {
    test(
      '${kind.$1} moves retain original protection, times and modes',
      () async {
        final name = 'protected.${kind.$1}';
        final workspace = await open(
          await _protected(kind.$2),
          name: name,
          passwords: ['original-secret'],
        );
        final encryptNames = workspace.encryptNames;
        workspace.moveMembers(['/secret.txt'], '/destination');
        await workspace.save();
        expect(workspace.encrypted, isTrue);
        expect(workspace.encryptNames, encryptNames);
        final reader = await published(name, password: 'original-secret');
        final member = reader.members.firstWhere((member) => member.isFile);
        expect(_name(member), 'destination/secret.txt');
        expect(await reader.readMember(member), [1, 2, 3]);
        expect(member.modified, DateTime.utc(2025, 2, 3, 4, 5, 6));
        expect(member.posixMode! & 0xfff, 0x1a0);
        await expectLater(
          ArchiveWorkspace.open(
            backend,
            (await backend.stat('/out/$name'))!,
            password: 'wrong-secret',
            journal: journal,
          ),
          throwsA(
            anyOf(
              isA<ArchivePasswordRequiredException>(),
              isA<ArchiveViewException>(),
            ),
          ),
        );
      },
    );
  }

  for (final kind in ['ustar', 'gnu', 'pax']) {
    test(
      'TAR $kind moves preserve inspected metadata through successive saves',
      () async {
        final bytes = referenceTar(kind);
        final beforeReader = await openViewerArchive(
          bytes,
          name: 'archive.tar',
        );
        addTearDown(beforeReader.close);
        final before = await inspectTarRewrite(bytes, beforeReader);
        final workspace = await open(bytes, name: 'archive.tar');
        final roots = workspace.list().map((file) => file.path!).toList();
        workspace.createDirectory('/moved');
        workspace.moveMembers(roots, '/moved');
        await workspace.save();
        workspace.moveMembers(roots.map((path) => '/moved$path').toList(), '/');
        await workspace.save();
        final afterReader = await published('archive.tar');
        final after = await inspectTarRewrite(
          backend.files['/out/archive.tar']!,
          afterReader,
        );
        expect(after.supported, isTrue, reason: after.reason);
        for (final member in beforeReader.members) {
          final name = _name(member);
          final retained = afterReader.members.firstWhere(
            (entry) => _name(entry) == name,
          );
          expect(retained.posixMode, member.posixMode);
          expect(retained.modified, member.modified);
          for (final key in [
            'tar.uid',
            'tar.gid',
            'tar.uname',
            'tar.gname',
            'tar.gnuAtime',
            'tar.gnuCtime',
          ]) {
            expect(
              after.attributes[name]?[key],
              before.attributes[name]?[key],
              reason: '$name $key',
            );
          }
          final oldPax = before.attributes[name]?['tar.pax'] as Map?;
          final newPax = after.attributes[name]?['tar.pax'] as Map?;
          for (final key in ['mtime', 'atime', 'ctime']) {
            expect(newPax?[key], oldPax?[key], reason: '$name $key');
          }
          if (member.isFile) {
            expect(
              await afterReader.readMember(retained),
              await beforeReader.readMember(member),
            );
          }
        }
      },
    );
  }

  for (final kind in ['cpio', 'xar', 'odc', 'binary-le', 'binary-be']) {
    test('$kind grouped moves preserve inspected IDs and metadata', () async {
      final format = kind == 'xar' ? 'xar' : 'cpio';
      final reference = switch (kind) {
        'cpio' => referenceNewc(),
        'xar' => referenceXar(),
        _ => await File(
          'test/fixtures/archives/reference-$kind.cpio',
        ).readAsBytes(),
      };
      // The historical XAR fixture includes 20 unrelated trailing bytes. Use
      // its exact independent TOC/heap slice, as in package writer acceptance.
      final bytes = kind == 'xar'
          ? Uint8List.sublistView(reference, 0, reference.length - 20)
          : reference;
      final beforeReader = await openViewerArchive(
        bytes,
        name: 'archive.$format',
      );
      addTearDown(beforeReader.close);
      final before = await inspectPackageRewrite(bytes, format, beforeReader);
      expect(before.supported, isTrue, reason: before.reason);
      final workspace = await open(bytes, name: 'archive.$format');
      final roots = workspace.list().map((file) => file.path!).toList();
      workspace.createDirectory('/moved');
      workspace.moveMembers(roots, '/moved');
      await workspace.save();
      final afterReader = await published('archive.$format');
      final after = await inspectPackageRewrite(
        backend.files['/out/archive.$format']!,
        format,
        afterReader,
      );
      expect(after.supported, isTrue, reason: after.reason);
      for (final member in beforeReader.members) {
        final name = _name(member);
        final retained = afterReader.members.firstWhere(
          (entry) => _name(entry) == 'moved/$name',
        );
        expect(retained.posixMode, member.posixMode);
        expect(retained.modified, member.modified);
        expect(
          _retainedMetadata(after.attributes['moved/$name']!),
          _retainedMetadata(before.attributes[name]!),
        );
        expect(
          after.attributes['moved/$name']!['package.sourcePath'],
          'moved/$name',
        );
        if (format == 'cpio') {
          expect(
            after.attributes['moved/$name']!['cpio.storedPath'],
            'moved/$name',
          );
        }
        if (member.isFile) {
          expect(
            await afterReader.readMember(retained),
            await beforeReader.readMember(member),
          );
        }
      }
      workspace.moveMembers(roots.map((path) => '/moved$path').toList(), '/');
      await workspace.save();
      final twiceReader = await published('archive.$format');
      final twice = await inspectPackageRewrite(
        backend.files['/out/archive.$format']!,
        format,
        twiceReader,
      );
      for (final member in beforeReader.members) {
        expect(
          _retainedMetadata(twice.attributes[_name(member)]!),
          _retainedMetadata(before.attributes[_name(member)]!),
        );
      }
    });
  }

  for (final kind in ['gzip', 'ar', 'deb', 'read-only']) {
    test('$kind profile refuses grouped member moves', () async {
      final (name, bytes) = switch (kind) {
        'gzip' => (
          'data.gz',
          Uint8List.fromList(const codec.GZipEncoder().encode([1])),
        ),
        'ar' => (
          'files.ar',
          arFixture([
            const PackageFixtureEntry('a.txt', [1]),
          ]),
        ),
        'deb' => ('package.deb', debianFixture().archive),
        _ => (
          'files.zip',
          _zip({
            'a.txt': [1],
          }),
        ),
      };
      final workspace = await open(bytes, name: name);
      if (kind == 'read-only') backend.publicationSupported = false;
      expect(workspace.canMoveMembers, isFalse);
      final revision = workspace.revision;
      expect(
        () => workspace.moveMembers([workspace.list().first.path!], '/'),
        throwsUnsupportedError,
      );
      expect(workspace.revision, revision);
      expect(workspace.dirty, isFalse);
      expect(backend.mutations, isEmpty);
    });
  }

  test(
    'nested Debian payloads cannot use grouped moves to bypass package policy',
    () async {
      final workspace = await open(
        debianFixture().archive,
        name: 'package.deb',
        nested: ['data.tar.gz'],
      );
      expect(workspace.canMoveMembers, isFalse);
      expect(
        () => workspace.moveMembers(['/usr/share/crisp/data.txt'], '/'),
        throwsUnsupportedError,
      );
      expect(backend.mutations, isEmpty);
    },
  );
}
