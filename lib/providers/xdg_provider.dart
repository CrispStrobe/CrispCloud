// lib/providers/xdg_provider.dart
//
// Riverpod providers exposing XdgService and convenience path providers.
//
// Providers:
//   xdgServiceProvider  — AsyncNotifier that initialises and exposes the
//                         XdgService singleton.
//   configPathProvider  — the resolved config directory path (String).
//   dataPathProvider    — the resolved data directory path (String).
//   cachePathProvider   — the resolved cache directory path (String).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/xdg_service.dart';

// ---------------------------------------------------------------------------
// Service provider
// ---------------------------------------------------------------------------

/// Initialises and exposes the [XdgService] singleton.
///
/// Consumers that need the service directly (e.g. to call [getConfigPath])
/// should watch this provider and handle the [AsyncValue] loading/error states.
final xdgServiceProvider = AsyncNotifierProvider<_XdgServiceNotifier, XdgService>(
  _XdgServiceNotifier.new,
);

class _XdgServiceNotifier extends AsyncNotifier<XdgService> {
  @override
  Future<XdgService> build() => XdgService.init();
}

// ---------------------------------------------------------------------------
// Convenience path providers
// ---------------------------------------------------------------------------

/// Resolves to the XDG config directory for CrispCloud.
///
/// Returns an empty string while [xdgServiceProvider] is loading.
final configPathProvider = Provider<String>((ref) {
  return ref.watch(xdgServiceProvider).maybeWhen(
        data: (svc) => svc.configHome,
        orElse: () => '',
      );
});

/// Resolves to the XDG data directory for CrispCloud.
///
/// Returns an empty string while [xdgServiceProvider] is loading.
final dataPathProvider = Provider<String>((ref) {
  return ref.watch(xdgServiceProvider).maybeWhen(
        data: (svc) => svc.dataHome,
        orElse: () => '',
      );
});

/// Resolves to the XDG cache directory for CrispCloud.
///
/// Returns an empty string while [xdgServiceProvider] is loading.
final cachePathProvider = Provider<String>((ref) {
  return ref.watch(xdgServiceProvider).maybeWhen(
        data: (svc) => svc.cacheHome,
        orElse: () => '',
      );
});

/// Resolves to the XDG state directory for CrispCloud.
///
/// Returns an empty string while [xdgServiceProvider] is loading.
final statePathProvider = Provider<String>((ref) {
  return ref.watch(xdgServiceProvider).maybeWhen(
        data: (svc) => svc.stateHome,
        orElse: () => '',
      );
});
