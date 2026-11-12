// Test tooling only. Generate a writer interoperability corpus, then check it
// with verify_iso_writer_libarchive.py using the system's independent reader:
// dart run test/support/generate_iso_writer_reference.dart /tmp/iso-check
// python3 test/support/verify_iso_writer_libarchive.py /tmp/iso-check
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/archive_iso_writer.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  final directory = arguments.isEmpty
      ? await Directory.systemTemp.createTemp('crisp_iso_reference_')
      : await Directory(arguments.single).create(recursive: true);
  final modified = DateTime.utc(2026, 11, 12, 9, 15, 30);
  final longDirectory = 'directory-${'é' * 240}';
  final paths = <String, String?>{
    'empty': null,
    'folder': null,
    'folder/日本語.txt': 'Unicode contents 日本語\n',
    'emoji-🌍.txt': 'Emoji filename\n',
    'long-${'a' * 170}.txt': 'Long ASCII name\n',
    longDirectory: null,
    '$longDirectory/inside.txt': 'Long directory\n',
    for (var i = 0; i < 8; i++)
      'continuation-$i-${'é' * 400}.txt': 'Continuation block $i\n',
  };
  final expected = <String, Object?>{};
  final entries = <ArchiveWriteEntry>[];
  for (final item in paths.entries) {
    final bytes = item.value == null ? <int>[] : utf8.encode(item.value!);
    final folder = item.value == null;
    final mode = folder ? 0x41ed : 0x81a4;
    entries.add(
      ArchiveWriteEntry(
        path: item.key,
        isDirectory: folder,
        size: bytes.length,
        modified: modified,
        mode: mode,
        readChunks: () => Stream.value(bytes),
      ),
    );
    expected[item.key] = {
      'directory': folder,
      'size': bytes.length,
      'mode': mode,
      'mtime': modified.millisecondsSinceEpoch ~/ 1000,
      if (!folder) 'sha256': sha256.convert(bytes).toString(),
    };
  }
  final file = await File('${directory.path}/writer.iso')
      .open(mode: FileMode.write);
  try {
    await writeIsoArchive(
      entries,
      sink: (bytes) async {
        await file.writeFrom(bytes);
      },
    );
  } finally {
    await file.close();
  }
  await File('${directory.path}/expected.json')
      .writeAsString(jsonEncode(expected));
  stdout.writeln(directory.path);
}
