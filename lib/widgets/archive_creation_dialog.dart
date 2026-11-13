import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/archive_creation_strings.dart';
import '../models/archive_operation.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/archive_creation_service.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import '../services/panel_source_service.dart';

Future<void> showArchiveCreationDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files, {
  required PanelFileOrigin sourceOrigin,
}) async {
  try {
    if (kIsWeb ||
        sourceOrigin.source is! LocalPanelSource ||
        !sourceOrigin.isCurrent ||
        files.isEmpty ||
        files.any((file) => file.path == null)) {
      throw const ArchiveCreationException(
        ArchiveCreationError.sourceUnavailable,
      );
    }
    // Keep both the rows and their output directory from the original menu.
    // Navigation while the review is open cannot redirect the operation.
    final selection = List<FileItem>.unmodifiable(files);
    final rememberSelection = ref
        .read(panelProvider(side))
        .captureSelectionMemoryForOperation(selection);
    final directory = p.dirname(selection.first.path!);
    final backend = fileOperationBackend(
      source: sourceOrigin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: () => sourceOrigin.isCurrent,
    );
    final transfers = ref.read(transferProvider);
    await showDialog<ArchiveCreationResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ArchiveCreationDialog(
        source: backend,
        destination: backend,
        files: selection,
        destinationDirectory: directory,
        enqueue: (options) => transfers.enqueueArchiveCreation(
          source: backend,
          destination: backend,
          files: selection,
          destinationDirectory: directory,
          options: options,
          onCreated: rememberSelection,
        ),
      ),
    );
    if (context.mounted) await ref.read(panelProvider(side)).refresh();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(archiveCreationError(context, error))),
      );
    }
  }
}

class ArchiveCreationDialog extends StatefulWidget {
  const ArchiveCreationDialog({
    super.key,
    required this.source,
    required this.destination,
    required this.files,
    required this.destinationDirectory,
    this.service = const ArchiveCreationService(),
    this.onCreated,
    this.enqueue,
  });

  final FileOperationBackend source;
  final FileOperationBackend destination;
  final List<FileItem> files;
  final String destinationDirectory;
  final ArchiveCreationService service;
  final VoidCallback? onCreated;

  /// Returns only after the queue has durably accepted the original selection.
  /// The owner of this callback owns the resulting job, including its lifetime.
  final Future<ArchiveOperationHandle<ArchiveCreationResult>> Function(
    ArchiveCreationOptions options,
  )?
  enqueue;

  @override
  State<ArchiveCreationDialog> createState() => _ArchiveCreationDialogState();
}

class _ArchiveCreationDialogState extends State<ArchiveCreationDialog> {
  late final TextEditingController _name;
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  ArchiveCreationFormat _format = ArchiveCreationFormat.zip;
  ArchiveCreationCompression _compression = ArchiveCreationCompression.normal;
  bool _protect = false, _hideNames = true, _busy = false, _admitting = false;
  ArchiveOperationHandle<ArchiveCreationResult>? _job;
  FileOperationControl? _localControl;
  StreamSubscription<void>? _localControlChanges;
  ArchiveCreationProgress? _progress;
  Object? _error;
  String? _validation;
  ArchiveCreationResult? _result;

  FileOperationControl? get _control => _job?.control ?? _localControl;
  bool get _cancelled => _control?.isCancelled ?? false;
  bool get _paused => _control?.isPaused ?? false;

  @override
  void initState() {
    super.initState();
    final first = widget.files.length == 1 ? widget.files.single : null;
    final stem = first == null
        ? 'archive'
        : first.isFolder
        ? first.name
        : p.basenameWithoutExtension(first.name);
    _name = TextEditingController(text: '$stem.zip');
  }

  @override
  void dispose() {
    // A queue-owned job outlives this route. Only the standalone foreground
    // fallback belongs to the dialog and must stop when its owner disappears.
    _job?.removeListener(_jobChanged);
    unawaited(_localControlChanges?.cancel());
    _localControl?.cancel();
    _name.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _chooseFormat(ArchiveCreationFormat format) {
    setState(() {
      final old = _format.extension;
      if (_name.text.toLowerCase().endsWith(old.toLowerCase())) {
        var stem = _name.text.substring(0, _name.text.length - old.length);
        if (format.singlePayload &&
            widget.files.length == 1 &&
            !widget.files.single.isFolder &&
            stem == p.basenameWithoutExtension(widget.files.single.name)) {
          stem = widget.files.single.name;
        }
        _name.text = '$stem${format.extension}';
      }
      _format = format;
      _compression = format.defaultCompression;
      if (!format.supportsPassword) {
        _protect = false;
        _password.clear();
        _confirmation.clear();
      }
      _validation = null;
      _error = null;
    });
  }

  void _jobChanged() {
    final job = _job;
    if (!mounted || job == null) return;
    setState(() {
      _progress = job.creationProgress;
      _result = job.result;
      _error = job.error;
      _busy = !job.isSettled;
    });
  }

  void _attachJob(ArchiveOperationHandle<ArchiveCreationResult> job) {
    _job?.removeListener(_jobChanged);
    _job = job;
    job.addListener(_jobChanged);
    _jobChanged();
  }

  void _togglePause() {
    final control = _control;
    if (control == null || control.isCancelled) return;
    if (control.isPaused) {
      control.resume();
    } else {
      control.pause();
    }
    setState(() {});
  }

  void _stop() {
    _control?.cancel();
    setState(() {});
  }

  Future<void> _create({bool background = false}) async {
    if (_busy || _result != null) return;
    setState(() {
      _validation = null;
      _error = null;
    });
    if (_protect && _password.text.isEmpty) {
      setState(() => _validation = 'Enter a password.');
      return;
    }
    if (_protect && _password.text != _confirmation.text) {
      setState(() => _validation = 'Passwords do not match.');
      return;
    }
    final options = ArchiveCreationOptions(
      name: _name.text,
      format: _format,
      compression: _compression,
      password: _protect ? _password.text : null,
      encryptNames: _protect && _format.supportsHiddenNames && _hideNames,
    );
    try {
      options.validate();
    } catch (error) {
      setState(() => _error = error);
      return;
    }
    try {
      _job?.removeListener(_jobChanged);
      _job = null;
      setState(() {
        _busy = true;
        _admitting = widget.enqueue != null;
        _validation = null;
        _error = null;
        _progress = null;
      });
      final enqueue = widget.enqueue;
      if (enqueue != null) {
        final job = await enqueue(options);
        // Admission may finish after an external navigator has removed this
        // route. Ownership still belongs to the queue; do not cancel the job.
        if (!mounted) return;
        _admitting = false;
        _attachJob(job);
        if (background) Navigator.of(context).pop();
        return;
      }
      final control = FileOperationControl();
      _localControl = control;
      _localControlChanges = control.changes.listen((_) {
        if (mounted) setState(() {});
      });
      final result = await widget.service.create(
        source: widget.source,
        destination: widget.destination,
        files: widget.files,
        destinationDirectory: widget.destinationDirectory,
        options: options,
        control: control,
        isCancelled: () => control.isCancelled || !mounted,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      var published = result;
      try {
        widget.onCreated?.call();
      } catch (error) {
        // The standalone observer has the same publication boundary as a
        // queue observer: failure after install cannot make creation retryable.
        published = ArchiveCreationResult(
          result.path,
          result.entryCount,
          result.bytes,
          publicationWarning: result.publicationWarning ?? error,
        );
      }
      if (mounted) setState(() => _result = published);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _busy = false;
        });
      }
    } finally {
      // Removing this in-memory listener is synchronous. A completed archive
      // must leave its busy state without waiting for an observer-cleanup
      // future (which may have been created in a different event-loop zone).
      unawaited(_localControlChanges?.cancel());
      _localControlChanges = null;
      _localControl = null;
      if (mounted) {
        _password.clear();
        _confirmation.clear();
        setState(() {
          _admitting = false;
          if (_job == null) _busy = false;
        });
      }
    }
  }

  String _compressionLabel(ArchiveCreationCompression value) => switch (value) {
    ArchiveCreationCompression.none => 'Store (no compression)',
    ArchiveCreationCompression.fast => 'Fast',
    ArchiveCreationCompression.normal => 'Normal',
    ArchiveCreationCompression.maximum => 'Maximum',
    ArchiveCreationCompression.deflate => 'Deflate',
    ArchiveCreationCompression.lzma2 => 'LZMA2',
  };

  @override
  Widget build(BuildContext context) {
    String tr(String key, [List<Object?> values = const []]) =>
        archiveCreationText(context, key, values);
    final enabled = !_busy && _result == null;
    final streamedTar = ArchiveCreationService.supportsStreamedTarCreation(
      format: _format,
      source: widget.source,
      destination: widget.destination,
    );
    final streamedCommon = ArchiveCreationService.supportsStreamedCreation(
      format: _format,
      source: widget.source,
      destination: widget.destination,
      password: _protect ? _password.text : null,
      compression: _compression,
    );
    final streamedDisk = ArchiveCreationService.supportsStreamedDiskCreation(
      format: _format,
      source: widget.source,
      destination: widget.destination,
    );
    final progress = _progress;
    final publicationWarning =
        _job?.publicationWarning ?? _result?.publicationWarning;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(tr('Create archive')),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('Selected items: {0}', [widget.files.length])),
                const SizedBox(height: 4),
                for (final file in widget.files.take(5))
                  Text(
                    file.path ?? file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                  ),
                if (widget.files.length > 5)
                  Text('… +${widget.files.length - 5}'),
                const SizedBox(height: 8),
                SelectableText(
                  tr('Destination: {0}', [widget.destinationDirectory]),
                ),
                if (widget.enqueue != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      'Background archives continue while CrispCloud is open. Manage them in the operation queue.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('archive-create-name'),
                  controller: _name,
                  enabled: enabled,
                  decoration: InputDecoration(
                    labelText: tr('Archive name'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ArchiveCreationFormat>(
                  key: const ValueKey('archive-create-format'),
                  initialValue: _format,
                  isExpanded: true,
                  menuMaxHeight: 400,
                  decoration: InputDecoration(
                    labelText: tr('Format'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final value in ArchiveCreationFormat.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(tr(value.label)),
                      ),
                  ],
                  onChanged: enabled
                      ? (value) {
                          if (value != null) _chooseFormat(value);
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ArchiveCreationCompression>(
                  key: ValueKey('archive-create-compression-${_format.name}'),
                  initialValue: _compression,
                  decoration: InputDecoration(
                    labelText: tr('Compression'),
                    border: const OutlineInputBorder(),
                  ),
                  isExpanded: true,
                  items: [
                    for (final value in _format.compressions)
                      DropdownMenuItem(
                        value: value,
                        child: Text(tr(_compressionLabel(value))),
                      ),
                  ],
                  onChanged: enabled && _format.compressions.length > 1
                      ? (value) {
                          if (value != null) {
                            setState(() => _compression = value);
                          }
                        }
                      : null,
                ),
                if (_format.supportsPassword) ...[
                  SwitchListTile(
                    key: const ValueKey('archive-create-protect'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Password protection')),
                    value: _protect,
                    onChanged: enabled
                        ? (value) => setState(() {
                            _protect = value;
                            if (!value) {
                              _password.clear();
                              _confirmation.clear();
                            }
                          })
                        : null,
                  ),
                  if (_protect) ...[
                    TextField(
                      key: const ValueKey('archive-create-password'),
                      controller: _password,
                      enabled: enabled,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: tr('Password'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('archive-create-confirmation'),
                      controller: _confirmation,
                      enabled: enabled,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: tr('Confirm password'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (_format.supportsHiddenNames)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(tr('Hide filenames')),
                        value: _hideNames,
                        onChanged: enabled
                            ? (value) =>
                                  setState(() => _hideNames = value ?? true)
                            : null,
                      ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        !_format.supportsHiddenNames
                            ? 'AES-256. ZIP filenames remain visible.'
                            : 'AES-256. Passwords are not saved.',
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                Text(
                  tr(
                    _format.diskImage
                        ? streamedDisk
                              ? _format == ArchiveCreationFormat.iso
                                    ? 'Create a data image up to 8 GiB. Each ISO file must be smaller than 4 GiB. Temporary disk space is required. Existing files are never replaced.'
                                    : 'Create a data image up to 8 GiB from local files and folders. Temporary disk space is required. Existing files are never replaced.'
                              : 'Create a data image from local files and folders. Up to 2 GiB of image output. Existing files are never replaced.'
                        : streamedCommon
                        ? 'Create an archive up to 8 GiB, including headers, with up to 8 GiB of expanded contents. Temporary disk space is required. Existing files are never replaced.'
                        : streamedTar
                        ? 'Stream local files into a new TAR or CBT archive up to 2 GiB, including headers. Existing files are never replaced.'
                        : _format.singlePayload
                        ? 'Select one local file, up to 64 MiB. Its name after decompression comes from the output filename.'
                        : _format == ArchiveCreationFormat.ar
                        ? 'Select regular local files without folders. Up to 64 MiB per file and 256 MiB total.'
                        : 'Local files only. Up to 64 MiB per file and 256 MiB total. Existing files are never replaced.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (!streamedCommon &&
                    _format.wrapper != null &&
                    !_format.singlePayload)
                  Text(
                    tr(
                      'Compressed TAR is limited to 64 MiB after decompression, including archive headers.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (!streamedCommon &&
                    (_format.wrapper != null || _format.singlePayload))
                  Text(
                    tr(
                      'Single-file compressors and compressed TAR are limited to 64 MiB of encoded output.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (_format == ArchiveCreationFormat.lz4 ||
                    _format == ArchiveCreationFormat.tarLz4)
                  Text(
                    tr(
                      'LZ4 offers fast compression or storage without compression. Both modes include content checksums.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (_format == ArchiveCreationFormat.lzma ||
                    _format == ArchiveCreationFormat.tarLzma)
                  Text(
                    tr(
                      'LZMA uses a 64 KiB dictionary for Fast, 8 MiB for Normal and 64 MiB for Maximum. The format has no content checksum.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (_format == ArchiveCreationFormat.compress ||
                    _format == ArchiveCreationFormat.tarCompress)
                  Text(
                    tr(
                      'UNIX compress uses 12-bit dictionaries for Fast, 14-bit for Normal and 16-bit for Maximum. The format has no content checksum or decoded length.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (_format.legacyCpio)
                  Text(
                    tr(
                      'Use legacy CPIO for compatibility. These profiles have no content checksum or encryption; names, sizes and metadata must fit their older fields.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (_format == ArchiveCreationFormat.hfsx ||
                    _format == ArchiveCreationFormat.dmg)
                  Text(
                    tr(
                      'Creates a case-sensitive HFSX data volume. Names use HFS Unicode normalization. Resource forks, extended attributes and symbolic links are not copied.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (_format == ArchiveCreationFormat.iso)
                  Text(
                    tr(
                      'Creates a data-only ISO with Rock Ridge and Joliet names. Boot records and UDF filesystems are not created.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: progress == null || progress.total == 0
                        ? null
                        : (progress.completed / progress.total).clamp(0, 1),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      _cancelled
                          ? 'Cancelling…'
                          : _admitting
                          ? 'Queueing archive…'
                          : _paused
                          ? 'Paused'
                          : switch (progress?.phase) {
                              ArchiveCreationPhase.packing => 'Packing…',
                              ArchiveCreationPhase.verifying =>
                                'Verifying archive…',
                              ArchiveCreationPhase.saving =>
                                'Saving verified archive…',
                              _ => 'Scanning selection…',
                            },
                    ),
                  ),
                  if (progress != null)
                    Text(
                      progress.path,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
                if (_validation != null || _error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _validation != null
                        ? tr(_validation!)
                        : archiveCreationError(context, _error!),
                    key: const ValueKey('archive-create-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_result != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    tr('Created and verified: {0}', [_result!.path]),
                    key: const ValueKey('archive-create-success'),
                  ),
                  if (publicationWarning != null)
                    Text(
                      tr('The archive was created. Recovery information: {0}', [
                        publicationWarning,
                      ]),
                      key: const ValueKey('archive-create-warning'),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (_busy && !_admitting) ...[
            TextButton(
              key: const ValueKey('archive-create-pause'),
              onPressed: _cancelled ? null : _togglePause,
              child: Text(tr(_paused ? 'Resume' : 'Pause')),
            ),
            TextButton(
              key: const ValueKey('archive-create-stop'),
              onPressed: _cancelled ? null : _stop,
              child: Text(tr('Stop')),
            ),
            if (_job != null)
              TextButton.icon(
                key: const ValueKey('archive-create-background-running'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.queue),
                label: Text(tr('Run in background')),
              ),
          ] else if (!_busy)
            TextButton(
              onPressed: () => Navigator.of(context).pop(_result),
              child: Text(tr(_result == null ? 'Cancel' : 'Close')),
            ),
          if (_result == null && !_busy) ...[
            if (widget.enqueue != null)
              OutlinedButton.icon(
                key: const ValueKey('archive-create-background'),
                onPressed: () => _create(background: true),
                icon: const Icon(Icons.queue),
                label: Text(tr('Queue in background')),
              ),
            FilledButton(
              key: const ValueKey('archive-create-submit'),
              onPressed: _create,
              child: Text(tr('Create archive')),
            ),
          ],
        ],
      ),
    );
  }
}
