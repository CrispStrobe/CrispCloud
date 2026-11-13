import '../services/archive_creation_service.dart';
import '../services/archive_workspace.dart';
import '../services/file_operation_service.dart';
import 'file_item.dart';
import 'transfer_job.dart';

bool isArchiveTransferJob(TransferJobRecord job) =>
    job.id.startsWith('archive_create_') ||
    job.id.startsWith('archive_workspace_') ||
    job.entries.firstOrNull?.recovery['archiveKind'] != null;

/// Credential-free creation recipe. The original sources are captured by the
/// normal transfer journal; a password must be supplied again after restart.
class ArchiveCreationJobDefinition {
  ArchiveCreationJobDefinition._({
    required this.name,
    required this.format,
    required this.compression,
    required this.passwordRequired,
    required this.encryptNames,
    required this.files,
    required this.destinationDirectory,
    required this.outputPath,
    required this.publication,
  });

  final String name;
  final ArchiveCreationFormat format;
  final ArchiveCreationCompression compression;
  final bool passwordRequired;
  final bool encryptNames;
  final List<FileItem> files;
  final String destinationDirectory;
  final String outputPath;
  final Map<String, dynamic> publication;

  String? get sourceManifestSha256 =>
      publication['sourceManifestSha256'] as String?;

  ArchiveCreationOptions options({String? password}) {
    if (passwordRequired && (password == null || password.isEmpty)) {
      throw StateError('Enter the archive password again to restart this job.');
    }
    final result = ArchiveCreationOptions(
      name: name,
      format: format,
      compression: compression,
      password: passwordRequired ? password : null,
      encryptNames: encryptNames,
    );
    result.validate();
    return result;
  }

  static ArchiveCreationJobDefinition fromJob(TransferJobRecord job) {
    final header = job.entries.firstOrNull;
    final raw = header?.recovery;
    final format = ArchiveCreationFormat.values
        .where((value) => value.name == raw?['format'])
        .firstOrNull;
    final compression = ArchiveCreationCompression.values
        .where((value) => value.name == raw?['compression'])
        .firstOrNull;
    final name = raw?['name'];
    if (!isArchiveTransferJob(job) ||
        !job.ready ||
        header == null ||
        raw?['archiveVersion'] != 1 ||
        raw?['archiveKind'] != 'create' ||
        name is! String ||
        format == null ||
        compression == null ||
        raw?['passwordRequired'] is! bool ||
        raw?['encryptNames'] is! bool ||
        job.entries.length != job.expectedEntries ||
        job.entries.isEmpty ||
        job.options.kind != FileOperationKind.copy) {
      throw const FormatException('The saved archive recipe is incomplete.');
    }
    final publication = raw?['archivePublication'];
    if (publication != null && publication is! Map) {
      throw const FormatException('The archive publication record is invalid.');
    }
    final checkedPublication = Map<String, dynamic>.from(
      publication as Map? ?? const {},
    );
    for (final key in ['packedSha256', 'sourceManifestSha256']) {
      final hash = checkedPublication[key];
      if (hash != null &&
          (hash is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash))) {
        throw const FormatException('Invalid saved archive content digest.');
      }
    }
    for (final key in ['packedBytes', 'entryCount', 'sourceEntryCount']) {
      final value = checkedPublication[key];
      if (value != null && (value is! int || value < 0)) {
        throw const FormatException('Invalid saved archive size.');
      }
    }
    for (var i = 0; i < job.entries.length; i++) {
      final entry = job.entries[i];
      if (entry.index != i ||
          entry.destination != header.destination ||
          entry.source.path == null ||
          entry.source.path!.isEmpty ||
          entry.source.path!.contains('\u0000') ||
          entry.source.name.isEmpty) {
        throw const FormatException('Invalid saved archive selection.');
      }
    }
    final result = ArchiveCreationJobDefinition._(
      name: name,
      format: format,
      compression: compression,
      passwordRequired: raw!['passwordRequired'] as bool,
      encryptNames: raw['encryptNames'] as bool,
      files: List.unmodifiable(job.entries.map((entry) => entry.source)),
      destinationDirectory: job.targetDirectory,
      outputPath: header.destination,
      publication: Map.unmodifiable(checkedPublication),
    );
    // Only validates the option combination; this placeholder never leaves the
    // parser or grants authority to perform password-protected work.
    result.options(
      password: result.passwordRequired ? 'validation-only' : null,
    );
    return result;
  }
}

FileOperationPlan archiveCreationJobPlan({
  required FileOperationBackend source,
  required FileOperationBackend destination,
  required List<FileItem> files,
  required String destinationDirectory,
  required ArchiveCreationOptions options,
}) {
  options.validate();
  if (files.isEmpty) {
    throw const ArchiveCreationException(ArchiveCreationError.emptySelection);
  }
  final output = destination.paths.join(destinationDirectory, options.name);
  final entries = [
    for (final file in files)
      FileOperationEntry(transferFileFromJson(transferFileJson(file)), output),
  ];
  entries.first.recovery = {
    'archiveVersion': 1,
    'archiveKind': 'create',
    'name': options.name,
    'format': options.format.name,
    'compression': options.compression.name,
    'passwordRequired': options.password != null,
    'encryptNames': options.encryptNames,
  };
  return FileOperationPlan(
    source: source,
    destination: destination,
    targetDirectory: destinationDirectory,
    options: const FileOperationOptions(kind: FileOperationKind.copy),
    entries: entries,
    errors: const [],
  );
}

/// Used only for durable identity and shared scheduler resource claims. It must
/// never be executed by the generic copy/move service.
FileOperationPlan archiveWorkspaceJobPlan(ArchiveWorkspace workspace) {
  final outer = workspace.outermost;
  final entry = FileOperationEntry(outer.file, outer.file.path!)
    ..recovery = {
      'archiveVersion': 1,
      'archiveKind': 'workspace',
      'name': outer.file.name,
      'format': workspace.format,
      'revision': workspace.revision,
      'fingerprint': outer.fingerprint,
      'nestedMemberPaths': workspace.nestedMemberPaths,
    };
  return FileOperationPlan(
    source: outer.source,
    destination: outer.source,
    targetDirectory: outer.source.paths.dirname(outer.file.path!),
    options: const FileOperationOptions(kind: FileOperationKind.copy),
    entries: [entry],
    errors: const [],
  );
}
