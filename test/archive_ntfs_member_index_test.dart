// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_member_index.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:flutter_test/flutter_test.dart';

ViewerArchiveMember _member(
  String name,
  int index, {
  bool special = false,
  bool escaped = false,
  bool file = true,
}) => ViewerArchiveMember(
  name: name,
  index: index,
  size: 0,
  isFile: file,
  isEncrypted: false,
  isSpecial: special,
  pathEscapedRoot: escaped,
);

ViewerArchive _archive(String format, List<ViewerArchiveMember> members) =>
    ViewerArchive.reader(
      formatName: format,
      members: members,
      read: (_, limit) async => Uint8List(0),
      close: () async {},
    );

void main() {
  for (final format in ['ntfs']) {
    test(
      '$format retains special metadata only outside the selectable index',
      () async {
        final archive = _archive(format, [
          _member('folder/regular.txt', 0),
          _member('folder/link', 1, special: true),
          _member('pipe', 2, special: true),
        ]);
        final index = ArchiveMemberIndex(archive);
        expect(index.members.keys, ['folder/regular.txt']);
        expect(index.list('').map((item) => item.name), ['folder']);
        expect(index.list('folder').map((item) => item.name), ['regular.txt']);
        expect(
          () => index.file('folder/link'),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(
          archive.members.where((member) => member.isSpecial),
          hasLength(2),
        );
        await expectLater(
          archive.readMember(archive.members[1]),
          throwsA(isA<ArchiveViewException>()),
        );
        await archive.close();
      },
    );

    for (final entries in [
      [_member('same', 0, special: true), _member('same', 1)],
      [_member('link', 0, special: true), _member('link/file', 1)],
      [_member('../escape', 0, special: true)],
      [_member('clean-name', 0, special: true, escaped: true)],
      [_member('directory', 0, special: true, file: false)],
    ]) {
      test(
        '$format validates all paths before omitting ${entries.first.name}',
        () {
          final archive = _archive(format, entries);
          expect(
            () => ArchiveMemberIndex(archive),
            throwsA(isA<ArchiveViewException>()),
          );
        },
      );
    }
  }

  test('ordinary archives retain strict special-entry rejection', () {
    for (final format in ['zip', 'tar', 'udf', 'hfs', 'fat']) {
      final archive = _archive(format, [_member('link', 0, special: true)]);
      expect(
        () => ArchiveMemberIndex(archive),
        throwsA(isA<ArchiveViewException>()),
        reason: format,
      );
    }
  });
}
