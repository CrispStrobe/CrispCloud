import 'package:path/path.dart' as p;

import '../services/conditional_file_publication.dart';
import 'storage_reference.dart';

enum ExternalEditFailure {
  unsupported,
  invalid,
  sourceChanged,
  tooLarge,
  stagingFailed,
  executableUnavailable,
  launchFailed,
  localChanged,
  conflict,
  uploadFailed,
  uncertain,
  retainedUnavailable,
  busy,
  exportFailed,
  saveFailed,
}

class ExternalEditException implements Exception {
  const ExternalEditException(this.failure);
  final ExternalEditFailure failure;
  @override
  String toString() => 'External editing: ${failure.name}';
}

enum ExternalEditPhase {
  staging,
  ready,
  pending,
  uploading,
  conflict,
  uncertain,
  paused,
}

void _invalid() =>
    throw const ExternalEditException(ExternalEditFailure.invalid);
bool _hash(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
bool _slot(String value) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,119}$').hasMatch(value) &&
    !const {'manifest.json', 'manifest.previous', 'lease'}.contains(value);
const _unchanged = Object();

/// The immutable bytes of a generation that may have reached publication.
/// No opaque provider session ID or credential is stored here.
class ExternalEditAttempt {
  const ExternalEditAttempt({
    required this.generation,
    required this.name,
    required this.length,
    required this.sha256,
    required this.expected,
    this.providerHash,
  });
  final int generation, length;
  final String name, sha256;
  final FilePublicationVersion expected;
  final String? providerHash;

  ExternalEditAttempt prepared(String hash) => ExternalEditAttempt(
    generation: generation,
    name: name,
    length: length,
    sha256: sha256,
    expected: expected,
    providerHash: hash,
  );

  Map<String, dynamic> toJson() => {
    'generation': generation,
    'name': name,
    'length': length,
    'sha256': sha256,
    'expected': expected.toJson(),
    if (providerHash != null) 'providerHash': providerHash,
  };

  factory ExternalEditAttempt.fromJson(Object? value) {
    if (value is! Map ||
        value['generation'] is! int ||
        value['name'] is! String ||
        value['length'] is! int ||
        value['sha256'] is! String ||
        value['providerHash'] != null && value['providerHash'] is! String) {
      _invalid();
    }
    final map = value as Map;
    final result = ExternalEditAttempt(
      generation: map['generation'] as int,
      name: map['name'] as String,
      length: map['length'] as int,
      sha256: map['sha256'] as String,
      expected: FilePublicationVersion.fromJson(map['expected']),
      providerHash: map['providerHash'] as String?,
    );
    if (result.generation < 1 ||
        result.generation > 0x1fffffffffffff ||
        !_slot(result.name) ||
        result.length < 0 ||
        result.length > conditionalFilePublicationLimit ||
        !_hash(result.sha256) ||
        result.providerHash != null && !_hash(result.providerHash!)) {
      _invalid();
    }
    return result;
  }
}

/// Bounded recovery instructions. Restoring this data authorizes neither a
/// process launch nor a remote write; both need an explicit live-source review.
class ExternalEditRecord {
  const ExternalEditRecord({
    required this.reference,
    required this.name,
    required this.workingName,
    required this.created,
    this.baseline,
    this.baselineSha256,
    this.localSha256,
    this.generation = 0,
    this.savedGeneration = 0,
    this.attempt,
    this.launched = false,
    this.phase = ExternalEditPhase.staging,
    this.failure,
  });
  final FileReference reference;
  final String name, workingName;
  final DateTime created;
  final FilePublicationVersion? baseline;
  final String? baselineSha256, localSha256;
  final int generation, savedGeneration;
  final ExternalEditAttempt? attempt;
  final bool launched;
  final ExternalEditPhase phase;
  final ExternalEditFailure? failure;

  bool get canPublish => baseline != null;
  bool get hasLocalChanges => localSha256 != baselineSha256;

  ExternalEditRecord copyWith({
    Object? baseline = _unchanged,
    Object? baselineSha256 = _unchanged,
    Object? localSha256 = _unchanged,
    int? generation,
    int? savedGeneration,
    Object? attempt = _unchanged,
    bool? launched,
    ExternalEditPhase? phase,
    Object? failure = _unchanged,
  }) => ExternalEditRecord(
    reference: reference,
    name: name,
    workingName: workingName,
    created: created,
    baseline: identical(baseline, _unchanged)
        ? this.baseline
        : baseline as FilePublicationVersion?,
    baselineSha256: identical(baselineSha256, _unchanged)
        ? this.baselineSha256
        : baselineSha256 as String?,
    localSha256: identical(localSha256, _unchanged)
        ? this.localSha256
        : localSha256 as String?,
    generation: generation ?? this.generation,
    savedGeneration: savedGeneration ?? this.savedGeneration,
    attempt: identical(attempt, _unchanged)
        ? this.attempt
        : attempt as ExternalEditAttempt?,
    launched: launched ?? this.launched,
    phase: phase ?? this.phase,
    failure: identical(failure, _unchanged)
        ? this.failure
        : failure as ExternalEditFailure?,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'reference': reference.toJson(),
    'name': name,
    'workingName': workingName,
    'created': created.toUtc().toIso8601String(),
    if (baseline != null) 'baseline': baseline!.toJson(),
    if (baselineSha256 != null) 'baselineSha256': baselineSha256,
    if (localSha256 != null) 'localSha256': localSha256,
    'generation': generation,
    'savedGeneration': savedGeneration,
    if (attempt != null) 'attempt': attempt!.toJson(),
    'launched': launched,
    'phase': phase.name,
    if (failure != null) 'failure': failure!.name,
  };

  factory ExternalEditRecord.fromJson(Map<String, dynamic> value) {
    try {
      if (value['version'] != 1 ||
          value['reference'] is! Map ||
          value['name'] is! String ||
          value['workingName'] is! String ||
          value['created'] is! String ||
          value['generation'] is! int ||
          value['savedGeneration'] is! int ||
          value['launched'] is! bool) {
        _invalid();
      }
      final reference = FileReference.fromJson(
        Map<String, dynamic>.from(value['reference'] as Map),
      );
      final result = ExternalEditRecord(
        reference: reference,
        name: value['name'] as String,
        workingName: value['workingName'] as String,
        created: DateTime.parse(value['created'] as String),
        baseline: value['baseline'] == null
            ? null
            : FilePublicationVersion.fromJson(value['baseline']),
        baselineSha256: value['baselineSha256'] as String?,
        localSha256: value['localSha256'] as String?,
        generation: value['generation'] as int,
        savedGeneration: value['savedGeneration'] as int,
        attempt: value['attempt'] == null
            ? null
            : ExternalEditAttempt.fromJson(value['attempt']),
        launched: value['launched'] as bool,
        phase: ExternalEditPhase.values.byName(value['phase'] as String),
        failure: value['failure'] == null
            ? null
            : ExternalEditFailure.values.byName(value['failure'] as String),
      );
      if (reference.storage.kind != 'remote' ||
          !_hash(reference.storage.accountKey) ||
          reference.storage.provider.isEmpty ||
          reference.storage.provider.length > 100 ||
          reference.storage.root.length > 4096 ||
          reference.storage.root.contains('\u0000') ||
          !p.posix.isAbsolute(reference.path) ||
          p.posix.normalize(reference.path) != reference.path ||
          reference.path.length > 4096 ||
          reference.path == '/' ||
          (reference.objectId?.length ?? 0) > 512 ||
          (reference.version?.length ?? 0) > 512 ||
          result.name.isEmpty ||
          result.name.length > 4096 ||
          result.name.contains('\u0000') ||
          !_slot(result.workingName) ||
          result.generation < 0 ||
          result.generation > 0x1fffffffffffff ||
          result.savedGeneration < 0 ||
          result.savedGeneration > result.generation ||
          result.baselineSha256 != null && !_hash(result.baselineSha256!) ||
          result.localSha256 != null && !_hash(result.localSha256!) ||
          result.baseline != null &&
              result.baseline!.path != reference.path.toLowerCase() ||
          result.attempt != null &&
              (result.attempt!.generation > result.generation ||
                  result.attempt!.name == result.workingName ||
                  result.baseline == null ||
                  !result.attempt!.expected.sameObject(result.baseline!))) {
        _invalid();
      }
      return result;
    } catch (_) {
      throw const ExternalEditException(ExternalEditFailure.invalid);
    }
  }
}
