import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../services/file_split_service.dart';
import 'file_item.dart';
import 'transfer_job.dart';

enum IntegrityOperationKind { split, combine }

bool isIntegrityTransferJob(TransferJobRecord job) =>
    job.id.startsWith('integrity_split_') ||
    job.id.startsWith('integrity_combine_') ||
    job.entries.firstOrNull?.recovery['integrityKind'] != null;

Map<String, dynamic> integrityFileJson(FileItem file) => {
  ...transferFileJson(file),
  'metadata': {
    for (final key in const [
      'version',
      'versionId',
      'eTag',
      'etag',
      'rev',
      'revision',
      'cTag',
      'content_hash',
    ])
      if (file.metadata?[key] != null) key: file.metadata![key].toString(),
  },
};

class IntegrityRecoveryPart {
  const IntegrityRecoveryPart({
    required this.index,
    required this.source,
    required this.destination,
    required this.relativePath,
    required this.size,
    required this.sha256,
  });
  final int index;
  final FileItem source;
  final String destination;
  final String relativePath;
  final int size;
  final String sha256;
}

/// Immutable operation definition reconstructed from the normal transfer log.
/// Mutable backend stages and confirmations live beside this definition on
/// their own entry, so each part checkpoint remains small.
class IntegrityRecoveryDefinition {
  IntegrityRecoveryDefinition._({
    required this.kind,
    required this.originalName,
    required this.totalBytes,
    required this.chunkSize,
    required this.expectedSha256,
    required this.destinationDirectory,
    required this.parts,
    required this.outputPath,
    required this.sourceFile,
    this.inputManifest,
    this.inputManifestFingerprint,
    this.legacy = false,
  });
  final IntegrityOperationKind kind;
  final String originalName;
  final int totalBytes;
  final int chunkSize;
  final String expectedSha256;
  final FileItem destinationDirectory;
  final List<IntegrityRecoveryPart> parts;
  final String outputPath;
  final FileItem sourceFile;
  final FileItem? inputManifest;
  final String? inputManifestFingerprint;
  final bool legacy;

  SplitManifest get completeManifest => SplitManifest(
    originalName: originalName,
    totalBytes: totalBytes,
    chunkSize: chunkSize,
    status: SplitManifestStatus.complete,
    parts: [
      for (final part in parts)
        SplitPart(
          index: part.index,
          path: part.relativePath,
          size: part.size,
          sha256: part.sha256,
        ),
    ],
    sha256: expectedSha256,
  );

  static IntegrityRecoveryDefinition fromJob(TransferJobRecord job) {
    if (!isIntegrityTransferJob(job) || !job.ready || job.entries.isEmpty) {
      throw StateError(
        'The saved integrity plan is incomplete. No output can be resumed.',
      );
    }
    final header = job.entries.first;
    final value = header.recovery;
    final kind = IntegrityOperationKind.values
        .where((kind) => kind.name == value['integrityKind'])
        .firstOrNull;
    final total = value['totalBytes'];
    final chunk = value['chunkSize'];
    final name = value['originalName'];
    final hash = value['expectedSha256'];
    final rawSource = value['sourceFile'];
    final rawDirectory = value['destinationDirectory'];
    if (value['integrityVersion'] != 1 ||
        kind == null ||
        total is! int ||
        total < 0 ||
        chunk is! int ||
        chunk <= 0 ||
        name is! String ||
        name.isEmpty ||
        name.length > 8192 ||
        hash is! String ||
        !_digest.hasMatch(hash) ||
        rawSource is! Map ||
        rawDirectory is! Map ||
        job.entries.length < 2 ||
        job.entries.length > kSplitMaxParts + 1 ||
        job.entries.length != job.expectedEntries) {
      throw const FormatException('Invalid saved integrity operation.');
    }
    final parts = <IntegrityRecoveryPart>[];
    var bytes = 0;
    for (var index = 1; index < job.entries.length; index++) {
      final entry = job.entries[index];
      final part = entry.recovery;
      final size = part['partSize'];
      final hash = part['partSha256'];
      final path = part['relativePath'];
      final captured = part['sourceFile'];
      if (entry.index != index ||
          part['integrityPart'] != index ||
          size is! int ||
          size < 0 ||
          hash is! String ||
          !_digest.hasMatch(hash) ||
          path is! String ||
          path.isEmpty ||
          path.length > 8192 ||
          captured is! Map) {
        throw const FormatException('Invalid saved integrity part.');
      }
      bytes += size;
      parts.add(
        IntegrityRecoveryPart(
          index: index,
          source: transferFileFromJson(Map<String, dynamic>.from(captured)),
          destination: entry.destination,
          relativePath: path,
          size: size,
          sha256: hash,
        ),
      );
    }
    if (bytes != total) {
      throw const FormatException('The saved integrity sizes do not agree.');
    }
    final rawManifest = value['inputManifest'];
    final fingerprint = value['inputManifestFingerprint'];
    if (rawManifest != null &&
        (rawManifest is! Map ||
            fingerprint is! String ||
            !_digest.hasMatch(fingerprint))) {
      throw const FormatException('Invalid saved input manifest.');
    }
    final result = IntegrityRecoveryDefinition._(
      kind: kind,
      originalName: name,
      totalBytes: total,
      chunkSize: chunk,
      expectedSha256: hash,
      destinationDirectory: transferFileFromJson(
        Map<String, dynamic>.from(rawDirectory),
      ),
      parts: List.unmodifiable(parts),
      outputPath: header.destination,
      sourceFile: transferFileFromJson(Map<String, dynamic>.from(rawSource)),
      inputManifest: rawManifest == null
          ? null
          : transferFileFromJson(Map<String, dynamic>.from(rawManifest as Map)),
      inputManifestFingerprint: fingerprint as String?,
      legacy: value['legacy'] == true,
    );
    if (!result.legacy) {
      // Reuse the manifest's size/count validation for a complete definition.
      SplitManifest.decode(result.completeManifest.encode());
    }
    if (kind == IntegrityOperationKind.combine &&
        !result.legacy &&
        result.inputManifest == null) {
      throw const FormatException('The saved combine manifest is missing.');
    }
    return result;
  }

  static final _digest = RegExp(r'^[a-f0-9]{64}$');
}

class IntegrityRecoveryReview {
  const IntegrityRecoveryReview({
    required this.jobId,
    required this.definition,
    required this.verifiedOutputs,
    required this.retainedPaths,
    required this.fingerprint,
    this.manifest,
    this.output,
  });
  final String jobId;
  final IntegrityRecoveryDefinition definition;
  final List<FileItem?> verifiedOutputs;
  final List<String> retainedPaths;
  final String fingerprint;
  final SplitManifest? manifest;
  final FileItem? output;
  int get verifiedParts => verifiedOutputs.whereType<FileItem>().length;
  bool get reconcilesOutput =>
      definition.kind == IntegrityOperationKind.combine && output != null;

  static String evidenceFingerprint(Object values) =>
      sha256.convert(utf8.encode(jsonEncode(values))).toString();
}
