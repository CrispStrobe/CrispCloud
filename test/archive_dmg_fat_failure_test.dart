import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:crisp_cloud/services/archive_dmg_reader.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_fat_fixture.dart';

void main() {
  test('DMG FAT cache-miss expansion is capped across partitions', () async {
    final fixture = _AmplifiedFatDmg();
    final source = _ObservedDmgSource(fixture.bytes);
    final archive = await openDmgArchive(
      source,
      maxMemberBytes: kArchiveReadLimit,
    );
    addTearDown(archive.close);

    expect(archive.members, hasLength(2));
    expect(archive.members.first.name, endsWith('.fat'));
    expect(archive.members.last.name, endsWith('.img'));
    expect(archive.notices.join(' '), contains('decompression work'));
    expect(
      archive.notices.join(' '),
      contains('without additional filesystem probing'),
    );
    final packedReads = fixture.packedReads(source);
    // Sixteen cache misses expand 16 MiB apiece. A seventeenth attempt is
    // refused before its packed bytes are read, even though the FAT requested
    // only a few KiB from each decoded block.
    expect(packedReads, hasLength(16));
    expect(packedReads.length * fixture.chunkBytes, 256 * 1024 * 1024);
    expect(
      packedReads.fold<int>(0, (sum, read) => sum + read.$2),
      lessThan(1024 * 1024),
    );
    expect(source.ranges.where((r) => r == (0, 512)), hasLength(2));
    expect(source.closeCount, 0);

    // Failed child ownership and exhausted listing allowances do not revoke
    // the raw partition entry. This is a bounded prefix, not a physical full
    // extraction of the synthetic large volume.
    final rawPrefix = await archive
        .openMember(archive.members.first, chunkSize: 512)
        .take(1)
        .single;
    expect(rawPrefix, fixture.boot);
    await archive.close();
    await archive.close();
    expect(source.closeCount, 1);
  });

  test(
    'DMG FAT backing-input budget stops costly low-compression cache misses',
    () async {
      final fixture = _AmplifiedFatDmg(lzfseRaw: true);
      final source = _ObservedDmgSource(fixture.bytes);
      final archive = await openDmgArchive(
        source,
        maxMemberBytes: kArchiveReadLimit,
      );
      addTearDown(archive.close);

      expect(archive.members, hasLength(2));
      expect(archive.notices.join(' '), contains('backing-input reads'));
      final packedReads = fixture.packedReads(source);
      // Each valid LZFSE raw frame has 8 MiB plus framing bytes. Eight frames
      // would exceed 64 MiB; only seven reach the source. Expanded work remains
      // well below its independent 256 MiB ceiling.
      expect(packedReads, hasLength(7));
      expect(
        packedReads.fold<int>(0, (sum, read) => sum + read.$2),
        lessThanOrEqualTo(64 * 1024 * 1024),
      );
      expect(
        packedReads.length * fixture.chunkBytes,
        lessThan(256 * 1024 * 1024),
      );
      expect(source.ranges.where((r) => r == (0, 512)), hasLength(2));
      expect(
        await archive
            .openMember(archive.members.last, chunkSize: 512)
            .take(1)
            .single,
        fixture.boot,
      );
    },
  );

  test(
    'FAT cache hits do not incur fictitious DMG expansion charges',
    () async {
      final fixture = _AmplifiedFatDmg(partitionCopies: 1, clusterStride: 1);
      final source = _ObservedDmgSource(fixture.bytes);
      final archive = await openDmgArchive(
        source,
        maxMemberBytes: kArchiveReadLimit,
      );
      addTearDown(archive.close);

      expect(
        archive.members.where((m) => m.name.startsWith('files/')),
        hasLength(16),
      );
      expect(archive.notices.join(' '), isNot(contains('resource limit')));
      expect(fixture.packedReads(source), hasLength(2));
      for (final member in archive.members.where(
        (m) => m.name.startsWith('files/'),
      )) {
        expect(await archive.readMember(member), [0]);
      }
    },
  );
}

/// Original sparse synthetic UDIF wrapper. It uses intentionally oversized FAT
/// tables, which the FAT BPB permits, so a tiny metadata page can force a large
/// block decode. Both logical tables are valid and have identical allocation
/// entries. Most of the data area is a zero-fill extent and is never allocated
/// as a large test buffer.
class _AmplifiedFatDmg {
  _AmplifiedFatDmg({
    bool lzfseRaw = false,
    int partitionCopies = 2,
    int clusterStride = 2048,
  }) : chunkBytes = (lzfseRaw ? 8 : 16) * 1024 * 1024 {
    const clusters = 50000;
    const rootBytes = 4096;
    final fatSectors = chunkBytes ~/ 512;
    final sectors = 1 + 2 * fatSectors + rootBytes ~/ 512 + clusters;
    boot = Uint8List.fromList(
      FatFixture(bits: 16, clusterCount: clusters, includeFile: false).boot,
    );
    fatPut16(boot, 19, 0);
    fatPut32(boot, 32, sectors);
    fatPut16(boot, 22, fatSectors);
    final fat = Uint8List(chunkBytes);
    fatPut16(fat, 0, 0xfff8);
    fatPut16(fat, 2, 0xffff);
    final root = Uint8List(rootBytes);
    for (var i = 0; i < 16; i++) {
      final cluster = 2 + i * clusterStride;
      fatPut16(fat, cluster * 2, 0xffff);
      root.setRange(
        i * 32,
        i * 32 + 32,
        fatShortEntry('F$i.BIN', firstCluster: cluster, size: 1),
      );
    }
    final packed = lzfseRaw
        ? _lzfseFrame(fat)
        : Uint8List.fromList(const ar.ZLibEncoder().encode(fat));
    packedLength = packed.length;
    firstPackedOffset = 512;
    secondPackedOffset = firstPackedOffset + packedLength;
    final rootOffset = secondPackedOffset + packedLength;
    final fork = Uint8List(rootOffset + rootBytes)
      ..setAll(0, boot)
      ..setAll(firstPackedOffset, packed)
      ..setAll(secondPackedOffset, packed)
      ..setAll(rootOffset, root);
    final method = lzfseRaw ? 0x80000007 : 0x80000005;
    final chunks = <(int, int, int, int, int)>[
      (1, 0, 1, 0, 512),
      (method, 1, fatSectors, firstPackedOffset, packedLength),
      (method, 1 + fatSectors, fatSectors, secondPackedOffset, packedLength),
      (1, 1 + 2 * fatSectors, rootBytes ~/ 512, rootOffset, rootBytes),
      (0, 1 + 2 * fatSectors + rootBytes ~/ 512, clusters, 0, 0),
      (0xffffffff, sectors, 0, 0, 0),
    ];
    final table = Uint8List(204 + 40 * chunks.length);
    table.setAll(0, ascii.encode('mish'));
    final descriptor = ByteData.sublistView(table);
    descriptor.setUint32(4, 1);
    descriptor.setUint64(16, sectors);
    descriptor.setUint32(32, fatSectors);
    descriptor.setUint32(200, chunks.length);
    for (var i = 0; i < chunks.length; i++) {
      final (type, start, count, offset, packedBytes) = chunks[i];
      final at = 204 + i * 40;
      descriptor.setUint32(at, type);
      descriptor.setUint64(at + 8, start);
      descriptor.setUint64(at + 16, count);
      descriptor.setUint64(at + 24, offset);
      descriptor.setUint64(at + 32, packedBytes);
    }
    final encoded = base64.encode(table);
    final entries = List.generate(
      partitionCopies,
      (i) =>
          '<dict><key>Name</key><string>Amplification $i</string>'
          '<key>Data</key><data>$encoded</data></dict>',
    ).join();
    final xml = utf8.encode(
      '<plist version="1.0"><dict>'
      '<key>resource-fork</key><dict><key>blkx</key><array>$entries</array>'
      '</dict></dict></plist>',
    );
    bytes = Uint8List(fork.length + xml.length + 512)
      ..setAll(0, fork)
      ..setAll(fork.length, xml);
    final at = bytes.length - 512;
    bytes.setAll(at, ascii.encode('koly'));
    final trailer = ByteData.sublistView(bytes, at);
    trailer.setUint32(4, 4);
    trailer.setUint32(8, 512);
    trailer.setUint32(12, 1);
    trailer.setUint64(32, fork.length);
    trailer.setUint32(56, 1);
    trailer.setUint32(60, 1);
    trailer.setUint64(216, fork.length);
    trailer.setUint64(224, xml.length);
    trailer.setUint32(488, 1);
    trailer.setUint64(492, sectors);
  }

  final int chunkBytes;
  late final int packedLength, firstPackedOffset, secondPackedOffset;
  late final Uint8List bytes, boot;
  List<(int, int)> packedReads(_ObservedDmgSource source) => source.ranges
      .where(
        (r) =>
            (r.$1 == firstPackedOffset || r.$1 == secondPackedOffset) &&
            r.$2 == packedLength,
      )
      .toList();
}

Uint8List _lzfseFrame(Uint8List input) {
  final frame = Uint8List(input.length + 12)
    ..setAll(0, ascii.encode('bvx-'))
    ..setAll(8, input)
    ..setAll(input.length + 8, ascii.encode('bvx\u0024'));
  ByteData.sublistView(frame).setUint32(4, input.length, Endian.little);
  return frame;
}

class _ObservedDmgSource implements koni.ByteSource {
  _ObservedDmgSource(this.bytes);
  final Uint8List bytes;
  final ranges = <(int, int)>[];
  int closeCount = 0;
  @override
  String get name => 'synthetic-amplification.dmg';
  @override
  int get length => bytes.length;
  @override
  Future<Uint8List> read(int offset, int length) async {
    ranges.add((offset, length));
    return Uint8List.sublistView(bytes, offset, offset + length);
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}
