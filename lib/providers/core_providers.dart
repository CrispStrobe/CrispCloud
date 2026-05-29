// lib/providers/core_providers.dart
//
// Base dependencies injected via ProviderScope overrides in main.dart.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../services/local_file_service.dart';
import '../services/secure_storage_service.dart';

/// Platform secure storage — overridden in main.dart with the real instance.
final secureStorageProvider = Provider<SecureStorage>((ref) {
  throw UnimplementedError('secureStorageProvider must be overridden');
});

/// Platform-specific config path — overridden in main.dart.
final configPathProvider = Provider<String>((ref) {
  throw UnimplementedError('configPathProvider must be overridden');
});

/// Singleton local file service.
final localFileServiceProvider = Provider<LocalFileService>((ref) {
  return LocalFileService();
});

/// Which panel is active (Local / Remote).
final activePanelProvider = StateProvider<PanelSide>((ref) => PanelSide.local);

/// Whether the preview pane is visible.
final showPreviewProvider = StateProvider<bool>((ref) => false);

/// Whether the tree sidebar is visible.
final showTreeSidebarProvider = StateProvider<bool>((ref) => false);

/// Panel split ratio (0.0–1.0, left panel share).
final panelSplitRatioProvider = StateProvider<double>((ref) => 0.5);

/// File view mode per panel.
enum ViewMode { list, grid }
final localViewModeProvider = StateProvider<ViewMode>((ref) => ViewMode.list);
final remoteViewModeProvider = StateProvider<ViewMode>((ref) => ViewMode.list);
