import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'cloud_object_reader.dart';
import 'file_operation_service.dart';
import 'storage_transfer_contract.dart';

/// Read-only, account-bound copy view. Provider IDs remain the source address;
/// portable destination names are separate and reviewed in the ordinary plan.
class CloudObjectCopySource extends FileOperationBackend {
  CloudObjectCopySource(this.original, this.reader);
  final FileOperationBackend original;
  final CloudObjectReader reader;
  final _parents = <String, String>{};
  @override
  Object get identity => original.identity;
  @override
  String get label => original.label;
  @override
  p.Context get paths => p.posix;
  @override
  bool get isCurrent => original.isCurrent;
  @override
  StorageTransferCapabilities get capabilities =>
      const StorageTransferCapabilities(
        boundedDownload: true,
        caseSensitivity: StorageCaseSensitivity.sensitive,
      );

  void _check() {
    if (!isCurrent) throw StateError('The original copy source disconnected.');
  }

  String _id(String path) {
    final id = paths.basename(path);
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,1024}$').hasMatch(id)) {
      throw StateError('Invalid provider object identity. Refresh the source.');
    }
    return id;
  }

  static String portableName(String name) {
    var result = name
        .replaceAll(RegExp(r'[\x00-\x1f\x7f/\\<>:"|?*]'), '_')
        .replaceFirst(RegExp(r'[ .]+$'), '');
    if (result.isEmpty || result == '.' || result == '..') result = 'unnamed';
    if (RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
      caseSensitive: false,
    ).hasMatch(result)) {
      result = '_$result';
    }
    if (utf8.encode(result).length > 240) {
      throw StateError(
        'The destination filename is too long. Rename the source before copying.',
      );
    }
    return result;
  }

  FileItem _item(Map<String, dynamic> value, String parent) {
    final id = value['id'] as String;
    _id(id);
    final raw = value['name'] as String;
    var name = portableName(raw);
    final extension = value['downloadExtension'] as String?;
    if (extension != null && !name.toLowerCase().endsWith('.$extension')) {
      name += '.$extension';
    }
    name = portableName(name);
    return FileItem(
      name: name,
      path: paths.join(parent, id),
      uuid: id,
      isFolder: value['mimeType'] == 'application/vnd.google-apps.folder',
      size: extension != null ? null : int.tryParse('${value['size']}'),
      updatedAt: DateTime.tryParse('${value['modifiedTime']}'),
      metadata: {
        ...value,
        'sourceDisplayName': raw,
        'destinationNameMapped': raw != name,
      },
    );
  }

  Future<List<FileItem>> capture(List<FileItem> selection) async {
    final result = <FileItem>[];
    for (final file in selection) {
      _check();
      final id = file.uuid;
      if (id == null || id.isEmpty) {
        throw StateError('Refresh Google Drive before copying these items.');
      }
      final metadata = await reader.readObjectMetadata(id);
      _check();
      if (metadata['id'] != id) {
        throw StateError('The provider returned a different source object.');
      }
      result.add(_item(metadata, '/.provider-objects'));
    }
    // A selected direct child is already included by its selected folder.
    final folders = result.where((f) => f.isFolder).map((f) => f.uuid).toSet();
    return result
        .where(
          (f) => !((f.metadata?['parents'] as List?) ?? const []).any(
            folders.contains,
          ),
        )
        .toList();
  }

  @override
  String destinationNameFor(FileItem file) => file.name;
  @override
  bool isValidListedChild(String parent, FileItem child) =>
      child.path != null &&
      paths.dirname(child.path!) == parent &&
      paths.basename(child.path!) == child.uuid &&
      !child.name.contains('/') &&
      !child.name.contains('\\') &&
      child.name.isNotEmpty;

  @override
  Future<FileItem?> stat(String path) async {
    _check();
    final id = _id(path);
    final value = await reader.readObjectMetadata(id);
    _check();
    if (value['id'] != id) {
      throw StateError('The source object identity changed.');
    }
    final parent = _parents[path];
    if (parent != null &&
        !((value['parents'] as List?) ?? const []).contains(parent)) {
      throw StateError('A source item moved out of its reviewed directory.');
    }
    return _item(value, paths.dirname(path));
  }

  @override
  Future<List<FileItem>> list(String path) async {
    _check();
    final id = _id(path);
    final values = await reader.listObjectChildren(id);
    _check();
    final result = <FileItem>[];
    for (final value in values) {
      if (!((value['parents'] as List?) ?? const []).contains(id)) {
        throw StateError(
          'A listed item does not belong to the requested directory.',
        );
      }
      final file = _item(value, path);
      _parents[file.path!] = id;
      result.add(file);
    }
    return result;
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    _check();
    if (_id(file.path!) != file.uuid) {
      throw StateError('Source identity changed.');
    }
    await for (final part in reader.readObjectContents(file.uuid!)) {
      _check();
      yield part;
    }
    _check();
  }

  @override
  Future<void> createDirectory(String path) async =>
      throw UnsupportedError('Read-only copy source.');
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async => throw UnsupportedError('Read-only copy source.');
  @override
  Future<void> deleteFile(FileItem file) async =>
      throw UnsupportedError('Read-only copy source.');
  @override
  Future<void> deleteEmptyDirectory(String path) async =>
      throw UnsupportedError('Read-only copy source.');
}
