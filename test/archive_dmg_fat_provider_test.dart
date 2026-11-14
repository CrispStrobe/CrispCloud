// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
// Original source-ownership and failure-propagation tests. FAT bytes retain
// the separate independent reference corpus attribution.

import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_dmg_reader.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_fat_reference_data.dart';
import 'support/dmg_fixture.dart';
import 'support/hfs_fixture.dart';

typedef _Open = Future<ViewerArchive> Function(
  koni.ByteSource source, {
  bool Function()? isCancelled,
});

Future<ViewerArchive> _direct(
  koni.ByteSource source, {
  bool Function()? isCancelled,
}) => openDmgArchive(
  source,
  maxMemberBytes: kArchiveReadLimit,
  isCancelled: isCancelled,
);

Future<ViewerArchive> _viewer(
  koni.ByteSource source, {
  bool Function()? isCancelled,
}) => openViewerArchiveSource(
  source,
  name: 'reference.dmg',
  isCancelled: isCancelled,
);

bool _fatTableRequest(int offset, int count) => offset == 512 && count > 512;

Object _failure(bool archiveShaped) => archiveShaped
    ? const ArchiveViewException(
        'The original provider failure.',
        code: ArchiveMessageCode.unsupported,
      )
    : StateError('The original provider failure.');

void main() {
  late Uint8List validDmg;
  setUpAll(() {
    validDmg = DmgFixture(
      fatReferenceBytes('fat12'),
      method: 1,
      chunkBytes: 32768,
    ).bytes;
  });

  for (final route in <(String, _Open)>[
    ('direct DMG', _direct),
    ('public viewer', _viewer),
  ]) {
    group(route.$1, () {
      for (final archiveShaped in [false, true]) {
        final kind = archiveShaped ? 'ArchiveViewException' : 'StateError';
        for (final throwingClose in [false, true]) {
          final cleanup = throwingClose ? 'throwing cleanup' : 'normal cleanup';

          test(
            '$kind from FAT table I/O survives $cleanup unchanged',
            () async {
              final error = _failure(archiveShaped);
              final source = _CountedSource(validDmg)
                ..readFailure = error
                ..failRead = _fatTableRequest;
              if (throwingClose) {
                source.closeFailure = StateError(
                  'Cleanup must not replace I/O.',
                );
              }
              await expectLater(route.$2(source), throwsA(same(error)));
              expect(source.failedReads, 1);
              expect(
                source.reads.any((read) => _fatTableRequest(read.$1, read.$2)),
                isTrue,
              );
              expect(source.closeAttempts, 1);
              expect(source.closed, isTrue);
            },
          );

          test(
            '$kind from cancellation callback survives $cleanup unchanged',
            () async {
              final error = _failure(archiveShaped);
              final source = _CountedSource(validDmg);
              var tableReturned = false;
              var throwingChecks = 0;
              source.afterRead = (offset, count) {
                if (_fatTableRequest(offset, count)) tableReturned = true;
              };
              if (throwingClose) {
                source.closeFailure = StateError(
                  'Cleanup must not replace the callback.',
                );
              }
              await expectLater(
                route.$2(
                  source,
                  isCancelled: () {
                    if (tableReturned) {
                      throwingChecks++;
                      throw error;
                    }
                    return false;
                  },
                ),
                throwsA(same(error)),
              );
              expect(tableReturned, isTrue);
              expect(throwingChecks, greaterThanOrEqualTo(1));
              expect(source.failedReads, 0);
              expect(source.closeAttempts, 1);
              expect(source.closed, isTrue);
            },
          );
        }

        test(
          '$kind from HFS catalog I/O also preserves the provider identity',
          () async {
            final fixture = DmgFixture(
              HfsFixture().bytes,
              method: 1,
              chunkBytes: 32768,
            );
            final error = _failure(archiveShaped);
            final source = _CountedSource(fixture.bytes)
              ..readFailure = error
              ..failRead = (offset, count) =>
                  offset == HfsFixture.catalogOffset &&
                  count >= HfsFixture.nodeSize;
            await expectLater(route.$2(source), throwsA(same(error)));
            expect(source.failedReads, 1);
            expect(source.closeAttempts, 1);
            expect(source.closed, isTrue);
          },
        );
      }

      test(
        'an original UDIF parse error survives throwing source cleanup',
        () async {
          final bytes = Uint8List.fromList(validDmg);
          final trailer = ByteData.sublistView(bytes, bytes.length - 512);
          trailer.setUint32(
            4,
            3,
          ); // Invalid UDIF version; the koly signature stays valid.
          final cleanup = StateError(
            'This cleanup error must not mask UDIF metadata.',
          );
          final source = _CountedSource(bytes)..closeFailure = cleanup;
          await expectLater(
            route.$2(source),
            throwsA(
              isA<ArchiveViewException>().having(
                (error) => error.message,
                'original parse message',
                contains('Unsupported UDIF version or trailer size'),
              ),
            ),
          );
          expect(source.failedReads, 0);
          expect(source.closeAttempts, 1);
          expect(source.closed, isTrue);
        },
      );

      test('successful close suppresses cleanup failure once and remains closed', () async {
        final source = _CountedSource(validDmg)
          ..closeFailure = StateError('Backing source failed while closing.');
        final archive = await route.$2(source);
        final file = archive.members.firstWhere(
          (member) => member.isFile && member.name.endsWith('/HELLO.TXT'),
        );
        expect(await archive.readMember(file), isNotEmpty);
        final reads = source.reads.length;
        // ViewerArchive's established public contract suppresses cleanup
        // errors. A source failure must still complete ownership exactly once.
        await expectLater(archive.close(), completes);
        await expectLater(archive.close(), completes);
        expect(archive.isClosed, isTrue);
        expect(source.closeAttempts, 1);
        expect(source.closed, isTrue);
        await expectLater(
          archive.readMember(file),
          throwsA(
            isA<ArchiveViewException>().having(
              (error) => error.code,
              'code',
              ArchiveMessageCode.closed,
            ),
          ),
        );
        expect(source.reads.length, reads);
      });
    });
  }
}

class _CountedSource implements koni.ByteSource {
  _CountedSource(this.bytes);

  final Uint8List bytes;
  final reads = <(int, int)>[];
  Object? readFailure;
  Object? closeFailure;
  bool Function(int offset, int count)? failRead;
  void Function(int offset, int count)? afterRead;
  int failedReads = 0;
  int closeAttempts = 0;
  bool closed = false;

  @override
  String get name => 'reference.dmg';
  @override
  int get length => bytes.length;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (closed) throw StateError('Read after source ownership ended.');
    if (offset < 0 || count < 0 || offset > length || count > length - offset) {
      throw RangeError('Counted source read leaves its bounds.');
    }
    reads.add((offset, count));
    if (readFailure != null && (failRead?.call(offset, count) ?? true)) {
      failedReads++;
      throw readFailure!;
    }
    final result = Uint8List.fromList(bytes.sublist(offset, offset + count));
    afterRead?.call(offset, count);
    return result;
  }

  @override
  Future<void> close() async {
    closeAttempts++;
    closed = true;
    if (closeFailure != null) throw closeFailure!;
  }
}
