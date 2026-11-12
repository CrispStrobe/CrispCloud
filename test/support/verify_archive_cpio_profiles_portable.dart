// Compile with `dart compile js` and execute with Node. Output hashes come from
// the original fresh fixtures accepted by native libarchive 3.7.4 through
// check_archive_cpio_profiles.py, independent of this JavaScript runtime.
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/archive_package_writers.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';

import 'archive_package_writer_fixtures.dart';

Future<void> main() async {
  final date = DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true);
  Map<String, Object?> attributes(int inode, {bool directory = false}) => {
    'cpio.dev': 0x1234,
    'cpio.rdev': 0x2345,
    'cpio.ino': inode,
    'cpio.uid': 123,
    'cpio.gid': 456,
    'cpio.nlink': directory ? 2 : 1,
  };
  final entries = [
    packageEntry(
      'docs',
      [],
      directory: true,
      mode: 0x1e8,
      modified: date,
      attributes: attributes(32768, directory: true),
    ),
    packageEntry(
      'docs/odd',
      [111, 100, 100],
      mode: 0x1a0,
      modified: date,
      attributes: attributes(32769),
    ),
    packageEntry('empty', [], modified: date, attributes: attributes(32770)),
    packageEntry(
      '日本語-é.txt',
      utf8.encode('Original UTF-8 payload\n'),
      modified: date,
      attributes: attributes(32771),
    ),
    packageEntry(
      'payload.bin',
      List.generate(65536 + 333, (i) => i % 251),
      modified: date,
      mode: 0x1ed,
      attributes: attributes(65535),
    ),
  ];
  const hashes = {
    ArchiveCpioFormat.odc:
        '61cea07ea722ec14e24dbe5f08e4e9e40613bad20c7c5cafbb881ba57b8ca555',
    ArchiveCpioFormat.binaryLittleEndian:
        '35d91c10e3d2e4d56bc4cce7908f21574492a0f1aa702f5b47d4f21aad4afa21',
    ArchiveCpioFormat.binaryBigEndian:
        '24f6f69dc70e64c1b99baa1f642abceb6def7b3c2a1e5a982296f517503fb9cf',
  };
  for (final profile in hashes.entries) {
    final bytes = await collectArchiveWrite(
      (sink) => writePackageArchive(
        'cpio',
        entries,
        cpioFormat: profile.key,
        sink: sink,
      ),
    );
    if (sha256.convert(bytes).toString() != profile.value) {
      throw StateError(
        'Portable output differs from native-verified ${profile.key.name}.',
      );
    }
    final opened = await PackageRewriteFixture.open(bytes, 'cpio');
    try {
      if (!opened.inspection.supported ||
          sha256.convert(await opened.repack()).toString() != profile.value) {
        throw StateError(
          'Portable inspected rewrite changed ${profile.key.name}.',
        );
      }
      final member = opened.archive.members.singleWhere(
        (entry) => entry.name == 'payload.bin',
      );
      final payload = await opened.archive.readMember(member);
      if (payload.length != 65869 ||
          payload.asMap().entries.any((e) => e.value != e.key % 251)) {
        throw StateError('Portable payload content differs.');
      }
    } finally {
      await opened.close();
    }
  }
  final high = await collectArchiveWrite(
    (sink) => writePackageArchive(
      'cpio',
      [
        packageEntry(
          'a',
          [1],
          modified: DateTime.fromMillisecondsSinceEpoch(
            0x1ffffffff * 1000,
            isUtc: true,
          ),
          attributes: {
            'cpio.ino': 0x3ffff,
            'cpio.dev': 0x3ffff,
            'cpio.rdev': 0x3ffff,
            'cpio.uid': 0x3ffff,
            'cpio.gid': 0x3ffff,
          },
        ),
      ],
      cpioFormat: ArchiveCpioFormat.odc,
      sink: sink,
    ),
  );
  final read = await openViewerArchive(high, name: 'high.cpio');
  try {
    if (read.members.single.modified!.millisecondsSinceEpoch !=
        0x1ffffffff * 1000) {
      throw StateError('Portable odc timestamp lost high bits.');
    }
  } finally {
    await read.close();
  }
  var refused = false;
  try {
    await collectArchiveWrite(
      (sink) => writePackageArchive(
        'cpio',
        [
          packageEntry('a', [1], attributes: {'cpio.uid': 0x10000}),
        ],
        cpioFormat: ArchiveCpioFormat.binaryLittleEndian,
        sink: sink,
      ),
    );
  } on ArchiveViewException {
    refused = true;
  }
  if (!refused) {
    throw StateError('Portable binary ownership overflow was ignored.');
  }
  print(
    'Portable CPIO profiles match all 3 native-verified outputs; rewrites, 33-bit odc time and overflow checks passed.',
  );
}
