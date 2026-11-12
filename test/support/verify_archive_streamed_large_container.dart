// Direct native verification of physical archive offsets above 2 GiB.
// Sparse zero-filled files keep this probe feasible on a small test volume.
// dart --packages=.dart_tool/package_config.json \
//   test/support/verify_archive_streamed_large_container.dart zip|7z [--oracle]
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_output_spool.dart';
import 'package:crisp_cloud/services/archive_streamed_reader.dart';
import 'package:crisp_cloud/services/archive_streaming_writer.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';

void require(bool value, String message) {
  if (!value) throw StateError(message);
}

Stream<List<int>> zeroes(int length) async* {
  final block = Uint8List(256 * 1024);
  for (var at = 0; at < length; at += block.length) {
    final remaining = length - at;
    yield remaining < block.length
        ? Uint8List.sublistView(block, 0, remaining)
        : block;
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty || !const {'zip', '7z'}.contains(args.first)) {
    throw ArgumentError('Choose zip or 7z, optionally followed by --oracle.');
  }
  const payloadLength = 2 * 1024 * 1024 * 1024 + 17;
  final format = args.first == 'zip'
      ? ArchiveEndpointFormat.zip
      : ArchiveEndpointFormat.sevenZip;
  final name = 'stored.${args.first}';
  final modified = DateTime.utc(2026, 11, 12, 1, 2, 3);
  final spool = await ArchiveOutputSpool.create(
    maxBytes: kArchiveStreamingLimit,
  );
  final directory = await Directory.systemTemp.createTemp(
    'crisp-large-stored-check-',
  );
  final initialRss = ProcessInfo.currentRss;
  var peakRss = initialRss, ticks = 0, maxWriterChunk = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
    ticks++;
    final rss = ProcessInfo.currentRss;
    if (rss > peakRss) peakRss = rss;
  });
  try {
    final watch = Stopwatch()..start();
    await writeStreamingArchiveEntries(
      format,
      [
        ArchiveWriteEntry(
          path: 'large.bin',
          isDirectory: false,
          size: payloadLength,
          mode: 0x1a4,
          modified: modified,
          readChunks: () => zeroes(payloadLength),
        ),
      ],
      sink: (chunk) async {
        if (chunk.length > maxWriterChunk) maxWriterChunk = chunk.length;
        require(chunk.length <= 256 * 1024, 'Unbounded writer chunk.');
        await spool.write(chunk);
      },
      maxOutputBytes: kArchiveStreamingLimit,
      level: 0,
    );
    await spool.finish();
    final writeMs = watch.elapsedMilliseconds;
    require(spool.length > payloadLength, 'Stored container was not >2 GiB.');
    stdout.writeln(
      jsonEncode({
        'phase': 'written',
        'file': name,
        'containerBytes': spool.length,
        'payloadBytes': payloadLength,
        'elapsedMs': writeMs,
      }),
    );

    watch.reset();
    final opened = await openStreamedArchiveSource(
      await spool.openByteSource(),
      name: name,
    );
    var decodedBytes = 0, maxReaderChunk = 0;
    try {
      require(opened.policy.reason == null, 'Stored rewrite policy refused.');
      final member = opened.archive.members.single;
      require(member.name == 'large.bin', 'Wrong member name.');
      require(member.size == payloadLength, 'Wrong member size.');
      require(member.modified == modified, 'Wrong modification time.');
      require((member.posixMode! & 0xfff) == 0x1a4, 'Wrong member mode.');
      await for (final chunk in opened.archive.openMember(
        member,
        maxBytes: kArchiveStreamingLimit,
      )) {
        require(
          chunk.every((value) => value == 0),
          'Incorrect member content.',
        );
        require(chunk.length <= 256 * 1024, 'Unbounded reader chunk.');
        decodedBytes += chunk.length;
        if (chunk.length > maxReaderChunk) maxReaderChunk = chunk.length;
      }
      require(decodedBytes == payloadLength, 'Incomplete member content.');
    } finally {
      await opened.archive.close();
    }
    final readMs = watch.elapsedMilliseconds;
    stdout.writeln(
      jsonEncode({
        'phase': 'productionReaderVerified',
        'file': name,
        'decodedBytes': decodedBytes,
        'elapsedMs': readMs,
        'maxReaderChunk': maxReaderChunk,
      }),
    );

    // Export the public spool stream for an independent reader. This copy
    // retains exact logical bytes and uses holes only for all-zero chunks.
    final outputFile = File('${directory.path}/$name');
    final output = await outputFile.open(mode: FileMode.writeOnly);
    var copied = 0;
    try {
      await for (final chunk in spool.openRead()) {
        if (chunk.every((value) => value == 0)) {
          await output.setPosition(copied + chunk.length);
        } else {
          await output.writeFrom(chunk);
        }
        copied += chunk.length;
      }
      await output.truncate(copied);
      await output.flush();
    } finally {
      await output.close();
    }
    require(copied == spool.length, 'Spool export length mismatch.');
    require(await outputFile.length() == spool.length, 'Export was truncated.');
    await File('${directory.path}/manifest.json').writeAsString(
      jsonEncode([
        {
          'archive': name,
          'members': [
            {
              'path': 'large.bin',
              'size': payloadLength,
              'directory': false,
              'mode': 0x1a4,
              'mtime': modified.millisecondsSinceEpoch ~/ 1000,
              'zeros': true,
            },
          ],
        },
      ]),
    );
    if (args.contains('--oracle')) {
      final allocation = await Process.run('python3', [
        '-c',
        'import json,os,sys; s=os.stat(sys.argv[1]); print(json.dumps({"logicalBytes":s.st_size,"allocatedBytes":s.st_blocks*512}))',
        outputFile.path,
      ]);
      require(allocation.exitCode == 0, '${allocation.stderr}');
      stdout.write(allocation.stdout);
      final oracle = await Process.run('python3', [
        'test/support/check_archive_streaming_writer.py',
        directory.path,
      ]);
      require(
        oracle.exitCode == 0,
        'Independent read failed: ${oracle.stdout}\n${oracle.stderr}',
      );
      stdout.write(oracle.stdout);
    }
    stdout.writeln(
      jsonEncode({
        'phase': 'complete',
        'file': name,
        'containerBytes': spool.length,
        'payloadBytes': decodedBytes,
        'writeMs': writeMs,
        'readMs': readMs,
        'maxWriterChunk': maxWriterChunk,
        'maxReaderChunk': maxReaderChunk,
        'rssGrowthBytes': peakRss - initialRss,
        'peakRssBytes': peakRss,
        'heartbeatTicks': ticks,
        'independentOracle': args.contains('--oracle'),
      }),
    );
  } finally {
    timer.cancel();
    await spool.dispose();
    await directory.delete(recursive: true);
  }
}
