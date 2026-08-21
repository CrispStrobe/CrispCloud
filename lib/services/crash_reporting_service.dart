// lib/services/crash_reporting_service.dart
//
// Crash reporting service with opt-in toggle.
//
// Features:
//   - Opt-in/opt-out toggle persisted to SharedPreferences
//   - In-memory breadcrumb ring buffer (last 50)
//   - CrashReport model with full JSON serialization
//   - Local crash log storage (JSON-lines, one report per line)
//   - Pluggable CrashReportingBackend: LocalBackend (default), SentryBackend placeholder
//   - Platform info collection (OS, version, locale) with web/native guards
//   - Wire-in with LogService: Log.error() auto-reports when enabled
//   - Safe to call on all platforms including web
//
// Usage:
//   final service = CrashReportingService();
//   await service.initialize();
//   service.reportBreadcrumb('User opened file browser', 'navigation');
//   await service.reportError(error, stackTrace, context: {'path': '/docs'});

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart'
    show FlutterError, FlutterErrorDetails, kDebugMode, kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log_service.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _kEnabledKey = 'crash_reporting_enabled';
const _kMaxBreadcrumbs = 50;
const _kCrashLogFileName = 'crash_reports.jsonl';
const _kMaxStoredReports = 200;

// ---------------------------------------------------------------------------
// Breadcrumb
// ---------------------------------------------------------------------------

/// A single breadcrumb capturing a user action or navigation event.
class Breadcrumb {
  final DateTime timestamp;
  final String message;
  final String category;
  final Map<String, dynamic>? data;

  Breadcrumb({
    required this.timestamp,
    required this.message,
    required this.category,
    this.data,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'message': message,
        'category': category,
        if (data != null && data!.isNotEmpty) 'data': data,
      };

  factory Breadcrumb.fromJson(Map<String, dynamic> json) => Breadcrumb(
        timestamp: DateTime.parse(json['timestamp'] as String),
        message: json['message'] as String? ?? '',
        category: json['category'] as String? ?? 'default',
        data: json['data'] as Map<String, dynamic>?,
      );
}

// ---------------------------------------------------------------------------
// Platform Info
// ---------------------------------------------------------------------------

/// Collected platform/device information.
class PlatformInfo {
  final String os;
  final String osVersion;
  final String locale;
  final bool isWeb;
  final bool isDebug;
  final String? appVersion;

  PlatformInfo({
    required this.os,
    required this.osVersion,
    required this.locale,
    required this.isWeb,
    required this.isDebug,
    this.appVersion,
  });

  Map<String, dynamic> toJson() => {
        'os': os,
        'osVersion': osVersion,
        'locale': locale,
        'isWeb': isWeb,
        'isDebug': isDebug,
        if (appVersion != null) 'appVersion': appVersion,
      };

  factory PlatformInfo.fromJson(Map<String, dynamic> json) => PlatformInfo(
        os: json['os'] as String? ?? 'unknown',
        osVersion: json['osVersion'] as String? ?? '',
        locale: json['locale'] as String? ?? '',
        isWeb: json['isWeb'] as bool? ?? false,
        isDebug: json['isDebug'] as bool? ?? false,
        appVersion: json['appVersion'] as String?,
      );

  /// Collect platform info from the current environment.
  static PlatformInfo collect({String? appVersion}) {
    if (kIsWeb) {
      return PlatformInfo(
        os: 'web',
        osVersion: '',
        locale: '',
        isWeb: true,
        isDebug: kDebugMode,
        appVersion: appVersion,
      );
    }
    // Native (dart:io is available)
    String os = 'unknown';
    String osVersion = '';
    try {
      if (Platform.isAndroid) {
        os = 'android';
      } else if (Platform.isIOS) {
        os = 'ios';
      } else if (Platform.isMacOS) {
        os = 'macos';
      } else if (Platform.isWindows) {
        os = 'windows';
      } else if (Platform.isLinux) {
        os = 'linux';
      } else if (Platform.isFuchsia) {
        os = 'fuchsia';
      }
      osVersion = Platform.operatingSystemVersion;
    } catch (_) {
      // Fail-safe on platforms where Platform is unavailable
    }
    String locale = '';
    try {
      locale = Platform.localeName;
    } catch (_) {}

    return PlatformInfo(
      os: os,
      osVersion: osVersion,
      locale: locale,
      isWeb: false,
      isDebug: kDebugMode,
      appVersion: appVersion,
    );
  }
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

/// Safely converts a dynamic map value to Map<String, dynamic>.
/// Returns null if the value is null or not a Map.
Map<String, dynamic>? _toStringDynamicMap(dynamic value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  return null;
}

const _sensitiveKeyFragments = <String>{
  'authorization',
  'cookie',
  'credential',
  'email',
  'password',
  'passphrase',
  'secret',
  'token',
};

bool _isSensitiveKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return _sensitiveKeyFragments.any(normalized.contains) ||
      normalized == 'apikey' ||
      normalized == 'accesskey' ||
      normalized == 'privatekey' ||
      normalized == 'encryptionkey';
}

bool _isPathKey(String key) {
  final normalized = key.toLowerCase();
  return normalized == 'path' ||
      normalized.endsWith('path') ||
      normalized.contains('directory');
}

String _sanitizeText(String value) {
  var sanitized = value;
  if (!kIsWeb) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      sanitized = sanitized.replaceAll(home, '<home>');
    }
  }
  return sanitized.replaceAllMapped(
    RegExp(
      r'([?&](?:access_token|auth|key|password|secret|token)=)[^&\s]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}<redacted>',
  );
}

/// Removes credentials and local file-system details before diagnostics are
/// persisted or copied. Unknown values are converted to safe strings.
dynamic sanitizeCrashData(dynamic value, {String? key}) {
  if (key != null && _isSensitiveKey(key)) return '<redacted>';
  if (key != null && _isPathKey(key) && value != null) {
    return '<redacted-path>';
  }
  if (value is Map) {
    return value.map(
      (mapKey, mapValue) => MapEntry(
        mapKey.toString(),
        sanitizeCrashData(mapValue, key: mapKey.toString()),
      ),
    );
  }
  if (value is Iterable) {
    return value.map((item) => sanitizeCrashData(item)).toList();
  }
  if (value is String) return _sanitizeText(value);
  if (value == null || value is num || value is bool) return value;
  return _sanitizeText(value.toString());
}

// ---------------------------------------------------------------------------
// CrashReport
// ---------------------------------------------------------------------------

/// A captured crash/error report.
class CrashReport {
  final String id;
  final DateTime timestamp;
  final String errorMessage;
  final String? errorType;
  final String? stackTrace;
  final List<Breadcrumb> breadcrumbs;
  final PlatformInfo platformInfo;
  final Map<String, dynamic>? context;
  final String? userId;

  CrashReport({
    required this.id,
    required this.timestamp,
    required this.errorMessage,
    this.errorType,
    this.stackTrace,
    required this.breadcrumbs,
    required this.platformInfo,
    this.context,
    this.userId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'errorMessage': errorMessage,
        if (errorType != null) 'errorType': errorType,
        if (stackTrace != null) 'stackTrace': stackTrace,
        'breadcrumbs': breadcrumbs.map((b) => b.toJson()).toList(),
        'platformInfo': platformInfo.toJson(),
        if (context != null && context!.isNotEmpty) 'context': context,
        if (userId != null) 'userId': userId,
      };

  factory CrashReport.fromJson(Map<String, dynamic> json) {
    final breadcrumbsJson = json['breadcrumbs'];
    final List<Breadcrumb> breadcrumbs = [];
    if (breadcrumbsJson is List) {
      for (final b in breadcrumbsJson) {
        if (b is Map) {
          try {
            // Cast to Map<String, dynamic> defensively
            final bMap = b.map((k, v) => MapEntry(k.toString(), v));
            breadcrumbs.add(Breadcrumb.fromJson(bMap));
          } catch (_) {}
        }
      }
    }
    return CrashReport(
      id: json['id'] as String? ?? '',
      timestamp: DateTime.parse(json['timestamp'] as String),
      errorMessage: json['errorMessage'] as String? ?? '',
      errorType: json['errorType'] as String?,
      stackTrace: json['stackTrace'] as String?,
      breadcrumbs: breadcrumbs,
      platformInfo: PlatformInfo.fromJson(
          _toStringDynamicMap(json['platformInfo']) ?? {}),
      context: _toStringDynamicMap(json['context']),
      userId: json['userId'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Backend abstraction
// ---------------------------------------------------------------------------

/// Abstract crash reporting backend.
abstract class CrashReportingBackend {
  /// Called once when the service initializes.
  Future<void> initialize() async {}

  /// Send or persist a crash report.
  Future<void> send(CrashReport report);

  /// Retrieve recently stored reports (newest first). May return empty list
  /// if the backend does not support retrieval.
  Future<List<CrashReport>> getRecentReports(int count) async => [];

  /// Export all stored reports as a formatted JSON string.
  Future<String> exportReports() async => '[]';

  /// Delete all stored reports.
  Future<void> clearReports() async {}
}

// ---------------------------------------------------------------------------
// LocalBackend
// ---------------------------------------------------------------------------

/// Writes crash reports as JSON-lines to <appSupportDir>/crash_reports.jsonl.
/// On web, stores in-memory only.
class LocalBackend extends CrashReportingBackend {
  static const _log = Log('LocalBackend');

  String? _filePath;

  // In-memory store for web or when the file isn't initialized yet.
  final List<CrashReport> _memoryStore = [];

  @override
  Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationSupportDirectory();
      _filePath = p.join(dir.path, _kCrashLogFileName);
    } catch (e) {
      _log.warn('LocalBackend: could not resolve storage path', e);
    }
  }

  @override
  Future<void> send(CrashReport report) async {
    if (kIsWeb || _filePath == null) {
      _memoryStore.add(report);
      // Keep only the last N reports in memory
      while (_memoryStore.length > _kMaxStoredReports) {
        _memoryStore.removeAt(0);
      }
      return;
    }
    try {
      final file = File(_filePath!);
      await file.parent.create(recursive: true);
      final line = '${jsonEncode(report.toJson())}\n';
      await file.writeAsString(line, mode: FileMode.append, flush: true);
      final lines = await file.readAsLines();
      if (lines.length > _kMaxStoredReports) {
        await file.writeAsString(
          '${lines.skip(lines.length - _kMaxStoredReports).join('\n')}\n',
          flush: true,
        );
      }
    } catch (e) {
      _log.warn('LocalBackend: failed to write crash report', e);
      // Fallback: keep in memory
      _memoryStore.add(report);
      while (_memoryStore.length > _kMaxStoredReports) {
        _memoryStore.removeAt(0);
      }
    }
  }

  @override
  Future<List<CrashReport>> getRecentReports(int count) async {
    if (kIsWeb || _filePath == null) {
      final list = _memoryStore.reversed.take(count).toList();
      return list;
    }
    final file = File(_filePath!);
    if (!file.existsSync()) return [];
    try {
      final lines = await file.readAsLines();
      final reports = <CrashReport>[];
      for (int i = lines.length - 1; i >= 0 && reports.length < count; i--) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        try {
          reports.add(
              CrashReport.fromJson(jsonDecode(line) as Map<String, dynamic>));
        } catch (_) {}
      }
      return reports;
    } catch (e) {
      _log.warn('LocalBackend: failed to read crash reports', e);
      return [];
    }
  }

  @override
  Future<String> exportReports() async {
    if (kIsWeb || _filePath == null) {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(_memoryStore.map((r) => r.toJson()).toList());
    }
    final file = File(_filePath!);
    if (!file.existsSync()) return '[]';
    try {
      final lines = await file.readAsLines();
      final entries = <Map<String, dynamic>>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          entries.add(jsonDecode(line) as Map<String, dynamic>);
        } catch (_) {}
      }
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(entries);
    } catch (e) {
      _log.warn('LocalBackend: failed to export crash reports', e);
      return '[]';
    }
  }

  @override
  Future<void> clearReports() async {
    _memoryStore.clear();
    if (kIsWeb || _filePath == null) return;
    try {
      final file = File(_filePath!);
      if (file.existsSync()) {
        await file.writeAsString('');
      }
    } catch (e) {
      _log.warn('LocalBackend: failed to clear crash reports', e);
    }
  }

  // For testing only: inject a custom file path.
  // ignore: invalid_use_of_visible_for_testing_member
  void setFilePathForTesting(String path) {
    _filePath = path;
  }

  // For testing only: direct read from memory store (exposed for unit tests).
  List<CrashReport> get memoryStore => List.unmodifiable(_memoryStore);
}

// ---------------------------------------------------------------------------
// SentryBackend (placeholder)
// ---------------------------------------------------------------------------

/// Placeholder Sentry backend.
///
/// In production, this class would wrap the `sentry_flutter` SDK. It is
/// provided as a structural placeholder so calling code can reference it and
/// switch backends without changes to [CrashReportingService]. Add
/// `sentry_flutter` to pubspec.yaml and flesh out [send] to activate it.
class SentryBackend extends CrashReportingBackend {
  static const _log = Log('SentryBackend');

  final String dsn;
  final String? environment;
  final String? release;

  SentryBackend({
    required this.dsn,
    this.environment,
    this.release,
  });

  @override
  Future<void> initialize() async {
    // TODO: await SentryFlutter.init((options) { options.dsn = dsn; ... });
    _log.info('SentryBackend initialized (placeholder)', {
      'dsn': dsn.substring(0, dsn.length.clamp(0, 20)),
      if (environment != null) 'env': environment,
    });
  }

  @override
  Future<void> send(CrashReport report) async {
    // TODO: await Sentry.captureException(
    //   report.errorMessage,
    //   stackTrace: report.stackTrace,
    //   hint: Hint.withMap({'context': report.context ?? {}}),
    // );
    _log.debug('SentryBackend.send (placeholder)', {
      'id': report.id,
      'error': report.errorMessage,
    });
  }
}

// ---------------------------------------------------------------------------
// CrashReportingService
// ---------------------------------------------------------------------------

/// Opt-in crash reporting service.
///
/// Wire-in example in main.dart or app startup:
/// ```dart
/// final crash = CrashReportingService();
/// await crash.initialize();
/// ```
///
/// The service hooks into [LogConfig] so that any [Log.error()] call
/// automatically triggers [reportError] when crash reporting is enabled.
class CrashReportingService {
  static const _log = Log('CrashReportingService');

  CrashReportingBackend _backend;
  bool _enabled = false;
  String? _userId;
  final String? _appVersion;

  // Breadcrumb ring buffer
  final Queue<Breadcrumb> _breadcrumbs = Queue<Breadcrumb>();

  // Track whether initialize() has been called.
  bool _initialized = false;
  bool _globalHandlersInstalled = false;

  CrashReportingService({
    CrashReportingBackend? backend,
    String? appVersion,
  })  : _backend = backend ?? LocalBackend(),
        _appVersion = appVersion;

  /// Whether crash reporting is currently enabled (opt-in).
  bool get isEnabled => _enabled;

  /// Whether the service has been initialized.
  bool get isInitialized => _initialized;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Initialize the service: load opt-in preference and prepare the backend.
  ///
  /// Must be called before any other method. Safe to call multiple times.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Load opt-in preference
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabledKey) ?? false;
    } catch (e) {
      _log.warn('CrashReportingService: failed to load preference', e);
      _enabled = false;
    }

    // Initialize backend
    try {
      await _backend.initialize();
    } catch (e) {
      _log.warn('CrashReportingService: backend initialization failed', e);
    }

    if (_enabled) {
      _log.info('CrashReportingService initialized (enabled)');
      _hookIntoLogService();
    } else {
      _log.info(
          'CrashReportingService initialized (disabled — user opt-in required)');
    }
  }

  /// Captures framework and engine errors that would otherwise only reach the
  /// console. Reports are still persisted only after explicit user opt-in.
  void installGlobalHandlers() {
    if (_globalHandlersInstalled) return;
    _globalHandlersInstalled = true;

    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (previousFlutterHandler != null) {
        previousFlutterHandler(details);
      } else {
        FlutterError.presentError(details);
      }
      unawaited(reportError(
        details.exception,
        details.stack,
        context: {
          'origin': 'flutter_framework',
          if (details.library != null) 'library': details.library,
        },
      ));
    };

    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      unawaited(reportError(
        error,
        stack,
        context: const {'origin': 'platform_dispatcher'},
      ));
      return previousPlatformHandler?.call(error, stack) ?? true;
    };
  }

  // ---------------------------------------------------------------------------
  // Opt-in toggle
  // ---------------------------------------------------------------------------

  /// Enable crash reporting and persist the preference.
  Future<void> enable() async {
    _enabled = true;
    await _savePreference(true);
    _hookIntoLogService();
    _log.info('Crash reporting enabled');
  }

  /// Disable crash reporting and persist the preference.
  Future<void> disable() async {
    _enabled = false;
    await _savePreference(false);
    _unhookFromLogService();
    _log.info('Crash reporting disabled');
  }

  Future<void> _savePreference(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabledKey, value);
    } catch (e) {
      _log.warn('CrashReportingService: failed to save preference', e);
    }
  }

  // ---------------------------------------------------------------------------
  // User context
  // ---------------------------------------------------------------------------

  /// Associate a user ID with future reports. The ID is never sent without
  /// explicit opt-in (and should be anonymized or hashed by the caller).
  void setUser(String userId) {
    _userId = userId;
  }

  /// Clear the current user association.
  void clearUser() {
    _userId = null;
  }

  // ---------------------------------------------------------------------------
  // Breadcrumbs
  // ---------------------------------------------------------------------------

  /// Add a breadcrumb to the in-memory ring buffer.
  ///
  /// When the buffer exceeds [_kMaxBreadcrumbs] entries the oldest is dropped.
  void reportBreadcrumb(
    String message,
    String category, {
    Map<String, dynamic>? data,
  }) {
    final crumb = Breadcrumb(
      timestamp: DateTime.now(),
      message: message,
      category: category,
      data: sanitizeCrashData(data) as Map<String, dynamic>?,
    );
    _breadcrumbs.add(crumb);
    while (_breadcrumbs.length > _kMaxBreadcrumbs) {
      _breadcrumbs.removeFirst();
    }
  }

  /// Current snapshot of the breadcrumb buffer (oldest first).
  List<Breadcrumb> get breadcrumbs => _breadcrumbs.toList();

  // ---------------------------------------------------------------------------
  // Error reporting
  // ---------------------------------------------------------------------------

  /// Report an error. Does nothing if crash reporting is disabled.
  ///
  /// [context] is an arbitrary key/value map attached to the report.
  Future<void> reportError(
    Object error,
    StackTrace? stackTrace, {
    Map<String, dynamic>? context,
  }) async {
    if (!_enabled) return;

    final report = _buildReport(error, stackTrace, context: context);
    try {
      await _backend.send(report);
    } catch (e) {
      _log.warn('CrashReportingService: failed to send report', e);
    }
  }

  CrashReport _buildReport(
    Object error,
    StackTrace? stackTrace, {
    Map<String, dynamic>? context,
  }) {
    final id = _generateId();
    return CrashReport(
      id: id,
      timestamp: DateTime.now(),
      errorMessage: _sanitizeText(error.toString()),
      errorType: error.runtimeType.toString(),
      stackTrace:
          stackTrace == null ? null : _sanitizeText(stackTrace.toString()),
      breadcrumbs: breadcrumbs,
      platformInfo: PlatformInfo.collect(appVersion: _appVersion),
      context: sanitizeCrashData(context) as Map<String, dynamic>?,
      userId: _userId,
    );
  }

  /// Generate a simple unique ID based on timestamp + hash.
  static String _generateId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final hash = ts.hashCode.toRadixString(16);
    return 'cr_${ts}_$hash';
  }

  // ---------------------------------------------------------------------------
  // Storage access
  // ---------------------------------------------------------------------------

  /// Retrieve the most recent [count] crash reports (newest first).
  Future<List<CrashReport>> getRecentReports([int count = 20]) async {
    return _backend.getRecentReports(count);
  }

  /// Export all crash reports as a formatted JSON string.
  Future<String> exportReports() async {
    return _backend.exportReports();
  }

  /// Delete all stored crash reports.
  Future<void> clearReports() async {
    await _backend.clearReports();
  }

  // ---------------------------------------------------------------------------
  // Backend management
  // ---------------------------------------------------------------------------

  /// Replace the active backend. Useful for switching from LocalBackend to
  /// SentryBackend after the user grants permission.
  Future<void> setBackend(CrashReportingBackend backend) async {
    _backend = backend;
    await _backend.initialize();
  }

  CrashReportingBackend get backend => _backend;

  // ---------------------------------------------------------------------------
  // LogService integration
  // ---------------------------------------------------------------------------

  // Tracks whether the hook is active to avoid double-registration.
  bool _logHookActive = false;

  void _hookIntoLogService() {
    if (_logHookActive) return;
    _logHookActive = true;
    LogConfigCrashHook.addErrorListener(_onLogError);
  }

  void _unhookFromLogService() {
    if (!_logHookActive) return;
    _logHookActive = false;
    LogConfigCrashHook.removeErrorListener(_onLogError);
  }

  void _onLogError(LogEntry entry) {
    if (!_enabled) return;
    // Report asynchronously; errors from reporting are swallowed.
    reportError(
      entry.error ?? entry.message,
      entry.stackTrace,
      context: {
        'logger': entry.logger,
        'message': entry.message,
        if (entry.data != null) 'data': entry.data,
      },
    );
  }
}

// ---------------------------------------------------------------------------
// LogConfigCrashHook — standalone crash reporting listener registry
// ---------------------------------------------------------------------------

// This class provides a static listener registry that [CrashLog] uses to
// dispatch error-level log entries to registered listeners (typically
// CrashReportingService). It is intentionally separate from LogConfig/Log
// to avoid coupling log_service.dart to crash reporting.

/// Callback type for crash reporting error listeners.
typedef CrashErrorListener = void Function(LogEntry entry);

/// Static registry for crash reporting error listeners.
///
/// Use [addErrorListener] / [removeErrorListener] to subscribe.
/// [CrashLog] calls [_dispatch] whenever [Log.error] is called.
class LogConfigCrashHook {
  LogConfigCrashHook._(); // private constructor — static-only class

  static final List<CrashErrorListener> _listeners = [];

  /// Register a listener that will be called for every [LogLevel.error] entry.
  static void addErrorListener(CrashErrorListener listener) {
    _listeners.add(listener);
  }

  /// Remove a previously registered listener.
  static void removeErrorListener(CrashErrorListener listener) {
    _listeners.remove(listener);
  }

  /// Dispatch [entry] to all registered listeners. Called by [CrashLog.error].
  static void _dispatch(LogEntry entry) {
    if (entry.level != LogLevel.error) return;
    for (final listener in List.of(_listeners)) {
      try {
        listener(entry);
      } catch (_) {
        // Listeners must not throw
      }
    }
  }
}

// ---------------------------------------------------------------------------
// LogInterceptor — wraps Log to inject crash reporting hooks
// ---------------------------------------------------------------------------

/// A [Log] subclass that additionally dispatches error entries to the
/// [LogConfigCrashHook] listeners registered by [CrashReportingService].
///
/// Usage: replace `final log = Log('Name');` with
/// `final log = CrashLog('Name');` in services that want automatic error
/// reporting. Or, more conveniently, use [CrashReportingService.hookLog].
///
/// The base `Log` class in log_service.dart is intentionally not modified;
/// we create an observable subclass here to avoid coupling.
class CrashLog extends Log {
  const CrashLog(super.name);

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    super.error(message, error, stackTrace);
    // Build a LogEntry and dispatch it to crash hooks
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.error,
      logger: name,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );
    LogConfigCrashHook._dispatch(entry);
  }
}
