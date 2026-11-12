import 'dart:convert';

import 'package:path/path.dart' as p;

import 'file_item.dart';
import 'storage_reference.dart';
import 'transfer_job.dart';

enum ArchiveEndpointFormat { zip, sevenZip, tar, tarGzip, readOnly }

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
  bool get supportsModifiedTime => format != ArchiveEndpointFormat.readOnly;
  bool get supportsPermissions => format != ArchiveEndpointFormat.readOnly;
  bool get repacksWholeContainer => true;
  bool get supportsDurableDrafts => false;
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
    published: published ?? this.published,
    accessPolicySha256: accessPolicySha256 ?? this.accessPolicySha256,
    message: clearMessage ? null : message ?? this.message,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
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
    if (message != null) 'message': message,
  };

  factory ArchivePublicationRecord.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
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
