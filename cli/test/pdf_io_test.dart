import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:crisp/adapters/bounded_download.dart';
import 'package:crisp/adapters/cli_storage_client.dart';
import 'package:crisp/adapters/s3_adapter.dart';
import 'package:crisp/adapters/webdav_adapter.dart';
import 'package:crisp/commands/pdf.dart';
import 'package:crisp/config/cli_config.dart';
import 'package:crisp/pdf/pdf_io.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdf_operations/pdf_operations.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late CliConfig config;
  late _MemoryClient client;
  late PdfCliFileStore store;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('crisp_pdf_io_');
    config = CliConfig(path: '${temporary.path}/config.yaml');
    config.saveProvider('test', {
      'type': 's3',
      'endpoint': 'https://example.test',
      'bucket': 'pdfs',
    });
    client = _MemoryClient();
    store = PdfCliFileStore(config, adapterFactory: (_, _) => client);
  });

  tearDown(() async {
    await store.dispose();
    temporary.deleteSync(recursive: true);
  });

  Matcher failure(String code) =>
      isA<PdfCliException>().having((error) => error.code, 'code', code);

  test('local paths stay local and cloud paths explicitly bind a profile', () {
    expect(PdfCliLocation.parse('relative.pdf').isRemote, isFalse);
    final remote = PdfCliLocation.parse('cloud://MyProfile/reports/a%20b.pdf');
    expect(remote.profile, 'MyProfile');
    expect(remote.path, '/reports/a b.pdf');
    expect(remote.name, 'a b.pdf');
    for (final path in [
      'cloud://test/',
      'cloud://user:secret@test/x.pdf',
      'cloud://test:22/x.pdf',
      'cloud://test/x.pdf?token=secret',
      'cloud://test/path%2Falias.pdf',
      'cloud://test/x.pdf#page=2',
    ]) {
      expect(() => PdfCliLocation.parse(path), throwsA(failure('invalidPath')));
    }
  });

  test(
    'fresh remote parent listing is required before a bounded read',
    () async {
      client.files['/docs/input.pdf'] = Uint8List.fromList([1, 2, 3]);
      expect(await store.readBytes('cloud://test/docs/input.pdf'), [1, 2, 3]);
      expect(client.listCalls, 1);
      expect(client.downloadCalls, 1);
      expect(client.statCalls, 0);
      expect(client.unboundedCalls, 0);
    },
  );

  test(
    'a declared oversized remote file is rejected before downloading',
    () async {
      client.files['/large.pdf'] = Uint8List.fromList([1, 2, 3]);
      await expectLater(
        store.readBytes('cloud://test/large.pdf', maxBytes: 2),
        throwsA(isA<CliDownloadLimitException>()),
      );
      expect(client.downloadCalls, 0);
    },
  );

  test('list failures cannot be mistaken for an absent output', () async {
    client.failListing = true;
    await expectLater(
      store.prepareOutput('cloud://test/result.pdf', overwrite: false),
      throwsA(failure('listingFailed')),
    );
    expect(client.uploadCalls, 0);
    expect(client.statCalls, 0);
  });

  test('remote output is checked again and verified after upload', () async {
    final output = await store.prepareOutput(
      'cloud://test/result.pdf',
      overwrite: false,
    );
    final warnings = await store.writeOutput(
      output,
      Uint8List.fromList([4, 5, 6]),
    );
    expect(client.files['/result.pdf'], [4, 5, 6]);
    expect(client.listCalls, greaterThanOrEqualTo(3));
    expect(client.downloadCalls, 1);
    expect(client.uploadCalls, 1);
    expect(warnings.single, contains('atomic'));
  });

  test('an output created after preflight is not overwritten', () async {
    final output = await store.prepareOutput(
      'cloud://test/result.pdf',
      overwrite: false,
    );
    client.files['/result.pdf'] = Uint8List.fromList([9]);
    await expectLater(
      store.writeOutput(output, Uint8List.fromList([1])),
      throwsA(failure('outputChanged')),
    );
    expect(client.files['/result.pdf'], [9]);
    expect(client.uploadCalls, 0);
  });

  test('an existing output changed after consent is not overwritten', () async {
    client.files['/result.pdf'] = Uint8List.fromList([5]);
    final output = await store.prepareOutput(
      'cloud://test/result.pdf',
      overwrite: true,
    );
    client.files['/result.pdf'] = Uint8List.fromList([6]);
    await expectLater(
      store.writeOutput(output, Uint8List.fromList([1])),
      throwsA(failure('outputChanged')),
    );
    expect(client.files['/result.pdf'], [6]);
    expect(client.uploadCalls, 0);
  });

  test(
    'a second profile alias cannot overwrite the same source account/path',
    () async {
      config.saveProvider('alias', {
        'type': 's3',
        'endpoint': 'https://EXAMPLE.test/',
        'bucket': 'pdfs',
      });
      client.files['/input.pdf'] = Uint8List.fromList([1, 2, 3]);
      await store.readBytes('cloud://test/input.pdf');
      await expectLater(
        store.prepareOutput('cloud://alias/input.pdf', overwrite: true),
        throwsA(failure('sourceOutput')),
      );
      expect(client.uploadCalls, 0);
    },
  );

  test('irrelevant profile keys cannot disguise the same S3 output', () async {
    config.saveProvider('alias', {
      'type': 's3',
      'endpoint': 'https://example.test',
      'bucket': 'pdfs',
      'port': 1234,
      'host': 'unused-setting',
    });
    client.files['/input.pdf'] = Uint8List.fromList([1, 2, 3]);
    await store.readBytes('cloud://test/input.pdf');
    await expectLater(
      store.prepareOutput('cloud://alias/input.pdf', overwrite: true),
      throwsA(failure('sourceOutput')),
    );
  });

  test(
    'WebDAV aliases with nested base paths cannot replace a source',
    () async {
      config.saveProvider('dav-root', {
        'type': 'webdav',
        'host': 'https://dav.test/root',
      });
      config.saveProvider('dav-nested', {
        'type': 'webdav',
        'host': 'https://DAV.test:443/root/docs/',
      });
      client.files['/docs/input.pdf'] = Uint8List.fromList([1, 2, 3]);
      await store.readBytes('cloud://dav-root/docs/input.pdf');
      await expectLater(
        store.prepareOutput('cloud://dav-nested/input.pdf', overwrite: true),
        throwsA(failure('sourceOutput')),
      );
    },
  );

  test(
    'malformed CLI configuration fails without printing credential source',
    () async {
      const secret = 'private-config-parser-source';
      File(config.configPath).writeAsStringSync('providers: ["$secret",');
      final errors = StringBuffer();
      final output = StringBuffer();
      final runner = PdfAwareCommandRunner('crisp', 'PDF tests', errors: errors)
        ..addCommand(PdfCommand(config, output: output, errors: errors));
      expect(
        await runner.run(['pdf', 'info', 'cloud://test/input.pdf', '--json']),
        1,
      );
      expect(output.toString(), isEmpty);
      expect(jsonDecode(errors.toString())['code'], 'configuration');
      expect(errors.toString(), isNot(contains(secret)));
    },
  );

  test('case-only remote destinations require exact spelling', () async {
    client.files['/Result.pdf'] = Uint8List.fromList([1]);
    await expectLater(
      store.prepareOutput('cloud://test/result.pdf', overwrite: false),
      throwsA(failure('ambiguousPath')),
    );
  });

  test('remote read-back mismatch is reported instead of success', () async {
    client.corruptUpload = true;
    final output = await store.prepareOutput(
      'cloud://test/result.pdf',
      overwrite: false,
    );
    await expectLater(
      store.writeOutput(output, Uint8List.fromList([1, 2])),
      throwsA(failure('verificationFailed')),
    );
  });

  test('local output aliases and symlinks are rejected', () async {
    final original = File('${temporary.path}/input.pdf')
      ..writeAsBytesSync([1, 2, 3]);
    await store.readBytes(original.path);
    await expectLater(
      store.prepareOutput(original.path, overwrite: true),
      throwsA(failure('sourceOutput')),
    );
    if (!Platform.isWindows) {
      final link = Link('${temporary.path}/alias.pdf')
        ..createSync(original.path);
      await expectLater(
        store.prepareOutput(link.path, overwrite: true),
        throwsA(failure('sourceOutput')),
      );
      final unrelated = File('${temporary.path}/unrelated.pdf')
        ..writeAsBytesSync([4]);
      final outputLink = Link('${temporary.path}/output.pdf')
        ..createSync(unrelated.path);
      await expectLater(
        store.prepareOutput(outputLink.path, overwrite: true),
        throwsA(failure('invalidOutput')),
      );
      expect(unrelated.readAsBytesSync(), [4]);
    }
    expect(original.readAsBytesSync(), [1, 2, 3]);
  });

  test('a hard link to an input is refused', () async {
    if (Platform.isWindows) return;
    final original = File('${temporary.path}/input.pdf')
      ..writeAsBytesSync([1, 2, 3]);
    final alias = '${temporary.path}/hardlink.pdf';
    expect((await Process.run('ln', [original.path, alias])).exitCode, 0);
    await store.readBytes(original.path);
    await expectLater(
      store.prepareOutput(alias, overwrite: true),
      throwsA(failure('sourceOutput')),
    );
    expect(original.readAsBytesSync(), [1, 2, 3]);
  });

  test(
    'local new files reserve their name and use private permissions',
    () async {
      final target = '${temporary.path}/result.pdf';
      final output = await store.prepareOutput(target, overwrite: false);
      await store.writeOutput(output, Uint8List.fromList([1, 2, 3]));
      expect(File(target).readAsBytesSync(), [1, 2, 3]);
      if (!Platform.isWindows)
        expect(File(target).statSync().mode & 0x1ff, 0x180);
    },
  );

  test(
    'private password files and a single stdin consumer are enforced',
    () async {
      final password = File('${temporary.path}/password.txt')
        ..writeAsStringSync('private');
      if (!Platform.isWindows) {
        expect(
          (await Process.run('chmod', ['644', password.path])).exitCode,
          0,
        );
        await expectLater(
          store.readUtf8(password.path, secret: true),
          throwsA(failure('passwordPermissions')),
        );
      }
      final stdinStore = PdfCliFileStore(
        config,
        input: Stream.value(utf8.encode('private')),
        inputHasTerminal: false,
      );
      expect(await stdinStore.readUtf8('-', secret: true), 'private');
      await expectLater(
        stdinStore.readUtf8('-'),
        throwsA(failure('stdinUsed')),
      );
      await stdinStore.dispose();
    },
  );

  test(
    'CLI PDF mutation uses remote source and output through the shared engine',
    () async {
      var fixture = File('../test/fixtures/pdf_editor/form_rotated.pdf');
      if (!fixture.existsSync())
        fixture = File('test/fixtures/pdf_editor/form_rotated.pdf');
      final sourceBytes = fixture.readAsBytesSync();
      client.files['/source.pdf'] = sourceBytes;
      final output = StringBuffer();
      final errors = StringBuffer();
      final runner = CommandRunner<int>('crisp', 'test')
        ..addCommand(
          PdfCommand(
            config,
            adapterFactory: (_, _) => client,
            output: output,
            errors: errors,
          ),
        );
      final code = await runner.run([
        'pdf',
        'rotate',
        'cloud://test/source.pdf',
        '--pages',
        '2',
        '--degrees',
        '90',
        '--output',
        'cloud://test/result.pdf',
        '--json',
      ]);
      expect(code, 0, reason: errors.toString());
      final result = jsonDecode(output.toString()) as Map<String, dynamic>;
      expect(result['status'], 'ok');
      expect(result['warnings'], isNotEmpty);
      final inspection = PdfOperationsService().inspect(
        PdfInput(client.files['/result.pdf']!),
      );
      expect(inspection.pages.map((page) => page.rotation), [0, 180]);
      expect(client.files['/source.pdf'], sourceBytes);
      expect(client.disposed, isTrue);
    },
  );

  group('complete XML directory listings', () {
    Future<HttpServer> serverWithXml(String body, {int status = 200}) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await request.drain<void>();
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType('application', 'xml');
        // S3 XML is UTF-8 even when the HTTP media type has no charset.
        request.response.add(utf8.encode(body));
        await request.response.close();
      });
      return server;
    }

    S3CliAdapter s3(HttpServer server) => S3CliAdapter(
      accessKey: 'fixture',
      secretKey: 'fixture',
      bucket: 'pdfs',
      endpoint: 'http://127.0.0.1:${server.port}',
      region: 'us-east-1',
    );

    test(
      'S3 parses escaped keys, namespaces and arbitrary property order',
      () async {
        final server = await serverWithXml('''
<S:ListBucketResult xmlns:S="http://s3.amazonaws.com/doc/2006-03-01/">
  <S:KeyCount>2</S:KeyCount><S:IsTruncated>false</S:IsTruncated>
  <S:Contents><S:Size>3</S:Size><S:Key>docs/Grüße &amp; 文.pdf</S:Key></S:Contents>
  <S:CommonPrefixes><S:Prefix>docs/folder&amp;name/</S:Prefix></S:CommonPrefixes>
</S:ListBucketResult>''');
        final adapter = s3(server);
        try {
          final listing = await adapter.list('/docs');
          expect(listing.map((entry) => entry.name), [
            'Grüße & 文.pdf',
            'folder&name',
          ]);
          expect(listing.map((entry) => entry.path), [
            '/docs/Grüße & 文.pdf',
            '/docs/folder&name/',
          ]);
          config.saveProvider('s3-xml', {
            'type': 's3',
            'endpoint': 'http://127.0.0.1:${server.port}',
            'bucket': 'pdfs',
          });
          final fileStore = PdfCliFileStore(
            config,
            adapterFactory: (_, _) => adapter,
          );
          try {
            await expectLater(
              fileStore.prepareOutput(
                'cloud://s3-xml/docs/${Uri.encodeComponent('Grüße & 文.pdf')}',
                overwrite: false,
              ),
              throwsA(failure('outputExists')),
            );
          } finally {
            await fileStore.dispose();
          }
        } finally {
          await server.close(force: true);
        }
      },
    );

    test(
      'S3 never accepts malformed or incomplete success responses as empty',
      () async {
        for (final body in [
          '<html>Sign in</html>',
          '<ListBucketResult><IsTruncated>false</IsTruncated><Contents><Key>secret.pdf</Key></Contents></ListBucketResult>',
          '<ListBucketResult><IsTruncated>true</IsTruncated></ListBucketResult>',
          '<ListBucketResult><KeyCount>1</KeyCount><IsTruncated>false</IsTruncated></ListBucketResult>',
        ]) {
          final server = await serverWithXml(body);
          final adapter = s3(server);
          try {
            await expectLater(adapter.list('/'), throwsA(isA<StateError>()));
          } finally {
            await adapter.dispose();
            await server.close(force: true);
          }
        }
      },
    );

    test('S3 refuses a repeated pagination token', () async {
      final server = await serverWithXml('''<ListBucketResult>
<IsTruncated>true</IsTruncated><NextContinuationToken>same&amp;token</NextContinuationToken>
</ListBucketResult>''');
      final adapter = s3(server);
      try {
        await expectLater(adapter.list('/'), throwsA(isA<StateError>()));
      } finally {
        await adapter.dispose();
        await server.close(force: true);
      }
    });

    String davXml({String prefix = '', bool denyChild = false}) {
      final tag = prefix.isEmpty ? '' : '$prefix:';
      String response(
        String path, {
        bool directory = false,
        bool denied = false,
      }) =>
          '''
<${tag}response><${tag}href>$path</${tag}href><${tag}propstat>
<${tag}prop><${tag}resourcetype>${directory ? '<${tag}collection/>' : ''}</${tag}resourcetype>
<${tag}getcontentlength>${directory ? 0 : 3}</${tag}getcontentlength></${tag}prop>
<${tag}status>HTTP/1.1 ${denied ? '403 Forbidden' : '200 OK'}</${tag}status>
</${tag}propstat></${tag}response>''';
      return '''<${tag}multistatus xmlns${prefix.isEmpty ? '' : ':$prefix'}="DAV:">
${response('/dav/Account%20Name/docs/', directory: true)}
${response('/dav/Account%20Name/docs/a%20%26%20b.pdf', denied: denyChild)}
</${tag}multistatus>''';
    }

    test(
      'WebDAV resolves names and logical paths with any namespace prefix',
      () async {
        for (final prefix in ['', 'arbitrary']) {
          final server = await serverWithXml(
            davXml(prefix: prefix),
            status: 207,
          );
          final adapter = WebDavCliAdapter(
            baseUrl: 'http://127.0.0.1:${server.port}/dav/Account%20Name',
            username: 'fixture',
            password: 'fixture',
          );
          try {
            final listing = await adapter.list('/docs');
            expect(listing, hasLength(1));
            expect(listing.single.name, 'a & b.pdf');
            expect(listing.single.path, '/docs/a & b.pdf');
            expect(listing.single.size, 3);
          } finally {
            await adapter.dispose();
            await server.close(force: true);
          }
        }
      },
    );

    test(
      'WebDAV failed or incomplete property responses block output checks',
      () async {
        for (final body in [
          '<html>Sign in</html>',
          '<multistatus xmlns="DAV:"/>',
          davXml(denyChild: true),
        ]) {
          final server = await serverWithXml(body, status: 207);
          config.saveProvider('dav-xml', {
            'type': 'webdav',
            'host': 'http://127.0.0.1:${server.port}/dav/Account%20Name',
          });
          final adapter = WebDavCliAdapter(
            baseUrl: 'http://127.0.0.1:${server.port}/dav/Account%20Name',
            username: 'fixture',
            password: 'fixture',
          );
          final fileStore = PdfCliFileStore(
            config,
            adapterFactory: (_, _) => adapter,
          );
          try {
            await expectLater(
              fileStore.prepareOutput(
                'cloud://dav-xml/docs/new.pdf',
                overwrite: false,
              ),
              throwsA(failure('listingFailed')),
            );
          } finally {
            await fileStore.dispose();
            await server.close(force: true);
          }
        }
      },
    );
  });

  group('bounded HTTP streams', () {
    test(
      'WebDAV cloud filenames keep reserved characters in the path',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = <Uri>[];
        server.listen((request) async {
          requests.add(request.uri);
          request.response.add([1, 2, 3]);
          await request.response.close();
        });
        final adapter = WebDavCliAdapter(
          baseUrl: 'http://127.0.0.1:${server.port}/dav/Account%20Name',
          username: 'test',
          password: 'fixture',
        );
        try {
          expect(
            await adapter.downloadBytesBounded('/docs/a #b%?.pdf', maxBytes: 3),
            [1, 2, 3],
          );
          expect(requests.single.pathSegments, [
            'dav',
            'Account Name',
            'docs',
            'a #b%?.pdf',
          ]);
          expect(requests.single.hasQuery, isFalse);
          expect(requests.single.hasFragment, isFalse);
        } finally {
          await adapter.dispose();
          await server.close(force: true);
        }
      },
    );

    test('unknown length cannot bypass the byte limit', () async {
      var delivered = 0;
      Stream<List<int>> chunks() async* {
        for (var i = 0; i < 100; i++) {
          delivered++;
          yield List.filled(8, 65);
        }
      }

      final client = MockClient.streaming((request, _) async {
        expect(request.followRedirects, isFalse);
        return http.StreamedResponse(chunks(), 200);
      });
      await expectLater(
        boundedHttpDownload(
          Uri.parse('https://example.test/pdf'),
          headers: const {},
          maxBytes: 16,
          client: client,
        ),
        throwsA(isA<CliDownloadLimitException>()),
      );
      expect(delivered, lessThan(100));
    });

    test('declared oversize is rejected and exact limit is accepted', () async {
      final large = MockClient.streaming(
        (_, _) async =>
            http.StreamedResponse(Stream.value([1]), 200, contentLength: 100),
      );
      await expectLater(
        boundedHttpDownload(
          Uri.parse('https://example.test/pdf'),
          headers: const {},
          maxBytes: 2,
          client: large,
        ),
        throwsA(isA<CliDownloadLimitException>()),
      );
      final exact = MockClient.streaming(
        (_, _) async =>
            http.StreamedResponse(Stream.value([1, 2]), 200, contentLength: 2),
      );
      expect(
        await boundedHttpDownload(
          Uri.parse('https://example.test/pdf'),
          headers: const {},
          maxBytes: 2,
          client: exact,
        ),
        [1, 2],
      );
    });

    test(
      'redirects do not follow credentials and error bodies stay private',
      () async {
        final client = MockClient.streaming((request, _) async {
          expect(request.followRedirects, isFalse);
          return http.StreamedResponse(
            Stream.value(utf8.encode('private response')),
            302,
            headers: {'location': 'https://elsewhere.test/file'},
          );
        });
        await expectLater(
          boundedHttpDownload(
            Uri.parse('https://example.test/pdf'),
            headers: const {'Authorization': 'private credential'},
            maxBytes: 100,
            client: client,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(contains('302'), isNot(contains('private'))),
            ),
          ),
        );
      },
    );
  });
}

class _MemoryClient implements CliStorageClient, CliBoundedDownload {
  final files = <String, Uint8List>{};
  int listCalls = 0;
  int statCalls = 0;
  int downloadCalls = 0;
  int unboundedCalls = 0;
  int uploadCalls = 0;
  bool failListing = false;
  bool corruptUpload = false;
  bool disposed = false;

  @override
  String get providerName => 'memory';

  @override
  Future<List<CliFileItem>> list(String remotePath) async {
    listCalls++;
    if (failListing) throw StateError('access denied');
    final prefix = remotePath == '/' ? '/' : '$remotePath/';
    return [
      for (final entry in files.entries)
        if (entry.key.startsWith(prefix) &&
            !entry.key.substring(prefix.length).contains('/'))
          CliFileItem(
            name: entry.key.substring(prefix.length),
            path: entry.key,
            isDirectory: false,
            size: entry.value.length,
          ),
    ];
  }

  @override
  Future<Uint8List> downloadBytesBounded(
    String remotePath, {
    required int maxBytes,
  }) async {
    downloadCalls++;
    final bytes = files[remotePath]!;
    if (bytes.length > maxBytes) throw CliDownloadLimitException(maxBytes);
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> upload(
    List<int> data,
    String fileName,
    String remoteDir, {
    void Function(int, int)? onProgress,
  }) async {
    uploadCalls++;
    final path = remoteDir == '/' ? '/$fileName' : '$remoteDir/$fileName';
    files[path] = Uint8List.fromList(corruptUpload ? [99] : data);
  }

  @override
  Future<CliFileItem?> stat(String remotePath) async {
    statCalls++;
    return null;
  }

  @override
  Future<List<int>> downloadBytes(String remotePath) async {
    unboundedCalls++;
    throw StateError('Unbounded reads are forbidden.');
  }

  @override
  Future<void> download(
    String remotePath,
    String localPath, {
    void Function(int, int)? onProgress,
  }) => throw UnimplementedError();

  @override
  Future<void> createDirectory(String remotePath) => throw UnimplementedError();

  @override
  Future<void> delete(String remotePath) => throw UnimplementedError();

  @override
  Future<void> move(String sourcePath, String targetPath) =>
      throw UnimplementedError();

  @override
  Future<String> share(String remotePath, {Duration? expires}) =>
      throw UnimplementedError();

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
