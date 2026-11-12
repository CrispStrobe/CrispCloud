import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

class ArchiveDirectoryTestBackend extends LocalOperationBackend {
  ArchiveDirectoryTestBackend({bool Function()? current})
    : super(LocalFileService(), isCurrent: current ?? (() => true));
  FutureOr<void> Function(String, List<FileItem>)? afterList;
  FutureOr<void> Function(FileItem)? beforeRead;
  FutureOr<void> Function(FileItem, String)? beforeMove;
  FutureOr<void> Function(FileItem, String)? afterMove;
  final List<String> moves = [];

  @override
  Future<List<FileItem>> list(String path) async {
    final files = await super.list(path);
    await afterList?.call(path, files);
    return files;
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    await beforeRead?.call(file);
    yield* super.readFile(file);
  }

  @override
  Future<bool> moveNoReplace(FileItem file, String target) async {
    await beforeMove?.call(file, target);
    final result = await super.moveNoReplace(file, target);
    if (result) moves.add('${file.path}:$target');
    await afterMove?.call(file, target);
    return result;
  }
}

Future<Uint8List> createDirectorySyncArchive(
  Map<String, List<int>> files, {
  koni.ArchiveWriteFormat format = const koni.ZipWriteFormat(),
  Set<String> directories = const {},
  String? password,
  bool encryptNames = false,
}) async {
  final sink = koni.BytesBuilderSink();
  final writer = koni.Archive.create(
    sink,
    format: format,
    options: koni.ArchiveWriteOptions(
      password: password,
      encryptHeader: encryptNames,
    ),
  );
  for (final directory in directories) {
    await writer.addEntry(
      koni.ArchiveEntrySpec(
        path: directory,
        type: koni.ArchiveEntryType.directory,
        posixMode: 0x1c0,
        modified: DateTime.utc(2025, 1, 2, 3, 4, 6),
      ),
    );
  }
  for (final file in files.entries) {
    await writer.addBytes(
      koni.ArchiveEntrySpec(
        path: file.key,
        posixMode: 0x1a0,
        modified: DateTime.utc(2025, 1, 2, 3, 4, 6),
      ),
      Uint8List.fromList(file.value),
    );
  }
  await writer.close();
  await sink.close();
  return sink.takeBytes();
}

Future<File> writeDirectorySyncSource(
  String root,
  String path,
  List<int> bytes,
) async {
  final file = File('$root/$path');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  await file.setLastModified(DateTime.utc(2025, 6, 7, 8, 9, 10));
  return file;
}
