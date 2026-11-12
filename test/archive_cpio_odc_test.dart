import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_package_readers.dart';
import 'package:crisp_cloud/services/archive_package_writers.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_package_fixtures.dart';

Uint8List odcFixture(List<PackageFixtureEntry> entries, {bool trailer = true}) {
  final output = BytesBuilder();
  var inode = 1;
  for (final entry in [
    ...entries,
    if (trailer) const PackageFixtureEntry('TRAILER!!!', [], mode: 0),
  ]) {
    final name = [...utf8.encode(entry.name), 0];
    final fields = <(int, int)>[
      (0, 6),
      (inode++, 6),
      (entry.mode, 6),
      (123, 6),
      (456, 6),
      (entry.links, 6),
      (0, 6),
      (1700000000, 11),
      (name.length, 6),
      (entry.bytes.length, 11),
    ];
    output.add(ascii.encode('070707'));
    for (final field in fields) {
      output.add(
        ascii.encode(field.$1.toRadixString(8).padLeft(field.$2, '0')),
      );
    }
    output.add(name);
    output.add(entry.bytes);
  }
  return output.takeBytes();
}

Future<ViewerArchive> _open(Uint8List bytes, {int limit = kArchiveReadLimit}) =>
    openCpioArchive(koni.MemoryByteSource(bytes), maxMemberBytes: limit);

void main() {
  test('reads independent libarchive odc without adding alignment', () async {
    final bytes = File('test/fixtures/archives/reference-odc.cpio')
        .readAsBytesSync();
    final archive = await _open(bytes);
    addTearDown(archive.close);
    final member = archive.members.singleWhere(
      (m) => m.name == 'docs/hello.txt',
    );
    expect(
      utf8.decode(await archive.readMember(member)),
      'Independent portable CPIO fixture\n',
    );
    expect(member.posixMode, 0x81a0);
    expect(member.modified, DateTime.utc(2023, 11, 14, 22, 13, 20));
    for (final file in archive.members.where((m) => m.isFile)) {
      expect((await archive.readMember(file)).length, file.size);
    }
  });

  test('reads odd-sized and UTF-8 names without newc padding', () async {
    final archive = await _open(
      odcFixture([
        const PackageFixtureEntry('.', [], mode: 0x41ed),
        const PackageFixtureEntry('a', [1, 2, 3]),
        const PackageFixtureEntry('日本語/é.txt', [4, 5]),
        const PackageFixtureEntry('empty', []),
      ]),
    );
    addTearDown(archive.close);
    expect(archive.members.map((m) => m.name), ['a', '日本語/é.txt', 'empty']);
    expect(await archive.readMember(archive.members[0]), [1, 2, 3]);
    expect(await archive.readMember(archive.members[1]), [4, 5]);
    expect(await archive.readMember(archive.members[2]), isEmpty);
  });

  test('inspects odc as its own preserved rewrite profile', () async {
    final bytes = odcFixture([
      const PackageFixtureEntry('a', [1]),
    ]);
    final archive = await _open(bytes);
    addTearDown(archive.close);
    final inspection = await inspectPackageRewrite(bytes, 'cpio', archive);
    expect(inspection.supported, isTrue);
    expect(inspection.container['cpio.variant'], '070707');
  });

  test(
    'lists unsafe names, links and devices but refuses reading them',
    () async {
      final archive = await _open(
        odcFixture([
          const PackageFixtureEntry('../outside', [1]),
          const PackageFixtureEntry('/absolute', [1]),
          const PackageFixtureEntry(r'C:\outside', [1]),
          const PackageFixtureEntry('link', [1], mode: 0xa1ff),
          const PackageFixtureEntry('hardlink', [1], links: 2),
          const PackageFixtureEntry('device', [], mode: 0x21a4),
        ]),
      );
      addTearDown(archive.close);
      expect(archive.members.take(3).every((m) => m.pathEscapedRoot), isTrue);
      expect(archive.members.skip(3).every((m) => m.isSpecial), isTrue);
      for (final member in archive.members) {
        await expectLater(
          archive.readMember(member),
          throwsA(isA<ArchiveViewException>()),
        );
      }
    },
  );

  test('enforces requested and configured read limits', () async {
    final archive = await _open(
      odcFixture([
        const PackageFixtureEntry('a', [1, 2, 3]),
      ]),
      limit: 2,
    );
    addTearDown(archive.close);
    await expectLater(
      archive.readMember(archive.members.single),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  final mutations = <String, Uint8List Function(Uint8List)>{
    'octal field containing 8': (b) => b..[6] = 56,
    'missing name terminator': (b) => b..[77] = 65,
    'zero name size': (b) => b..setRange(59, 65, ascii.encode('000000')),
    'oversized name': (b) => b..setRange(59, 65, ascii.encode('777777')),
    'payload outside source': (b) =>
        b..setRange(65, 76, ascii.encode('77777777777')),
    'directory with payload': (b) =>
        b..setRange(18, 24, ascii.encode('040755')),
    'truncated header': (b) => Uint8List.sublistView(b, 0, 75),
    'truncated trailer': (b) => Uint8List.sublistView(b, 0, b.length - 1),
    'non-padding trailing data': (b) => Uint8List.fromList([...b, 1]),
    'concatenated archives': (b) => Uint8List.fromList([...b, ...b]),
  };
  for (final mutation in mutations.entries) {
    test('rejects ${mutation.key}', () async {
      await expectLater(
        _open(
          mutation.value(
            odcFixture([
              const PackageFixtureEntry('a', [1, 2, 3]),
            ]),
          ),
        ),
        throwsA(isA<ArchiveViewException>()),
      );
    });
  }

  test('requires trailer and accepts bounded zero padding', () async {
    await expectLater(
      _open(
        odcFixture([
          const PackageFixtureEntry('a', [1]),
        ], trailer: false),
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    final archive = await _open(
      Uint8List.fromList([...odcFixture([]), ...List.filled(511, 0)]),
    );
    addTearDown(archive.close);
    expect(archive.members, isEmpty);
  });
}
