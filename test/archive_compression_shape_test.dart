import 'dart:typed_data';

import 'package:archive/archive.dart' as codec;
import 'package:crisp_cloud/services/archive_compression_writer.dart';
import 'package:crisp_cloud/services/archive_endpoint_policy.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

const _suffixes = <ArchiveCompressionKind, String>{
  ArchiveCompressionKind.gzip: 'gz',
  ArchiveCompressionKind.bzip2: 'bz2',
  ArchiveCompressionKind.xz: 'xz',
  ArchiveCompressionKind.zstd: 'zst',
  ArchiveCompressionKind.lz4: 'lz4',
  ArchiveCompressionKind.lzma: 'lzma',
};

final _payload = Uint8List.fromList('ordinary member contents'.codeUnits);

Future<Uint8List> _sevenZip() async {
  final sink = koni.BytesBuilderSink();
  final writer = koni.Archive.create(
    sink,
    format: const koni.SevenZWriteFormat(),
  );
  await writer.addBytes(koni.ArchiveEntrySpec(path: 'member.txt'), _payload);
  await writer.close();
  await sink.close();
  return sink.takeBytes();
}

// A small independent UNIX-compress wire fixture using only 9-bit literal
// codes. No dictionary codes, resets, or width changes are needed for this 7z.
Uint8List _literalCompress(Uint8List payload) {
  final bytes = <int>[0x1f, 0x9d, 9];
  var accumulator = 0, bits = 0;
  for (final byte in payload) {
    accumulator |= byte << bits;
    bits += 9;
    while (bits >= 8) {
      bytes.add(accumulator & 255);
      accumulator >>= 8;
      bits -= 8;
    }
  }
  if (bits != 0) bytes.add(accumulator & 255);
  return Uint8List.fromList(bytes);
}

Future<void> _inspect(
  Uint8List bytes,
  String name, {
  required List<int> visibleBytes,
  required bool writable,
  required bool direct,
  bool singlePayload = true,
  String? readerFormat,
}) async {
  final original = Uint8List.fromList(bytes);
  final archive = await openViewerArchive(bytes, name: name);
  try {
    expect(archive.members.length, 1);
    expect(archive.isDirectCompressionPayload, direct);
    expect(await archive.readMember(archive.members.single), visibleBytes);
    if (readerFormat != null) expect(archive.formatName, readerFormat);
    final policy = await ArchiveEndpointPolicy.inspect(
      bytes,
      name,
      archive,
      null,
    );
    expect(policy.singlePayload, singlePayload);
    expect(policy.reason == null, writable, reason: policy.reason ?? name);
  } finally {
    await archive.close();
  }
  // Inspection and readback must never rewrite either a framing header or its
  // payload in the caller's original container buffer.
  expect(bytes, original);
}

void main() {
  for (final outer in ArchiveCompressionKind.values) {
    final suffix = _suffixes[outer]!;
    test(
      '${outer.name} immediate payload stays writable through the public reader facade',
      () async {
        await _inspect(
          encodeArchiveCompression(_payload, outer),
          'payload.$suffix',
          visibleBytes: _payload,
          writable: true,
          direct: true,
        );
      },
    );

    test(
      '${outer.name} recursive same-codec expansion cannot become a one-layer rewrite',
      () async {
        final inner = encodeArchiveCompression(_payload, outer);
        final original = encodeArchiveCompression(inner, outer);
        await _inspect(
          original,
          'payload.$suffix.$suffix',
          visibleBytes: _payload,
          writable: false,
          direct: false,
        );
        expect(decompressSingleFile(original, 'payload.$suffix').data, inner);
      },
    );

    final innerKind = ArchiveCompressionKind
        .values[(outer.index + 1) % ArchiveCompressionKind.values.length];
    test(
      '${outer.name} with nested ${innerKind.name} remains read-only after expansion',
      () async {
        await _inspect(
          encodeArchiveCompression(
            encodeArchiveCompression(_payload, innerKind),
            outer,
          ),
          'payload.${_suffixes[innerKind]}.$suffix',
          visibleBytes: _payload,
          writable: false,
          direct: false,
        );
      },
    );

    test(
      'one ${outer.name} wrapper around TAR retains its supported rewrite path',
      () async {
        final tar = Uint8List.fromList(
          codec.TarEncoder().encode(
            codec.Archive()
              ..addFile(codec.ArchiveFile.bytes('member.txt', _payload)),
          ),
        );
        await _inspect(
          encodeArchiveCompression(tar, outer),
          'payload.tar.$suffix',
          visibleBytes: _payload,
          writable: true,
          direct: false,
          singlePayload: false,
          readerFormat: 'tar',
        );
      },
    );
  }

  for (final kind in ArchiveCompressionKind.values.where(
    (kind) => kind != ArchiveCompressionKind.lzma,
  )) {
    test(
      '${kind.name} magic detects the inner wrapper even with only one filename suffix',
      () async {
        await _inspect(
          encodeArchiveCompression(
            encodeArchiveCompression(_payload, kind),
            kind,
          ),
          'misleading.${_suffixes[kind]}',
          visibleBytes: _payload,
          writable: false,
          direct: false,
        );
      },
    );
  }

  for (final outer in [
    ArchiveCompressionKind.lz4,
    ArchiveCompressionKind.lzma,
  ]) {
    test(
      'unhinted inner LZMA is an immediate byte payload inside ${outer.name}',
      () async {
        final inner = encodeArchiveCompression(
          _payload,
          ArchiveCompressionKind.lzma,
        );
        await _inspect(
          encodeArchiveCompression(inner, outer),
          'payload.${_suffixes[outer]}',
          visibleBytes: inner,
          writable: true,
          direct: true,
        );
      },
    );
  }

  test('LZMA-alone requires its explicit name hint', () async {
    final bytes = encodeArchiveCompression(
      _payload,
      ArchiveCompressionKind.lzma,
    );
    final original = Uint8List.fromList(bytes);
    await expectLater(
      openViewerArchive(bytes, name: 'payload.bin'),
      throwsA(isA<ArchiveViewException>()),
    );
    await expectLater(
      openViewerArchive(bytes, name: 'payload.lz4'),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(bytes, original);
  });

  test(
    'framed LZ4 renamed as LZMA reads by magic but cannot rewrite as LZMA',
    () async {
      final bytes = encodeArchiveCompression(
        _payload,
        ArchiveCompressionKind.lz4,
      );
      await _inspect(
        bytes,
        'misleading.lzma',
        visibleBytes: _payload,
        writable: false,
        direct: true,
        readerFormat: 'lz4',
      );
      expect(decompressSingleFile(bytes, 'misleading.lzma').data, _payload);
    },
  );

  test('ordinary ZIP magic wins over an LZMA name hint', () async {
    final zip = Uint8List.fromList(
      codec.ZipEncoder().encode(
        codec.Archive()
          ..addFile(codec.ArchiveFile.bytes('member.txt', _payload)),
      ),
    );
    await _inspect(
      zip,
      'misleading.lzma',
      visibleBytes: _payload,
      writable: false,
      direct: false,
      readerFormat: 'zip',
    );
  });

  test(
    'plain TAR renamed as compressed TAR is not a writable compression profile',
    () async {
      final tar = Uint8List.fromList(
        codec.TarEncoder().encode(
          codec.Archive()
            ..addFile(codec.ArchiveFile.bytes('member.txt', _payload)),
        ),
      );
      await _inspect(
        tar,
        'misleading.tar.lzma',
        visibleBytes: _payload,
        writable: false,
        direct: false,
        singlePayload: false,
        readerFormat: 'tar',
      );
    },
  );

  test('the wrapper depth bound applies before another expansion', () async {
    var bytes = _payload;
    for (var i = 0; i < 4; i++) {
      bytes = encodeArchiveCompression(bytes, ArchiveCompressionKind.lz4);
    }
    await _inspect(
      bytes,
      'payload.lz4',
      visibleBytes: _payload,
      writable: false,
      direct: false,
    );
    final fifth = encodeArchiveCompression(bytes, ArchiveCompressionKind.lz4);
    await expectLater(
      openViewerArchive(fifth, name: 'payload.lz4'),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  for (final kind in [
    ArchiveCompressionKind.lz4,
    ArchiveCompressionKind.zstd,
  ]) {
    test(
      'skippable ${kind.name} around 7z cannot rewrite a misleading .7z filename',
      () async {
        final wrapped = encodeArchiveCompression(await _sevenZip(), kind);
        await _inspect(
          Uint8List.fromList([
            0x50,
            0x2a,
            0x4d,
            0x18,
            3,
            0,
            0,
            0,
            1,
            2,
            3,
            ...wrapped,
          ]),
          'misleading.7z',
          visibleBytes: _payload,
          writable: false,
          direct: false,
          singlePayload: false,
          readerFormat: '7z',
        );
      },
    );
  }

  test(
    'readonly UNIX compress around 7z cannot rewrite a misleading .7z filename',
    () async {
      await _inspect(
        _literalCompress(await _sevenZip()),
        'misleading.7z',
        visibleBytes: _payload,
        writable: false,
        direct: false,
        singlePayload: false,
        readerFormat: '7z',
      );
    },
  );

  test(
    'an outer decoded wrapper cannot bypass its payload size bound',
    () async {
      final inner = encodeArchiveCompression(
        _payload,
        ArchiveCompressionKind.lz4,
      );
      expect(inner.length, greaterThan(_payload.length));
      final outer = encodeArchiveCompression(inner, ArchiveCompressionKind.lz4);
      await expectLater(
        openViewerArchive(
          outer,
          name: 'payload.lz4',
          maxMemberBytes: _payload.length,
        ),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );
}
