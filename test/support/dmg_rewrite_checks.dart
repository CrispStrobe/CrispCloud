import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/archive_dmg_reader.dart';
import 'package:crisp_cloud/services/archive_dmg_writer.dart';
import 'package:crisp_cloud/services/archive_hfs_writer.dart';
import 'package:crisp_cloud/services/archive_streaming_unsupported.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'dmg_fixture.dart';
import 'hfs_fixture.dart';

final _modified = DateTime.utc(2024, 4, 5, 6, 7, 8);
final _payload = Uint8List.fromList(utf8.encode('captured HFSX data fork'));

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _reject(
  Future<void> Function() action, {
  required bool unsupported,
}) async {
  try {
    await action();
  } catch (error) {
    if (error is ArchiveViewException &&
        (error is ArchiveStreamingUnsupported) == unsupported) {
      return;
    }
    throw StateError('Unexpected rejection type: $error');
  }
  throw StateError('Unsafe image or operation was accepted.');
}

ArchiveWriteEntry _file(String path, List<int> bytes, {int mode = 0x81ed}) =>
    ArchiveWriteEntry(
      path: path,
      isDirectory: false,
      size: bytes.length,
      modified: _modified,
      mode: mode,
      readChunks: () => Stream.value(bytes),
    );

List<ArchiveWriteEntry> _baseEntries() => [
  _file('docs/keep.txt', _payload),
  _file('remove.txt', [9, 8, 7]),
  ArchiveWriteEntry(
    path: 'empty-folder',
    isDirectory: true,
    size: 0,
    modified: _modified,
    mode: 0x41c0,
  ),
];

/// The same focused checks are registered in Flutter's test runner and can be
/// run by the independent Dart probe when the local Flutter engine is blocked.
Map<String, Future<void> Function()> dmgRewriteChecks() {
  Future<Uint8List>? template;
  Future<Uint8List> hfs() async {
    template ??= collectArchiveWrite(
      (sink) =>
          writeHfsArchive(_baseEntries(), sink: sink, volumeName: 'Records'),
    );
    return Uint8List.fromList(await template!);
  }

  final cases = <String, Future<void> Function()>{};
  for (final compressed in [false, true]) {
    cases['native DMG ${compressed ? 'zlib' : 'raw'} opens flattened files and owns its source'] = () async {
      final bytes = await collectArchiveWrite(
        (sink) => writeDmgArchive(
          _baseEntries(),
          sink: sink,
          compress: compressed,
          volumeName: 'Records',
        ),
      );
      final source = _TrackedSource(bytes);
      var cancelled = false;
      final opened = await openStreamedDmgSource(
        source,
        isCancelled: () => cancelled,
      );
      try {
        _require(opened.inspection.supported, 'Canonical image is read-only.');
        _require(opened.archive.formatName == 'dmg', 'Wrong format.');
        _require(
          opened.archive.maxStreamingMemberBytes == kArchiveStreamingLimit,
          'Native streaming cap was not propagated.',
        );
        _require(
          opened.archive.members.map((m) => m.name).toSet().difference({
                'docs',
                'docs/keep.txt',
                'remove.txt',
                'empty-folder',
              }).isEmpty &&
              opened.archive.members.length == 4,
          'The editable view contains generated partition or files prefixes.',
        );
        final member = opened.archive.members.singleWhere(
          (m) => m.name == 'docs/keep.txt',
        );
        _require(member.modified == _modified, 'Modification time changed.');
        _require(member.posixMode == 0x81ed, 'POSIX mode changed.');
        // An opening-operation cancellation token must not invalidate the
        // successful handle later when that operation's lifetime ends.
        cancelled = true;
        _require(
          await sha256.bind(opened.archive.openMember(member)).single ==
              sha256.convert(_payload),
          'The flattened file view changed the data fork.',
        );
        _require(source.closes == 0, 'Source closed before its handle.');
      } finally {
        await opened.archive.close();
        await opened.archive.close();
      }
      _require(source.closes == 1, 'Source ownership is not exactly once.');
    };
  }

  cases['native DMG rewrites preserve volume and root dates plus renamed member metadata'] =
      () async {
        final raw = await hfs();
        _setDistinctMetadata(raw);
        final original = await openStreamedDmgSource(
          _TrackedSource(_canonicalEnvelope(raw)),
        );
        try {
          final entries = _capture(original, rename: true);
          final bytes = await collectArchiveWrite(
            (sink) => writeDmgArchive(
              entries,
              source: original.inspection,
              sink: sink,
              // A caller's creation default must not replace the original name.
              volumeName: 'Wrong replacement label',
            ),
          );
          final candidate = await openStreamedDmgSource(_TrackedSource(bytes));
          try {
            verifyDmgRewritePreservation(
              entries,
              candidate.inspection,
              source: original.inspection,
            );
            _require(
              !candidate.archive.members.any((m) => m.name == 'remove.txt') &&
                  candidate.archive.members.any(
                    (m) => m.name == 'added/new.txt',
                  ),
              'Add/delete changes were not applied.',
            );
            final renamed = candidate.archive.members.singleWhere(
              (m) => m.name == 'docs/renamed.txt',
            );
            _require(
              await sha256.bind(candidate.archive.openMember(renamed)).single ==
                  sha256.convert(_payload),
              'Renaming changed file contents.',
            );
            _require(
              _sameMap(
                candidate.inspection.attributes['docs/renamed.txt']!,
                original.inspection.attributes['docs/keep.txt']!,
              ),
              'Auxiliary dates were not retained on rename.',
            );
          } finally {
            await candidate.archive.close();
          }
        } finally {
          await original.archive.close();
        }
      };

  for (final root in [false, true]) {
    cases['native DMG verification rejects a self-consistent changed ${root ? 'root' : 'member'} auxiliary date'] =
        () async {
          final raw = await hfs();
          _setDistinctMetadata(raw);
          final original = await openStreamedDmgSource(
            _TrackedSource(_canonicalEnvelope(raw)),
          );
          final changed = Uint8List.fromList(raw);
          final record = _record(changed, root ? 'Records' : 'keep.txt');
          record.setUint32(12, record.getUint32(12) + 1);
          final candidate = await openStreamedDmgSource(
            _TrackedSource(_canonicalEnvelope(changed)),
          );
          try {
            await _reject(
              () async => verifyDmgRewritePreservation(
                _capture(original),
                candidate.inspection,
                source: original.inspection,
              ),
              unsupported: false,
            );
          } finally {
            await original.archive.close();
            await candidate.archive.close();
          }
        };
  }

  final unsafeHfs = <String, void Function(Uint8List)>{
    'journal': (bytes) => ByteData.sublistView(bytes).setUint32(1028, 0x2100),
    'attribute fork': (bytes) => bytes[1024 + 352 + 7] = 1,
    'startup fork': (bytes) => bytes[1024 + 432 + 7] = 1,
    'resource fork': (bytes) =>
        _record(bytes, 'keep.txt').setUint32(168 + 4, 1),
    'symbolic link': (bytes) =>
        _record(bytes, 'keep.txt').setUint16(42, 0xa1ff),
    'ownership': (bytes) => _record(bytes, 'keep.txt').setUint32(32, 501),
    'Finder info': (bytes) =>
        _record(bytes, 'keep.txt').setUint32(48, 0x54455854),
    'catalog slack': (bytes) {
      final header = ByteData.sublistView(bytes, 1024);
      final start = header.getUint32(272 + 16);
      final blocks = header.getUint32(272 + 20);
      bytes[(start + blocks - 1) * 4096 + 19] = 3;
    },
    'extents overflow node': (bytes) {
      final start = ByteData.sublistView(bytes, 1024).getUint32(192 + 16);
      bytes[(start + 1) * 4096 + 29] = 4;
    },
    'free block': (bytes) {
      final free = ByteData.sublistView(bytes, 1024).getUint32(52);
      bytes[free * 4096 + 31] = 5;
    },
    'file allocation slack': (bytes) {
      final record = _record(bytes, 'keep.txt');
      final start = record.getUint32(88 + 16) * 4096;
      bytes[start + _payload.length] = 6;
    },
    'boot reservation': (bytes) => bytes[7] = 7,
    'alternate header': (bytes) => bytes[bytes.length - 1024 + 20] ^= 1,
    'foreign allocation': (bytes) {
      final record = _record(bytes, 'keep.txt');
      record.setUint32(88 + 16, record.getUint32(88 + 16) + 1);
    },
  };
  for (final item in unsafeHfs.entries) {
    cases['native DMG refuses unpreserved HFSX ${item.key} even with CrC1 and valid CRCs'] =
        () async {
          final raw = await hfs();
          item.value(raw);
          final source = _TrackedSource(_canonicalEnvelope(raw));
          await _reject(
            () async => openStreamedDmgSource(source),
            unsupported: true,
          );
          _require(source.closes == 1, 'Unsupported source was not closed.');
        };
  }

  cases['native DMG refuses a foreign filesystem bearing a forged creator marker'] =
      () async {
        final fixture = HfsFixture(hfsx: true);
        fixture.data.setUint32(1024 + 8, 0x43724331);
        final source = _TrackedSource(_canonicalEnvelope(fixture.bytes));
        await _reject(
          () async => openStreamedDmgSource(source),
          unsupported: true,
        );
        _require(source.closes == 1, 'Foreign source leaked.');
      };

  for (final kind in ['plist', 'trailer', 'partition', 'compressed suffix']) {
    cases['native DMG refuses unknown UDIF $kind data'] = () async {
      final raw = await hfs();
      final source = _TrackedSource(
        _canonicalEnvelope(
          raw,
          compressed: kind == 'compressed suffix',
          unknown: kind,
        ),
      );
      await _reject(
        () async => openStreamedDmgSource(source),
        unsupported: true,
      );
      _require(source.closes == 1, 'Unsupported UDIF source leaked.');
    };
  }

  cases['native DMG checksum corruption is an error instead of a fallback'] =
      () async {
        final raw = await hfs();
        final fileAt = _record(raw, 'keep.txt').getUint32(88 + 16) * 4096;
        final bytes = _canonicalEnvelope(raw)..[fileAt] ^= 1;
        final source = _TrackedSource(bytes);
        await _reject(
          () async => openStreamedDmgSource(source),
          unsupported: false,
        );
        _require(source.closes == 1, 'Corrupt source leaked.');
      };

  for (final during in [false, true]) {
    cases['native DMG cancellation ${during ? 'during' : 'before'} opening closes its source'] =
        () async {
          var cancelled = !during;
          final source = _TrackedSource(
            _canonicalEnvelope(await hfs()),
            onRead: (count) {
              if (during && count == 5) cancelled = true;
            },
          );
          await _reject(
            () async =>
                openStreamedDmgSource(source, isCancelled: () => cancelled),
            unsupported: false,
          );
          _require(source.closes == 1, 'Cancelled source leaked.');
          _require(during || source.reads == 0, 'Cancelled open read bytes.');
        };
  }

  cases['native DMG rejects excessive size and fabricated rewrite proofs before reading'] =
      () async {
        final source = _TrackedSource(
          Uint8List(0),
          declaredLength: kArchiveStreamingLimit + 1,
        );
        await _reject(
          () async => openStreamedDmgSource(source),
          unsupported: false,
        );
        _require(
          source.reads == 0 && source.closes == 1,
          'Bad limit ownership.',
        );
        var reads = 0, writes = 0;
        final entry = ArchiveWriteEntry(
          path: 'too-large',
          isDirectory: false,
          size: kArchiveStreamingLimit,
          readChunks: () {
            reads++;
            return const Stream.empty();
          },
        );
        await _reject(
          () => writeDmgArchive(
            [entry],
            sink: (_) async {
              writes++;
            },
          ),
          unsupported: false,
        );
        await _reject(
          () => writeDmgArchive(
            [],
            source: ArchiveRewriteInspection(
              container: {'dmg.profile': 'CrC1'},
            ),
            sink: (_) async {
              writes++;
            },
          ),
          unsupported: false,
        );
        _require(reads == 0 && writes == 0, 'Invalid input reached the sink.');
      };

  cases['native DMG streams and verifies a 65 MiB member with bounded reads'] =
      () async {
        const size = 65 * 1024 * 1024 + 333;
        final block = Uint8List.fromList(List.generate(65536, (i) => i % 251));
        Stream<List<int>> contents() async* {
          for (var at = 0; at < size; at += block.length) {
            final count = size - at < block.length ? size - at : block.length;
            yield Uint8List.sublistView(block, 0, count);
          }
        }

        final expected = await sha256.bind(contents()).single;
        final entry = ArchiveWriteEntry(
          path: 'large.bin',
          isDirectory: false,
          size: size,
          modified: _modified,
          readChunks: contents,
        );
        final bytes = await collectArchiveWrite(
          (sink) => writeDmgArchive([entry], sink: sink),
          maxBytes: 16 * 1024 * 1024,
        );
        final source = _TrackedSource(bytes);
        final opened = await openStreamedDmgSource(source);
        try {
          final member = opened.archive.members.single;
          _require(member.size == size, 'Large size was truncated.');
          _require(
            await sha256
                    .bind(
                      opened.archive.openMember(
                        member,
                        maxBytes: kArchiveStreamingLimit,
                        chunkSize: 65537,
                      ),
                    )
                    .single ==
                expected,
            'Large streamed contents differ.',
          );
          _require(source.maxRead <= 1024 * 1024, 'A whole member was read.');
          await _reject(
            () async => opened.archive.readMember(member),
            unsupported: false,
          );
        } finally {
          await opened.archive.close();
        }
        _require(source.closes == 1, 'Large source leaked.');
      };
  return cases;
}

List<ArchiveWriteEntry> _capture(
  StreamedDmgOpen opened, {
  bool rename = false,
}) => [
  for (final member in opened.archive.members)
    if (!rename || member.name != 'remove.txt')
      ArchiveWriteEntry(
        path: rename && member.name == 'docs/keep.txt'
            ? 'docs/renamed.txt'
            : member.name,
        isDirectory: !member.isFile,
        size: member.size,
        modified: member.modified,
        mode: member.posixMode,
        attributes: opened.inspection.attributes[member.name]!,
        readChunks: member.isFile
            ? () => opened.archive.openMember(
                member,
                maxBytes: kArchiveStreamingLimit,
              )
            : null,
      ),
  if (rename) _file('added/new.txt', [1, 2, 3]),
];

bool _sameMap(Map<String, Object?> a, Map<String, Object?> b) =>
    a.length == b.length &&
    a.entries.every((entry) => b[entry.key] == entry.value);

void _setDistinctMetadata(Uint8List bytes) {
  final volume = ByteData.sublistView(bytes, 1024);
  for (var i = 0; i < 4; i++) {
    volume.setUint32(16 + 4 * i, 3800000001 + i);
  }
  final root = _record(bytes, 'Records');
  for (var i = 0; i < 5; i++) {
    root.setUint32(12 + 4 * i, 3800000101 + i);
  }
  root.setUint16(42, 0x41c0);
  final member = _record(bytes, 'keep.txt');
  for (final (index, offset) in [12, 20, 24, 28].indexed) {
    member.setUint32(offset, 3800000201 + index);
  }
  bytes.setRange(bytes.length - 1024, bytes.length - 512, bytes, 1024);
}

/// Independent catalog walk used to mutate fields that the public file view
/// omits. It does not use the production parser or rewrite inspection.
ByteData _record(Uint8List bytes, String name) {
  final volume = ByteData.sublistView(bytes, 1024);
  final catalogAt = volume.getUint32(272 + 16) * volume.getUint32(40);
  final header = ByteData.sublistView(bytes, catalogAt);
  final nodeSize = header.getUint16(32);
  var leaf = header.getUint32(24);
  while (leaf != 0) {
    final start = catalogAt + leaf * nodeSize;
    final node = ByteData.sublistView(bytes, start, start + nodeSize);
    for (var i = 0; i < node.getUint16(10); i++) {
      final at = node.getUint16(nodeSize - (i + 1) * 2);
      final keySize = node.getUint16(at) + 2;
      final dataAt = at + keySize;
      if (node.getUint16(dataAt) > 2) continue;
      final length = node.getUint16(at + 6);
      final found = String.fromCharCodes([
        for (var j = 0; j < length; j++) node.getUint16(at + 8 + j * 2),
      ]);
      if (found == name) return ByteData.sublistView(bytes, start + dataAt);
    }
    leaf = node.getUint32(0);
  }
  throw StateError('Fixture catalog member not found: $name');
}

/// Adds the canonical envelope fields to the independent UDIF fixture. CRCs
/// are regenerated after mutations, so preservation tests cannot pass merely
/// because a checksum is stale. Only the corruption test intentionally skips it.
Uint8List _canonicalEnvelope(
  Uint8List hfs, {
  bool compressed = false,
  String? unknown,
}) {
  final fixture = DmgFixture(
    hfs,
    method: compressed ? 0x80000005 : 1,
    chunkBytes: 1024 * 1024,
    label: 'Apple_HFSX (CrispCloud data volume)',
  );
  final table = fixture.tableData;
  table.setUint32(36, 0xfffffffe);
  final count = table.getUint32(200);
  if (unknown == 'compressed suffix') {
    final length = table.getUint64(204 + 32);
    fixture.packedBytes = Uint8List.fromList([
      ...fixture.packedBytes.sublist(0, length),
      0x21,
      ...fixture.packedBytes.sublist(length),
    ]);
    table.setUint64(204 + 32, length + 1);
    for (var i = 1; i < count - 1; i++) {
      final at = 204 + i * 40 + 24;
      table.setUint64(at, table.getUint64(at) + 1);
    }
  }
  table.setUint64(204 + (count - 1) * 40 + 24, fixture.packedBytes.length);
  final one =
      '<dict><key>Attributes</key><string>0x0050</string>'
      '<key>ID</key><string>0</string>'
      '<key>Name</key><string>Apple_HFSX (CrispCloud data volume)</string>'
      '<key>Data</key><data>${base64.encode(fixture.table)}</data></dict>';
  final xml =
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
      '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
      '<plist version="1.0"><dict><key>resource-fork</key><dict>'
      '<key>blkx</key><array>$one${unknown == 'partition' ? one : ''}'
      '</array></dict>${unknown == 'plist' ? '<key>Opaque</key><string>keep me</string>' : ''}'
      '</dict></plist>\n';
  fixture.rebuild(xml: xml);
  final k = fixture.trailer;
  final rawCrc = table.getUint32(72);
  final packedCrc = ar.getCrc32(fixture.packedBytes);
  k.setUint32(64, 0x43724331);
  k.setUint32(68, rawCrc);
  k.setUint32(72, packedCrc);
  k.setUint32(76, fixture.logical.length & 0xffffffff);
  k.setUint32(80, 2);
  k.setUint32(84, 32);
  k.setUint32(88, packedCrc);
  k.setUint32(352, 2);
  k.setUint32(356, 32);
  final checksum = Uint8List(4);
  ByteData.sublistView(checksum).setUint32(0, rawCrc);
  k.setUint32(360, ar.getCrc32(checksum));
  k.setUint32(488, 2);
  if (unknown == 'trailer') k.setUint32(232, 0x11223344);
  return fixture.bytes;
}

class _TrackedSource implements koni.ByteSource {
  _TrackedSource(this.bytes, {this.onRead, this.declaredLength});
  final Uint8List bytes;
  final void Function(int)? onRead;
  final int? declaredLength;
  int reads = 0, closes = 0, maxRead = 0;
  @override
  String get name => 'fixture.dmg';
  @override
  int get length => declaredLength ?? bytes.length;
  @override
  Future<Uint8List> read(int offset, int length) async {
    _require(closes == 0, 'Reading a closed source.');
    reads++;
    if (length > maxRead) maxRead = length;
    onRead?.call(reads);
    return Uint8List.sublistView(bytes, offset, offset + length);
  }

  @override
  Future<void> close() async {
    closes++;
  }
}
