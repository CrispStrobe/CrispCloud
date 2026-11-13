// Direct offline native ISO create/inspect/edit/rewrite verification.
// dart --packages=.dart_tool/package_config.json \
//   test/support/verify_archive_streamed_iso.dart [--large] [--oracle]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_iso_reader.dart';
import 'package:crisp_cloud/services/archive_iso_writer.dart';
import 'package:crisp_cloud/services/archive_output_spool.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';

void require(bool value, String message) {
  if (!value) throw StateError(message);
}

Stream<List<int>> zeroes(int length) async* {
  final block = Uint8List(256 * 1024);
  for (var offset = 0; offset < length; offset += block.length) {
    final remaining = length - offset;
    yield remaining < block.length
        ? Uint8List.sublistView(block, 0, remaining)
        : block;
  }
}

Future<ArchiveRewriteInspection> inspect(
  ArchiveOutputSpool spool,
  ViewerArchive archive,
) async {
  final source = await spool.openByteSource();
  try {
    final result = await inspectIsoRewriteSource(source, archive);
    require(result.supported, result.reason ?? 'ISO profile refused.');
    return result;
  } finally {
    await source.close();
  }
}

Future<void> exportSparse(ArchiveOutputSpool spool, File file) async {
  final output = await file.open(mode: FileMode.writeOnly);
  var position = 0;
  try {
    await for (final bytes in spool.openRead()) {
      if (bytes.every((value) => value == 0)) {
        await output.setPosition(position + bytes.length);
      } else {
        await output.writeFrom(bytes);
      }
      position += bytes.length;
    }
    require(position == spool.length, 'Spool export length differs.');
    await output.truncate(position);
    await output.flush();
  } finally {
    await output.close();
  }
}

Future<void> main(List<String> args) async {
  final length = args.contains('--large')
      ? 2 * 1024 * 1024 * 1024 + 17
      : 1024 * 1024 + 17;
  final modified = DateTime.utc(2026, 11, 13, 1, 2, 3);
  final original = await ArchiveOutputSpool.create(
    maxBytes: kArchiveStreamingLimit,
  );
  final replacement = await ArchiveOutputSpool.create(
    maxBytes: kArchiveStreamingLimit,
  );
  final directory = await Directory.systemTemp.createTemp(
    'crisp-iso-rewrite-probe-',
  );
  ViewerArchive? before, after;
  final watch = Stopwatch()..start();
  var maxOutputChunk = 0;
  Future<void> emit(ArchiveOutputSpool spool, List<int> bytes) async {
    require(bytes.length <= 256 * 1024, 'Unbounded ISO writer output.');
    if (bytes.length > maxOutputChunk) maxOutputChunk = bytes.length;
    await spool.write(bytes);
  }

  try {
    await writeIsoArchive(
      [
        ArchiveWriteEntry(
          path: 'large.bin',
          isDirectory: false,
          size: length,
          modified: modified,
          mode: 0x81a4,
          readChunks: () => zeroes(length),
        ),
        ArchiveWriteEntry(
          path: 'remove.txt',
          isDirectory: false,
          size: 1,
          modified: modified,
          mode: 0x81a4,
          readChunks: () => Stream.value([7]),
        ),
        ArchiveWriteEntry(
          path: 'empty',
          isDirectory: true,
          size: 0,
          modified: modified,
          mode: 0x41ed,
        ),
      ],
      sink: (bytes) => emit(original, bytes),
      maxOutputBytes: kArchiveStreamingLimit,
    );
    await original.finish();
    final createMs = watch.elapsedMilliseconds;
    before = await openIsoArchive(
      await original.openByteSource(),
      maxMemberBytes: kArchiveStreamingLimit,
    );
    require(
      before.maxStreamingMemberBytes == kArchiveStreamingLimit,
      'Wrong stream allowance.',
    );
    final policy = await inspect(original, before);
    final large = before.members.singleWhere(
      (member) => member.name == 'large.bin',
    );
    final empty = before.members.singleWhere(
      (member) => member.name == 'empty',
    );
    final sourceArchive = before;
    final replacementEntries = [
      ArchiveWriteEntry(
        path: 'empty',
        isDirectory: true,
        size: 0,
        modified: empty.modified,
        mode: empty.posixMode,
        attributes: policy.attributes[empty.name]!,
      ),
      ArchiveWriteEntry(
        path: 'folder',
        isDirectory: true,
        size: 0,
        modified: modified,
        mode: 0x41ed,
      ),
      ArchiveWriteEntry(
        path: 'folder/renamed.bin',
        isDirectory: false,
        size: large.size,
        modified: large.modified,
        mode: large.posixMode,
        attributes: policy.attributes[large.name]!,
        readChunks: () =>
            sourceArchive.openMember(large, maxBytes: kArchiveStreamingLimit),
      ),
      ArchiveWriteEntry(
        path: 'added.txt',
        isDirectory: false,
        size: 5,
        modified: modified,
        mode: 0x81a4,
        readChunks: () => Stream.value(utf8.encode('added')),
      ),
    ];
    watch.reset();
    await writeIsoArchive(
      replacementEntries,
      source: policy,
      sink: (bytes) => emit(replacement, bytes),
      maxOutputBytes: kArchiveStreamingLimit,
    );
    await replacement.finish();
    final rewriteMs = watch.elapsedMilliseconds;
    after = await openIsoArchive(
      await replacement.openByteSource(),
      maxMemberBytes: kArchiveStreamingLimit,
    );
    await inspect(replacement, after);
    final expected = replacementEntries.map((entry) => entry.path).toSet();
    require(
      after.members.length == expected.length &&
          after.members.every((member) => expected.contains(member.name)),
      'Rewritten namespace differs.',
    );
    final renamed = after.members.singleWhere(
      (member) => member.name == 'folder/renamed.bin',
    );
    require(
      renamed.modified == modified && renamed.posixMode == 0x81a4,
      'Rewritten metadata differs.',
    );
    watch.reset();
    var received = 0, maxReadChunk = 0;
    await for (final chunk in after.openMember(
      renamed,
      maxBytes: kArchiveStreamingLimit,
    )) {
      require(
        chunk.every((value) => value == 0),
        'Rewritten member content differs.',
      );
      require(chunk.length <= 256 * 1024, 'Unbounded ISO member read.');
      received += chunk.length;
      if (chunk.length > maxReadChunk) maxReadChunk = chunk.length;
    }
    require(received == length, 'Rewritten member length differs.');
    final readMs = watch.elapsedMilliseconds;
    require(
      utf8.decode(
            await after.readMember(
              after.members.singleWhere((member) => member.name == 'added.txt'),
            ),
          ) ==
          'added',
      'Added file differs.',
    );
    if (args.contains('--large'))
      require(
        replacement.length > 2 * 1024 * 1024 * 1024,
        'Container did not exceed 2 GiB.',
      );
    if (args.contains('--oracle')) {
      final file = File('${directory.path}/rewritten.iso');
      await exportSparse(replacement, file);
      await File('${directory.path}/manifest.json').writeAsString(
        jsonEncode({
          'members': [
            for (final entry in replacementEntries)
              {
                'path': entry.path,
                'directory': entry.isDirectory,
                'size': entry.size,
                'mode': entry.mode! & 0xfff,
                'mtime': modified.millisecondsSinceEpoch ~/ 1000,
                if (entry.path == 'folder/renamed.bin') 'zeros': true,
                if (entry.path == 'added.txt') 'text': 'added',
              },
          ],
        }),
      );
      final result = await Process.run('python3', [
        'test/support/check_archive_streamed_iso.py',
        directory.path,
      ]);
      require(
        result.exitCode == 0,
        'Independent ISO verification failed: ${result.stdout}\n${result.stderr}',
      );
      stdout.write(result.stdout);
    }
    stdout.writeln(
      jsonEncode({
        'profile': 'data-only ISO with Rock Ridge and Joliet',
        'originalBytes': original.length,
        'replacementBytes': replacement.length,
        'memberBytes': received,
        'createMs': createMs,
        'rewriteMs': rewriteMs,
        'readMs': readMs,
        'maxOutputChunk': maxOutputChunk,
        'maxReadChunk': maxReadChunk,
        'independentOracle': args.contains('--oracle'),
      }),
    );
  } finally {
    await after?.close();
    await before?.close();
    await replacement.dispose();
    await original.dispose();
    await directory.delete(recursive: true);
  }
}
