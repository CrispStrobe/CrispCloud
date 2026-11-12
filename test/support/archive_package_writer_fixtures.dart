import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codec;
import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/archive_package_writers.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';

import 'archive_package_fixtures.dart';

ArchiveWriteEntry packageEntry(
  String path,
  List<int> bytes, {
  bool directory = false,
  int? mode,
  DateTime? modified,
  Map<String, Object?> attributes = const {},
  int chunkSize = 17,
}) {
  final captured = Uint8List.fromList(bytes);
  return ArchiveWriteEntry(
    path: path,
    isDirectory: directory,
    size: captured.length,
    mode: mode,
    modified: modified,
    attributes: attributes,
    readChunks: () async* {
      for (var at = 0; at < captured.length; at += chunkSize) {
        yield captured.sublist(at, (at + chunkSize).clamp(0, captured.length));
      }
    },
  );
}

class PackageRewriteFixture {
  PackageRewriteFixture(this.kind, this.archive, this.inspection, this.entries);
  final String kind;
  final ViewerArchive archive;
  final ArchiveRewriteInspection inspection;
  final List<ArchiveWriteEntry> entries;

  static Future<PackageRewriteFixture> open(
    Uint8List bytes,
    String kind,
  ) async {
    final archive = await openViewerArchive(bytes, name: 'fixture.$kind');
    final inspection = await inspectPackageRewrite(bytes, kind, archive);
    return PackageRewriteFixture(kind, archive, inspection, [
      if (inspection.supported)
        for (final member in archive.members)
          ArchiveWriteEntry(
            path: member.name,
            isDirectory: !member.isFile,
            size: member.size,
            mode: member.posixMode,
            modified: member.modified,
            attributes: inspection.attributes[member.name] ?? const {},
            readChunks: () async* {
              yield await archive.readMember(member);
            },
          ),
    ]);
  }

  Future<Uint8List> repack() =>
      packageOutput(kind, entries, source: inspection);
  Future<void> close() => archive.close();
}

Future<Uint8List> packageOutput(
  String kind,
  List<ArchiveWriteEntry> entries, {
  ArchiveRewriteInspection? source,
  int limit = 256 * 1024 * 1024,
  bool Function()? isCancelled,
}) => collectArchiveWrite(
  (sink) => writePackageArchive(
    kind,
    entries,
    sink: sink,
    source: source,
    maxOutputBytes: limit,
    isCancelled: isCancelled,
  ),
  maxBytes: limit,
);

Uint8List packageTar(Map<String, List<int>> files) {
  final archive = codec.Archive();
  for (final entry in files.entries) {
    archive.addFile(
      codec.ArchiveFile(entry.key, entry.value.length, entry.value)
        ..mode = 0x1a4
        ..lastModTime = 1700000000,
    );
  }
  return Uint8List.fromList(codec.TarEncoder().encode(archive));
}

({Uint8List archive, Uint8List control, Uint8List data}) debianFixture({
  String text = 'Debian payload\n',
  String? checksumFor,
  bool includeChecksums = true,
}) {
  final contents = utf8.encode(text);
  final checksum = md5.convert(utf8.encode(checksumFor ?? text));
  final controlTar = packageTar({
    'control': utf8.encode(
      'Package: crisp-fixture\nVersion: 1.0\n'
      'Architecture: all\nMaintainer: Fixture <fixture@example.test>\n'
      'Description: Independent test package\n',
    ),
    if (includeChecksums)
      'md5sums': utf8.encode('$checksum  usr/share/crisp/data.txt\n'),
  });
  final dataTar = packageTar({'usr/share/crisp/data.txt': contents});
  final control = Uint8List.fromList(
    const codec.GZipEncoder().encode(controlTar),
  );
  final data = Uint8List.fromList(const codec.GZipEncoder().encode(dataTar));
  return (
    archive: arFixture([
      const PackageFixtureEntry('debian-binary', [50, 46, 48, 10]),
      PackageFixtureEntry('control.tar.gz', control),
      PackageFixtureEntry('data.tar.gz', data),
    ]),
    control: control,
    data: data,
  );
}
