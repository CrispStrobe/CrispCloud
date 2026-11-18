import 'analysis.dart';
import 'bundle.dart';

/// Send only paths/options to a worker; create all native pointers inside open.
abstract interface class SpacyBackendFactory {
  Future<SpacyBackend> open(SpacyBundle bundle);
}

/// Owned by one worker. Analyze and dispose must never overlap. Results contain
/// only immutable Dart values and can outlive the backend's native context.
abstract interface class SpacyBackend {
  SpacyBackendIdentity get identity;
  Future<LinguisticAnalysisResult> analyze(LinguisticAnalysisRequest request);
  Future<void> dispose();
}

final class SpacyUnavailableException implements Exception {
  const SpacyUnavailableException(this.message);
  final String message;
  @override
  String toString() => message;
}

final class SpacyBackendIdentity {
  const SpacyBackendIdentity({
    required this.librarySha256,
    this.bundleSha256 = spacyBundleManifestSha256,
    this.modelSha256 = spacyModelSha256,
    this.resourcesSha256 = spacyResourcesSha256,
    this.abiVersion = 1,
    this.textAbiVersion = 1,
    this.capabilityMask = 15,
  });

  final String librarySha256;
  final String bundleSha256;
  final String modelSha256;
  final String resourcesSha256;
  final int abiVersion;
  final int textAbiVersion;
  final int capabilityMask;

  void validate([SpacyBundle? bundle]) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(librarySha256) ||
        bundleSha256 != spacyBundleManifestSha256 ||
        modelSha256 != spacyModelSha256 ||
        resourcesSha256 != spacyResourcesSha256 ||
        abiVersion != 1 ||
        textAbiVersion != 1 ||
        capabilityMask != 15) {
      throw const FormatException('Unsupported spaCy runtime/model identity.');
    }
  }

  bool sameIdentity(SpacyBackendIdentity other) => this == other;

  @override
  bool operator ==(Object other) =>
      other is SpacyBackendIdentity &&
      librarySha256 == other.librarySha256 &&
      bundleSha256 == other.bundleSha256 &&
      modelSha256 == other.modelSha256 &&
      resourcesSha256 == other.resourcesSha256 &&
      abiVersion == other.abiVersion &&
      textAbiVersion == other.textAbiVersion &&
      capabilityMask == other.capabilityMask;

  @override
  int get hashCode => Object.hash(
    librarySha256,
    bundleSha256,
    modelSha256,
    resourcesSha256,
    abiVersion,
    textAbiVersion,
    capabilityMask,
  );

  Map<String, Object> toJson() => {
    'library_sha256': librarySha256,
    'bundle_sha256': bundleSha256,
    'model_sha256': modelSha256,
    'resources_sha256': resourcesSha256,
    'abi_version': abiVersion,
    'text_abi_version': textAbiVersion,
    'capability_mask': capabilityMask,
  };
}
