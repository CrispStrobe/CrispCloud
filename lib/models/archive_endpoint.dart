import 'dart:convert';

import 'package:path/path.dart' as p;

import 'file_item.dart';
import 'storage_reference.dart';
import 'transfer_job.dart';

enum ArchiveEndpointFormat {
  zip,
  sevenZip,
  tar,
  tarGzip,
  tarBzip2,
  tarXz,
  tarZstd,
  tarLz4,
  tarLzma,
  tarCompress,
  gzip,
  bzip2,
  xz,
  zstd,
  lz4,
  lzma,
  compress,
  ar,
  cpio,
  xar,
  iso,
  readOnly,
}

enum ArchivePublicationPhase {
  prepared,
  candidateWritten,
  backingUp,
  backedUp,
  installing,
  published,
  cleaningBackup,
  complete,
  restoring,
  restored,
  cleaningCandidate,
  discarded,
  needsReview,
}

enum ArchiveRecoveryAction { finishPublication, restoreOriginal }

/// Capabilities apply to a captured container and its publication backend.
/// A member edit always repacks and verifies the complete enclosing container.
class ArchiveEndpointCapabilities {
  const ArchiveEndpointCapabilities({
    required this.format,
    required this.canPublish,
    required this.encrypted,
    required this.encryptNames,
    this.reason,
  });
  final ArchiveEndpointFormat format;
  final bool canPublish;
  final bool encrypted;
  final bool encryptNames;
  final String? reason;
  bool get supportsMemberWrites =>
      canPublish && format != ArchiveEndpointFormat.readOnly;
  bool get supportsModifiedTime => supportsMemberWrites && !_singlePayload;
  bool get supportsPermissions => supportsMemberWrites && !_singlePayload;
  bool get _singlePayload => const {
    ArchiveEndpointFormat.gzip,
    ArchiveEndpointFormat.bzip2,
    ArchiveEndpointFormat.xz,
    ArchiveEndpointFormat.zstd,
    ArchiveEndpointFormat.lz4,
    ArchiveEndpointFormat.lzma,
    ArchiveEndpointFormat.compress,
  }.contains(format);
  bool get repacksWholeContainer => true;
  bool get supportsDurableDrafts => false;
}

/// Durable, password-free evidence that a separate destination was published
/// before this archive may remove its source members. Recovery rechecks the
/// captured destination through the same persistent storage authority.
class ArchivePublicationDependency {
  ArchivePublicationDependency({
    required this.receiptId,
    required this.storage,
    required FileItem file,
    required this.sha256,
    required this.accessPolicySha256,
  }) : file = file.copyWith(
         metadata: file.metadata == null
             ? null
             : Map.unmodifiable(Map<String, dynamic>.of(file.metadata!)),
       ) {
    if (!_id.hasMatch(receiptId) ||
        !storage.persistent ||
        file.path == null ||
        file.path!.isEmpty ||
        file.path!.contains('\u0000') ||
        utf8.encode(file.path!).length > 16 * 1024 ||
        file.isFolder ||
        file.isSymlink == true ||
        file.size == null ||
        file.size! < 0 ||
        file.size! > ArchivePublicationRecord.maximumContainerBytes ||
        !_hash.hasMatch(sha256) ||
        !_hash.hasMatch(accessPolicySha256)) {
      throw const FormatException('Invalid archive destination dependency.');
    }
  }

  static final _id = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  static final _hash = RegExp(r'^[a-f0-9]{64}$');
  final String receiptId;
  final StorageReference storage;
  final FileItem file;
  final String sha256;
  final String accessPolicySha256;

  factory ArchivePublicationDependency.fromReceipt(
    ArchivePublicationReceipt receipt,
  ) {
    final record = receipt.record;
    if (record.published == null ||
        record.accessPolicySha256 == null ||
        receipt.file.path != record.original.path ||
        receipt.file.size != record.candidateBytes ||
        !const {
          ArchivePublicationPhase.published,
          ArchivePublicationPhase.cleaningBackup,
          ArchivePublicationPhase.cleaningCandidate,
          ArchivePublicationPhase.complete,
        }.contains(record.phase)) {
      throw StateError(
        'Source removal requires a durably verified destination receipt.',
      );
    }
    return ArchivePublicationDependency(
      receiptId: record.id,
      storage: record.storage,
      file: receipt.file,
      sha256: receipt.sha256,
      accessPolicySha256: record.accessPolicySha256!,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'receiptId': receiptId,
    'storage': storage.toJson(),
    'file': transferFileJson(file),
    'sha256': sha256,
    'accessPolicySha256': accessPolicySha256,
  };

  factory ArchivePublicationDependency.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unknown archive dependency version.');
    }
    return ArchivePublicationDependency(
      receiptId: json['receiptId'] as String,
      storage: StorageReference.fromJson(
        Map<String, dynamic>.from(json['storage'] as Map),
      ),
      file: transferFileFromJson(
        Map<String, dynamic>.from(json['file'] as Map),
      ),
      sha256: json['sha256'] as String,
      accessPolicySha256: json['accessPolicySha256'] as String,
    );
  }
}

/// Password-free authority for one bounded publication. Paths are generated
/// from [id], never accepted as arbitrary cleanup targets from a saved record.
class ArchivePublicationRecord {
  ArchivePublicationRecord({
    required this.id,
    required this.storage,
    required this.original,
    required this.originalSha256,
    required this.candidateSha256,
    required this.candidateBytes,
    required this.phase,
    required this.createdAt,
    this.backup,
    this.candidate,
    this.published,
    this.accessPolicySha256,
    this.dependency,
    this.message,
  }) {
    if (!RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(id) ||
        !storage.persistent ||
        original.path == null ||
        original.isFolder ||
        original.isSymlink == true ||
        original.size == null ||
        original.size! < 0 ||
        original.size! > maximumContainerBytes ||
        candidateBytes < 0 ||
        candidateBytes > maximumContainerBytes ||
        !_hash.hasMatch(originalSha256) ||
        !_hash.hasMatch(candidateSha256) ||
        accessPolicySha256 != null && !_hash.hasMatch(accessPolicySha256!) ||
        utf8.encode(original.path!).length > 16 * 1024 ||
        original.path!.contains('\u0000') ||
        (message != null && utf8.encode(message!).length > 16 * 1024)) {
      throw const FormatException('Invalid archive publication evidence.');
    }
    if (dependency != null &&
        (dependency!.storage != storage ||
            dependency!.receiptId == id ||
            dependency!.file.path == original.path)) {
      throw const FormatException(
        'Archive source publication needs a distinct destination on the same storage.',
      );
    }
  }

  static const maximumContainerBytes = 256 * 1024 * 1024;
  static final _hash = RegExp(r'^[a-f0-9]{64}$');
  final String id;
  final StorageReference storage;
  final FileItem original;
  final String originalSha256;
  final String candidateSha256;
  final int candidateBytes;
  final ArchivePublicationPhase phase;
  final DateTime createdAt;
  final FileItem? backup;
  final FileItem? candidate;
  final FileItem? published;
  final String? accessPolicySha256;
  final ArchivePublicationDependency? dependency;
  final String? message;

  bool get isFinished =>
      phase == ArchivePublicationPhase.complete ||
      phase == ArchivePublicationPhase.discarded;
  String candidatePath(p.Context paths) =>
      paths.join(paths.dirname(original.path!), '.crisp-archive-$id.candidate');
  String backupPath(p.Context paths) =>
      paths.join(paths.dirname(original.path!), '.crisp-archive-$id.original');

  ArchivePublicationRecord copyWith({
    ArchivePublicationPhase? phase,
    FileItem? original,
    FileItem? backup,
    FileItem? candidate,
    FileItem? published,
    String? accessPolicySha256,
    String? message,
    bool clearMessage = false,
    bool clearPublished = false,
  }) => ArchivePublicationRecord(
    id: id,
    storage: storage,
    original: original ?? this.original,
    originalSha256: originalSha256,
    candidateSha256: candidateSha256,
    candidateBytes: candidateBytes,
    phase: phase ?? this.phase,
    createdAt: createdAt,
    backup: backup ?? this.backup,
    candidate: candidate ?? this.candidate,
    published: clearPublished ? null : published ?? this.published,
    accessPolicySha256: accessPolicySha256 ?? this.accessPolicySha256,
    dependency: dependency,
    message: clearMessage ? null : message ?? this.message,
  );

  Map<String, dynamic> toJson() => {
    // Older apps must refuse a guarded source publication rather than silently
    // ignore its dependency and recover it as an independent archive edit.
    'version': dependency == null ? 1 : 2,
    'id': id,
    'storage': storage.toJson(),
    'original': transferFileJson(original),
    'originalSha256': originalSha256,
    'candidateSha256': candidateSha256,
    'candidateBytes': candidateBytes,
    'phase': phase.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (backup != null) 'backup': transferFileJson(backup!),
    if (candidate != null) 'candidate': transferFileJson(candidate!),
    if (published != null) 'published': transferFileJson(published!),
    if (accessPolicySha256 != null) 'accessPolicySha256': accessPolicySha256,
    if (dependency != null) 'dependency': dependency!.toJson(),
    if (message != null) 'message': message,
  };

  factory ArchivePublicationRecord.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 && json['version'] != 2 ||
        (json['version'] == 2) != (json['dependency'] != null)) {
      throw const FormatException('Unknown archive publication version.');
    }
    FileItem file(Object? value) =>
        transferFileFromJson(Map<String, dynamic>.from(value as Map));
    return ArchivePublicationRecord(
      id: json['id'] as String,
      storage: StorageReference.fromJson(
        Map<String, dynamic>.from(json['storage'] as Map),
      ),
      original: file(json['original']),
      originalSha256: json['originalSha256'] as String,
      candidateSha256: json['candidateSha256'] as String,
      candidateBytes: json['candidateBytes'] as int,
      phase: ArchivePublicationPhase.values.byName(json['phase'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      backup: json['backup'] == null ? null : file(json['backup']),
      candidate: json['candidate'] == null ? null : file(json['candidate']),
      published: json['published'] == null ? null : file(json['published']),
      accessPolicySha256: json['accessPolicySha256'] as String?,
      dependency: json['dependency'] == null
          ? null
          : ArchivePublicationDependency.fromJson(
              Map<String, dynamic>.from(json['dependency'] as Map),
            ),
      message: json['message'] as String?,
    );
  }
}

class ArchivePublicationReceipt {
  const ArchivePublicationReceipt({
    required this.record,
    required this.file,
    this.cleanupPending = false,
  });
  final ArchivePublicationRecord record;
  final FileItem file;
  final bool cleanupPending;
  String get sha256 => record.candidateSha256;
}

class ArchiveRecoveryInspection {
  const ArchiveRecoveryInspection({
    required this.record,
    required this.canFinish,
    required this.canRestore,
    required this.message,
  });
  final ArchivePublicationRecord record;
  final bool canFinish;
  final bool canRestore;
  final String message;
}

class ArchivePublicationException implements Exception {
  const ArchivePublicationException(this.message, this.record);
  final String message;
  final ArchivePublicationRecord record;
  @override
  String toString() => message;
}
