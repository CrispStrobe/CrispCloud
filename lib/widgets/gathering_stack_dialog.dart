import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../l10n/gathering_stack_strings.dart';
import '../models/file_item.dart';
import '../models/gathering_stack.dart';
import '../models/panel_side.dart';
import '../models/storage_reference.dart';
import '../providers/core_providers.dart';
import '../providers/gathering_stack_provider.dart';
import '../providers/panel_provider.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import '../services/gathering_stack_service.dart';
import '../services/gathering_stack_store.dart';
import '../services/local_file_service.dart';
import 'file_operation_dialog.dart';

PanelFileOrigin? _withOriginalGrant(
  PanelFileOrigin origin,
  LocalFileService local,
  String path,
) {
  if (!origin.source.isLocal || local is! LocalFileSourceIdentity) {
    return origin;
  }
  final identities = local as LocalFileSourceIdentity;
  final grant = identities.sourceIdentityForPath(path);
  if (grant == null) return null;
  var lost = false;
  return origin.withAvailabilityGuard(() {
    if (!identical(identities.sourceIdentityForPath(path), grant)) lost = true;
    return !lost;
  });
}

GatheringSourceBinding? _binding(
  PanelFileOrigin? origin,
  LocalFileService local,
  String path,
) {
  if (origin == null) return null;
  final captured = _withOriginalGrant(origin, local, path);
  if (captured == null) return null;
  return GatheringSourceBinding(
    storage: captured.storageReference,
    backend: fileOperationBackend(
      source: captured.source,
      local: local,
      isCurrent: () => captured.isCurrent,
    ),
    hostContext: captured,
  );
}

/// Capture the actual destination independently of the visual pane's label.
GatheringDestinationCapture captureGatheringDestination(
  PanelNotifier panel,
  LocalFileService local,
) {
  if (!panel.hasVerifiedDirectoryListing || panel.isLoading) {
    throw const GatheringException(GatheringFailure.destinationChanged);
  }
  final original = panel.captureCurrentOrigin();
  final path = original.source.currentPath;
  final origin = _withOriginalGrant(original, local, path);
  if (origin == null) {
    throw const GatheringException(GatheringFailure.destinationChanged);
  }
  final tab = panel.activeTabId;
  final navigation = panel.navigationIntentRevision;
  final listing = panel.captureOperationSession();
  return GatheringDestinationCapture(
    backend: fileOperationBackend(
      source: origin.source,
      local: local,
      isCurrent: () => origin.isCurrent,
    ),
    path: path,
    hostContext: origin,
    isCurrent: () =>
        origin.isCurrent &&
        panel.activeTabId == tab &&
        panel.navigationIntentRevision == navigation &&
        panel.hasVerifiedDirectoryListing &&
        !panel.isLoading,
    isReviewCurrent: listing,
  );
}

Future<GatheringAddResult> _gatherSelection(
  WidgetRef ref,
  PanelSide side,
) async {
  final panel = ref.read(panelProvider(side));
  final local = ref.read(localFileServiceProvider);
  final session = panel.captureOperationSession();
  final intent = panel.navigationIntentRevision;
  final requested = List<FileItem>.unmodifiable(panel.selection);
  if (requested.length > GatheringStackStore.maximumEntries) {
    throw const GatheringException(GatheringFailure.limit);
  }
  if (requested.isEmpty) throw const GatheringException(GatheringFailure.empty);
  // Ordinary rows can capture every original synchronously. Paged marks use
  // the existing original-resolution contract and the session pinned above.
  final paged = panel.isPagedCollection;
  var groups = paged ? null : panel.captureOperationGroups(requested);
  final files = paged
      ? await panel.prepareOperationFiles(requested)
      : requested;
  bool current() => session() && intent == panel.navigationIntentRevision;
  if (!current()) throw const GatheringException(GatheringFailure.changed);
  groups ??= panel.captureOperationGroups(files);
  final additions = <GatheringAddition>[];
  for (final group in groups.entries) {
    for (final file in group.value) {
      final source = _binding(group.key, local, file.path!);
      if (source == null) {
        throw const GatheringException(GatheringFailure.unavailable);
      }
      additions.add(
        GatheringAddition(
          file: file,
          source: source,
          sessionBound:
              source.storage.isLocal &&
              (kIsWeb || local is LocalFileSourceIdentity),
        ),
      );
    }
  }
  return ref
      .read(gatheringStackServiceProvider)
      .add(additions, isCurrent: current);
}

/// Host hook for menus, shortcuts, and the selected-row context menu.
Future<void> addPanelSelectionToGatheringStack(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
) async {
  try {
    final result = await _gatherSelection(ref, side);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          GatheringStackStrings(context)
              .text('added', [result.added, result.refreshed]),
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(GatheringStackStrings(context).failure(error))),
    );
  }
}

String _sourceLabel(PanelNotifier panel, StorageReference storage) {
  final key = storage.accountKey;
  final short = key.substring(0, math.min(key.length, 8));
  return '${panel.storageDisplayName(storage)} · $short';
}

/// Host hook. The active verified folder is captured before opening the stack.
Future<void> showGatheringStackDialog(
  BuildContext context,
  WidgetRef ref, {
  required PanelSide destinationSide,
}) async {
  final panel = ref.read(panelProvider(destinationSide));
  final local = ref.read(localFileServiceProvider);
  final service = ref.read(gatheringStackServiceProvider);
  GatheringDestinationCapture? destination;
  try {
    destination = captureGatheringDestination(panel, local);
  } catch (_) {
    // Managing saved references stays available outside a writable folder.
  }
  await showDialog<void>(
    context: context,
    builder: (_) => GatheringStackDialog(
      service: service,
      resolve: (storage, path) =>
          _binding(panel.resolveStorageReference(storage, path), local, path),
      destination: destination,
      sourceLabel: (storage) => _sourceLabel(panel, storage),
      onGather: () => _gatherSelection(ref, destinationSide),
      onTransfer: (dialogContext, review, kind) async {
        final strings = GatheringStackStrings(dialogContext);
        final byStorage = <StorageReference, List<GatheringStackEntry>>{};
        for (final entry in review.capture.entries) {
          byStorage.putIfAbsent(entry.reference.storage, () => []).add(entry);
        }
        final groups = <PanelFileOrigin, List<FileItem>>{};
        for (final entries in byStorage.values) {
          final origins = [
            for (final entry in entries)
              review.capture.sources[entry.id]!.hostContext as PanelFileOrigin,
          ];
          final captured = origins.first.withAvailabilityGuard(
            () => origins.every((origin) => origin.isCurrent),
          );
          groups[captured] = List.unmodifiable([
            for (final entry in entries) review.verified[entry.id]!.file,
          ]);
        }
        await showFileOperationDialog(
          dialogContext,
          ref,
          destinationSide,
          groups.values.expand((files) => files).toList(),
          kind: kind,
          sourceGroups: groups,
          destinationOrigin:
              review.capture.destination!.hostContext as PanelFileOrigin,
          destinationPath: review.capture.destination!.path,
          lockedDestinationSide: destinationSide,
          isReviewCurrent: () => review.canTransfer,
          onPreparedPlan: (plan) {
            try {
              review.validatePlan(plan);
            } catch (error) {
              throw StateError(strings.failure(error));
            }
          },
          onForegroundPlan: (plan) async {
            try {
              await service.reconcile(review, plan);
            } catch (_) {
              throw StateError(strings.text('storageFailure'));
            }
          },
          groupLabel: (index, count, origin) => strings.text('account', [
            index,
            count,
            _sourceLabel(panel, origin.storageReference),
          ]),
        );
      },
    ),
  );
}

typedef GatheringTransferReview = Future<void> Function(
  BuildContext context,
  GatheringReview review,
  FileOperationKind kind,
);

/// Presentation depends on captured capabilities and is testable without
/// inferring sources from panel positions or creating a synthetic panel list.
class GatheringStackDialog extends StatefulWidget {
  const GatheringStackDialog({
    super.key,
    required this.service,
    required this.resolve,
    required this.sourceLabel,
    required this.onTransfer,
    this.destination,
    this.onGather,
  });
  final GatheringStackService service;
  final GatheringSourceResolver resolve;
  final String Function(StorageReference storage) sourceLabel;
  final GatheringDestinationCapture? destination;
  final Future<GatheringAddResult> Function()? onGather;
  final GatheringTransferReview onTransfer;

  @override
  State<GatheringStackDialog> createState() => _GatheringStackDialogState();
}

class _GatheringStackDialogState extends State<GatheringStackDialog> {
  bool _busy = true;
  bool _checking = false;
  String? _message;
  int _complete = 0;
  int _total = 0;
  int _action = 0;
  FileOperationControl? _control;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (widget.service.store.isLoading) await widget.service.store.ready;
    if (!mounted) return;
    setState(() => _busy = false);
    if (widget.service.store.loadError == null &&
        widget.service.store.entries.isNotEmpty) {
      await _check();
    }
  }

  @override
  void dispose() {
    _action++;
    _control?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _complete = 0;
      _total = 0;
      _control = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) _message = GatheringStackStrings(context).failure(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<GatheringReview> _verify({bool transfer = false}) async {
    final action = ++_action;
    final control = _control = FileOperationControl();
    setState(() => _checking = true);
    try {
      final capture = widget.service.capture(
        resolve: widget.resolve,
        destination: transfer ? widget.destination : null,
        isCurrent: () => mounted && action == _action,
      );
      return await widget.service.verify(
        capture,
        control: control,
        onProgress: (completed, total) {
          if (mounted && action == _action) {
            setState(() {
              _complete = completed;
              _total = total;
            });
          }
        },
      );
    } finally {
      if (mounted && action == _action) {
        setState(() {
          _checking = false;
          _control = null;
        });
      }
    }
  }

  Future<void> _check() => _run(() async {
    await _verify();
  });

  Future<void> _transfer(FileOperationKind kind) => _run(() async {
    if (widget.destination?.isCurrent != true) {
      throw const GatheringException(GatheringFailure.destinationChanged);
    }
    final review = await _verify(transfer: true);
    if (!mounted) return;
    if (!review.canTransfer) {
      _message = GatheringStackStrings(context).text('blocked');
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => GatheringTransferOverview(
        review: review,
        sourceLabel: widget.sourceLabel,
        kind: kind,
      ),
    );
    if (accepted != true || !mounted) return;
    review.capture.check();
    if (!review.canTransfer) {
      throw const GatheringException(GatheringFailure.unavailable);
    }
    review.capture.destination!.accept();
    await widget.onTransfer(context, review, kind);
  });

  String? _destinationLabel() {
    final destination = widget.destination;
    if (destination == null) return null;
    return '${destination.storage == null ? destination.backend.label : widget.sourceLabel(destination.storage!)} · ${destination.path}';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service.store,
    builder: (context, _) {
      final strings = GatheringStackStrings(context);
      final store = widget.service.store;
      final entries = store.entries;
      final destination = _destinationLabel();
      final canReview =
          !_busy &&
          entries.isNotEmpty &&
          store.loadError == null &&
          widget.destination?.isCurrent == true;
      return PopScope(
        canPop: !_busy,
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 16,
          ),
          title: Text(strings.text('title')),
          content: SizedBox(
            width: 900,
            height: MediaQuery.sizeOf(context).height * .64,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(strings.text('explanation')),
                      const SizedBox(height: 12),
                      Text(
                        destination == null
                            ? strings.text('chooseDestination')
                            : strings.text('destination', [destination]),
                      ),
                      const SizedBox(height: 8),
                      Text(strings.text('count', [entries.length])),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (widget.onGather != null)
                            OutlinedButton.icon(
                              key: const ValueKey('gathering-add'),
                              onPressed: _busy || store.loadError != null
                                  ? null
                                  : () => _run(() async {
                                      final result = await widget.onGather!();
                                      if (mounted) {
                                        _message = strings.text('added', [
                                          result.added,
                                          result.refreshed,
                                        ]);
                                      }
                                    }),
                              icon: const Icon(Icons.playlist_add),
                              label: Text(strings.text('gather')),
                            ),
                          OutlinedButton.icon(
                            key: const ValueKey('gathering-refresh'),
                            onPressed: _busy
                                ? null
                                : store.loadError != null
                                ? () => _run(store.reload)
                                : _check,
                            icon: const Icon(Icons.refresh),
                            label: Text(context.commanderTr('Refresh')),
                          ),
                          FilledButton.tonal(
                            key: const ValueKey('gathering-copy'),
                            onPressed: canReview
                                ? () => _transfer(FileOperationKind.copy)
                                : null,
                            child: Text(strings.text('reviewCopy')),
                          ),
                          FilledButton.tonal(
                            key: const ValueKey('gathering-move'),
                            onPressed: canReview
                                ? () => _transfer(FileOperationKind.move)
                                : null,
                            child: Text(strings.text('reviewMove')),
                          ),
                        ],
                      ),
                      if (_checking || store.isLoading) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                        if (_total > 0)
                          Text(strings.text('progress', [_complete, _total])),
                      ],
                      if (_message != null || store.loadError != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            store.loadError != null
                                ? strings.text('storageFailure')
                                : _message!,
                            key: const ValueKey('gathering-message'),
                          ),
                        ),
                      if (entries.isEmpty && !_busy)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(strings.text('emptyHint')),
                        ),
                    ],
                  ),
                ),
                SliverList.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _GatheringRow(
                      key: ValueKey('gathering-row-${entry.id}'),
                      entry: entry,
                      state: store.stateFor(entry.id),
                      source: widget.sourceLabel(entry.reference.storage),
                      onRemove: _busy
                          ? null
                          : () => _run(() => store.remove(entry.id)),
                      onUp: _busy || index == 0
                          ? null
                          : () => _run(() => store.move(entry.id, -1)),
                      onDown: _busy || index == entries.length - 1
                          ? null
                          : () => _run(() => store.move(entry.id, 1)),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            if (_busy && _control != null)
              TextButton(
                onPressed: _control!.cancel,
                child: Text(context.commanderTr('Cancel')),
              ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: Text(context.commanderTr('Close')),
            ),
          ],
        ),
      );
    },
  );
}

class GatheringTransferOverview extends StatelessWidget {
  const GatheringTransferOverview({
    super.key,
    required this.review,
    required this.sourceLabel,
    required this.kind,
  });
  final GatheringReview review;
  final String Function(StorageReference storage) sourceLabel;
  final FileOperationKind kind;

  @override
  Widget build(BuildContext context) {
    final strings = GatheringStackStrings(context);
    final destination = review.capture.destination!;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      title: Text(strings.text('reviewTitle')),
      content: SizedBox(
        width: 840,
        height: MediaQuery.sizeOf(context).height * .6,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.commanderTr(
                      kind == FileOperationKind.copy ? 'Copy' : 'Move',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.text('destination', [
                      '${destination.storage == null ? destination.backend.label : sourceLabel(destination.storage!)} · ${destination.path}',
                    ]),
                  ),
                  const SizedBox(height: 12),
                  Text(strings.text('reviewIntro')),
                  const SizedBox(height: 12),
                  Text(strings.text('count', [review.capture.entries.length])),
                ],
              ),
            ),
            SliverList.builder(
              itemCount: review.capture.entries.length,
              itemBuilder: (context, index) {
                final item = review.capture.entries[index];
                return _GatheringRow(
                  entry: item,
                  state: review.states[item.id]!,
                  source: sourceLabel(item.reference.storage),
                  editable: false,
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.commanderTr('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('gathering-continue'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(strings.text('continueReview')),
        ),
      ],
    );
  }
}

class _GatheringRow extends StatelessWidget {
  const _GatheringRow({
    super.key,
    required this.entry,
    required this.state,
    required this.source,
    this.onRemove,
    this.onUp,
    this.onDown,
    this.editable = true,
  });
  final GatheringStackEntry entry;
  final GatheringReferenceState state;
  final String source;
  final VoidCallback? onRemove, onUp, onDown;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final strings = GatheringStackStrings(context);
    final stateKey = state == GatheringReferenceState.changed
        ? 'changedStatus'
        : state.name;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  entry.original.file.isFolder
                      ? Icons.folder_outlined
                      : Icons.description_outlined,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.original.file.name,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Tooltip(
              message:
                  '${entry.reference.storage.id} · ${entry.reference.storage.root}',
              child: Text(source),
            ),
            Text(entry.reference.path),
            const SizedBox(height: 6),
            Text(strings.text(stateKey)),
            if (editable)
              Wrap(
                children: [
                  IconButton(
                    key: ValueKey('gathering-up-${entry.id}'),
                    tooltip: strings.text('up'),
                    onPressed: onUp,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    key: ValueKey('gathering-down-${entry.id}'),
                    tooltip: strings.text('down'),
                    onPressed: onDown,
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  IconButton(
                    key: ValueKey('gathering-remove-${entry.id}'),
                    tooltip: strings.text('remove'),
                    onPressed: onRemove,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
