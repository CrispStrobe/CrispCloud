import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/archive_integrity_service.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';

ViewerArchiveMember _member(
  String name,
  int size,
  int index, {
  bool directory = false,
  bool special = false,
  bool unsafe = false,
  bool encrypted = false,
}) => ViewerArchiveMember(
  name: name,
  size: size,
  index: index,
  isFile: !directory,
  isSpecial: special,
  isEncrypted: encrypted,
  pathEscapedRoot: unsafe,
);

ViewerArchive _fake(
  List<ViewerArchiveMember> members, {
  Future<Uint8List> Function(ViewerArchiveMember, int)? read,
  Stream<List<int>> Function(ViewerArchiveMember, int)? stream,
}) => ViewerArchive.reader(
  formatName: 'test',
  members: members,
  notices: const ['The format has no publisher signature verification.'],
  read: read ?? (member, _) async => Uint8List(member.size),
  streamReader: stream,
  close: () async {},
);

void main() {
  test(
    'hashes an independent member stream without retaining content',
    () async {
      final data = utf8.encode('archive test payload');
      var bufferedReads = 0;
      final archive = _fake(
        [
          _member('nested/file.txt', data.length, 0),
          _member('empty/', 0, 1, directory: true),
        ],
        read: (_, _) async {
          bufferedReads++;
          throw StateError('Use the streaming callback.');
        },
        stream: (_, _) async* {
          yield data.sublist(0, 4);
          yield data.sublist(4);
        },
      );
      final progress = <ArchiveIntegrityProgress>[];
      final report = await checkArchiveIntegrity(
        archive,
        onProgress: progress.add,
      );
      expect(report.allRegularMembersChecked, isTrue);
      expect(report.checkedCount, 1);
      expect(report.directoryCount, 1);
      expect(report.bytesRead, data.length);
      expect(report.entries.first.sha256, sha256.convert(data).toString());
      expect(report.notices, archive.notices);
      expect(progress.last.completedEntries, 2);
      expect(progress.any((p) => p.memberName == 'nested/file.txt'), isTrue);
      expect(bufferedReads, 0);
      expect(archive.isClosed, isFalse, reason: 'the caller owns the reader');
    },
  );

  test('checks real ZIP payloads and empty members', () async {
    final bytes = ar.ZipEncoder().encode(
      ar.Archive()
        ..addFile(ar.ArchiveFile('hello.txt', 5, utf8.encode('hello')))
        ..addFile(ar.ArchiveFile('empty.txt', 0, <int>[])),
    );
    final archive = await openViewerArchive(
      Uint8List.fromList(bytes),
      name: 'test.zip',
    );
    addTearDown(archive.close);
    final report = await checkArchiveIntegrity(archive);
    expect(report.checkedCount, 2);
    expect(report.allRegularMembersChecked, isTrue);
    expect(report.entries.last.sha256, sha256.convert([]).toString());
  });

  test('payload failure does not hide later readable members', () async {
    final archive = _fake(
      [_member('bad', 4, 0), _member('good', 3, 1)],
      read: (member, _) async {
        if (member.index == 0) {
          throw const ArchiveViewException('CRC mismatch.');
        }
        return Uint8List.fromList([1, 2, 3]);
      },
    );
    final report = await checkArchiveIntegrity(archive);
    expect(report.failedCount, 1);
    expect(report.checkedCount, 1);
    expect(report.entries.first.detail, contains('CRC mismatch'));
    expect(report.entries.first.sha256, isNull);
    expect(report.allRegularMembersChecked, isFalse);
  });

  for (final actual in [2, 4]) {
    test('rejects streamed member length $actual against declared 3', () async {
      final archive = _fake(
        [_member('length', 3, 0)],
        stream: (_, _) async* {
          yield List.filled(actual, 7);
        },
      );
      final report = await checkArchiveIntegrity(archive);
      expect(report.failedCount, 1);
      expect(report.entries.single.sha256, isNull);
    });
  }

  test('unsafe and special entries are reported without reads', () async {
    var reads = 0;
    final archive = _fake(
      [
        _member('escape', 1, 0, unsafe: true),
        _member('link', 1, 1, special: true),
      ],
      read: (_, _) async {
        reads++;
        return Uint8List(1);
      },
    );
    final report = await checkArchiveIntegrity(archive);
    expect(reads, 0);
    expect(report.skippedCount, 2);
    expect(report.namespaceIssue, isNotNull);
    expect(report.entries.map((e) => e.skipReason), [
      ArchiveIntegritySkipReason.unsafePath,
      ArchiveIntegritySkipReason.specialEntry,
    ]);
  });

  test('duplicate and file-directory namespaces cannot pass', () async {
    for (final members in [
      [_member('same', 0, 0), _member('same', 0, 1)],
      [_member('parent', 0, 0), _member('parent/child', 0, 1)],
    ]) {
      final report = await checkArchiveIntegrity(_fake(members));
      expect(report.checkedCount, 2);
      expect(report.namespaceIssue, isNotNull);
      expect(report.allRegularMembersChecked, isFalse);
    }
  });

  test('per-member and cumulative work limits are explicit', () async {
    final readNames = <String>[];
    final archive = _fake(
      [
        _member('too-large', 11, 0),
        _member('first', 6, 1),
        _member('over-total', 5, 2),
        _member('fits', 4, 3),
      ],
      read: (member, _) async {
        readNames.add(member.name);
        return Uint8List(member.size);
      },
    );
    final report = await checkArchiveIntegrity(
      archive,
      maxMemberBytes: 10,
      maxTotalBytes: 10,
    );
    expect(readNames, ['first', 'fits']);
    expect(report.bytesRead, 10);
    expect(
      report.entries[0].skipReason,
      ArchiveIntegritySkipReason.memberLimit,
    );
    expect(report.entries[2].skipReason, ArchiveIntegritySkipReason.totalLimit);
    expect(report.skippedCount, 2);
    expect(report.allRegularMembersChecked, isFalse);
  });

  test(
    'deep and long names cannot trigger unbounded namespace expansion',
    () async {
      for (final name in [
        List.filled(30000, 'a').join('/'),
        List.filled(1500, '日').join(),
        List.filled(201, 'a').join('/'),
      ]) {
        final report = await checkArchiveIntegrity(
          _fake([_member(name, 0, 0)]),
        );
        expect(report.namespaceIssue, contains('namespace limits'));
        expect(report.checkedCount, 1);
        expect(report.allRegularMembersChecked, isFalse);
      }
    },
  );

  test('failed reads still consume the declared work budget', () async {
    final archive = _fake([
      _member('bad', 6, 0),
      _member('over-total', 6, 1),
    ], read: (_, _) async => throw const ArchiveViewException('Bad payload.'));
    final report = await checkArchiveIntegrity(archive, maxTotalBytes: 10);
    expect(report.failedCount, 1);
    expect(
      report.entries.last.skipReason,
      ArchiveIntegritySkipReason.totalLimit,
    );
  });

  for (final wrong in [false, true]) {
    test('distinguishes required and rejected passwords ($wrong)', () async {
      final archive = _fake(
        [_member('secret', 1, 0, encrypted: true)],
        read: (_, _) async => throw ArchivePasswordRequiredException(
          'Unlock member.',
          wrongPassword: wrong,
        ),
      );
      final report = await checkArchiveIntegrity(archive);
      expect(report.failedCount, wrong ? 1 : 0);
      expect(report.skippedCount, wrong ? 0 : 1);
      expect(report.allRegularMembersChecked, isFalse);
    });
  }

  test('an already unlocked encrypted member is tested', () async {
    final archive = _fake([_member('secret', 1, 0, encrypted: true)]);
    expect((await checkArchiveIntegrity(archive)).checkedCount, 1);
  });

  test(
    'cancellation stops a stream and leaves no partial passing hash',
    () async {
      var cancelled = false, closed = false, secondRead = false;
      final archive = _fake(
        [_member('current', 6, 0), _member('next', 1, 1)],
        stream: (member, _) async* {
          if (member.index == 1) secondRead = true;
          try {
            yield [1, 2, 3];
            yield [4, 5, 6];
          } finally {
            closed = true;
          }
        },
      );
      final report = await checkArchiveIntegrity(
        archive,
        isCancelled: () => cancelled,
        onProgress: (progress) {
          if (progress.bytesRead > 0) cancelled = true;
        },
      );
      expect(closed, isTrue);
      expect(secondRead, isFalse);
      expect(report.stopReason, ArchiveIntegrityStopReason.cancelled);
      expect(report.checkedCount, 0);
      expect(report.unprocessedCount, 2);
      expect(report.bytesRead, 3);
    },
  );

  test('cancels before any read and yields between empty members', () async {
    var cancelled = false, reads = 0;
    final archive = _fake(
      List.generate(100, (i) => _member('empty$i', 0, i)),
      read: (_, _) async {
        reads++;
        return Uint8List(0);
      },
    );
    final result = checkArchiveIntegrity(archive, isCancelled: () => cancelled);
    Timer.run(() => cancelled = true);
    final report = await result;
    expect(report.stopReason, ArchiveIntegrityStopReason.cancelled);
    expect(reads, lessThan(100));
    expect(report.unprocessedCount, greaterThan(0));
  });

  test(
    'closed or stale handles produce incomplete reports without reads',
    () async {
      final archive = _fake([_member('member', 1, 0)]);
      expect(
        (await checkArchiveIntegrity(
          archive,
          isCurrent: () => false,
        )).stopReason,
        ArchiveIntegrityStopReason.unavailable,
      );
      await archive.close();
      final report = await checkArchiveIntegrity(archive);
      expect(report.stopReason, ArchiveIntegrityStopReason.unavailable);
      expect(report.unprocessedCount, 1);
      expect(report.failedCount, 0);
    },
  );

  test(
    'source invalidation during a read is not mistaken for corruption',
    () async {
      var current = true;
      final archive = _fake(
        [_member('file', 3, 0)],
        read: (_, _) async {
          current = false;
          throw StateError('Disconnected');
        },
      );
      final report = await checkArchiveIntegrity(
        archive,
        isCurrent: () => current,
      );
      expect(report.stopReason, ArchiveIntegrityStopReason.unavailable);
      expect(report.failedCount, 0);
      expect(report.checkedCount, 0);
    },
  );

  test(
    'empty and directory-only archives do not invent content checks',
    () async {
      for (final members in [
        <ViewerArchiveMember>[],
        [_member('empty/', 0, 0, directory: true)],
      ]) {
        final report = await checkArchiveIntegrity(_fake(members));
        expect(report.checkedCount, 0);
        expect(report.failedCount, 0);
        expect(report.allRegularMembersChecked, isTrue);
        expect(report.directoryCount, members.length);
      }
    },
  );

  test('rejects invalid limits and too many members before reading', () async {
    final archive = _fake([_member('first', 0, 0), _member('second', 0, 1)]);
    await expectLater(
      checkArchiveIntegrity(archive, maxEntries: 1),
      throwsA(isA<ArchiveViewException>()),
    );
    await expectLater(
      checkArchiveIntegrity(archive, maxMemberBytes: 0),
      throwsArgumentError,
    );
    await expectLater(
      checkArchiveIntegrity(archive, maxTotalBytes: 0),
      throwsArgumentError,
    );
  });
}
