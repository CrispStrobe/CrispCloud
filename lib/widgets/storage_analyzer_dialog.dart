import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../l10n/storage_analyzer_strings.dart';
import '../models/file_item.dart';
import '../providers/providers.dart';
import '../services/file_operation_service.dart';
import '../services/panel_source_service.dart';
import '../services/storage_scan_backend.dart';
import '../services/storage_scan_service.dart';
import '../services/storage_scan_snapshot_store.dart';
import '../utils/formatters.dart';
import 'storage_analysis_view.dart';
import 'catalogue_dialog.dart';
import '../l10n/catalogue_strings.dart';

/// Analyze the exact folder chosen in a context menu, including remote folders.
/// The report owns its original endpoint and exposes cancellation/partial data.
Future<void> showFolderSizeDialog(
  BuildContext context,
  WidgetRef ref,
  FileItem folder,
  PanelFileOrigin origin,
) async {
  try {
    if (!origin.isCurrent ||
        !folder.isFolder ||
        folder.isSymlink == true ||
        folder.path == null)
      throw StateError('Folder unavailable.');
    final source = storageScanBackend(
      source: origin.source is LocalPanelSource
          ? LocalPanelSource(folder.path!)
          : origin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: () => origin.isCurrent,
    );
    await showDialog<void>(
      context: context,
      builder: (_) => StorageAnalyzerDialog(
        source: source,
        rootPath: folder.path!,
        sourceLabel: origin.source.displayName,
        storageId: kIsWeb && origin.source is LocalPanelSource
            ? 'browser-grant-session:${const Uuid().v4()}'
            : origin.storageId,
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(StorageAnalyzerStrings(context).text('openFolderFirst')),
      ),
    );
  }
}

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
        // A later browser picker grant may reuse the same display path and
        // installation ID while referring to an entirely different folder.
        // Only this dialog's captured grant may activate its saved live actions.
        storageId: kIsWeb && origin.source is LocalPanelSource
            ? 'browser-grant-session:${const Uuid().v4()}'
            : origin.storageId,
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
              !source.isCurrent ||
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
      builder: (_) => StorageAnalyzerDialog(
        sourceLabel: strings.text('historyOnly'),
        historyOnly: true,
      ),
    );
  }
}

/// A metadata-only analyzer, also usable with injected storage in widget tests.
class StorageAnalyzerDialog extends StatefulWidget {
  const StorageAnalyzerDialog({
    super.key,
    this.source,
    this.rootPath = '',
    this.sourceLabel = '',
    this.storageId,
    this.historyOnly = false,
    this.onReveal,
    this.service,
    this.snapshotStore,
    this.initialSnapshot,
  });

  final FileOperationBackend? source;
  final String rootPath;
  final String sourceLabel;

  /// A stable opaque account/endpoint reference; never a client or credential.
  final String? storageId;
  final bool historyOnly;
  final Future<void> Function(StorageNode)? onReveal;
  final StorageScanService? service;
  final StorageScanSnapshotStore? snapshotStore;
  final StorageScanSnapshotSummary? initialSnapshot;

  @override
  State<StorageAnalyzerDialog> createState() => _StorageAnalyzerDialogState();
}

class _StorageAnalyzerDialogState extends State<StorageAnalyzerDialog> {
  bool _scanning = false;
  bool _cancelled = false;
  bool _revealing = false;
  bool _saving = false;
  bool _showHistory = false;
  bool _historyLoading = false;
  bool _openingSnapshot = false;
  int _generation = 0;
  int _historyGeneration = 0;
  late final StorageScanSnapshotStore _snapshots;
  late final Object? _sourceIdentity;
  late final String _storageId;
  List<StorageScanSnapshotSummary> _history = [];
  StorageScanSnapshotSummary? _saved;
  String? _historyError;
  StorageScanProgress? _progress;
  StorageScanResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _snapshots = widget.snapshotStore ?? StorageScanSnapshotStore();
    _sourceIdentity = widget.source?.identity;
    _storageId =
        widget.storageId ??
        widget.source?.persistentStorageId ??
        'session:${const Uuid().v4()}';
    if (widget.initialSnapshot != null) {
      unawaited(_openSaved(widget.initialSnapshot!));
    } else if (widget.historyOnly || widget.source == null) {
      _showHistory = true;
      unawaited(_loadHistory());
    } else {
      unawaited(_scan());
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    _generation++;
    _historyGeneration++;
    super.dispose();
  }

  Future<void> _scan() async {
    final source = widget.source;
    if (_scanning || source == null || !_canUseSource) return;
    final generation = ++_generation;
    setState(() {
      _scanning = true;
      _cancelled = false;
      _result = null;
      _progress = null;
      _error = null;
      _saved = null;
      _showHistory = false;
    });
    try {
      final result = await (widget.service ?? const StorageScanService()).scan(
        source,
        widget.rootPath,
        isCancelled: () => _cancelled || !mounted || generation != _generation,
        onProgress: (progress) {
          if (mounted && generation == _generation) {
            setState(() => _progress = progress);
          }
        },
      );
      if (mounted && generation == _generation) {
        setState(() => _result = result);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _scanning = false);
      }
    }
  }

  bool get _canUseSource {
    final source = widget.source;
    if (source == null ||
        !source.isCurrent ||
        source.identity != _sourceIdentity) {
      return false;
    }
    final saved = _saved;
    return saved == null ||
        (saved.storageId == _storageId &&
            source.samePath(
              saved.rootPath,
              source.paths.normalize(widget.rootPath),
            ));
  }

  Future<void> _loadHistory() async {
    final generation = ++_historyGeneration;
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });
    try {
      final entries = await _snapshots.list();
      if (mounted && generation == _historyGeneration) {
        setState(() => _history = entries);
      }
    } catch (error) {
      if (mounted && generation == _historyGeneration) {
        setState(() => _historyError = error.toString());
      }
    } finally {
      if (mounted && generation == _historyGeneration) {
        setState(() => _historyLoading = false);
      }
    }
  }

  void _historyView() {
    setState(() => _showHistory = !_showHistory);
    if (_showHistory) unawaited(_loadHistory());
  }

  Future<void> _openSaved(StorageScanSnapshotSummary summary) async {
    final generation = ++_generation;
    setState(() {
      _cancelled = true;
      _scanning = false;
      _openingSnapshot = true;
      _result = null;
      _progress = null;
      _error = null;
      _showHistory = false;
    });
    try {
      final snapshot = await _snapshots.load(summary.id);
      if (!mounted || generation != _generation) return;
      setState(() {
        _saved = snapshot.summary;
        _result = snapshot.result;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _openingSnapshot = false);
      }
    }
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null || _saving || _saved != null) return;
    final generation = _generation;
    final strings = StorageAnalyzerStrings(context);
    setState(() => _saving = true);
    try {
      final saved = await _snapshots.save(
        result: result,
        storageId: _storageId,
        sourceLabel: widget.sourceLabel,
        pathStyle: widget.source?.paths.style,
      );
      if (!mounted) return;
      if (generation == _generation) setState(() => _saved = saved);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(strings.text('scanSaved'))));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              strings.text('snapshotFailed', {'error': error.toString()}),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteSaved(StorageScanSnapshotSummary summary) async {
    try {
      await _snapshots.delete(summary.id);
      if (mounted) {
        if (_saved?.id == summary.id) {
          setState(() {
            _generation++;
            _saved = null;
            _result = null;
            _showHistory = true;
          });
        }
        await _loadHistory();
      }
    } catch (error) {
      if (mounted) setState(() => _historyError = error.toString());
    }
  }

  String _time(DateTime time) {
    final local = time.toLocal();
    final text = MaterialLocalizations.of(context);
    return '${text.formatMediumDate(local)} ${text.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  Widget _historyBody(StorageAnalyzerStrings strings) {
    if (_historyLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_historyError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(
            strings.text('snapshotFailed', {'error': _historyError!}),
          ),
        ),
      );
    }
    if (_history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            strings.text('noSavedScans'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final saved = _history[index];
        return ListTile(
          key: ValueKey('saved-scan-${saved.id}'),
          leading: const Icon(Icons.history),
          title: Text(
            saved.sourceLabel.isEmpty ? saved.rootPath : saved.sourceLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${saved.rootPath}\n${strings.text('savedScanAt', {'time': _time(saved.savedAt)})}'
            ' · ${formatBytes(saved.bytes)}${saved.isComplete ? '' : ' · ${strings.text('partial')}'}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _openSaved(saved),
          trailing: IconButton(
            tooltip: strings.text('deleteSavedScan'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteSaved(saved),
          ),
        );
      },
    );
  }

  Future<void> _reveal(StorageNode node) async {
    if (_revealing || widget.onReveal == null) return;
    final strings = StorageAnalyzerStrings(context);
    final route = ModalRoute.of(context);
    final generation = _generation;
    setState(() => _revealing = true);
    try {
      if (!_canUseSource) throw StateError('Storage changed.');
      await widget.onReveal!(node);
      if (!mounted || generation != _generation) return;
      if (!_canUseSource) throw StateError('Storage changed.');
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
                          _saved?.sourceLabel ?? widget.sourceLabel,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_saved != null)
                          Text(
                            strings.text('historicalScan', {
                              'time': _time(_saved!.completedAt),
                            }),
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Builder(
                    builder: (context) => IconButton(
                      tooltip: CatalogueStrings(context).text('Catalogues'),
                      icon: const Icon(Icons.inventory_2_outlined),
                      onPressed: () => showCatalogueLibrary(
                        context,
                        local: ProviderScope.containerOf(
                          context,
                          listen: false,
                        ).read(localFileServiceProvider),
                      ),
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
              child: _showHistory
                  ? _historyBody(strings)
                  : result != null
                  ? StorageAnalysisView(
                      key: ValueKey(result),
                      analysis: result,
                      onReveal:
                          widget.onReveal == null ||
                              _revealing ||
                              !_canUseSource ||
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
                                      ? (_openingSnapshot
                                            ? 'loadingSavedScans'
                                            : _scanning
                                            ? (_cancelled
                                                  ? 'stopping'
                                                  : 'scanning')
                                            : 'historyOnly')
                                      : 'failed',
                                ),
                                style: theme.textTheme.titleMedium,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              if (_scanning || _openingSnapshot) ...[
                                const LinearProgressIndicator(),
                                const SizedBox(height: 12),
                                if (_scanning)
                                  Text(
                                    strings.text('progress', {
                                      'files': _progress?.files ?? 0,
                                      'folders': _progress?.folders ?? 0,
                                      'size': formatBytes(
                                        _progress?.bytes ?? 0,
                                      ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _showHistory
                        ? strings.text('offlineScan')
                        : _result?.root.path ?? widget.rootPath,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _saving || _openingSnapshot || _revealing
                            ? null
                            : _historyView,
                        icon: const Icon(Icons.history, size: 18),
                        label: Text(strings.text('savedScans')),
                      ),
                      if (!_showHistory && result != null)
                        OutlinedButton.icon(
                          onPressed: _saving || _saved != null ? null : _save,
                          icon: Icon(
                            _saved == null ? Icons.save_outlined : Icons.check,
                            size: 18,
                          ),
                          label: Text(
                            strings.text(
                              _saving
                                  ? 'savingScan'
                                  : _saved == null
                                  ? 'saveScan'
                                  : 'scanSaved',
                            ),
                          ),
                        ),
                      if (_scanning)
                        OutlinedButton.icon(
                          onPressed: _cancelled
                              ? null
                              : () => setState(() => _cancelled = true),
                          icon: const Icon(Icons.stop, size: 18),
                          label: Text(strings.text('cancel')),
                        )
                      else if (widget.source != null)
                        OutlinedButton.icon(
                          onPressed:
                              _canUseSource &&
                                  !_revealing &&
                                  !_saving &&
                                  !_openingSnapshot
                              ? _scan
                              : null,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(
                            strings.text(
                              _saved == null ? 'scanAgain' : 'updateSavedScan',
                            ),
                          ),
                        ),
                    ],
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
