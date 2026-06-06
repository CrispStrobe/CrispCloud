// lib/services/analytics_service.dart
//
// Opt-in anonymous usage analytics service.
//
// Privacy guarantees:
//   - NO file names, paths, or content are ever recorded.
//   - NO IP addresses or location data.
//   - NO credentials, tokens, or authentication data.
//   - Only feature names, event counts, byte sizes, and durations (ms).
//   - Install ID is a random UUID unrelated to any user identity.
//
// Features:
//   - Opt-in toggle persisted to SharedPreferences (disabled by default).
//   - In-memory ring buffer: last 1000 events.
//   - Pluggable AnalyticsBackend: LocalBackend (JSON file) and
//     RemoteBackend placeholder (HTTP POST).
//   - Convenience methods: trackScreenView, trackFeatureUsage, trackError,
//     trackProviderConnection, trackTransferCompleted.
//   - Aggregate: getEventCounts(), getUsageSummary(), exportEvents().
//
// Usage:
//   final service = AnalyticsService();
//   await service.initialize();
//   await service.setEnabled(true);
//   service.trackFeatureUsage('file_preview');
//   service.trackTransferCompleted('upload', 1024 * 1024, 3500);

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log_service.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _kEnabledKey = 'analytics_enabled';
const _kInstallIdKey = 'analytics_install_id';
const _kFirstSeenKey = 'analytics_first_seen';
const _kSessionCountKey = 'analytics_session_count';
const _kRingBufferCapacity = 1000;
const _kAnalyticsFileName = 'analytics_events.jsonl';
const _kMaxStoredEvents = 5000;

// ---------------------------------------------------------------------------
// EventCategory enum
// ---------------------------------------------------------------------------

/// High-level category for an analytics event.
///
/// Values are kept stable — do NOT reorder or remove them.
enum EventCategory {
  navigation,
  fileOperation,
  sync,
  connection,
  ui,
  encryption,
  search,
  transfer,
  settings,
  error,
}

// ---------------------------------------------------------------------------
// AnalyticsEvent model
// ---------------------------------------------------------------------------

/// A single immutable analytics event.
class AnalyticsEvent {
  final String name;
  final EventCategory category;
  final Map<String, dynamic> properties;
  final DateTime timestamp;

  AnalyticsEvent({
    required this.name,
    required this.category,
    Map<String, dynamic>? properties,
    DateTime? timestamp,
  })  : properties = Map.unmodifiable(properties ?? const {}),
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'name': name,
        'category': category.name,
        'properties': properties,
        'timestamp': timestamp.toIso8601String(),
      };

  factory AnalyticsEvent.fromJson(Map<String, dynamic> json) {
    EventCategory cat;
    final catStr = json['category'] as String? ?? 'ui';
    try {
      cat = EventCategory.values.firstWhere((e) => e.name == catStr);
    } catch (_) {
      cat = EventCategory.ui;
    }
    final rawProps = json['properties'];
    Map<String, dynamic> props = {};
    if (rawProps is Map) {
      props = Map<String, dynamic>.from(rawProps);
    }
    return AnalyticsEvent(
      name: json['name'] as String? ?? '',
      category: cat,
      properties: props,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  @override
  String toString() =>
      'AnalyticsEvent(name: $name, category: ${category.name}, '
      'timestamp: ${timestamp.toIso8601String()})';
}

// ---------------------------------------------------------------------------
// UsageSummary model
// ---------------------------------------------------------------------------

/// Aggregate usage statistics computed from the in-memory event buffer.
class UsageSummary {
  final int totalEvents;
  final Map<String, int> eventsByCategory;
  final List<MapEntry<String, int>> mostUsedFeatures;
  final int sessionCount;
  final DateTime? firstSeen;
  final DateTime? lastSeen;

  const UsageSummary({
    required this.totalEvents,
    required this.eventsByCategory,
    required this.mostUsedFeatures,
    required this.sessionCount,
    this.firstSeen,
    this.lastSeen,
  });

  Map<String, dynamic> toJson() => {
        'totalEvents': totalEvents,
        'eventsByCategory': eventsByCategory,
        'mostUsedFeatures': {
          for (final e in mostUsedFeatures) e.key: e.value,
        },
        'sessionCount': sessionCount,
        if (firstSeen != null) 'firstSeen': firstSeen!.toIso8601String(),
        if (lastSeen != null) 'lastSeen': lastSeen!.toIso8601String(),
      };

  factory UsageSummary.fromJson(Map<String, dynamic> json) {
    final catMap = <String, int>{};
    final catRaw = json['eventsByCategory'];
    if (catRaw is Map) {
      catRaw.forEach((k, v) {
        if (v is int) catMap[k.toString()] = v;
      });
    }
    final featuresList = <MapEntry<String, int>>[];
    final featRaw = json['mostUsedFeatures'];
    if (featRaw is Map) {
      featRaw.forEach((k, v) {
        if (v is int) featuresList.add(MapEntry(k.toString(), v));
      });
    }
    return UsageSummary(
      totalEvents: json['totalEvents'] as int? ?? 0,
      eventsByCategory: catMap,
      mostUsedFeatures: featuresList,
      sessionCount: json['sessionCount'] as int? ?? 0,
      firstSeen: json['firstSeen'] != null
          ? DateTime.tryParse(json['firstSeen'] as String)
          : null,
      lastSeen: json['lastSeen'] != null
          ? DateTime.tryParse(json['lastSeen'] as String)
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// AnalyticsBackend abstraction
// ---------------------------------------------------------------------------

/// Abstract analytics backend — implement to persist or ship events.
abstract class AnalyticsBackend {
  /// Called once during service initialization.
  Future<void> initialize() async {}

  /// Persist or send a batch of events.
  Future<void> persistEvents(List<AnalyticsEvent> events) async {}

  /// Load previously persisted events (newest-last order).
  Future<List<AnalyticsEvent>> loadEvents() async => [];

  /// Delete all persisted events.
  Future<void> clearEvents() async {}
}

// ---------------------------------------------------------------------------
// LocalBackend
// ---------------------------------------------------------------------------

/// Appends events as JSON-lines to <appSupportDir>/analytics_events.jsonl.
/// On web, operates fully in-memory.
class LocalBackend extends AnalyticsBackend {
  static const _log = Log('AnalyticsLocalBackend');

  String? _filePath;
  final List<AnalyticsEvent> _memStore = [];

  @override
  Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationSupportDirectory();
      _filePath = p.join(dir.path, _kAnalyticsFileName);
    } catch (e) {
      _log.warn('LocalBackend: could not resolve storage path', e);
    }
  }

  @override
  Future<void> persistEvents(List<AnalyticsEvent> events) async {
    if (kIsWeb || _filePath == null) {
      _memStore.addAll(events);
      while (_memStore.length > _kMaxStoredEvents) {
        _memStore.removeAt(0);
      }
      return;
    }
    try {
      final file = File(_filePath!);
      final buffer = StringBuffer();
      for (final e in events) {
        buffer.writeln(jsonEncode(e.toJson()));
      }
      await file.writeAsString(buffer.toString(),
          mode: FileMode.append, flush: true);
    } catch (e) {
      _log.warn('LocalBackend: failed to persist events', e);
      _memStore.addAll(events);
    }
  }

  @override
  Future<List<AnalyticsEvent>> loadEvents() async {
    if (kIsWeb || _filePath == null) {
      return List.of(_memStore);
    }
    final file = File(_filePath!);
    if (!file.existsSync()) return [];
    try {
      final lines = await file.readAsLines();
      final events = <AnalyticsEvent>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          events.add(
              AnalyticsEvent.fromJson(jsonDecode(line) as Map<String, dynamic>));
        } catch (_) {}
      }
      return events;
    } catch (e) {
      _log.warn('LocalBackend: failed to load events', e);
      return List.of(_memStore);
    }
  }

  @override
  Future<void> clearEvents() async {
    _memStore.clear();
    if (kIsWeb || _filePath == null) return;
    try {
      final file = File(_filePath!);
      if (file.existsSync()) {
        await file.writeAsString('');
      }
    } catch (e) {
      _log.warn('LocalBackend: failed to clear events', e);
    }
  }

  // Testing helpers
  void setFilePathForTesting(String path) => _filePath = path;
  List<AnalyticsEvent> get memoryStore => List.unmodifiable(_memStore);
}

// ---------------------------------------------------------------------------
// RemoteBackend (placeholder)
// ---------------------------------------------------------------------------

/// Placeholder remote backend that would POST events to an analytics endpoint.
///
/// To activate, add an HTTP client dependency and implement [persistEvents].
class RemoteBackend extends AnalyticsBackend {
  static const _log = Log('AnalyticsRemoteBackend');

  final String endpointUrl;
  final String? apiKey;

  RemoteBackend({required this.endpointUrl, this.apiKey});

  @override
  Future<void> initialize() async {
    _log.info('RemoteBackend initialized (placeholder)', {'url': endpointUrl});
  }

  @override
  Future<void> persistEvents(List<AnalyticsEvent> events) async {
    // TODO: POST jsonEncode(events.map((e) => e.toJson()).toList())
    // to endpointUrl with Authorization: Bearer $apiKey header.
    _log.debug('RemoteBackend.persistEvents (placeholder)',
        {'count': events.length});
  }
}

// ---------------------------------------------------------------------------
// UUID generator (no external dependency)
// ---------------------------------------------------------------------------

/// Generates a v4 (random) UUID string.
String _generateUuid() {
  final rng = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  // Set version 4 bits
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  // Set variant bits
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
  final b = bytes.map(hex).toList();
  return '${b[0]}${b[1]}${b[2]}${b[3]}'
      '-${b[4]}${b[5]}'
      '-${b[6]}${b[7]}'
      '-${b[8]}${b[9]}'
      '-${b[10]}${b[11]}${b[12]}${b[13]}${b[14]}${b[15]}';
}

// ---------------------------------------------------------------------------
// AnalyticsService
// ---------------------------------------------------------------------------

/// Opt-in anonymous usage analytics service.
///
/// Disabled by default — explicitly call [setEnabled(true)] after user
/// consent. No file names, paths, credentials, or personal data are ever
/// recorded.
class AnalyticsService {
  static const _log = Log('AnalyticsService');

  AnalyticsBackend _backend;
  bool _enabled = false;
  bool _initialized = false;

  // In-memory ring buffer of the last [_kRingBufferCapacity] events.
  final Queue<AnalyticsEvent> _buffer = Queue<AnalyticsEvent>();

  // Feature-usage counters (counts since last clear).
  final Map<String, int> _featureCounts = {};

  // Cached persistent values (loaded during initialize).
  String? _installId;
  DateTime? _firstSeen;

  AnalyticsService({AnalyticsBackend? backend})
      : _backend = backend ?? LocalBackend();

  bool get isEnabled => _enabled;
  bool get isInitialized => _initialized;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Initialize the service: load preferences, install ID, and backend.
  ///
  /// Safe to call multiple times. No-op after the first call.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await _backend.initialize();
    } catch (e) {
      _log.warn('AnalyticsService: backend init failed', e);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabledKey) ?? false;
      _installId = prefs.getString(_kInstallIdKey);
      final firstSeenStr = prefs.getString(_kFirstSeenKey);
      _firstSeen =
          firstSeenStr != null ? DateTime.tryParse(firstSeenStr) : null;

      if (_installId == null) {
        _installId = _generateUuid();
        await prefs.setString(_kInstallIdKey, _installId!);
      }
      if (_firstSeen == null) {
        _firstSeen = DateTime.now();
        await prefs.setString(_kFirstSeenKey, _firstSeen!.toIso8601String());
      }

      // Increment session counter each time the service initializes.
      final sessionCount = (prefs.getInt(_kSessionCountKey) ?? 0) + 1;
      await prefs.setInt(_kSessionCountKey, sessionCount);
    } catch (e) {
      _log.warn('AnalyticsService: failed to load preferences', e);
      _installId ??= _generateUuid();
    }

    _log.info('AnalyticsService initialized',
        {'enabled': _enabled, 'installId': _installId});
  }

  // ---------------------------------------------------------------------------
  // Opt-in toggle
  // ---------------------------------------------------------------------------

  /// Enable or disable analytics and persist the preference.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabledKey, value);
    } catch (e) {
      _log.warn('AnalyticsService: failed to save preference', e);
    }
    _log.info('Analytics ${value ? "enabled" : "disabled"}');
  }

  // ---------------------------------------------------------------------------
  // Core tracking
  // ---------------------------------------------------------------------------

  /// Record a named event. No-op when analytics are disabled.
  ///
  /// [properties] must NEVER contain file names, paths, credentials, tokens,
  /// IP addresses, or any personally identifiable information.
  void trackEvent(
    String name,
    EventCategory category, {
    Map<String, dynamic>? properties,
  }) {
    if (!_enabled) return;
    _record(AnalyticsEvent(
      name: name,
      category: category,
      properties: properties,
    ));
  }

  void _record(AnalyticsEvent event) {
    _buffer.add(event);
    while (_buffer.length > _kRingBufferCapacity) {
      _buffer.removeFirst();
    }
    // Update feature counter
    _featureCounts[event.name] = (_featureCounts[event.name] ?? 0) + 1;
  }

  // ---------------------------------------------------------------------------
  // Convenience methods
  // ---------------------------------------------------------------------------

  /// Record a screen view event. No-op when disabled.
  void trackScreenView(String screenName) {
    if (!_enabled) return;
    _record(AnalyticsEvent(
      name: 'screen_view',
      category: EventCategory.navigation,
      properties: {'screen': screenName},
    ));
  }

  /// Record a feature usage event. No-op when disabled.
  void trackFeatureUsage(String featureName) {
    if (!_enabled) return;
    _record(AnalyticsEvent(
      name: featureName,
      category: EventCategory.ui,
    ));
  }

  /// Record an error event. File paths are stripped from the error message.
  ///
  /// The stack trace is truncated to 500 characters and sanitized.
  /// No file paths or user-identifiable data are stored.
  void trackError(
    Object error, {
    StackTrace? stackTrace,
    String? context,
  }) {
    if (!_enabled) return;
    final errorStr = _sanitizeErrorMessage(error.toString());
    final props = <String, dynamic>{
      'error_type': error.runtimeType.toString(),
      'error_message': errorStr,
      if (context != null) 'context': context,
      if (stackTrace != null)
        'stack_summary': _summarizeStackTrace(stackTrace.toString()),
    };
    _record(AnalyticsEvent(
      name: 'error',
      category: EventCategory.error,
      properties: props,
    ));
  }

  /// Record a cloud provider connection event. Only the provider name is
  /// stored — no URLs, credentials, or tokens.
  void trackProviderConnection(String providerName) {
    if (!_enabled) return;
    _record(AnalyticsEvent(
      name: 'provider_connected',
      category: EventCategory.connection,
      properties: {'provider': providerName},
    ));
  }

  /// Record transfer statistics. Stores direction, size in bytes, and
  /// duration in milliseconds — no file names or paths.
  ///
  /// [direction] should be `'upload'` or `'download'`.
  void trackTransferCompleted(
    String direction,
    int sizeBytes,
    int durationMs,
  ) {
    if (!_enabled) return;
    _record(AnalyticsEvent(
      name: 'transfer_completed',
      category: EventCategory.transfer,
      properties: {
        'direction': direction,
        'size_bytes': sizeBytes,
        'duration_ms': durationMs,
      },
    ));
  }

  // ---------------------------------------------------------------------------
  // Retrieval
  // ---------------------------------------------------------------------------

  /// Return the last [limit] events from the in-memory buffer (newest last).
  ///
  /// Defaults to [_kRingBufferCapacity] (1000), i.e. all buffered events.
  List<AnalyticsEvent> getRecentEvents([int limit = _kRingBufferCapacity]) {
    final all = _buffer.toList();
    if (all.length <= limit) return List.unmodifiable(all);
    return List.unmodifiable(all.sublist(all.length - limit));
  }

  /// Return event counts keyed by event name.
  Map<String, int> getEventCounts() => Map.unmodifiable(_featureCounts);

  /// Compute an aggregate [UsageSummary] from the current buffer.
  Future<UsageSummary> getUsageSummary() async {
    int sessionCount = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      sessionCount = prefs.getInt(_kSessionCountKey) ?? 0;
    } catch (_) {}

    // Count events by category
    final catCounts = <String, int>{};
    for (final event in _buffer) {
      catCounts[event.category.name] =
          (catCounts[event.category.name] ?? 0) + 1;
    }

    // Top-10 most-used features (by event name count)
    final sorted = _featureCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top10 = sorted.take(10).toList();

    final lastSeen = _buffer.isNotEmpty ? _buffer.last.timestamp : null;

    return UsageSummary(
      totalEvents: _buffer.length,
      eventsByCategory: catCounts,
      mostUsedFeatures: top10,
      sessionCount: sessionCount,
      firstSeen: _firstSeen,
      lastSeen: lastSeen,
    );
  }

  // ---------------------------------------------------------------------------
  // Export / clear
  // ---------------------------------------------------------------------------

  /// Export all in-memory events as a pretty-printed JSON string.
  String exportEvents() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(_buffer.map((e) => e.toJson()).toList());
  }

  /// Clear in-memory buffer, counters, and persisted events.
  Future<void> clearEvents() async {
    _buffer.clear();
    _featureCounts.clear();
    try {
      await _backend.clearEvents();
    } catch (e) {
      _log.warn('AnalyticsService: failed to clear backend events', e);
    }
  }

  // ---------------------------------------------------------------------------
  // Install ID
  // ---------------------------------------------------------------------------

  /// Return the anonymous install ID (random UUID, generated once and
  /// persisted). Not tied to any user identity.
  Future<String> getInstallId() async {
    if (_installId != null) return _installId!;
    // Fallback: generate and persist
    try {
      final prefs = await SharedPreferences.getInstance();
      _installId = prefs.getString(_kInstallIdKey);
      if (_installId == null) {
        _installId = _generateUuid();
        await prefs.setString(_kInstallIdKey, _installId!);
      }
    } catch (_) {
      _installId = _generateUuid();
    }
    return _installId!;
  }

  // ---------------------------------------------------------------------------
  // Backend management
  // ---------------------------------------------------------------------------

  /// Replace the active backend (e.g. switch from Local to Remote).
  Future<void> setBackend(AnalyticsBackend backend) async {
    _backend = backend;
    await _backend.initialize();
  }

  AnalyticsBackend get backend => _backend;

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Strip potential file paths from error messages to avoid leaking
  /// user data. Removes absolute path patterns.
  static String _sanitizeErrorMessage(String message) {
    // Remove Unix-style paths: /path/to/something
    var result = message.replaceAll(RegExp(r'(/[^\s,;:]+)+'), '[path]');
    // Remove Windows-style paths: C:\path\to\something
    result = result.replaceAll(
        RegExp(r'[A-Za-z]:\\[^\s,;:]+'), '[path]');
    // Remove home-relative paths: ~/something
    result = result.replaceAll(RegExp(r'~(/[^\s,;:]*)+'), '[path]');
    return result;
  }

  /// Return a short stack trace summary (first 500 characters, no paths).
  static String _summarizeStackTrace(String stackTrace) {
    var summary = stackTrace.length > 500
        ? '${stackTrace.substring(0, 500)}...'
        : stackTrace;
    summary = _sanitizeErrorMessage(summary);
    return summary;
  }
}
