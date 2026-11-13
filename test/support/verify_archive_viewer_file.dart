// Narrow offline check of native viewer routing and source ownership.
// dart --packages=.dart_tool/package_config.json test/support/verify_archive_viewer_file.dart
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' as ar;
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_streamed_reader.dart';
import 'package:crisp_cloud/services/archive_streaming_writer.dart';
import 'package:crisp_cloud/services/archive_viewer_file_io.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:koni_archive/io.dart' as koni;

import 'archive_iso_fixtures.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final directory = await Directory('.dart_tool').createTemp('viewer-wrapper-');
  final spools = await Directory('${directory.path}/spools').create();
  final content = utf8.encode('native viewer wrapper evidence');
  final fixture = ar.Archive()
    ..addFile(ar.ArchiveFile.bytes('evidence.txt', content));
  final zip = ar.ZipEncoder().encode(fixture);
  final tar = ar.TarEncoder().encode(fixture);
  try {
    await IOOverrides.runZoned(() async {
      Future<void> checkArchive(
        String name,
        List<int> bytes, {
        required String format,
        required int limit,
        String? password,
      }) async {
        final file = await File('${directory.path}/$name').writeAsBytes(bytes);
        final archive = await openViewerArchiveFile(
          file.path,
          name: name,
          password: password,
          streaming: true,
        );
        try {
          require(archive.formatName == format, '$name: format');
          require(archive.maxStreamingMemberBytes == limit, '$name: limit');
          require(archive.members.length == 1, '$name: member count');
          final member = archive.members.single;
          require(member.name == 'evidence.txt', '$name: member name');
          require(
            utf8.decode(await archive.readMember(member)) ==
                utf8.decode(content),
            '$name: member content',
          );
        } finally {
          await archive.close();
        }
        require(spools.listSync().isEmpty, '$name: decoded spool leaked');
        print('PASS $name: $format, member limit $limit, content and cleanup');
      }

      await checkArchive(
        'valid.zip',
        zip,
        format: 'zip',
        limit: kArchiveStreamingLimit,
      );
      for (final profile in [
        ('iso', ArchiveEndpointFormat.iso, 'iso'),
        ('rar', ArchiveEndpointFormat.rar, 'rar'),
        ('cbr', ArchiveEndpointFormat.rar, 'rar'),
        ('dmg', ArchiveEndpointFormat.dmg, 'dmg'),
      ]) {
        final packed = await collectArchiveWrite(
          (sink) => writeStreamingArchiveEntries(
            profile.$2,
            [
              ArchiveWriteEntry(
                path: 'evidence.txt',
                isDirectory: false,
                size: content.length,
                modified: DateTime.utc(2026, 11, 13),
                mode: 0x1a4,
                readChunks: () => Stream.value(content),
              ),
            ],
            sink: sink,
            maxOutputBytes: kArchiveStreamingLimit,
          ),
        );
        await checkArchive(
          'valid.${profile.$1}',
          packed,
          format: profile.$3,
          limit: kArchiveStreamingLimit,
        );
      }
      for (final example in [
        (name: 'mislabeled.zip', bytes: tar, format: 'tar'),
        (name: 'mislabeled.7z', bytes: zip, format: 'zip'),
        (name: 'mislabeled.tar', bytes: zip, format: 'zip'),
        (name: 'wrapped-zip.tgz', bytes: gzip.encode(zip), format: 'zip'),
        (name: 'mislabeled.iso', bytes: zip, format: 'zip'),
        (name: 'mislabeled.rar', bytes: zip, format: 'zip'),
        (name: 'mislabeled.dmg', bytes: zip, format: 'zip'),
      ]) {
        await checkArchive(
          example.name,
          example.bytes,
          format: example.format,
          limit: kArchiveReadLimit,
        );
      }

      final isoFixture = IsoFixture();
      const paddedIsoBytes = 80 * 1024 * 1024;
      isoBoth32(isoFixture.bytes, 16 * 2048 + 80, paddedIsoBytes ~/ 2048);
      final paddedIso = await File('${directory.path}/padded.iso')
          .writeAsBytes(isoFixture.bytes);
      final paddedOutput = await paddedIso.open(mode: FileMode.append);
      try {
        await paddedOutput.truncate(paddedIsoBytes);
        await paddedOutput.setPosition(paddedIsoBytes - 1);
        await paddedOutput.writeByte(1);
      } finally {
        await paddedOutput.close();
      }
      final viewedIso = await openViewerArchiveFile(
        paddedIso.path,
        name: 'padded.iso',
        streaming: true,
      );
      try {
        require(viewedIso.formatName == 'iso', 'Padded ISO view format');
        final member = viewedIso.members.singleWhere(
          (member) => member.name == 'HELLO.TXT',
        );
        require(
          utf8.decode(await viewedIso.readMember(member)) == 'hello iso',
          'Padded ISO view content',
        );
      } finally {
        await viewedIso.close();
      }
      final inspectedIso = await openStreamedArchiveSource(
        await koni.FileByteSource.open(paddedIso.path),
        name: 'padded.iso',
      );
      try {
        require(
          inspectedIso.policy.reason?.contains('unmodeled data') == true,
          'Writable ISO open skipped its unclaimed-data preservation scan',
        );
      } finally {
        await inspectedIso.archive.close();
      }
      print(
        'PASS 80 MiB ISO: read-only viewing succeeds; rewrite inspection '
        'still refuses unmodeled data',
      );
      await checkArchive(
        'protected.zip',
        ar.ZipEncoder(password: 'secret').encode(fixture),
        format: 'zip',
        limit: kArchiveReadLimit,
        password: 'secret',
      );

      final cancelled = await File('${directory.path}/cancelled.tgz')
          .writeAsBytes(gzip.encode(tar));
      var sawOwnedSpool = false;
      try {
        final unexpected = await openViewerArchiveFile(
          cancelled.path,
          name: 'cancelled.tgz',
          streaming: true,
          isCancelled: () {
            sawOwnedSpool |= spools.listSync().isNotEmpty;
            return sawOwnedSpool;
          },
        );
        await unexpected.close();
        throw StateError('Cancellation returned an archive');
      } on ArchiveViewException catch (error) {
        require(
          error.message.contains('cancelled'),
          'Wrong cancellation error',
        );
      }
      require(sawOwnedSpool, 'Cancellation did not reach spool creation');
      require(spools.listSync().isEmpty, 'Cancellation leaked a decoded spool');
      print('PASS cancellation: observed temporary spool, no retained output');
    }, getSystemTempDirectory: () => spools);
  } finally {
    await directory.delete(recursive: true);
  }
}
