// lib/providers/storage_analytics_provider.dart
//
// Riverpod providers for StorageAnalyticsService.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../services/storage_analytics_service.dart';

export '../services/storage_analytics_service.dart'
    show
        FileCategory,
        CategoryStats,
        StaleFile,
        DuplicateEntry,
        DuplicateGroup,
        CleanupType,
        CleanupSuggestion,
        StorageBreakdown,
        StorageAnalyticsService;

// ---------------------------------------------------------------------------
// Service singleton
// ---------------------------------------------------------------------------

/// Singleton [StorageAnalyticsService] available across the app.
final storageAnalyticsProvider = Provider<StorageAnalyticsService>((ref) {
  return StorageAnalyticsService();
});

// ---------------------------------------------------------------------------
// Per-provider breakdown
// ---------------------------------------------------------------------------

/// Family provider: given a [providerId] and a flat list of its files,
/// computes (or returns a cached) [StorageBreakdown].
///
/// Usage:
///   ref.watch(storageBreakdownProvider(
///       StorageBreakdownArgs(providerId: 'my-s3', files: fileList)))
class StorageBreakdownArgs {
  final String providerId;
  final List<FileItem> files;
  final int staleDays;
  final int topN;

  const StorageBreakdownArgs({
    required this.providerId,
    required this.files,
    this.staleDays = 180,
    this.topN = 10,
  });

  @override
  bool operator ==(Object other) =>
      other is StorageBreakdownArgs &&
      providerId == other.providerId &&
      files == other.files &&
      staleDays == other.staleDays &&
      topN == other.topN;

  @override
  int get hashCode =>
      Object.hash(providerId, files, staleDays, topN);
}

final storageBreakdownProvider =
    Provider.family<StorageBreakdown, StorageBreakdownArgs>(
  (ref, args) {
    final service = ref.watch(storageAnalyticsProvider);
    return service.analyzeProvider(
      args.providerId,
      args.files,
      staleDays: args.staleDays,
      topN: args.topN,
    );
  },
);

// ---------------------------------------------------------------------------
// Cross-provider duplicates
// ---------------------------------------------------------------------------

/// Family provider: given a map of providerId → file list, returns all
/// duplicate groups found across those providers.
final crossProviderDuplicatesProvider =
    Provider.family<List<DuplicateGroup>, Map<String, List<FileItem>>>(
  (ref, allFiles) {
    final service = ref.watch(storageAnalyticsProvider);
    return service.findDuplicatesAcrossProviders(allFiles);
  },
);

// ---------------------------------------------------------------------------
// Aggregate cleanup suggestions
// ---------------------------------------------------------------------------

/// Holds all inputs needed to compute aggregate cleanup suggestions.
class CleanupSuggestionsArgs {
  final List<StorageBreakdown> breakdowns;
  final List<DuplicateGroup> duplicates;
  final List<StaleFile> staleFiles;

  const CleanupSuggestionsArgs({
    required this.breakdowns,
    required this.duplicates,
    required this.staleFiles,
  });
}

/// Family provider returning aggregate [CleanupSuggestion]s.
final cleanupSuggestionsProvider =
    Provider.family<List<CleanupSuggestion>, CleanupSuggestionsArgs>(
  (ref, args) {
    final service = ref.watch(storageAnalyticsProvider);
    return service.generateCleanupSuggestions(
      args.breakdowns,
      args.duplicates,
      args.staleFiles,
    );
  },
);
