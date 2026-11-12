// Produce original CPIO output for independent native validation:
// dart run test/support/emit_archive_cpio_profiles.dart <output-directory>
// python3 test/support/check_archive_cpio_profiles.py <output-directory>
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/archive_package_writers.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';

import 'archive_package_writer_fixtures.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError('Supply an output directory for native validation.');
  }
  final output = await Directory(arguments.single).create(recursive: true);
  final manifest = <Map<String, Object?>>[];
  final date = DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true);

  Future<Uint8List> write(
    ArchiveCpioFormat profile,
    List<ArchiveWriteEntry> entries, {
    ArchiveRewriteInspection? source,
  }) => collectArchiveWrite(
    (sink) => writePackageArchive(
      'cpio',
      entries,
      cpioFormat: profile,
      source: source,
      sink: sink,
    ),
  );

  Future<Map<String, Object?>> expected(ArchiveWriteEntry entry) async => {
    'path': entry.path,
    'size': entry.size,
    'mode':
        (entry.isDirectory ? 0x4000 : 0x8000) |
        ((entry.mode ?? (entry.isDirectory ? 0x1ed : 0x1a4)) & 0xfff),
    'uid': entry.attributes['cpio.uid'] ?? 0,
    'gid': entry.attributes['cpio.gid'] ?? 0,
    'dev': entry.attributes['cpio.dev'] ?? 0,
    'rdev': entry.attributes['cpio.rdev'] ?? 0,
    'ino': entry.attributes['cpio.ino'],
    'nlink': entry.attributes['cpio.nlink'] ?? (entry.isDirectory ? 2 : 1),
    'mtime': (entry.modified?.millisecondsSinceEpoch ?? 0) ~/ 1000,
    'sha256': sha256.convert(await entry.read()).toString(),
  };

  Future<void> save(String name, Uint8List bytes) async {
    await File('${output.path}/$name').writeAsBytes(bytes);
  }

  const profiles = {
    ArchiveCpioFormat.odc: ('odc', '070707', 'reference-odc.cpio'),
    ArchiveCpioFormat.binaryLittleEndian: (
      'binary-le',
      'binary-le',
      'reference-binary-le.cpio',
    ),
    ArchiveCpioFormat.binaryBigEndian: (
      'binary-be',
      'binary-be',
      'reference-binary-be.cpio',
    ),
  };
  for (final profile in profiles.entries) {
    final label = profile.value.$1;
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
    final freshName = 'fresh-$label.cpio';
    await save(freshName, await write(profile.key, entries));
    manifest.add({
      'file': freshName,
      'profile': profile.value.$2,
      'entries': [for (final entry in entries) await expected(entry)],
    });

    final source = File('test/fixtures/archives/${profile.value.$3}')
        .readAsBytesSync();
    final sourceName = 'source-$label.cpio';
    await save(sourceName, source);
    final fixture = await PackageRewriteFixture.open(source, 'cpio');
    try {
      if (!fixture.inspection.supported) {
        throw StateError(fixture.inspection.reason!);
      }
      final copyName = 'rewritten-$label.cpio';
      // An irrelevant fresh-creation preference must not convert an existing
      // archive's profile. Inspection remains authoritative.
      await save(
        copyName,
        await write(
          ArchiveCpioFormat.newc,
          fixture.entries,
          source: fixture.inspection,
        ),
      );
      manifest.add({
        'file': copyName,
        'profile': profile.value.$2,
        'source': sourceName,
        'identicalBytes': true,
      });

      final selected = fixture.entries.indexWhere(
        (entry) => !entry.isDirectory,
      );
      final changed = utf8.encode('Changed but preserved original metadata\n');
      final modified = [
        for (var i = 0; i < fixture.entries.length; i++)
          i == selected
              ? ArchiveWriteEntry(
                  path: 'renamed.txt',
                  isDirectory: false,
                  size: changed.length,
                  mode: fixture.entries[i].mode,
                  modified: fixture.entries[i].modified,
                  attributes: fixture.entries[i].attributes,
                  readChunks: () => Stream.value(changed),
                )
              : fixture.entries[i],
        packageEntry(
          'added.txt',
          [4, 3, 2, 1],
          modified: date,
          attributes: {'cpio.ino': 50000},
        ),
      ];
      final modifiedName = 'edited-$label.cpio';
      await save(
        modifiedName,
        await write(
          ArchiveCpioFormat.newc,
          modified,
          source: fixture.inspection,
        ),
      );
      manifest.add({
        'file': modifiedName,
        'profile': profile.value.$2,
        'entries': [for (final entry in modified) await expected(entry)],
      });
    } finally {
      await fixture.close();
    }
  }
  await File('${output.path}/manifest.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
  stdout.writeln('Emitted ${manifest.length} CPIO profile verification cases.');
}
