import 'credential_storage_config.dart';

/// Fixed, non-sensitive reasons safe to show before the profile is unlocked.
enum CredentialStorageRecoveryFailure {
  unavailable,
  selectionChanged,
  unsupported,
}

class CredentialStorageRecoveryException implements Exception {
  const CredentialStorageRecoveryException(this.reason);

  final CredentialStorageRecoveryFailure reason;

  @override
  String toString() => switch (reason) {
    CredentialStorageRecoveryFailure.unavailable =>
      'Access to the selected keychain could not be restored. Restore or unlock '
          'the original file, then retry.',
    CredentialStorageRecoveryFailure.selectionChanged => 'The credential storage selection changed. Retry to use the current selection.',
    CredentialStorageRecoveryFailure.unsupported =>
      'Access recovery is only available for the selected custom keychain.',
  };
}

/// Authorizes access repair for the existing profile's selected store only.
///
/// An unreadable App Lock policy cannot authorize a change of backend. This
/// service therefore has no operation that writes selection preferences, opens
/// a replacement store, creates a vault, migrates credentials, or resets a lock.
/// Fresh-profile setup and authenticated Settings remain separate flows.
///
/// [restoreAccess] must present a native access-grant picker restricted to the
/// original configured keychain, verify canonical existing-file identity before
/// saving a bookmark, and return false on cancellation. A generic picker that
/// merely returns a different path does not satisfy this contract. If a file
/// has disappeared and its identity cannot be verified, it must be restored to
/// the configured location first.
class CredentialStorageRecovery {
  CredentialStorageRecovery({
    required this.failedSelection,
    required this.supportsCustomKeychains,
    required Future<bool> Function(String originalPath) restoreAccess,
    Future<CredentialStorageSelection> Function()? readSelection,
  }) : _restoreAccess = restoreAccess,
       _readSelection = readSelection ?? CredentialStorageConfig.readSelection;

  final CredentialStorageSelection failedSelection;
  final bool supportsCustomKeychains;
  final Future<bool> Function(String originalPath) _restoreAccess;
  final Future<CredentialStorageSelection> Function() _readSelection;

  /// Only a selected macOS file keychain can receive a new sandbox bookmark.
  /// Default OS stores use their normal OS unlock/repair UI followed by Retry.
  bool get canRestoreKeychainAccess {
    final path = failedSelection.customKeychainPath;
    return supportsCustomKeychains &&
        (failedSelection.mode ?? CredentialStorageMode.systemKeychain) ==
            CredentialStorageMode.systemKeychain &&
        path != null &&
        path.isNotEmpty &&
        path.trim() == path &&
        !path.contains('\u0000');
  }

  /// Grants access to the original store, then lets startup retry it normally.
  /// Success does not authorize bypassing that store's App Lock check.
  Future<bool> restoreKeychainAccess() async {
    if (!canRestoreKeychainAccess) {
      throw const CredentialStorageRecoveryException(
        CredentialStorageRecoveryFailure.unsupported,
      );
    }
    await _requireUnchangedSelection();
    final bool restored;
    try {
      restored = await _restoreAccess(failedSelection.customKeychainPath!);
    } catch (_) {
      // Platform exceptions can contain paths, account names, and arbitrary
      // native details. None of those cross the unauthenticated recovery UI.
      throw const CredentialStorageRecoveryException(
        CredentialStorageRecoveryFailure.unavailable,
      );
    }
    // A settings change or another process may race with the native picker.
    // Never restore a stale selection or treat the new one as authenticated.
    await _requireUnchangedSelection();
    return restored;
  }

  Future<void> _requireUnchangedSelection() async {
    final CredentialStorageSelection current;
    try {
      current = await _readSelection();
    } catch (_) {
      throw const CredentialStorageRecoveryException(
        CredentialStorageRecoveryFailure.unavailable,
      );
    }
    if (current.mode != failedSelection.mode ||
        current.customKeychainPath != failedSelection.customKeychainPath ||
        current.createFileVault != failedSelection.createFileVault) {
      throw const CredentialStorageRecoveryException(
        CredentialStorageRecoveryFailure.selectionChanged,
      );
    }
  }
}
