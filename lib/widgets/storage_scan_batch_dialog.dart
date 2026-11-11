import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../l10n/storage_analyzer_strings.dart';
import '../providers/providers.dart';
import '../services/local_file_service.dart';
import '../services/panel_source_service.dart';
import '../services/storage_scan_backend.dart';
import '../services/storage_scan_batch_service.dart';
import '../utils/formatters.dart';
import 'storage_analyzer_dialog.dart';

class StorageScanBatchCaptureFailure implements Exception {
  const StorageScanBatchCaptureFailure(this.key, [this.values = const {}]);

  final String key;
  final Map<String, Object> values;
}

String _capturedSourceLabel(PanelFileOrigin origin) {
  final source = origin.source;
  if (source is! RemotePanelSource) return source.displayName;
  final account = origin.storageReference.accountKey;
  final prefix = account.substring(0, account.length < 8 ? account.length : 8);
  return '${source.displayName} · $prefix';
}

/// Capture every requested row before opening a dialog or awaiting any work.
/// Compact off-page marks are not capabilities and must never resolve through
/// whichever account happens to be active when a later job starts.
List<StorageScanBatchRoot> captureMarkedStorageScanRoots(
  PanelNotifier panel,
  LocalFileService local, {
  String Function(PanelFileOrigin)? sourceLabel,
}) {
  final folders = panel.selection
      .where((file) => file.isFolder && file.name != '..' && file.name != '.')
      .take(StorageScanBatchService.maxRoots + 1)
      .toList(growable: false);
  if (folders.isEmpty) {
    throw const StorageScanBatchCaptureFailure('batchNoFolders');
  }
  if (folders.length > StorageScanBatchService.maxRoots) {
    throw const StorageScanBatchCaptureFailure('batchRootLimit', {
      'count': StorageScanBatchService.maxRoots,
    });
  }
  final roots = <StorageScanBatchRoot>[];
  for (final folder in folders) {
    final origin = panel.originForFile(folder);
    final path = folder.path;
    if (origin == null &&
        panel.isPagedCollection &&
        !(panel.files?.any((file) => identical(file, folder)) ?? false)) {
      throw StorageScanBatchCaptureFailure('batchUnverified', {
        'path': path ?? folder.name,
      });
    }
    if (origin?.isCurrent != true ||
        path == null ||
        path.isEmpty ||
        folder.isSymlink == true) {
      throw StorageScanBatchCaptureFailure('batchUnavailable', {
        'path': path ?? folder.name,
      });
    }
    try {
      final source = origin!.source;
      roots.add(
        StorageScanBatchRoot(
          source: storageScanBackend(
            source: source is LocalPanelSource
                ? LocalPanelSource(path)
                : source,
            local: local,
            isCurrent: () => origin.isCurrent,
          ),
          rootPath: path,
          storage: origin.storageReference,
          sourceLabel:
              sourceLabel?.call(origin) ?? _capturedSourceLabel(origin),
          // Remote clients may share mutable sessions between listings. Local
          // scans already own independent scoped workers/snapshot readers.
          serialReadKey: source is RemotePanelSource ? source.client : null,
          snapshotStorageId: kIsWeb && source is LocalPanelSource
              ? 'browser-grant-session:${const Uuid().v4()}'
              : origin.storageId,
        ),
      );
    } catch (_) {
      throw StorageScanBatchCaptureFailure('batchUnavailable', {'path': path});
    }
  }
  return List.unmodifiable(roots);
}

Future<void> showStorageScanBatchDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final strings = StorageAnalyzerStrings(context);
  final panel = ref.read(panelProvider(ref.read(activePanelProvider)));
  late List<StorageScanBatchRoot> roots;
  try {
    roots = captureMarkedStorageScanRoots(
      panel,
      ref.read(localFileServiceProvider),
      sourceLabel: (origin) {
        final source = origin.source;
        if (source is RemotePanelSource) {
          for (final connection in ref.read(multiCloudProvider).connections) {
            if (identical(connection.client, source.client)) {
              return '${connection.label} (${origin.storageReference.provider})';
            }
          }
          final auth = ref.read(authProvider);
          if (identical(auth.client, source.client)) {
            final email = auth.userEmail;
            if (email?.isNotEmpty == true) {
              return '${origin.storageReference.provider} · $email';
            }
          }
        }
        return _capturedSourceLabel(origin);
      },
    );
  } on StorageScanBatchCaptureFailure catch (failure) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(strings.text(failure.key, failure.values))),
    );
    return;
  }
  if (!context.mounted) return;
  final batch = StorageScanBatchService(roots: roots);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => StorageScanBatchDialog(batch: batch),
  );
}

class StorageScanBatchDialog extends StatefulWidget {
  const StorageScanBatchDialog({super.key, required this.batch});

  final StorageScanBatchService batch;

  @override
  State<StorageScanBatchDialog> createState() => _StorageScanBatchDialogState();
}

class _StorageScanBatchDialogState extends State<StorageScanBatchDialog> {
  StorageScanBatchService get _batch => widget.batch;

  @override
  void initState() {
    super.initState();
    _batch.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _batch.removeListener(_changed);
    _batch.dispose();
    super.dispose();
  }

  String _status(StorageScanBatchJob job, StorageAnalyzerStrings strings) {
    if (job.phase == StorageScanBatchPhase.partial) {
      return '${strings.text('scanSaved')} · ${strings.text('partial')}';
    }
    return strings.text(switch (job.phase) {
      StorageScanBatchPhase.ready => 'batchReady',
      StorageScanBatchPhase.queued => 'queued',
      StorageScanBatchPhase.scanning => 'scanning',
      StorageScanBatchPhase.saving => 'savingScan',
      StorageScanBatchPhase.stopping => 'stopping',
      StorageScanBatchPhase.saved => 'scanSaved',
      StorageScanBatchPhase.partial => 'partial',
      StorageScanBatchPhase.cancelled => 'batchStopped',
      StorageScanBatchPhase.failed => 'failed',
      StorageScanBatchPhase.sourceChanged => 'sourceChanged',
      StorageScanBatchPhase.unconfirmed => 'batchUnconfirmed',
    });
  }

  Future<void> _openSaved(StorageScanBatchJob job) async {
    final saved = job.snapshot;
    if (saved == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => StorageAnalyzerDialog(
        historyOnly: true,
        sourceLabel: saved.sourceLabel,
        initialSnapshot: saved,
        snapshotStore: _batch.snapshots,
      ),
    );
  }

  Future<void> _inspectHistory() async {
    await showDialog<void>(
      context: context,
      builder: (_) => StorageAnalyzerDialog(
        historyOnly: true,
        snapshotStore: _batch.snapshots,
      ),
    );
  }

  Widget _job(
    StorageScanBatchJob job,
    int index,
    StorageAnalyzerStrings strings,
  ) {
    final summary = job.summary;
    final progress = job.progress;
    return Card(
      key: ValueKey('scan-batch-job-$index'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              job.root.sourceLabel,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Tooltip(
              message: job.root.rootPath,
              child: Text(
                job.root.rootPath,
                key: ValueKey('scan-batch-path-$index'),
                textDirection: TextDirection.ltr,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _status(job, strings),
              key: ValueKey('scan-batch-status-$index'),
            ),
            if (summary != null || progress != null) ...[
              const SizedBox(height: 4),
              Text(
                strings.text('progress', {
                  'files': summary?.fileCount ?? progress!.files,
                  'folders': summary?.folderCount ?? progress!.folders,
                  'size': formatBytes(summary?.bytes ?? progress!.bytes),
                }),
              ),
            ],
            if (summary != null && !summary.isComplete)
              Text(strings.text('partialHint')),
            if (summary != null && summary.unknownSizeCount > 0)
              Text(
                strings.text('unknown', {'count': summary.unknownSizeCount}),
              ),
            if (summary?.limited == true) Text(strings.text('limited')),
            if (job.error != null)
              Text(
                strings.text('snapshotFailed', {'error': job.error!}),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (job.phase == StorageScanBatchPhase.unconfirmed) ...[
              Text(
                strings.text('batchUnconfirmedHint', {
                  'history': strings.text('savedScans'),
                }),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: ValueKey('scan-batch-history-$index'),
                  onPressed: _inspectHistory,
                  icon: const Icon(Icons.history),
                  label: Text(strings.text('savedScans')),
                ),
              ),
            ],
            if (job.snapshot != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: ValueKey('scan-batch-open-$index'),
                  onPressed: () => _openSaved(job),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(strings.text('openSavedScan')),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = StorageAnalyzerStrings(context);
    final size = MediaQuery.sizeOf(context);
    final saved = _batch.jobs.where((job) => job.snapshot != null).length;
    final partial = _batch.jobs
        .where((job) => job.phase == StorageScanBatchPhase.partial)
        .length;
    final failed = _batch.jobs
        .where(
          (job) =>
              job.phase == StorageScanBatchPhase.failed ||
              job.phase == StorageScanBatchPhase.sourceChanged,
        )
        .length;
    final cancelled = _batch.jobs
        .where((job) => job.phase == StorageScanBatchPhase.cancelled)
        .length;
    final unconfirmed = _batch.jobs
        .where((job) => job.phase == StorageScanBatchPhase.unconfirmed)
        .length;
    return Dialog(
      insetPadding: EdgeInsets.all(size.width < 600 ? 8 : 24),
      child: SizedBox(
        width: math.min(780, size.width - 16),
        height: math.min(700, size.height - 32),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.text('batchTitle'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(strings.text('batchReview', {'count': _batch.jobs.length})),
              if (_batch.hasStarted) ...[
                const SizedBox(height: 8),
                Text(
                  strings.text('batchSummary', {
                    'saved': saved,
                    'partial': partial,
                    'failed': failed,
                    'cancelled': cancelled,
                  }),
                ),
                if (unconfirmed > 0)
                  Text(
                    strings.text('batchUnconfirmedCount', {
                      'count': unconfirmed,
                    }),
                  ),
              ],
              if (_batch.isRunning) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _batch.jobs.length,
                  itemBuilder: (context, index) =>
                      _job(_batch.jobs[index], index, strings),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  if (!_batch.hasStarted)
                    FilledButton.icon(
                      key: const ValueKey('scan-batch-start'),
                      onPressed: () => unawaited(_batch.start()),
                      icon: const Icon(Icons.save_outlined),
                      label: Text(strings.text('batchStart')),
                    ),
                  if (_batch.isRunning)
                    OutlinedButton(
                      key: const ValueKey('scan-batch-stop'),
                      onPressed: _batch.isStopping ? null : _batch.cancel,
                      child: Text(strings.text('batchStop')),
                    ),
                  TextButton(
                    key: const ValueKey('scan-batch-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      strings.text(
                        _batch.isRunning ? 'batchStopAndClose' : 'close',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
