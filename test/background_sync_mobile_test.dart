import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/background_sync_mobile.dart' as mobile;
import 'package:crisp_cloud/services/background_sync_service.dart';
import 'package:crisp_cloud/services/background_transfer_journal.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/ftp_client_adapter.dart';
import 'package:crisp_cloud/services/ftp_config_service.dart';
import 'package:crisp_cloud/services/locale_preference.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/sync_database.dart';
import 'package:crisp_cloud/services/webdav_client_adapter.dart';
import 'package:crisp_cloud/services/webdav_config_service.dart';
import 'package:dio/dio.dart' as dio;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:workmanager/workmanager.dart';

import 'support/sync_test_binding.dart';
import 'support/workflow_fake_client.dart';

const _ftpCredentials = {
  'host': '2001:db8::4',
  'port': '2121',
  'username': 'worker@team',
  'password': 'fixture-ftp-secret',
  'useTLS': 'true',
};
const _webDavCredentials = {
  'host': 'https://dav.example.test:8443/dav/accounts/team',
  'username': 'worker@example.test',
  'password': 'fixture-webdav-secret',
};

class _TrackedSecureStorage extends SecureStorage {
  final values = <String, String>{};
  final reads = <String>[];
  final mutations = <String>[];
  bool unavailable = false;

  void seed(String key, Map<String, String> credentials) {
    values[key] = jsonEncode(credentials);
  }

  @override
  Future<String?> read(String key) async {
    reads.add(key);
    if (unavailable) throw StateError('Keychain is locked');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    mutations.add('write:$key');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    mutations.add('delete:$key');
    values.remove(key);
  }

  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);
  @override
  Future<void> deleteAll() async {
    mutations.add('deleteAll');
    values.clear();
  }
}

class _FtpNetwork implements FTPConnect {
  bool accepted = true;
  int connects = 0;
  int disconnects = 0;
  int listings = 0;
  final opened = <String>[];
  @override
  Future<bool> connect() async {
    connects++;
    return accepted;
  }

  @override
  Future<bool> disconnect() async {
    disconnects++;
    return true;
  }

  @override
  Future<String> currentDirectory() async => '/';

  @override
  Future<bool> changeDirectory(String? path) async {
    opened.add(path!);
    return true;
  }

  @override
  Future<List<FTPEntry>> listDirectoryContent() async {
    listings++;
    return opened.last == '/'
        ? [FTPEntry.parse('type=dir; docs', ListCommand.mlsd)]
        : [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FTPClientFactory _ftpFactory(
  _FtpNetwork network, {
  void Function(String, int, String, String, SecurityType)? inspect,
}) =>
    (
      String host, {
      required int port,
      required String user,
      required String pass,
      required SecurityType securityType,
      required int timeout,
    }) {
      inspect?.call(host, port, user, pass, securityType);
      expect(timeout, 30);
      return network;
    };

class _DavNetwork implements dio.HttpClientAdapter {
  _DavNetwork(this.respond);
  final Future<dio.ResponseBody> Function(dio.RequestOptions) respond;
  final requests = <dio.RequestOptions>[];
  bool closed = false;
  @override
  Future<dio.ResponseBody> fetch(
    dio.RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await requestStream?.drain<void>();
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) => closed = true;
}

webdav.Client Function(String, String, String) _davFactory(
  _DavNetwork network, {
  void Function(String, String, String)? inspect,
}) => (url, user, password) {
  inspect?.call(url, user, password);
  final client = webdav.newClient(url, user: user, password: password);
  client.c.httpClientAdapter = network;
  return client;
};

dio.ResponseBody _davSuccess() => dio.ResponseBody.fromString(
  '<d:multistatus xmlns:d="DAV:"/>',
  207,
  headers: {
    'content-type': ['application/xml'],
  },
);

class _Scheduler extends WorkmanagerPlatform {
  final cancelled = <String>[];
  String? uniqueName;
  String? callbackId;
  Duration? interval;
  bool accepted = true;
  bool rejectRegistration = false;
  bool retainPreviousRequest = false;

  @override
  Future<bool> isScheduledByUniqueName(String uniqueName) async =>
      accepted && uniqueName == this.uniqueName;
  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    cancelled.add(uniqueName);
    if (uniqueName == this.uniqueName) accepted = false;
  }

  @override
  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Duration? flexInterval,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
  }) async {
    if (rejectRegistration) throw StateError('Scheduler rejected the update');
    if (retainPreviousRequest && this.uniqueName != null) return;
    this.uniqueName = uniqueName;
    callbackId = taskName;
    interval = frequency;
    expect(initialDelay, frequency);
    expect(constraints!.networkType, NetworkType.connected);
    expect(constraints.requiresBatteryNotLow, isTrue);
  }
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _Notices {
  final titles = <String>[];
  final bodies = <String>[];
  Future<void> send({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
  }) async {
    titles.add(title);
    bodies.add(body);
  }
}

Future<SyncPair> _pair(
  SyncDatabase db,
  String local,
  CloudStorageClient client, {
  String provider = 'ftp',
}) async => bindTestPair(
  db,
  await db.getPair(
    await db.insertPair(
      SyncPairsCompanion.insert(
        name: 'Saved account',
        localPath: local,
        remotePath: '/docs',
        provider: provider,
      ),
    ),
  ),
  client,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('worker localizes failures without reporting unavailable accounts as success', () async {
    final root = await Directory.systemTemp.createTemp('background-locale-');
    addTearDown(() => root.delete(recursive: true));
    final local = await Directory(p.join(root.path, 'local')).create();
    final db = SyncDatabase.forTesting(NativeDatabase.memory());
    await _pair(db, local.path, WorkflowFakeClient());
    // Pair binding initializes the installation identity and resets its mock
    // preferences once. Persist the UI language after that fixture setup.
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(LocalePreference.key, 'de');
    expect((await LocalePreference.read())?.languageCode, 'de');
    final notices = _Notices();
    final success = await BackgroundSyncService.executeBackgroundTask(
      databaseFactory: () => db,
      clientFactory: (_) async => null,
      journalFactory: () => createBackgroundTransferJournalRun(
        rootPath: p.join(root.path, 'runs'),
      ),
      notificationSender: notices.send,
    );
    expect(success, isFalse);
    expect(notices.titles.single, 'CrispCloud-Synchronisierung');
    expect(notices.bodies.single, contains('1 Fehler'));
    expect(
      notices.bodies.single,
      contains('Hintergrundverbindung für ftp nicht verfügbar'),
    );
    expect(await local.list().toList(), isEmpty);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '${platform.name} registered callback actually dispatches the sync',
      () async {
        final previous = WorkmanagerPlatform.instance;
        final scheduler = _Scheduler();
        WorkmanagerPlatform.instance = scheduler;
        addTearDown(() => WorkmanagerPlatform.instance = previous);
        await mobile.scheduleWorkmanagerTask(
          uniqueName: kBackgroundSyncTaskName,
          taskId: kBackgroundSyncTaskId,
          intervalMinutes: 30,
          targetPlatform: platform,
        );
        expect(scheduler.interval, const Duration(minutes: 30));
        expect(
          scheduler.uniqueName,
          platform == TargetPlatform.iOS
              ? kBackgroundSyncTaskId
              : kBackgroundSyncTaskName,
        );
        final delivered = platform == TargetPlatform.iOS
            ? scheduler.uniqueName!
            : scheduler.callbackId!;
        var runs = 0;
        expect(
          await mobile.dispatchBackgroundSyncTask(
            delivered,
            null,
            execute: () async {
              runs++;
              return false;
            },
          ),
          isFalse,
        );
        expect(runs, 1);
        scheduler.cancelled.clear();
        await mobile.cancelWorkmanagerTask(
          kBackgroundSyncTaskName,
          targetPlatform: platform,
        );
        expect(scheduler.cancelled, contains(scheduler.uniqueName));
      },
    );
  }

  test(
    'iOS registration rejection is surfaced instead of appearing enabled',
    () async {
      final previous = WorkmanagerPlatform.instance;
      WorkmanagerPlatform.instance = _Scheduler()..accepted = false;
      addTearDown(() => WorkmanagerPlatform.instance = previous);
      await expectLater(
        mobile.scheduleWorkmanagerTask(
          uniqueName: kBackgroundSyncTaskName,
          taskId: kBackgroundSyncTaskId,
          intervalMinutes: 30,
          targetPlatform: TargetPlatform.iOS,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('did not accept'),
          ),
        ),
      );
    },
  );

  test(
    'legacy task names dispatch, unknown tasks fail without running sync',
    () async {
      var calls = 0;
      Future<bool> run() async {
        calls++;
        return true;
      }

      expect(
        await mobile.dispatchBackgroundSyncTask(
          kBackgroundSyncTaskName,
          null,
          execute: run,
        ),
        isTrue,
      );
      expect(
        await mobile.dispatchBackgroundSyncTask(
          'unrelated-task',
          null,
          execute: run,
        ),
        isFalse,
      );
      expect(calls, 1);
    },
  );

  test(
    'default platform secure channel restores credentials read-only',
    () async {
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        final arguments = call.arguments as Map;
        expect(arguments['key'], 'ftp_credentials');
        return jsonEncode(_ftpCredentials);
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final network = _FtpNetwork();
      final client = await mobile.buildClientForProvider(
        'ftp',
        ftpClientFactory: _ftpFactory(network),
      );
      expect(client.isAuthenticated, isTrue);
      await client.logout();
      expect(network.disconnects, 1);
      expect(methods, ['read']);
    },
  );

  test(
    'failed reschedule retains the accepted Apple task and saved interval',
    () async {
      SharedPreferences.setMockInitialValues({
        'background_sync_enabled': true,
        'background_sync_interval_minutes': 30,
      });
      final previous = WorkmanagerPlatform.instance;
      final scheduler = _Scheduler()
        ..uniqueName = kBackgroundSyncTaskId
        ..callbackId = kBackgroundSyncTaskId
        ..interval = const Duration(minutes: 30)
        ..rejectRegistration = true;
      WorkmanagerPlatform.instance = scheduler;
      addTearDown(() => WorkmanagerPlatform.instance = previous);
      await expectLater(
        BackgroundSyncService.schedulePeriodicSync(
          intervalMinutes: 60,
          scheduler: (interval) => mobile.scheduleWorkmanagerTask(
            uniqueName: kBackgroundSyncTaskName,
            taskId: kBackgroundSyncTaskId,
            intervalMinutes: interval,
            targetPlatform: TargetPlatform.iOS,
          ),
        ),
        throwsStateError,
      );
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool('background_sync_enabled'), isTrue);
      expect(preferences.getInt('background_sync_interval_minutes'), 30);
      expect(scheduler.cancelled, isEmpty);
      expect(scheduler.interval, const Duration(minutes: 30));
      expect(
        await scheduler.isScheduledByUniqueName(kBackgroundSyncTaskId),
        isTrue,
      );
    },
  );

  test('retained Apple wake accepts a desired interval for its next reschedule', () async {
    final previous = WorkmanagerPlatform.instance;
    final scheduler = _Scheduler();
    WorkmanagerPlatform.instance = scheduler;
    addTearDown(() => WorkmanagerPlatform.instance = previous);
    Future<void> schedule(int interval) => mobile.scheduleWorkmanagerTask(
      uniqueName: kBackgroundSyncTaskName,
      taskId: kBackgroundSyncTaskId,
      intervalMinutes: interval,
      targetPlatform: TargetPlatform.iOS,
    );
    await BackgroundSyncService.schedulePeriodicSync(
      intervalMinutes: 30,
      scheduler: schedule,
    );
    // The Apple plugin can swallow a replacement-submit failure while its old
    // request remains pending. A boolean pending check cannot distinguish it.
    scheduler.retainPreviousRequest = true;
    await BackgroundSyncService.schedulePeriodicSync(
      intervalMinutes: 60,
      scheduler: schedule,
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('background_sync_enabled'), isTrue);
    expect(preferences.getInt('background_sync_interval_minutes'), 60);
    expect(scheduler.interval, const Duration(minutes: 30));
    expect(
      await scheduler.isScheduledByUniqueName(kBackgroundSyncTaskId),
      isTrue,
    );
    expect(scheduler.cancelled, isEmpty);
    // AppDelegate reads this desired interval at the next wake. The service
    // does not claim that the retained request's start time changed to 60 min.
  });

  test('rejected first registration cannot persist enabled state or a new interval', () async {
    SharedPreferences.setMockInitialValues({
      'background_sync_enabled': false,
      'background_sync_interval_minutes': 15,
    });
    final previous = WorkmanagerPlatform.instance;
    WorkmanagerPlatform.instance = _Scheduler()..accepted = false;
    addTearDown(() => WorkmanagerPlatform.instance = previous);
    await expectLater(
      BackgroundSyncService.schedulePeriodicSync(
        intervalMinutes: 30,
        scheduler: (interval) => mobile.scheduleWorkmanagerTask(
          uniqueName: kBackgroundSyncTaskName,
          taskId: kBackgroundSyncTaskId,
          intervalMinutes: interval,
          targetPlatform: TargetPlatform.iOS,
        ),
      ),
      throwsStateError,
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('background_sync_enabled'), isFalse);
    expect(preferences.getInt('background_sync_interval_minutes'), 15);
  });

  test(
    'enabled preferences follow accepted scheduling and confirmed cancellation',
    () async {
      final previous = WorkmanagerPlatform.instance;
      final scheduler = _Scheduler();
      WorkmanagerPlatform.instance = scheduler;
      addTearDown(() => WorkmanagerPlatform.instance = previous);
      await BackgroundSyncService.schedulePeriodicSync(
        intervalMinutes: 30,
        scheduler: (interval) => mobile.scheduleWorkmanagerTask(
          uniqueName: kBackgroundSyncTaskName,
          taskId: kBackgroundSyncTaskId,
          intervalMinutes: interval,
          targetPlatform: TargetPlatform.iOS,
        ),
      );
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool('background_sync_enabled'), isTrue);
      expect(preferences.getInt('background_sync_interval_minutes'), 30);
      expect(
        await scheduler.isScheduledByUniqueName(kBackgroundSyncTaskId),
        isTrue,
      );
      await expectLater(
        BackgroundSyncService.cancelSync(
          canceller: () async {
            throw StateError('Native cancellation failed');
          },
        ),
        throwsStateError,
      );
      expect(preferences.getBool('background_sync_enabled'), isTrue);
      expect(
        await scheduler.isScheduledByUniqueName(kBackgroundSyncTaskId),
        isTrue,
      );
      await BackgroundSyncService.cancelSync(
        canceller: () => mobile.cancelWorkmanagerTask(
          kBackgroundSyncTaskName,
          targetPlatform: TargetPlatform.iOS,
        ),
      );
      expect(preferences.getBool('background_sync_enabled'), isFalse);
      expect(preferences.getInt('background_sync_interval_minutes'), 30);
      expect(
        await scheduler.isScheduledByUniqueName(kBackgroundSyncTaskId),
        isFalse,
      );
    },
  );

  test('actual Workmanager engine channel reaches the database and secure store', () async {
    final root = await Directory.systemTemp.createTemp('background-dispatch-');
    addTearDown(() => root.delete(recursive: true));
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(root.path);
    addTearDown(() => PathProviderPlatform.instance = previousPaths);
    final methods = <String>[];
    const secureChannel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureChannel, (call) async {
      methods.add(call.method);
      expect((call.arguments as Map)['key'], 'ftp_credentials');
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(secureChannel, null));
    final db = SyncDatabase();
    await db.insertPair(
      SyncPairsCompanion.insert(
        name: 'Missing saved credentials',
        localPath: root.path,
        remotePath: '/docs',
        provider: 'ftp',
      ),
    );
    await db.close();
    mobile.callbackDispatcher();
    final response = Completer<ByteData?>();
    // Emulate the native Workmanager engine's Pigeon message, without replacing
    // the production dispatcher, database, credential builder or task service.
    // ignore: deprecated_member_use
    await messenger.handlePlatformMessage(
      'dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerFlutterApi.executeTask',
      WorkmanagerFlutterApi.pigeonChannelCodec.encodeMessage([
        kBackgroundSyncTaskId,
        null,
      ]),
      response.complete,
    );
    final decoded = WorkmanagerFlutterApi.pigeonChannelCodec.decodeMessage(
      await response.future,
    );
    expect(decoded, [false]);
    expect(methods, ['read']);
    WorkmanagerFlutterApi.setUp(null);
  });

  test(
    'restores FTPS from the real config map with exact account/endpoint/TLS',
    () async {
      final secure = _TrackedSecureStorage();
      await FTPConfigService(
        configPath: '',
        secureStorage: secure,
      ).saveCredentials(_ftpCredentials);
      secure.mutations.clear();
      final network = _FtpNetwork();
      final client = await mobile.buildClientForProvider(
        'ftp',
        secureStorage: secure,
        ftpClientFactory: _ftpFactory(
          network,
          inspect: (host, port, user, pass, security) {
            expect(host, '2001:db8::4');
            expect(port, 2121);
            expect(user, 'worker@team');
            expect(pass, _ftpCredentials['password']);
            expect(security, SecurityType.ftps);
          },
        ),
      );
      expect(client, isA<FTPClientAdapter>());
      expect(client.isAuthenticated, isTrue);
      expect(client.userId, 'worker@team');
      expect(client.bucketId, '2001:db8::4');
      expect(network.connects, 1);
      expect(network.listings, 0);
      expect(secure.reads, ['ftp_credentials']);
      await client.logout();
      expect(client.isAuthenticated, isFalse);
      expect(network.disconnects, 1);
      expect(secure.mutations, isEmpty);
      expect(await secure.readMap('ftp_credentials'), _ftpCredentials);
    },
  );

  test(
    'FTP authentication failure and retry never erase foreground credentials',
    () async {
      final secure = _TrackedSecureStorage()
        ..seed('ftp_credentials', _ftpCredentials);
      final network = _FtpNetwork()..accepted = false;
      await expectLater(
        mobile.buildClientForProvider(
          'ftp',
          secureStorage: secure,
          ftpClientFactory: _ftpFactory(network),
        ),
        throwsA(isA<mobile.BackgroundSyncClientException>()),
      );
      expect(network.disconnects, 1);
      expect(secure.mutations, isEmpty);
      network.accepted = true;
      final client = await mobile.buildClientForProvider(
        'ftp',
        secureStorage: secure,
        ftpClientFactory: _ftpFactory(network),
      );
      await client.logout();
      expect(secure.mutations, isEmpty);
      expect(await secure.readMap('ftp_credentials'), _ftpCredentials);
    },
  );

  test(
    'plaintext preferences cannot supply missing secure credentials',
    () async {
      SharedPreferences.setMockInitialValues({
        'ftp_host': 'old.example.test',
        'ftp_username': 'plaintext',
        'ftp_password': 'not-a-secure-credential',
        '_ss_ftp_credentials': jsonEncode(_ftpCredentials),
        'webdav_url': _webDavCredentials['host']!,
        'webdav_username': 'plaintext',
        'webdav_password': 'plaintext',
      });
      final secure = _TrackedSecureStorage();
      for (final provider in ['ftp', 'webdav']) {
        await expectLater(
          mobile.buildClientForProvider(provider, secureStorage: secure),
          throwsA(isA<mobile.BackgroundSyncClientException>()),
        );
      }
      expect(secure.mutations, isEmpty);
    },
  );

  test(
    'unavailable secure store and unsupported provider are explicit errors',
    () async {
      final secure = _TrackedSecureStorage()..unavailable = true;
      await expectLater(
        mobile.buildClientForProvider('ftp', secureStorage: secure),
        throwsA(
          isA<mobile.BackgroundSyncClientException>().having(
            (e) => e.message,
            'message',
            contains('secure credential store'),
          ),
        ),
      );
      await expectLater(
        mobile.buildClientForProvider('s3', secureStorage: secure),
        throwsA(
          isA<mobile.BackgroundSyncClientException>().having(
            (e) => e.message,
            'message',
            contains('unavailable for "s3"'),
          ),
        ),
      );
      expect(secure.reads, ['ftp_credentials']);
      expect(secure.mutations, isEmpty);
    },
  );

  for (final bad in [
    {..._ftpCredentials}..remove('username'),
    {..._ftpCredentials}..remove('password'),
    {..._ftpCredentials}..remove('port'),
    {..._ftpCredentials}..remove('useTLS'),
    {..._ftpCredentials, 'port': 'invalid'},
    {..._ftpCredentials, 'port': '65536'},
    {..._ftpCredentials, 'useTLS': 'invalid'},
  ]) {
    test(
      'incomplete/malformed FTP credentials never downgrade or connect: ${bad.keys}',
      () async {
        final secure = _TrackedSecureStorage()..seed('ftp_credentials', bad);
        final network = _FtpNetwork();
        await expectLater(
          mobile.buildClientForProvider(
            'ftp',
            secureStorage: secure,
            ftpClientFactory: _ftpFactory(network),
          ),
          throwsA(isA<mobile.BackgroundSyncClientException>()),
        );
        expect(network.connects, 0);
        expect(secure.mutations, isEmpty);
      },
    );
  }

  test('an FTPS pair cannot restore a stored plain FTP connection', () async {
    final secure = _TrackedSecureStorage()
      ..seed('ftp_credentials', {..._ftpCredentials, 'useTLS': 'false'});
    final network = _FtpNetwork();
    await expectLater(
      mobile.buildClientForProvider(
        'ftps',
        secureStorage: secure,
        ftpClientFactory: _ftpFactory(network),
      ),
      throwsA(isA<mobile.BackgroundSyncClientException>()),
    );
    expect(network.connects, 0);
  });

  test('WebDAV authenticates the exact secure account and saved root before returning', () async {
    final secure = _TrackedSecureStorage();
    await WebDavConfigService(
      configPath: '',
      secureStorage: secure,
    ).saveCredentials(_webDavCredentials);
    secure.mutations.clear();
    final network = _DavNetwork((request) async {
      expect(
        request.uri.toString(),
        'https://dav.example.test:8443/dav/accounts/team/docs%20%231',
      );
      expect(request.method, 'PROPFIND');
      expect(request.headers['depth'], '0');
      expect(request.followRedirects, isFalse);
      if (request.headers['authorization'] == null) {
        return dio.ResponseBody.fromString(
          '',
          401,
          headers: {
            'www-authenticate': ['Basic realm="fixture"'],
          },
        );
      }
      expect(
        request.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('${_webDavCredentials['username']}:${_webDavCredentials['password']}'))}',
      );
      return _davSuccess();
    });
    final client = await mobile.buildClientForProvider(
      'webdav',
      secureStorage: secure,
      remotePath: '/docs #1',
      webDavClientFactory: _davFactory(
        network,
        inspect: (url, user, password) {
          expect(url, _webDavCredentials['host']);
          expect(user, _webDavCredentials['username']);
          expect(password, _webDavCredentials['password']);
        },
      ),
    );
    expect(client, isA<WebDavClientAdapter>());
    expect(client.isAuthenticated, isTrue);
    expect(client.bucketId, _webDavCredentials['host']);
    expect(client.userId, _webDavCredentials['username']);
    expect(network.requests, hasLength(2));
    await client.logout();
    expect(network.closed, isTrue);
    expect(secure.mutations, isEmpty);
    expect(await secure.readMap('webdav_credentials'), _webDavCredentials);
  });

  for (final status in [401, 302, 500]) {
    test(
      'WebDAV $status fails without redirecting or changing stored secrets',
      () async {
        final secure = _TrackedSecureStorage()
          ..seed('webdav_credentials', _webDavCredentials);
        final network = _DavNetwork(
          (request) async => dio.ResponseBody.fromString(
            '',
            status,
            headers: {
              'www-authenticate': ['Basic realm="fixture"'],
              'location': ['https://other.example.test/'],
            },
          ),
        );
        await expectLater(
          mobile.buildClientForProvider(
            'webdav',
            secureStorage: secure,
            webDavClientFactory: _davFactory(network),
          ),
          throwsA(isA<mobile.BackgroundSyncClientException>()),
        );
        expect(network.requests.length, lessThanOrEqualTo(2));
        expect(
          network.requests.every(
            (request) => request.uri.host == 'dav.example.test',
          ),
          isTrue,
        );
        expect(network.closed, isTrue);
        expect(secure.mutations, isEmpty);
        expect(await secure.readMap('webdav_credentials'), _webDavCredentials);
      },
    );
  }

  test(
    'WebDAV authentication metadata has a real bounded response limit',
    () async {
      final secure = _TrackedSecureStorage()
        ..seed('webdav_credentials', _webDavCredentials);
      final network = _DavNetwork(
        (request) async =>
            dio.ResponseBody.fromBytes(Uint8List(256 * 1024 + 1), 207),
      );
      await expectLater(
        mobile.buildClientForProvider(
          'webdav',
          secureStorage: secure,
          webDavClientFactory: _davFactory(network),
        ),
        throwsA(isA<mobile.BackgroundSyncClientException>()),
      );
      expect(network.closed, isTrue);
      expect(secure.mutations, isEmpty);
    },
  );

  for (final change in [null, 'host', 'port', 'username']) {
    test(
      'real restored FTP sync ${change == null ? 'runs and closes privately' : 'rejects changed $change before listing'}',
      () async {
        final root = await Directory.systemTemp.createTemp('background-bound-');
        addTearDown(() => root.delete(recursive: true));
        final local = await Directory(p.join(root.path, 'local')).create();
        final secure = _TrackedSecureStorage()
          ..seed('ftp_credentials', _ftpCredentials);
        final foreground = await mobile.buildClientForProvider(
          'ftp',
          secureStorage: secure,
          ftpClientFactory: _ftpFactory(_FtpNetwork()),
        );
        final db = SyncDatabase.forTesting(NativeDatabase.memory());
        await _pair(db, local.path, foreground);
        await foreground.logout();
        if (change != null) {
          secure.seed('ftp_credentials', {
            ..._ftpCredentials,
            change: change == 'port' ? '2122' : 'different.example.test',
          });
        }
        final expectedSaved = secure.values['ftp_credentials'];
        final network = _FtpNetwork();
        final notices = _Notices();
        final success = await BackgroundSyncService.executeBackgroundTask(
          databaseFactory: () => db,
          clientFactory: (provider) => mobile.buildClientForProvider(
            provider,
            secureStorage: secure,
            ftpClientFactory: _ftpFactory(network),
          ),
          journalFactory: () => createBackgroundTransferJournalRun(
            rootPath: p.join(root.path, 'runs'),
          ),
          notificationSender: notices.send,
        );
        expect(success, change == null);
        expect(network.connects, 1);
        if (change == null) {
          expect(network.listings, greaterThan(0));
          expect(network.opened, contains('/docs'));
        } else {
          expect(network.listings, 0);
        }
        expect(network.disconnects, 1);
        expect(secure.mutations, isEmpty);
        expect(secure.values['ftp_credentials'], expectedSaved);
        if (change == null) {
          expect(notices.bodies, isEmpty);
        } else {
          expect(notices.bodies.single, contains('saved for this sync pair'));
        }
      },
    );
  }

  for (final failure in ['null', 'unauthenticated', 'missing', 'unsupported']) {
    test(
      'worker reports $failure client as failure rather than a successful skip',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'background-unavailable-',
        );
        addTearDown(() => root.delete(recursive: true));
        final local = await Directory(p.join(root.path, 'local')).create();
        final db = SyncDatabase.forTesting(NativeDatabase.memory());
        await _pair(db, local.path, WorkflowFakeClient());
        final notices = _Notices();
        final success = await BackgroundSyncService.executeBackgroundTask(
          databaseFactory: () => db,
          clientFactory: (_) async => switch (failure) {
            'null' => null,
            'unauthenticated' => WorkflowFakeClient()..current = false,
            'missing' => await mobile.buildClientForProvider(
              'ftp',
              secureStorage: _TrackedSecureStorage(),
            ),
            _ => await mobile.buildClientForProvider(
              's3',
              secureStorage: _TrackedSecureStorage(),
            ),
          },
          journalFactory: () => createBackgroundTransferJournalRun(
            rootPath: p.join(root.path, 'runs'),
          ),
          notificationSender: notices.send,
        );
        expect(success, isFalse);
        expect(notices.bodies.single, contains('1 error'));
        expect(notices.bodies.single, contains('Saved account'));
        expect(await local.list().toList(), isEmpty);
      },
    );
  }
}
