import 'terminal_arrangement.dart';

/// The last recoverable terminal layout and the user's recovery preferences.
///
/// A snapshot contains only the same validated, credential-free destination
/// metadata as a named arrangement. It cannot restore a process, connection,
/// working-directory grant, output buffer, command or broadcast membership.
class TerminalWorkspaceRecoveryRecord {
  TerminalWorkspaceRecoveryRecord({
    this.enabled = false,
    this.relaunchLocalShells = false,
    this.snapshot,
    DateTime? savedAt,
  }) : savedAt = savedAt?.toUtc() {
    if ((snapshot == null) != (savedAt == null) ||
        (savedAt != null &&
            (savedAt.millisecondsSinceEpoch < 0 ||
                savedAt.millisecondsSinceEpoch > maximumTimestamp))) {
      throw const FormatException('Invalid terminal recovery timestamp');
    }
  }

  const TerminalWorkspaceRecoveryRecord.disabled()
    : enabled = false,
      relaunchLocalShells = false,
      snapshot = null,
      savedAt = null;

  static const version = 1;
  static const maximumTimestamp = 253402300799999;

  final bool enabled;
  final bool relaunchLocalShells;
  final TerminalArrangement? snapshot;
  final DateTime? savedAt;

  Map<String, Object?> toJson() => {
    'version': version,
    'enabled': enabled,
    'relaunchLocalShells': relaunchLocalShells,
    if (snapshot != null) 'snapshot': snapshot!.toJson(),
    if (savedAt != null) 'savedAt': savedAt!.millisecondsSinceEpoch,
  };

  factory TerminalWorkspaceRecoveryRecord.fromJson(Map<String, dynamic> value) {
    if (value['version'] is! int || value['version'] != version) {
      throw const FormatException('Unsupported terminal recovery store');
    }
    final enabled = value['enabled'];
    final relaunch = value['relaunchLocalShells'];
    final snapshot = value['snapshot'];
    final savedAt = value['savedAt'];
    if (enabled is! bool ||
        relaunch is! bool ||
        (snapshot != null && snapshot is! Map<String, dynamic>) ||
        (savedAt != null &&
            (savedAt is! int || savedAt < 0 || savedAt > maximumTimestamp)) ||
        ((snapshot == null) != (savedAt == null))) {
      throw const FormatException('Invalid terminal recovery store');
    }
    return TerminalWorkspaceRecoveryRecord(
      enabled: enabled,
      relaunchLocalShells: relaunch,
      snapshot: snapshot == null
          ? null
          : TerminalArrangement.fromJson(
              snapshot as Map<String, dynamic>,
              requireLayout: true,
            ),
      savedAt: savedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(savedAt as int, isUtc: true),
    );
  }
}
