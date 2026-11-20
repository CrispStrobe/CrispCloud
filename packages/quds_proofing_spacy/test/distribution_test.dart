import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_grammar.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_install.dart';
import 'package:test/test.dart';

const _identity = SpacyBackendIdentity(
  librarySha256: spacyLinuxX64LibrarySha256,
);

/// A synthetic package whose pins only the test server can satisfy. Its
/// archive is never accepted because nothing it serves matches these pins.
SpacyPlatformPackage _fakePackage({int bytes = 64, String? sha}) =>
    SpacyPlatformPackage(
      platform: SpacyPlatform.linuxX64,
      revision: 'a' * 40,
      archivePath: 'package.tar.gz',
      archiveSha256: sha ?? 'b' * 64,
      archiveBytes: bytes,
      manifestSha256: 'c' * 64,
      manifestBytes: 10,
      libraryEntrypoint: 'native/${'d' * 64}/libcrispembed-spacy.so',
      librarySha256: 'd' * 64,
      libraryBytes: 10,
      profile: 'test',
      qualification: SpacyBuildQualification(
        librarySha256: 'd' * 64,
        analysis: 'none',
      ),
    );

final class _Server {
  _Server(this.server);
  final HttpServer server;
  static Future<_Server> start(
    Future<void> Function(HttpRequest request) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => unawaited(handler(request)));
    return _Server(server);
  }

  /// Rewrites the installer's Hub URL to this loopback server.
  Uri mirror(Uri hub) => Uri.http('127.0.0.1:${server.port}', hub.path);

  Future<void> close() => server.close(force: true);
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('spacy-install-'));
  tearDown(() => root.deleteSync(recursive: true));

  test('catalog pins the published Linux capsule at an immutable revision', () {
    final package = spacyPlatformStatus(SpacyPlatform.linuxX64).package!;
    expect(package.revision, matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(
      package.url.toString(),
      'https://huggingface.co/cstr/crispembed-spacy-de-core-news-sm-3.8.0/'
      'resolve/659dae33997d00296ae12b76510fa4dfe26540e0/'
      'spacy-de_core_news_sm-3.8.0-linux-x86_64-avx2-f32.tar.gz',
    );
    expect(
      package.libraryEntrypoint.split('/')[1],
      package.librarySha256,
      reason: 'the native loader requires a SHA-named library directory',
    );
    expect(package.qualification.grammarQualified, isTrue);
    expect(SpacyBundleDownload.files, hasLength(5));
    expect(
      spacyBundleDownload.totalBytes,
      7383104 + 1404948 + 1056 + 13470 + 23762,
    );
  });

  test('the macOS package is published without a grammar claim', () {
    final mac = spacyPlatformStatus(SpacyPlatform.macosArm64).package!;
    expect(mac.libraryEntrypoint.split('/')[1], mac.librarySha256);
    expect(mac.qualification.grammarQualified, isFalse);
    expect(mac.url.toString(), contains('/resolve/${mac.revision}/packages/'));
    expect(spacyNerDownload!.url.toString(), endsWith('/ner/ner.gguf'));
  });

  test('claims are bound to exact library digests', () {
    expect(
      spacyQualificationFor(spacyLinuxX64LibrarySha256)!.grammarQualified,
      isTrue,
    );
    final mac = spacyQualificationFor(
      '5cb67f0092f3659653773b8687fe7448dc3c235144b01c80a6fae54c103ca4e5',
    )!;
    expect(mac.grammarQualified, isFalse);
    expect(spacyQualificationFor('e' * 64), isNull);
    // The app-bundled macOS library is a recorded build, not a download.
    final bundled = spacyQualificationFor(spacyGrammarMacosBundledSha256)!;
    expect(bundled.grammarQualified, isTrue);
    expect(bundled.librarySha256, spacyGrammarMacosBundledSha256);
    expect(bundled.codeSha256, spacyGrammarMacosBundledCodeSha256);
    // A re-signed copy of the same code inherits the record only through the
    // host-bundled lookup; downloads and unknown code stay unqualified.
    expect(spacyQualificationFor('b' * 64), isNull);
    expect(
      spacyQualificationForHostBundled(
        librarySha256: 'b' * 64,
        codeSha256: spacyGrammarMacosBundledCodeSha256,
      ),
      same(bundled),
    );
    expect(
      spacyQualificationForHostBundled(
        librarySha256: 'b' * 64,
        codeSha256: 'c' * 64,
      ),
      isNull,
    );
    expect(spacyQualificationForHostBundled(librarySha256: 'b' * 64), isNull);
    expect(
      spacyQualificationForHostBundled(
        librarySha256: spacyGrammarMacosBundledSha256,
      ),
      same(bundled),
    );
    // Only host-bundled recorded builds carry a code identity.
    for (final package in [...spacyCatalogPackages, ...spacyRuntimePackages]) {
      expect(package.qualification.codeSha256, isNull);
    }
    expect(
      spacyCatalogPackages
          .followedBy(spacyRuntimePackages)
          .map((package) => package.librarySha256),
      isNot(contains(spacyGrammarMacosBundledSha256)),
    );
  });

  test('catalog grammar claims match the planner\'s enforced build pin', () {
    final claimed = {
      for (final package in spacyCatalogPackages)
        if (package.qualification.grammarQualified) package.librarySha256,
      for (final build in spacyRecordedBuilds)
        if (build.grammarQualified) build.librarySha256,
    };
    expect(claimed, spacyGrammarNativeSha256s);
  });

  test('unpublished platforms are unavailable with a stated reason', () {
    for (final platform in SpacyPlatform.values) {
      final status = spacyPlatformStatus(platform);
      expect(
        status.available,
        platform == SpacyPlatform.linuxX64 ||
            platform == SpacyPlatform.macosArm64,
      );
      if (!status.available) expect(status.reason, isNotEmpty);
    }
  });

  test('only immutable revisions and safe paths resolve', () {
    for (final revision in ['main', 'a' * 39, 'A' * 40]) {
      expect(() => spacyResolveUrl(revision, 'x'), throwsArgumentError);
    }
    for (final path in ['', '/x', 'a/../b', 'a//b', './a']) {
      expect(() => spacyResolveUrl('a' * 40, path), throwsArgumentError);
    }
  });

  test('missing installation is null and a damaged one is reported', () async {
    final installer = SpacyPackageInstaller(root: root);
    expect(await installer.installed(spacyLinuxX64Package), isNull);
    expect(await installer.installedBundle(), isNull);
    final damaged = Directory(
      '${root.path}/packages/${spacyLinuxX64Package.archiveSha256}',
    )..createSync(recursive: true);
    File('${damaged.path}/distribution.json').writeAsStringSync('{}');
    await expectLater(
      installer.installed(spacyLinuxX64Package),
      throwsA(isA<SpacyInstallException>()),
    );
  });

  group('download failures leave no installation', () {
    Future<void> expectRejected(
      Future<void> Function(HttpRequest request) handler,
      SpacyPlatformPackage package, {
      SpacyInstallCancellation? cancellation,
      String? message,
    }) async {
      final server = await _Server.start(handler);
      try {
        final installer = SpacyPackageInstaller(
          root: root,
          mirror: server.mirror,
        );
        await expectLater(
          installer.install(package, cancellation: cancellation),
          throwsA(
            isA<SpacyInstallException>().having(
              (error) => error.message,
              'message',
              contains(message ?? ''),
            ),
          ),
        );
        expect(Directory('${root.path}/packages').existsSync(), isFalse);
        expect(
          root.listSync().where((entity) => entity.path.contains('.staging-')),
          isEmpty,
        );
      } finally {
        await server.close();
      }
    }

    test('HTTP error', () async {
      await expectRejected(
        (request) async {
          request.response.statusCode = 404;
          await request.response.close();
        },
        _fakePackage(),
        message: 'HTTP 404',
      );
    });

    test('same length but wrong bytes fail SHA-256', () async {
      await expectRejected(
        (request) async {
          request.response.contentLength = 64;
          request.response.add(List.filled(64, 1));
          await request.response.close();
        },
        _fakePackage(),
        message: 'SHA-256',
      );
    });

    test('declared length mismatch', () async {
      await expectRejected(
        (request) async {
          request.response.contentLength = 65;
          request.response.add(List.filled(65, 1));
          await request.response.close();
        },
        _fakePackage(),
        message: 'unexpected download size',
      );
    });

    test('undeclared oversized body is cut off', () async {
      await expectRejected(
        (request) async {
          request.response.headers.chunkedTransferEncoding = true;
          for (var i = 0; i < 4; i++) {
            request.response.add(List.filled(32, 1));
            await request.response.flush();
          }
          await request.response.close();
        },
        _fakePackage(),
        message: 'exceeds its pinned size',
      );
    });

    test('caller cancellation aborts the transfer', () async {
      final cancellation = SpacyInstallCancellation();
      await expectRejected(
        (request) async {
          request.response.headers.chunkedTransferEncoding = true;
          request.response.add(List.filled(8, 1));
          await request.response.flush();
          cancellation.cancel();
          await Future<void>.delayed(const Duration(milliseconds: 200));
          request.response.add(List.filled(8, 1));
          await request.response.close().catchError((Object _) {});
        },
        _fakePackage(),
        cancellation: cancellation,
        message: 'cancelled',
      );
    });

    test(
      'authentic bytes that are not a closed capsule are rejected',
      () async {
        final body = utf8.encode(
          'not a gzip archive at all, but pinned bytes.',
        );
        final package = _fakePackage(bytes: body.length, sha: sha256Hex(body));
        await expectRejected(
          (request) async {
            request.response.contentLength = body.length;
            request.response.add(body);
            await request.response.close();
          },
          package,
          message: 'archive',
        );
      },
    );
  });

  test('optional entities are validated against whole tokens', () {
    const text = 'Anna lebt';
    final request = LinguisticAnalysisRequest(
      text: text,
      documentId: 'doc',
      blockId: 'b',
      revision: 1,
    );
    LinguisticToken token(String value, int index, int start, int head) =>
        LinguisticToken(
          index: index,
          text: value,
          byteStart: start,
          byteEnd: start + value.length,
          scalarStart: start,
          scalarEnd: start + value.length,
          start: start,
          end: start + value.length,
          lemma: value,
          tag: 'NE',
          pos: 'PROPN',
          morphology: '',
          dependency: index == head ? 'ROOT' : 'sb',
          head: head,
          sentenceStart: index == 0,
          sentenceEnd: index == 1,
          spaceAfter: index == 0,
        );
    final tokens = [token('Anna', 0, 0, 1), token('lebt', 1, 5, 1)];
    final plain = LinguisticAnalysisResult.success(
      request: request,
      identity: _identity,
      tokens: tokens,
    );
    expect(plain.entitiesAvailable, isFalse);
    expect(plain.toJson().containsKey('entities'), isFalse);
    final withEntities = LinguisticAnalysisResult.success(
      request: request,
      identity: _identity,
      tokens: tokens,
      entities: const [
        LinguisticEntity(
          startToken: 0,
          endToken: 1,
          start: 0,
          end: 4,
          label: 'PER',
          text: 'Anna',
        ),
      ],
    );
    expect(withEntities.entitiesAvailable, isTrue);
    expect(
      (withEntities.toJson()['entities']! as List<Object?>).single,
      containsPair('label', 'PER'),
    );
    for (final bad in const [
      LinguisticEntity(
        startToken: 0,
        endToken: 1,
        start: 0,
        end: 3,
        label: 'PER',
        text: 'Ann',
      ),
      LinguisticEntity(
        startToken: 1,
        endToken: 1,
        start: 5,
        end: 5,
        label: 'PER',
        text: '',
      ),
      LinguisticEntity(
        startToken: 0,
        endToken: 1,
        start: 0,
        end: 4,
        label: '',
        text: 'Anna',
      ),
    ]) {
      expect(
        () => LinguisticAnalysisResult.success(
          request: request,
          identity: _identity,
          tokens: tokens,
          entities: [bad],
        ),
        throwsFormatException,
      );
    }
  });
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();
