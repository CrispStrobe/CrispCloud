// lib/services/virtual_fs_service.dart
//
// VirtualFilesystemService — unified cross-platform virtual filesystem API.
//
// Abstracts over the platform-specific virtual filesystem integration
// mechanisms so that the rest of the app can simply call `mount()` /
// `unmount()` without needing to know which underlying technology is used:
//
//   Platform        Mechanism              Service used
//   ────────────────────────────────────────────────────────────────────
//   Linux           FUSE (libfuse3)        FuseMountService
//   macOS           FUSE (macFUSE/FUSE-T)  FuseMountService
//   Windows         FUSE (WinFsp)          FuseMountService
//   Android         DocumentsProvider      DocumentsProviderBridge
//   iOS             FileProvider           FileProviderBridge
//   Web             File System Access API (managed elsewhere — no-op here)
//
// Usage:
// ```dart
// final vfs = VirtualFilesystemService();
//
// if (vfs.isSupported) {
//   print(vfs.getAvailableMethods());   // [VirtualFsMethod.fuse] on desktop
//
//   await vfs.mount(provider: 's3', path: '/mybucket');
//   print(vfs.isMounted('s3'));  // true
//
//   await vfs.unmount('s3');
// }
// ```

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'cloud_storage_interface.dart' show CloudStorageClient;
import 'documents_provider_bridge.dart';
import 'file_provider_bridge.dart';
import 'fuse_mount_service.dart';
import 'log_service.dart';

// ---------------------------------------------------------------------------
// Enum
// ---------------------------------------------------------------------------

/// Enumerates the virtual filesystem integration methods supported by the app.
enum VirtualFsMethod {
  /// FUSE-based mount (macOS / Linux / Windows desktop).
  fuse,

  /// Android DocumentsProvider — exposes cloud storage in the SAF file picker.
  documentsProvider,

  /// iOS NSFileProviderReplicatedExtension — Files.app integration.
  fileProvider,

  /// Web File System Access API + OPFS (browser).
  fileSystemAccess,
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// Describes an active virtual filesystem mount.
class VirtualMount {
  /// The cloud provider name (e.g. "s3", "dropbox").
  final String provider;

  /// Human-readable label.
  final String label;

  /// The mechanism used for this mount.
  final VirtualFsMethod method;

  /// Platform-specific mount point path (desktop only; empty on mobile/web).
  final String mountPoint;

  /// Whether this mount is currently active.
  bool isActive;

  VirtualMount({
    required this.provider,
    required this.label,
    required this.method,
    this.mountPoint = '',
    this.isActive = true,
  });

  @override
  String toString() =>
      'VirtualMount(provider: $provider, method: $method, '
      'mountPoint: $mountPoint, isActive: $isActive)';
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Unified cross-platform virtual filesystem service.
///
/// Delegates to [FuseMountService], [DocumentsProviderBridge], or
/// [FileProviderBridge] depending on the current platform.
class VirtualFilesystemService {
  static const _log = Log('VirtualFilesystemService');

  final FuseMountService _fuseService;
  final DocumentsProviderBridge _documentsProviderBridge;
  final FileProviderBridge _fileProviderBridge;

  // In-memory registry of active mounts (non-desktop platforms).
  // Desktop mounts are tracked by FuseMountService.
  final Map<String, VirtualMount> _mounts = {};

  VirtualFilesystemService({
    FuseMountService? fuseService,
    DocumentsProviderBridge? documentsProviderBridge,
    FileProviderBridge? fileProviderBridge,
  })  : _fuseService = fuseService ?? FuseMountService(),
        _documentsProviderBridge =
            documentsProviderBridge ?? DocumentsProviderBridge.instance,
        _fileProviderBridge =
            fileProviderBridge ?? FileProviderBridge.instance;

  // ---------------------------------------------------------------------------
  // Platform capability queries
  // ---------------------------------------------------------------------------

  /// Whether any virtual filesystem integration is supported on this platform.
  bool get isSupported => getAvailableMethods().isNotEmpty;

  /// Returns the list of virtual filesystem methods available on the current
  /// platform/runtime.
  ///
  /// - Desktop (macOS / Linux / Windows): [[VirtualFsMethod.fuse]]
  /// - Android: [[VirtualFsMethod.documentsProvider]]
  /// - iOS: [[VirtualFsMethod.fileProvider]]
  /// - Web: [[VirtualFsMethod.fileSystemAccess]]
  List<VirtualFsMethod> getAvailableMethods() {
    if (kIsWeb) {
      return const [VirtualFsMethod.fileSystemAccess];
    }

    if (FuseMountService.isSupported) {
      return const [VirtualFsMethod.fuse];
    }

    if (Platform.isAndroid) {
      return const [VirtualFsMethod.documentsProvider];
    }

    if (Platform.isIOS) {
      return const [VirtualFsMethod.fileProvider];
    }

    return const [];
  }

  /// The primary method for this platform, or null if unsupported.
  VirtualFsMethod? get primaryMethod {
    final methods = getAvailableMethods();
    return methods.isEmpty ? null : methods.first;
  }

  // ---------------------------------------------------------------------------
  // Mount lifecycle
  // ---------------------------------------------------------------------------

  /// Mounts [provider]'s cloud storage using the appropriate mechanism.
  ///
  /// On desktop: calls [FuseMountService.mount] and creates a FUSE mount
  /// at [mountPoint] (or `/tmp/crispcloud/<provider>` if not supplied).
  /// The [storageClient] is required on desktop so FUSE can delegate I/O.
  ///
  /// On Android: registers the provider with [DocumentsProviderBridge] so it
  /// appears in the system file picker. [storageClient] is not required here
  /// (the MethodChannel handler must be registered separately).
  ///
  /// On iOS: registers a [FileProviderConnection] and calls
  /// [FileProviderBridge.registerDomain].
  ///
  /// On web: no-op (File System Access is managed by [FileSystemAccessService]).
  ///
  /// Throws [UnsupportedError] if the platform has no supported method.
  Future<void> mount({
    required String provider,
    required String label,
    String path = '/',
    Map<String, String> credentials = const {},
    String mountPoint = '',
    CloudStorageClient? storageClient,
  }) async {
    if (!isSupported) {
      throw UnsupportedError(
          'VirtualFilesystemService: no supported method on this platform');
    }

    final method = primaryMethod!;
    _log.info('mount provider=$provider method=$method');

    switch (method) {
      case VirtualFsMethod.fuse:
        if (storageClient == null) {
          throw ArgumentError(
              'storageClient is required for FUSE mounts on desktop');
        }
        await _mountFuse(
            storageClient: storageClient,
            remotePath: path,
            label: label,
            mountPoint: mountPoint.isNotEmpty
                ? mountPoint
                : '/tmp/crispcloud/$provider');
        break;

      case VirtualFsMethod.documentsProvider:
        await _mountDocumentsProvider(
            provider: provider, label: label, credentials: credentials);
        break;

      case VirtualFsMethod.fileProvider:
        await _mountFileProvider(
            provider: provider, label: label, credentials: credentials);
        break;

      case VirtualFsMethod.fileSystemAccess:
        // Managed by FileSystemAccessService — nothing to do here.
        _log.debug('mount: fileSystemAccess is managed externally, no-op');
        _mounts[provider] = VirtualMount(
          provider: provider,
          label: label,
          method: method,
        );
        break;
    }
  }

  /// Unmounts / deregisters the virtual filesystem for [provider].
  ///
  /// On desktop: calls [FuseMountService.unmount].
  /// On Android: removes the provider from [DocumentsProviderBridge] and
  /// calls [DocumentsProviderBridge.refreshRoots].
  /// On iOS: calls [FileProviderBridge.unregisterDomain] when the last
  /// provider is removed.
  ///
  /// Throws [UnsupportedError] if the platform has no supported method.
  Future<void> unmount(String provider) async {
    if (!isSupported) {
      throw UnsupportedError(
          'VirtualFilesystemService: no supported method on this platform');
    }

    final method = primaryMethod!;
    _log.info('unmount provider=$provider method=$method');

    switch (method) {
      case VirtualFsMethod.fuse:
        await _unmountFuse(provider);
        break;

      case VirtualFsMethod.documentsProvider:
        await _unmountDocumentsProvider(provider);
        break;

      case VirtualFsMethod.fileProvider:
        await _unmountFileProvider(provider);
        break;

      case VirtualFsMethod.fileSystemAccess:
        _mounts.remove(provider);
        break;
    }
  }

  /// Returns true if [provider] currently has an active virtual filesystem mount.
  bool isMounted(String provider) {
    if (kIsWeb || FuseMountService.isSupported) {
      // For desktop, check FuseMountService state.
      if (FuseMountService.isSupported) {
        return _mounts.containsKey(provider) &&
            (_mounts[provider]?.isActive ?? false);
      }
      return _mounts.containsKey(provider);
    }

    if (!kIsWeb && Platform.isAndroid) {
      return _documentsProviderBridge
          .getConnectedProviders()
          .any((c) => c.provider == provider);
    }

    return _mounts[provider]?.isActive ?? false;
  }

  /// Returns an unmodifiable list of all active mounts tracked by this service.
  List<VirtualMount> get activeMounts => List.unmodifiable(_mounts.values);

  // ---------------------------------------------------------------------------
  // Platform-specific implementation helpers
  // ---------------------------------------------------------------------------

  Future<void> _mountFuse({
    required CloudStorageClient storageClient,
    required String remotePath,
    required String label,
    required String mountPoint,
  }) async {
    final entry = await _fuseService.mount(
      client: storageClient,
      remotePath: remotePath,
      mountPoint: mountPoint,
      label: label,
    );

    _mounts[storageClient.providerName] = VirtualMount(
      provider: storageClient.providerName,
      label: label,
      method: VirtualFsMethod.fuse,
      mountPoint: entry.mountPoint,
    );
    _log.info(
        'FUSE mount created at ${entry.mountPoint} for ${storageClient.providerName}');
  }

  Future<void> _unmountFuse(String provider) async {
    final mount = _mounts[provider];
    if (mount == null) {
      _log.warn('unmount: no tracked mount for provider $provider');
      return;
    }
    await _fuseService.unmount(mount.mountPoint);
    _mounts.remove(provider);
  }

  Future<void> _mountDocumentsProvider({
    required String provider,
    required String label,
    required Map<String, String> credentials,
  }) async {
    final existing = _documentsProviderBridge.getConnectedProviders().toList();

    // Add or update the entry for this provider.
    final updated = [
      ...existing.where((c) => c.provider != provider),
      DocumentsProviderConnection(provider: provider, label: label),
    ];

    await _documentsProviderBridge.syncConnections(updated);
    await _documentsProviderBridge.refreshRoots();

    _mounts[provider] = VirtualMount(
      provider: provider,
      label: label,
      method: VirtualFsMethod.documentsProvider,
    );
    _log.info('DocumentsProvider root added for $provider');
  }

  Future<void> _unmountDocumentsProvider(String provider) async {
    final existing = _documentsProviderBridge.getConnectedProviders().toList();
    final updated = existing.where((c) => c.provider != provider).toList();

    await _documentsProviderBridge.syncConnections(updated);
    await _documentsProviderBridge.refreshRoots();

    _mounts.remove(provider);
    _log.info('DocumentsProvider root removed for $provider');
  }

  Future<void> _mountFileProvider({
    required String provider,
    required String label,
    required Map<String, String> credentials,
  }) async {
    await _fileProviderBridge.syncConnections([
      FileProviderConnection(
        provider: provider,
        label: label,
        credentials: credentials,
      ),
    ]);
    await _fileProviderBridge.registerDomain();

    _mounts[provider] = VirtualMount(
      provider: provider,
      label: label,
      method: VirtualFsMethod.fileProvider,
    );
    _log.info('FileProvider domain registered for $provider');
  }

  Future<void> _unmountFileProvider(String provider) async {
    _mounts.remove(provider);

    // Unregister the domain only when no providers remain.
    if (_mounts.isEmpty) {
      await _fileProviderBridge.unregisterDomain();
      _log.info('FileProvider domain unregistered (no providers left)');
    } else {
      // Re-sync remaining providers.
      final remaining = _mounts.values
          .map((m) => FileProviderConnection(
                provider: m.provider,
                label: m.label,
                credentials: const {},
              ))
          .toList();
      await _fileProviderBridge.syncConnections(remaining);
      _log.info('FileProvider domain updated, removed $provider');
    }
  }
}
