import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:crisp_cloud/services/archive_sevenz_streamed_reader.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

// Independent tiny 7z grammar fixtures. Logical gaps are never materialized;
// malformed resource declarations are checked by opening metadata only.
List<int> _number(int value) {
  for (var bytes = 0; bytes < 8; bytes++) {
    if (value < (1 << (7 + bytes * 7))) {
      return [
        ((0xff << (8 - bytes)) & 0xff) | (value >> (bytes * 8)),
        for (var i = 0; i < bytes; i++) (value >> (i * 8)) & 0xff,
      ];
    }
  }
  return [0xff, for (var i = 0; i < 8; i++) (value >> (8 * i)) & 0xff];
}

class _Coder {
  const _Coder(this.id, {this.properties});
  final List<int> id;
  final List<int>? properties;
  List<int> get bytes => [
    id.length | (properties == null ? 0 : 0x20),
    ...id,
    if (properties != null) ...[..._number(properties!.length), ...properties!],
  ];
}

const _copy = _Coder([0]);
const _aes = _Coder([6, 0xf1, 7, 1], properties: [0]);
const _delta = _Coder([3], properties: [0]);

List<int> _streams({
  required List<int> packedSizes,
  required List<int> outputs,
  List<_Coder> coders = const [_copy],
  int packPosition = 0,
}) => [
  6, ..._number(packPosition), ..._number(packedSizes.length),
  9, for (final size in packedSizes) ..._number(size), 0,
  7, 11, 1, 0, // one inline folder
  ..._number(coders.length),
  for (final coder in coders) ...coder.bytes,
  for (var i = 1; i < coders.length; i++) ...[..._number(i), ..._number(i - 1)],
  12, for (final size in outputs) ..._number(size), 0,
  0, // StreamsInfo end; one substream by default
];

Uint8List _plain(List<int> streams, {String? name}) => Uint8List.fromList([
  1,
  4,
  ...streams,
  if (name != null) ...[
    5, 1, // FilesInfo, one file
    17, ..._number(1 + name.length * 2 + 2), 0,
    for (final unit in name.codeUnits) ...[unit & 0xff, unit >> 8],
    0, 0, 0, // name terminator and FilesInfo end
  ],
  0,
]);

class _SparseSource implements koni.ByteSource {
  _SparseSource(Uint8List metadata, {List<int> payload = const [], int? size})
    : length = size ?? 32 + payload.length + metadata.length,
      metadata = Uint8List.fromList(metadata),
      payload = Uint8List.fromList(payload) {
    headerOffset = length - metadata.length;
    signature.setRange(0, 8, const [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 0, 4]);
    final data = ByteData.sublistView(signature);
    data.setUint64(12, headerOffset - 32, Endian.little);
    data.setUint64(20, metadata.length, Endian.little);
    data.setUint32(28, getCrc32(metadata), Endian.little);
    data.setUint32(
      8,
      getCrc32(Uint8List.sublistView(signature, 12)),
      Endian.little,
    );
  }
  @override
  final int length;
  @override
  String get name => 'resource-fixture.7z';
  final Uint8List signature = Uint8List(32), metadata, payload;
  late final int headerOffset;
  bool closed = false;
  final requests = <(int, int)>[];

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (closed || offset < 0 || length < 0 || length > this.length - offset) {
      throw StateError('Read left the sparse fixture.');
    }
    // A malformed field must not become a giant source read. Tests never
    // construct a large data buffer, even when the logical input is 8 GiB.
    if (length > 1024 * 1024) throw StateError('Unbounded fixture read.');
    requests.add((offset, length));
    final result = Uint8List(length);
    for (final segment in [
      (0, signature),
      (32, payload),
      (headerOffset, metadata),
    ]) {
      final begin = offset > segment.$1 ? offset : segment.$1;
      final end = offset + length < segment.$1 + segment.$2.length
          ? offset + length
          : segment.$1 + segment.$2.length;
      if (begin < end) {
        result.setRange(
          begin - offset,
          end - offset,
          segment.$2,
          begin - segment.$1,
        );
      }
    }
    return result;
  }

  @override
  Future<void> close() async => closed = true;
}

class _ChangingMagicSource implements koni.ByteSource {
  _ChangingMagicSource(this.inner);
  final _SparseSource inner;
  var sixByteReads = 0;
  @override
  int get length => inner.length;
  @override
  String? get name => inner.name;
  @override
  Future<Uint8List> read(int offset, int length) async {
    if (offset == 0 && length == 6 && ++sixByteReads == 1) {
      return Uint8List(6);
    }
    return inner.read(offset, length);
  }

  @override
  Future<void> close() => inner.close();
}

class _ChangingLengthSource implements koni.ByteSource {
  _ChangingLengthSource(this.inner);
  final _SparseSource inner;
  bool lengthChanged = false;
  final requestsAfterChange = <(int, int)>[];
  @override
  int get length => lengthChanged ? kArchiveStreamingLimit : inner.length;
  @override
  String? get name => inner.name;
  @override
  Future<Uint8List> read(int offset, int length) async {
    if (lengthChanged) requestsAfterChange.add((offset, length));
    final bytes = await inner.read(offset, length);
    if (offset == inner.headerOffset && length == inner.metadata.length) {
      lengthChanged = true;
    }
    return bytes;
  }

  @override
  Future<void> close() => inner.close();
}

void main() {
  Matcher limit(String detail) => throwsA(
    isA<ArchiveViewException>()
        .having(
          (e) => e is ArchivePasswordRequiredException,
          'password prompt',
          isFalse,
        )
        .having((e) => e.code, 'code', ArchiveMessageCode.archiveLimit)
        .having((e) => e.message, 'detail', contains(detail)),
  );
  Matcher corrupt() => throwsA(
    isA<ArchiveViewException>().having(
      (e) => e is ArchivePasswordRequiredException,
      'password prompt',
      isFalse,
    ),
  );

  test(
    'an ordinary Copy folder keeps lazy content reads and source ownership',
    () async {
      final source = _SparseSource(
        _plain(_streams(packedSizes: [4], outputs: [4])),
        payload: [1, 2, 3, 4],
      );
      final archive = await openViewerArchiveSource(source, name: 'small.7z');
      expect(source.closed, isFalse);
      expect(await archive.readMember(archive.members.single), [1, 2, 3, 4]);
      await archive.close();
      expect(source.closed, isTrue);
    },
  );

  test(
    'changed magic cannot auto-detect 7z after an uninspected first sniff',
    () async {
      final source = _ChangingMagicSource(
        _SparseSource(
          _plain(_streams(packedSizes: [4], outputs: [4])),
          payload: [1, 2, 3, 4],
        ),
      );
      await expectLater(
        openViewerArchiveSource(source, name: 'changing.7z'),
        corrupt(),
      );
      expect(source.inner.closed, isTrue);
    },
  );

  test(
    'encoded headers are decoded once then scanned as ordinary metadata',
    () async {
      final inner = _plain(_streams(packedSizes: [4], outputs: [4]));
      final outer = Uint8List.fromList([
        23,
        ..._streams(
          packedSizes: [inner.length],
          outputs: [inner.length],
          packPosition: 4,
        ),
      ]);
      final source = _SparseSource(outer, payload: [1, 2, 3, 4, ...inner]);
      final archive = await openViewerArchiveSource(source, name: 'encoded.7z');
      expect(await archive.readMember(archive.members.single), [1, 2, 3, 4]);
      await archive.close();
      expect(source.closed, isTrue);
    },
  );

  test(
    'checked metadata keeps captured geometry when the source length changes',
    () async {
      for (final encoded in [false, true]) {
        final header = _plain(
          _streams(packedSizes: [4], outputs: [4]),
          name: 'tiny.txt',
        );
        final metadata = encoded
            ? Uint8List.fromList([
                23,
                ..._streams(
                  packedSizes: [header.length],
                  outputs: [header.length],
                  packPosition: 4,
                ),
              ])
            : header;
        final source = _ChangingLengthSource(
          _SparseSource(
            metadata,
            payload: [1, 2, 3, 4, if (encoded) ...header],
          ),
        );
        final archive = await openViewerArchiveSource(
          source,
          name: 'changing-length.7z',
        );
        try {
          expect(source.lengthChanged, isTrue);
          expect(source.length, kArchiveStreamingLimit);
          expect(source.inner.length, lessThan(256));
          expect(archive.members.single.name, 'tiny.txt');
          expect(await archive.readMember(archive.members.single), [
            1,
            2,
            3,
            4,
          ]);
          expect(source.requestsAfterChange, isNotEmpty);
          // The checked header lives in the overlay, not at the new reported
          // end of the parent. No request may follow that changed geometry.
          expect(
            source.requestsAfterChange.every(
              (request) =>
                  request.$1 >= 0 &&
                  request.$2 <= source.inner.length - request.$1,
            ),
            isTrue,
          );
        } finally {
          await archive.close();
        }
        expect(source.inner.closed, isTrue);
      }
    },
  );

  test('an 8 GiB logical source cannot enter the buffered fallback', () async {
    final source = _SparseSource(
      _plain(_streams(packedSizes: [4], outputs: [4])),
      payload: [1, 2, 3, 4],
      size: kArchiveStreamingLimit,
    );
    await expectLater(
      openViewerArchiveSource(source, name: 'large.7z', password: 'supplied'),
      limit('whole input'),
    );
    expect(source.closed, isTrue);
    // The format registry may make a bounded ZIP end-record probe before
    // selecting 7z. It must never read an allocation-sized content range.
    expect(
      source.requests.every((request) => request.$2 <= 128 * 1024),
      isTrue,
    );
  });

  test(
    'the separate native streaming reader still accepts an 8 GiB source',
    () async {
      final source = _SparseSource(
        _plain(
          _streams(packedSizes: [4], outputs: [4]),
          name: 'small.txt',
        ),
        payload: [1, 2, 3, 4],
        size: kArchiveStreamingLimit,
      );
      final archive = await openStreamedSevenZipSource(source);
      expect(await archive.readMember(archive.members.single), [1, 2, 3, 4]);
      await archive.close();
      expect(source.closed, isTrue);
      expect(source.requests.every((request) => request.$2 <= 512), isTrue);
    },
  );

  test(
    'every declared packed size is capped before content can be opened',
    () async {
      final source = _SparseSource(
        _plain(
          _streams(
            packedSizes: [kArchiveReadLimit + 16],
            outputs: [1],
            coders: [_aes],
          ),
        ),
        size: 128 * 1024 * 1024,
      );
      await expectLater(
        openViewerArchiveSource(
          source,
          name: 'packed.7z',
          password: 'supplied',
        ),
        limit('packed stream'),
      );
      expect(source.closed, isTrue);
    },
  );

  test(
    'encoded-header ciphertext sizes are checked before invoking AES',
    () async {
      // Empty AES properties also prevent a large allocation if this regression
      // ever loses its preflight. The expected error must identify packed size.
      final source = _SparseSource(
        Uint8List.fromList([
          23,
          ..._streams(
            packedSizes: [kArchiveReadLimit + 16],
            outputs: [1],
            coders: [
              const _Coder([6, 0xf1, 7, 1], properties: []),
            ],
          ),
        ]),
        size: 128 * 1024 * 1024,
      );
      await expectLater(
        openViewerArchiveSource(
          source,
          name: 'ciphertext.7z',
          password: 'supplied',
        ),
        limit('packed stream'),
      );
      expect(source.closed, isTrue);
    },
  );

  for (final encoded in [false, true]) {
    test(
      '${encoded ? 'encoded' : 'plain'} stream extents cannot leave the source',
      () async {
        final streams = _streams(
          packedSizes: [16],
          outputs: [1],
          coders: [_aes],
          packPosition: 4096,
        );
        final source = _SparseSource(
          encoded ? Uint8List.fromList([23, ...streams]) : _plain(streams),
        );
        await expectLater(
          openViewerArchiveSource(
            source,
            name: 'range.7z',
            password: 'supplied',
          ),
          corrupt(),
        );
        expect(source.closed, isTrue);
        expect(
          source.requests.every(
            (request) => request.$1 + request.$2 <= source.length,
          ),
          isTrue,
        );
      },
    );
    test(
      '${encoded ? 'encoded' : 'plain'} cumulative packed extents cannot cross EOF',
      () async {
        final streams = _streams(packedSizes: [64, 64], outputs: [1]);
        final source = _SparseSource(
          encoded ? Uint8List.fromList([23, ...streams]) : _plain(streams),
          size: 100,
        );
        await expectLater(
          openViewerArchiveSource(source, name: 'cumulative.7z'),
          corrupt(),
        );
        expect(source.closed, isTrue);
      },
    );
  }

  test('a small final output cannot hide a huge AES intermediate', () async {
    final source = _SparseSource(
      _plain(
        _streams(
          packedSizes: [16],
          outputs: [kArchiveStreamingLimit, 1],
          coders: [_aes, _copy],
        ),
      ),
      payload: List.filled(16, 0),
    );
    await expectLater(
      openViewerArchiveSource(
        source,
        name: 'intermediate.7z',
        password: 'supplied',
      ),
      limit('coder output'),
    );
    expect(source.closed, isTrue);
  });

  test('unencrypted filtered intermediates have the same 64 MiB cap', () async {
    final source = _SparseSource(
      _plain(
        _streams(
          packedSizes: [1],
          outputs: [kArchiveReadLimit + 1, 1],
          coders: [_copy, _delta],
        ),
      ),
      payload: [1],
    );
    await expectLater(
      openViewerArchiveSource(
        source,
        name: 'filter.7z',
        maxMemberBytes: kArchiveStreamingLimit,
      ),
      limit('coder output'),
    );
    expect(source.closed, isTrue);
  });

  test(
    'encoded-header intermediate allocation respects a smaller caller budget',
    () async {
      final source = _SparseSource(
        Uint8List.fromList([
          23,
          ..._streams(
            packedSizes: [1],
            outputs: [129, 1],
            coders: [_copy, _delta],
          ),
        ]),
        payload: [1],
      );
      await expectLater(
        openViewerArchiveSource(
          source,
          name: 'header-filter.7z',
          maxMemberBytes: 128,
        ),
        limit('coder output'),
      );
      expect(source.closed, isTrue);
    },
  );

  test(
    'a decoded header cannot introduce unchecked intermediate sizes',
    () async {
      final inner = _plain(
        _streams(
          packedSizes: [16],
          outputs: [kArchiveStreamingLimit, 1],
          coders: [_aes, _copy],
        ),
      );
      final source = _SparseSource(
        Uint8List.fromList([
          23,
          ..._streams(
            packedSizes: [inner.length],
            outputs: [inner.length],
            packPosition: 16,
          ),
        ]),
        payload: [...List.filled(16, 0), ...inner],
      );
      await expectLater(
        openViewerArchiveSource(source, name: 'inner.7z', password: 'supplied'),
        limit('coder output'),
      );
      expect(source.closed, isTrue);
    },
  );

  for (final encoded in [false, true]) {
    test(
      '${encoded ? 'encoded' : 'plain'} AES KDF above 2^20 is refused before derivation',
      () async {
        final streams = _streams(
          packedSizes: [16],
          outputs: [1],
          coders: [
            const _Coder([6, 0xf1, 7, 1], properties: [39]),
          ],
        );
        final source = _SparseSource(
          encoded ? Uint8List.fromList([23, ...streams]) : _plain(streams),
          payload: List.filled(16, 0),
        );
        await expectLater(
          openViewerArchiveSource(source, name: 'kdf.7z', password: 'supplied'),
          throwsA(
            isA<ArchiveViewException>().having(
              (e) => e.message,
              'detail',
              contains('2^20'),
            ),
          ),
        );
        expect(source.closed, isTrue);
      },
    );
  }

  test(
    'hostile complex-coder counts fail before unbounded binding metadata',
    () async {
      final source = _SparseSource(
        Uint8List.fromList([
          1,
          4,
          6,
          0,
          1,
          9,
          0,
          0,
          7,
          11,
          1,
          0,
          1,
          0x11,
          0,
          1,
          ..._number(1 << 40),
          0,
        ]),
      );
      await expectLater(
        openViewerArchiveSource(source, name: 'graph.7z'),
        corrupt(),
      );
      expect(source.closed, isTrue);
    },
  );

  for (final coder in const [
    _Coder([3, 1, 1], properties: [0x5d, 0, 0, 0, 0x80]),
    _Coder([0x21], properties: [40]),
  ]) {
    for (final encoded in [false, true]) {
      test(
        '${coder.id} ${encoded ? 'encoded' : 'plain'} tiny output cannot advertise a huge dictionary',
        () async {
          final streams = _streams(
            packedSizes: [1],
            outputs: [1],
            coders: [coder],
          );
          final source = _SparseSource(
            encoded ? Uint8List.fromList([23, ...streams]) : _plain(streams),
            payload: [0],
          );
          await expectLater(
            openViewerArchiveSource(source, name: 'dictionary.7z'),
            limit('dictionary'),
          );
          expect(source.closed, isTrue);
        },
      );
    }
  }

  test(
    'aggregate coder graphs are bounded before upstream metadata allocation',
    () async {
      // About 0.6 MiB of metadata and no data: each individually valid graph
      // has 64 inputs and outputs, so per-folder bounds alone are insufficient.
      const count = 3126;
      final metadata = BytesBuilder(copy: false)
        ..add([1, 4, 6, 0, ..._number(count), 9])
        ..add(Uint8List(count))
        ..add([0, 7, 11, ..._number(count), 0]);
      for (var i = 0; i < count; i++) {
        metadata.add([
          1,
          0x11,
          0,
          64,
          64,
          for (var stream = 1; stream < 64; stream++) ...[stream, stream - 1],
        ]);
      }
      metadata
        ..addByte(12)
        ..add(Uint8List(count * 64))
        ..add([0, 0, 0]);
      final source = _SparseSource(metadata.takeBytes());
      await expectLater(
        openViewerArchiveSource(source, name: 'many-graphs.7z'),
        throwsA(
          isA<ArchiveViewException>().having(
            (e) => e.message,
            'bounded graph count',
            contains('400000'),
          ),
        ),
      );
      expect(source.closed, isTrue);
    },
  );

  test(
    'repeated file vectors cannot repeatedly allocate the full entry count',
    () async {
      final source = _SparseSource(
        Uint8List.fromList([1, 5, 1, 14, 1, 0x80, 14, 1, 0x80, 0, 0]),
      );
      await expectLater(
        openViewerArchiveSource(source, name: 'repeated.7z'),
        corrupt(),
      );
      expect(source.closed, isTrue);
    },
  );

  test(
    'truncated metadata and invalid CRC remain ordinary corruption errors',
    () async {
      final header = _plain(_streams(packedSizes: [4], outputs: [4]));
      for (var cut = 1; cut < header.length; cut++) {
        final source = _SparseSource(
          Uint8List.sublistView(header, 0, cut),
          payload: [1, 2, 3, 4],
        );
        await expectLater(
          openViewerArchiveSource(
            source,
            name: 'truncated.7z',
            password: 'unused',
          ),
          corrupt(),
        );
        expect(source.closed, isTrue);
      }
      final source = _SparseSource(header, payload: [1, 2, 3, 4]);
      source.metadata.last ^= 1;
      await expectLater(
        openViewerArchiveSource(source, name: 'bad-crc.7z', password: 'unused'),
        corrupt(),
      );
      expect(source.closed, isTrue);
    },
  );
}
