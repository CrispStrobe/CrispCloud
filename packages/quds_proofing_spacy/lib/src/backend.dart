import 'analysis.dart';
import 'bundle.dart';
import 'macho_code_identity.dart' show machOCodeSha256;

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
    this.codeSha256,
  });

  final String librarySha256;

  /// Signature-independent Mach-O code digest ([machOCodeSha256]) measured
  /// from the same bytes as [librarySha256] when the library ships inside the
  /// host's signed app bundle; null otherwise. Lets a re-signed copy of
  /// qualified code be recognized without trusting any host claim.
  final String? codeSha256;
  final String bundleSha256;
  final String modelSha256;
  final String resourcesSha256;
  final int abiVersion;
  final int textAbiVersion;
  final int capabilityMask;

  /// Identity for [bundle] with the given native build and capabilities.
  factory SpacyBackendIdentity.forBundle(
    SpacyBundle bundle, {
    required String librarySha256,
    required int capabilityMask,
    String? codeSha256,
  }) => SpacyBackendIdentity(
    librarySha256: librarySha256,
    codeSha256: codeSha256,
    bundleSha256: bundle.manifestSha256,
    modelSha256: bundle.modelFile.sha256,
    resourcesSha256: bundle.resourcesFile.sha256,
    capabilityMask: capabilityMask,
  );

  /// The pinned bundle this identity names, or null for an unknown model.
  SpacyBundle? get bundle => SpacyBundle.forModelSha256(modelSha256);

  /// Validates against [bundle], or against the pinned bundle named by
  /// [modelSha256] when omitted (German, English or French).
  void validate([SpacyBundle? bundle]) {
    final expected = bundle ?? this.bundle;
    if (expected == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(librarySha256) ||
        (codeSha256 != null &&
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(codeSha256!)) ||
        bundleSha256 != expected.manifestSha256 ||
        modelSha256 != expected.modelFile.sha256 ||
        resourcesSha256 != expected.resourcesFile.sha256 ||
        abiVersion != 1 ||
        textAbiVersion != 1 ||
        !expected.capabilityMasks.contains(capabilityMask)) {
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
      capabilityMask == other.capabilityMask &&
      codeSha256 == other.codeSha256;

  @override
  int get hashCode => Object.hash(
    librarySha256,
    bundleSha256,
    modelSha256,
    resourcesSha256,
    abiVersion,
    textAbiVersion,
    capabilityMask,
    codeSha256,
  );

  Map<String, Object> toJson() => {
    'library_sha256': librarySha256,
    'bundle_sha256': bundleSha256,
    'model_sha256': modelSha256,
    'resources_sha256': resourcesSha256,
    'abi_version': abiVersion,
    'text_abi_version': textAbiVersion,
    'capability_mask': capabilityMask,
    'code_sha256': ?codeSha256,
  };
}
