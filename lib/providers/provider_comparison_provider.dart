// lib/providers/provider_comparison_provider.dart
//
// Riverpod providers for provider comparison.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/cloud_storage_interface.dart';
import '../services/provider_comparison_service.dart';
import 'auth_provider.dart';

// ---------------------------------------------------------------------------
// Service provider
// ---------------------------------------------------------------------------

/// Singleton [ProviderComparisonService] instance.
final providerComparisonProvider = Provider<ProviderComparisonService>(
  (ref) => ProviderComparisonService.instance,
);

// ---------------------------------------------------------------------------
// Comparison result for the currently connected provider
// ---------------------------------------------------------------------------

/// Compares the provider(s) that currently have an authenticated connection.
///
/// Reads the active [AuthNotifier] state and maps the active [CloudProvider]
/// to a [ComparisonResult].  Returns an empty result when not connected.
final comparisonResultProvider = Provider<ComparisonResult>((ref) {
  final service = ref.watch(providerComparisonProvider);
  final auth = ref.watch(authProvider);

  if (!auth.isConnected) {
    return const ComparisonResult(providers: []);
  }

  // The active provider enum value is exposed on the notifier.
  final currentProvider = auth.currentProvider;
  return service.compareProviders([currentProvider]);
});

// ---------------------------------------------------------------------------
// Convenience providers
// ---------------------------------------------------------------------------

/// All 11 providers ranked by price (cheapest first).
final providersByPriceProvider = Provider<List<ProviderInfo>>(
  (ref) => ref.watch(providerComparisonProvider).rankByPrice(),
);

/// All 11 providers ranked by privacy score (highest first).
final providersByPrivacyProvider = Provider<List<ProviderInfo>>(
  (ref) => ref.watch(providerComparisonProvider).rankByPrivacy(),
);

/// All 11 providers ranked by feature count (most first).
final providersByFeaturesProvider = Provider<List<ProviderInfo>>(
  (ref) => ref.watch(providerComparisonProvider).rankByFeatures(),
);

/// Recommendation for a given use case.
final recommendationProvider =
    Provider.family<ProviderInfo, ComparisonUseCase>(
  (ref, useCase) =>
      ref.watch(providerComparisonProvider).getRecommendation(useCase),
);
