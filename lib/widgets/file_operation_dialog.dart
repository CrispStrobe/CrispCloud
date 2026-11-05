import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/core_providers.dart';
import '../providers/panel_provider.dart';
import '../providers/transfer_provider.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import '../services/file_selection_pattern.dart';

Future<void> showFileOperationDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files, {
  required FileOperationKind kind,
}) async {
  if (files.isEmpty) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => FileOperationDialog(
      side: side,
      files: List.unmodifiable(files),
      kind: kind,
    ),
  );
  if (context.mounted) ref.read(panelProvider(side)).focusList();
}

class FileOperationDialog extends ConsumerStatefulWidget {
  const FileOperationDialog({
    super.key,
    required this.side,
    required this.files,
    required this.kind,
  });
  final PanelSide side;
  final List<FileItem> files;
  final FileOperationKind kind;
  @override
  ConsumerState<FileOperationDialog> createState() =>
      _FileOperationDialogState();
}

class _FileOperationDialogState extends ConsumerState<FileOperationDialog> {
  final _destination = TextEditingController();
  final _relativeBase = TextEditingController();
  final _mask = TextEditingController(text: '*');
  FileOperationControl _control = FileOperationControl();
  final _origins = <PanelSide, PanelFileOrigin>{};
  late final PanelNotifier _panel;
  PanelFileOrigin? _sourceOrigin;
  PanelSide? _destinationSide;
  FileConflictPolicy _fileConflict = FileConflictPolicy.ask;
  DirectoryConflictPolicy _directoryConflict = DirectoryConflictPolicy.merge;
  bool _recursive = true;
  bool _relative = false;
  bool _preserveTime = false;
  bool _verify = false;
  bool _stopOnError = true;
  bool _copyLinks = false;
  bool _regex = false;
  bool _caseSensitive = false;
  bool _matchPath = false;
  bool _preparing = false;
  bool _running = false;
  bool _finished = false;
  String? _error;
  String? _current;
  int _bytes = 0;
  int? _total;
  FileOperationPlan? _plan;

  String get _verb => widget.kind == FileOperationKind.copy ? 'Copy' : 'Move';
  bool get _busy => _preparing || _running;

  @override
  void initState() {
    super.initState();
    _panel = ref.read(panelProvider(widget.side));
    try {
      _sourceOrigin = _panel.captureOperationOrigin(widget.files);
      _origins[widget.side] = _sourceOrigin!;
      final opposite = widget.side == PanelSide.local
          ? PanelSide.remote
          : PanelSide.local;
      try {
        _origins[opposite] = ref
            .read(panelProvider(opposite))
            .captureCurrentOrigin();
      } catch (_) {
        /* A disconnected opposite panel is not a destination. */
      }
      _destinationSide = _origins.containsKey(opposite)
          ? opposite
          : widget.side;
      _destination.text = _origins[_destinationSide]!.source.currentPath;
      final backend = _backend(_sourceOrigin!);
      var base = backend.paths.dirname(widget.files.first.path!);
      while (widget.files.any(
        (file) => !backend.paths.isWithin(base, file.path!),
      )) {
        final parent = backend.paths.dirname(base);
        if (parent == base) break;
        base = parent;
      }
      _relativeBase.text = base;
    } catch (error) {
      _error = error.toString();
    }
  }

  FileOperationBackend _backend(PanelFileOrigin origin) => fileOperationBackend(
    source: origin.source,
    local: ref.read(localFileServiceProvider),
    isCurrent: () => origin.isCurrent,
  );

  @override
  void dispose() {
    _destination.dispose();
    _relativeBase.dispose();
    _mask.dispose();
    super.dispose();
  }

  void _change(VoidCallback change) {
    if (_busy) return;
    setState(() {
      change();
      _plan = null;
      _finished = false;
      _error = null;
    });
  }

  Future<void> _preview() async {
    final origin = _sourceOrigin;
    final destinationOrigin = _origins[_destinationSide];
    if (origin == null || destinationOrigin == null) return;
    setState(() {
      _control = FileOperationControl();
      _preparing = true;
      _error = null;
      _plan = null;
      _finished = false;
    });
    try {
      final plan = await const FileOperationService().prepare(
        files: widget.files,
        source: _backend(origin),
        destination: _backend(destinationOrigin),
        targetDirectory: _destination.text,
        control: _control,
        options: FileOperationOptions(
          kind: widget.kind,
          fileConflict: _fileConflict,
          directoryConflict: _directoryConflict,
          recursive: _recursive,
          preserveRelativePaths: _relative,
          relativeBase: _relativeBase.text,
          preserveModified: _preserveTime,
          verifyContents: _verify,
          stopOnError: _stopOnError,
          copySymbolicLinks: _copyLinks,
          pattern: FileSelectionPattern(
            _mask.text,
            mode: _regex ? FilePatternMode.regex : FilePatternMode.wildcard,
            caseSensitive: _caseSensitive,
            matchFullPath: _matchPath,
          ),
        ),
      );
      if (mounted) setState(() => _plan = plan);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<FileConflictDecision> _resolve(
    FileOperationEntry entry,
    FileItem existing,
  ) async {
    if (!mounted) return FileConflictDecision.cancel;
    return await showDialog<FileConflictDecision>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(
              entry.source.isFolder
                  ? 'Folder already exists'
                  : 'File already exists',
            ),
            content: SizedBox(
              width: 560,
              child: SelectableText(
                'Source: ${entry.source.path}\nDestination: ${entry.destination}\n\n'
                'Source: ${entry.source.size ?? 'unknown'} bytes · ${entry.source.updatedAt ?? 'time unknown'}\n'
                'Destination: ${existing.size ?? 'unknown'} bytes · ${existing.updatedAt ?? 'time unknown'}',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, FileConflictDecision.cancel),
                child: const Text('Cancel operation'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, FileConflictDecision.skip),
                child: const Text('Skip'),
              ),
              if (!entry.source.isFolder)
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, FileConflictDecision.keepBoth),
                  child: const Text('Keep both'),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  entry.source.isFolder
                      ? FileConflictDecision.merge
                      : FileConflictDecision.replace,
                ),
                child: Text(
                  entry.source.isFolder ? 'Merge folder' : 'Replace file',
                ),
              ),
            ],
          ),
        ) ??
        FileConflictDecision.cancel;
  }

  Future<void> _start({bool background = false}) async {
    final plan = _plan;
    if (plan == null || !plan.canExecute) return;
    final notifier = ref.read(transferProvider);
    final targetPanel = ref.read(panelProvider(_destinationSide!));
    setState(() {
      _running = true;
      _error = null;
    });
    final future = notifier.runFileOperation(
      plan,
      control: _control,
      resolveConflict: background ? null : _resolve,
      onProgress: (entry, bytes, total) {
        if (mounted) {
          setState(() {
            _current = entry.source.path;
            _bytes = bytes;
            _total = total;
          });
        }
      },
      onEntryComplete: (entry) {
        if (entry.outcome == FileOperationOutcome.moved) {
          _panel.applyFileListChanges({entry.source.path!: null});
        }
        if (mounted) setState(() {});
      },
    );
    if (background && mounted) Navigator.pop(context);
    try {
      await future;
      await _panel.refresh();
      if (!identical(_panel, targetPanel)) await targetPanel.refresh();
      if (mounted) {
        setState(() {
          _running = false;
          _finished = true;
          _current = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _running = false;
          _finished = true;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final destinationOrigin = _origins[_destinationSide];
    final destinationBackend = destinationOrigin == null
        ? null
        : _backend(destinationOrigin);
    final sourceBackend = _sourceOrigin == null
        ? null
        : _backend(_sourceOrigin!);
    final supportsTime = destinationBackend?.supportsModifiedTime ?? false;
    final supportsLinks =
        (destinationBackend?.supportsSymbolicLinks ?? false) &&
        (sourceBackend?.supportsSymbolicLinks ?? false);
    final plan = _plan;
    final completed =
        plan?.entries.where((entry) => entry.completed).length ?? 0;
    final failed = plan?.entries.where((entry) => entry.failed).length ?? 0;
    final skipped =
        plan?.entries
            .where(
              (entry) =>
                  entry.outcome == FileOperationOutcome.skipped ||
                  entry.outcome == FileOperationOutcome.filtered,
            )
            .length ??
        0;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text('$_verb ${widget.files.length} selected item(s)'),
        content: SizedBox(
          width: math.min(920, math.max(280, size.width - 96)),
          height: math.min(700, math.max(240, size.height - 190)),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_sourceOrigin != null)
                  Text(
                    'From ${_sourceOrigin!.source.displayName} · original item paths',
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<PanelSide>(
                  isExpanded: true,
                  initialValue: _destinationSide,
                  decoration: const InputDecoration(
                    labelText: 'Destination storage',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _origins.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(
                            '${entry.key == widget.side ? 'This panel' : 'Opposite panel'} · ${entry.value.source.displayName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (side) => _change(() {
                          _destinationSide = side;
                          _destination.text =
                              _origins[side]!.source.currentPath;
                          _preserveTime = false;
                          _copyLinks = false;
                        }),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _destination,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Destination directory',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _change(() {}),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 270,
                      child: DropdownButtonFormField<FileConflictPolicy>(
                        isExpanded: true,
                        initialValue: _fileConflict,
                        decoration: const InputDecoration(
                          labelText: 'Existing files',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: FileConflictPolicy.ask,
                            child: Text(
                              'Ask for each conflict',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: FileConflictPolicy.skip,
                            child: Text(
                              'Skip existing files',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: FileConflictPolicy.replace,
                            child: Text(
                              'Replace existing files',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: FileConflictPolicy.replaceIfNewer,
                            child: Text(
                              'Replace only if source is newer',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: FileConflictPolicy.keepBoth,
                            child: Text(
                              'Keep both (number new copies)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => _change(() => _fileConflict = value!),
                      ),
                    ),
                    SizedBox(
                      width: 245,
                      child: DropdownButtonFormField<DirectoryConflictPolicy>(
                        isExpanded: true,
                        initialValue: _directoryConflict,
                        decoration: const InputDecoration(
                          labelText: 'Existing folders',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: DirectoryConflictPolicy.merge,
                            child: Text(
                              'Merge contents',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: DirectoryConflictPolicy.skip,
                            child: Text(
                              'Skip whole folder',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: DirectoryConflictPolicy.ask,
                            child: Text(
                              'Ask for each folder',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) =>
                                  _change(() => _directoryConflict = value!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _mask,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'File filter',
                    hintText: '*.jpg;*.png|thumb*',
                    helperText: 'Filters files within selected folders. Excluded files stay in the source.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _change(() {}),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    _toggle(
                      'Regular expression',
                      _regex,
                      (value) => _regex = value,
                    ),
                    _toggle(
                      'Case sensitive',
                      _caseSensitive,
                      (value) => _caseSensitive = value,
                    ),
                    _toggle(
                      'Match full source path',
                      _matchPath,
                      (value) => _matchPath = value,
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    _toggle(
                      'Include subfolders',
                      _recursive,
                      (value) => _recursive = value,
                    ),
                    _toggle(
                      'Preserve relative paths',
                      _relative,
                      (value) => _relative = value,
                    ),
                    _toggle(
                      'Stop on first error',
                      _stopOnError,
                      (value) => _stopOnError = value,
                    ),
                  ],
                ),
                if (_relative)
                  TextField(
                    controller: _relativeBase,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Relative to source directory',
                      helperText:
                          'All selected paths must be below this directory.',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _change(() {}),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    _toggle(
                      'Verify contents (SHA-256)',
                      _verify,
                      (value) => _verify = value,
                    ),
                    _toggle(
                      'Preserve file modification times',
                      _preserveTime,
                      (value) => _preserveTime = value,
                      enabled: supportsTime,
                    ),
                    _toggle(
                      'Copy symbolic links as links',
                      _copyLinks,
                      (value) => _copyLinks = value,
                      enabled: supportsLinks,
                    ),
                  ],
                ),
                Text(
                  'Links are never followed. SHA-256 verification reads both copies and can add cloud traffic.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (!supportsTime)
                  Text(
                    'The destination does not expose modification-time preservation.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (widget.kind == FileOperationKind.move &&
                        sourceBackend is! LocalOperationBackend ||
                    (widget.kind == FileOperationKind.move &&
                        !(sourceBackend?.supportsSymbolicLinks ?? false)))
                  const Text(
                    'Empty source folders are retained where storage lacks a safe empty-folder delete.',
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SelectableText(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_preparing)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  ),
                if (plan != null) ...[
                  const Divider(height: 24),
                  Text(
                    _finished
                        ? '$completed completed · $skipped skipped/filtered · $failed failed'
                        : '${plan.fileCount} files in preview · ${plan.entries.length} total rows',
                  ),
                  for (final error in plan.errors)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 230,
                    child: ListView.builder(
                      itemCount: plan.entries.length,
                      itemBuilder: (context, index) {
                        final entry = plan.entries[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            entry.failed
                                ? Icons.error_outline
                                : entry.source.isFolder
                                ? Icons.folder_outlined
                                : Icons.insert_drive_file_outlined,
                          ),
                          title: Text(
                            '${entry.source.path} → ${entry.destination}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            entry.message ??
                                (entry.outcome != FileOperationOutcome.pending
                                    ? entry.outcome.name
                                    : entry.existing == null
                                    ? 'New destination'
                                    : 'Destination exists'),
                            style: TextStyle(
                              color: entry.failed
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (_running) ...[
                  LinearProgressIndicator(
                    value: _total != null && _total! > 0
                        ? (_bytes / _total!).clamp(0, 1)
                        : null,
                  ),
                  Text(
                    _current ?? 'Waiting for the transfer queue…',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (_running) ...[
            TextButton(
              onPressed: () => setState(() {
                _control.isPaused ? _control.resume() : _control.pause();
              }),
              child: Text(_control.isPaused ? 'Resume' : 'Pause'),
            ),
            TextButton(
              onPressed: () => setState(_control.cancel),
              child: const Text('Cancel operation'),
            ),
          ] else ...[
            TextButton(
              onPressed: _preparing ? null : () => Navigator.pop(context),
              child: Text(_finished ? 'Close' : 'Cancel'),
            ),
            OutlinedButton(
              onPressed: _preparing || _sourceOrigin == null ? null : _preview,
              child: const Text('Preview'),
            ),
            if (_fileConflict != FileConflictPolicy.ask &&
                _directoryConflict != DirectoryConflictPolicy.ask)
              TextButton(
                onPressed:
                    !_finished && (plan?.canExecute ?? false) && !_preparing
                    ? () => _start(background: true)
                    : null,
                child: const Text('Queue in background'),
              ),
            FilledButton(
              onPressed:
                  !_finished && (plan?.canExecute ?? false) && !_preparing
                  ? _start
                  : null,
              child: Text('Start $_verb'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _toggle(
    String text,
    bool value,
    ValueChanged<bool> change, {
    bool enabled = true,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Checkbox(
        value: value,
        onChanged: _busy || !enabled
            ? null
            : (value) => _change(() => change(value!)),
      ),
      Flexible(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
    ],
  );
}
