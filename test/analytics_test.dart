// test/analytics_test.dart
//
// Unit tests for AnalyticsService, AnalyticsEvent, UsageSummary,
// EventCategory, LocalBackend, RemoteBackend placeholder, and providers.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/analytics_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// In-memory backend that captures all persisted events, for testing.
class _CapturingBackend extends AnalyticsBackend {
  final List<AnalyticsEvent> persisted = [];
  bool initialized = false;
  bool cleared = false;

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> persistEvents(List<AnalyticsEvent> events) async {
    persisted.addAll(events);
  }

  @override
  Future<List<AnalyticsEvent>> loadEvents() async => List.of(persisted);

  @override
  Future<void> clearEvents() async {
    persisted.clear();
    cleared = true;
  }
}

/// Build a fresh [AnalyticsService] with an in-memory backend.
/// Does NOT call [initialize()] — tests that need it call it explicitly.
AnalyticsService _makeService({_CapturingBackend? backend}) {
  return AnalyticsService(backend: backend ?? _CapturingBackend());
}

/// Build and initialize a fresh [AnalyticsService] that is already enabled.
Future<AnalyticsService> _enabledService({_CapturingBackend? backend}) async {
  SharedPreferences.setMockInitialValues({});
  final svc = _makeService(backend: backend);
  await svc.initialize();
  await svc.setEnabled(true);
  return svc;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Reset SharedPreferences mock before every test.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ---------------------------------------------------------------------------
  // EventCategory enum
  // ---------------------------------------------------------------------------

  group('EventCategory enum', () {
    test('has exactly the required 10 values', () {
      expect(EventCategory.values, hasLength(10));
    });

    test('contains all required categories', () {
      final names = EventCategory.values.map((e) => e.name).toSet();
      expect(names, containsAll([
        'navigation',
        'fileOperation',
        'sync',
        'connection',
        'ui',
        'encryption',
        'search',
        'transfer',
        'settings',
        'error',
      ]));
    });

    test('name property returns snake-case category name', () {
      expect(EventCategory.navigation.name, 'navigation');
      expect(EventCategory.fileOperation.name, 'fileOperation');
      expect(EventCategory.error.name, 'error');
    });
  });

  // ---------------------------------------------------------------------------
  // AnalyticsEvent serialization
  // ---------------------------------------------------------------------------

  group('AnalyticsEvent', () {
    test('toJson includes all required fields', () {
      final event = AnalyticsEvent(
        name: 'screen_view',
        category: EventCategory.navigation,
        properties: {'screen': 'home'},
        timestamp: DateTime(2026, 5, 1, 12, 0),
      );
      final json = event.toJson();
      expect(json['name'], 'screen_view');
      expect(json['category'], 'navigation');
      expect(json['properties'], {'screen': 'home'});
      expect(json['timestamp'], '2026-05-01T12:00:00.000');
    });

    test('fromJson round-trip preserves all fields', () {
      final original = AnalyticsEvent(
        name: 'feature_used',
        category: EventCategory.fileOperation,
        properties: {'feature': 'copy', 'count': 3},
        timestamp: DateTime(2026, 6, 15, 9, 30, 45),
      );
      final restored = AnalyticsEvent.fromJson(original.toJson());
      expect(restored.name, original.name);
      expect(restored.category, original.category);
      expect(restored.properties, original.properties);
      expect(restored.timestamp, original.timestamp);
    });

    test('fromJson handles unknown category gracefully (falls back to ui)', () {
      final event = AnalyticsEvent.fromJson({
        'name': 'test',
        'category': 'totally_unknown_category',
        'properties': {},
        'timestamp': '2026-01-01T00:00:00.000',
      });
      expect(event.category, EventCategory.ui);
    });

    test('fromJson handles missing fields with defaults', () {
      final event = AnalyticsEvent.fromJson({
        'timestamp': '2026-01-01T00:00:00.000',
      });
      expect(event.name, '');
      expect(event.category, EventCategory.ui);
      expect(event.properties, isEmpty);
    });

    test('properties are immutable (unmodifiable)', () {
      final event = AnalyticsEvent(
        name: 'test',
        category: EventCategory.ui,
        properties: {'key': 'value'},
      );
      expect(
        () => event.properties['new_key'] = 'x',
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('timestamp defaults to now when not provided', () {
      final before = DateTime.now();
      final event = AnalyticsEvent(name: 'test', category: EventCategory.ui);
      final after = DateTime.now();
      expect(
        event.timestamp.isAfter(before) || event.timestamp == before,
        isTrue,
      );
      expect(
        event.timestamp.isBefore(after) || event.timestamp == after,
        isTrue,
      );
    });

    test('empty properties are serialized as empty map', () {
      final event =
          AnalyticsEvent(name: 'test', category: EventCategory.settings);
      expect(event.toJson()['properties'], isEmpty);
    });

    test('JSON serialization covers all EventCategory values', () {
      for (final cat in EventCategory.values) {
        final event =
            AnalyticsEvent(name: 'test_${cat.name}', category: cat);
        final json = event.toJson();
        expect(json['category'], cat.name);
        final restored = AnalyticsEvent.fromJson(json);
        expect(restored.category, cat);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // UsageSummary serialization
  // ---------------------------------------------------------------------------

  group('UsageSummary', () {
    test('toJson includes all fields', () {
      final summary = UsageSummary(
        totalEvents: 42,
        eventsByCategory: {'navigation': 10, 'ui': 32},
        mostUsedFeatures: [
          MapEntry('file_preview', 20),
          MapEntry('sync', 15),
        ],
        sessionCount: 7,
        firstSeen: DateTime(2026, 1, 1),
        lastSeen: DateTime(2026, 5, 31),
      );
      final json = summary.toJson();
      expect(json['totalEvents'], 42);
      expect(json['eventsByCategory'], {'navigation': 10, 'ui': 32});
      expect((json['mostUsedFeatures'] as Map<String, int>)['file_preview'], 20);
      expect(json['sessionCount'], 7);
      expect(json['firstSeen'], '2026-01-01T00:00:00.000');
      expect(json['lastSeen'], '2026-05-31T00:00:00.000');
    });

    test('fromJson round-trip preserves all fields', () {
      final original = UsageSummary(
        totalEvents: 100,
        eventsByCategory: {'transfer': 50, 'error': 10},
        mostUsedFeatures: [MapEntry('upload', 50)],
        sessionCount: 3,
        firstSeen: DateTime(2026, 2, 1),
        lastSeen: DateTime(2026, 5, 20),
      );
      final restored = UsageSummary.fromJson(original.toJson());
      expect(restored.totalEvents, 100);
      expect(restored.eventsByCategory['transfer'], 50);
      expect(restored.mostUsedFeatures.first.key, 'upload');
      expect(restored.mostUsedFeatures.first.value, 50);
      expect(restored.sessionCount, 3);
      expect(restored.firstSeen, original.firstSeen);
      expect(restored.lastSeen, original.lastSeen);
    });

    test('toJson omits firstSeen/lastSeen when null', () {
      final summary = UsageSummary(
        totalEvents: 0,
        eventsByCategory: {},
        mostUsedFeatures: [],
        sessionCount: 0,
      );
      final json = summary.toJson();
      expect(json.containsKey('firstSeen'), isFalse);
      expect(json.containsKey('lastSeen'), isFalse);
    });

    test('fromJson handles empty/missing map', () {
      final summary = UsageSummary.fromJson({});
      expect(summary.totalEvents, 0);
      expect(summary.eventsByCategory, isEmpty);
      expect(summary.mostUsedFeatures, isEmpty);
      expect(summary.sessionCount, 0);
      expect(summary.firstSeen, isNull);
      expect(summary.lastSeen, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Opt-in / opt-out toggle
  // ---------------------------------------------------------------------------

  group('Opt-in toggle', () {
    test('service starts disabled by default', () async {
      final svc = _makeService();
      await svc.initialize();
      expect(svc.isEnabled, isFalse);
    });

    test('setEnabled(true) enables the service', () async {
      final svc = _makeService();
      await svc.initialize();
      await svc.setEnabled(true);
      expect(svc.isEnabled, isTrue);
    });

    test('setEnabled(false) disables the service', () async {
      final svc = _makeService();
      await svc.initialize();
      await svc.setEnabled(true);
      await svc.setEnabled(false);
      expect(svc.isEnabled, isFalse);
    });

    test('enabled state is persisted across service restarts', () async {
      // First service instance — enable it.
      SharedPreferences.setMockInitialValues({});
      final svc1 = _makeService();
      await svc1.initialize();
      await svc1.setEnabled(true);

      // Second instance shares same SharedPreferences mock — should see enabled.
      final svc2 = _makeService();
      await svc2.initialize();
      expect(svc2.isEnabled, isTrue);
    });

    test('disabled state is persisted across service restarts', () async {
      SharedPreferences.setMockInitialValues({'analytics_enabled': true});
      final svc1 = _makeService();
      await svc1.initialize();
      await svc1.setEnabled(false);

      final svc2 = _makeService();
      await svc2.initialize();
      expect(svc2.isEnabled, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Disabled service does not record events
  // ---------------------------------------------------------------------------

  group('Disabled service', () {
    test('trackEvent is no-op when disabled', () async {
      final svc = _makeService();
      await svc.initialize();
      // isEnabled is false by default
      svc.trackEvent('test', EventCategory.ui);
      expect(svc.getRecentEvents(), isEmpty);
    });

    test('trackScreenView is no-op when disabled', () async {
      final svc = _makeService();
      await svc.initialize();
      svc.trackScreenView('home');
      expect(svc.getRecentEvents(), isEmpty);
    });

    test('trackFeatureUsage is no-op when disabled', () async {
      final svc = _makeService();
      await svc.initialize();
      svc.trackFeatureUsage('file_preview');
      expect(svc.getRecentEvents(), isEmpty);
    });

    test('trackError is no-op when disabled', () async {
      final svc = _makeService();
      await svc.initialize();
      svc.trackError(Exception('boom'));
      expect(svc.getRecentEvents(), isEmpty);
    });

    test('trackProviderConnection is no-op when disabled', () async {
      final svc = _makeService();
      await svc.initialize();
      svc.trackProviderConnection('s3');
      expect(svc.getRecentEvents(), isEmpty);
    });

    test('trackTransferCompleted is no-op when disabled', () async {
      final svc = _makeService();
      await svc.initialize();
      svc.trackTransferCompleted('upload', 1024, 500);
      expect(svc.getRecentEvents(), isEmpty);
    });

    test('event counts remain empty when disabled', () async {
      final svc = _makeService();
      await svc.initialize();
      svc.trackEvent('test', EventCategory.ui);
      expect(svc.getEventCounts(), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Event recording when enabled
  // ---------------------------------------------------------------------------

  group('Event recording', () {
    test('trackEvent records event with correct fields', () async {
      final svc = await _enabledService();
      svc.trackEvent('my_action', EventCategory.fileOperation,
          properties: {'key': 'value'});
      final events = svc.getRecentEvents();
      expect(events, hasLength(1));
      expect(events.first.name, 'my_action');
      expect(events.first.category, EventCategory.fileOperation);
      expect(events.first.properties['key'], 'value');
    });

    test('trackEvent with no properties records empty map', () async {
      final svc = await _enabledService();
      svc.trackEvent('bare_event', EventCategory.settings);
      expect(svc.getRecentEvents().first.properties, isEmpty);
    });

    test('multiple events are all recorded', () async {
      final svc = await _enabledService();
      svc.trackEvent('event_a', EventCategory.ui);
      svc.trackEvent('event_b', EventCategory.sync);
      svc.trackEvent('event_c', EventCategory.error);
      expect(svc.getRecentEvents(), hasLength(3));
    });
  });

  // ---------------------------------------------------------------------------
  // Screen view tracking
  // ---------------------------------------------------------------------------

  group('trackScreenView', () {
    test('records screen_view event in navigation category', () async {
      final svc = await _enabledService();
      svc.trackScreenView('settings_page');
      final events = svc.getRecentEvents();
      expect(events, hasLength(1));
      expect(events.first.name, 'screen_view');
      expect(events.first.category, EventCategory.navigation);
      expect(events.first.properties['screen'], 'settings_page');
    });

    test('multiple screen views are all recorded', () async {
      final svc = await _enabledService();
      svc.trackScreenView('home');
      svc.trackScreenView('files');
      svc.trackScreenView('settings');
      expect(svc.getRecentEvents(), hasLength(3));
    });
  });

  // ---------------------------------------------------------------------------
  // Feature usage counting
  // ---------------------------------------------------------------------------

  group('trackFeatureUsage', () {
    test('records event in ui category', () async {
      final svc = await _enabledService();
      svc.trackFeatureUsage('file_preview');
      final events = svc.getRecentEvents();
      expect(events.first.name, 'file_preview');
      expect(events.first.category, EventCategory.ui);
    });

    test('usage count increments on repeated calls', () async {
      final svc = await _enabledService();
      svc.trackFeatureUsage('copy');
      svc.trackFeatureUsage('copy');
      svc.trackFeatureUsage('copy');
      expect(svc.getEventCounts()['copy'], 3);
    });

    test('different features have independent counts', () async {
      final svc = await _enabledService();
      svc.trackFeatureUsage('copy');
      svc.trackFeatureUsage('paste');
      svc.trackFeatureUsage('copy');
      final counts = svc.getEventCounts();
      expect(counts['copy'], 2);
      expect(counts['paste'], 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Error tracking — strips file paths
  // ---------------------------------------------------------------------------

  group('trackError', () {
    test('records event in error category', () async {
      final svc = await _enabledService();
      svc.trackError(Exception('something went wrong'));
      final events = svc.getRecentEvents();
      expect(events.first.category, EventCategory.error);
      expect(events.first.name, 'error');
    });

    test('stores error type', () async {
      final svc = await _enabledService();
      svc.trackError(FormatException('bad format'));
      final props = svc.getRecentEvents().first.properties;
      expect(props['error_type'], contains('FormatException'));
    });

    test('strips Unix file paths from error message', () async {
      final svc = await _enabledService();
      svc.trackError(
          Exception('Failed to read /home/user/documents/secret.txt'));
      final props = svc.getRecentEvents().first.properties;
      final msg = props['error_message'] as String;
      expect(msg, isNot(contains('/home/user/documents/secret.txt')));
      expect(msg, contains('[path]'));
    });

    test('strips Windows file paths from error message', () async {
      final svc = await _enabledService();
      svc.trackError(
          Exception(r'Access denied: C:\Users\Alice\Documents\report.docx'));
      final props = svc.getRecentEvents().first.properties;
      final msg = props['error_message'] as String;
      expect(msg, isNot(contains(r'C:\Users\Alice')));
      expect(msg, contains('[path]'));
    });

    test('records optional context string', () async {
      final svc = await _enabledService();
      svc.trackError(Exception('oops'), context: 'file_upload');
      final props = svc.getRecentEvents().first.properties;
      expect(props['context'], 'file_upload');
    });

    test('stack trace is summarized and sanitized', () async {
      final svc = await _enabledService();
      StackTrace? trace;
      try {
        throw Exception('test error');
      } catch (e, st) {
        trace = st;
      }
      svc.trackError(Exception('test error'), stackTrace: trace);
      final props = svc.getRecentEvents().first.properties;
      expect(props.containsKey('stack_summary'), isTrue);
      // Stack summary should be at most 503 chars (500 + "...")
      expect((props['stack_summary'] as String).length, lessThanOrEqualTo(503));
    });
  });

  // ---------------------------------------------------------------------------
  // Provider connection tracking
  // ---------------------------------------------------------------------------

  group('trackProviderConnection', () {
    test('records provider_connected event in connection category', () async {
      final svc = await _enabledService();
      svc.trackProviderConnection('dropbox');
      final events = svc.getRecentEvents();
      expect(events.first.name, 'provider_connected');
      expect(events.first.category, EventCategory.connection);
      expect(events.first.properties['provider'], 'dropbox');
    });

    test('only stores provider name, not any credentials', () async {
      final svc = await _enabledService();
      svc.trackProviderConnection('s3');
      final props = svc.getRecentEvents().first.properties;
      // Should only contain 'provider'
      expect(props.keys, equals(['provider']));
    });

    test('tracks multiple providers independently', () async {
      final svc = await _enabledService();
      svc.trackProviderConnection('s3');
      svc.trackProviderConnection('gdrive');
      svc.trackProviderConnection('onedrive');
      final events = svc.getRecentEvents();
      expect(events, hasLength(3));
      final providers =
          events.map((e) => e.properties['provider'] as String).toSet();
      expect(providers, containsAll(['s3', 'gdrive', 'onedrive']));
    });
  });

  // ---------------------------------------------------------------------------
  // Transfer stats — no filenames
  // ---------------------------------------------------------------------------

  group('trackTransferCompleted', () {
    test('records transfer_completed event in transfer category', () async {
      final svc = await _enabledService();
      svc.trackTransferCompleted('upload', 1024 * 1024, 3500);
      final events = svc.getRecentEvents();
      expect(events.first.name, 'transfer_completed');
      expect(events.first.category, EventCategory.transfer);
    });

    test('records direction, size_bytes, and duration_ms', () async {
      final svc = await _enabledService();
      svc.trackTransferCompleted('download', 512 * 1024, 1200);
      final props = svc.getRecentEvents().first.properties;
      expect(props['direction'], 'download');
      expect(props['size_bytes'], 512 * 1024);
      expect(props['duration_ms'], 1200);
    });

    test('properties contain only direction, size_bytes, duration_ms', () async {
      final svc = await _enabledService();
      svc.trackTransferCompleted('upload', 256, 100);
      final props = svc.getRecentEvents().first.properties;
      expect(props.keys.toSet(),
          equals({'direction', 'size_bytes', 'duration_ms'}));
    });
  });

  // ---------------------------------------------------------------------------
  // Ring buffer cap
  // ---------------------------------------------------------------------------

  group('Ring buffer', () {
    test('stores up to 1000 events', () async {
      final svc = await _enabledService();
      for (int i = 0; i < 1000; i++) {
        svc.trackEvent('event_$i', EventCategory.ui);
      }
      expect(svc.getRecentEvents(), hasLength(1000));
    });

    test('adding 1001st event drops the oldest', () async {
      final svc = await _enabledService();
      for (int i = 0; i < 1001; i++) {
        svc.trackEvent('event_$i', EventCategory.ui);
      }
      final events = svc.getRecentEvents();
      expect(events, hasLength(1000));
      // Oldest event_0 should be gone; event_1 should be the first
      expect(events.first.name, 'event_1');
    });

    test('ring buffer rolls over: 1000 events after 2000 insertions', () async {
      final svc = await _enabledService();
      for (int i = 0; i < 2000; i++) {
        svc.trackEvent('event_$i', EventCategory.ui);
      }
      expect(svc.getRecentEvents(), hasLength(1000));
      // Should have events_1000 through events_1999
      expect(svc.getRecentEvents().first.name, 'event_1000');
      expect(svc.getRecentEvents().last.name, 'event_1999');
    });

    test('getRecentEvents(limit) returns at most limit events', () async {
      final svc = await _enabledService();
      for (int i = 0; i < 20; i++) {
        svc.trackEvent('e$i', EventCategory.ui);
      }
      expect(svc.getRecentEvents(5), hasLength(5));
    });

    test('getRecentEvents returns newest-last order', () async {
      final svc = await _enabledService();
      svc.trackEvent('first', EventCategory.ui);
      svc.trackEvent('second', EventCategory.ui);
      svc.trackEvent('third', EventCategory.ui);
      final events = svc.getRecentEvents();
      expect(events.first.name, 'first');
      expect(events.last.name, 'third');
    });
  });

  // ---------------------------------------------------------------------------
  // Event counts aggregation
  // ---------------------------------------------------------------------------

  group('getEventCounts', () {
    test('returns empty map when no events', () async {
      final svc = await _enabledService();
      expect(svc.getEventCounts(), isEmpty);
    });

    test('counts each distinct event name', () async {
      final svc = await _enabledService();
      svc.trackEvent('alpha', EventCategory.ui);
      svc.trackEvent('beta', EventCategory.ui);
      svc.trackEvent('alpha', EventCategory.ui);
      svc.trackEvent('alpha', EventCategory.ui);
      final counts = svc.getEventCounts();
      expect(counts['alpha'], 3);
      expect(counts['beta'], 1);
    });

    test('returns unmodifiable map', () async {
      final svc = await _enabledService();
      svc.trackEvent('test', EventCategory.ui);
      expect(
        () => svc.getEventCounts()['new'] = 99,
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Usage summary computation
  // ---------------------------------------------------------------------------

  group('getUsageSummary', () {
    test('returns zero counts with empty buffer', () async {
      final svc = await _enabledService();
      final summary = await svc.getUsageSummary();
      expect(summary.totalEvents, 0);
      expect(summary.eventsByCategory, isEmpty);
      expect(summary.mostUsedFeatures, isEmpty);
    });

    test('totalEvents matches buffer size', () async {
      final svc = await _enabledService();
      svc.trackEvent('a', EventCategory.ui);
      svc.trackEvent('b', EventCategory.sync);
      svc.trackEvent('c', EventCategory.error);
      final summary = await svc.getUsageSummary();
      expect(summary.totalEvents, 3);
    });

    test('eventsByCategory groups events correctly', () async {
      final svc = await _enabledService();
      svc.trackEvent('nav1', EventCategory.navigation);
      svc.trackEvent('nav2', EventCategory.navigation);
      svc.trackEvent('ui1', EventCategory.ui);
      final summary = await svc.getUsageSummary();
      expect(summary.eventsByCategory['navigation'], 2);
      expect(summary.eventsByCategory['ui'], 1);
    });

    test('eventsByCategory covers multiple categories', () async {
      final svc = await _enabledService();
      svc.trackEvent('a', EventCategory.navigation);
      svc.trackEvent('b', EventCategory.transfer);
      svc.trackEvent('c', EventCategory.error);
      svc.trackEvent('d', EventCategory.sync);
      final summary = await svc.getUsageSummary();
      expect(summary.eventsByCategory.keys,
          containsAll(['navigation', 'transfer', 'error', 'sync']));
    });

    test('lastSeen is set to the timestamp of the last event', () async {
      final svc = await _enabledService();
      svc.trackEvent('a', EventCategory.ui);
      final summary = await svc.getUsageSummary();
      expect(summary.lastSeen, isNotNull);
    });

    test('lastSeen is null when buffer is empty', () async {
      final svc = await _enabledService();
      final summary = await svc.getUsageSummary();
      expect(summary.lastSeen, isNull);
    });

    test('sessionCount is at least 1 after initialization', () async {
      final svc = await _enabledService();
      final summary = await svc.getUsageSummary();
      expect(summary.sessionCount, greaterThanOrEqualTo(1));
    });
  });

  // ---------------------------------------------------------------------------
  // Top-10 features sorting
  // ---------------------------------------------------------------------------

  group('mostUsedFeatures top-10 sorting', () {
    test('returns features sorted by count descending', () async {
      final svc = await _enabledService();
      // alpha × 5, beta × 3, gamma × 8
      for (int i = 0; i < 5; i++) svc.trackFeatureUsage('alpha');
      for (int i = 0; i < 3; i++) svc.trackFeatureUsage('beta');
      for (int i = 0; i < 8; i++) svc.trackFeatureUsage('gamma');
      final summary = await svc.getUsageSummary();
      expect(summary.mostUsedFeatures.first.key, 'gamma');
      expect(summary.mostUsedFeatures.first.value, 8);
      expect(summary.mostUsedFeatures[1].key, 'alpha');
      expect(summary.mostUsedFeatures.last.key, 'beta');
    });

    test('returns at most 10 features when more exist', () async {
      final svc = await _enabledService();
      for (int i = 0; i < 15; i++) {
        svc.trackFeatureUsage('feature_$i');
      }
      final summary = await svc.getUsageSummary();
      expect(summary.mostUsedFeatures, hasLength(10));
    });

    test('returns all features when fewer than 10 exist', () async {
      final svc = await _enabledService();
      svc.trackFeatureUsage('alpha');
      svc.trackFeatureUsage('beta');
      final summary = await svc.getUsageSummary();
      expect(summary.mostUsedFeatures, hasLength(2));
    });
  });

  // ---------------------------------------------------------------------------
  // Export as JSON
  // ---------------------------------------------------------------------------

  group('exportEvents', () {
    test('returns valid JSON string', () async {
      final svc = await _enabledService();
      svc.trackEvent('test', EventCategory.ui);
      final json = svc.exportEvents();
      expect(() => jsonDecode(json), returnsNormally);
    });

    test('exported JSON contains all recorded events', () async {
      final svc = await _enabledService();
      svc.trackEvent('first', EventCategory.navigation);
      svc.trackEvent('second', EventCategory.sync);
      final json = svc.exportEvents();
      final list = jsonDecode(json) as List;
      expect(list, hasLength(2));
      expect(list.first['name'], 'first');
      expect(list.last['name'], 'second');
    });

    test('export is pretty-printed (contains newlines)', () async {
      final svc = await _enabledService();
      svc.trackEvent('test', EventCategory.ui);
      final json = svc.exportEvents();
      expect(json, contains('\n'));
    });

    test('empty buffer exports as empty JSON array', () async {
      final svc = await _enabledService();
      final json = svc.exportEvents();
      expect(jsonDecode(json), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Clear events
  // ---------------------------------------------------------------------------

  group('clearEvents', () {
    test('clears the in-memory buffer', () async {
      final svc = await _enabledService();
      svc.trackEvent('test', EventCategory.ui);
      svc.trackEvent('test2', EventCategory.sync);
      await svc.clearEvents();
      expect(svc.getRecentEvents(), isEmpty);
    });

    test('clears event counts', () async {
      final svc = await _enabledService();
      svc.trackFeatureUsage('copy');
      svc.trackFeatureUsage('paste');
      await svc.clearEvents();
      expect(svc.getEventCounts(), isEmpty);
    });

    test('calls backend clearEvents', () async {
      final backend = _CapturingBackend();
      final svc = await _enabledService(backend: backend);
      svc.trackEvent('test', EventCategory.ui);
      await svc.clearEvents();
      expect(backend.cleared, isTrue);
    });

    test('new events can be recorded after clear', () async {
      final svc = await _enabledService();
      svc.trackEvent('before', EventCategory.ui);
      await svc.clearEvents();
      svc.trackEvent('after', EventCategory.ui);
      expect(svc.getRecentEvents(), hasLength(1));
      expect(svc.getRecentEvents().first.name, 'after');
    });
  });

  // ---------------------------------------------------------------------------
  // Install ID
  // ---------------------------------------------------------------------------

  group('Install ID', () {
    test('getInstallId returns a non-empty string', () async {
      final svc = _makeService();
      await svc.initialize();
      final id = await svc.getInstallId();
      expect(id, isNotEmpty);
    });

    test('install ID matches UUID v4 format', () async {
      final svc = _makeService();
      await svc.initialize();
      final id = await svc.getInstallId();
      final uuidRegex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      );
      expect(uuidRegex.hasMatch(id), isTrue,
          reason: 'Install ID "$id" does not match UUID v4 format');
    });

    test('install ID is the same on repeated calls to getInstallId', () async {
      final svc = _makeService();
      await svc.initialize();
      final id1 = await svc.getInstallId();
      final id2 = await svc.getInstallId();
      expect(id1, equals(id2));
    });

    test('install ID survives service restart (same SharedPreferences)', () async {
      SharedPreferences.setMockInitialValues({});
      final svc1 = _makeService();
      await svc1.initialize();
      final id1 = await svc1.getInstallId();

      // New service instance sharing the same mock SharedPreferences
      final svc2 = _makeService();
      await svc2.initialize();
      final id2 = await svc2.getInstallId();

      expect(id1, equals(id2));
    });

    test('two separate install IDs differ (fresh prefs each time)', () async {
      SharedPreferences.setMockInitialValues({});
      final svc1 = _makeService();
      await svc1.initialize();
      final id1 = await svc1.getInstallId();

      SharedPreferences.setMockInitialValues({});
      final svc2 = _makeService();
      await svc2.initialize();
      final id2 = await svc2.getInstallId();

      expect(id1, isNot(equals(id2)));
    });
  });

  // ---------------------------------------------------------------------------
  // LocalBackend persistence
  // ---------------------------------------------------------------------------

  group('LocalBackend', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('analytics_test_');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('initialize() sets up without errors', () async {
      final backend = LocalBackend();
      await expectLater(backend.initialize(), completes);
    });

    test('persistEvents and loadEvents round-trip', () async {
      final backend = LocalBackend();
      backend.setFilePathForTesting(p.join(tempDir.path, 'events.jsonl'));

      final events = [
        AnalyticsEvent(
            name: 'event_a',
            category: EventCategory.ui,
            timestamp: DateTime(2026, 5, 1)),
        AnalyticsEvent(
            name: 'event_b',
            category: EventCategory.sync,
            timestamp: DateTime(2026, 5, 2)),
      ];
      await backend.persistEvents(events);

      final loaded = await backend.loadEvents();
      expect(loaded, hasLength(2));
      expect(loaded.first.name, 'event_a');
      expect(loaded.last.name, 'event_b');
    });

    test('clearEvents empties the file', () async {
      final backend = LocalBackend();
      backend.setFilePathForTesting(p.join(tempDir.path, 'events.jsonl'));

      await backend.persistEvents([
        AnalyticsEvent(name: 'test', category: EventCategory.ui),
      ]);
      await backend.clearEvents();

      final loaded = await backend.loadEvents();
      expect(loaded, isEmpty);
    });

    test('loadEvents returns empty list when file does not exist', () async {
      final backend = LocalBackend();
      backend.setFilePathForTesting(
          p.join(tempDir.path, 'nonexistent.jsonl'));
      final loaded = await backend.loadEvents();
      expect(loaded, isEmpty);
    });

    test('memoryStore is accessible for testing', () async {
      final backend = LocalBackend();
      // Without a filePath, events go to memory store
      await backend.persistEvents([
        AnalyticsEvent(name: 'mem_event', category: EventCategory.ui),
      ]);
      expect(backend.memoryStore, hasLength(1));
      expect(backend.memoryStore.first.name, 'mem_event');
    });

    test('persisted events survive across backend instances (file)', () async {
      final filePath = p.join(tempDir.path, 'persistent.jsonl');

      final backend1 = LocalBackend();
      backend1.setFilePathForTesting(filePath);
      await backend1.persistEvents([
        AnalyticsEvent(
            name: 'persisted_event',
            category: EventCategory.settings,
            timestamp: DateTime(2026, 1, 10)),
      ]);

      final backend2 = LocalBackend();
      backend2.setFilePathForTesting(filePath);
      final loaded = await backend2.loadEvents();
      expect(loaded, hasLength(1));
      expect(loaded.first.name, 'persisted_event');
    });
  });

  // ---------------------------------------------------------------------------
  // RemoteBackend placeholder
  // ---------------------------------------------------------------------------

  group('RemoteBackend placeholder', () {
    test('initialize() completes without error', () async {
      final backend = RemoteBackend(endpointUrl: 'https://example.com/events');
      await expectLater(backend.initialize(), completes);
    });

    test('persistEvents completes without error', () async {
      final backend = RemoteBackend(endpointUrl: 'https://example.com/events');
      await expectLater(
        backend.persistEvents([
          AnalyticsEvent(name: 'test', category: EventCategory.ui),
        ]),
        completes,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // isInitialized flag
  // ---------------------------------------------------------------------------

  group('isInitialized', () {
    test('is false before initialize()', () {
      final svc = _makeService();
      expect(svc.isInitialized, isFalse);
    });

    test('is true after initialize()', () async {
      final svc = _makeService();
      await svc.initialize();
      expect(svc.isInitialized, isTrue);
    });

    test('initialize() is idempotent', () async {
      final svc = _makeService();
      await svc.initialize();
      await svc.initialize(); // Should not throw or double-count session
      expect(svc.isInitialized, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Backend management
  // ---------------------------------------------------------------------------

  group('setBackend', () {
    test('replaces the active backend', () async {
      final svc = await _enabledService();
      final newBackend = _CapturingBackend();
      await svc.setBackend(newBackend);
      expect(svc.backend, same(newBackend));
      expect(newBackend.initialized, isTrue);
    });
  });
}
