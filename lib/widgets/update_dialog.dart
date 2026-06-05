// lib/widgets/update_dialog.dart
//
// Dialog for checking and displaying CrispCloud update information.
//
// Surfaces:
//   • Current running version (stamped at build via APP_VERSION dart-define)
//   • Latest available version from GitHub Releases
//   • Release notes rendered via flutter_markdown
//   • "Update Available" / "You're up to date" state
//   • Download button that opens the release URL via url_launcher
//   • Update channel selector (Stable / Beta / Nightly)
//   • Auto-check on startup toggle
//   • "Check Now" button that invalidates the FutureProvider
//   • Loading and error states

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/update_provider.dart';
import '../services/auto_update_service.dart';

// ---------------------------------------------------------------------------
// Public convenience function
// ---------------------------------------------------------------------------

/// Opens the [UpdateDialog] over [context].
Future<void> showUpdateDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const UpdateDialog(),
  );
}

// ---------------------------------------------------------------------------
// UpdateDialog
// ---------------------------------------------------------------------------

/// Full-featured update dialog: version status, release notes, channel selector,
/// auto-check toggle, and a manual "Check Now" trigger.
class UpdateDialog extends ConsumerWidget {
  const UpdateDialog({super.key});

  // The running version is stamped by CI via --dart-define=APP_VERSION=x.y.z.
  static const _currentVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.1.0',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkAsync = ref.watch(updateCheckProvider);
    final channel = ref.watch(updateChannelProvider);
    final autoEnabled = ref.watch(autoUpdateEnabledProvider);
    final theme = Theme.of(context);

    return AlertDialog(
      key: const Key('update_dialog'),
      title: Row(
        children: [
          const Icon(Icons.system_update_alt),
          const SizedBox(width: 8),
          const Text('Check for Updates'),
          const Spacer(),
          IconButton(
            key: const Key('update_dialog_close'),
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Version row ----
              _VersionRow(currentVersion: _currentVersion, checkAsync: checkAsync),
              const SizedBox(height: 16),

              // ---- Status banner ----
              checkAsync.when(
                loading: () => const _LoadingBanner(),
                error: (err, _) => _ErrorBanner(message: err.toString()),
                data: (info) => info != null
                    ? _UpdateAvailableBanner(info: info)
                    : const _UpToDateBanner(),
              ),
              const SizedBox(height: 16),

              // ---- Release notes ----
              checkAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (info) => info != null
                    ? _ReleaseNotesSection(info: info)
                    : const SizedBox.shrink(),
              ),

              // ---- Channel selector ----
              const Divider(height: 32),
              Text(
                'Update Channel',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              _ChannelSelector(
                current: channel,
                onChanged: (ch) =>
                    ref.read(updateChannelProvider.notifier).setChannel(ch),
              ),
              const SizedBox(height: 8),

              // ---- Auto-check toggle ----
              SwitchListTile(
                key: const Key('update_auto_check_toggle'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Check automatically on startup'),
                subtitle: const Text('Runs a background check each time the app launches'),
                value: autoEnabled,
                onChanged: (v) =>
                    ref.read(autoUpdateEnabledProvider.notifier).setEnabled(v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        // Download button — only visible when an update is available.
        checkAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (info) => info != null
              ? _DownloadButton(key: const Key('update_download_button'), info: info)
              : const SizedBox.shrink(),
        ),

        // Check Now
        OutlinedButton.icon(
          key: const Key('update_check_now_button'),
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Check Now'),
          onPressed: checkAsync.isLoading
              ? null
              : () => ref.invalidate(updateCheckProvider),
        ),

        // Close
        TextButton(
          key: const Key('update_dialog_done'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _VersionRow
// ---------------------------------------------------------------------------

class _VersionRow extends StatelessWidget {
  final String currentVersion;
  final AsyncValue<UpdateInfo?> checkAsync;

  const _VersionRow({required this.currentVersion, required this.checkAsync});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current version', style: theme.textTheme.labelSmall),
            Text(
              'v$currentVersion',
              key: const Key('update_current_version'),
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(width: 32),
        checkAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (info) => info != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Latest version', style: theme.textTheme.labelSmall),
                    Text(
                      info.version,
                      key: const Key('update_latest_version'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Status banners
// ---------------------------------------------------------------------------

class _LoadingBanner extends StatelessWidget {
  const _LoadingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('update_loading_banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Checking for updates…'),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('update_error_banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _friendlyError(message),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _friendlyError(String raw) {
    if (raw.contains('rate limit')) {
      return 'GitHub API rate limit reached. Please try again later.';
    }
    if (raw.contains('Network error') || raw.contains('SocketException')) {
      return 'Network error — check your internet connection and try again.';
    }
    if (raw.contains('not found')) {
      return 'Repository not found. Check your update configuration.';
    }
    return raw.replaceFirst('AutoUpdateException: ', '');
  }
}

class _UpToDateBanner extends StatelessWidget {
  const _UpToDateBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('update_up_to_date_banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
          SizedBox(width: 8),
          Text(
            "You're up to date!",
            key: Key('update_up_to_date_label'),
          ),
        ],
      ),
    );
  }
}

class _UpdateAvailableBanner extends StatelessWidget {
  final UpdateInfo info;
  const _UpdateAvailableBanner({required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('update_available_banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.new_releases_outlined,
              color: theme.colorScheme.onPrimaryContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Update Available — ${info.version}',
              key: const Key('update_available_label'),
              style: TextStyle(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            _formatDate(info.publishedAt),
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onPrimaryContainer.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Release notes
// ---------------------------------------------------------------------------

class _ReleaseNotesSection extends StatelessWidget {
  final UpdateInfo info;
  const _ReleaseNotesSection({required this.info});

  @override
  Widget build(BuildContext context) {
    if (info.releaseNotes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Release Notes', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Container(
          key: const Key('update_release_notes'),
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Markdown(
              data: info.releaseNotes,
              shrinkWrap: true,
              padding: const EdgeInsets.all(12),
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
                    p: Theme.of(context).textTheme.bodySmall,
                    h1: Theme.of(context).textTheme.titleSmall,
                    h2: Theme.of(context).textTheme.labelLarge,
                    h3: Theme.of(context).textTheme.labelMedium,
                  ),
              onTapLink: (text, href, title) async {
                if (href != null) {
                  final uri = Uri.tryParse(href);
                  if (uri != null && await canLaunchUrl(uri)) {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                  }
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Channel selector
// ---------------------------------------------------------------------------

class _ChannelSelector extends StatelessWidget {
  final UpdateChannel current;
  final ValueChanged<UpdateChannel> onChanged;

  const _ChannelSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<UpdateChannel>(
      key: const Key('update_channel_selector'),
      segments: const [
        ButtonSegment(
          value: UpdateChannel.stable,
          label: Text('Stable'),
          icon: Icon(Icons.verified_outlined, size: 16),
        ),
        ButtonSegment(
          value: UpdateChannel.beta,
          label: Text('Beta'),
          icon: Icon(Icons.science_outlined, size: 16),
        ),
        ButtonSegment(
          value: UpdateChannel.nightly,
          label: Text('Nightly'),
          icon: Icon(Icons.nightlight_outlined, size: 16),
        ),
      ],
      selected: {current},
      onSelectionChanged: (set) {
        if (set.isNotEmpty) onChanged(set.first);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Download button
// ---------------------------------------------------------------------------

class _DownloadButton extends StatelessWidget {
  final UpdateInfo info;

  const _DownloadButton({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      icon: const Icon(Icons.download, size: 16),
      label: const Text('Download Update'),
      onPressed: () async {
        final uri = Uri.tryParse(info.downloadUrl);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
    );
  }
}
