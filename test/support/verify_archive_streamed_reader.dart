// Direct, offline Dart verification of the bounded native readers.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:koni_codecs/koni_codecs.dart' as codecs;
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_streamed_reader.dart';
import 'package:crisp_cloud/services/archive_streaming_lzma.dart';
import 'package:crisp_cloud/services/archive_streaming_lzma2.dart';
import 'package:crisp_cloud/services/archive_streaming_writer.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';

void equal(List<int> actual, List<int> expected, String label) {
  if (actual.length != expected.length) {
    throw StateError('$label: length differs');
  }
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) throw StateError('$label: byte $i differs');
  }
}

Future<void> main(List<String> args) async {
  final payload = Uint8List.fromList(
    List<int>.generate(1024 * 1024, (i) => (i ~/ 31 + i % 203) & 255),
  );
  final lzma = codecs.LzmaEncoder(dictSize: 4096);
  final packed = lzma.encode(payload);
  final decoded = BytesBuilder(copy: false);
  final decoder = ArchiveStreamingLzmaDecoder(
    outputSize: payload.length,
    dictionarySize: 4096,
    onOutput: decoded.add,
  )..setProps(lzma.propsByte);
  for (var at = 0; at < packed.length; at += 13) {
    decoder.addInput(
      Uint8List.sublistView(
        packed,
        at,
        at + 13 < packed.length ? at + 13 : packed.length,
      ),
    );
  }
  decoder.setInputComplete();
  decoder.flush();
  equal(decoded.takeBytes(), payload, 'LZMA ring/history');
  final lzma2 = codecs.Lzma2Encoder(dictSize: 4096, chunkSize: 8192);
  final packed2 = lzma2.encode(payload);
  final decoder2 = ArchiveStreamingLzma2Decoder(
    outputSize: payload.length,
    dictSizeProp: lzma2.dictSizeProp,
    onOutput: decoded.add,
  );
  for (var at = 0; at < packed2.length; at += 17) {
    decoder2.addInput(
      Uint8List.sublistView(
        packed2,
        at,
        at + 17 < packed2.length ? at + 17 : packed2.length,
      ),
    );
  }
  decoder2.finish();
  equal(decoded.takeBytes(), payload, 'LZMA2 ring/history');
  print(
    'LZMA/LZMA2 ring dictionaries passed with 4KiB history and 1MiB output.',
  );

  for (final format in [
    ArchiveEndpointFormat.zip,
    ArchiveEndpointFormat.sevenZip,
    ArchiveEndpointFormat.tar,
    ArchiveEndpointFormat.tarGzip,
  ]) {
    for (final level in [0, 6]) {
      final name = switch (format) {
        ArchiveEndpointFormat.zip => 'sample.zip',
        ArchiveEndpointFormat.sevenZip => 'sample.7z',
        ArchiveEndpointFormat.tar => 'sample.tar',
        _ => 'sample.tgz',
      };
      final out = BytesBuilder(copy: false);
      await writeStreamingArchiveEntries(
        format,
        [
          ArchiveWriteEntry(
            path: 'empty',
            isDirectory: true,
            size: 0,
            modified: DateTime.utc(2024, 1, 2, 3, 4, 5),
            mode: 0x1ed,
          ),
          ArchiveWriteEntry(
            path: 'data.txt',
            isDirectory: false,
            size: payload.length,
            modified: DateTime.utc(2024, 1, 2, 3, 4, 5),
            mode: 0x1a4,
            readChunks: () => Stream.value(payload),
          ),
          ArchiveWriteEntry(
            path: 'zero',
            isDirectory: false,
            size: 0,
            modified: DateTime.utc(2024, 1, 2, 3, 4, 5),
            mode: 0x1a4,
            readChunks: () => const Stream.empty(),
          ),
        ],
        sink: (bytes) async => out.add(Uint8List.fromList(bytes)),
        maxOutputBytes: kArchiveStreamingLimit,
        level: level,
      );
      final bytes = out.takeBytes();
      final opened = await openStreamedArchiveSource(
        koni.MemoryByteSource(bytes),
        name: name,
      );
      try {
        if (opened.policy.reason != null) {
          throw StateError('$name policy: ${opened.policy.reason}');
        }
        final member = opened.archive.members.firstWhere(
          (m) => m.name == 'data.txt',
        );
        equal(await opened.archive.readMember(member), payload, '$name/$level');
      } finally {
        await opened.archive.close();
      }
      print('$name level $level passed (${bytes.length} bytes).');
    }
  }
  if (args.isNotEmpty) {
    final fixtures = Directory(args.single);
    for (final path in [
      'copy.7z',
      'deflate.7z',
      'lzma1.7z',
      'lzma2_nonsolid.7z',
      'lzma2_solid.7z',
    ]) {
      final file = File('${fixtures.path}/$path');
      final bytes = await file.readAsBytes();
      final old = await openViewerArchive(bytes, name: path);
      final current = await openStreamedArchiveSource(
        koni.MemoryByteSource(bytes),
        name: path,
      );
      try {
        for (final member in old.members.where((m) => m.isFile)) {
          final peer = current.archive.members.firstWhere(
            (m) => m.name == member.name,
          );
          equal(
            await current.archive.readMember(peer),
            await old.readMember(member),
            'fixture $path/${member.name}',
          );
        }
      } finally {
        await old.close();
        await current.archive.close();
      }
      print('Independent fixture $path passed.');
    }
  }
  final gzip = Uint8List.fromList(
    const ar.GZipEncoder().encode(utf8.encode('not tar')),
  );
  var refused = false;
  try {
    await openStreamedArchiveSource(
      koni.MemoryByteSource(gzip),
      name: 'bad.tgz',
    );
  } on ArchiveViewException {
    refused = true;
  }
  if (!refused) throw StateError('Non-TAR gzip accepted as tgz.');
  print('Streamed archive verification complete.');
}
