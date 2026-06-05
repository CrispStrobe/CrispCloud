// lib/widgets/update_banner.dart
//
// Small dismissible banner shown at the top of the main screen when a new
// *stable* release is available.
//
// Behaviour:
//   • Only shown for UpdateChannel.stable updates (beta/nightly are silent).
//   • Persists dismissal per-version in SharedPreferences so the banner stays
//     gone for that version even after a restart.
//   • Tapping "Update" opens UpdateDialog.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/update_provider.dart';
import '../services/auto_update_service.dart';
import 'update_dialog.dart';

// ---------------------------------------------------------------------------
// Dismissal persistence provider
// ---------------------------------------------------------------------------

/// Provides a set of version strings that the user has already dismissed.
/// Loaded lazily from SharedPreferences.
final _dismissedVersionsProvider =
    StateNotifierProvider<_DismissedVersionsNotifier, Set<String>>((ref) {
  return _DismissedVersionsNotifier();
});

class _DismissedVersionsNotifier extends StateNotifier<Set<String>> {
  static const _prefKey = 'update_banner_dismissed';

  _DismissedVersionsNotifier() : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefKey) ?? [];
    if (mounted) state = list.toSet();
  }

  Future<void> dismiss(String version) async {
    final next = {...state, version};
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKey, next.toList());
  }
}

// ---------------------------------------------------------------------------
// UpdateBanner
// ---------------------------------------------------------------------------

/// Renders a slim banner when a stable-channel update is available and has
/// not been dismissed for this version.  Returns [SizedBox.shrink] otherwise.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkAsync = ref.watch(updateCheckProvider);
    final channel = ref.watch(updateChannelProvider);
    final dismissed = ref.watch(_dismissedVersionsProvider);

    // Only show for stable channel.
    if (channel != UpdateChannel.stable) return const SizedBox.shrink();

    return checkAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (info) {
        if (info == null) return const SizedBox.shrink();
        if (dismissed.contains(info.version)) return const SizedBox.shrink();

        return _BannerStrip(
          info: info,
          onDismiss: () => ref
              .read(_dismissedVersionsProvider.notifier)
              .dismiss(info.version),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// _BannerStrip — the actual visible widget
// ---------------------------------------------------------------------------

class _BannerStrip extends StatelessWidget {
  final UpdateInfo info;
  final VoidCallback onDismiss;

  const _BannerStrip({required this.info, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(
                Icons.system_update_alt,
                size: 16,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  key: const Key('update_banner_label'),
                  'CrispCloud ${info.version} available',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              TextButton(
                key: const Key('update_banner_update_button'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => showUpdateDialog(context),
                child: const Text('Update'),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const Key('update_banner_dismiss_button'),
                icon: Icon(
                  Icons.close,
                  size: 16,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                tooltip: 'Dismiss for this version',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
