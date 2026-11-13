import 'package:path/path.dart' as p;

import '../services/archive_creation_service.dart';
import 'file_item.dart';

enum ArchiveJobStatus {
  queued,
  running,
  paused,
  stopping,
  interrupted,
  completed,
  failed,
  cancelled,
}

/// A restartable selection, not a serialization of an open pane or a password.
/// Sources are captured by the creator when an attempt starts. Restarting an
/// interrupted job rebuilds from those source paths after an explicit review.
class ArchiveJobRequest {
  ArchiveJobRequest({
    required this.id,
    required this.storageId,
    required this.created,
    required this.destinationDirectory,
    required this.name,
    required this.format,
    required this.compression,
    required List<FileItem> files,
    this.passwordRequired = false,
    this.encryptNames = false,
  }) : files = List.unmodifiable(files.map(_copyFile)) {
    validate();
  }

  static const maximumSelections = 5000;
  final String id;
  final String storageId;
  final DateTime created;
  final String destinationDirectory;
  final String name;
  final ArchiveCreationFormat format;
  final ArchiveCreationCompression compression;
  final bool passwordRequired;
  final bool encryptNames;
  final List<FileItem> files;
  String get outputPath => p.join(destinationDirectory, name);

  static FileItem _copyFile(FileItem file) => FileItem(
    name: file.name,
    path: file.path,
    uuid: file.uuid,
    isFolder: file.isFolder,
    size: file.size,
    updatedAt: file.updatedAt,
    isSymlink: file.isSymlink,
  );

  static bool validPath(String value) =>
      value.length <= 16384 &&
      !value.contains('\u0000') &&
      p.isAbsolute(value) &&
      p.normalize(value) == value;

  void validate() {
    if (!RegExp(r'^[a-z0-9-]{8,80}$').hasMatch(id) ||
        storageId.isEmpty ||
        storageId.length > 1024 ||
        !validPath(destinationDirectory) ||
        files.isEmpty ||
        files.length > maximumSelections) {
      throw const FormatException('Invalid archive job selection.');
    }
    final paths = <String>{};
    for (final file in files) {
      final path = file.path;
      if (path == null ||
          !validPath(path) ||
          !paths.add(path) ||
          file.name != p.basename(path) ||
          file.isSymlink == true ||
          file.uuid != null && file.uuid!.length > 4096 ||
          file.size != null && (file.size! < 0 || file.size! > 0x200000000)) {
        throw const FormatException('Invalid archive job source.');
      }
    }
    options(password: passwordRequired ? 'validation-only' : null).validate();
  }

  ArchiveCreationOptions options({String? password}) {
    if (passwordRequired && (password == null || password.isEmpty)) {
      throw StateError('Enter the archive password again to restart this job.');
    }
    if (!passwordRequired && password != null) {
      throw StateError('This archive job does not use a password.');
    }
    return ArchiveCreationOptions(
      name: name,
      format: format,
      compression: compression,
      password: password,
      encryptNames: encryptNames,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'storageId': storageId,
    'created': created.toUtc().toIso8601String(),
    'directory': destinationDirectory,
    'name': name,
    'format': format.name,
    'compression': compression.name,
    'passwordRequired': passwordRequired,
    'encryptNames': encryptNames,
    'files': [
      for (final file in files)
        {
          'name': file.name,
          'path': file.path,
          'uuid': file.uuid,
          'directory': file.isFolder,
          'size': file.size,
          'modified': file.updatedAt?.toUtc().toIso8601String(),
        },
    ],
  };

  factory ArchiveJobRequest.fromJson(Map<String, dynamic> value) {
    _keys(value, const {
      'id',
      'storageId',
      'created',
      'directory',
      'name',
      'format',
      'compression',
      'passwordRequired',
      'encryptNames',
      'files',
    });
    final items = value['files'];
    if (items is! List || items.length > maximumSelections) {
      throw const FormatException('Invalid saved archive selection.');
    }
    return ArchiveJobRequest(
      id: value['id'] as String,
      storageId: value['storageId'] as String,
      created: DateTime.parse(value['created'] as String),
      destinationDirectory: value['directory'] as String,
      name: value['name'] as String,
      format: ArchiveCreationFormat.values.byName(value['format'] as String),
      compression: ArchiveCreationCompression.values.byName(
        value['compression'] as String,
      ),
      passwordRequired: value['passwordRequired'] as bool,
      encryptNames: value['encryptNames'] as bool,
      files: [
        for (final item in items)
          _fileFromJson(Map<String, dynamic>.from(item as Map)),
      ],
    );
  }

  static FileItem _fileFromJson(Map<String, dynamic> value) {
    _keys(value, const {
      'name',
      'path',
      'uuid',
      'directory',
      'size',
      'modified',
    });
    return FileItem(
      name: value['name'] as String,
      path: value['path'] as String,
      uuid: value['uuid'] as String?,
      isFolder: value['directory'] as bool,
      size: value['size'] as int?,
      isSymlink: false,
      updatedAt: value['modified'] == null
          ? null
          : DateTime.parse(value['modified'] as String),
    );
  }
}

class ArchiveJobRecord {
  const ArchiveJobRecord({
    required this.request,
    required this.status,
    required this.updated,
    this.attempt = 0,
    this.prepared,
    this.error,
  });
  final ArchiveJobRequest request;
  final ArchiveJobStatus status;
  final DateTime updated;
  final int attempt;
  final ArchiveCreationPrepared? prepared;
  final String? error;
  String get id => request.id;
  bool get terminal => const {
    ArchiveJobStatus.completed,
    ArchiveJobStatus.failed,
    ArchiveJobStatus.cancelled,
  }.contains(status);

  ArchiveJobRecord change(
    ArchiveJobStatus status, {
    DateTime? now,
    int? attempt,
    ArchiveCreationPrepared? prepared,
    bool clearPrepared = false,
    String? error,
  }) => ArchiveJobRecord(
    request: request,
    status: status,
    updated: now ?? DateTime.now().toUtc(),
    attempt: attempt ?? this.attempt,
    prepared: clearPrepared ? null : prepared ?? this.prepared,
    error: error == null
        ? null
        : error.substring(0, error.length.clamp(0, 4096)),
  );

  Map<String, Object?> toJson() => {
    'request': request.toJson(),
    'status': status.name,
    'updated': updated.toUtc().toIso8601String(),
    'attempt': attempt,
    'error': error,
    'prepared': prepared == null
        ? null
        : {
            'path': prepared!.path,
            'entries': prepared!.entryCount,
            'bytes': prepared!.bytes,
            'sha256': prepared!.sha256,
          },
  };

  factory ArchiveJobRecord.fromJson(Map<String, dynamic> value) {
    _keys(value, const {
      'request',
      'status',
      'updated',
      'attempt',
      'error',
      'prepared',
    });
    final request = ArchiveJobRequest.fromJson(
      Map<String, dynamic>.from(value['request'] as Map),
    );
    final saved = value['prepared'];
    ArchiveCreationPrepared? prepared;
    if (saved != null) {
      final data = Map<String, dynamic>.from(saved as Map);
      _keys(data, const {'path', 'entries', 'bytes', 'sha256'});
      prepared = ArchiveCreationPrepared(
        data['path'] as String,
        data['entries'] as int,
        data['bytes'] as int,
        data['sha256'] as String,
      );
      if (prepared.path != request.outputPath ||
          prepared.bytes < 0 ||
          prepared.bytes > 0x200000000 ||
          prepared.entryCount < 0 ||
          prepared.entryCount > ArchiveCreationService.maxEntries ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(prepared.sha256)) {
        throw const FormatException('Invalid archive job publication receipt.');
      }
    }
    final attempt = value['attempt'] as int;
    final error = value['error'] as String?;
    final status = ArchiveJobStatus.values.byName(value['status'] as String);
    if (attempt < 0 ||
        attempt > 1000000 ||
        error != null && error.length > 4096 ||
        status == ArchiveJobStatus.completed && prepared == null) {
      throw const FormatException('Invalid archive job state.');
    }
    return ArchiveJobRecord(
      request: request,
      status: status,
      updated: DateTime.parse(value['updated'] as String),
      attempt: attempt,
      prepared: prepared,
      error: error,
    );
  }
}

void _keys(Map<String, dynamic> value, Set<String> allowed) {
  if (value.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Unsupported archive job fields.');
  }
}
