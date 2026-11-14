import 'dart:async';
import 'dart:convert';

import 'package:crisp_storage/crisp_storage.dart'
    show
        TransferBandwidthAllocator,
        TransferBandwidthLimits,
        TransferBandwidthSnapshot;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:crisp_storage/crisp_storage.dart'
    show TransferBandwidthLimits, TransferBandwidthSnapshot;

enum TransferBandwidthSettingsFailure { load, save, disposed }

class TransferBandwidthSettingsException implements Exception {
  const TransferBandwidthSettingsException(this.failure);

  final TransferBandwidthSettingsFailure failure;

  @override
  String toString() => 'Transfer bandwidth settings: ${failure.name}';
}

/// Owns the foreground runtime's allocator and its durable, paired policy.
///
/// Queue admission awaits [ready]. Unreadable settings fail that future rather
/// than silently admitting transfers without a previously selected limit.
/// Explicitly saving valid values, or a successful [retryLoad], restores it.
class TransferBandwidthController extends ChangeNotifier {
  TransferBandwidthController({
    TransferBandwidthAllocator? allocator,
    Future<String?> Function()? readSettings,
    Future<bool> Function(String value)? writeSettings,
  }) : allocator = allocator ?? TransferBandwidthAllocator(),
       _readSettings = readSettings ?? _readPreferences,
       _writeSettings = writeSettings ?? _writePreferences {
    _snapshot = this.allocator.snapshot;
    _subscription = this.allocator.changes.listen((_) => _changed());
    _ready = _enqueue(_restore);
  }

  static const preferencesKey = 'commander_transfer_bandwidth_v1';
  static const _uiInterval = Duration(milliseconds: 250);

  final TransferBandwidthAllocator allocator;
  final Future<String?> Function() _readSettings;
  final Future<bool> Function(String value) _writeSettings;
  late final StreamSubscription<void> _subscription;
  late Future<void> _ready;
  Future<void> _tail = Future<void>.value();
  late TransferBandwidthSnapshot _snapshot;
  Timer? _updates;
  bool _dirty = false;
  int _quietTicks = 0;
  bool _disposed = false;
  bool _loading = true;
  bool _loaded = false;
  Object? _loadError;

  Future<void> get ready => _ready;
  bool get isReady => _loaded && !_disposed;
  bool get isLoading => _loading;
  Object? get loadError => _loadError;
  TransferBandwidthLimits get limits => allocator.limits;
  TransferBandwidthSnapshot get snapshot => _snapshot;

  static Future<String?> _readPreferences() async =>
      (await SharedPreferences.getInstance()).getString(preferencesKey);

  static Future<bool> _writePreferences(String value) async =>
      (await SharedPreferences.getInstance()).setString(preferencesKey, value);

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _tail.then((_) async {
      _checkOpen();
      await action();
    });
    // Observe each error even when a settings-only surface is the first owner.
    // Callers still receive the original failing future; a failed write does
    // not poison later explicit retries or saves.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _checkOpen() {
    if (_disposed) {
      throw const TransferBandwidthSettingsException(
        TransferBandwidthSettingsFailure.disposed,
      );
    }
  }

  Future<void> _restore() async {
    try {
      final encoded = await _readSettings();
      _checkOpen();
      var loaded = const TransferBandwidthLimits();
      if (encoded != null) {
        final json = jsonDecode(encoded);
        if (json is! Map<String, dynamic> ||
            json['version'] != 1 ||
            json['uploadBytesPerSecond'] is! int ||
            json['downloadBytesPerSecond'] is! int) {
          throw const FormatException('Invalid transfer bandwidth policy.');
        }
        loaded = TransferBandwidthLimits(
          uploadBytesPerSecond: json['uploadBytesPerSecond'] as int,
          downloadBytesPerSecond: json['downloadBytesPerSecond'] as int,
        );
        loaded.validate();
      }
      allocator.updateLimits(loaded);
      _loaded = true;
      _loadError = null;
    } catch (error) {
      if (!_disposed) {
        _loaded = false;
        _loadError = error;
      }
      throw const TransferBandwidthSettingsException(
        TransferBandwidthSettingsFailure.load,
      );
    } finally {
      _loading = false;
      _publish();
    }
  }

  Future<void> retryLoad() {
    _checkOpen();
    _loading = true;
    _loaded = false;
    _loadError = null;
    _ready = _enqueue(_restore);
    notifyListeners();
    return _ready;
  }

  /// Persist both directions atomically before changing active allocation.
  Future<void> updateLimits(TransferBandwidthLimits value) {
    value.validate();
    return _enqueue(() async {
      final encoded = jsonEncode({
        'version': 1,
        'uploadBytesPerSecond': value.uploadBytesPerSecond,
        'downloadBytesPerSecond': value.downloadBytesPerSecond,
      });
      try {
        if (!await _writeSettings(encoded)) {
          throw const TransferBandwidthSettingsException(
            TransferBandwidthSettingsFailure.save,
          );
        }
      } catch (_) {
        throw const TransferBandwidthSettingsException(
          TransferBandwidthSettingsFailure.save,
        );
      }
      _checkOpen();
      allocator.updateLimits(value);
      _loadError = null;
      _loading = false;
      _loaded = true;
      _ready = Future<void>.value();
      _publish();
    });
  }

  void _changed() {
    if (_disposed) return;
    _dirty = true;
    _updates ??= Timer.periodic(_uiInterval, (_) {
      if (_dirty) {
        _dirty = false;
        _quietTicks = 0;
      } else {
        _quietTicks++;
      }
      _publish();
      // A final idle second lets the allocator's recent-rate window decay.
      // No perpetual refresh timer runs when covered traffic has stopped.
      if (_quietTicks >= 4) {
        _updates?.cancel();
        _updates = null;
      }
    });
  }

  void _publish() {
    if (_disposed) return;
    _snapshot = allocator.snapshot;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _updates?.cancel();
    unawaited(_subscription.cancel());
    allocator.dispose();
    super.dispose();
  }
}

final transferBandwidthProvider =
    ChangeNotifierProvider<TransferBandwidthController>(
      (ref) => TransferBandwidthController(),
    );
