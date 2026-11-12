// Original writer output for independent gzip and libarchive verification.
// dart run test/support/emit_archive_unix_compress_profiles.dart <directory>
// python3 test/support/check_archive_unix_compress_profiles.py <directory>
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_compression_writer.dart';
import 'package:crisp_cloud/services/archive_tar_writer.dart';
import 'package:crisp_cloud/services/archive_unix_compress_codec.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:crisp_cloud/services/archive_writer_service.dart';

import 'archive_unix_compress_writer_fixtures.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError('Supply an output directory for native validation.');
  }
  final directory = await Directory(arguments.single).create(recursive: true);
  final manifest = <Map<String, Object>>[];

  Future<void> save(
    String name,
    Uint8List bytes,
    Uint8List source,
    int width, {
    Map<String, Object> extra = const {},
  }) async {
    await File('${directory.path}/$name').writeAsBytes(bytes);
    await File('${directory.path}/$name.raw').writeAsBytes(source);
    manifest.add({
      'file': name,
      'source': '$name.raw',
      'maxBits': width,
      'packedBytes': bytes.length,
      'packedSha256': sha256.convert(bytes).toString(),
      'decodedBytes': source.length,
      'decodedSha256': sha256.convert(source).toString(),
      ...extra,
    });
  }

  for (final item in unixCompressWriterPayloads().entries) {
    for (final width in [12, 14, 16]) {
      final bytes = encodeArchiveUnixCompress(item.value, maxBits: width);
      final name = '${item.key}-$width.Z';
      await save(name, bytes, item.value, width);
    }
  }

  final tarEntries = <ArchiveWriteEntry>[];
  final expectedTar = <Map<String, Object>>[];
  for (final item in <String, List<int>?>{
    'docs': null,
    'docs/日本語.txt': utf8.encode('Original portable TAR.Z payload\n'),
    'empty-file': [],
    'empty-folder': null,
    'binary.dat': List.generate(65536 + 19, (i) => i % 251),
  }.entries) {
    final isDirectory = item.value == null;
    final bytes = Uint8List.fromList(item.value ?? []);
    final mode = isDirectory ? 0x1e8 : 0x1a0;
    tarEntries.add(
      ArchiveWriteEntry(
        path: item.key,
        isDirectory: isDirectory,
        size: bytes.length,
        mode: mode,
        modified: DateTime.fromMillisecondsSinceEpoch(
          1700000000000,
          isUtc: true,
        ),
        readChunks: isDirectory ? null : () => Stream.value(bytes),
      ),
    );
    expectedTar.add({
      'path': item.key,
      'directory': isDirectory,
      'size': bytes.length,
      'mode': mode,
      'uid': 0,
      'gid': 0,
      'uname': '',
      'gname': '',
      'mtime': 1700000000,
      'sha256': sha256.convert(bytes).toString(),
    });
  }
  final rawTar = await collectArchiveWrite(
    (sink) => writeTarArchive(tarEntries, sink: sink),
  );
  for (final profile in [(1, 12), (6, 14), (9, 16)]) {
    final bytes = await collectArchiveWrite(
      (sink) => writeArchiveEntries(
        ArchiveEndpointFormat.tarCompress,
        tarEntries,
        sink: sink,
        compression: ArchiveCompressionKind.compress,
        level: profile.$1,
      ),
    );
    await save(
      'tree-${profile.$2}.tar.Z',
      bytes,
      rawTar,
      profile.$2,
      extra: {'tarEntries': expectedTar},
    );
  }

  // Repack a saved external reference through the preservation-aware writer.
  final reference = File('test/fixtures/archives/codec-container.tar.Z')
      .readAsBytesSync();
  await File('${directory.path}/reference.tar.Z').writeAsBytes(reference);
  final archive = await openViewerArchive(reference, name: 'reference.tar.Z');
  try {
    final inspection = await inspectTarRewrite(
      reference,
      archive,
      name: 'reference.tar.Z',
    );
    if (!inspection.supported) throw StateError(inspection.reason!);
    for (final edited in [false, true]) {
      final entries = [
        for (final member in archive.members)
          ArchiveWriteEntry(
            path: member.name.replaceFirst(RegExp(r'/+$'), ''),
            isDirectory: !member.isFile,
            size: edited && member.isFile ? 7 : member.size,
            mode: member.posixMode,
            modified: member.modified,
            attributes: inspection.attributes[member.name] ?? const {},
            readChunks: !member.isFile
                ? null
                : () async* {
                    yield edited
                        ? Uint8List.fromList(utf8.encode('changed'))
                        : await archive.readMember(member);
                  },
          ),
      ];
      final expectedRaw = await collectArchiveWrite(
        (sink) => writeTarArchive(entries, sink: sink, source: inspection),
      );
      final bytes = await collectArchiveWrite(
        (sink) => writeArchiveEntries(
          ArchiveEndpointFormat.tarCompress,
          entries,
          sink: sink,
          source: inspection,
          compression: ArchiveCompressionKind.compress,
        ),
      );
      await save(
        edited ? 'edited.tar.Z' : 'rewritten.tar.Z',
        bytes,
        expectedRaw,
        14,
        extra: {'tarSource': 'reference.tar.Z', 'edited': edited},
      );
    }
  } finally {
    await archive.close();
  }
  await File(
    '${directory.path}/manifest.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(manifest)}\n');
}
