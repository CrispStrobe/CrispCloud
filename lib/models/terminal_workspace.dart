import 'package:path/path.dart' as p;

import 'file_item.dart';
import 'storage_reference.dart';

/// A local copy has an explicit account and remote path throughout its life.
enum TerminalWorkspaceStatus { staging, ready, uploading, interrupted }

enum TerminalWorkspaceEntryStatus { pending, ready }

enum TerminalWorkspaceChangeKind { modified, added, deleted, unsafe }

/// Only stable, non-secret remote revision metadata is persisted.
class TerminalWorkspaceFingerprint {
  TerminalWorkspaceFingerprint({
    required this.isDirectory,
    this.objectId,
    this.version,
    this.size,
    Map<String, String> metadata = const {},
  }) : metadata = Map.unmodifiable(metadata);

  final bool isDirectory;
  final String? objectId;
  final String? version;
  final int? size;
  final Map<String, String> metadata;

  factory TerminalWorkspaceFingerprint.fromFile(FileItem file) {
    final raw = file.metadata ?? const <String, dynamic>{};
    final nested = raw['metadata'];
    Object? value(String key) =>
        raw[key] ?? (nested is Map ? nested[key] : null);
    String? first(List<String> keys) {
      for (final key in keys) {
        final candidate = value(key);
        if (candidate != null && candidate.toString().isNotEmpty) {
          return candidate.toString();
        }
      }
      return null;
    }

    final metadata = <String, String>{};
    for (final key in const [
      'etag',
      'eTag',
      'version',
      'versionId',
      'revision',
      'rev',
      'cTag',
      'updatedAt',
      'modificationTime',
      'lastModified',
      'timestamp',
    ]) {
      final candidate = value(key);
      if (candidate != null) metadata[key] = candidate.toString();
    }
    if (file.updatedAt != null) {
      metadata['modified'] = file.updatedAt!.toUtc().toIso8601String();
    }
    return TerminalWorkspaceFingerprint(
      isDirectory: file.isFolder,
      objectId: file.uuid ?? first(const ['id', 'uuid', 'fileId']),
      version: first(const [
        'version',
        'versionId',
        'eTag',
        'etag',
        'rev',
        'cTag',
        'revision',
      ]),
      size: file.isFolder ? null : file.size,
      metadata: metadata,
    );
  }

  bool matches(TerminalWorkspaceFingerprint other) =>
      isDirectory == other.isDirectory &&
      objectId == other.objectId &&
      version == other.version &&
      size == other.size &&
      metadata.length == other.metadata.length &&
      metadata.entries.every(
        (entry) => other.metadata[entry.key] == entry.value,
      );

  /// Directory contents can legitimately change; only identity is an anchor.
  bool sameDirectory(TerminalWorkspaceFingerprint other) =>
      isDirectory && other.isDirectory && objectId == other.objectId;

  Map<String, dynamic> toJson() => {
    'directory': isDirectory,
    if (objectId != null) 'objectId': objectId,
    if (version != null) 'version': version,
    if (size != null) 'size': size,
    'metadata': metadata,
  };

  factory TerminalWorkspaceFingerprint.fromJson(Map<String, dynamic> json) {
    if (json['directory'] is! bool ||
        (json['size'] != null && (json['size'] is! int || json['size'] < 0)) ||
        (json['objectId'] != null && json['objectId'] is! String) ||
        (json['version'] != null && json['version'] is! String)) {
      throw const FormatException('Invalid workspace fingerprint.');
    }
    return TerminalWorkspaceFingerprint(
      isDirectory: json['directory'] as bool,
      objectId: json['objectId'] as String?,
      version: json['version'] as String?,
      size: json['size'] as int?,
      metadata: Map<String, String>.from(json['metadata'] as Map),
    );
  }
}

class TerminalWorkspaceEntry {
  TerminalWorkspaceEntry({
    required this.relativePath,
    required this.remotePath,
    required this.fingerprint,
    this.status = TerminalWorkspaceEntryStatus.pending,
    this.originalDigest,
    this.originalSize,
    Map<String, dynamic>? pendingUpload,
  }) : pendingUpload = pendingUpload == null
           ? null
           : Map.unmodifiable(pendingUpload);

  final String relativePath;
  final String remotePath;
  final TerminalWorkspaceFingerprint fingerprint;
  final TerminalWorkspaceEntryStatus status;
  final String? originalDigest;
  final int? originalSize;

  /// A durable receipt, never authority to replay a remote mutation blindly.
  final Map<String, dynamic>? pendingUpload;
  bool get isDirectory => fingerprint.isDirectory;

  TerminalWorkspaceEntry copyWith({
    TerminalWorkspaceFingerprint? fingerprint,
    TerminalWorkspaceEntryStatus? status,
    String? originalDigest,
    int? originalSize,
    Map<String, dynamic>? pendingUpload,
    bool clearPendingUpload = false,
  }) => TerminalWorkspaceEntry(
    relativePath: relativePath,
    remotePath: remotePath,
    fingerprint: fingerprint ?? this.fingerprint,
    status: status ?? this.status,
    originalDigest: originalDigest ?? this.originalDigest,
    originalSize: originalSize ?? this.originalSize,
    pendingUpload: clearPendingUpload
        ? null
        : pendingUpload ?? this.pendingUpload,
  );

  Map<String, dynamic> toJson() => {
    'relativePath': relativePath,
    'remotePath': remotePath,
    'fingerprint': fingerprint.toJson(),
    'status': status.name,
    if (originalDigest != null) 'originalDigest': originalDigest,
    if (originalSize != null) 'originalSize': originalSize,
    if (pendingUpload != null) 'pendingUpload': pendingUpload,
  };

  factory TerminalWorkspaceEntry.fromJson(Map<String, dynamic> json) {
    final relativePath = json['relativePath'] as String;
    validateTerminalWorkspaceRelativePath(relativePath);
    final digest = json['originalDigest'] as String?;
    if (digest != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid workspace content fingerprint.');
    }
    final size = json['originalSize'];
    if (size != null && (size is! int || size < 0)) {
      throw const FormatException('Invalid workspace content length.');
    }
    return TerminalWorkspaceEntry(
      relativePath: relativePath,
      remotePath: json['remotePath'] as String,
      fingerprint: TerminalWorkspaceFingerprint.fromJson(
        Map<String, dynamic>.from(json['fingerprint'] as Map),
      ),
      status: TerminalWorkspaceEntryStatus.values.byName(
        json['status'] as String,
      ),
      originalDigest: digest,
      originalSize: size as int?,
      pendingUpload: json['pendingUpload'] == null
          ? null
          : Map<String, dynamic>.from(json['pendingUpload'] as Map),
    );
  }
}

class TerminalWorkspace {
  TerminalWorkspace({
    required this.id,
    required this.title,
    required this.storage,
    required this.remoteRoot,
    required this.remoteRootFingerprint,
    required this.directoryPath,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    required this.status,
    required List<TerminalWorkspaceEntry> entries,
    List<String> warnings = const [],
    this.error,
  }) : entries = List.unmodifiable(entries),
       warnings = List.unmodifiable(warnings);

  final String id;
  final String title;
  final StorageReference storage;
  final String remoteRoot;
  final TerminalWorkspaceFingerprint remoteRootFingerprint;
  final String directoryPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
  final TerminalWorkspaceStatus status;
  final List<TerminalWorkspaceEntry> entries;
  final List<String> warnings;
  final String? error;

  TerminalWorkspace copyWith({
    int? revision,
    DateTime? updatedAt,
    TerminalWorkspaceStatus? status,
    List<TerminalWorkspaceEntry>? entries,
    List<String>? warnings,
    String? error,
    bool clearError = false,
  }) => TerminalWorkspace(
    id: id,
    title: title,
    storage: storage,
    remoteRoot: remoteRoot,
    remoteRootFingerprint: remoteRootFingerprint,
    directoryPath: directoryPath,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    revision: revision ?? this.revision,
    status: status ?? this.status,
    entries: entries ?? this.entries,
    warnings: warnings ?? this.warnings,
    error: clearError ? null : error ?? this.error,
  );

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'id': id,
    'title': title,
    'storage': storage.toJson(),
    'remoteRoot': remoteRoot,
    'remoteRootFingerprint': remoteRootFingerprint.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'revision': revision,
    'status': status.name,
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'warnings': warnings,
    if (error != null) 'error': error,
  };

  factory TerminalWorkspace.fromJson(
    Map<String, dynamic> json, {
    required String directoryPath,
  }) {
    if (json['schema'] != 1 ||
        json['revision'] is! int ||
        json['revision'] < 0) {
      throw const FormatException('Unsupported workspace manifest.');
    }
    final id = json['id'] as String;
    validateTerminalWorkspaceId(id);
    final root = json['remoteRoot'] as String;
    validateTerminalWorkspaceRemoteRoot(root);
    final entries = (json['entries'] as List)
        .map(
          (entry) => TerminalWorkspaceEntry.fromJson(
            Map<String, dynamic>.from(entry as Map),
          ),
        )
        .toList();
    final names = <String>{};
    for (final entry in entries) {
      if (!names.add(entry.relativePath.toLowerCase()) ||
          entry.remotePath != p.posix.join(root, entry.relativePath)) {
        throw const FormatException('Ambiguous or escaped workspace entry.');
      }
      if (!entry.isDirectory &&
          ((entry.originalDigest != null && entry.originalSize == null) ||
              (entry.status == TerminalWorkspaceEntryStatus.ready &&
                  entry.originalDigest == null &&
                  entry.pendingUpload == null))) {
        throw const FormatException('Missing workspace file baseline.');
      }
    }
    return TerminalWorkspace(
      id: id,
      title: json['title'] as String,
      storage: StorageReference.fromJson(
        Map<String, dynamic>.from(json['storage'] as Map),
      ),
      remoteRoot: root,
      remoteRootFingerprint: TerminalWorkspaceFingerprint.fromJson(
        Map<String, dynamic>.from(json['remoteRootFingerprint'] as Map),
      ),
      directoryPath: directoryPath,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      revision: json['revision'] as int,
      status: TerminalWorkspaceStatus.values.byName(json['status'] as String),
      entries: entries,
      warnings: List<String>.from(json['warnings'] as List? ?? const []),
      error: json['error'] as String?,
    );
  }
}

/// Immutable review token. Revalidated and copied to a private upload snapshot.
class TerminalWorkspaceChange {
  const TerminalWorkspaceChange({
    required this.workspaceId,
    required this.manifestRevision,
    required this.relativePath,
    required this.remotePath,
    required this.kind,
    this.isDirectory = false,
    this.digest,
    this.size,
    this.reason,
  });

  final String workspaceId;
  final int manifestRevision;
  final String relativePath;
  final String remotePath;
  final TerminalWorkspaceChangeKind kind;
  final bool isDirectory;
  final String? digest;
  final int? size;
  final String? reason;
  bool get canUpload =>
      !isDirectory &&
      digest != null &&
      size != null &&
      (kind == TerminalWorkspaceChangeKind.modified ||
          kind == TerminalWorkspaceChangeKind.added);
}

class TerminalWorkspaceUploadResult {
  TerminalWorkspaceUploadResult({
    required this.workspace,
    required List<String> uploadedPaths,
    required List<String> skippedPaths,
    required Map<String, String> failures,
  }) : uploadedPaths = List.unmodifiable(uploadedPaths),
       skippedPaths = List.unmodifiable(skippedPaths),
       failures = Map.unmodifiable(failures);
  final TerminalWorkspace workspace;
  final List<String> uploadedPaths;
  final List<String> skippedPaths;
  final Map<String, String> failures;
  bool get succeeded => failures.isEmpty;
}

class TerminalWorkspaceException implements Exception {
  const TerminalWorkspaceException(this.message, {this.workspaceId});
  final String message;
  final String? workspaceId;
  @override
  String toString() => message;
}

void validateTerminalWorkspaceId(String id) {
  if (!RegExp(
    r'^ws-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  ).hasMatch(id)) {
    throw const FormatException('Invalid workspace identifier.');
  }
}

void validateTerminalWorkspaceRelativePath(String path) {
  if (path.isEmpty ||
      p.posix.isAbsolute(path) ||
      path.contains('\\') ||
      path.contains(':') ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(path) ||
      p.posix.normalize(path) != path ||
      path
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw const FormatException('Unsafe workspace path.');
  }
}

void validateTerminalWorkspaceRemoteRoot(String path) {
  if (!p.posix.isAbsolute(path) ||
      p.posix.normalize(path) != path ||
      path.contains('\\') ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(path)) {
    throw const FormatException('Unsafe cloud directory.');
  }
}
