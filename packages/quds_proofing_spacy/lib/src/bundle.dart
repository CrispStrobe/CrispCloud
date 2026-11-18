/// One closed, original-model profile. These are externally frozen pins, not
/// hashes accepted from an untrusted manifest supplied beside the model.
const spacySourceWheelSha256 =
    'fec69fec52b1780f2d269d5af7582a5e28028738bd3190532459aeb473bfa3e7';
const spacyBundleManifestSha256 =
    'd599768375de3dc56abcca5cf1d49da0015857f9d3a10640aebb5317ef5d427e';
const spacyModelSha256 =
    'fae2e6ab8d6c611d7a9dddd4b3259a871a1d2f95cacc8259f49c1e4ff31ff6cd';
const spacyResourcesSha256 =
    'b42496cc373ada57a67ed2f4c2c25f8d22f80c08db5841a7cdb91c8a6e18562a';

final class SpacyArtifact {
  const SpacyArtifact(this.file, this.sha256, this.bytes);
  final String file;
  final String sha256;
  final int bytes;
}

/// Immutable admission contract for German de_core_news_sm 3.8.0, F32 CPU.
/// Native ABI/profile validation is additional to authenticating these files.
/// No model weights or native binary are included in this Dart package.
final class SpacyBundle {
  const SpacyBundle.germanF32();

  String get modelName => 'de_core_news_sm';
  String get modelVersion => '3.8.0';
  String get manifestSha256 => spacyBundleManifestSha256;
  String get sourceWheelSha256 => spacySourceWheelSha256;
  int get formatVersion => 1;

  static const model = SpacyArtifact('model.gguf', spacyModelSha256, 7383104);
  static const resources = SpacyArtifact(
    'resources.json',
    spacyResourcesSha256,
    1404948,
  );
  static const license = SpacyArtifact(
    'LICENSE',
    '3933c176979b68bc6d0bcc902c7d6c130f1d127f476f17ba5cdba8d99cfd0012',
    1056,
  );
  static const sourceNotices = SpacyArtifact(
    'LICENSES_SOURCES',
    '0c3ab78745569d848b7c83a486183bce42b9643561084d6d6f67eb0229c79869',
    13470,
  );
  static const files = [model, resources, license, sourceNotices];
}
