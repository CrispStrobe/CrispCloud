// Run from the repository root, then use check_archive_tar_writer.py on the
// same directory. The native checker compares independent producer fixtures
// with the production writer's output, including raw PAX timestamp precision.
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/archive_tar_writer.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';

import 'archive_package_writer_fixtures.dart' show packageEntry;
import 'archive_tar_writer_fixtures.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) throw ArgumentError('Supply an output directory.');
  final directory = await Directory(arguments.single).create(recursive: true);
  final manifest = <Map<String, Object?>>[];
  for (final kind in ['ustar', 'gnu', 'pax']) {
    final bytes = referenceTar(kind);
    final archive = await openViewerArchive(bytes, name: 'source.tar');
    try {
      final source = await inspectTarRewrite(bytes, archive);
      if (!source.supported) throw StateError(source.reason!);
      final entries = [
        for (final member in archive.members)
          if (member.name != '/')
            ArchiveWriteEntry(
              path: member.name,
              isDirectory: !member.isFile,
              size: member.size,
              mode: member.posixMode,
              modified: member.modified,
              attributes: source.attributes[member.name] ?? const {},
              readChunks: member.isFile
                  ? () => archive.openMember(member)
                  : null,
            ),
      ];
      final output = await collectArchiveWrite(
        (sink) => writeTarArchive(entries, sink: sink, source: source),
      );
      await File('${directory.path}/source-$kind.tar').writeAsBytes(bytes);
      await File('${directory.path}/$kind.tar').writeAsBytes(output);
      manifest.add({'file': '$kind.tar', 'source': 'source-$kind.tar'});
    } finally {
      await archive.close();
    }
  }
  final entries = [
    packageEntry(
      'new-文書.txt',
      utf8.encode('Independent native extraction\n'),
      mode: 0x1a0,
      modified: DateTime.fromMicrosecondsSinceEpoch(
        1700000000123456,
        isUtc: true,
      ),
      attributes: {
        'tar.uid': 1234567890,
        'tar.gid': 3456789012,
        'tar.uname': 'owner-${'u' * 40}',
        'tar.gname': 'group-${'g' * 40}',
      },
    ),
  ];
  final output = await collectArchiveWrite(
    (sink) => writeTarArchive(entries, sink: sink),
  );
  await File('${directory.path}/new.tar').writeAsBytes(output);
  manifest.add({
    'file': 'new.tar',
    'expected': {
      'path': 'new-文書.txt',
      'uid': 1234567890,
      'gid': 3456789012,
      'uname': 'owner-${'u' * 40}',
      'gname': 'group-${'g' * 40}',
      'mtime': '1700000000.123456',
      'mode': 0x1a0,
      'content': 'Independent native extraction\n',
    },
  });
  await File('${directory.path}/manifest.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
  stdout.writeln(
    'Wrote ${manifest.length} independent TAR verification cases.',
  );
}
