import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:crisp_cloud/services/archive_sfx_source.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_sfx_fixtures.dart';

class _Source implements koni.ByteSource {
  _Source(Uint8List bytes) : this.sparse(bytes.length, {0: bytes});
  _Source.sparse(this.length, this.regions);

  @override
  int length;
  final Map<int, Uint8List> regions;
  final reads = <({int offset, int length})>[];
  int closes = 0;
  bool shortRead = false;
  bool throwRead = false;
  Completer<void>? block;

  @override
  String get name => 'fixture.exe';

  @override
  Future<Uint8List> read(int offset, int count) async {
    reads.add((offset: offset, length: count));
    if (throwRead) throw StateError('Injected input failure.');
    if (offset < 0 || count < 0 || offset > length || count > length - offset) {
      throw StateError('Unexpected out-of-range request.');
    }
    if (closes != 0) throw StateError('Unexpected read after source close.');
    await block?.future;
    final bytes = Uint8List(shortRead && count > 0 ? count - 1 : count);
    for (final region in regions.entries) {
      final begin = offset > region.key ? offset : region.key;
      final end = offset + bytes.length < region.key + region.value.length
          ? offset + bytes.length
          : region.key + region.value.length;
      if (begin < end) {
        bytes.setRange(
          begin - offset,
          end - offset,
          region.value,
          begin - region.key,
        );
      }
    }
    return bytes;
  }

  @override
  Future<void> close() async => closes++;
}

Future<koni.ArchiveReader> _reader(
  ArchiveSfxSource source, {
  String? password,
}) => koni.builtInFormats.openReader(
  source,
  options: koni.ArchiveReadOptions(
    password: password,
    maxEntrySize: kArchiveReadLimit,
    maxEntryCount: 200000,
    maxContainerDecodeSize: kArchiveReadLimit,
  ),
);

Future<Uint8List> _member(koni.ArchiveReader reader, String name) async {
  final entry = reader.entries.singleWhere((entry) => entry.path == name);
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in reader.openRead(entry)) {
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

Uint8List _fixture(String name) =>
    File('test/fixtures/archives/$name').readAsBytesSync();

Uint8List _simpleZip(String name, String text, {String? password}) =>
    Uint8List.fromList(
      ar.ZipEncoder(password: password).encode(
        ar.Archive()..addFile(ar.ArchiveFile.bytes(name, utf8.encode(text))),
      ),
    );

void _u16(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(bytes).setUint16(offset, value, Endian.little);

void _u32(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(bytes).setUint32(offset, value, Endian.little);

int _get32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint32(offset, Endian.little);

int _central(Uint8List bytes) =>
    sfxPayloadOffset + _get32(bytes, bytes.length - 6);

Future<void> _reject(
  Uint8List bytes, {
  ArchiveMessageCode? code,
  String? message,
}) async {
  final owner = _Source(bytes);
  await expectLater(
    openPeSfxSource(owner),
    throwsA(
      isA<ArchiveViewException>()
          .having((error) => error.code, 'code', code ?? anything)
          .having(
            (error) => error.message,
            'message',
            message == null ? anything : contains(message),
          ),
    ),
  );
  expect(owner.closes, 1);
}

void main() {
  group('independent archive payloads', () {
    for (final pe64 in [false, true]) {
      for (final absolute in [false, true]) {
        test(
          'Python ZIP, PE${pe64 ? 64 : 32}, ${absolute ? 'absolute' : 'relative'} offsets',
          () async {
            var zip = sfxReferenceZip();
            if (absolute) zip = sfxAbsoluteZipOffsets(zip, sfxPayloadOffset);
            final owner = _Source(sfxPeArchive(zip, pe64: pe64));
            final source = await openPeSfxSource(owner);
            expect(source.archiveKind, 'zip');
            expect(source.payloadOffset, sfxPayloadOffset);
            expect(source.length, owner.length);
            final reader = await _reader(source);
            expect(
              reader.entries.map((entry) => entry.path),
              containsAll(['readme.txt', 'docs/empty', '日本語/名前.txt']),
            );
            expect(
              utf8.decode(await _member(reader, 'readme.txt')),
              'SFX payload\n',
            );
            expect(
              utf8.decode(await _member(reader, '日本語/名前.txt')),
              'hello from a ZIP overlay\n',
            );
            await reader.close();
            await source.close();
            await source.close();
            expect(owner.closes, 1);
          },
        );
      }
    }

    test('ARM64 PE32+ accepts the same bounded archive profile', () async {
      final source = await openPeSfxSource(
        _Source(sfxPeArchive(sfxReferenceZip(), pe64: true, arm64: true)),
      );
      addTearDown(source.close);
      expect(source.archiveKind, 'zip');
      final reader = await _reader(source);
      addTearDown(reader.close);
      expect(utf8.decode(await _member(reader, 'readme.txt')), 'SFX payload\n');
    });

    test('7-Zip-produced 7z opens through its exact offset slice', () async {
      final payload = _fixture('sample.7z');
      final owner = _Source(sfxPeArchive(payload));
      final source = await openPeSfxSource(owner);
      addTearDown(source.close);
      expect(source.archiveKind, '7z');
      expect(source.length, payload.length);
      expect(await source.read(0, 6), payload.sublist(0, 6));
      final reader = await _reader(source);
      addTearDown(reader.close);
      expect((await _member(reader, 'nested/deep/data.bin')).length, 100000);
    });

    test('7z encrypted header keeps the normal password boundary', () async {
      final source = await openPeSfxSource(
        _Source(sfxPeArchive(_fixture('header_encrypted.7z'))),
      );
      addTearDown(source.close);
      await expectLater(
        _reader(source),
        throwsA(isA<koni.EncryptedArchiveException>()),
      );
      final reader = await _reader(source, password: 'secret');
      addTearDown(reader.close);
      expect(await _member(reader, 'hello.txt'), isNotEmpty);
    });

    test('RAR4 external fixture decodes its filtered member', () async {
      final source = await openPeSfxSource(
        _Source(sfxPeArchive(_fixture('sample.rar'))),
      );
      addTearDown(source.close);
      expect(source.archiveKind, 'rar');
      final reader = await _reader(source);
      addTearDown(reader.close);
      expect((await _member(reader, 'grad.bmp')).length, 27702);
    });

    test('RAR4 encrypted payload retains password handling', () async {
      final source = await openPeSfxSource(
        _Source(sfxPeArchive(_fixture('encrypted.rar'))),
      );
      addTearDown(source.close);
      final reader = await _reader(source, password: 'secret');
      addTearDown(reader.close);
      expect(utf8.decode(await _member(reader, 'hello.txt')), 'hello, rar!\n');
    });

    test(
      'RAR5 external compressed fixture decodes after the PE prefix',
      () async {
        final source = await openPeSfxSource(
          _Source(sfxPeArchive(sfxReferenceRar5())),
        );
        addTearDown(source.close);
        final reader = await _reader(source);
        addTearDown(reader.close);
        expect(
          utf8.decode(await _member(reader, 'hello.txt')),
          'hello, rar!\n',
        );
        expect(
          utf8.decode(await _member(reader, 'story.txt')),
          contains('quick brown fox'),
        );
      },
    );

    test('RAR5 encrypted headers retain the typed password request', () async {
      final source = await openPeSfxSource(
        _Source(sfxPeArchive(sfxReferenceEncryptedRar5())),
      );
      addTearDown(source.close);
      await expectLater(
        _reader(source),
        throwsA(isA<koni.EncryptedArchiveException>()),
      );
      final reader = await _reader(source, password: 'secret');
      addTearDown(reader.close);
      expect(utf8.decode(await _member(reader, 'hello.txt')), 'hello, rar!\n');
    });

    test('empty ZIP remains an empty read-only executable archive', () async {
      final empty = Uint8List(22)
        ..[0] = 0x50
        ..[1] = 0x4b
        ..[2] = 5
        ..[3] = 6;
      final source = await openPeSfxSource(_Source(sfxPeArchive(empty)));
      addTearDown(source.close);
      final reader = await _reader(source);
      addTearDown(reader.close);
      expect(reader.entries, isEmpty);
      expect(ArchiveSfxSource.notices.join(' '), contains('never run'));
      expect(ArchiveSfxSource.notices.join(' '), contains('not authenticated'));
    });

    test('traversal names remain flagged by the normal reader', () async {
      final source = await openPeSfxSource(
        _Source(sfxPeArchive(_simpleZip('../escape.txt', 'unsafe'))),
      );
      addTearDown(source.close);
      final reader = await _reader(source);
      addTearDown(reader.close);
      expect(reader.entries.single.pathEscapedRoot, isTrue);
    });
  });

  group('PE layout validation', () {
    final cases = <String, void Function(Uint8List)>{
      'DOS magic': (bytes) => bytes[0] = 0,
      'PE offset before DOS header': (bytes) => _u32(bytes, 60, 32),
      'PE offset beyond prefix limit': (bytes) => _u32(bytes, 60, 0xffffffff),
      'PE signature': (bytes) => bytes[sfxPeOffset] = 0,
      'no sections': (bytes) => _u16(bytes, sfxPeOffset + 6, 0),
      'too many sections': (bytes) => _u16(bytes, sfxPeOffset + 6, 97),
      'object file': (bytes) => _u16(bytes, sfxPeOffset + 22, 0),
      'DLL': (bytes) => _u16(bytes, sfxPeOffset + 22, 0x2002),
      'COFF symbols': (bytes) => _u32(bytes, sfxPeOffset + 12, 1024),
      'COFF symbol count': (bytes) => _u32(bytes, sfxPeOffset + 16, 1),
      'short optional header': (bytes) => _u16(bytes, sfxPeOffset + 20, 95),
      'oversized optional header': (bytes) =>
          _u16(bytes, sfxPeOffset + 20, 4097),
      'unknown optional header': (bytes) =>
          _u16(bytes, sfxOptionalOffset, 0x107),
      'machine mismatch': (bytes) => _u16(bytes, sfxPeOffset + 4, 0x8664),
      'unaligned file': (bytes) => _u32(bytes, sfxOptionalOffset + 36, 513),
      'small section alignment': (bytes) =>
          _u32(bytes, sfxOptionalOffset + 32, 512),
      'header table out of bounds': (bytes) =>
          _u32(bytes, sfxOptionalOffset + 60, 256),
      'unaligned image size': (bytes) =>
          _u32(bytes, sfxOptionalOffset + 56, 8193),
      'unmapped entry point': (bytes) =>
          _u32(bytes, sfxOptionalOffset + 16, 0x3000),
      'missing entry point': (bytes) => _u32(bytes, sfxOptionalOffset + 16, 0),
      'unknown data directories': (bytes) =>
          _u32(bytes, sfxOptionalOffset + 92, 17),
      'certificate pointer': (bytes) =>
          _u32(bytes, sfxOptionalOffset + 96 + 4 * 8, 1024),
      'certificate size only': (bytes) =>
          _u32(bytes, sfxOptionalOffset + 96 + 4 * 8 + 4, 32),
      'unmapped resource': (bytes) {
        _u32(bytes, sfxOptionalOffset + 96 + 2 * 8, 0x3000);
        _u32(bytes, sfxOptionalOffset + 96 + 2 * 8 + 4, 4);
      },
      'reserved directory': (bytes) {
        _u32(bytes, sfxOptionalOffset + 96 + 15 * 8, 0x1000);
        _u32(bytes, sfxOptionalOffset + 96 + 15 * 8 + 4, 4);
      },
      'section inside headers': (bytes) =>
          _u32(bytes, sfxOptionalOffset + 224 + 20, 0),
      'section beyond source': (bytes) =>
          _u32(bytes, sfxOptionalOffset + 224 + 20, 4096),
      'unaligned section extent': (bytes) =>
          _u32(bytes, sfxOptionalOffset + 224 + 16, 511),
      'section outside virtual image': (bytes) =>
          _u32(bytes, sfxOptionalOffset + 224 + 12, 0x2000),
      'section relocation': (bytes) =>
          _u32(bytes, sfxOptionalOffset + 224 + 24, 512),
    };
    for (final entry in cases.entries) {
      test('refuses ${entry.key} and closes its source', () async {
        final bytes = sfxPeArchive(sfxReferenceZip());
        entry.value(bytes);
        await _reject(bytes);
      });
    }

    test(
      'refuses overlapping physical sections even with distinct RVAs',
      () async {
        final bytes = sfxPeArchive(sfxReferenceZip());
        _u16(bytes, sfxPeOffset + 6, 2);
        const first = sfxOptionalOffset + 224;
        bytes.setRange(first + 40, first + 80, bytes, first);
        _u32(bytes, first + 40 + 12, 0x2000);
        _u32(bytes, sfxOptionalOffset + 56, 0x3000);
        await _reject(bytes, message: 'raw sections overlap');
      },
    );

    test(
      'does not mistake an archive inside a PE section for an overlay',
      () async {
        final zip = _simpleZip('inside.txt', 'not an overlay');
        final bytes = Uint8List.fromList([
          ...sfxPeStub(),
          ...List.filled(64, 0),
        ]);
        bytes.setRange(512, 512 + zip.length, zip);
        await _reject(bytes, message: 'overlay is not a supported');
      },
    );

    test(
      'does not scan past unexplained installer metadata or padding',
      () async {
        final bytes = sfxPeArchive(
          Uint8List.fromList([0, 0, 0, 0, ...sfxReferenceZip()]),
        );
        await _reject(bytes, message: 'overlay is not a supported');
      },
    );

    test(
      'mapped debug records can be inspected without external data',
      () async {
        final bytes = sfxPeArchive(sfxReferenceZip());
        _u32(bytes, sfxOptionalOffset + 96 + 6 * 8, 0x1010);
        _u32(bytes, sfxOptionalOffset + 96 + 6 * 8 + 4, 28);
        _u32(bytes, 528 + 16, 4);
        _u32(bytes, 528 + 20, 0x1030);
        _u32(bytes, 528 + 24, 560);
        final source = await openPeSfxSource(_Source(bytes));
        await source.close();
      },
    );

    test(
      'rejects debug data using the archive overlay as debug storage',
      () async {
        final bytes = sfxPeArchive(sfxReferenceZip());
        _u32(bytes, sfxOptionalOffset + 96 + 6 * 8, 0x1010);
        _u32(bytes, sfxOptionalOffset + 96 + 6 * 8 + 4, 28);
        _u32(bytes, 528 + 16, 4);
        _u32(bytes, 528 + 24, sfxPayloadOffset);
        await _reject(bytes, message: 'debug data');
      },
    );

    test(
      'oversized sparse PE prefix is refused without reading that prefix',
      () async {
        final header = sfxPeStub(
          rawSectionStart: kArchiveSfxStubLimit,
          headersOnly: true,
        );
        final owner = _Source.sparse(kArchiveSfxStubLimit + 512 + 100, {
          0: header,
        });
        await expectLater(
          openPeSfxSource(owner),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(
          owner.reads.every((read) => read.offset < 512 && read.length <= 224),
          isTrue,
        );
        expect(owner.closes, 1);
      },
    );
  });

  group('archive framing and bounds', () {
    test('accepts a five-GiB sparse ZIP64 using metadata-only reads', () async {
      for (final absolute in [false, true]) {
        final fixture = sfxSparseZip64(absoluteOffsets: absolute);
        final owner = _Source.sparse(fixture.length, fixture.regions);
        final source = await openPeSfxSource(owner);
        final reader = await _reader(source);
        expect(reader.entries.single.uncompressedSize, 5 * 1024 * 1024 * 1024);
        expect(
          owner.reads.fold<int>(0, (sum, read) => sum + read.length),
          lessThan(250000),
        );
        expect(
          owner.reads
              .map((read) => read.length)
              .reduce((a, b) => a > b ? a : b),
          lessThanOrEqualTo(65557),
        );
        await reader.close();
        await source.close();
        expect(owner.closes, 1);
      }
    });

    test('ZIP central offsets cannot invent another overlay start', () async {
      final bytes = sfxPeArchive(sfxReferenceZip());
      _u32(bytes, bytes.length - 6, _get32(bytes, bytes.length - 6) + 1);
      await _reject(bytes, message: 'ambiguous archive offsets');
    });

    test('ZIP members cannot point into the executable prefix', () async {
      final bytes = sfxPeArchive(
        sfxAbsoluteZipOffsets(sfxReferenceZip(), sfxPayloadOffset),
      );
      final central = _get32(bytes, bytes.length - 6);
      _u32(bytes, central + 42, 512);
      await _reject(bytes, message: 'points into the executable');
    });

    test('ZIP local/central names must match', () async {
      final bytes = sfxPeArchive(sfxReferenceZip());
      bytes[sfxPayloadOffset + 30] ^= 1;
      await _reject(bytes, message: 'member names disagree');
    });

    test('ZIP local/central sizes must match', () async {
      final bytes = sfxPeArchive(sfxReferenceZip());
      _u32(bytes, sfxPayloadOffset + 18, 1);
      await _reject(bytes, message: 'sizes/checksums disagree');
    });

    test('ZIP payload data cannot overlap its directory', () async {
      final bytes = sfxPeArchive(sfxReferenceZip());
      _u32(bytes, _central(bytes) + 20, bytes.length);
      await _reject(bytes, message: 'data leaves its archive region');
    });

    test(
      'ZIP64 locator offsets cannot use a third coordinate origin',
      () async {
        final fixture = sfxSparseZip64();
        final end = fixture.regions.entries.last.value;
        _u32(end, 64, _get32(end, 64) + 1);
        final owner = _Source.sparse(fixture.length, fixture.regions);
        await expectLater(
          openPeSfxSource(owner),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(owner.closes, 1);
      },
    );

    test('ZIP64 unsafe integer values never become file reads', () async {
      final fixture = sfxSparseZip64();
      final end = fixture.regions.entries.last.value;
      _u32(end, 68, 0x200000);
      final owner = _Source.sparse(fixture.length, fixture.regions);
      await expectLater(
        openPeSfxSource(owner),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(owner.closes, 1);
      expect(
        owner.reads.every((read) => read.offset <= fixture.length),
        isTrue,
      );
    });

    test(
      'ZIP end record and comment must reach the exact physical end',
      () async {
        await _reject(
          Uint8List.fromList([...sfxPeArchive(sfxReferenceZip()), 0]),
        );
      },
    );

    test('split ZIP is explicitly unsupported', () async {
      final bytes = sfxPeArchive(sfxReferenceZip());
      _u16(bytes, bytes.length - 22 + 4, 1);
      await _reject(bytes, message: 'Split-volume');
    });

    test('7z start-header checksum is checked before using offsets', () async {
      final bytes = sfxPeArchive(_fixture('sample.7z'));
      bytes[sfxPayloadOffset + 12] ^= 1;
      await _reject(
        bytes,
        code: ArchiveMessageCode.corrupt,
        message: 'start-header checksum',
      );
    });

    test(
      '7z next-header checksum is checked before handing to decoder',
      () async {
        final bytes = sfxPeArchive(_fixture('sample.7z'));
        bytes[bytes.length - 1] ^= 1;
        await _reject(
          bytes,
          code: ArchiveMessageCode.corrupt,
          message: 'next-header checksum',
        );
      },
    );

    test('7z trailing data is not accepted as part of the payload', () async {
      await _reject(
        Uint8List.fromList([...sfxPeArchive(_fixture('sample.7z')), 0]),
        message: 'trailing data',
      );
    });

    test('RAR4 public header CRC is checked', () async {
      final bytes = sfxPeArchive(_fixture('sample.rar'));
      bytes[sfxPayloadOffset + 7] ^= 1;
      await _reject(bytes, message: 'RAR4 SFX header checksum');
    });

    test('RAR5 public header CRC is checked', () async {
      final bytes = sfxPeArchive(sfxReferenceRar5());
      bytes[sfxPayloadOffset + 8] ^= 1;
      await _reject(bytes, message: 'RAR5 SFX header checksum');
    });

    test('truncated archive signatures/headers close the source', () async {
      for (final payload in [
        Uint8List.fromList([0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]),
        Uint8List.fromList([0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0]),
        Uint8List.fromList([0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 1, 0]),
      ]) {
        await _reject(sfxPeArchive(payload));
      }
    });

    test('metadata budget is checked before a directory allocation', () async {
      final owner = _Source(sfxPeArchive(sfxReferenceZip()));
      await expectLater(
        openPeSfxSource(owner, maxMetadataBytes: 512),
        throwsA(
          isA<ArchiveViewException>().having(
            (error) => error.code,
            'code',
            ArchiveMessageCode.archiveLimit,
          ),
        ),
      );
      expect(owner.closes, 1);
    });
  });

  group('source ownership and positional reads', () {
    test(
      'short metadata reads and input failures close exactly once',
      () async {
        for (final short in [false, true]) {
          final owner = _Source(sfxPeArchive(sfxReferenceZip()))
            ..shortRead = short
            ..throwRead = !short;
          await expectLater(openPeSfxSource(owner), throwsA(anything));
          expect(owner.closes, 1);
        }
      },
    );

    test('bad configuration still releases ownership', () async {
      final owner = _Source(sfxPeArchive(sfxReferenceZip()));
      await expectLater(
        openPeSfxSource(owner, maxStubBytes: 1),
        throwsArgumentError,
      );
      expect(owner.closes, 1);
    });

    test('range validation precedes source I/O', () async {
      final owner = _Source(sfxPeArchive(_fixture('sample.7z')));
      final source = await openPeSfxSource(owner);
      addTearDown(source.close);
      final calls = owner.reads.length;
      await expectLater(source.read(-1, 0), throwsArgumentError);
      await expectLater(source.read(0, -1), throwsArgumentError);
      await expectLater(
        source.read(source.length, 1),
        throwsA(isA<koni.UnexpectedEofException>()),
      );
      await expectLater(
        source.read(source.length + 1, 0),
        throwsA(isA<koni.UnexpectedEofException>()),
      );
      expect(owner.reads.length, calls);
      expect(await source.read(source.length, 0), isEmpty);
    });

    test('concurrent positional reads retain their original offsets', () async {
      final payload = _fixture('sample.7z');
      final owner = _Source(sfxPeArchive(payload));
      final source = await openPeSfxSource(owner);
      addTearDown(source.close);
      final chunks = await Future.wait([
        source.read(16, 17),
        source.read(0, 9),
        source.read(100, 7),
      ]);
      expect(chunks, [
        payload.sublist(16, 33),
        payload.sublist(0, 9),
        payload.sublist(100, 107),
      ]);
    });

    test(
      'close invalidates pending reads and closes underlying once',
      () async {
        final owner = _Source(sfxPeArchive(_fixture('sample.7z')));
        final source = await openPeSfxSource(owner);
        owner.block = Completer<void>();
        final pending = source.read(0, 8);
        final assertion = expectLater(
          pending,
          throwsA(isA<koni.ArchiveClosedException>()),
        );
        await Future<void>.delayed(Duration.zero);
        await source.close();
        owner.block!.complete();
        await assertion;
        await source.close();
        expect(owner.closes, 1);
        await expectLater(
          source.read(0, 0),
          throwsA(isA<koni.ArchiveClosedException>()),
        );
      },
    );

    test('source resizing is rejected after inspection', () async {
      final owner = _Source(sfxPeArchive(_fixture('sample.7z')));
      final source = await openPeSfxSource(owner);
      addTearDown(source.close);
      owner.length++;
      await expectLater(
        source.read(0, 1),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    test('single-read cap prevents whole large-container allocation', () async {
      final fixture = sfxSparseZip64();
      final owner = _Source.sparse(fixture.length, fixture.regions);
      final source = await openPeSfxSource(owner);
      addTearDown(source.close);
      final calls = owner.reads.length;
      await expectLater(
        source.read(0, kArchiveReadLimit + 65537),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(owner.reads.length, calls);
    });
  });
}
