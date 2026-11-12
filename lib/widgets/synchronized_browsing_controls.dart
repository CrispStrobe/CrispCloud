import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/synchronized_browsing_strings.dart';
import '../providers/synchronized_browsing_provider.dart';
import '../providers/core_providers.dart';

void toggleSynchronizedBrowsing(WidgetRef ref) {
  final service = ref.read(synchronizedBrowsingProvider);
  if (service.enabled) {
    service.stop();
  } else {
    if (service.start()) {
      ref.read(showDualPanelProvider.notifier).state = true;
    }
  }
}

class SynchronizedBrowsingButton extends ConsumerWidget {
  const SynchronizedBrowsingButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(synchronizedBrowsingProvider);
    final strings = SynchronizedBrowsingStrings(context);
    return IconButton(
      key: const ValueKey('synchronized-browsing-toggle'),
      tooltip: strings.text(service.enabled ? 'stop' : 'start'),
      icon: Icon(
        service.enabled ? Icons.link : Icons.link_off,
        size: 20,
        color: service.enabled ? Theme.of(context).colorScheme.primary : null,
      ),
      onPressed: () => toggleSynchronizedBrowsing(ref),
    );
  }
}

class SynchronizedBrowsingStatus extends ConsumerWidget {
  const SynchronizedBrowsingStatus({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(synchronizedBrowsingProvider);
    if (!service.enabled && service.issue == null) {
      return const SizedBox.shrink();
    }
    final strings = SynchronizedBrowsingStrings(context);
    final scheme = Theme.of(context).colorScheme;
    final message = service.enabled
        ? '${strings.text('active')}: ${service.leftRoot} ↔ ${service.rightRoot}'
        : strings.failure(service.issue!, service.issuePath);
    return Material(
      color: service.enabled
          ? scheme.secondaryContainer
          : scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
        child: Row(
          children: [
            Icon(service.enabled ? Icons.link : Icons.link_off, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Tooltip(
                  message: message,
                  child: Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: strings.text(service.enabled ? 'stop' : 'dismiss'),
              icon: const Icon(Icons.close, size: 18),
              onPressed: service.enabled ? service.stop : service.dismissIssue,
            ),
          ],
        ),
      ),
    );
  }
}
