import 'file_item.dart';
import 'storage_reference.dart';
import '../services/file_operation_options.dart';

enum TransferJobStatus {
  preparing,
  queued,
  running,
  paused,
  waitingForDecision,
  interrupted,
  completed,
  cancelled,
  failed,
}

String transferStatusLabel(TransferJobStatus status) => switch (status) {
  TransferJobStatus.preparing => 'Saving the plan',
  TransferJobStatus.queued => 'Queued',
  TransferJobStatus.running => 'Running',
  TransferJobStatus.paused => 'Paused',
  TransferJobStatus.waitingForDecision => 'Waiting for a conflict decision',
  TransferJobStatus.interrupted => 'Interrupted · review to resume',
  TransferJobStatus.completed => 'Completed',
  TransferJobStatus.cancelled => 'Cancelled · unfinished items retained',
  TransferJobStatus.failed => 'Needs review',
};

/// One reviewed operation. Authentication objects never enter this model.
class TransferJobRecord {
  TransferJobRecord({
    required this.id,
    required this.created,
    required this.source,
    required this.destination,
    required this.targetDirectory,
    required this.options,
    required this.sourceLabel,
    required this.destinationLabel,
    required this.expectedEntries,
    required this.canRecover,
    this.protectedDestinationPaths = const [],
    DateTime? updated,
    this.status = TransferJobStatus.preparing,
    this.priority = 0,
    this.queueOrder = 0,
    this.scheduledAt,
    this.ready = false,
    this.message,
    List<TransferEntryRecord>? entries,
  }) : updated = updated ?? created,
       entries = entries ?? [];

  final String id;
  final DateTime created;
  DateTime updated;
  final StorageReference? source;
  final StorageReference? destination;
  final String targetDirectory;
  FileOperationOptions options;
  final String sourceLabel;
  final String destinationLabel;
  final int expectedEntries;
  final bool canRecover;
  final List<String> protectedDestinationPaths;
  final List<TransferEntryRecord> entries;
  TransferJobStatus status;
  int priority;
  int queueOrder;

  /// Earliest dispatch time. It is persisted as UTC, but never authorizes
  /// unattended recovery after a process restart.
  DateTime? scheduledAt;
  bool ready;
  String? message;

  bool get isFinished => status == TransferJobStatus.completed;
  bool get needsReview =>
      status != TransferJobStatus.completed &&
      status != TransferJobStatus.preparing;

  Map<String, dynamic> toHeaderJson() => {
    'id': id,
    'created': created.toUtc().toIso8601String(),
    'updated': updated.toUtc().toIso8601String(),
    'source': source?.toJson(),
    'destination': destination?.toJson(),
    'targetDirectory': targetDirectory,
    'options': options.toJson(),
    'sourceLabel': sourceLabel,
    'destinationLabel': destinationLabel,
    'expectedEntries': expectedEntries,
    'canRecover': canRecover,
    'protectedDestinationPaths': protectedDestinationPaths,
    'status': status.name,
    'priority': priority,
    'queueOrder': queueOrder,
    'scheduledAt': scheduledAt?.toUtc().toIso8601String(),
    'ready': ready,
    'message': message,
  };

  factory TransferJobRecord.fromHeaderJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || !RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) {
      throw const FormatException('Invalid transfer job identifier.');
    }
    final count = json['expectedEntries'];
    if (count is! int || count < 0) {
      throw const FormatException('Invalid transfer entry count.');
    }
    return TransferJobRecord(
      id: id,
      created: DateTime.parse(json['created'] as String),
      updated: DateTime.parse(json['updated'] as String),
      source: json['source'] == null
          ? null
          : StorageReference.fromJson(
              Map<String, dynamic>.from(json['source'] as Map),
            ),
      destination: json['destination'] == null
          ? null
          : StorageReference.fromJson(
              Map<String, dynamic>.from(json['destination'] as Map),
            ),
      targetDirectory: json['targetDirectory'] as String,
      options: FileOperationOptions.fromJson(
        Map<String, dynamic>.from(json['options'] as Map),
      ),
      sourceLabel: json['sourceLabel'] as String,
      destinationLabel: json['destinationLabel'] as String,
      expectedEntries: count,
      canRecover: json['canRecover'] == true,
      protectedDestinationPaths: List<String>.from(
        json['protectedDestinationPaths'] as List? ?? const [],
      ),
      status: TransferJobStatus.values.byName(json['status'] as String),
      priority: json['priority'] as int? ?? 0,
      queueOrder: json['queueOrder'] as int? ?? 0,
      scheduledAt: json['scheduledAt'] == null
          ? null
          : DateTime.parse(json['scheduledAt'] as String).toUtc(),
      ready: json['ready'] == true,
      message: json['message'] as String?,
    );
  }
}

class TransferEntryRecord {
  TransferEntryRecord({
    required this.index,
    required this.source,
    required this.destination,
    this.existing,
    this.outcome = FileOperationOutcome.pending,
    this.phase = 'queued',
    this.message,
    this.recovery = const {},
  });

  final int index;
  final FileItem source;
  final String destination;
  final FileItem? existing;
  final FileOperationOutcome outcome;
  final String phase;
  final String? message;
  final Map<String, dynamic> recovery;

  Map<String, dynamic> toJson() => {
    'index': index,
    'source': transferFileJson(source),
    'destination': destination,
    'existing': existing == null ? null : transferFileJson(existing!),
    'outcome': outcome.name,
    'phase': phase,
    'message': message,
    'recovery': recovery,
  };

  factory TransferEntryRecord.fromJson(Map<String, dynamic> json) {
    final index = json['index'];
    if (index is! int || index < 0) {
      throw const FormatException('Invalid transfer entry index.');
    }
    return TransferEntryRecord(
      index: index,
      source: transferFileFromJson(
        Map<String, dynamic>.from(json['source'] as Map),
      ),
      destination: json['destination'] as String,
      existing: json['existing'] == null
          ? null
          : transferFileFromJson(
              Map<String, dynamic>.from(json['existing'] as Map),
            ),
      outcome: FileOperationOutcome.values.byName(json['outcome'] as String),
      phase: json['phase'] as String,
      message: json['message'] as String?,
      recovery: Map<String, dynamic>.from(json['recovery'] as Map? ?? const {}),
    );
  }
}

/// Only object/version metadata is persisted, never arbitrary provider fields.
Map<String, dynamic> transferFileJson(FileItem file) => {
  'name': file.name,
  'path': file.path,
  'uuid': file.uuid,
  'storageId': file.storageId,
  'isFolder': file.isFolder,
  'size': file.size,
  'updatedAt': file.updatedAt?.toUtc().toIso8601String(),
  'isSymlink': file.isSymlink,
  'symlinkTarget': file.symlinkTarget,
  'metadata': {
    for (final key in ['version', 'versionId', 'eTag', 'etag', 'rev', 'cTag'])
      if (file.metadata?[key] != null) key: file.metadata![key].toString(),
  },
};

FileItem transferFileFromJson(Map<String, dynamic> json) {
  final path = json['path'];
  if (path is! String || path.isEmpty || path.contains('\u0000')) {
    throw const FormatException('Invalid transfer source path.');
  }
  return FileItem(
    name: json['name'] as String,
    path: path,
    uuid: json['uuid'] as String?,
    storageId: json['storageId'] as String?,
    isFolder: json['isFolder'] == true,
    size: json['size'] as int?,
    updatedAt: json['updatedAt'] == null
        ? null
        : DateTime.parse(json['updatedAt'] as String),
    isSymlink: json['isSymlink'] as bool?,
    symlinkTarget: json['symlinkTarget'] as String?,
    metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
  );
}
