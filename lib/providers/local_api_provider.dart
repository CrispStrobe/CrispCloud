// lib/providers/local_api_provider.dart
//
// Riverpod providers for the Local REST API service (PLAN.md 9.4).
//
// Exposed providers:
//   localApiEnabledProvider  — bool toggle, persisted to SharedPreferences
//   localApiPortProvider     — int port number, persisted to SharedPreferences
//   localApiServiceProvider  — manages the LocalApiService lifecycle

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/local_api_service.dart';
import '../services/log_service.dart';

// ---------------------------------------------------------------------------
// localApiEnabledProvider
// ---------------------------------------------------------------------------

/// Whether the local REST API server is enabled.
/// Persisted to SharedPreferences under [kLocalApiEnabledKey].
final localApiEnabledProvider =
    StateNotifierProvider<LocalApiEnabledNotifier, bool>(
  (ref) => LocalApiEnabledNotifier(ref),
);

class LocalApiEnabledNotifier extends StateNotifier<bool> {
  static const _log = Log('LocalApiEnabledNotifier');
  final Ref _ref;

  LocalApiEnabledNotifier(this._ref) : super(false) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(kLocalApiEnabledKey) ?? false;
      state = enabled;
      // Sync the running service with the persisted state.
      if (enabled) {
        await _ref.read(localApiServiceProvider.notifier).ensureRunning();
      }
    } catch (e) {
      _log.warn('Failed to load localApiEnabled preference', e);
    }
  }

  /// Toggle the enabled state, persist it, and start/stop the server.
  Future<void> toggle() async {
    final next = !state;
    await setValue(next);
  }

  /// Set to a specific value, persist it, and start/stop the server.
  Future<void> setValue(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kLocalApiEnabledKey, enabled);
    } catch (e) {
      _log.warn('Failed to persist localApiEnabled', e);
    }

    final notifier = _ref.read(localApiServiceProvider.notifier);
    if (enabled) {
      await notifier.ensureRunning();
    } else {
      await notifier.ensureStopped();
    }
  }
}

// ---------------------------------------------------------------------------
// localApiPortProvider
// ---------------------------------------------------------------------------

/// Configurable port for the local REST API server.
/// Persisted to SharedPreferences under [kLocalApiPortKey].
final localApiPortProvider =
    StateNotifierProvider<LocalApiPortNotifier, int>(
  (ref) => LocalApiPortNotifier(),
);

class LocalApiPortNotifier extends StateNotifier<int> {
  static const _log = Log('LocalApiPortNotifier');

  LocalApiPortNotifier() : super(kLocalApiDefaultPort) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final port = prefs.getInt(kLocalApiPortKey) ?? kLocalApiDefaultPort;
      state = port.clamp(kLocalApiMinPort, kLocalApiMaxPort);
    } catch (e) {
      _log.warn('Failed to load localApiPort preference', e);
    }
  }

  /// Update the port and persist it.
  /// Returns false if [port] is out of range (no change applied).
  Future<bool> setPort(int port) async {
    if (port < kLocalApiMinPort || port > kLocalApiMaxPort) {
      _log.warn('Invalid port: $port');
      return false;
    }
    state = port;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kLocalApiPortKey, port);
    } catch (e) {
      _log.warn('Failed to persist localApiPort', e);
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// localApiServiceProvider
// ---------------------------------------------------------------------------

/// Manages the [LocalApiService] lifecycle.
/// The service is started/stopped via [LocalApiServiceNotifier].
final localApiServiceProvider =
    StateNotifierProvider<LocalApiServiceNotifier, LocalApiServiceState>(
  (ref) => LocalApiServiceNotifier(ref),
);

/// Snapshot of service state exposed to the UI.
class LocalApiServiceState {
  final bool running;
  final int port;
  final String? token;
  final String? error;

  const LocalApiServiceState({
    required this.running,
    required this.port,
    this.token,
    this.error,
  });

  LocalApiServiceState copyWith({
    bool? running,
    int? port,
    String? token,
    String? error,
  }) =>
      LocalApiServiceState(
        running: running ?? this.running,
        port: port ?? this.port,
        token: token ?? this.token,
        error: error,
      );
}

class LocalApiServiceNotifier
    extends StateNotifier<LocalApiServiceState> {
  static const _log = Log('LocalApiServiceNotifier');

  final Ref _ref;
  final LocalApiService _service;

  LocalApiServiceNotifier(this._ref)
      : _service = LocalApiService(),
        super(const LocalApiServiceState(
          running: false,
          port: kLocalApiDefaultPort,
        ));

  LocalApiService get service => _service;

  /// Start the server if not already running. Uses the configured port.
  Future<void> ensureRunning() async {
    if (kIsWeb) {
      state = state.copyWith(
        running: false,
        error: 'Local API is not supported on web',
      );
      return;
    }
    if (_service.isRunning) return;

    final port = _ref.read(localApiPortProvider);
    try {
      final token = await _service.getOrCreateToken();
      final started = await _service.start(port: port);
      if (started) {
        state = state.copyWith(
          running: true,
          port: port,
          token: token,
          error: null,
        );
        _log.info('Local API started', {'port': port});
      }
    } catch (e, st) {
      _log.error('Failed to start Local API', e, st);
      state = state.copyWith(
        running: false,
        error: e.toString(),
      );
    }
  }

  /// Stop the server if running.
  Future<void> ensureStopped() async {
    if (!_service.isRunning) return;
    try {
      await _service.stop();
      state = state.copyWith(running: false, error: null);
      _log.info('Local API stopped');
    } catch (e, st) {
      _log.error('Failed to stop Local API', e, st);
      state = state.copyWith(error: e.toString());
    }
  }

  /// Rotate the API token and return the new token.
  Future<String> rotateToken() async {
    final token = await _service.rotateToken();
    state = state.copyWith(token: token);
    _log.info('Local API token rotated');
    return token;
  }
}
