// Optional independent acceptance check, outside the Flutter suite.
// Run from the repository root with Dart's existing package configuration:
// dart run test/support/verify_disk_writer_native.dart /path/to/fsck.hfsplus
//     /path/to/libdmg/dmg /path/to/libdmg/hfsplus
// These tools validate outputs; they are not application runtime dependencies.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/archive_dmg_writer.dart';
import 'package:crisp_cloud/services/archive_hfs_writer.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    throw ArgumentError(
      'Provide fsck.hfsplus, libdmg dmg and libdmg hfsplus paths.',
    );
  }
  final directory = await Directory.systemTemp.createTemp(
    'crisp-native-disk-check-',
  );
  Future<void> tool(String executable, List<String> arguments) async {
    final result = await Process.run(executable, arguments);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      throw StateError(
        'Independent validation failed with exit ${result.exitCode}.',
      );
    }
  }

  Future<void> write(
    String path,
    List<ArchiveWriteEntry> entries, {
    bool dmg = false,
  }) async {
    final output = await File(path).open(mode: FileMode.write);
    Future<void> sink(List<int> chunk) async {
      await output.writeFrom(chunk);
    }

    try {
      if (dmg) {
        await writeDmgArchive(entries, sink: sink);
      } else {
        await writeHfsArchive(entries, sink: sink);
      }
    } finally {
      await output.close();
    }
  }

  const text = 'Independently validated CrispCloud data image\n';
  ArchiveWriteEntry file(String name) {
    final bytes = Uint8List.fromList(utf8.encode(text));
    return ArchiveWriteEntry(
      path: name,
      isDirectory: false,
      size: bytes.length,
      modified: DateTime.utc(2024, 4, 5, 6, 7, 8),
      mode: 0x81a4,
      readChunks: () => Stream.value(bytes),
    );
  }

  try {
    final entries = [
      file('hello.txt'),
      file('café.txt'),
      file('한글.txt'),
      file('資料/☃.txt'),
      file('Case.txt'),
      file('case.txt'),
      file('emoji-😀.txt'),
      file('symbols-Å-豈.txt'),
      for (var i = 0; i < 180; i++) file('docs/file-$i.txt'),
      ArchiveWriteEntry(path: 'empty-folder', isDirectory: true, size: 0),
    ];
    final empty = '${directory.path}/empty.hfs';
    final populated = '${directory.path}/files.hfs';
    final dmg = '${directory.path}/files.dmg';
    final extracted = '${directory.path}/extracted.hfs';
    final hello = '${directory.path}/hello.txt';
    await write(empty, []);
    await tool(args[0], ['-n', empty]);
    await write(populated, entries);
    await tool(args[0], ['-n', populated]);
    await write(dmg, entries, dmg: true);
    await tool(args[1], ['extract', dmg, extracted]);
    await tool(args[0], ['-n', extracted]);
    await tool(args[2], [extracted, 'extract', '/hello.txt', hello]);
    if (await File(hello).readAsString() != text) {
      throw StateError('Independent HFS file extraction changed the content.');
    }
    const size = 65 * 1024 * 1024 + 333;
    final block = Uint8List.fromList(List.generate(65536, (i) => i % 251));
    Stream<List<int>> largeBytes() async* {
      for (var at = 0; at < size; at += block.length) {
        yield Uint8List.sublistView(
          block,
          0,
          size - at < block.length ? size - at : block.length,
        );
      }
    }

    final large = [
      ArchiveWriteEntry(
        path: 'large.bin',
        isDirectory: false,
        size: size,
        readChunks: largeBytes,
      ),
    ];
    final largeImage = '${directory.path}/large.dmg';
    final largeHfs = '${directory.path}/large.hfs';
    final largeFile = '${directory.path}/large.bin';
    await write(largeImage, large, dmg: true);
    await tool(args[1], ['extract', largeImage, largeHfs]);
    await tool(args[0], ['-n', largeHfs]);
    await tool(args[2], [largeHfs, 'extract', '/large.bin', largeFile]);
    final actual = await sha256.bind(File(largeFile).openRead()).single;
    final expected = await sha256.bind(largeBytes()).single;
    if (actual != expected || await File(largeFile).length() != size) {
      throw StateError(
        'Independent large-file extraction changed the content.',
      );
    }
    stdout.writeln(
      'PASS: native fsck, DMG extraction, HFS file extraction, '
      'Unicode/multi-leaf catalogs and 65 MiB + 333 byte streamed SHA-256.',
    );
  } finally {
    await directory.delete(recursive: true);
  }
}
