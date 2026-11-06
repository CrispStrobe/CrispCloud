import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';

/// Models the same verified-stage-before-replace contract used by local and
/// remote providers, with deterministic failures at each storage boundary.
class HexMemoryBackend extends FileOperationBackend {
  HexMemoryBackend(List<int> initial) {
    bytes = initial;
  }
  final _files = <String, Uint8List>{};
  List<int> get bytes => _files['/sample.bin']!;
  set bytes(List<int> value) =>
      _files['/sample.bin'] = Uint8List.fromList(value);
  @override
  Object identity = Object();
  bool current = true;
  bool verifiedStaging = true;
  bool failWrite = false;
  bool corruptStage = false;
  bool failStatAfterCommit = false;
  int? reportedLength;
  int writesStarted = 0;
  int commits = 0;
  int readCalls = 0;
  void Function()? beforeRead;
  Future<void> Function()? afterStage;
  @override
  bool get isCurrent => current;
  @override
  bool get supportsStagedVerification => verifiedStaging;
  @override
  String get label => 'Captured source';
  @override
  p.Context get paths => p.posix;
  @override
  Future<FileItem?> stat(String path) async {
    if (failStatAfterCommit && commits > 0 && path == '/sample.bin')
      throw StateError('Metadata unavailable');
    final data = _files[path];
    if (data == null) return null;
    return FileItem(
      name: p.basename(path),
      path: path,
      uuid: path,
      isFolder: false,
      isSymlink: false,
      size: path == '/sample.bin' ? reportedLength ?? data.length : data.length,
      updatedAt: DateTime.utc(2025, 1, 1),
    );
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    readCalls++;
    beforeRead?.call();
    final data = _files[file.path]!;
    for (var offset = 0; offset < data.length; offset += 32768) {
      yield Uint8List.sublistView(
        data,
        offset,
        (offset + 32768).clamp(0, data.length),
      );
    }
  }

  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem)? verifyStaged,
    Future<void> Function(Map<String, dynamic>)? checkpoint,
  }) async {
    writesStarted++;
    final builder = BytesBuilder();
    await for (final chunk in data) {
      builder.add(chunk);
    }
    final output = builder.takeBytes();
    expect(output.length, length);
    _files['/.staged'] = output;
    try {
      if (corruptStage && output.isNotEmpty) output[0] ^= 0xff;
      await afterStage?.call();
      if (failWrite) throw StateError('Upload failed');
      await verifyStaged?.call((await stat('/.staged'))!);
      _files[path] = Uint8List.fromList(output);
      commits++;
    } finally {
      _files.remove('/.staged');
    }
  }

  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) =>
      throw StateError('Unverified write must never be used by the hex editor');
  @override
  Future<List<FileItem>> list(String path) async => [];
  @override
  Future<void> createDirectory(String path) async {}
  @override
  Future<void> deleteFile(FileItem file) async {}
  @override
  Future<void> deleteEmptyDirectory(String path) async {}
}
