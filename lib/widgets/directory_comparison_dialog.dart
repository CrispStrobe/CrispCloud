import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/directory_comparison_service.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';

Future<void> showDirectoryComparisonDialog(
  BuildContext context,
  WidgetRef ref,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const _DirectoryComparisonDialog(),
);

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
  String? _message;
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
      _message = 'Comparing…';
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
            setState(() => _message = '$count compared: $path');
          }
        },
      );
      if (mounted) {
        setState(() {
          _plan = plan;
          _message = plan.errors.isNotEmpty
              ? plan.errors.join('\n')
              : plan.cancelled
              ? 'Comparison cancelled.'
              : '${plan.rows.length} entries compared. Select the actions to apply.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _cancel = false;
      _control = FileOperationControl();
      _message = 'Validating reviewed files…';
    });
    try {
      final errors = await _service.apply(
        _plan!,
        Map.of(_choices),
        control: _control!,
        onProgress: (path) {
          if (mounted) setState(() => _message = path);
        },
      );
      if (mounted) {
        setState(() {
          _plan = null;
          _message = errors.isNotEmpty
              ? errors.join('\n')
              : _control!.isCancelled
              ? 'Cancelled. Completed copies are retained.'
              : 'Reviewed changes applied.';
        });
      }
      if (mounted) {
        await ref.read(panelProvider(PanelSide.local)).refresh();
        await ref.read(panelProvider(PanelSide.remote)).refresh();
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
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
      child: AlertDialog(
        title: const Text('Compare current panel directories'),
        content: SizedBox(
          width: 850,
          height: 500,
          child: Column(
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  FilterChip(
                    label: const Text('Subdirectories'),
                    selected: _recursive,
                    onSelected: _busy
                        ? null
                        : (value) => setState(() {
                            _recursive = value;
                            _plan = null;
                          }),
                  ),
                  FilterChip(
                    label: const Text('Compare file contents'),
                    selected: _verify,
                    onSelected: _busy
                        ? null
                        : (value) => setState(() {
                            _verify = value;
                            _plan = null;
                          }),
                  ),
                  FilterChip(
                    label: const Text('Show equal'),
                    selected: _showEqual,
                    onSelected: (value) => setState(() => _showEqual = value),
                  ),
                ],
              ),
              if (_plan != null)
                Text(
                  '${_plan!.left.label}: ${_plan!.leftRoot} ↔ ${_plan!.right.label}: ${_plan!.rightRoot}',
                ),
              if (_message != null) Text(_message!, maxLines: 4),
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
                            if (row.status != DirectoryComparisonStatus.equal &&
                                row.choices.contains(direction)) {
                              _choices[row.relativePath] = direction;
                            }
                          }
                        }),
                        child: Text(
                          direction == DirectoryComparisonAction.copyToRight
                              ? 'Differences → Right'
                              : 'Differences → Left',
                        ),
                      ),
                    TextButton(
                      onPressed: () => setState(_choices.clear),
                      child: const Text('Clear actions'),
                    ),
                  ],
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      title: Text(row.relativePath),
                      subtitle: Text(row.status.name),
                      trailing: DropdownButton<DirectoryComparisonAction>(
                        value:
                            _choices[row.relativePath] ??
                            DirectoryComparisonAction.skip,
                        items: [
                          for (final choice in row.choices)
                            DropdownMenuItem(
                              value: choice,
                              child: Text(switch (choice) {
                                DirectoryComparisonAction.skip => 'Skip',
                                DirectoryComparisonAction.copyToRight =>
                                  'Left → Right',
                                DirectoryComparisonAction.copyToLeft =>
                                  'Right → Left',
                              }),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(
                                () => _choices[row.relativePath] = value!,
                              ),
                      ),
                    );
                  },
                ),
              ),
              const Text(
                'Applying replaces the reviewed destination files. Unselected children and files remain untouched. Use Sync Pairs for deletion-aware synchronization.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          if (_busy)
            TextButton(
              onPressed: () {
                setState(() => _cancel = true);
                _control?.cancel();
              },
              child: const Text('Stop'),
            ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: _busy ? null : _compare,
            child: const Text('Compare'),
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
            child: const Text('Apply selected actions'),
          ),
        ],
      ),
    );
  }
}
