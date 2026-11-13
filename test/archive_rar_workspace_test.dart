import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_rar_stored_format.dart';
import 'package:crisp_cloud/services/archive_rar_stored_reader.dart';
import 'package:crisp_cloud/services/archive_rar_stored_writer.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_endpoint_backend.dart';

final _modified = DateTime.utc(2026, 11, 13, 1, 2, 3, 123, 456);

List<RarStoredTimes> _times() => [
  RarStoredTimes(
    0x1f,
    {
      'mtime': BigInt.from(_modified.microsecondsSinceEpoch ~/ 1000000),
      'ctime': BigInt.from(1700000000),
      'atime': BigInt.from(1800000000),
    },
    {'mtime': 123456789, 'ctime': 987654321, 'atime': 100000001},
  ),
  RarStoredTimes(0xe, {
    'mtime':
        BigInt.from(_modified.microsecondsSinceEpoch) * BigInt.from(10) +
        BigInt.from(116444736000000007),
    'ctime': BigInt.from(130000000000000003),
    'atime': BigInt.from(130000000000000009),
  }, const {}),
];

Future<Uint8List> _storedRar(RarStoredTimes times) => collectArchiveWrite(
  (sink) => writeStoredRarArchive(
    [
      ArchiveWriteEntry(
        path: 'folder/original.txt',
        isDirectory: false,
        size: 3,
        modified: times.modified,
        mode: 0x1a4,
        attributes: {
          'rar5.hostOs': 1,
          'rar5.attributes': 0x81a4,
          'rar5.compression': 0,
          'rar5.hasCrc': true,
          'rar5.trailingSlash': false,
          'rar5.headerMtime': _modified.microsecondsSinceEpoch ~/ 1000000,
          'rar5.times': times.toAttributes(),
        },
        readChunks: () => Stream.value([1, 2, 3]),
      ),
    ],
    sink: sink,
    maxOutputBytes: 1024 * 1024,
  ),
);

Uint8List _zip(String path, Uint8List bytes) {
  final archive = codecs.Archive()
    ..addFile(codecs.ArchiveFile.bytes(path, bytes));
  return Uint8List.fromList(codecs.ZipEncoder().encode(archive));
}

ArchivePublicationJournal _journal() =>
    ArchivePublicationJournal(storage: MemoryFileCollectionStorage());

Future<void> _expectExactTimes(Uint8List bytes, RarStoredTimes times) async {
  final source = koni.MemoryByteSource(bytes);
  try {
    final inspection = await inspectStoredRarRewriteSource(source);
    expect(inspection.supported, isTrue);
    expect(
      inspection.attributes['folder/renamed.txt']!['rar5.times'],
      times.toAttributes(),
    );
    expect(
      inspection.attributes['folder/renamed.txt']!['rar5.headerMtime'],
      _modified.microsecondsSinceEpoch ~/ 1000000,
    );
  } finally {
    await source.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final extension in ['rar', 'cbr']) {
    for (final times in _times()) {
      test(
        'buffered $extension preserves exact time record ${times.flags} through rename, review, save and reopen',
        () async {
          final path = '/out/work.$extension';
          final original = await _storedRar(times);
          final backend = ArchiveEndpointTestBackend()..put(path, original);
          final journal = _journal();
          final workspace = await ArchiveWorkspace.open(
            backend,
            (await backend.stat(path))!,
            journal: journal,
          );
          addTearDown(workspace.close);
          expect(workspace.supportsLargeFiles, isFalse);
          expect(workspace.canUpdate, isTrue);
          expect(workspace.list('/folder').single.updatedAt, times.modified);
          workspace.rename('/folder/original.txt', 'folder/renamed.txt');
          final review = await workspace.review();
          expect(review.spool, isNull);
          await _expectExactTimes(review.bytes, times);
          expect(backend.files[path], original);
          expect(backend.mutations, isEmpty);
          await workspace.save(reviewed: review);
          expect(workspace.dirty, isFalse);
          await _expectExactTimes(backend.files[path]!, times);
          final reopened = await ArchiveWorkspace.open(
            backend,
            (await backend.stat(path))!,
            journal: journal,
          );
          addTearDown(reopened.close);
          expect(reopened.list('/folder').single.updatedAt, times.modified);
          expect(await reopened.read('/folder/renamed.txt'), [1, 2, 3]);
        },
      );
    }

    test(
      'nested $extension retains submicrosecond metadata on outer publication',
      () async {
        final times = _times().first;
        final innerPath = 'nested/inside.$extension';
        final original = _zip(innerPath, await _storedRar(times));
        final backend = ArchiveEndpointTestBackend()
          ..put('/out/outer.zip', original);
        final journal = _journal();
        final workspace = await ArchiveWorkspace.openNested(
          backend,
          (await backend.stat('/out/outer.zip'))!,
          [innerPath],
          journal: journal,
        );
        addTearDown(workspace.close);
        expect(workspace.canUpdate, isTrue);
        expect(workspace.supportsLargeFiles, isFalse);
        expect(workspace.list('/folder').single.updatedAt, times.modified);
        workspace.rename('/folder/original.txt', 'folder/renamed.txt');
        final review = await workspace.review();
        await _expectExactTimes(review.bytes, times);
        expect(backend.files['/out/outer.zip'], original);
        await workspace.save(reviewed: review);
        final outer = await openViewerArchive(
          backend.files['/out/outer.zip']!,
          name: 'outer.zip',
        );
        try {
          await _expectExactTimes(
            await outer.readMember(outer.members.single),
            times,
          );
        } finally {
          await outer.close();
        }
        final reopened = await ArchiveWorkspace.openNested(
          backend,
          (await backend.stat('/out/outer.zip'))!,
          [innerPath],
          journal: journal,
        );
        addTearDown(reopened.close);
        expect(reopened.list('/folder').single.updatedAt, times.modified);
        expect(await reopened.read('/folder/renamed.txt'), [1, 2, 3]);
      },
    );
  }

  for (final protected in [false, true]) {
    test(
      'buffered unsupported RAR fallback remains read-only, encrypted=$protected',
      () async {
        final original = await File(
          'test/fixtures/archives/${protected ? 'encrypted' : 'sample'}.rar',
        ).readAsBytes();
        final path = protected ? '/out/protected.rar' : '/out/legacy.cbr';
        final backend = ArchiveEndpointTestBackend()..put(path, original);
        final journal = _journal();
        final workspace = await ArchiveWorkspace.open(
          backend,
          (await backend.stat(path))!,
          password: protected ? 'secret' : null,
          journal: journal,
        );
        addTearDown(workspace.close);
        expect(workspace.format, 'rar');
        expect(workspace.canUpdate, isFalse);
        final member = protected ? 'hello.txt' : 'grad.bmp';
        final payload = await workspace.read('/$member');
        if (protected) {
          expect(utf8.decode(payload), 'hello, rar!\n');
        } else {
          expect(payload.length, 27702);
          expect(payload.sublist(0, 2), [0x42, 0x4d]);
        }
        expect(
          () => workspace.rename('/$member', 'renamed.txt'),
          throwsUnsupportedError,
        );
        await expectLater(workspace.review(), throwsUnsupportedError);
        expect(backend.files[path], original);
        expect(backend.mutations, isEmpty);
        expect(journal.records, isEmpty);
      },
    );
  }

  test('misnamed CBR fallback cannot become writable and corrupt Store headers fail closed', () async {
    final mislabeled = _zip('inside.txt', Uint8List.fromList([4, 5]));
    final corrupt = await _storedRar(_times().first)
      ..[8] ^= 1;
    final backend = ArchiveEndpointTestBackend()
      ..put('/out/misnamed.cbr', mislabeled)
      ..put('/out/corrupt.rar', corrupt);
    final workspace = await ArchiveWorkspace.open(
      backend,
      (await backend.stat('/out/misnamed.cbr'))!,
      journal: _journal(),
    );
    addTearDown(workspace.close);
    expect(workspace.format, 'zip');
    expect(workspace.canUpdate, isFalse);
    expect(await workspace.read('/inside.txt'), [4, 5]);
    await expectLater(
      ArchiveWorkspace.open(
        backend,
        (await backend.stat('/out/corrupt.rar'))!,
        journal: _journal(),
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(backend.mutations, isEmpty);
  });
}
