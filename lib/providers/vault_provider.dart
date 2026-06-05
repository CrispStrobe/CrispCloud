// lib/providers/vault_provider.dart
//
// Riverpod providers for Cryptomator vault and VeraCrypt container state.
//
// - [detectedVaultsProvider] — immutable snapshot of detected vaults/containers
//   found during a directory browse. Updated by calling notifier methods.
// - [unlockedVaultsProvider] — manages unlocked Cryptomator vault sessions.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/cryptomator_service.dart';
import '../services/veracrypt_service.dart';

// ---------------------------------------------------------------------------
// Detected vaults / containers state
// ---------------------------------------------------------------------------

class DetectedVaultsState {
  /// Cryptomator vaults detected in browsed directories.
  final List<CryptomatorVault> cryptomatorVaults;

  /// VeraCrypt containers detected during browsing.
  final List<VeraCryptContainer> veraCryptContainers;

  const DetectedVaultsState({
    this.cryptomatorVaults = const [],
    this.veraCryptContainers = const [],
  });

  DetectedVaultsState copyWith({
    List<CryptomatorVault>? cryptomatorVaults,
    List<VeraCryptContainer>? veraCryptContainers,
  }) =>
      DetectedVaultsState(
        cryptomatorVaults: cryptomatorVaults ?? this.cryptomatorVaults,
        veraCryptContainers: veraCryptContainers ?? this.veraCryptContainers,
      );

  bool get isEmpty =>
      cryptomatorVaults.isEmpty && veraCryptContainers.isEmpty;

  int get totalCount =>
      cryptomatorVaults.length + veraCryptContainers.length;
}

class DetectedVaultsNotifier extends Notifier<DetectedVaultsState> {
  @override
  DetectedVaultsState build() => const DetectedVaultsState();

  /// Check a directory listing for Cryptomator vault markers and add any found
  /// vault to the detected list.
  void checkDirectoryForVault(String dirPath, List<String> fileNames) {
    if (CryptomatorService.detectVault(dirPath, fileNames)) {
      final masterkeyPath = '$dirPath/masterkey.cryptomator';
      final vault = CryptomatorVault(
        vaultPath: dirPath,
        masterkeyFilePath: masterkeyPath,
      );
      // Avoid duplicates
      final already = state.cryptomatorVaults.any((v) => v.vaultPath == dirPath);
      if (!already) {
        state = state.copyWith(
          cryptomatorVaults: [...state.cryptomatorVaults, vault],
        );
      }
    }
  }

  /// Check a file path/size for VeraCrypt container markers and register it.
  void checkFileForContainer(String filePath, int fileSize) {
    if (VeraCryptService.detectContainerStrict(filePath, fileSize)) {
      final container = VeraCryptContainer(
        path: filePath,
        sizeBytes: fileSize,
      );
      final already =
          state.veraCryptContainers.any((c) => c.path == filePath);
      if (!already) {
        state = state.copyWith(
          veraCryptContainers: [...state.veraCryptContainers, container],
        );
      }
    }
  }

  /// Mark a VeraCrypt container as mounted (e.g., after OS-level mount).
  void markContainerMounted(String path, {bool mounted = true}) {
    final updated = state.veraCryptContainers.map((c) {
      if (c.path == path) return c.copyWith(mounted: mounted);
      return c;
    }).toList();
    state = state.copyWith(veraCryptContainers: updated);
  }

  /// Remove a detected vault entry (e.g., after the directory is no longer visible).
  void removeVault(String vaultPath) {
    state = state.copyWith(
      cryptomatorVaults:
          state.cryptomatorVaults.where((v) => v.vaultPath != vaultPath).toList(),
    );
  }

  /// Remove a detected container entry.
  void removeContainer(String containerPath) {
    state = state.copyWith(
      veraCryptContainers:
          state.veraCryptContainers.where((c) => c.path != containerPath).toList(),
    );
  }

  /// Clear all detected entries (e.g., when navigating to a new root).
  void clear() => state = const DetectedVaultsState();
}

/// Provider that tracks Cryptomator vaults and VeraCrypt containers found
/// during directory browsing.
final detectedVaultsProvider =
    NotifierProvider<DetectedVaultsNotifier, DetectedVaultsState>(
  DetectedVaultsNotifier.new,
);

// ---------------------------------------------------------------------------
// Unlocked vault sessions
// ---------------------------------------------------------------------------

class UnlockedVaultsState {
  /// Map from vault path → unlocked vault session.
  final Map<String, UnlockedVault> sessions;

  const UnlockedVaultsState({this.sessions = const {}});

  UnlockedVaultsState copyWith({Map<String, UnlockedVault>? sessions}) =>
      UnlockedVaultsState(sessions: sessions ?? this.sessions);

  bool isUnlocked(String vaultPath) => sessions.containsKey(vaultPath);

  UnlockedVault? session(String vaultPath) => sessions[vaultPath];

  int get count => sessions.length;
}

class UnlockedVaultsNotifier extends Notifier<UnlockedVaultsState> {
  @override
  UnlockedVaultsState build() => const UnlockedVaultsState();

  /// Unlock a Cryptomator vault with the given [password].
  ///
  /// Parses [masterkeyJson] and derives the master keys. Throws on wrong
  /// password or corrupted masterkey file.
  void unlockVault(
    CryptomatorVault vaultMeta,
    MasterkeyFile masterkeyFile,
    String password,
  ) {
    final unlocked = CryptomatorService.unlockVault(
      vaultMeta,
      masterkeyFile,
      password,
    );
    final updated = Map<String, UnlockedVault>.from(state.sessions);
    updated[vaultMeta.vaultPath] = unlocked;
    state = state.copyWith(sessions: updated);
  }

  /// Lock a previously unlocked vault (remove the session).
  void lockVault(String vaultPath) {
    final updated = Map<String, UnlockedVault>.from(state.sessions)
      ..remove(vaultPath);
    state = state.copyWith(sessions: updated);
  }

  /// Lock all open vault sessions (e.g., on app background/lock screen).
  void lockAll() => state = const UnlockedVaultsState();

  /// Return true if the vault at [vaultPath] is currently unlocked.
  bool isUnlocked(String vaultPath) => state.isUnlocked(vaultPath);

  /// Retrieve the active session for a vault, or null if locked.
  UnlockedVault? session(String vaultPath) => state.session(vaultPath);
}

/// Provider that manages unlocked Cryptomator vault sessions.
final unlockedVaultsProvider =
    NotifierProvider<UnlockedVaultsNotifier, UnlockedVaultsState>(
  UnlockedVaultsNotifier.new,
);
