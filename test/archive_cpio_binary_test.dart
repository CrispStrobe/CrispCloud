import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:crisp_cloud/services/archive_endpoint_policy.dart';
import 'package:crisp_cloud/services/archive_package_readers.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

Uint8List _fixture(String order) =>
    File('test/fixtures/archives/reference-binary-$order.cpio')
        .readAsBytesSync();

class _Source implements koni.ByteSource {
  _Source(this.bytes);
  final Uint8List bytes;
  int closes = 0;
  final reads = <(int, int)>[];
  @override
  String get name => 'Payload';
  @override
  int get length => bytes.length;
  @override
  Future<Uint8List> read(int at, int count) async {
    if (closes > 0) throw StateError('closed');
    reads.add((at, count));
    return Uint8List.sublistView(bytes, at, at + count);
  }

  @override
  Future<void> close() async => closes++;
}

void main() {
  for (final order in ['le', 'be']) {
    test(
      'reads independent $order binary fixture and 32-bit word order',
      () async {
        final bytes = _fixture(order);
        final source = _Source(bytes);
        final archive = await openCpioArchive(
          source,
          maxMemberBytes: kArchiveReadLimit,
        );
        addTearDown(archive.close);
        expect(archive.members.map((m) => m.name), [
          'docs',
          'docs/odd',
          'empty',
          'payload.bin',
        ]);
        expect(
          source.reads.every((read) => read.$2 <= 26),
          isTrue,
          reason: 'payloads remain lazy',
        );
        expect(archive.members.first.isFile, isFalse);
        expect(archive.members[1].posixMode, 0x81a0);
        expect(
          archive.members.last.modified,
          DateTime.utc(2023, 11, 14, 22, 13, 20),
        );
        expect(await archive.readMember(archive.members[1]), [111, 100, 100]);
        expect(await archive.readMember(archive.members[2]), isEmpty);
        final large = await archive.readMember(archive.members.last);
        expect(large.length, 65536 + 333);
        expect(large, List.generate(65536 + 333, (i) => i % 251));
        final policy = await ArchiveEndpointPolicy.inspect(
          bytes,
          'test.cpio',
          archive,
          null,
        );
        expect(
          policy.reason,
          isNotNull,
          reason: 'the newc writer must not rewrite binary metadata',
        );
      },
    );

    test('$order magic works under misleading and compressed names', () async {
      for (final name in ['Payload', 'misleading.zip']) {
        final archive = await openViewerArchive(_fixture(order), name: name);
        expect(archive.formatName, 'cpio');
        await archive.close();
      }
      final packed = Uint8List.fromList(
        const ar.GZipEncoder().encode(_fixture(order)),
      );
      final archive = await openViewerArchive(packed, name: 'Payload.gz');
      expect(archive.formatName, 'cpio');
      expect(archive.members.length, 4);
      await archive.close();
    });
  }

  test('oversized members remain listable but reads are bounded', () async {
    final archive = await openCpioArchive(
      _Source(_fixture('le')),
      maxMemberBytes: 32,
    );
    addTearDown(archive.close);
    expect(archive.members.last.size, 65869);
    await expectLater(
      archive.readMember(archive.members.last),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test(
    'binary unsafe, linked and historical special modes cannot extract',
    () async {
      for (final mutate in <void Function(Uint8List)>[
        (data) => data.setRange(58, 66, '/bad/odd'.codeUnits),
        (data) =>
            ByteData.sublistView(data).setUint16(32 + 12, 2, Endian.little),
        (data) =>
            ByteData.sublistView(data).setUint16(32 + 6, 0x91a4, Endian.little),
      ]) {
        final bytes = _fixture('le');
        mutate(bytes);
        final archive = await openCpioArchive(
          _Source(bytes),
          maxMemberBytes: kArchiveReadLimit,
        );
        addTearDown(archive.close);
        final member = archive.members[1];
        expect(member.pathEscapedRoot || member.isSpecial, isTrue);
        await expectLater(
          archive.readMember(member),
          throwsA(isA<ArchiveViewException>()),
        );
      }
    },
  );

  test(
    'malformed headers, padding, profiles and tails close owned source',
    () async {
      final mutations = <void Function(Uint8List)>[
        (data) => data[0] = 0,
        (data) => data[31] = 1, // directory name alignment
        (data) => data[71] = 1, // odd payload alignment
        (data) => data[30] = 1, // NUL pathname terminator
        (data) => ByteData.sublistView(data).setUint16(20, 0, Endian.little),
        (data) =>
            ByteData.sublistView(data).setUint16(20, 65535, Endian.little),
        (data) =>
            ByteData.sublistView(data).setUint16(22, 0x8000, Endian.little),
        (data) => ByteData.sublistView(data)
            .setUint16(24, 1, Endian.little), // directory data
        (data) {
          for (var i = 32; i < 58; i += 2) {
            final a = data[i];
            data[i] = data[i + 1];
            data[i + 1] = a;
          }
        },
      ];
      final bytes = _fixture('le');
      final cases = [
        for (final mutate in mutations)
          (Uint8List.fromList(bytes)..also(mutate)),
        Uint8List.fromList([...bytes, 1]),
        Uint8List.fromList([...bytes, ...bytes]),
        for (final size in [0, 1, 2, 6, 25, 31, 40, 70, 200, bytes.length - 1])
          Uint8List.sublistView(bytes, 0, size),
      ];
      for (final data in cases) {
        final source = _Source(data);
        await expectLater(
          openCpioArchive(source, maxMemberBytes: kArchiveReadLimit),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(source.closes, 1);
      }
    },
  );
}

extension on Uint8List {
  void also(void Function(Uint8List) mutate) => mutate(this);
}
