import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/terminal_arrangement.dart';
import '../models/terminal_workspace_recovery.dart';

export '../models/terminal_workspace_recovery.dart';

/// A mount's exclusive authority to update the remembered terminal workspace.
/// Acquiring another lease supersedes this one, including queued writes.
class TerminalWorkspaceRecoveryLease {
  TerminalWorkspaceRecoveryLease._(this._authority);

  final _RecoveryAuthority _authority;
  bool _closed = false;

  bool get isCurrent => !_closed && identical(_authority.activeLease, this);

  /// Synchronous revocation prevents pending readers from publishing a write.
  /// An already-started backend write settles before a new owner's operation.
  void close() {
    if (_closed) return;
    _closed = true;
    if (identical(_authority.activeLease, this)) {
      _authority.activeLease = null;
    }
  }
}

class TerminalWorkspaceRecoveryLeaseExpired implements Exception {
  const TerminalWorkspaceRecoveryLeaseExpired();

  @override
  String toString() => 'Terminal workspace recovery owner has changed.';
}

/// One versioned preference value, independent of explicitly named layouts.
///
/// Mutations run in invocation order and reread the store before changing it.
/// Corrupt/newer bytes remain intact until the user explicitly calls [forget].
/// Default-backed instances share both the queue and exclusive mount authority.
class TerminalWorkspaceRecovery {
  TerminalWorkspaceRecovery({
    Future<String?> Function()? read,
    Future<void> Function(String value)? write,
    DateTime Function()? clock,
    this.readTimeout = const Duration(seconds: 3),
  }) : _read = read ?? _readPreferences,
       _write = write ?? _writePreferences,
       _clock = clock ?? DateTime.now,
       _authority = read == null
           ? _preferencesAuthority
           : _RecoveryAuthority() {
    if ((read == null) != (write == null)) {
      throw ArgumentError('Supply both terminal recovery storage callbacks');
    }
    if (readTimeout <= Duration.zero) {
      throw ArgumentError('Terminal recovery read timeout must be positive');
    }
  }

  static const preferencesKey = 'terminal_workspace_recovery_v1';
  static const maximumStorageLength = 128 * 1024;
  static final _preferencesAuthority = _RecoveryAuthority();

  final Future<String?> Function() _read;
  final Future<void> Function(String value) _write;
  final DateTime Function() _clock;
  final _RecoveryAuthority _authority;

  /// A stalled read must not indefinitely block retries or an explicit reset.
  /// Writes remain serialized until they settle: timing them out would allow
  /// a late backend write to overwrite a newer owner's checkpoint.
  final Duration readTimeout;

  static Future<String?> _readPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getString(preferencesKey);
  }

  static Future<void> _writePreferences(String value) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(preferencesKey, value)) {
      throw StateError('Terminal recovery storage failed');
    }
  }

  TerminalWorkspaceRecoveryLease acquireLease() {
    final lease = TerminalWorkspaceRecoveryLease._(_authority);
    _authority.activeLease = lease;
    return lease;
  }

  Future<TerminalWorkspaceRecoveryRecord> load() => _authority.enqueue(_load);

  Future<TerminalWorkspaceRecoveryRecord> _load() async {
    final raw = await _read().timeout(readTimeout);
    if (raw == null) {
      return const TerminalWorkspaceRecoveryRecord.disabled();
    }
    if (raw.length > maximumStorageLength) {
      throw const FormatException('Terminal recovery store exceeds limit');
    }
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid terminal recovery store');
    }
    return TerminalWorkspaceRecoveryRecord.fromJson(data);
  }

  /// Disabling stops automatic saves and preserves the last saved layout.
  /// [forget] also removes that layout and resets both preferences.
  Future<TerminalWorkspaceRecoveryRecord> configure({
    required TerminalWorkspaceRecoveryLease lease,
    required bool enabled,
    required bool relaunchLocalShells,
  }) {
    if (!_owns(lease)) return _expired();
    // A save issued before this setting change must not publish after it,
    // even if it is waiting for a slow backend read.
    _authority.configurationRevision++;
    return _authority.enqueue(() async {
      _requireOwner(lease);
      final previous = await _load();
      _requireOwner(lease);
      if (previous.enabled == enabled &&
          previous.relaunchLocalShells == relaunchLocalShells) {
        return previous;
      }
      final next = TerminalWorkspaceRecoveryRecord(
        enabled: enabled,
        relaunchLocalShells: relaunchLocalShells,
        snapshot: previous.snapshot,
        savedAt: previous.savedAt,
      );
      await _persist(next, lease);
      return next;
    });
  }

  /// Save an already-sanitized arrangement if this owner and configuration are
  /// still current. Superseded configuration saves return the current record.
  /// A caller that debounces should cancel its timer on configuration changes,
  /// because an invocation made later is a new request, regardless of its data.
  Future<TerminalWorkspaceRecoveryRecord> save(
    TerminalArrangement snapshot, {
    required TerminalWorkspaceRecoveryLease lease,
  }) {
    if (!_owns(lease)) return _expired();
    final revision = _authority.configurationRevision;
    return _authority.enqueue(() async {
      _requireOwner(lease);
      final previous = await _load();
      _requireOwner(lease);
      if (!previous.enabled || revision != _authority.configurationRevision) {
        return previous;
      }
      final next = _withSnapshot(previous, snapshot);
      if (identical(next, previous)) return previous;
      await _persist(next, lease);
      return next;
    });
  }

  /// Seal the final checkpoint before relinquishing an app-owned workspace.
  ///
  /// Authority is verified and the lease closed synchronously. This one write
  /// is queued before a subsequent owner's load or mutation, so a rapid remount
  /// sees the final layout rather than only the previous debounced checkpoint.
  /// A later setting change or explicit forget still invalidates the snapshot.
  /// No further operation can be authorized with the finished lease.
  Future<TerminalWorkspaceRecoveryRecord> finish(
    TerminalArrangement snapshot, {
    required TerminalWorkspaceRecoveryLease lease,
  }) {
    if (!_owns(lease)) return _expired();
    final revision = _authority.configurationRevision;
    final result = _authority.enqueue(() async {
      // This operation has sealed authority. It must not use _requireOwner:
      // the next mount may already own the service, but its operations remain
      // behind this one in the same strict invocation-order queue.
      final previous = await _load();
      if (!previous.enabled || revision != _authority.configurationRevision) {
        return previous;
      }
      final next = _withSnapshot(previous, snapshot);
      if (identical(next, previous)) return previous;
      await _write(_encode(next));
      return next;
    });
    lease.close();
    return result;
  }

  /// Explicit destructive reset, including corrupt or unknown-version data.
  /// This is the only write that deliberately does not parse the old value.
  Future<TerminalWorkspaceRecoveryRecord> forget({
    required TerminalWorkspaceRecoveryLease lease,
  }) {
    if (!_owns(lease)) return _expired();
    _authority.configurationRevision++;
    return _authority.enqueue(() async {
      _requireOwner(lease);
      const next = TerminalWorkspaceRecoveryRecord.disabled();
      await _persist(next, lease);
      return next;
    });
  }

  Future<void> _persist(
    TerminalWorkspaceRecoveryRecord record,
    TerminalWorkspaceRecoveryLease lease,
  ) async {
    final encoded = _encode(record);
    _requireOwner(lease);
    await _write(encoded);
  }

  String _encode(TerminalWorkspaceRecoveryRecord record) {
    final encoded = jsonEncode(record.toJson());
    if (encoded.length > maximumStorageLength) {
      throw StateError('Terminal recovery store exceeds limit');
    }
    return encoded;
  }

  TerminalWorkspaceRecoveryRecord _withSnapshot(
    TerminalWorkspaceRecoveryRecord previous,
    TerminalArrangement snapshot,
  ) {
    if (previous.snapshot != null &&
        jsonEncode(previous.snapshot!.toJson()) ==
            jsonEncode(snapshot.toJson())) {
      return previous;
    }
    return TerminalWorkspaceRecoveryRecord(
      enabled: true,
      relaunchLocalShells: previous.relaunchLocalShells,
      snapshot: snapshot,
      savedAt: _clock(),
    );
  }

  bool _owns(TerminalWorkspaceRecoveryLease lease) =>
      identical(lease._authority, _authority) && lease.isCurrent;

  void _requireOwner(TerminalWorkspaceRecoveryLease lease) {
    if (!_owns(lease)) {
      throw const TerminalWorkspaceRecoveryLeaseExpired();
    }
  }

  Future<TerminalWorkspaceRecoveryRecord> _expired() =>
      Future.error(const TerminalWorkspaceRecoveryLeaseExpired());
}

class _RecoveryAuthority {
  Future<void> _tail = Future<void>.value();
  TerminalWorkspaceRecoveryLease? activeLease;
  int configurationRevision = 0;

  Future<T> enqueue<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    // A failed operation must not poison subsequent reads or explicit resets.
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }
}
