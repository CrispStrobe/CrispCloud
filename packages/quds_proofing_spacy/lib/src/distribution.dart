import 'bundle.dart';

/// Immutable Hugging Face distribution catalog for the German spaCy profile.
///
/// Every value below is compiled into the app. Nothing downloaded beside an
/// artifact can widen or replace these pins: a package is admitted only when
/// its archive bytes match the pinned SHA-256/length before any parsing, its
/// internal manifest matches the pinned digest, and every installed payload
/// (including the native library and all notices) matches that manifest.
///
/// Qualification claims are bound to one exact native library digest. A newly
/// built binary never inherits the claims of an earlier build; it needs its
/// own catalog entry and evidence.
const spacyHuggingFaceRepository =
    'cstr/crispembed-spacy-de-core-news-sm-3.8.0';

/// Desktop/mobile targets known to the catalog, including honest
/// "not available" entries so hosts can explain why setup is not offered.
enum SpacyPlatform {
  linuxX64('linux-x86_64'),
  linuxArm64('linux-arm64'),
  macosArm64('macos-arm64'),
  macosX64('macos-x86_64'),
  windowsX64('windows-x86_64'),
  windowsArm64('windows-arm64'),
  iosArm64('ios-arm64'),
  androidArm64('android-arm64'),
  web('web');

  const SpacyPlatform(this.id);
  final String id;
}

/// What a given exact native build has been shown to do. These are separate
/// claims; analysis evidence never implies grammar evidence.
final class SpacyBuildQualification {
  const SpacyBuildQualification({
    required this.librarySha256,
    required this.analysis,
    this.grammar,
    this.limitations = const [],
  });

  /// The exact native library these claims refer to.
  final String librarySha256;

  /// Evidence for token/tag/morphology/lemma/dependency/sentence parity.
  final String analysis;

  /// Evidence for the manual de-DE grammar provider, or null when this exact
  /// build has no grammar qualification.
  final String? grammar;
  final List<String> limitations;

  bool get grammarQualified => grammar != null;
}

/// One closed platform capsule: five bundle files, one native library, its
/// header, every notice and the capsule's own `distribution.json`.
final class SpacyPlatformPackage {
  const SpacyPlatformPackage({
    required this.platform,
    required this.revision,
    required this.archivePath,
    required this.archiveSha256,
    required this.archiveBytes,
    required this.manifestSha256,
    required this.manifestBytes,
    required this.libraryEntrypoint,
    required this.librarySha256,
    required this.libraryBytes,
    required this.qualification,
    required this.profile,
    this.systemRequirements = const [],
  });

  final SpacyPlatform platform;

  /// Full 40-hex Hub commit; never a branch name.
  final String revision;
  final String archivePath;
  final String archiveSha256;
  final int archiveBytes;

  /// Digest/length of the capsule's internal `distribution.json`.
  final String manifestSha256;
  final int manifestBytes;

  /// Capsule-relative path. Its parent directory is the library SHA-256.
  final String libraryEntrypoint;
  final String librarySha256;
  final int libraryBytes;
  final SpacyBuildQualification qualification;
  final String profile;
  final List<String> systemRequirements;

  Uri get url => spacyResolveUrl(revision, archivePath);
}

/// The five model files, downloadable without a native library. Hosts which
/// ship a signed native library inside the app (App Store, iOS, Android)
/// download only this bundle; downloading executable code is not offered.
final class SpacyBundleDownload {
  const SpacyBundleDownload({required this.revision});

  final String revision;

  static const manifest = SpacyArtifact(
    'manifest.json',
    spacyBundleManifestSha256,
    23762,
  );

  /// All five pinned files, including licenses/notices.
  static const files = [...SpacyBundle.files, manifest];

  Uri url(SpacyArtifact artifact) =>
      spacyResolveUrl(revision, 'bundle/${artifact.file}');

  int get totalBytes => files.fold(0, (sum, file) => sum + file.bytes);
}

/// The optional, separately downloaded named-entity model (`ner.gguf`).
/// Used only with a native build that exports the NER ABI (runtime after
/// CrispEmbed PR #240); never required for analysis or grammar.
final class SpacyNerDownload {
  const SpacyNerDownload({
    required this.revision,
    required this.path,
    required this.sha256,
    required this.bytes,
  });
  final String revision;
  final String path;
  final String sha256;
  final int bytes;
  Uri get url => spacyResolveUrl(revision, path);
}

/// Null until the canonically converted `ner.gguf` is published and
/// read back from its immutable revision.
const SpacyNerDownload? spacyNerDownload = null;

/// Availability of a platform in this catalog, with a user-facing reason.
final class SpacyPlatformStatus {
  const SpacyPlatformStatus._(this.platform, this.package, this.reason);

  final SpacyPlatform platform;
  final SpacyPlatformPackage? package;

  /// Why no package is offered (null when one is offered).
  final String? reason;
  bool get available => package != null;
}

Uri spacyResolveUrl(String revision, String path) {
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(revision) ||
      path.isEmpty ||
      path.startsWith('/') ||
      path
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw ArgumentError('Only immutable revision paths can be resolved.');
  }
  return Uri.https(
    'huggingface.co',
    '/$spacyHuggingFaceRepository/resolve/$revision/$path',
  );
}

/// Immutable revision that holds the bundle files and the Linux capsule.
const spacyLinuxPublicationRevision =
    '659dae33997d00296ae12b76510fa4dfe26540e0';

/// The accepted W4/W5 Linux library (CrispEmbed acceptance candidate).
const spacyLinuxX64LibrarySha256 =
    'ea89842ebf22c08508aff1cfbf18d78a107118af320523009616ff62b6e42977';

const spacyLinuxX64Package = SpacyPlatformPackage(
  platform: SpacyPlatform.linuxX64,
  revision: spacyLinuxPublicationRevision,
  archivePath: 'spacy-de_core_news_sm-3.8.0-linux-x86_64-avx2-f32.tar.gz',
  archiveSha256:
      '4e3b627a614cd21851e6e354335e2e08adeb4cedd4d7778df0cc68c1ce2edf01',
  archiveBytes: 7808129,
  manifestSha256:
      'e043af51e247368931f23fa0d9b931453e174f105b021fe2053e8e3029fd3d8d',
  manifestBytes: 6723,
  libraryEntrypoint:
      'native/$spacyLinuxX64LibrarySha256/libcrispembed-spacy.so',
  librarySha256: spacyLinuxX64LibrarySha256,
  libraryBytes: 1959256,
  profile: 'de_core_news_sm-3.8.0-f32-linux-x86_64-avx2-validation',
  systemRequirements: [
    'x86-64 CPU with AVX2',
    'glibc 2.38 or newer, libstdc++ (GLIBCXX 3.4.29) and shared PCRE2 10.x '
        '(libpcre2-8.so.0); only the six recorded dependency builds are qualified',
  ],
  qualification: SpacyBuildQualification(
    librarySha256: spacyLinuxX64LibrarySha256,
    analysis:
        'CrispEmbed native acceptance 2176c896 (98 tokens, 13 sentences, 201 '
        'parser transitions, 851 numerical stages exact) and the W5 Dart '
        'worker/Studio view on this exact library.',
    grammar:
        'Manual de-DE only: sealed W6 panel (22/30 exact corrections vs 5/30 '
        'deterministic; no findings on 42 valid/10 guard controls) and the W7 '
        'extension panel (CrispEmbed run 44262982569: 24/40 exact, 0 valid or '
        'guard findings) on this exact library. Not a general German grammar '
        'quality claim.',
    limitations: [
      'Six declared external dependency builds only; not general Linux '
          'portability.',
      'Caller cancellation settles the caller; native compute is not '
          'interrupted.',
    ],
  ),
);

/// Catalog entries in the order hosts should present them.
const spacyCatalogPackages = <SpacyPlatformPackage>[spacyLinuxX64Package];

const spacyBundleDownload = SpacyBundleDownload(
  revision: spacyLinuxPublicationRevision,
);

const _pendingNative =
    'A verified native package for this platform has not been published yet. '
    'It will be built from the CrispEmbed runtime after its current update '
    'lands and published with its own qualification record.';

/// Explains availability per platform; unknown platforms are unavailable.
SpacyPlatformStatus spacyPlatformStatus(SpacyPlatform platform) {
  for (final package in spacyCatalogPackages) {
    if (package.platform == platform) {
      return SpacyPlatformStatus._(platform, package, null);
    }
  }
  final reason = switch (platform) {
    SpacyPlatform.macosArm64 => _pendingNative,
    SpacyPlatform.linuxArm64 => _pendingNative,
    SpacyPlatform.windowsX64 || SpacyPlatform.windowsArm64 =>
      'No Windows native build or qualification exists yet.',
    SpacyPlatform.macosX64 => 'Intel macOS is not built or qualified.',
    SpacyPlatform.iosArm64 || SpacyPlatform.androidArm64 =>
      'Mobile apps must ship the native library inside the signed app; only '
          'the model bundle may be downloaded. No mobile build is qualified.',
    SpacyPlatform.web => 'Native analysis is unavailable in the browser.',
    SpacyPlatform.linuxX64 => 'No package is configured.',
  };
  return SpacyPlatformStatus._(platform, null, reason);
}

/// Exact builds with recorded claims that are not offered as downloadable
/// packages (for example development candidates or host-bundled libraries).
/// Lookup is by exact library digest only.
const spacyRecordedBuilds = <SpacyBuildQualification>[
  SpacyBuildQualification(
    librarySha256:
        '5cb67f0092f3659653773b8687fe7448dc3c235144b01c80a6fae54c103ca4e5',
    analysis:
        'Unsigned macOS arm64 development candidate (CrispEmbed 1d4f433a, '
        'hosted run 44262399612): 16 development cases, 113 tokens and 1,201 '
        'numerical stages exact; 21 API controls. Component evidence only.',
    limitations: [
      'Not signed, notarized or qualified inside an app.',
      'No grammar qualification for this build.',
    ],
  ),
];

/// Qualification for an exact library, or null for an unrecorded build.
SpacyBuildQualification? spacyQualificationFor(String librarySha256) {
  for (final package in spacyCatalogPackages) {
    if (package.librarySha256 == librarySha256) return package.qualification;
  }
  for (final build in spacyRecordedBuilds) {
    if (build.librarySha256 == librarySha256) return build;
  }
  return null;
}
