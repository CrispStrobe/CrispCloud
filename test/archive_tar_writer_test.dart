import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_compression_writer.dart';
import 'package:crisp_cloud/services/archive_tar_writer.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_package_writer_fixtures.dart' show packageEntry;
import 'support/archive_tar_writer_fixtures.dart';

Future<Uint8List> _write(
  List<ArchiveWriteEntry> entries, {
  ArchiveRewriteInspection? source,
  int limit = 256 * 1024 * 1024,
  bool Function()? isCancelled,
}) => collectArchiveWrite(
  (sink) => writeTarArchive(
    entries,
    sink: sink,
    source: source,
    maxOutputBytes: limit,
    isCancelled: isCancelled,
  ),
  maxBytes: limit,
);

class _Fixture {
  _Fixture(this.archive, this.inspection);
  final ViewerArchive archive;
  final ArchiveRewriteInspection inspection;
  List<ArchiveWriteEntry> get entries => [
    for (final member in archive.members)
      if (member.name != '/')
        ArchiveWriteEntry(
          path: member.name,
          isDirectory: !member.isFile,
          size: member.isFile ? member.size : 0,
          mode: member.posixMode,
          modified: member.modified,
          attributes: inspection.attributes[member.name] ?? const {},
          readChunks: member.isFile
              ? () async* {
                  yield await archive.readMember(member);
                }
              : null,
        ),
  ];
  Future<Uint8List> repack() => _write(entries, source: inspection);
}

Future<_Fixture> _fixture(
  Uint8List bytes, {
  String name = 'fixture.tar',
}) async {
  final archive = await openViewerArchive(bytes, name: name);
  addTearDown(archive.close);
  return _Fixture(archive, await inspectTarRewrite(bytes, archive, name: name));
}

void _checksum(Uint8List bytes, int at) {
  bytes.fillRange(at + 148, at + 156, 32);
  final sum = bytes.sublist(at, at + 512).fold(0, (a, b) => a + b);
  bytes.setRange(
    at + 148,
    at + 154,
    ascii.encode(sum.toRadixString(8).padLeft(6, '0')),
  );
  bytes[at + 154] = 0;
  bytes[at + 155] = 32;
}

void _number(Uint8List bytes, int at, int length, int value) {
  bytes.fillRange(at, at + length, 0);
  bytes.setAll(
    at,
    ascii.encode(value.toRadixString(8).padLeft(length - 1, '0')),
  );
}

void _name(Uint8List bytes, int at, int length, String name) {
  bytes.fillRange(at, at + length, 0);
  bytes.setAll(at, utf8.encode(name));
}

Uint8List _paxArchive(
  Map<String, String> records, {
  String path = 'file',
  List<int> payload = const [1, 2, 3],
}) {
  final raw = referenceTar('ustar');
  final header = raw.sublist(512, 1024);
  _name(header, 0, 100, path);
  _number(header, 124, 12, payload.length);
  _checksum(header, 0);
  final text = BytesBuilder(copy: false);
  for (final record in records.entries) {
    final data = utf8.encode(' ${record.key}=${record.value}\n');
    var size = data.length + 1;
    while ('$size'.length + data.length != size) {
      size = '$size'.length + data.length;
    }
    text.add(ascii.encode('$size'));
    text.add(data);
  }
  final pax = text.takeBytes(), extended = Uint8List.fromList(header);
  _name(extended, 0, 100, 'PaxHeaders/file');
  extended[156] = 120;
  _number(extended, 124, 12, pax.length);
  _checksum(extended, 0);
  return Uint8List.fromList([
    ...extended,
    ...pax,
    ...Uint8List((512 - pax.length % 512) % 512),
    ...header,
    ...payload,
    ...Uint8List((512 - payload.length % 512) % 512),
    ...Uint8List(1024),
  ]);
}

void main() {
  group('TAR metadata preservation', () {
    test('creates a bounded empty POSIX TAR', () async {
      final bytes = await _write([]);
      expect(bytes, Uint8List(1024));
      final source = await _fixture(bytes);
      expect(source.inspection.reason, isNull);
      expect(source.archive.members, isEmpty);
    });

    test('creates Unicode paths and streams non-aligned contents', () async {
      final bytes = await _write([
        packageEntry('docs', [], directory: true, mode: 0x1e8),
        packageEntry(
          'docs/日本語.txt',
          List.generate(900, (i) => i % 256),
          modified: DateTime.utc(2024),
          mode: 0x1a0,
          attributes: {
            'tar.uid': 123,
            'tar.gid': 456,
            'tar.uname': 'owner',
            'tar.gname': 'group',
          },
        ),
      ]);
      final source = await _fixture(bytes);
      expect(source.inspection.reason, isNull);
      expect(source.inspection.attributes['docs/日本語.txt']!['tar.uid'], 123);
      expect(
        await source.archive.readMember(source.archive.members.last),
        List.generate(900, (i) => i % 256),
      );
      final again = await _fixture(await source.repack());
      expect(again.inspection.attributes, source.inspection.attributes);
    });

    for (final kind in ['ustar', 'gnu', 'pax']) {
      test(
        'preserves independent Python $kind ownership and extended metadata',
        () async {
          final source = await _fixture(referenceTar(kind));
          expect(source.inspection.reason, isNull);
          final output = await source.repack();
          final again = await _fixture(output);
          expect(again.inspection.reason, isNull);
          expect(again.inspection.attributes, source.inspection.attributes);
          expect(again.inspection.container, source.inspection.container);
          expect(output.length, referenceTar(kind).length);
          expect(
            await again.archive.readMember(again.archive.members.last),
            utf8.encode('Independent TAR metadata fixture\n'),
          );
        },
      );
    }

    test(
      'retains nanosecond PAX strings beyond the DateTime model precision',
      () async {
        final source = await _fixture(referenceTar('pax'));
        final attrs = source.inspection.attributes.values.single;
        expect((attrs['tar.pax']! as Map)['mtime'], '1700000000.123456789');
        final result = await _fixture(await source.repack());
        final pax =
            result.inspection.attributes.values.single['tar.pax']! as Map;
        expect(pax['mtime'], '1700000000.123456789');
        expect(pax['atime'], '1690000000.987654321');
        expect(pax['ctime'], '1695000000.000000001');
      },
    );

    test(
      'preserves root metadata while replacing a body and renaming a member',
      () async {
        final source = await _fixture(referenceTar('pax'));
        final original = source.entries.single;
        final result = await _fixture(
          await _write([
            packageEntry(
              'renamed',
              [4, 5],
              mode: original.mode,
              modified: original.modified,
              attributes: original.attributes,
            ),
          ], source: source.inspection),
        );
        expect(result.inspection.reason, isNull);
        expect(
          result.inspection.container['tar.root'],
          source.inspection.container['tar.root'],
        );
        final attrs = result.inspection.attributes['renamed']!;
        expect(attrs['tar.uid'], 1234567890);
        expect((attrs['tar.pax']! as Map)['path'], 'renamed');
        expect(await result.archive.readMember(result.archive.members.last), [
          4,
          5,
        ]);
      },
    );

    test('supports newly created large owners and long PAX text', () async {
      final path = 'path-${'x' * 150}';
      final source = await _fixture(
        await _write([
          packageEntry(
            path,
            [1],
            modified: DateTime.utc(2024, 1, 1, 0, 0, 0, 123, 456),
            attributes: {
              'tar.uid': 1234567890,
              'tar.gid': 3456789012,
              'tar.uname': 'owner-${'u' * 40}',
              'tar.gname': 'group-${'g' * 40}',
            },
          ),
        ]),
      );
      expect(source.inspection.reason, isNull);
      final attrs = source.inspection.attributes.values.single;
      expect(attrs['tar.uid'], 1234567890);
      expect(attrs['tar.uname'], 'owner-${'u' * 40}');
      expect((attrs['tar.pax']! as Map)['mtime'], '1704067200.123456');
    });

    test('preserves a V7 header without adding modern fields', () async {
      final bytes = referenceTar('ustar').sublist(512);
      bytes.fillRange(257, 512, 0);
      _checksum(bytes, 0);
      final source = await _fixture(bytes);
      expect(source.inspection.reason, isNull);
      expect(source.inspection.container['tar.variant'], 'v7');
      final result = await source.repack();
      expect(result.sublist(257, 512), Uint8List(255));
      expect(
        (await _fixture(result)).inspection.attributes,
        source.inspection.attributes,
      );
    });

    test(
      'preserves GNU atime and ctime fields and signed base-256 mtime',
      () async {
        final bytes = referenceTar('gnu');
        _number(bytes, 1536 + 345, 12, 1690000000);
        _number(bytes, 1536 + 357, 12, 1695000000);
        _checksum(bytes, 1536);
        final source = await _fixture(bytes);
        expect(source.inspection.reason, isNull);
        final attrs = source.inspection.attributes.values.single;
        expect(attrs['tar.gnuAtime'], 1690000000);
        expect(attrs['tar.gnuCtime'], 1695000000);
        final result = await _fixture(await source.repack());
        expect(result.inspection.attributes, source.inspection.attributes);
        expect(
          result.archive.members.last.modified!.millisecondsSinceEpoch,
          -12345000,
        );
      },
    );

    test('preserves negative POSIX timestamps with explicit PAX', () async {
      final source = await _fixture(
        await _write([
          packageEntry(
            'file',
            [],
            modified: DateTime.fromMicrosecondsSinceEpoch(
              -1250000,
              isUtc: true,
            ),
          ),
        ]),
      );
      expect(source.inspection.reason, isNull);
      expect(
        source.archive.members.single.modified!.microsecondsSinceEpoch,
        -1250000,
      );
      expect(
        (source.inspection.attributes.values.single['tar.pax']!
            as Map)['mtime'],
        '-1.25',
      );
    });

    for (final kind in ArchiveCompressionKind.values) {
      test('inspects metadata inside the ${kind.name} wrapper', () async {
        final bytes = encodeArchiveCompression(referenceTar('pax'), kind);
        final extension = switch (kind) {
          ArchiveCompressionKind.gzip => 'gz',
          ArchiveCompressionKind.bzip2 => 'bz2',
          ArchiveCompressionKind.xz => 'xz',
          ArchiveCompressionKind.zstd => 'zst',
          ArchiveCompressionKind.lz4 => 'lz4',
          ArchiveCompressionKind.lzma => 'lzma',
        };
        final source = await _fixture(bytes, name: 'fixture.tar.$extension');
        expect(source.inspection.reason, isNull);
        expect(
          source.inspection.attributes.values.single['tar.uid'],
          1234567890,
        );
        final again = await _fixture(await source.repack());
        expect(again.inspection.reason, isNull);
        expect(again.inspection.attributes, source.inspection.attributes);
        expect(again.inspection.container, source.inspection.container);
        expect(
          await again.archive.readMember(again.archive.members.last),
          utf8.encode('Independent TAR metadata fixture\n'),
        );
      });
    }
  });

  group('TAR refusal profiles', () {
    test('refuses source mode/type contradictions', () async {
      final source = await _fixture(referenceTar('ustar'));
      final bytes = referenceTar('ustar');
      _number(bytes, 512 + 100, 8, 0x41ed);
      _checksum(bytes, 512);
      expect(
        (await inspectTarRewrite(bytes, source.archive)).reason,
        contains('mode/type'),
      );
    });
    test(
      'refuses to discard GNU timestamps on a POSIX output request',
      () async {
        await expectLater(
          _write([
            packageEntry('file', [], attributes: {'tar.gnuAtime': 1700000000}),
          ]),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );
    for (final key in [
      'GNU.sparse.map',
      'SCHILY.xattr.user.test',
      'SCHILY.acl.access',
      'comment',
      'hdrcharset',
    ]) {
      test('refuses opaque PAX $key', () async {
        final source = await _fixture(_paxArchive({key: 'unknown'}));
        expect(source.inspection.reason, contains('Unsupported PAX'));
      });
    }
    test('refuses global PAX rather than changing its scope', () async {
      final bytes = _paxArchive({'uid': '123'});
      bytes[156] = 103;
      _checksum(bytes, 0);
      expect((await _fixture(bytes)).inspection.reason, contains('Global PAX'));
    });
    for (final type in [49, 50, 51, 52, 54, 55, 83]) {
      test('refuses link/sparse/special type $type', () async {
        final source = await _fixture(referenceTar('ustar'));
        final bytes = referenceTar('ustar');
        bytes[512 + 156] = type;
        _checksum(bytes, 512);
        final result = await inspectTarRewrite(bytes, source.archive);
        expect(result.reason, contains('filesystem-aware'));
      });
    }
    test('refuses traversal, aliasing and absolute header paths', () async {
      final source = await _fixture(referenceTar('ustar'));
      for (final path in [
        '../file',
        '/file',
        'folder/../file',
        'C:/file',
        r'folder\file',
        'folder//file',
      ]) {
        final bytes = referenceTar('ustar');
        _name(bytes, 512, 100, path);
        _checksum(bytes, 512);
        expect(
          (await inspectTarRewrite(bytes, source.archive)).supported,
          isFalse,
        );
      }
    });
    test('refuses corrupt checksums, truncation, incomplete endings and opaque padding', () async {
      final bytes = referenceTar('ustar');
      final source = await _fixture(bytes);
      final checksum = Uint8List.fromList(bytes)..[512] ^= 1;
      final padding = Uint8List.fromList(bytes)..[1100] = 1;
      final extra = Uint8List(bytes.length + 1)
        ..setAll(0, bytes)
        ..last = 1;
      for (final damaged in [
        checksum,
        padding,
        extra,
        bytes.sublist(0, 1040),
        bytes.sublist(0, 2048),
      ]) {
        expect(
          (await inspectTarRewrite(damaged, source.archive)).supported,
          isFalse,
        );
      }
    });
    test('refuses unsupported GNU incremental/multivolume data', () async {
      final bytes = referenceTar('gnu');
      final source = await _fixture(bytes);
      _number(bytes, 1536 + 369, 12, 1);
      _checksum(bytes, 1536);
      expect(
        (await inspectTarRewrite(bytes, source.archive)).reason,
        contains('multivolume'),
      );
    });
    test('refuses invalid or reader-ambiguous fractional timestamps', () async {
      for (final time in ['-0.25', '1700000000.1234567890', 'nan']) {
        final source = await _fixture(_paxArchive({'mtime': time}));
        expect(source.inspection.supported, isFalse);
      }
      await expectLater(
        _write([
          packageEntry(
            'file',
            [],
            modified: DateTime.fromMicrosecondsSinceEpoch(-250000, isUtc: true),
          ),
        ]),
        throwsA(isA<ArchiveViewException>()),
      );
    });
    test('refuses invalid and repeated PAX keys', () async {
      final bytes = _paxArchive({'uid': '123', 'gid': '456'});
      final text = utf8.decode(bytes.sublist(512, 536), allowMalformed: true);
      final at = text.indexOf('gid');
      bytes.setAll(512 + at, ascii.encode('uid'));
      final source = await _fixture(bytes);
      expect(source.inspection.reason, contains('Repeated PAX'));
    });
  });

  group('TAR writer bounds and lifecycle', () {
    test(
      'rejects namespace and unsupported metadata before any output',
      () async {
        for (final entries in [
          [
            packageEntry('../file', [1]),
          ],
          [
            packageEntry('file', [1]),
            packageEntry('file', [2]),
          ],
          [
            packageEntry('file', [1]),
            packageEntry('file/child', [2]),
          ],
          [
            packageEntry('file', [1], attributes: {'opaque': 'value'}),
          ],
          [
            packageEntry('file', [1], attributes: {'tar.uid': -1}),
          ],
          [
            packageEntry('file', [1], mode: 0xa1ff),
          ],
        ]) {
          var written = 0;
          await expectLater(
            writeTarArchive(
              entries,
              sink: (chunk) async {
                written += chunk.length;
              },
            ),
            throwsA(anyOf(isA<ArchiveViewException>(), isA<ArgumentError>())),
          );
          expect(written, 0);
        }
      },
    );
    test(
      'preflights the output cap including headers and end records',
      () async {
        var written = 0;
        await expectLater(
          writeTarArchive(
            [
              packageEntry('file', [1]),
            ],
            sink: (chunk) async {
              written += chunk.length;
            },
            maxOutputBytes: 2047,
          ),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(written, 0);
      },
    );
    test('detects truncated, growing and invalid byte streams', () async {
      for (final body in [
        [1],
        [1, 2, 3],
        [1, 999],
      ]) {
        await expectLater(
          _write([
            ArchiveWriteEntry(
              path: 'file',
              isDirectory: false,
              size: 2,
              readChunks: () => Stream.value(body),
            ),
          ]),
          throwsA(isA<ArchiveViewException>()),
        );
      }
    });
    test('checks cancellation before headers and between chunks', () async {
      await expectLater(
        _write([], isCancelled: () => true),
        throwsA(isA<ArchiveViewException>()),
      );
      var cancelled = false, written = 0;
      await expectLater(
        writeTarArchive(
          [packageEntry('file', List.filled(100, 1), chunkSize: 10)],
          isCancelled: () => cancelled,
          sink: (chunk) async {
            written += chunk.length;
            if (written > 512) cancelled = true;
          },
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(written, 522);
    });
    test('rejects a refused or incompatible preservation inspection', () async {
      for (final source in [
        ArchiveRewriteInspection(reason: 'Read only'),
        ArchiveRewriteInspection(container: {'package.kind': 'ar'}),
      ]) {
        await expectLater(
          _write([], source: source),
          throwsA(isA<ArchiveViewException>()),
        );
      }
    });
  });
}
