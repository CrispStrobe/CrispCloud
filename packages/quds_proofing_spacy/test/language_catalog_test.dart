import 'dart:async';
import 'dart:io';

import 'package:quds_proofing_spacy/quds_proofing_spacy_grammar.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_install.dart';
import 'package:test/test.dart';

final class _Server {
  _Server(this.server, this.paths);
  final HttpServer server;
  final List<String> paths;
  static Future<_Server> start(List<int> Function(String path) body) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    server.listen((request) async {
      paths.add(request.uri.path);
      final bytes = body(request.uri.path);
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    });
    return _Server(server, paths);
  }

  Uri mirror(Uri hub) => Uri.http('127.0.0.1:${server.port}', hub.path);
  Future<void> close() => server.close(force: true);
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('spacy-language-'));
  tearDown(() => root.deleteSync(recursive: true));

  test('request locales map to exactly one analysis language', () {
    expect(SpacyLanguage.forLocale('de-DE'), SpacyLanguage.german);
    for (final locale in ['de-CH', 'de-AT', 'de', 'es-ES', 'it', '', 'x']) {
      expect(SpacyLanguage.forLocale(locale), isNull, reason: locale);
    }
    for (final locale in ['en', 'en-US', 'en-GB', 'en_AU']) {
      expect(SpacyLanguage.forLocale(locale), SpacyLanguage.english);
    }
    for (final locale in ['fr', 'fr-FR', 'fr-CA', 'fr-BE']) {
      expect(SpacyLanguage.forLocale(locale), SpacyLanguage.french);
    }
    expect(const SpacyBundle.germanF32().acceptsLocale('de-DE'), isTrue);
    expect(const SpacyBundle.germanF32().acceptsLocale('en-US'), isFalse);
    expect(const SpacyBundle.englishF32().acceptsLocale('en-GB'), isTrue);
    expect(const SpacyBundle.frenchF32().acceptsLocale('de-DE'), isFalse);
  });

  test('bundles are distinct closed profiles with v2 capability masks', () {
    final models = SpacyBundle.all.map((b) => b.modelFile.sha256).toSet();
    expect(models, hasLength(3));
    for (final bundle in SpacyBundle.all) {
      expect(bundle.pinnedFiles.map((file) => file.file), [
        'model.gguf',
        'resources.json',
        'LICENSE',
        'LICENSES_SOURCES',
        'manifest.json',
      ]);
      expect(SpacyBundle.forModelSha256(bundle.modelFile.sha256), bundle);
      expect(bundle.language.bundle, bundle);
    }
    const german = SpacyBundle.germanF32();
    expect(german.formatVersion, 1);
    expect(german.modelFile, SpacyBundle.model);
    expect(german.manifestSha256, spacyBundleManifestSha256);
    expect(german.capabilityMasks, {15, 31});
    expect(const SpacyBundle.englishF32().capabilityMasks, {12, 28});
    expect(const SpacyBundle.frenchF32().resourcesFile.bytes, 35391368);
  });

  test('identities validate only against their own bundle', () {
    final english = SpacyBackendIdentity.forBundle(
      const SpacyBundle.englishF32(),
      librarySha256: spacyLinuxX64RuntimeLibrarySha256,
      capabilityMask: 28,
    );
    english.validate();
    english.validate(const SpacyBundle.englishF32());
    expect(english.bundle, const SpacyBundle.englishF32());
    expect(
      () => english.validate(const SpacyBundle.germanF32()),
      throwsFormatException,
    );
    expect(
      () => SpacyBackendIdentity.forBundle(
        const SpacyBundle.frenchF32(),
        librarySha256: spacyLinuxX64RuntimeLibrarySha256,
        capabilityMask: 15,
      ).validate(),
      throwsFormatException,
      reason: 'v2 contexts expose no prepared numeric services',
    );
    const SpacyBackendIdentity(
      librarySha256: spacyLinuxX64LibrarySha256,
    ).validate();
    final request = LinguisticAnalysisRequest(
      text: 'Hi',
      documentId: 'd',
      blockId: 'b',
      revision: 1,
      locale: 'de-DE',
      startOffset: 0,
      generation: 0,
      configurationId: 'c',
    );
    expect(
      () => LinguisticAnalysisResult.success(
        request: request,
        identity: english,
        tokens: const [],
      ),
      throwsFormatException,
      reason: 'a German request cannot carry an English identity',
    );
  });

  test('the grammar planner pin never matches a v2 runtime or bundle', () {
    for (final package in spacyRuntimePackages) {
      expect(package.qualification.grammarQualified, isFalse);
      expect(package.librarySha256, isNot(spacyGrammarNativeSha256));
      expect(package.opensVersion2Bundles, isTrue);
      expect(package.libraryEntrypoint.split('/')[1], package.librarySha256);
      expect(spacyQualificationFor(package.librarySha256), isNotNull);
      expect(
        package.url.toString(),
        startsWith(
          'https://huggingface.co/$spacyHuggingFaceRepository/resolve/'
          '${package.revision}/packages/${package.platform.id}/',
        ),
      );
    }
    for (final package in spacyCatalogPackages) {
      expect(package.opensVersion2Bundles, isFalse);
    }
    expect(spacyRuntimePackage(SpacyPlatform.web), isNull);
    expect(spacyRuntimePackage(SpacyPlatform.linuxX64), isNotNull);
  });

  test('language downloads resolve only at their immutable revisions', () {
    expect(spacyLanguageDownload(SpacyLanguage.german), isNull);
    for (final language in [SpacyLanguage.english, SpacyLanguage.french]) {
      final download = spacyLanguageDownload(language)!;
      expect(download.language, language);
      expect(download.revision, matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(download.repository, isNot(spacyHuggingFaceRepository));
      for (final file in download.files) {
        expect(
          download.url(file).toString(),
          'https://huggingface.co/${download.repository}/resolve/'
          '${download.revision}/bundle/${file.file}',
        );
      }
      expect(
        download.totalBytes,
        download.files.fold<int>(0, (sum, f) => sum + f.bytes),
      );
    }
    expect(spacyFrenchDownload.license, contains('LGPL-LR'));
    expect(spacyEnglishDownload.entityLabels, contains('PERSON'));
    expect(spacyFrenchDownload.entityLabels, ['LOC', 'MISC', 'ORG', 'PER']);
  });

  test('a language bundle needs a v2-capable runtime package', () async {
    final installer = SpacyPackageInstaller(root: root);
    final legacy = spacyPlatformStatus(SpacyPlatform.linuxX64).package!;
    await expectLater(
      installer.installLanguage(spacyEnglishDownload, legacy),
      throwsA(isA<SpacyInstallException>()),
    );
    expect(root.listSync(), isEmpty, reason: 'nothing was downloaded');
  });

  test('absent and damaged language trees are distinguished', () async {
    final installer = SpacyPackageInstaller(root: root);
    final runtime = spacyRuntimePackage(SpacyPlatform.linuxX64)!;
    expect(
      await installer.installedLanguage(spacyFrenchDownload, runtime),
      isNull,
    );
    expect(await installer.hasLanguageBundle(spacyFrenchDownload), isFalse);
    final damaged = Directory(
      '${root.path}/bundles/${spacyFrenchDownload.bundle.manifestSha256}',
    )..createSync(recursive: true);
    File('${damaged.path}/model.gguf').writeAsStringSync('x');
    await expectLater(
      installer.installedLanguage(spacyFrenchDownload, runtime),
      throwsA(isA<SpacyInstallException>()),
    );
    await installer.removeLanguage(spacyFrenchDownload);
    expect(damaged.existsSync(), isFalse);
  });

  test(
    'wrong bundle bytes of the pinned length leave no installation',
    () async {
      // Pretend the runtime is installed so only the bundle is fetched.
      final runtime = spacyRuntimePackage(SpacyPlatform.linuxX64)!;
      final sizes = {
        for (final file in spacyEnglishDownload.files)
          '/${spacyEnglishDownload.repository}/resolve/'
                  '${spacyEnglishDownload.revision}/bundle/${file.file}':
              file.bytes,
        runtime.url.path: runtime.archiveBytes,
      };
      final server = await _Server.start(
        (path) => List.filled(sizes[path] ?? 1, 0),
      );
      try {
        final installer = SpacyPackageInstaller(
          root: root,
          mirror: server.mirror,
        );
        await expectLater(
          installer.installLanguage(spacyEnglishDownload, runtime),
          throwsA(isA<SpacyInstallException>()),
        );
        expect(server.paths.first, runtime.url.path);
        expect(
          root.listSync().where(
            (entry) => !entry.path.split('/').last.startsWith('.'),
          ),
          isEmpty,
        );
        expect(
          await installer.hasLanguageBundle(spacyEnglishDownload),
          isFalse,
        );
      } finally {
        await server.close();
      }
    },
  );
}
