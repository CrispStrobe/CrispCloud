import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/storage_analyzer_strings.dart';
import '../models/storage_analysis.dart';
import '../providers/providers.dart';
import '../services/file_operation_service.dart';
import '../services/storage_scan_backend.dart';
import '../services/storage_scan_service.dart';
import '../utils/formatters.dart';
import 'storage_analysis_view.dart';

/// Capture the actual active endpoint before opening the asynchronous scan.
Future<void> showStorageAnalyzerDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final strings = StorageAnalyzerStrings(context);
  final side = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(side));
  try {
    if (panel.showingSearchResults) {
      throw StateError('A real folder is required.');
    }
    final origin = panel.captureCurrentOrigin();
    final source = storageScanBackend(
      source: origin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: () => origin.isCurrent,
    );
    await showDialog<void>(
      context: context,
      builder: (_) => StorageAnalyzerDialog(
        source: source,
        rootPath: origin.source.currentPath,
        sourceLabel: origin.source.displayName,
        onReveal: (node) async {
          if (!origin.isCurrent) throw StateError('Storage changed.');
          final directory = node.isFolder
              ? node.path
              : source.paths.dirname(node.path);
          await panel.navigateToPath(
            directory,
            origin: origin,
            selectItem: node.isFolder ? null : node.item,
          );
          // Locked tabs, declined folder grants and failed listings can return
          // normally. Keep the report open unless reveal actually succeeded.
          final navigated = panel.captureCurrentOrigin();
          if (!origin.isCurrent ||
              navigated.storageId != origin.storageId ||
              !source.samePath(navigated.source.currentPath, directory) ||
              (!node.isFolder &&
                  !panel.selection.any(
                    (file) =>
                        (file.path != null &&
                            source.samePath(file.path!, node.path)) ||
                        (node.item.uuid != null && file.uuid == node.item.uuid),
                  ))) {
            throw StateError('The original item could not be revealed.');
          }
        },
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.text('title')),
        content: Text(strings.text('openFolderFirst')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.text('close')),
          ),
        ],
      ),
    );
  }
}

/// A metadata-only analyzer, also usable with injected storage in widget tests.
class StorageAnalyzerDialog extends StatefulWidget {
  const StorageAnalyzerDialog({
    super.key,
    required this.source,
    required this.rootPath,
    required this.sourceLabel,
    this.onReveal,
    this.service,
  });

  final FileOperationBackend source;
  final String rootPath;
  final String sourceLabel;
  final Future<void> Function(StorageNode)? onReveal;
  final StorageScanService? service;

  @override
  State<StorageAnalyzerDialog> createState() => _StorageAnalyzerDialogState();
}

class _StorageAnalyzerDialogState extends State<StorageAnalyzerDialog> {
  bool _scanning = false;
  bool _cancelled = false;
  bool _revealing = false;
  StorageScanProgress? _progress;
  StorageScanResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_scan());
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _cancelled = false;
      _result = null;
      _progress = null;
      _error = null;
    });
    try {
      final result = await (widget.service ?? StorageScanService()).scan(
        widget.source,
        widget.rootPath,
        isCancelled: () => _cancelled || !mounted,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _reveal(StorageNode node) async {
    if (_revealing || widget.onReveal == null) return;
    final strings = StorageAnalyzerStrings(context);
    final route = ModalRoute.of(context);
    setState(() => _revealing = true);
    try {
      if (!widget.source.isCurrent) throw StateError('Storage changed.');
      await widget.onReveal!(node);
      if (mounted && route?.isCurrent == true) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(strings.text('revealFailed'))));
      }
    } finally {
      if (mounted) setState(() => _revealing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = StorageAnalyzerStrings(context);
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final result = _result;
    return Dialog(
      insetPadding: EdgeInsets.all(size.width < 600 ? 8 : 24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: math.min(1240, size.width - 16),
        height: math.min(900, size.height - 32),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.space_dashboard_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.text('title'),
                          style: theme.textTheme.titleLarge,
                        ),
                        Text(
                          widget.sourceLabel,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: strings.text('close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: result != null
                  ? StorageAnalysisView(
                      analysis: result,
                      onReveal:
                          widget.onReveal == null ||
                              _revealing ||
                              result.sourceChanged
                          ? null
                          : _reveal,
                    )
                  : Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _error == null
                                    ? Icons.folder_open
                                    : Icons.error_outline,
                                size: 48,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                strings.text(
                                  _error == null
                                      ? (_cancelled ? 'stopping' : 'scanning')
                                      : 'failed',
                                ),
                                style: theme.textTheme.titleMedium,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              if (_scanning) ...[
                                const LinearProgressIndicator(),
                                const SizedBox(height: 12),
                                Text(
                                  strings.text('progress', {
                                    'files': _progress?.files ?? 0,
                                    'folders': _progress?.folders ?? 0,
                                    'size': formatBytes(_progress?.bytes ?? 0),
                                  }),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                _progress?.currentPath ?? widget.rootPath,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                strings.text('scope'),
                                textAlign: TextAlign.center,
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                SelectableText(
                                  _error!,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.rootPath,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_scanning)
                    OutlinedButton.icon(
                      onPressed: _cancelled
                          ? null
                          : () => setState(() => _cancelled = true),
                      icon: const Icon(Icons.stop, size: 18),
                      label: Text(strings.text('cancel')),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: widget.source.isCurrent && !_revealing
                          ? _scan
                          : null,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(strings.text('scanAgain')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
