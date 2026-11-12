import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_package_readers.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_package_fixtures.dart';

typedef _Open = Future<ViewerArchive> Function(
  koni.ByteSource, {
  required int maxMemberBytes,
});

class _TrackedSource implements koni.ByteSource {
  _TrackedSource(this.bytes);
  final Uint8List bytes;
  final reads = <({int offset, int length})>[];
  var closes = 0;
  bool shortRead = false;
  @override
  String get name => 'fixture';
  @override
  int get length => bytes.length;
  @override
  Future<Uint8List> read(int offset, int length) async {
    if (closes != 0) throw StateError('Source is closed.');
    reads.add((offset: offset, length: length));
    return Uint8List.sublistView(
      bytes,
      offset,
      offset + length - (shortRead && length > 0 ? 1 : 0),
    );
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

Future<ViewerArchive> _open(
  _Open reader,
  Uint8List bytes, {
  int limit = 1024 * 1024,
}) => reader(koni.MemoryByteSource(bytes), maxMemberBytes: limit);

Future<void> _refused(_Open reader, Uint8List bytes) async {
  final source = _TrackedSource(bytes);
  await expectLater(
    reader(source, maxMemberBytes: 1024 * 1024),
    throwsA(isA<ArchiveViewException>()),
  );
  expect(source.closes, 1, reason: 'failed readers must release owned input');
}

void _replace(Uint8List bytes, int at, String text) =>
    bytes.setRange(at, at + text.length, ascii.encode(text));

void main() {
  group('AR / Debian packages', () {
    test('reads independent GNU ar long names and odd-byte padding', () async {
      final archive = await _open(openArArchive, referenceGnuAr());
      addTearDown(archive.close);
      expect(archive.formatName, 'ar');
      expect(archive.members.map((e) => e.name), [
        'a-very-long-file-name.txt',
        'short',
      ]);
      expect(
        utf8.decode(await archive.readMember(archive.members.first)),
        'GNU long name fixture\n',
      );
      expect(
        utf8.decode(await archive.readMember(archive.members.last)),
        'odd',
      );
    });

    test('reads Debian member layout and preserves content and mode', () async {
      final archive = await _open(
        openArArchive,
        arFixture([
          const PackageFixtureEntry('debian-binary', [50, 46, 48, 10]),
          const PackageFixtureEntry('control.tar.gz', [1, 2, 3]),
          const PackageFixtureEntry('data.tar.xz', [4, 5], mode: 0x81a0),
        ]),
      );
      addTearDown(archive.close);
      expect(archive.members.map((e) => e.name), [
        'debian-binary',
        'control.tar.gz',
        'data.tar.xz',
      ]);
      expect(await archive.readMember(archive.members.last), [4, 5]);
      expect(archive.members.last.posixMode, 0x81a0);
      expect(
        archive.members.last.modified,
        DateTime.utc(2023, 11, 14, 22, 13, 20),
      );
    });

    test('BSD inline UTF-8 names are not part of the payload', () async {
      final archive = await _open(
        openArArchive,
        arFixture([
          const PackageFixtureEntry('long/日本語.txt', [9, 8, 7]),
        ], bsdNames: true),
      );
      addTearDown(archive.close);
      expect(archive.members.single.name, 'long/日本語.txt');
      expect(archive.members.single.size, 3);
      expect(await archive.readMember(archive.members.single), [9, 8, 7]);
    });

    test('does not fetch file payloads until requested', () async {
      final source = _TrackedSource(
        arFixture([
          PackageFixtureEntry('large.bin', List.filled(256 * 1024, 42)),
        ]),
      );
      final archive = await openArArchive(source, maxMemberBytes: 1024 * 1024);
      expect(source.reads.every((r) => r.length <= 60), isTrue);
      expect(source.closes, 0);
      expect(
        (await archive.readMember(archive.members.single)).length,
        256 * 1024,
      );
      await archive.close();
      await archive.close();
      expect(source.closes, 1);
    });

    for (final name in ['../bad', '/absolute', r'C:\bad', 'bad\u0000name']) {
      test('flags and refuses unsafe AR member $name', () async {
        final archive = await _open(
          openArArchive,
          arFixture([
            PackageFixtureEntry(name, [1]),
          ], bsdNames: true),
        );
        addTearDown(archive.close);
        expect(archive.members.single.pathEscapedRoot, isTrue);
        await expectLater(
          archive.readMember(archive.members.single),
          throwsA(isA<ArchiveViewException>()),
        );
      });
    }

    test('rejects thin archives and missing member padding', () async {
      await _refused(
        openArArchive,
        Uint8List.fromList(ascii.encode('!<thin>\n')),
      );
      final bytes = arFixture([
        const PackageFixtureEntry('a', [1]),
      ]);
      await _refused(
        openArArchive,
        Uint8List.sublistView(bytes, 0, bytes.length - 1),
      );
    });

    test(
      'rejects invalid lengths, magic, bounds, and GNU name references',
      () async {
        final base = arFixture([
          const PackageFixtureEntry('a', [1, 2]),
        ]);
        final badLength = Uint8List.fromList(base)..[56] = 0x2d;
        final tooLong = Uint8List.fromList(base);
        _replace(tooLong, 56, '9999999999');
        final badMagic = Uint8List.fromList(base)..[66] = 0;
        final missingTable = Uint8List.fromList(base);
        _replace(missingTable, 8, '/0              ');
        for (final bytes in [badLength, tooLong, badMagic, missingTable]) {
          await _refused(openArArchive, bytes);
        }
        final badReference = referenceGnuAr();
        _replace(badReference, 96, '/1');
        await _refused(openArArchive, badReference);
      },
    );

    test('rejects oversized BSD names before allocation', () async {
      final bytes = arFixture([
        const PackageFixtureEntry('a', [1, 2]),
      ]);
      _replace(bytes, 8, '#1/999999999    ');
      await _refused(openArArchive, bytes);
    });
  });

  group('CPIO newc and CRC', () {
    test('reads an independent libarchive newc sample', () async {
      final archive = await _open(openCpioArchive, referenceNewc());
      addTearDown(archive.close);
      expect(archive.formatName, 'cpio');
      expect(archive.members.map((e) => e.name), ['docs', 'docs/hello.txt']);
      expect(archive.members.first.isFile, isFalse);
      expect(archive.members.first.isSpecial, isFalse);
      expect(
        utf8.decode(await archive.readMember(archive.members.last)),
        'Independent container fixture\n',
      );
      expect(archive.members.last.posixMode, 0x81a0);
    });

    test(
      'checks CRC member data, including lazy corruption detection',
      () async {
        final archive = await _open(
          openCpioArchive,
          cpioFixture([
            const PackageFixtureEntry('good', [1, 2, 255]),
            const PackageFixtureEntry('bad', [3, 4], checksum: 8),
          ], crc: true),
        );
        addTearDown(archive.close);
        expect(await archive.readMember(archive.members.first), [1, 2, 255]);
        await expectLater(
          archive.readMember(archive.members.last),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );

    test(
      'does not materialize symbolic links, hardlinks, or devices',
      () async {
        final archive = await _open(
          openCpioArchive,
          cpioFixture([
            const PackageFixtureEntry('link', [46, 46, 47, 120], mode: 0xa1ff),
            const PackageFixtureEntry('hardlink', [1], links: 2),
            const PackageFixtureEntry('device', [], mode: 0x21a4),
          ]),
        );
        addTearDown(archive.close);
        expect(archive.members.every((e) => e.isSpecial), isTrue);
        for (final member in archive.members) {
          await expectLater(
            archive.readMember(member),
            throwsA(isA<ArchiveViewException>()),
          );
        }
      },
    );

    test('skips benign root records but retains traversal flags', () async {
      final archive = await _open(
        openCpioArchive,
        cpioFixture([
          const PackageFixtureEntry('.', [], mode: 0x41ed),
          const PackageFixtureEntry('../outside', [1]),
        ]),
      );
      addTearDown(archive.close);
      expect(archive.members.single.name, 'outside');
      expect(archive.members.single.pathEscapedRoot, isTrue);
      await expectLater(
        archive.readMember(archive.members.single),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    test(
      'refuses missing trailers, truncated payloads, and concatenated data',
      () async {
        final missing = cpioFixture([
          const PackageFixtureEntry('a', [1, 2, 3]),
        ], trailer: false);
        await _refused(openCpioArchive, missing);
        final valid = cpioFixture([
          const PackageFixtureEntry('a', [1, 2, 3]),
        ]);
        await _refused(openCpioArchive, Uint8List.sublistView(valid, 0, 114));
        await _refused(
          openCpioArchive,
          Uint8List.fromList([...valid, ...valid]),
        );
      },
    );

    test('refuses oversized names, invalid numeric fields and unsafe checksum metadata', () async {
      final base = cpioFixture([
        const PackageFixtureEntry('a', [1]),
      ]);
      final hugeName = Uint8List.fromList(base);
      _replace(hugeName, 94, 'ffffffff');
      final invalidHex = Uint8List.fromList(base)..[6] = 0x7a;
      final invalidTerminator = Uint8List.fromList(base)..[111] = 1;
      final unexpectedChecksum = Uint8List.fromList(base);
      _replace(unexpectedChecksum, 102, '00000001');
      for (final bytes in [
        hugeName,
        invalidHex,
        invalidTerminator,
        unexpectedChecksum,
      ]) {
        await _refused(openCpioArchive, bytes);
      }
    });

    test(
      'regular files remain lazy and enforce the configured member limit',
      () async {
        final source = _TrackedSource(
          cpioFixture([PackageFixtureEntry('large', List.filled(4096, 3))]),
        );
        final archive = await openCpioArchive(source, maxMemberBytes: 1024);
        addTearDown(archive.close);
        expect(source.reads.every((r) => r.length <= 110), isTrue);
        await expectLater(
          archive.readMember(archive.members.single),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(source.reads.every((r) => r.length <= 110), isTrue);
      },
    );
  });

  group('XAR package containers', () {
    test(
      'reads independent libarchive TOC, hierarchy, checksums, and zlib data',
      () async {
        final archive = await _open(openXarArchive, referenceXar());
        addTearDown(archive.close);
        expect(archive.formatName, 'xar');
        expect(archive.members.map((e) => e.name), ['docs', 'docs/hello.txt']);
        expect(
          utf8.decode(await archive.readMember(archive.members.last)),
          'Independent container fixture\n',
        );
      },
    );

    for (final encoding in [
      'application/octet-stream',
      'application/x-gzip',
      'application/zlib',
      'application/x-bzip2',
      'application/x-xz',
    ]) {
      test('reads $encoding data with declared and verified hashes', () async {
        final bytes = utf8.encode('container data 日本語');
        final archive = await _open(
          openXarArchive,
          xarMemberFixture(bytes, encoding: encoding),
        );
        addTearDown(archive.close);
        expect(await archive.readMember(archive.members.single), bytes);
      });
    }

    test('rejects corrupted TOC checksum before exposing members', () async {
      final bytes = referenceXar();
      final heapOffset = 28 + ByteData.sublistView(bytes).getUint64(8);
      bytes[heapOffset] ^= 1;
      await _refused(openXarArchive, bytes);
    });

    test(
      'rejects member hash mismatch and unsupported member compression',
      () async {
        for (final bytes in [
          xarMemberFixture([1, 2, 3], invalidChecksum: true),
          xarMemberFixture([1], encoding: 'application/x-lzma'),
        ]) {
          final archive = await _open(openXarArchive, bytes);
          addTearDown(archive.close);
          await expectLater(
            archive.readMember(archive.members.single),
            throwsA(isA<ArchiveViewException>()),
          );
        }
      },
    );

    test(
      'rejects data whose expansion contradicts the declared size',
      () async {
        final archive = await _open(
          openXarArchive,
          xarMemberFixture(
            List.filled(10000, 0),
            encoding: 'application/x-gzip',
            declaredSize: 1,
          ),
          limit: 64,
        );
        addTearDown(archive.close);
        await expectLater(
          archive.readMember(archive.members.single),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );

    test(
      'propagates a hostile parent path flag to descendant members',
      () async {
        final archive = await _open(
          openXarArchive,
          xarFixture(
            '<file><name>../outside</name><type>directory</type>'
            '<file><name>child.txt</name><type>file</type></file></file>',
          ),
        );
        addTearDown(archive.close);
        expect(archive.members.every((e) => e.pathEscapedRoot), isTrue);
        await expectLater(
          archive.readMember(archive.members.last),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );

    test('marks links and device types as non-extractable', () async {
      final archive = await _open(
        openXarArchive,
        xarFixture(
          '<file><name>symbolic</name><type>symlink</type><link>../bad</link></file>'
          '<file><name>hard</name><type link="original">hardlink</type></file>'
          '<file><name>device</name><type>character special</type></file>',
        ),
      );
      addTearDown(archive.close);
      expect(archive.members.every((e) => e.isSpecial), isTrue);
      await expectLater(
        archive.readMember(archive.members.first),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    test(
      'rejects invalid ranges, duplicate fields and files with children',
      () async {
        for (final xml in [
          '<file><name>a</name><type>file</type><data><size>1</size><length>1</length><offset>999999</offset></data></file>',
          '<file><name>a</name><name>b</name><type>file</type></file>',
          '<file><name>a</name><type>file</type><file><name>b</name><type>file</type></file></file>',
          '<file><name>a</name><type>file</type><data><size>1</size><length>1</length><offset>9007199254740992</offset></data></file>',
        ]) {
          await _refused(openXarArchive, xarFixture(xml));
        }
      },
    );

    test('rejects oversized TOC integers, truncated headers, and deeply nested metadata', () async {
      final huge = xarFixture('');
      ByteData.sublistView(huge).setUint64(16, 8 * 1024 * 1024 + 1);
      await _refused(openXarArchive, huge);
      final overflow = xarFixture('');
      ByteData.sublistView(overflow).setUint32(8, 0x200000);
      await _refused(openXarArchive, overflow);
      await _refused(
        openXarArchive,
        Uint8List.sublistView(referenceXar(), 0, 27),
      );
      await _refused(
        openXarArchive,
        xarFixture('${'<x>' * 130}${'</x>' * 130}'),
      );
    });
  });

  group('owned reader lifecycle', () {
    for (final item in [
      (
        reader: openArArchive,
        bytes: arFixture([
          const PackageFixtureEntry('a', [1, 2]),
        ]),
      ),
      (
        reader: openCpioArchive,
        bytes: cpioFixture([
          const PackageFixtureEntry('a', [1, 2]),
        ]),
      ),
      (reader: openXarArchive, bytes: xarMemberFixture([1, 2])),
    ]) {
      test('${item.reader} refuses short reads and releases source', () async {
        final source = _TrackedSource(item.bytes)..shortRead = true;
        await expectLater(
          item.reader(source, maxMemberBytes: 1024),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(source.closes, 1);
      });
      test(
        '${item.reader} binds members and rejects reads after close',
        () async {
          final source = _TrackedSource(item.bytes);
          final archive = await item.reader(source, maxMemberBytes: 1024);
          final other = await _open(item.reader, item.bytes);
          addTearDown(other.close);
          await expectLater(
            archive.readMember(other.members.single),
            throwsA(isA<ArchiveViewException>()),
          );
          await expectLater(
            archive.readMember(archive.members.single, maxBytes: 1),
            throwsA(isA<ArchiveViewException>()),
          );
          await archive.close();
          await archive.close();
          expect(source.closes, 1);
          await expectLater(
            archive.readMember(archive.members.single),
            throwsA(isA<ArchiveViewException>()),
          );
        },
      );
    }
  });
}
