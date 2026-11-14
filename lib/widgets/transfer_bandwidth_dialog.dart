import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/transfer_bandwidth_strings.dart';
import '../providers/transfer_bandwidth_provider.dart';
import '../utils/formatters.dart' show formatBytes, formatSpeed;

Future<void> showTransferBandwidthDialog(BuildContext context) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const TransferBandwidthDialog(),
    );

String _rateValue(int bytes) =>
    bytes % 1024 == 0 ? '${bytes ~/ 1024}' : '${bytes / 1024}';

String _limitLabel(TransferBandwidthStrings strings, int bytes) =>
    bytes == 0 ? strings.text('unlimited') : formatSpeed(bytes.toDouble());

@visibleForTesting
int parseTransferBandwidthKibibytes(String input) {
  var value = input.trim().replaceAll(',', '.').replaceAll('\u066b', '.');
  for (var digit = 0; digit < 10; digit++) {
    value = value
        .replaceAll(String.fromCharCode(0x660 + digit), '$digit')
        .replaceAll(String.fromCharCode(0x6f0 + digit), '$digit');
  }
  if (value.isEmpty) return 0;
  if (!RegExp(r'^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$').hasMatch(value)) {
    throw const FormatException('Invalid bandwidth rate.');
  }
  final kibibytes = double.tryParse(value);
  if (kibibytes == null || !kibibytes.isFinite) {
    throw const FormatException('Invalid bandwidth rate.');
  }
  if (kibibytes == 0) return 0;
  final bytes = kibibytes * 1024;
  if (!bytes.isFinite ||
      bytes < 1 ||
      bytes > TransferBandwidthLimits.maximumBytesPerSecond) {
    throw const FormatException(
      'Bandwidth rate is outside the supported range.',
    );
  }
  return bytes.round();
}

class TransferBandwidthDialog extends ConsumerStatefulWidget {
  const TransferBandwidthDialog({super.key, this.browserUploadUnsupported});

  @visibleForTesting
  final bool? browserUploadUnsupported;

  @override
  ConsumerState<TransferBandwidthDialog> createState() =>
      _TransferBandwidthDialogState();
}

class _TransferBandwidthDialogState
    extends ConsumerState<TransferBandwidthDialog> {
  final _upload = TextEditingController();
  final _download = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _errorKey;

  bool get _browserUpload => widget.browserUploadUnsupported ?? kIsWeb;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool retry = false}) async {
    final controller = ref.read(transferBandwidthProvider);
    if (retry) setState(() => _loading = true);
    try {
      await (retry ? controller.retryLoad() : controller.ready);
    } catch (_) {
      // The provider retains a visible load error and blocks queue admission.
      // Saving an explicit replacement remains available after this completes.
    }
    if (!mounted) return;
    setState(() {
      _upload.text = _rateValue(controller.limits.uploadBytesPerSecond);
      _download.text = _rateValue(controller.limits.downloadBytesPerSecond);
      _loading = false;
      _errorKey = null;
    });
  }

  Future<void> _save() async {
    if (_loading || _saving) return;
    final controller = ref.read(transferBandwidthProvider);
    late final TransferBandwidthLimits value;
    try {
      value = TransferBandwidthLimits(
        uploadBytesPerSecond: _browserUpload
            ? controller.limits.uploadBytesPerSecond
            : parseTransferBandwidthKibibytes(_upload.text),
        downloadBytesPerSecond: parseTransferBandwidthKibibytes(_download.text),
      );
      value.validate();
    } catch (_) {
      setState(() => _errorKey = 'invalidRate');
      return;
    }
    setState(() {
      _saving = true;
      _errorKey = null;
    });
    try {
      await controller.updateLimits(value);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _errorKey = 'saveFailed');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _upload.dispose();
    _download.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(transferBandwidthProvider);
    final strings = TransferBandwidthStrings(context);
    final theme = Theme.of(context);
    final busy = _loading || _saving;
    Widget field(
      String key,
      TextEditingController input, {
      bool enabled = true,
    }) => TextField(
      key: ValueKey('bandwidth-$key'),
      controller: input,
      enabled: !busy && enabled,
      textDirection: TextDirection.ltr,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        label: Text(strings.text(key)),
        helperText: strings.text('zeroHelp'),
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) {
        if (_errorKey != null) setState(() => _errorKey = null);
      },
    );

    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        key: const ValueKey('transfer-bandwidth-dialog'),
        scrollable: true,
        title: Text(strings.text('title')),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.text('scope')),
              const SizedBox(height: 8),
              Text(
                strings.text('exclusions'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(strings.text('payload'), style: theme.textTheme.bodySmall),
              if (_browserUpload) ...[
                const SizedBox(height: 12),
                Text(
                  strings.text('browserUpload'),
                  key: const ValueKey('bandwidth-browser-upload-unsupported'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_loading) ...[
                const SizedBox(height: 12),
                Text(strings.text('loading')),
                const LinearProgressIndicator(),
              ],
              if (controller.loadError != null && !_loading) ...[
                const SizedBox(height: 12),
                Text(
                  strings.text('loadFailed'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('bandwidth-retry'),
                    onPressed: busy ? null : () => _load(retry: true),
                    icon: const Icon(Icons.refresh),
                    label: Text(strings.text('retry')),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              field('upload', _upload, enabled: !_browserUpload),
              const SizedBox(height: 16),
              field('download', _download),
              if (_errorKey != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    strings.text(_errorKey!),
                    key: const ValueKey('bandwidth-error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text(strings.text('cancel')),
          ),
          FilledButton(
            key: const ValueKey('bandwidth-save'),
            onPressed: busy ? null : _save,
            child: Text(strings.text('save')),
          ),
        ],
      ),
    );
  }
}

/// Shared entry point from the existing Network settings section.
class TransferBandwidthSettingsTile extends ConsumerWidget {
  const TransferBandwidthSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(transferBandwidthProvider);
    final strings = TransferBandwidthStrings(context);
    final subtitle = controller.isLoading
        ? strings.text('loading')
        : controller.loadError != null
        ? strings.text('loadFailed')
        : [
            strings.format('uploadLimit', {
              'limit': _limitLabel(
                strings,
                controller.limits.uploadBytesPerSecond,
              ),
            }),
            strings.format('downloadLimit', {
              'limit': _limitLabel(
                strings,
                controller.limits.downloadBytesPerSecond,
              ),
            }),
          ].join(' · ');
    return ListTile(
      key: const ValueKey('settings-transfer-bandwidth'),
      leading: const Icon(Icons.speed),
      title: Text(strings.text('title')),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      dense: true,
      onTap: () => showTransferBandwidthDialog(context),
    );
  }
}

class TransferBandwidthActionButton extends StatelessWidget {
  const TransferBandwidthActionButton({super.key});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: const ValueKey('queue-bandwidth'),
    onPressed: () => showTransferBandwidthDialog(context),
    icon: const Icon(Icons.speed),
    label: Text(TransferBandwidthStrings(context).text('shortcut')),
  );
}

/// Directional covered transport counters, separate from logical file progress.
class TransferBandwidthTrafficSummary extends ConsumerWidget {
  const TransferBandwidthTrafficSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(transferBandwidthProvider);
    final strings = TransferBandwidthStrings(context);
    if (!controller.isReady) {
      if (controller.loadError == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          strings.text('loadFailed'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    final snapshot = controller.snapshot;
    final limits = controller.limits;
    final unsupported =
        snapshot.unsupportedUploadJobs > 0 ||
        snapshot.unsupportedDownloadJobs > 0;
    if (snapshot.activeJobs == 0 &&
        snapshot.uploadBytes == 0 &&
        snapshot.downloadBytes == 0 &&
        limits.uploadBytesPerSecond == 0 &&
        limits.downloadBytesPerSecond == 0 &&
        !unsupported) {
      return const SizedBox.shrink();
    }
    return Padding(
      key: const ValueKey('queue-http-traffic'),
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.text('trafficTitle'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 3),
          Wrap(
            spacing: 12,
            runSpacing: 3,
            children: [
              Text(
                strings.format('uploadTraffic', {
                  'rate': formatSpeed(snapshot.uploadBytesPerSecond),
                  'total': formatBytes(snapshot.uploadBytes),
                }),
                key: const ValueKey('queue-http-upload'),
              ),
              Text(
                strings.format('downloadTraffic', {
                  'rate': formatSpeed(snapshot.downloadBytesPerSecond),
                  'total': formatBytes(snapshot.downloadBytes),
                }),
                key: const ValueKey('queue-http-download'),
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            runSpacing: 3,
            children: [
              Text(
                strings.format('uploadLimit', {
                  'limit': _limitLabel(strings, limits.uploadBytesPerSecond),
                }),
              ),
              Text(
                strings.format('downloadLimit', {
                  'limit': _limitLabel(strings, limits.downloadBytesPerSecond),
                }),
              ),
            ],
          ),
          if (unsupported)
            Text(
              strings.text('unsupportedTraffic'),
              key: const ValueKey('queue-http-unsupported'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (kIsWeb)
            Text(
              strings.text('browserUpload'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
