import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../l10n/commander_strings.dart';
import '../l10n/file_conflict_preview_strings.dart';
import '../models/file_item.dart';
import '../services/file_conflict_preview_service.dart';
import '../services/file_operation_service.dart';
import 'diff_viewer_dialog.dart';

Future<FileConflictResolution> showFileOperationConflict(
  BuildContext context, {
  required FileOperationEntry entry,
  required FileItem existing,
  required FileOperationBackend source,
  required FileOperationBackend destination,
  FileConflictPreviewService previewService =
      const FileConflictPreviewService(),
}) async =>
    await showDialog<FileConflictResolution>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConflictDialog(
        entry: entry,
        existing: existing,
        source: source,
        destination: destination,
        previewService: previewService,
      ),
    ) ??
    const FileConflictResolution(FileConflictDecision.cancel);

class _ConflictDialog extends StatefulWidget {
  const _ConflictDialog({
    required this.entry,
    required this.existing,
    required this.source,
    required this.destination,
    required this.previewService,
  });
  final FileOperationEntry entry;
  final FileItem existing;
  final FileOperationBackend source;
  final FileOperationBackend destination;
  final FileConflictPreviewService previewService;
  @override
  State<_ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends State<_ConflictDialog> {
  final _name = TextEditingController();
  late final String _destinationPath;
  late final List<FileConflictPreviewTarget> _targets;
  final _previews = <FileConflictImagePreview?>[null, null];
  final _previewProblems = <FileConflictPreviewProblem?>[null, null];
  final _loading = [true, true];
  List<FileOperationControl> _previewControls = [];
  FileOperationControl? _comparisonControl;
  Timer? _sessionWatch;
  FileConflictPreviewProblem? _reviewProblem;
  int _generation = 0;
  bool _closed = false;
  bool _all = false;
  bool _comparing = false;
  String? _comparison;

  bool get _reviewIsCurrent =>
      !_closed &&
      widget.entry.destination == _destinationPath &&
      _targets.every((target) => target.isCurrent);

  @override
  void initState() {
    super.initState();
    _destinationPath = widget.entry.destination;
    _targets = [
      FileConflictPreviewTarget(widget.source, widget.entry.source),
      FileConflictPreviewTarget(
        widget.destination,
        widget.existing,
        path: _destinationPath,
      ),
    ];
    unawaited(_loadPreviews());
    // Backends expose a captured-session guard rather than a UI notifier.
    // Poll only that in-memory guard; this never lists or downloads a file.
    _sessionWatch = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!_closed && _reviewProblem == null && !_reviewIsCurrent) {
        _invalidateReview(FileConflictPreviewProblem.sourceUnavailable);
      }
    });
  }

  void _cancelWork() {
    _generation++;
    for (final control in _previewControls) {
      control.cancel();
    }
    _comparisonControl?.cancel();
  }

  void _invalidateReview(FileConflictPreviewProblem problem) {
    _cancelWork();
    if (!mounted || _closed) return;
    setState(() {
      _reviewProblem = problem;
      _comparing = false;
      _comparison = null;
      for (var i = 0; i < 2; i++) {
        _previews[i] = null;
        _previewProblems[i] = problem;
        _loading[i] = false;
      }
    });
  }

  Future<void> _loadPreviews() async {
    for (final control in _previewControls) {
      control.cancel();
    }
    final generation = ++_generation;
    _previewControls = [FileOperationControl(), FileOperationControl()];
    // Decode sequentially so two large source rasters cannot overlap in the
    // platform decoder. Both final thumbnails remain small and memory-only.
    for (var side = 0; side < 2; side++) {
      if (!mounted || generation != _generation || _closed) return;
      try {
        final preview = await widget.previewService.load(
          _targets[side],
          control: _previewControls[side],
        );
        if (!mounted || generation != _generation || _closed) return;
        if (!_reviewIsCurrent) {
          _invalidateReview(FileConflictPreviewProblem.sourceUnavailable);
          return;
        }
        setState(() {
          _previews[side] = preview;
          _previewProblems[side] = null;
          _loading[side] = false;
        });
      } catch (error) {
        if (!mounted || generation != _generation || _closed) return;
        final problem = error is FileConflictPreviewException
            ? error.problem
            : FileConflictPreviewProblem.unavailable;
        if (problem == FileConflictPreviewProblem.sourceChanged ||
            problem == FileConflictPreviewProblem.sourceUnavailable ||
            !_reviewIsCurrent) {
          _invalidateReview(
            !_reviewIsCurrent
                ? FileConflictPreviewProblem.sourceUnavailable
                : problem,
          );
          return;
        }
        setState(() {
          _previewProblems[side] = problem;
          _loading[side] = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    _sessionWatch?.cancel();
    _cancelWork();
    _name.dispose();
    super.dispose();
  }

  void _choose(FileConflictDecision decision, {bool renamed = false}) {
    if (decision != FileConflictDecision.cancel &&
        (_reviewProblem != null || !_reviewIsCurrent)) {
      _invalidateReview(
        _reviewProblem ?? FileConflictPreviewProblem.sourceUnavailable,
      );
      return;
    }
    if (renamed && _name.text.trim().isEmpty) {
      setState(() => _comparison = 'Enter a new filename first.');
      return;
    }
    _closed = true;
    _sessionWatch?.cancel();
    _cancelWork();
    Navigator.pop(
      context,
      FileConflictResolution(
        decision,
        name: renamed ? _name.text.trim() : null,
        applyToAll: !renamed && _all,
      ),
    );
  }

  Future<void> _compare({required bool text}) async {
    if (!_reviewIsCurrent || _reviewProblem != null) {
      _invalidateReview(
        _reviewProblem ?? FileConflictPreviewProblem.sourceUnavailable,
      );
      return;
    }
    final generation = _generation;
    final control = FileOperationControl();
    _comparisonControl?.cancel();
    _comparisonControl = control;
    void check() {
      if (control.isCancelled || _closed) throw const FileOperationCancelled();
      for (final target in _targets) {
        target.checkCurrent();
      }
    }

    setState(() {
      _comparing = true;
      _comparison = null;
    });
    try {
      check();
      if (text) {
        Future<String> read(FileConflictPreviewTarget target) async {
          final file = await target.verifyCurrent(control: control);
          final bytes = <int>[];
          await for (final chunk in control.bind(
            target.backend.readFile(file),
          )) {
            check();
            if (bytes.length + chunk.length > 1024 * 1024) {
              throw StateError(
                'Text comparison is limited to 1 MiB per file. Use Compare SHA-256 for larger files.',
              );
            }
            bytes.addAll(chunk);
          }
          await target.verifyCurrent(expected: file, control: control);
          if (bytes.contains(0)) {
            throw StateError('Binary file. Use Compare SHA-256.');
          }
          return utf8.decode(bytes);
        }

        final left = await read(_targets[0]);
        final right = await read(_targets[1]);
        check();
        if (!mounted || generation != _generation) return;
        showDiffViewerFromContent(
          context,
          leftContent: left,
          rightContent: right,
          leftLabel: _targets[0].file.path!,
          rightLabel: _destinationPath,
        );
      } else {
        Future<Digest> hash(FileConflictPreviewTarget target) async {
          final file = await target.verifyCurrent(control: control);
          final result = await sha256
              .bind(
                control.bind(target.backend.readFile(file)).map((chunk) {
                  check();
                  return chunk;
                }),
              )
              .first;
          await target.verifyCurrent(expected: file, control: control);
          return result;
        }

        final left = await hash(_targets[0]);
        final right = await hash(_targets[1]);
        check();
        if (mounted && generation == _generation) {
          setState(
            () => _comparison = left == right
                ? 'Contents are identical (SHA-256).'
                : 'Contents differ (SHA-256).',
          );
        }
      }
    } catch (error) {
      if (!mounted || _closed || generation != _generation) return;
      if (error is FileConflictPreviewException &&
          (error.problem == FileConflictPreviewProblem.sourceChanged ||
              error.problem == FileConflictPreviewProblem.sourceUnavailable)) {
        _invalidateReview(error.problem);
      } else {
        const safeMessages = {
          'Text comparison is limited to 1 MiB per file. Use Compare SHA-256 for larger files.',
          'Binary file. Use Compare SHA-256.',
        };
        setState(
          () => _comparison =
              error is StateError && safeMessages.contains(error.message)
              ? context.commanderTr(error.message)
              : FileConflictPreviewStrings(context).text(
                  'The files could not be compared. Check access and retry.',
                ),
        );
      }
    } finally {
      if (mounted && !_closed && generation == _generation) {
        setState(() => _comparing = false);
      }
    }
  }

  Widget _fileCard(int side) {
    final strings = FileConflictPreviewStrings(context);
    final target = _targets[side];
    final file = target.file;
    final preview = _previews[side];
    final problem = _previewProblems[side];
    final details = fileConflictReviewDetails(file);
    final name = side == 0 ? 'incoming' : 'existing';
    Widget detail(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SelectableText.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${strings.text(label)}: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
    return Container(
      key: ValueKey('file-conflict-$name-card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.text(side == 0 ? 'Incoming' : 'Existing'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          SelectableText(
            file.path ?? file.name,
            maxLines: 3,
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: Center(
              child: preview != null
                  ? Image.memory(
                      preview.png,
                      key: ValueKey('file-conflict-$name-image'),
                      semanticLabel:
                          '${strings.text(side == 0 ? 'Incoming' : 'Existing')}: ${file.name}',
                      fit: BoxFit.contain,
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_loading[side])
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            file.isFolder
                                ? Icons.folder_outlined
                                : Icons.image_not_supported_outlined,
                          ),
                        const SizedBox(height: 8),
                        Flexible(
                          child: Text(
                            _loading[side]
                                ? strings.text('Preparing image preview…')
                                : strings.problem(
                                    problem ??
                                        FileConflictPreviewProblem.unsupported,
                                  ),
                            key: ValueKey('file-conflict-$name-preview-status'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (preview != null) ...[
            Text(
              strings.text('{0} × {1} pixels', [preview.width, preview.height]),
              key: ValueKey('file-conflict-$name-dimensions'),
            ),
            if (preview.animated) Text(strings.text('First frame')),
          ],
          detail('Storage', target.storageLabel),
          detail(
            'Kind',
            strings.text(
              file.isSymlink == true
                  ? 'Symbolic link'
                  : file.isFolder
                  ? 'Folder'
                  : 'File',
            ),
          ),
          detail(
            'Size',
            file.size == null || file.isFolder
                ? strings.text('Unknown')
                : strings.text('{0} bytes', [file.size]),
          ),
          detail(
            'Modified',
            file.updatedAt?.toUtc().toIso8601String() ??
                strings.text('Unknown'),
          ),
          if (file.extension.isNotEmpty) detail('Extension', file.extension),
          if (details.isNotEmpty)
            ExpansionTile(
              key: ValueKey('file-conflict-$name-details'),
              tilePadding: EdgeInsets.zero,
              title: Text(strings.text('More details')),
              children: [
                for (final item in details.entries)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: detail(item.key, item.value),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final folder = entry.source.isFolder;
    final strings = FileConflictPreviewStrings(context);
    final canChoose = _reviewProblem == null && _reviewIsCurrent;
    final canCompare =
        canChoose &&
        !_comparing &&
        _targets.every(
          (target) => !target.file.isFolder && target.file.isSymlink != true,
        );
    return AlertDialog(
      title: Text(
        folder
            ? context.commanderTr("Folder already exists")
            : context.commanderTr("File already exists"),
      ),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth >= 560
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _fileCard(0)),
                          const SizedBox(width: 12),
                          Expanded(child: _fileCard(1)),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _fileCard(0),
                          const SizedBox(height: 12),
                          _fileCard(1),
                        ],
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                strings.text('Previews do not select a conflict decision.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_reviewProblem != null)
                Text(
                  strings.problem(_reviewProblem!),
                  key: const ValueKey('file-conflict-review-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (canChoose &&
                  !_comparing &&
                  !_loading.contains(true) &&
                  _previewProblems.any(
                    (problem) =>
                        problem == FileConflictPreviewProblem.unavailable ||
                        problem == FileConflictPreviewProblem.timedOut,
                  ))
                TextButton(
                  onPressed: () {
                    setState(() {
                      for (var i = 0; i < 2; i++) {
                        _loading[i] = true;
                        _previews[i] = null;
                        _previewProblems[i] = null;
                      }
                    });
                    unawaited(_loadPreviews());
                  },
                  child: Text(strings.text('Retry image previews')),
                ),
              if (!folder) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: canCompare ? () => _compare(text: true) : null,
                      child: Text(context.commanderTr("Compare text")),
                    ),
                    TextButton(
                      onPressed: canCompare
                          ? () => _compare(text: false)
                          : null,
                      child: Text(context.commanderTr("Compare SHA-256")),
                    ),
                  ],
                ),
                if (_comparing) const LinearProgressIndicator(),
                if (_comparison != null)
                  SelectableText(context.commanderTr(_comparison!)),
                const SizedBox(height: 8),
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: context.commanderTr(
                      "New filename for this conflict",
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: !canChoose
                          ? null
                          : () => _choose(
                              FileConflictDecision.renameSource,
                              renamed: true,
                            ),
                      child: Text(context.commanderTr("Rename incoming file")),
                    ),
                    if (widget.destination.capabilities.noReplaceMove)
                      TextButton(
                        onPressed: !canChoose
                            ? null
                            : () => _choose(
                                FileConflictDecision.renameDestination,
                                renamed: true,
                              ),
                        child: Text(
                          context.commanderTr("Rename existing file"),
                        ),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: !canChoose
                          ? null
                          : () => _choose(FileConflictDecision.resumeVerified),
                      child: Text(
                        context.commanderTr("Resume after prefix check"),
                      ),
                    ),
                    TextButton(
                      onPressed: !canChoose
                          ? null
                          : () => _choose(FileConflictDecision.append),
                      child: Text(
                        context.commanderTr("Append to existing file"),
                      ),
                    ),
                  ],
                ),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _all,
                title: Text(
                  context.commanderTr("Apply this decision to remaining {0}", [
                    context.commanderTr(folder ? "Folders" : "Files"),
                  ]),
                ),
                onChanged: !canChoose
                    ? null
                    : (value) => setState(() => _all = value!),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _choose(FileConflictDecision.cancel),
          child: Text(context.commanderTr("Cancel operation")),
        ),
        TextButton(
          onPressed: !canChoose
              ? null
              : () => _choose(FileConflictDecision.skip),
          child: Text(context.commanderTr("Skip")),
        ),
        if (!folder)
          TextButton(
            onPressed: !canChoose
                ? null
                : () => _choose(FileConflictDecision.keepBoth),
            child: Text(context.commanderTr("Keep both")),
          ),
        FilledButton(
          onPressed: !canChoose
              ? null
              : () => _choose(
                  folder
                      ? FileConflictDecision.merge
                      : FileConflictDecision.replace,
                ),
          child: Text(
            folder
                ? context.commanderTr("Merge folder")
                : context.commanderTr("Replace file"),
          ),
        ),
      ],
    );
  }
}
