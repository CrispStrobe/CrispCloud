// Portable codec smoke check: run directly in Dart or compile to JavaScript.
// This covers browser compilation/decoding, not native publication or large
// browser writes. The native workspace remains separately platform-gated.
// ignore_for_file: avoid_print
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_dmg_reader.dart';
import 'package:crisp_cloud/services/archive_dmg_writer.dart';
import 'package:crisp_cloud/services/archive_iso_reader.dart';
import 'package:crisp_cloud/services/archive_iso_writer.dart';
import 'package:crisp_cloud/services/archive_rar_stored_reader.dart';
import 'package:crisp_cloud/services/archive_rar_stored_writer.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

Future<void> main() async {
  final content = Uint8List.fromList(
    List.generate(8193, (index) => index % 251),
  );
  final entries = [
    ArchiveWriteEntry(
      path: 'hello.txt',
      isDirectory: false,
      size: content.length,
      modified: DateTime.utc(2026, 11, 13, 1, 2, 3, 123),
      mode: 0x1a4,
      readChunks: () => Stream.value(content),
    ),
  ];
  for (final name in ['iso', 'rar', 'dmg']) {
    final bytes = await collectArchiveWrite(
      (sink) => switch (name) {
        'iso' => writeIsoArchive(entries, sink: sink),
        'rar' => writeStoredRarArchive(
          entries,
          sink: sink,
          maxOutputBytes: kArchiveReadLimit,
        ),
        _ => writeDmgArchive(entries, sink: sink),
      },
    );
    final source = koni.MemoryByteSource(bytes);
    final archive = await switch (name) {
      'iso' => openIsoArchive(source, maxMemberBytes: kArchiveReadLimit),
      'rar' => openStoredRarArchive(source, maxBytes: kArchiveReadLimit),
      _ => openDmgArchive(source, maxMemberBytes: kArchiveReadLimit),
    };
    try {
      final member = archive.members.singleWhere(
        (entry) => entry.isFile && entry.name.endsWith('hello.txt'),
      );
      final decoded = await archive.readMember(member);
      if (decoded.length != content.length ||
          Iterable.generate(content.length)
              .any((at) => decoded[at] != content[at])) {
        throw StateError('$name portable payload differs');
      }
      print(
        'PASS portable $name: ${bytes.length} packed bytes; complete payload verified',
      );
    } finally {
      await archive.close();
    }
  }
}
