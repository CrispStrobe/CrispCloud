import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/filen_client_adapter.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/internxt_client_adapter.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_storage/rust_cloud.dart';
import 'package:crisp_storage/rust_cloud_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internxt_client/internxt_client.dart' as inxt;
import 'package:shared_preferences/shared_preferences.dart';

/// Internxt ConfigService storage backed by memory (no files, no keychain).
class _MemoryInternxtStorage implements inxt.ConfigStorage {
  final values = <String, String>{};
  @override
  void init(String dataDir, List<String> subDirs) {}
  @override
  Future<bool> exists(String key) async => values.containsKey(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeRustCloudApi api;
  late FilenConfigService filenConfig;
  late FilenClientAdapter filen;
  late InternxtClientAdapter internxt;
  late Directory temp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    RustCloudSession.progressInterval = const Duration(milliseconds: 5);
    api = FakeRustCloudApi();
    temp = await Directory.systemTemp.createTemp('rust-adapter-test-');
    api.onDownloadFile = (path) => File(path).writeAsBytes([1, 2, 3, 4, 5]);
    filenConfig = FilenConfigService(
      configPath: '${temp.path}/filen',
      secureStorage: InMemorySecureStorage(),
    );
    filen = FilenClientAdapter(config: filenConfig, rustApi: api);
    internxt = InternxtClientAdapter(
      config: inxt.ConfigService(
        configPath: '${temp.path}/internxt',
        storage: _MemoryInternxtStorage(),
      ),
      rustApi: api,
    );
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('engine defaults', () {
    test('both adapters default to the Dart engine', () {
      expect(filen.engine, CloudEngine.dart);
      expect(internxt.engine, CloudEngine.dart);
      expect(filen.effectiveEngine, isNull);
      expect(internxt.effectiveEngine, isNull);
    });
  });

  group('Filen Rust engine', () {
    test('strict rust login stores a versioned Rust session', () async {
      filen.engine = CloudEngine.rust;
      await filen.login('me@example.com', 'pw', twoFactorCode: '654321');
      expect(api.calls.first, 'login:filen:me@example.com:654321');
      expect(filen.effectiveEngine, CloudEngine.rust);
      expect(filen.isAuthenticated, isTrue);
      expect(filen.userId, 'a@b.c');
      final saved = await filenConfig.readCredentials();
      expect(saved!['engine'], 'rust');
      expect(saved['email'], 'me@example.com');
      expect(saved.containsKey('apiKey'), isFalse);
      final envelope = jsonDecode(saved['rustSession']!) as Map;
      expect(envelope['format'], 'crisp-cloud-rust-session');
      expect(envelope['version'], 1);
      expect(envelope['provider'], 'filen');
    });

    test('strict rust reports unavailability before sending credentials',
        () async {
      api.available = false;
      filen.engine = CloudEngine.rust;
      await expectLater(
        filen.login('me@example.com', 'pw'),
        throwsA(isA<RustCloudUnavailable>()),
      );
      expect(api.calls, isEmpty);
      expect(await filenConfig.readCredentials(), isNull);
      expect(filen.isAuthenticated, isFalse);
    });

    test('auto never falls back after a Rust sign-in failure', () async {
      filen.engine = CloudEngine.auto;
      api.loginError = const RustCloudException(RustCloudErrorCode.authFailed);
      await expectLater(
        filen.login('me@example.com', 'wrong'),
        throwsA(isA<RustCloudException>()),
      );
      expect(filen.effectiveEngine, isNull);
      expect(filen.isAuthenticated, isFalse);
      expect(await filenConfig.readCredentials(), isNull);
    });

    test('restore uses Rust for Rust-format credentials', () async {
      final restored = await filen.restoreSavedSession({
        'email': 'me@example.com',
        'engine': 'rust',
        'rustSession': FakeRustCloudApi.envelope('filen'),
      });
      expect(restored, isTrue);
      expect(filen.effectiveEngine, CloudEngine.rust);
      expect(api.initializeCalls, 1);
    });

    test('restore of a Rust session never falls back when unavailable',
        () async {
      api.available = false;
      await expectLater(
        filen.restoreSavedSession({
          'email': 'me@example.com',
          'rustSession': FakeRustCloudApi.envelope('filen'),
        }),
        throwsA(isA<RustCloudUnavailable>()),
      );
      expect(filen.isAuthenticated, isFalse);
    });

    test('restore rejects an Internxt envelope in Filen credentials', () async {
      await expectLater(
        filen.restoreSavedSession({
          'email': 'me@example.com',
          'rustSession': FakeRustCloudApi.envelope('internxt'),
        }),
        throwsA(
          isA<RustCloudException>().having(
            (e) => e.code,
            'code',
            RustCloudErrorCode.providerMismatch,
          ),
        ),
      );
    });

    test('legacy Dart credentials restore through the Dart client', () async {
      final restored = await filen.restoreSavedSession({
        'email': 'me@example.com',
        'apiKey': 'k',
        'masterKeys': 'm',
        'baseFolderUUID': 'root',
      });
      expect(restored, isTrue);
      expect(filen.effectiveEngine, CloudEngine.dart);
      expect(api.initializeCalls, 0);
      expect(
        await filen.restoreSavedSession({'email': 'me@example.com'}),
        isFalse,
      );
    });

    Future<void> rustFilen() async {
      filen.engine = CloudEngine.rust;
      await filen.login('me@example.com', 'pw');
      api.calls.clear();
    }

    test('listPath maps entries to the panel format', () async {
      await rustFilen();
      final listing = await filen.listPath('/Docs');
      expect(api.calls, ['list:/Docs:false']);
      final folders = listing['folders'] as List;
      final files = listing['files'] as List;
      expect(folders.single['name'], 'Docs');
      expect(folders.single['uuid'], 'd1');
      expect((folders.single as Map).containsKey('size'), isFalse);
      expect(files.single['name'], 'a.txt');
      expect(files.single['size'], 3);
      expect(files.single['lastModified'], 1700000000000);
      expect(files.single['mime'], 'text/plain');
      expect((files.single as Map).containsKey('type'), isFalse);
    });

    test('readDirectoryForEdit requests a fresh listing', () async {
      await rustFilen();
      await filen.readDirectoryForEdit('/Docs');
      expect(api.calls, ['list:/Docs:true']);
    });

    test('resolvePath returns null only for NotFound', () async {
      await rustFilen();
      final found = await filen.resolvePath('/x/a.txt');
      expect(found!['type'], 'file');
      expect(found['uuid'], 'f1');
      api.nextError = const RustCloudException(RustCloudErrorCode.notFound);
      expect(await filen.resolvePath('/missing'), isNull);
      api.nextError = const RustCloudException(RustCloudErrorCode.network);
      await expectLater(
        filen.resolvePath('/x'),
        throwsA(isA<RustCloudException>()),
      );
    });

    test('folder, rename, move and delete route to Rust', () async {
      await rustFilen();
      await filen.createFolderPath('/a/b');
      await filen.renamePath('/a/b', 'c');
      await filen.movePath('/a/c', '/z');
      await filen.deletePath('/z/c');
      expect(api.calls, [
        'mkdir:/a/b',
        'rename:/a/b:c',
        'move:/a/c:/z',
        'trash:/z/c',
      ]);
    });

    test('uploadFile spools bytes to a private temp file', () async {
      await rustFilen();
      List<int>? uploaded;
      String? uploadedPath;
      api.onUploadFile = (path) async {
        uploadedPath = path;
        uploaded = await File(path).readAsBytes();
      };
      final progress = <int>[];
      await filen.uploadFile(
        [7, 8, 9],
        'n.bin',
        '/up',
        onProgress: (d, _) => progress.add(d),
      );
      expect(uploaded, [7, 8, 9]);
      expect(api.calls, ['upload:/up:n.bin']);
      expect(progress.last, 10);
      expect(File(uploadedPath!).existsSync(), isFalse);
    });

    test('uploadStream rejects a short stream before uploading', () async {
      await rustFilen();
      await expectLater(
        filen.uploadStream(Stream.value([1, 2]), 5, 'x.bin', '/'),
        throwsStateError,
      );
      expect(api.calls, isEmpty);
    });

    test('downloadFileBytes and downloadStream return the file', () async {
      await rustFilen();
      expect(await filen.downloadFileBytes('/a.txt'), [1, 2, 3, 4, 5]);
      final chunks = await filen.downloadStream('/a.txt').toList();
      expect(chunks.expand((c) => c).toList(), [1, 2, 3, 4, 5]);
    });

    test('downloadFileByPath publishes the downloaded file', () async {
      await rustFilen();
      final target = '${temp.path}/out.bin';
      await filen.downloadFileByPath('/a.txt', target);
      expect(await File(target).readAsBytes(), [1, 2, 3, 4, 5]);
    });

    test('failed download keeps an existing destination', () async {
      await rustFilen();
      final target = File('${temp.path}/keep.bin')..writeAsBytesSync([9]);
      api.nextError = const RustCloudException(
        RustCloudErrorCode.integrity,
      );
      await expectLater(
        filen.downloadFileByPath('/a.txt', target.path),
        throwsA(isA<RustCloudException>()),
      );
      expect(target.readAsBytesSync(), [9]);
    });

    test('renewed sessions are persisted after an operation', () async {
      await rustFilen();
      api.revisionValue = 2;
      await filen.listPath('/');
      final saved = await filenConfig.readCredentials();
      expect(saved!['rustSession'], contains('renewed@b.c'));
      expect(saved['engine'], 'rust');
    });

    test('logout closes the Rust session and clears credentials', () async {
      await rustFilen();
      await filen.logout();
      expect(api.closed, hasLength(1));
      expect(filen.isAuthenticated, isFalse);
      expect(filen.effectiveEngine, isNull);
      expect(await filenConfig.readCredentials(), isNull);
    });

    test('a new login closes the previous Rust session', () async {
      await rustFilen();
      await filen.login('me@example.com', 'pw');
      expect(api.closed, hasLength(1));
    });
  });

  group('Internxt Rust engine', () {
    Future<void> rustInternxt() async {
      internxt.engine = CloudEngine.rust;
      await internxt.login('t@example.com', 'pw');
      api.calls.clear();
    }

    test('login stores only the Rust envelope', () async {
      internxt.engine = CloudEngine.rust;
      await internxt.login('t@example.com', 'pw', twoFactorCode: '111111');
      expect(api.calls.first, 'login:internxt:t@example.com:111111');
      expect(internxt.lastLoginResponse, isNull);
      expect(internxt.effectiveEngine, CloudEngine.rust);
      final saved = (await internxt.config.readCredentials())!;
      expect(saved.keys.toSet(), {'email', 'engine', 'rustSession'});
      expect(jsonDecode(saved['rustSession'] as String)['provider'],
          'internxt');
    });

    test('2FA is reported by sign-in, not a Dart pre-check', () async {
      internxt.engine = CloudEngine.rust;
      expect(await internxt.is2faNeeded('t@example.com'), isFalse);
      api.loginError = const RustCloudException(
        RustCloudErrorCode.twoFactorRequired,
      );
      await expectLater(
        internxt.login('t@example.com', 'pw'),
        throwsA(
          isA<RustCloudException>().having(
            (e) => e.code,
            'code',
            RustCloudErrorCode.twoFactorRequired,
          ),
        ),
      );
    });

    test('auto uses Dart when Rust is unavailable before sign-in', () async {
      api.available = false;
      internxt.engine = CloudEngine.auto;
      // The Dart login would contact the network; stop at engine selection.
      final selected = await selectCloudEngine(
        internxt.engine,
        api.initialize,
      );
      expect(selected, CloudEngine.dart);
    });

    test('restore picks the engine from the credential format', () async {
      expect(
        await internxt.restoreSavedSession({
          'email': 't@example.com',
          'rustSession': FakeRustCloudApi.envelope('internxt'),
        }),
        isTrue,
      );
      expect(internxt.effectiveEngine, CloudEngine.rust);
      expect(await internxt.restoreSavedSession({'email': 'x'}), isFalse);
      expect(internxt.effectiveEngine, CloudEngine.rust);
    });

    test('operations route to Rust and identity is engine-specific', () async {
      await rustInternxt();
      await internxt.listPath('/');
      await internxt.createFolderPath('/n');
      await internxt.renamePath('/n', 'm.txt');
      await internxt.movePath('/m.txt', '/d');
      await internxt.deletePath('/d/m.txt');
      expect(api.calls, [
        'list:/:false',
        'mkdir:/n',
        'rename:/n:m.txt',
        'move:/m.txt:/d',
        'trash:/d/m.txt',
      ]);
      expect(internxt.bucketId, isNull);
      expect(jsonDecode(internxt.transferIdentity)[0], 'internxt-rust');
    });

    test('rename still validates names before the engine', () async {
      await rustInternxt();
      await expectLater(
        internxt.renamePath('/a', 'x/y'),
        throwsFormatException,
      );
      expect(api.calls, isEmpty);
    });

    test('Dart-only search is refused explicitly in Rust mode', () async {
      await rustInternxt();
      await expectLater(internxt.search('q'), throwsUnsupportedError);
      await expectLater(internxt.findFiles('/', '*'), throwsUnsupportedError);
    });

    test('downloadFileBytes applies the 32 MiB buffer limit', () async {
      await rustInternxt();
      expect(await internxt.downloadFileBytes('/a.txt'), [1, 2, 3, 4, 5]);
      expect(api.calls.first, 'stat:/a.txt');
    });

    test('logout closes Rust and clears saved credentials', () async {
      await rustInternxt();
      await internxt.logout();
      expect(api.closed, hasLength(1));
      expect(await internxt.config.readCredentials(), isNull);
      expect(internxt.isAuthenticated, isFalse);
    });
  });
}
