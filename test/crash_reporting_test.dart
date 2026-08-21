// test/crash_reporting_test.dart
//
// Unit tests for CrashReportingService, CrashReport model, Breadcrumb,
// PlatformInfo, LocalBackend, SentryBackend placeholder, and CrashLog.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/crash_reporting_service.dart';
import 'package:crisp_cloud/services/log_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// A simple in-memory backend for testing that captures sent reports.
class _CapturingBackend extends CrashReportingBackend {
  final List<CrashReport> sent = [];
  bool initialized = false;

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> send(CrashReport report) async {
    sent.add(report);
  }

  @override
  Future<List<CrashReport>> getRecentReports(int count) async {
    return sent.reversed.take(count).toList();
  }

  @override
  Future<String> exportReports() async {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(sent.map((r) => r.toJson()).toList());
  }

  @override
  Future<void> clearReports() async {
    sent.clear();
  }
}

// ---------------------------------------------------------------------------
// Breadcrumb tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Privacy sanitization', () {
    test('redacts credentials and local paths recursively', () {
      final sanitized = sanitizeCrashData({
        'accessToken': 'top-secret',
        'filePath': '/Users/alice/private/report.pdf',
        'nested': {
          'password': 'hunter2',
          'status': 'failed',
        },
      }) as Map<String, dynamic>;

      expect(sanitized['accessToken'], '<redacted>');
      expect(sanitized['filePath'], '<redacted-path>');
      expect((sanitized['nested'] as Map)['password'], '<redacted>');
      expect((sanitized['nested'] as Map)['status'], 'failed');
    });

    test('removes query-string secrets from messages', () {
      final sanitized = sanitizeCrashData(
        'GET https://example.test/a?token=abc123&mode=view',
      ) as String;
      expect(sanitized, contains('token=<redacted>'));
      expect(sanitized, isNot(contains('abc123')));
    });
  });

  group('Breadcrumb', () {
    test('toJson includes required fields', () {
      final crumb = Breadcrumb(
        timestamp: DateTime(2026, 1, 15, 10, 30),
        message: 'User opened file browser',
        category: 'navigation',
      );
      final json = crumb.toJson();
      expect(json['timestamp'], '2026-01-15T10:30:00.000');
      expect(json['message'], 'User opened file browser');
      expect(json['category'], 'navigation');
      expect(json.containsKey('data'), false);
    });

    test('toJson includes data when present', () {
      final crumb = Breadcrumb(
        timestamp: DateTime(2026, 3, 1),
        message: 'Upload started',
        category: 'transfer',
        data: {'file': 'report.pdf', 'size': 1024},
      );
      final json = crumb.toJson();
      expect(json['data'], {'file': 'report.pdf', 'size': 1024});
    });

    test('fromJson round-trip preserves all fields', () {
      final original = Breadcrumb(
        timestamp: DateTime(2026, 6, 15, 14, 30, 45),
        message: 'Sync completed',
        category: 'sync',
        data: {'provider': 'dropbox', 'files': 42},
      );
      final restored = Breadcrumb.fromJson(original.toJson());
      expect(restored.message, original.message);
      expect(restored.category, original.category);
      expect(restored.data, original.data);
      expect(restored.timestamp, original.timestamp);
    });

    test('fromJson handles missing optional fields', () {
      final crumb = Breadcrumb.fromJson({
        'timestamp': '2026-01-01T00:00:00.000',
        'message': 'hello',
        'category': 'nav',
      });
      expect(crumb.data, null);
    });

    test('fromJson uses defaults for missing required fields', () {
      final crumb = Breadcrumb.fromJson({
        'timestamp': '2026-01-01T00:00:00.000',
      });
      expect(crumb.message, '');
      expect(crumb.category, 'default');
    });
  });

  // ---------------------------------------------------------------------------
  // PlatformInfo tests
  // ---------------------------------------------------------------------------

  group('PlatformInfo', () {
    test('toJson includes all fields', () {
      final info = PlatformInfo(
        os: 'linux',
        osVersion: 'Ubuntu 22.04',
        locale: 'en_US',
        isWeb: false,
        isDebug: true,
        appVersion: '1.2.3',
      );
      final json = info.toJson();
      expect(json['os'], 'linux');
      expect(json['osVersion'], 'Ubuntu 22.04');
      expect(json['locale'], 'en_US');
      expect(json['isWeb'], false);
      expect(json['isDebug'], true);
      expect(json['appVersion'], '1.2.3');
    });

    test('toJson omits appVersion when null', () {
      final info = PlatformInfo(
        os: 'android',
        osVersion: '14',
        locale: 'de_DE',
        isWeb: false,
        isDebug: false,
      );
      expect(info.toJson().containsKey('appVersion'), false);
    });

    test('fromJson round-trip preserves all fields', () {
      final original = PlatformInfo(
        os: 'macos',
        osVersion: 'Sonoma 14.4',
        locale: 'fr_FR',
        isWeb: false,
        isDebug: false,
        appVersion: '0.9.1',
      );
      final restored = PlatformInfo.fromJson(original.toJson());
      expect(restored.os, 'macos');
      expect(restored.osVersion, 'Sonoma 14.4');
      expect(restored.locale, 'fr_FR');
      expect(restored.isWeb, false);
      expect(restored.isDebug, false);
      expect(restored.appVersion, '0.9.1');
    });

    test('fromJson handles empty/missing map gracefully', () {
      final info = PlatformInfo.fromJson({});
      expect(info.os, 'unknown');
      expect(info.osVersion, '');
      expect(info.locale, '');
      expect(info.isWeb, false);
      expect(info.isDebug, false);
      expect(info.appVersion, null);
    });

    test('collect() does not throw', () {
      expect(() => PlatformInfo.collect(appVersion: '1.0.0'), returnsNormally);
    });

    test('collect() returns non-empty os string', () {
      final info = PlatformInfo.collect();
      expect(info.os, isNotEmpty);
    });

    test('collect() with appVersion includes it', () {
      final info = PlatformInfo.collect(appVersion: '2.0.0');
      expect(info.appVersion, '2.0.0');
    });
  });

  // ---------------------------------------------------------------------------
  // CrashReport model tests
  // ---------------------------------------------------------------------------

  group('CrashReport', () {
    CrashReport _makeReport({
      String id = 'cr_test_001',
      String errorMessage = 'Something went wrong',
      String? errorType = 'StateError',
      String? stackTrace = '#0 main (main.dart:1)',
      List<Breadcrumb>? breadcrumbs,
      Map<String, dynamic>? context,
      String? userId,
    }) {
      return CrashReport(
        id: id,
        timestamp: DateTime(2026, 5, 20, 9, 0),
        errorMessage: errorMessage,
        errorType: errorType,
        stackTrace: stackTrace,
        breadcrumbs: breadcrumbs ??
            [
              Breadcrumb(
                timestamp: DateTime(2026, 5, 20, 8, 59),
                message: 'Page loaded',
                category: 'navigation',
              )
            ],
        platformInfo: PlatformInfo(
          os: 'linux',
          osVersion: '6.8',
          locale: 'en_US',
          isWeb: false,
          isDebug: true,
        ),
        context: context,
        userId: userId,
      );
    }

    test('toJson includes all required fields', () {
      final report = _makeReport();
      final json = report.toJson();
      expect(json['id'], 'cr_test_001');
      expect(json['errorMessage'], 'Something went wrong');
      expect(json['errorType'], 'StateError');
      expect(json['stackTrace'], '#0 main (main.dart:1)');
      expect(json['breadcrumbs'], isA<List>());
      expect(json['platformInfo'], isA<Map>());
    });

    test('toJson omits null optional fields', () {
      final report = _makeReport(
        errorType: null,
        stackTrace: null,
        context: null,
        userId: null,
      );
      final json = report.toJson();
      expect(json.containsKey('errorType'), false);
      expect(json.containsKey('stackTrace'), false);
      expect(json.containsKey('context'), false);
      expect(json.containsKey('userId'), false);
    });

    test('toJson includes context when present', () {
      final report = _makeReport(context: {'path': '/docs', 'provider': 's3'});
      final json = report.toJson();
      expect(json['context'], {'path': '/docs', 'provider': 's3'});
    });

    test('toJson includes userId when set', () {
      final report = _makeReport(userId: 'user_abc123');
      final json = report.toJson();
      expect(json['userId'], 'user_abc123');
    });

    test('fromJson round-trip preserves all fields', () {
      final original = _makeReport(
        id: 'cr_roundtrip',
        errorMessage: 'Connection timeout',
        errorType: 'SocketException',
        stackTrace: '#0 connect\n#1 main',
        context: {'retries': 3},
        userId: 'u_42',
      );
      final json = original.toJson();
      final restored = CrashReport.fromJson(json);

      expect(restored.id, 'cr_roundtrip');
      expect(restored.errorMessage, 'Connection timeout');
      expect(restored.errorType, 'SocketException');
      expect(restored.stackTrace, '#0 connect\n#1 main');
      expect(restored.context, {'retries': 3});
      expect(restored.userId, 'u_42');
    });

    test('fromJson deserializes breadcrumbs list', () {
      final original = _makeReport(breadcrumbs: [
        Breadcrumb(
          timestamp: DateTime(2026, 1, 1),
          message: 'Step A',
          category: 'test',
        ),
        Breadcrumb(
          timestamp: DateTime(2026, 1, 2),
          message: 'Step B',
          category: 'test',
          data: {'key': 'value'},
        ),
      ]);
      final restored = CrashReport.fromJson(original.toJson());
      expect(restored.breadcrumbs.length, 2);
      expect(restored.breadcrumbs[0].message, 'Step A');
      expect(restored.breadcrumbs[1].message, 'Step B');
      expect(restored.breadcrumbs[1].data, {'key': 'value'});
    });

    test('fromJson handles missing breadcrumbs field', () {
      final json = {
        'id': 'x',
        'timestamp': '2026-01-01T00:00:00.000',
        'errorMessage': 'oops',
        'platformInfo': {},
      };
      final report = CrashReport.fromJson(json);
      expect(report.breadcrumbs, isEmpty);
    });

    test('fromJson handles malformed breadcrumb entries', () {
      final json = {
        'id': 'x',
        'timestamp': '2026-01-01T00:00:00.000',
        'errorMessage': 'oops',
        'breadcrumbs': [
          {
            'timestamp': '2026-01-01T00:00:00.000',
            'message': 'ok',
            'category': 'nav'
          },
          'not a map', // should be skipped
          42, // should be skipped
        ],
        'platformInfo': {},
      };
      final report = CrashReport.fromJson(json);
      expect(report.breadcrumbs.length, 1);
    });

    test('JSON serialization is valid JSON', () {
      final report = _makeReport();
      final jsonStr = jsonEncode(report.toJson());
      expect(() => jsonDecode(jsonStr), returnsNormally);
    });
  });

  // ---------------------------------------------------------------------------
  // Breadcrumb ring buffer tests
  // ---------------------------------------------------------------------------

  group('Breadcrumb ring buffer', () {
    late CrashReportingService service;
    late _CapturingBackend backend;

    setUp(() {
      backend = _CapturingBackend();
      service = CrashReportingService(backend: backend);
    });

    test('starts empty', () {
      expect(service.breadcrumbs, isEmpty);
    });

    test('adds single breadcrumb', () {
      service.reportBreadcrumb('Hello', 'test');
      expect(service.breadcrumbs.length, 1);
      expect(service.breadcrumbs.first.message, 'Hello');
      expect(service.breadcrumbs.first.category, 'test');
    });

    test('adds multiple breadcrumbs in order', () {
      service.reportBreadcrumb('A', 'nav');
      service.reportBreadcrumb('B', 'ui');
      service.reportBreadcrumb('C', 'network');
      final crumbs = service.breadcrumbs;
      expect(crumbs.length, 3);
      expect(crumbs[0].message, 'A');
      expect(crumbs[1].message, 'B');
      expect(crumbs[2].message, 'C');
    });

    test('ring buffer caps at 50 when 60 are added', () {
      for (int i = 0; i < 60; i++) {
        service.reportBreadcrumb('Crumb $i', 'test');
      }
      expect(service.breadcrumbs.length, 50);
    });

    test('ring buffer keeps the most recent 50 when 60 are added', () {
      for (int i = 0; i < 60; i++) {
        service.reportBreadcrumb('Crumb $i', 'test');
      }
      final crumbs = service.breadcrumbs;
      // The oldest kept should be crumb 10 (index 10 in 0..59)
      expect(crumbs.first.message, 'Crumb 10');
      expect(crumbs.last.message, 'Crumb 59');
    });

    test('ring buffer keeps newest after overflow', () {
      for (int i = 0; i < 100; i++) {
        service.reportBreadcrumb('Crumb $i', 'test');
      }
      final crumbs = service.breadcrumbs;
      expect(crumbs.length, 50);
      expect(crumbs.last.message, 'Crumb 99');
    });

    test('breadcrumb data is stored', () {
      service.reportBreadcrumb('Upload', 'transfer', data: {'file': 'a.pdf'});
      expect(service.breadcrumbs.first.data, {'file': 'a.pdf'});
    });
  });

  // ---------------------------------------------------------------------------
  // CrashReportingService — enabled/disabled logic
  // ---------------------------------------------------------------------------

  group('CrashReportingService opt-in', () {
    late _CapturingBackend backend;
    late CrashReportingService service;

    setUp(() {
      backend = _CapturingBackend();
      service = CrashReportingService(backend: backend);
    });

    test('service starts disabled', () {
      expect(service.isEnabled, false);
    });

    test('reportError does nothing when disabled', () async {
      expect(service.isEnabled, false);
      await service.reportError(Exception('boom'), null);
      expect(backend.sent, isEmpty);
    });

    test('enable() sets isEnabled to true', () async {
      await service.enable();
      expect(service.isEnabled, true);
    });

    test('disable() sets isEnabled to false', () async {
      await service.enable();
      await service.disable();
      expect(service.isEnabled, false);
    });

    test('reportError sends when enabled', () async {
      await service.enable();
      await service.reportError(Exception('test error'), null);
      expect(backend.sent.length, 1);
      expect(backend.sent.first.errorMessage, contains('test error'));
    });

    test('reportError does not send after disable()', () async {
      await service.enable();
      await service.disable();
      await service.reportError(Exception('should not send'), null);
      expect(backend.sent, isEmpty);
    });

    test('multiple enables do not duplicate reports', () async {
      await service.enable();
      await service.enable();
      await service.reportError(Exception('once'), null);
      expect(backend.sent.length, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // CrashReportingService — error reporting
  // ---------------------------------------------------------------------------

  group('CrashReportingService.reportError', () {
    late _CapturingBackend backend;
    late CrashReportingService service;

    setUp(() async {
      backend = _CapturingBackend();
      service = CrashReportingService(backend: backend, appVersion: '1.0.0');
      await service.enable();
    });

    test('report includes error message', () async {
      await service.reportError(StateError('bad state'), null);
      expect(backend.sent.first.errorMessage, contains('bad state'));
    });

    test('report includes error type', () async {
      await service.reportError(StateError('x'), null);
      expect(backend.sent.first.errorType, 'StateError');
    });

    test('report includes stack trace when provided', () async {
      final st = StackTrace.current;
      await service.reportError(Exception('x'), st);
      expect(backend.sent.first.stackTrace, isNotNull);
      expect(backend.sent.first.stackTrace, isNotEmpty);
    });

    test('report stackTrace is null when not provided', () async {
      await service.reportError(Exception('x'), null);
      expect(backend.sent.first.stackTrace, null);
    });

    test('report includes context', () async {
      await service.reportError(
        Exception('ctx'),
        null,
        context: {'path': '/docs', 'provider': 'dropbox'},
      );
      expect(backend.sent.first.context,
          {'path': '<redacted-path>', 'provider': 'dropbox'});
    });

    test('report without context has null context', () async {
      await service.reportError(Exception('no ctx'), null);
      expect(backend.sent.first.context, null);
    });

    test('report includes breadcrumbs snapshot', () async {
      service.reportBreadcrumb('Step 1', 'nav');
      service.reportBreadcrumb('Step 2', 'ui');
      await service.reportError(Exception('oops'), null);
      final crumbs = backend.sent.first.breadcrumbs;
      expect(crumbs.length, 2);
      expect(crumbs[0].message, 'Step 1');
      expect(crumbs[1].message, 'Step 2');
    });

    test('report includes platform info', () async {
      await service.reportError(Exception('pi'), null);
      final info = backend.sent.first.platformInfo;
      expect(info.os, isNotEmpty);
    });

    test('report includes appVersion', () async {
      await service.reportError(Exception('ver'), null);
      expect(backend.sent.first.platformInfo.appVersion, '1.0.0');
    });

    test('report has unique non-empty id', () async {
      await service.reportError(Exception('a'), null);
      await service.reportError(Exception('b'), null);
      final id1 = backend.sent[0].id;
      final id2 = backend.sent[1].id;
      expect(id1, isNotEmpty);
      expect(id2, isNotEmpty);
      expect(id1, isNot(equals(id2)));
    });

    test('report has timestamp close to now', () async {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      await service.reportError(Exception('ts'), null);
      final after = DateTime.now().add(const Duration(seconds: 1));
      expect(backend.sent.first.timestamp.isAfter(before), true);
      expect(backend.sent.first.timestamp.isBefore(after), true);
    });
  });

  // ---------------------------------------------------------------------------
  // User set/clear tests
  // ---------------------------------------------------------------------------

  group('CrashReportingService user context', () {
    late _CapturingBackend backend;
    late CrashReportingService service;

    setUp(() async {
      backend = _CapturingBackend();
      service = CrashReportingService(backend: backend);
      await service.enable();
    });

    test('userId is null by default', () async {
      await service.reportError(Exception('no user'), null);
      expect(backend.sent.first.userId, null);
    });

    test('setUser associates userId with reports', () async {
      service.setUser('user_12345');
      await service.reportError(Exception('with user'), null);
      expect(backend.sent.first.userId, 'user_12345');
    });

    test('clearUser removes userId from reports', () async {
      service.setUser('user_abc');
      service.clearUser();
      await service.reportError(Exception('cleared'), null);
      expect(backend.sent.first.userId, null);
    });

    test('setUser replaces previous userId', () async {
      service.setUser('user_old');
      service.setUser('user_new');
      await service.reportError(Exception('replaced'), null);
      expect(backend.sent.first.userId, 'user_new');
    });
  });

  // ---------------------------------------------------------------------------
  // LocalBackend tests
  // ---------------------------------------------------------------------------

  group('LocalBackend (file I/O)', () {
    late Directory tempDir;
    late LocalBackend backend;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('crash_test_');
      backend = LocalBackend();
      backend
          .setFilePathForTesting(p.join(tempDir.path, 'crash_reports.jsonl'));
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    CrashReport _makeSimpleReport(String msg) => CrashReport(
          id: 'cr_${msg.hashCode}',
          timestamp: DateTime(2026, 1, 1),
          errorMessage: msg,
          breadcrumbs: [],
          platformInfo: PlatformInfo(
            os: 'linux',
            osVersion: '6.8',
            locale: 'en_US',
            isWeb: false,
            isDebug: true,
          ),
        );

    test('send writes to file', () async {
      await backend.send(_makeSimpleReport('file write test'));
      final file = File(p.join(tempDir.path, 'crash_reports.jsonl'));
      expect(file.existsSync(), true);
      final lines = file.readAsLinesSync().where((l) => l.trim().isNotEmpty);
      expect(lines.length, 1);
    });

    test('send multiple reports appends to file', () async {
      await backend.send(_makeSimpleReport('report 1'));
      await backend.send(_makeSimpleReport('report 2'));
      await backend.send(_makeSimpleReport('report 3'));
      final file = File(p.join(tempDir.path, 'crash_reports.jsonl'));
      final lines =
          file.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
      expect(lines.length, 3);
    });

    test('getRecentReports returns newest first', () async {
      await backend.send(_makeSimpleReport('oldest'));
      await backend.send(_makeSimpleReport('middle'));
      await backend.send(_makeSimpleReport('newest'));
      final reports = await backend.getRecentReports(3);
      expect(reports.length, 3);
      expect(reports[0].errorMessage, 'newest');
      expect(reports[1].errorMessage, 'middle');
      expect(reports[2].errorMessage, 'oldest');
    });

    test('getRecentReports respects count limit', () async {
      for (int i = 0; i < 5; i++) {
        await backend.send(_makeSimpleReport('report $i'));
      }
      final reports = await backend.getRecentReports(2);
      expect(reports.length, 2);
    });

    test('getRecentReports returns empty list when no file', () async {
      final reports = await backend.getRecentReports(10);
      expect(reports, isEmpty);
    });

    test('exportReports returns valid JSON array', () async {
      await backend.send(_makeSimpleReport('export test 1'));
      await backend.send(_makeSimpleReport('export test 2'));
      final exported = await backend.exportReports();
      final decoded = jsonDecode(exported) as List;
      expect(decoded.length, 2);
      expect(decoded[0]['errorMessage'], 'export test 1');
      expect(decoded[1]['errorMessage'], 'export test 2');
    });

    test('exportReports returns empty array when no reports', () async {
      final exported = await backend.exportReports();
      expect(exported, '[]');
    });

    test('clearReports empties the file', () async {
      await backend.send(_makeSimpleReport('to be cleared'));
      await backend.clearReports();
      final reports = await backend.getRecentReports(10);
      expect(reports, isEmpty);
    });

    test('handles malformed JSONL lines in file', () async {
      final file = File(p.join(tempDir.path, 'crash_reports.jsonl'));
      final good = _makeSimpleReport('good report');
      await file.writeAsString(
        '${jsonEncode(good.toJson())}\n'
        'not valid json\n'
        '${jsonEncode(good.toJson())}\n',
      );
      final reports = await backend.getRecentReports(10);
      expect(reports.length, 2);
    });
  });

  // ---------------------------------------------------------------------------
  // CrashReportingService — getRecentReports / exportReports / clearReports
  // ---------------------------------------------------------------------------

  group('CrashReportingService storage API', () {
    late _CapturingBackend backend;
    late CrashReportingService service;

    setUp(() async {
      backend = _CapturingBackend();
      service = CrashReportingService(backend: backend);
      await service.enable();
    });

    test('getRecentReports returns reports from backend', () async {
      await service.reportError(Exception('e1'), null);
      await service.reportError(Exception('e2'), null);
      final reports = await service.getRecentReports(10);
      expect(reports.length, 2);
    });

    test('exportReports returns JSON string', () async {
      await service.reportError(Exception('export me'), null);
      final exported = await service.exportReports();
      expect(exported, isA<String>());
      final decoded = jsonDecode(exported) as List;
      expect(decoded.length, 1);
    });

    test('clearReports removes all reports', () async {
      await service.reportError(Exception('clear me'), null);
      await service.clearReports();
      final reports = await service.getRecentReports(10);
      expect(reports, isEmpty);
    });

    test('getRecentReports with default count', () async {
      for (int i = 0; i < 5; i++) {
        await service.reportError(Exception('e$i'), null);
      }
      final reports = await service.getRecentReports();
      expect(reports.length, 5);
    });
  });

  // ---------------------------------------------------------------------------
  // Multiple backend test
  // ---------------------------------------------------------------------------

  group('Multiple backends', () {
    test('setBackend switches active backend', () async {
      final backend1 = _CapturingBackend();
      final backend2 = _CapturingBackend();

      final service = CrashReportingService(backend: backend1);
      await service.enable();

      await service.reportError(Exception('goes to backend1'), null);
      expect(backend1.sent.length, 1);
      expect(backend2.sent.length, 0);

      await service.setBackend(backend2);

      await service.reportError(Exception('goes to backend2'), null);
      expect(backend1.sent.length, 1); // unchanged
      expect(backend2.sent.length, 1);
    });

    test('setBackend calls initialize() on the new backend', () async {
      final backend1 = _CapturingBackend();
      final backend2 = _CapturingBackend();

      final service = CrashReportingService(backend: backend1);
      await service.enable();

      expect(backend2.initialized, false);
      await service.setBackend(backend2);
      expect(backend2.initialized, true);
    });

    test('backend property returns active backend', () {
      final b = _CapturingBackend();
      final service = CrashReportingService(backend: b);
      expect(service.backend, same(b));
    });
  });

  // ---------------------------------------------------------------------------
  // SentryBackend placeholder test
  // ---------------------------------------------------------------------------

  group('SentryBackend placeholder', () {
    test('initialize does not throw', () async {
      final sentry =
          SentryBackend(dsn: 'https://example@o123.ingest.sentry.io/456');
      await expectLater(sentry.initialize(), completes);
    });

    test('send does not throw', () async {
      final sentry =
          SentryBackend(dsn: 'https://example@o123.ingest.sentry.io/456');
      final report = CrashReport(
        id: 'cr_sentry_test',
        timestamp: DateTime.now(),
        errorMessage: 'Sentry test',
        breadcrumbs: [],
        platformInfo: PlatformInfo(
          os: 'linux',
          osVersion: '',
          locale: '',
          isWeb: false,
          isDebug: true,
        ),
      );
      await expectLater(sentry.send(report), completes);
    });

    test('getRecentReports returns empty by default', () async {
      final sentry = SentryBackend(dsn: 'https://x@y.z/1');
      final reports = await sentry.getRecentReports(10);
      expect(reports, isEmpty);
    });

    test('SentryBackend accepts optional environment and release', () {
      final sentry = SentryBackend(
        dsn: 'https://x@y.z/1',
        environment: 'production',
        release: '1.2.3',
      );
      expect(sentry.dsn, isNotEmpty);
      expect(sentry.environment, 'production');
      expect(sentry.release, '1.2.3');
    });
  });

  // ---------------------------------------------------------------------------
  // CrashLog (LogService integration)
  // ---------------------------------------------------------------------------

  group('CrashLog integration', () {
    test('CrashLog.error dispatches to registered listener', () async {
      final captured = <LogEntry>[];
      LogConfigCrashHook.addErrorListener(captured.add);

      try {
        final log = CrashLog('TestLogger');
        log.error('Test error message', Exception('crash log test'),
            StackTrace.current);

        expect(captured.length, 1);
        expect(captured.first.level, LogLevel.error);
        expect(captured.first.logger, 'TestLogger');
        expect(captured.first.message, 'Test error message');
      } finally {
        LogConfigCrashHook.removeErrorListener(captured.add);
      }
    });

    test('CrashLog.info does not dispatch to error listener', () {
      final captured = <LogEntry>[];
      LogConfigCrashHook.addErrorListener(captured.add);

      try {
        final log = CrashLog('TestLogger');
        log.info('This is just info');
        expect(captured, isEmpty);
      } finally {
        LogConfigCrashHook.removeErrorListener(captured.add);
      }
    });

    test('CrashLog.warn does not dispatch to error listener', () {
      final captured = <LogEntry>[];
      LogConfigCrashHook.addErrorListener(captured.add);

      try {
        final log = CrashLog('TestLogger');
        log.warn('This is a warning');
        expect(captured, isEmpty);
      } finally {
        LogConfigCrashHook.removeErrorListener(captured.add);
      }
    });

    test('remove listener stops receiving events', () {
      final captured = <LogEntry>[];
      void listener(LogEntry e) => captured.add(e);

      LogConfigCrashHook.addErrorListener(listener);
      LogConfigCrashHook.removeErrorListener(listener);

      final log = CrashLog('TestLogger');
      log.error('Should not be captured');

      expect(captured, isEmpty);
    });

    test('CrashReportingService receives errors via CrashLog when enabled',
        () async {
      final backend = _CapturingBackend();
      final service = CrashReportingService(backend: backend);
      // Enable the service — this registers the service's internal hook
      // so that CrashLog dispatches lead to backend.send().
      await service.enable();

      try {
        final log = CrashLog('IntegrationTest');
        log.error('Integration error', Exception('from log'), null);

        // Give async operations a tick to complete
        await Future.delayed(Duration.zero);
        expect(backend.sent.length, 1);
        expect(backend.sent.first.errorMessage, contains('from log'));
      } finally {
        await service.disable();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Export format
  // ---------------------------------------------------------------------------

  group('Export format', () {
    test('exported JSON is valid and parseable', () async {
      final backend = _CapturingBackend();
      final service = CrashReportingService(backend: backend);
      await service.enable();

      service.reportBreadcrumb('Step 1', 'nav');
      await service.reportError(
        Exception('export format test'),
        null,
        context: {'key': 'value'},
      );

      final exported = await service.exportReports();
      expect(() => jsonDecode(exported), returnsNormally);

      final decoded = jsonDecode(exported) as List;
      expect(decoded.length, 1);

      final first = decoded.first as Map<String, dynamic>;
      expect(first.containsKey('id'), true);
      expect(first.containsKey('timestamp'), true);
      expect(first.containsKey('errorMessage'), true);
      expect(first.containsKey('platformInfo'), true);
      expect(first.containsKey('breadcrumbs'), true);
      expect(first['context'], {'key': 'value'});
    });

    test('exported JSON has indented formatting', () async {
      final backend = _CapturingBackend();
      final service = CrashReportingService(backend: backend);
      await service.enable();
      await service.reportError(Exception('indent test'), null);

      final exported = await service.exportReports();
      // Indented JSON contains newlines
      expect(exported, contains('\n'));
    });
  });
}
