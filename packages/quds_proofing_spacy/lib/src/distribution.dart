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
    this.opensVersion2Bundles = false,
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

  /// True for libraries built from CrispEmbed source with the v2 runtime
  /// (PR #244 and later): they also open the separately published English
  /// and French bundles. Earlier libraries reject them.
  final bool opensVersion2Bundles;

  Uri get url => spacyResolveUrl(revision, archivePath);
}

/// One separately published language bundle (five pinned files, no
/// executable code) in its own Hub repository. It is opened by a v2-capable
/// library from a [SpacyPlatformPackage] with [opensVersion2Bundles].
final class SpacyLanguageDownload {
  const SpacyLanguageDownload({
    required this.bundle,
    required this.repository,
    required this.revision,
    required this.license,
    required this.entityLabels,
    required this.qualification,
  });

  final SpacyBundle bundle;
  final String repository;

  /// Full 40-hex Hub commit holding `bundle/*`; never a branch name.
  final String revision;

  /// User-facing license summary; the full texts are installed as files.
  final String license;
  final List<String> entityLabels;

  /// Analysis evidence for the bundle (exact libraries are listed per
  /// package qualification). Never a grammar claim.
  final String qualification;

  SpacyLanguage get language => bundle.language;
  List<SpacyArtifact> get files => bundle.pinnedFiles;
  Uri url(SpacyArtifact artifact) => spacyResolveUrl(
    revision,
    'bundle/${artifact.file}',
    repository: repository,
  );
  int get totalBytes => files.fold(0, (sum, file) => sum + file.bytes);
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

/// Canonical CPython 3.12.14 conversion published by CrispEmbed run
/// 44302008411 (main 28d8ce0e) at an immutable revision and read back from an
/// empty cache. Runtime-owner receipts: 1,776/1,776 sentences and 1,758/1,758
/// entities identical to original spaCy. Display only; never used for grammar.
const _publishedNer = SpacyNerDownload(
  revision: '8b5d7084bab236fff9921ef5e397069163e83738',
  path: 'ner/ner.gguf',
  sha256: '1b65fce5864703d971880cf038a67f2ffd1ef99cad2cd49f9dc122d7882cdaa1',
  bytes: 6135456,
);

/// The published NER model, or null for catalogs without one. Hosts must
/// tolerate null (offer no NER) rather than assume a model exists.
SpacyNerDownload? get spacyNerDownload => _publishedNer;

/// Availability of a platform in this catalog, with a user-facing reason.
final class SpacyPlatformStatus {
  const SpacyPlatformStatus._(this.platform, this.package, this.reason);

  final SpacyPlatform platform;
  final SpacyPlatformPackage? package;

  /// Why no package is offered (null when one is offered).
  final String? reason;
  bool get available => package != null;
}

Uri spacyResolveUrl(
  String revision,
  String path, {
  String repository = spacyHuggingFaceRepository,
}) {
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(revision) ||
      path.isEmpty ||
      path.startsWith('/') ||
      path
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw ArgumentError('Only immutable revision paths can be resolved.');
  }
  return Uri.https('huggingface.co', '/$repository/resolve/$revision/$path');
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

/// macOS arm64 library built from CrispEmbed main 28d8ce0e (ggml + SGEMM
/// default engine, runtime PR #240).
const spacyMacosArm64LibrarySha256 =
    '918a069e3ce3e6786fd11f91d9f7b6c9a99b1c18a96493ef86ab586146dc2992';

const spacyMacosArm64Package = SpacyPlatformPackage(
  platform: SpacyPlatform.macosArm64,
  revision: '24e607cbcf4187e7589619e725134c27d4d83817',
  archivePath:
      'packages/macos-arm64/28d8ce0eb24963ecd5eb37f823e7ca75ab6df8ee/'
      'spacy-de_core_news_sm-3.8.0-macos-arm64-f32.tar.gz',
  archiveSha256:
      '492c8bfb9e78d5e3fe9163918e2038900578f977aee830683cae7d7be6525fec',
  archiveBytes: 7879182,
  manifestSha256:
      'aa28595a374f3db683ebd88e49db857bc6bd74de0e811e41d72808e233f01bf4',
  manifestBytes: 10911,
  libraryEntrypoint:
      'native/$spacyMacosArm64LibrarySha256/libcrispembed-spacy.dylib',
  librarySha256: spacyMacosArm64LibrarySha256,
  libraryBytes: 2162776,
  profile: 'de_core_news_sm-3.8.0-f32-macos-arm64',
  systemRequirements: [
    'Apple silicon, macOS 13 or newer (system libc++ only; PCRE2 static)',
    'Unsigned library: a hardened/sandboxed app must allow it or ship it '
        'inside its own signed bundle',
  ],
  qualification: SpacyBuildQualification(
    librarySha256: spacyMacosArm64LibrarySha256,
    analysis:
        'Hosted macOS 15 arm64 run 44302625032 on the library installed from '
        'this exact capsule: ctest, 21 text-API controls, development parity '
        '(16 cases, 113 tokens, 22 sentences, 1,201 numerical stages exact). '
        'Optional NER attaches and decodes on this library (local Quds worker '
        'check). Component evidence; not a signed-app qualification.',
    limitations: [
      'No manual grammar qualification for this build; the grammar planner '
          'refuses it.',
      'Not signed or notarized.',
    ],
  ),
);

/// Catalog entries in the order hosts should present them.
const spacyCatalogPackages = <SpacyPlatformPackage>[
  spacyLinuxX64Package,
  spacyMacosArm64Package,
];

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
    SpacyPlatform.linuxArm64 => _pendingNative,
    SpacyPlatform.windowsX64 || SpacyPlatform.windowsArm64 =>
      'No Windows native build or qualification exists yet.',
    SpacyPlatform.macosX64 => 'Intel macOS is not built or qualified.',
    SpacyPlatform.iosArm64 || SpacyPlatform.androidArm64 =>
      'Mobile apps must ship the native library inside the signed app; only '
          'the model bundle may be downloaded. No mobile build is qualified.',
    SpacyPlatform.web => 'Native analysis is unavailable in the browser.',
    SpacyPlatform.linuxX64 ||
    SpacyPlatform.macosArm64 => 'No package is configured.',
  };
  return SpacyPlatformStatus._(platform, null, reason);
}

/// The ad hoc signed macOS arm64 library shipped inside the Studio app
/// (CrispEmbed v2 runtime 45b05770, static PCRE2). Analysis and manual
/// German grammar are recorded for exactly these bytes below.
const spacyGrammarMacosBundledSha256 =
    'ccc96620e01164d18e8d2e46b9a383677e4430c8889833bedab5b56c16a1b40f';

/// Exact builds with recorded claims that are not offered as downloadable
/// packages (for example development candidates or host-bundled libraries).
/// Lookup is by exact library digest only.
const spacyRecordedBuilds = <SpacyBuildQualification>[
  // The ad hoc signed library inside the Studio macOS app. Its pinned bytes
  // are published at Hub revision 2aa70083 (app-bundled/macos-arm64/<sha>/)
  // and installed by build_macos_app.sh; `tool/build.py --native` reproduces
  // them with the recorded toolchain.
  SpacyBuildQualification(
    librarySha256: spacyGrammarMacosBundledSha256,
    analysis:
        'macOS arm64 library built from CrispEmbed v2 runtime 45b05770 with '
        'static PCRE2, ad hoc signed for the Studio app; checked on Apple '
        'silicon on these exact signed bytes: ctest 4/4, 21 text-API '
        'controls, enable-API controls, development parity (16 cases, 113 '
        'tokens, 22 sentences, 1,201 numerical stages, 244 parser states '
        'exact against the frozen original spaCy references).',
    grammar:
        'Manual de-DE only: cross-binary replay of the consumed sealed W6 '
        'panel (22/30 exact corrections vs 5/30 deterministic; no findings on '
        '42 valid/10 guard controls) and the W7 extension panel (24/40 exact '
        'vs 14/40, 0 valid or guard findings) with annotations, planner '
        'decisions, arms and corrected rechecks identical case by case to the '
        'qualified Linux build; native editor gate 10/10. Not a general German '
        'grammar quality claim.',
    limitations: [
      'Valid only for these exact signed bytes inside an app bundle; a '
          'rebuild with another toolchain is a different, unqualified build.',
      'Grammar uses the parser without named entities (capability mask 15).',
      'Ad hoc signed; not notarized.',
    ],
  ),
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
  for (final package in [...spacyCatalogPackages, ...spacyRuntimePackages]) {
    if (package.librarySha256 == librarySha256) return package.qualification;
  }
  for (final build in spacyRecordedBuilds) {
    if (build.librarySha256 == librarySha256) return build;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Version-2 runtime packages and separately published language bundles.
//
// The native library is language-independent. Capsules built from CrispEmbed
// main 45b05770 (after the v2 runtime, PR #244) hold the same German bundle as
// before plus a library that also opens the English and French bundles.
// They carry no grammar claim; the German manual grammar provider stays bound
// to its qualified builds ([spacyGrammarNativeSha256s]).

const _v2Source = '45b057700880e125d701d941a9e3123679960d35';

/// CrispEmbed run that loaded the published English and French bundles with
/// the published runtime capsules and compared them with original spaCy.
const spacyLanguageConsumerRun = '44377019364';

const _v2Analysis =
    'Hosted development parity on this exact library (CrispEmbed run '
    '44369523105): German 16 cases, 113 tokens, 1,201 numerical stages exact; '
    'spacy_smoke vs original spaCy 60/60 texts, 835 tokens, 29/29 entities. '
    'English and French bundles opened from the published capsule through '
    'the C ABI (run $spacyLanguageConsumerRun): UD English-EWT test 2,077/2,077 '
    'texts, 25,531 tokens, 1,876/1,876 entities; UD French-GSD test 416/416 '
    'texts, 9,786 tokens, 469/469 entities identical to original spaCy '
    '3.8.18. Component evidence; not an app qualification.';

const _v2Limitations = [
  'No manual grammar qualification for this build; the grammar planner '
      'refuses it.',
];

const spacyLinuxX64RuntimeLibrarySha256 =
    '6e21ae15b08922520a2cb6bcba3ed27ae7f6476a6bde1cec33607ab9489045f4';

const spacyLinuxX64RuntimePackage = SpacyPlatformPackage(
  platform: SpacyPlatform.linuxX64,
  revision: 'd143d26a3edd7b51bdfdf12a6cda5b6243ec69d0',
  archivePath:
      'packages/linux-x86_64/$_v2Source/'
      'spacy-de_core_news_sm-3.8.0-linux-x86_64-f32.tar.gz',
  archiveSha256:
      'c8bbbb86fdd362117c2b5c94453f975b33fab6953a78c13db37b255caa816ce5',
  archiveBytes: 8045365,
  manifestSha256:
      '9fe9b4b3fdb96600121261f80b23b2536b24b380702ab1ba8a4e0ab430df84a2',
  manifestBytes: 10886,
  libraryEntrypoint:
      'native/$spacyLinuxX64RuntimeLibrarySha256/libcrispembed-spacy.so',
  librarySha256: spacyLinuxX64RuntimeLibrarySha256,
  libraryBytes: 2716896,
  profile: 'de_core_news_sm-3.8.0-f32-linux-x86_64',
  systemRequirements: [
    'x86-64; glibc 2.34 or newer and libstdc++ (GLIBCXX 3.4.29); PCRE2 static',
  ],
  opensVersion2Bundles: true,
  qualification: SpacyBuildQualification(
    librarySha256: spacyLinuxX64RuntimeLibrarySha256,
    analysis: _v2Analysis,
    limitations: _v2Limitations,
  ),
);

const spacyLinuxArm64RuntimeLibrarySha256 =
    '21d15c1e48418d7db0d7cf5626330ce6d9c31c637a09cd1ae57020a9f9a17c45';

const spacyLinuxArm64RuntimePackage = SpacyPlatformPackage(
  platform: SpacyPlatform.linuxArm64,
  revision: 'fd75184d58944ec5f6c4cb037a48eae6e6f5942f',
  archivePath:
      'packages/linux-arm64/$_v2Source/'
      'spacy-de_core_news_sm-3.8.0-linux-arm64-f32.tar.gz',
  archiveSha256:
      '41c07dbe1ecc21fb2c3409aa5d6d13a1d47cb213bff485e2c4e06bfe0d02b0c6',
  archiveBytes: 7977603,
  manifestSha256:
      '3f7ad88e9e28fe921bbd40547366ced4512cbe9807bb75b839b7bc14dd588dc4',
  manifestBytes: 10941,
  libraryEntrypoint:
      'native/$spacyLinuxArm64RuntimeLibrarySha256/libcrispembed-spacy.so',
  librarySha256: spacyLinuxArm64RuntimeLibrarySha256,
  libraryBytes: 2388288,
  profile: 'de_core_news_sm-3.8.0-f32-linux-arm64',
  systemRequirements: [
    'arm64 (aarch64); glibc 2.34 or newer and libstdc++ (GLIBCXX 3.4.29); '
        'PCRE2 static',
  ],
  opensVersion2Bundles: true,
  qualification: SpacyBuildQualification(
    librarySha256: spacyLinuxArm64RuntimeLibrarySha256,
    analysis: _v2Analysis,
    limitations: _v2Limitations,
  ),
);

const spacyMacosArm64RuntimeLibrarySha256 =
    'f3300152c8b063960ff9c21785241bb8b99ffc8f1b2150e362b46d78b0272647';

const spacyMacosArm64RuntimePackage = SpacyPlatformPackage(
  platform: SpacyPlatform.macosArm64,
  revision: 'cf833ae59e6e92773af90c4cbae67a2ba68dec03',
  archivePath:
      'packages/macos-arm64/$_v2Source/'
      'spacy-de_core_news_sm-3.8.0-macos-arm64-f32.tar.gz',
  archiveSha256:
      '200a09b1f582e67abf813355424c0ae9066d47a076c2bf641daed0ff605c7d8c',
  archiveBytes: 7930303,
  manifestSha256:
      'd3daca5dd08d0c881a307feae80cc3507a3b653ff28a4c8122dfbb62220893d2',
  manifestBytes: 11154,
  libraryEntrypoint:
      'native/$spacyMacosArm64RuntimeLibrarySha256/libcrispembed-spacy.dylib',
  librarySha256: spacyMacosArm64RuntimeLibrarySha256,
  libraryBytes: 2284856,
  profile: 'de_core_news_sm-3.8.0-f32-macos-arm64',
  systemRequirements: [
    'Apple silicon, macOS 13 or newer (system libc++ only; PCRE2 static)',
    'Unsigned library: a hardened/sandboxed app must allow it or ship it '
        'inside its own signed bundle',
  ],
  opensVersion2Bundles: true,
  qualification: SpacyBuildQualification(
    librarySha256: spacyMacosArm64RuntimeLibrarySha256,
    analysis: _v2Analysis,
    limitations: [..._v2Limitations, 'Not signed or notarized.'],
  ),
);

/// Packages whose library opens the English and French bundles, one per
/// platform. Only platforms with a published v2 capsule are listed; the
/// Windows v2 capsule failed its text-API controls (CrispEmbed run
/// 44369523105) and is not published.
const spacyRuntimePackages = <SpacyPlatformPackage>[
  spacyLinuxX64RuntimePackage,
  spacyLinuxArm64RuntimePackage,
  spacyMacosArm64RuntimePackage,
];

/// The v2-capable package for [platform], or null when none is published.
SpacyPlatformPackage? spacyRuntimePackage(SpacyPlatform platform) {
  for (final package in spacyRuntimePackages) {
    if (package.platform == platform) return package;
  }
  return null;
}

/// en_core_web_sm 3.8.0 bundle, published by CrispEmbed run 44372635419
/// (main e91b054d) at an immutable revision and read back from an empty
/// cache (every file's SHA-256 and length).
const spacyEnglishDownload = SpacyLanguageDownload(
  bundle: SpacyBundle.englishF32(),
  repository: 'cstr/crispembed-spacy-en-core-web-sm-3.8.0',
  revision: 'eb659259b489593ddf29c747bc4562fbad5570f4',
  license:
      'MIT (ExplosionAI GmbH). Training-source notices (OntoNotes 5, '
      'ClearNLP conversion, WordNet 3.0 License) are installed verbatim; no '
      'corpus text is included.',
  entityLabels: [
    'CARDINAL', 'DATE', 'EVENT', 'FAC', 'GPE', 'LANGUAGE', 'LAW', 'LOC', //
    'MONEY', 'NORP', 'ORDINAL', 'ORG', 'PERCENT', 'PERSON', 'PRODUCT',
    'QUANTITY', 'TIME', 'WORK_OF_ART',
  ],
  qualification:
      '2,077/2,077 UD English-EWT test texts (25,531 tokens) and 1,876/1,876 '
      'entities identical to original spaCy 3.8.18 (macOS arm64 and hosted '
      'Linux x86-64 run 44363961502; published-bundle consumers in run '
      '$spacyLanguageConsumerRun). Analysis only; no grammar claim.',
);

/// fr_core_news_sm 3.8.0 bundle, published by the same run.
const spacyFrenchDownload = SpacyLanguageDownload(
  bundle: SpacyBundle.frenchF32(),
  repository: 'cstr/crispembed-spacy-fr-core-news-sm-3.8.0',
  revision: '5e90593195cc4ecd20ceb864d932d7d7f5e3d762',
  license:
      'LGPL-LR (Lesser General Public License for Linguistic Resources), as '
      'the official fr_core_news_sm package; this is a format conversion of '
      'that resource. Training-source notices (UD French Sequoia LGPL-LR, '
      'WikiNER CC BY 4.0, spaCy lookups MIT) are installed verbatim; no corpus '
      'text is included.',
  entityLabels: ['LOC', 'MISC', 'ORG', 'PER'],
  qualification:
      '416/416 UD French-GSD test texts (9,786 tokens) and 469/469 entities '
      'identical to original spaCy 3.8.18 (macOS arm64 and hosted Linux '
      'x86-64 run 44363955799; published-bundle consumers in run '
      '$spacyLanguageConsumerRun). Analysis only; no grammar claim.',
);

/// The published bundle for an additional language; null for German (which
/// ships inside every package) or an unpublished language.
SpacyLanguageDownload? spacyLanguageDownload(SpacyLanguage language) =>
    switch (language) {
      SpacyLanguage.english => spacyEnglishDownload,
      SpacyLanguage.french => spacyFrenchDownload,
      SpacyLanguage.german => null,
    };
