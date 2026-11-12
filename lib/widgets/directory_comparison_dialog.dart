import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import 'commander_review_dialog.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/directory_comparison_service.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import 'archive_directory_sync_dialog.dart';

Future<void> showDirectoryComparisonDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  if (ref.read(panelProvider(PanelSide.local)).isInArchive ||
      ref.read(panelProvider(PanelSide.remote)).isInArchive) {
    await showCurrentArchiveDirectorySyncDialog(context, ref);
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DirectoryComparisonDialog(),
  );
}

class _DirectoryComparisonDialog extends ConsumerStatefulWidget {
  const _DirectoryComparisonDialog();
  @override
  ConsumerState<_DirectoryComparisonDialog> createState() =>
      _DirectoryComparisonDialogState();
}

class _DirectoryComparisonDialogState
    extends ConsumerState<_DirectoryComparisonDialog> {
  DirectoryComparisonPlan? _plan;
  final _choices = <String, DirectoryComparisonAction>{};
  final _service = DirectoryComparisonService();
  FileOperationControl? _control;
  bool _busy = false,
      _cancel = false,
      _verify = true,
      _recursive = true,
      _showEqual = false;
  String Function(BuildContext)? _message;
  @override
  void initState() {
    super.initState();
    _compare();
  }

  @override
  void dispose() {
    _cancel = true;
    _control?.cancel();
    super.dispose();
  }

  Future<void> _compare() async {
    setState(() {
      _busy = true;
      _cancel = false;
      _message = (context) => context.commanderTr("Comparing…");
      _plan = null;
      _choices.clear();
    });
    try {
      final left = ref.read(panelProvider(PanelSide.local));
      final right = ref.read(panelProvider(PanelSide.remote));
      final leftOrigin = left.captureCurrentOrigin(),
          rightOrigin = right.captureCurrentOrigin();
      final local = ref.read(localFileServiceProvider);
      final plan = await _service.compare(
        left: fileOperationBackend(
          source: leftOrigin.source,
          local: local,
          isCurrent: () => mounted && leftOrigin.isCurrent,
        ),
        right: fileOperationBackend(
          source: rightOrigin.source,
          local: local,
          isCurrent: () => mounted && rightOrigin.isCurrent,
        ),
        leftRoot: left.currentPath,
        rightRoot: right.currentPath,
        verifyContents: _verify,
        recursive: _recursive,
        isCancelled: () => _cancel,
        onProgress: (count, path) {
          if (mounted && count % 20 == 0) {
            setState(
              () =>
                  _message = (context) =>
                      context.commanderTr("{0} compared: {1}", [count, path]),
            );
          }
        },
      );
      if (mounted) {
        setState(() {
          _plan = plan;
          _message = (context) => plan.errors.isNotEmpty
              ? plan.errors.join('\n')
              : plan.cancelled
              ? context.commanderTr("Comparison cancelled.")
              : context.commanderTr(
                  "{0} entries compared. Select the actions to apply.",
                  [plan.rows.length],
                );
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = (_) => error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _cancel = false;
      _control = FileOperationControl();
      _message = (context) => context.commanderTr("Validating reviewed files…");
    });
    try {
      final errors = await _service.apply(
        _plan!,
        Map.of(_choices),
        control: _control!,
        onProgress: (path) {
          if (mounted) setState(() => _message = (_) => path);
        },
      );
      if (mounted) {
        setState(() {
          _plan = null;
          _message = (context) => errors.isNotEmpty
              ? errors.join('\n')
              : _control!.isCancelled
              ? context.commanderTr("Cancelled. Completed copies are retained.")
              : context.commanderTr("Reviewed changes applied.");
        });
      }
      if (mounted) {
        await ref.read(panelProvider(PanelSide.local)).refresh();
        await ref.read(panelProvider(PanelSide.remote)).refresh();
      }
    } catch (error) {
      if (mounted) setState(() => _message = (_) => error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows =
        _plan?.rows
            .where(
              (row) =>
                  _showEqual || row.status != DirectoryComparisonStatus.equal,
            )
            .toList() ??
        [];
    return PopScope(
      canPop: !_busy,
      child: CommanderReviewDialog(
        title: context.commanderTr("Compare current panel directories"),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    FilterChip(
                      label: Text(context.commanderTr("Subdirectories")),
                      selected: _recursive,
                      onSelected: _busy
                          ? null
                          : (value) => setState(() {
                              _recursive = value;
                              _plan = null;
                            }),
                    ),
                    FilterChip(
                      label: Text(context.commanderTr("Compare file contents")),
                      selected: _verify,
                      onSelected: _busy
                          ? null
                          : (value) => setState(() {
                              _verify = value;
                              _plan = null;
                            }),
                    ),
                    FilterChip(
                      label: Text(context.commanderTr("Show equal")),
                      selected: _showEqual,
                      onSelected: (value) => setState(() => _showEqual = value),
                    ),
                  ],
                ),
                if (_plan != null)
                  Text(
                    '${_plan!.left.label}: ${_plan!.leftRoot} ↔ ${_plan!.right.label}: ${_plan!.rightRoot}',
                  ),
                if (_message != null)
                  Semantics(liveRegion: true, child: Text(_message!(context))),
                if (_busy) const LinearProgressIndicator(),
                if (_plan != null && !_busy)
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final direction in [
                        DirectoryComparisonAction.copyToRight,
                        DirectoryComparisonAction.copyToLeft,
                      ])
                        TextButton(
                          onPressed: () => setState(() {
                            for (final row in rows) {
                              if (row.status !=
                                      DirectoryComparisonStatus.equal &&
                                  row.choices.contains(direction)) {
                                _choices[row.relativePath] = direction;
                              }
                            }
                          }),
                          child: Text(
                            direction == DirectoryComparisonAction.copyToRight
                                ? context.commanderTr("Differences → Right")
                                : context.commanderTr("Differences → Left"),
                          ),
                        ),
                      TextButton(
                        onPressed: () => setState(_choices.clear),
                        child: Text(context.commanderTr("Clear actions")),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.relativePath, textDirection: TextDirection.ltr),
                      Text(context.commanderEnum(row.status)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<DirectoryComparisonAction>(
                        key: ValueKey('compare-action-${row.relativePath}'),
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.commanderTr("Action"),
                        ),
                        initialValue:
                            _choices[row.relativePath] ??
                            DirectoryComparisonAction.skip,
                        items: [
                          for (final choice in row.choices)
                            DropdownMenuItem(
                              value: choice,
                              child: Text(
                                switch (choice) {
                                  DirectoryComparisonAction.skip =>
                                    context.commanderTr("Skip"),
                                  DirectoryComparisonAction.copyToRight =>
                                    context.commanderTr("Left → Right"),
                                  DirectoryComparisonAction.copyToLeft =>
                                    context.commanderTr("Right → Left"),
                                },
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(
                                () => _choices[row.relativePath] = value!,
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          SliverToBoxAdapter(
            child: Text(
              context.commanderTr(
                "Applying replaces the reviewed destination files. Unselected children and files remain untouched. Use Sync Pairs for deletion-aware synchronization.",
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
        actions: [
          if (_busy)
            TextButton(
              onPressed: () {
                setState(() => _cancel = true);
                _control?.cancel();
              },
              child: Text(context.commanderTr("Stop")),
            ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(context.commanderTr("Close")),
          ),
          TextButton(
            onPressed: _busy ? null : _compare,
            child: Text(context.commanderTr("Compare")),
          ),
          FilledButton(
            onPressed:
                _busy ||
                    _plan == null ||
                    _plan!.cancelled ||
                    _plan!.errors.isNotEmpty ||
                    !_choices.values.any(
                      (choice) => choice != DirectoryComparisonAction.skip,
                    )
                ? null
                : _apply,
            child: Text(context.commanderTr("Apply selected actions")),
          ),
        ],
      ),
    );
  }
}
