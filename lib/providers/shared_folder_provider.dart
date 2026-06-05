// lib/providers/shared_folder_provider.dart
//
// Riverpod providers for shared folder management.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/cloud_storage_interface.dart';
import '../services/shared_folder_service.dart';
import 'auth_provider.dart';

// ---------------------------------------------------------------------------
// Singleton service provider
// ---------------------------------------------------------------------------

/// Singleton [SharedFolderService] shared across the app.
final sharedFolderServiceProvider = Provider<SharedFolderService>((ref) {
  return SharedFolderService();
});

// ---------------------------------------------------------------------------
// FutureProviders for folder listings
// ---------------------------------------------------------------------------

/// Provides the list of folders shared *by* the current user.
///
/// Automatically re-fetches when the authenticated client changes.
final sharedFoldersProvider =
    FutureProvider.autoDispose<List<SharedFolder>>((ref) async {
  final auth = ref.watch(authProvider);
  final service = ref.watch(sharedFolderServiceProvider);

  if (!auth.isConnected) return [];
  return service.getSharedFolders(auth.client);
});

/// Provides the list of folders shared *with* the current user.
///
/// Automatically re-fetches when the authenticated client changes.
final sharedWithMeProvider =
    FutureProvider.autoDispose<List<SharedFolder>>((ref) async {
  final auth = ref.watch(authProvider);
  final service = ref.watch(sharedFolderServiceProvider);

  if (!auth.isConnected) return [];
  return service.getSharedWithMe(auth.client);
});

// ---------------------------------------------------------------------------
// Share dialog settings — StateNotifier
// ---------------------------------------------------------------------------

/// Holds the [ShareSettings] that the user is currently configuring in the
/// share dialog. Consumers can read the current settings and call mutation
/// methods to update them before submitting the share request.
class ShareSettingsNotifier extends StateNotifier<ShareSettings> {
  ShareSettingsNotifier()
      : super(const ShareSettings(
          permissions: SharedPermission.view,
          allowDownload: true,
          allowUpload: false,
          notifyOnAccess: false,
        ));

  /// Replace all settings at once (e.g. when opening the dialog for an
  /// existing share).
  void loadSettings(ShareSettings settings) {
    state = settings;
  }

  /// Reset to sensible defaults.
  void reset() {
    state = const ShareSettings(
      permissions: SharedPermission.view,
      allowDownload: true,
      allowUpload: false,
      notifyOnAccess: false,
    );
  }

  /// Set or clear the password. Pass null to remove password protection.
  void setPassword(String? password) {
    state = state.copyWith(password: password);
  }

  /// Set or clear the expiry date.
  void setExpiresAt(DateTime? expiresAt) {
    state = state.copyWith(expiresAt: expiresAt);
  }

  /// Change the default permission for link recipients.
  void setPermissions(SharedPermission permissions) {
    state = state.copyWith(permissions: permissions);
  }

  /// Toggle whether recipients can download individual files.
  void setAllowDownload(bool value) {
    state = state.copyWith(allowDownload: value);
  }

  /// Toggle whether recipients can upload files.
  void setAllowUpload(bool value) {
    state = state.copyWith(allowUpload: value);
  }

  /// Toggle access notifications for the share owner.
  void setNotifyOnAccess(bool value) {
    state = state.copyWith(notifyOnAccess: value);
  }
}

/// Provider for the share settings currently being configured in the UI.
///
/// Scoped with [autoDispose] so the state is cleaned up when the share
/// dialog is closed.
final shareSettingsProvider =
    StateNotifierProvider.autoDispose<ShareSettingsNotifier, ShareSettings>(
  (ref) => ShareSettingsNotifier(),
);

// ---------------------------------------------------------------------------
// Convenience: capability check for the active client
// ---------------------------------------------------------------------------

/// Returns true if the currently authenticated provider supports sharing.
///
/// Useful for conditionally showing the share UI.
final activeProviderSupportsSharingProvider = Provider.autoDispose<bool>((ref) {
  final auth = ref.watch(authProvider);
  final service = ref.watch(sharedFolderServiceProvider);

  return service.isProviderSupported(auth.client);
});
