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

/// Analysis languages with a pinned bundle. German keeps its exact de-DE
/// scope (the only qualified German locale); English and French accept any
/// region of their language because the bundles are not region-specific.
enum SpacyLanguage {
  german('de', 'German', 'de-DE'),
  english('en', 'English', 'en-US'),
  french('fr', 'French', 'fr-FR');

  const SpacyLanguage(this.code, this.displayName, this.defaultLocale);

  /// ISO 639-1 code (`de`, `en`, `fr`).
  final String code;
  final String displayName;

  /// Locale used when the user analyzes text explicitly as this language.
  final String defaultLocale;

  /// The analysis language for a request locale, or null when unsupported.
  static SpacyLanguage? forLocale(String locale) {
    if (locale == 'de-DE') return german;
    if (!RegExp(r'^[A-Za-z]{2,3}([-_][A-Za-z0-9]{1,8})*$').hasMatch(locale)) {
      return null;
    }
    final primary = locale.split(RegExp('[-_]')).first.toLowerCase();
    return switch (primary) {
      'en' => english,
      'fr' => french,
      _ => null,
    };
  }

  SpacyBundle get bundle => switch (this) {
    german => const SpacyBundle.germanF32(),
    english => const SpacyBundle.englishF32(),
    french => const SpacyBundle.frenchF32(),
  };
}

/// Immutable admission contract for one converted spaCy 3.8.0 pipeline, F32
/// CPU. German de_core_news_sm is the frozen version-1 profile; English
/// en_core_web_sm and French fr_core_news_sm are version-2 bundles (GGUF
/// architecture `spacy_pipeline_v2`, NER inside the model) that only a native
/// library built from CrispEmbed source with the v2 runtime can open.
/// Native ABI/profile validation is additional to authenticating these files.
/// No model weights or native binary are included in this Dart package.
final class SpacyBundle {
  const SpacyBundle.germanF32()
    : language = SpacyLanguage.german,
      modelName = 'de_core_news_sm',
      formatVersion = 1,
      sourceWheelSha256 = spacySourceWheelSha256,
      modelFile = model,
      resourcesFile = resources,
      licenseFile = license,
      noticesFile = sourceNotices,
      manifestFile = const SpacyArtifact(
        'manifest.json',
        spacyBundleManifestSha256,
        23762,
      );

  /// en_core_web_sm 3.8.0 (MIT), converted on hosted Linux by CrispEmbed's
  /// pinned v2 converter; byte-equal to the qualification receipts.
  const SpacyBundle.englishF32()
    : language = SpacyLanguage.english,
      modelName = 'en_core_web_sm',
      formatVersion = 2,
      sourceWheelSha256 =
          '1932429db727d4bff3deed6b34cfc05df17794f4a52eeb26cf8928f7c1a0fb85',
      modelFile = const SpacyArtifact(
        'model.gguf',
        '17b18871a2c1e766be4572c1dd9a9902ba01c4a46679797ccb3c4d0048d24e7d',
        12752960,
      ),
      resourcesFile = const SpacyArtifact(
        'resources.json',
        'd585e59b9b2f1aedfd5eb37716ff0d362969f6f8ba8535dad4ae50991567981a',
        3451396,
      ),
      licenseFile = const SpacyArtifact(
        'LICENSE',
        '3933c176979b68bc6d0bcc902c7d6c130f1d127f476f17ba5cdba8d99cfd0012',
        1056,
      ),
      noticesFile = const SpacyArtifact(
        'LICENSES_SOURCES',
        '20d9dfacd215112251f15341edd1a47b1f98bf393a212f10f194ffdc7ee98a90',
        2347,
      ),
      manifestFile = const SpacyArtifact(
        'manifest.json',
        '5cba3b979c67e6a6ecd2f5414bc953728cc4601c2cbe69bf89e9b62465d8dc6c',
        21889,
      );

  /// fr_core_news_sm 3.8.0 (LGPL-LR, see its LICENSE).
  const SpacyBundle.frenchF32()
    : language = SpacyLanguage.french,
      modelName = 'fr_core_news_sm',
      formatVersion = 2,
      sourceWheelSha256 =
          '7d6ad14cd5078e53147bfbf70fb9d433c6a3865b695fda2657140bbc59a27e29',
      modelFile = const SpacyArtifact(
        'model.gguf',
        '8b8f9ab4aa322191faa1735d1b7d53e0e744e18f4025290fe37242faa9a8e53e',
        12780352,
      ),
      resourcesFile = const SpacyArtifact(
        'resources.json',
        'bbdd7b6a51478abcc8e6d6e9cfad0d70e3a3f44a76de6ed4be4fdbb699825f8d',
        35391368,
      ),
      licenseFile = const SpacyArtifact(
        'LICENSE',
        'fcfeb5f3a67aa25d659d1162b4f4a9c52a92171d4df68a11d87c52e3af982a17',
        4424,
      ),
      noticesFile = const SpacyArtifact(
        'LICENSES_SOURCES',
        '21ea31093799e954757d62505687652dfd059d8685f97266d1a442f8a39fcdde',
        28874,
      ),
      manifestFile = const SpacyArtifact(
        'manifest.json',
        '986d620edc745624198c56d3494fa30f3b649786c1d93a29db76fe55196f2264',
        21928,
      );

  final SpacyLanguage language;
  final String modelName;

  /// 1: frozen German profile; 2: `spacy_pipeline_v2` (needs a v2 runtime).
  final int formatVersion;
  final String sourceWheelSha256;
  final SpacyArtifact modelFile;
  final SpacyArtifact resourcesFile;
  final SpacyArtifact licenseFile;
  final SpacyArtifact noticesFile;
  final SpacyArtifact manifestFile;

  String get modelVersion => '3.8.0';
  String get manifestSha256 => manifestFile.sha256;

  /// All five pinned bundle files, including licenses/notices and manifest.
  List<SpacyArtifact> get pinnedFiles => [
    modelFile,
    resourcesFile,
    licenseFile,
    noticesFile,
    manifestFile,
  ];

  /// Context capability masks a native library may report for this bundle:
  /// v1 prepared+text services (15, or 31 with attached NER); v2 text
  /// services only (12, or 28 with the built-in NER).
  Set<int> get capabilityMasks => formatVersion == 1 ? {15, 31} : {12, 28};

  /// True when this bundle may analyze a request with [locale].
  bool acceptsLocale(String locale) =>
      SpacyLanguage.forLocale(locale) == language;

  static const all = [
    SpacyBundle.germanF32(),
    SpacyBundle.englishF32(),
    SpacyBundle.frenchF32(),
  ];

  /// The pinned bundle whose model has [sha256], or null.
  static SpacyBundle? forModelSha256(String sha256) {
    for (final bundle in all) {
      if (bundle.modelFile.sha256 == sha256) return bundle;
    }
    return null;
  }

  // Frozen German pins, kept as statics for existing callers.
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
