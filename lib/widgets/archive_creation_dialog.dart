import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/archive_creation_strings.dart';
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
    await showDialog<ArchiveCreationResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ArchiveCreationDialog(
        source: backend,
        destination: backend,
        files: selection,
        destinationDirectory: directory,
        onCreated: rememberSelection,
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
  });

  final FileOperationBackend source;
  final FileOperationBackend destination;
  final List<FileItem> files;
  final String destinationDirectory;
  final ArchiveCreationService service;
  final VoidCallback? onCreated;

  @override
  State<ArchiveCreationDialog> createState() => _ArchiveCreationDialogState();
}

class _ArchiveCreationDialogState extends State<ArchiveCreationDialog> {
  late final TextEditingController _name;
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  ArchiveCreationFormat _format = ArchiveCreationFormat.zip;
  ArchiveCreationCompression _compression = ArchiveCreationCompression.normal;
  bool _protect = false, _hideNames = true, _busy = false, _cancelled = false;
  ArchiveCreationProgress? _progress;
  Object? _error;
  String? _validation;
  ArchiveCreationResult? _result;

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
    _cancelled = true;
    _name.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _chooseFormat(ArchiveCreationFormat format) {
    setState(() {
      final old = _format.extension;
      if (_name.text.toLowerCase().endsWith(old)) {
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

  Future<void> _create() async {
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
      setState(() {
        _busy = true;
        _cancelled = false;
        _validation = null;
        _error = null;
        _progress = null;
      });
      final result = await widget.service.create(
        source: widget.source,
        destination: widget.destination,
        files: widget.files,
        destinationDirectory: widget.destinationDirectory,
        options: options,
        isCancelled: () => _cancelled || !mounted,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      widget.onCreated?.call();
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        if (_busy) {
          _password.clear();
          _confirmation.clear();
        }
        setState(() => _busy = false);
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
    final progress = _progress;
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
                      DropdownMenuItem(value: value, child: Text(value.label)),
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
                        ? 'Create a data image from local files and folders. Up to 2 GiB of image output. Existing files are never replaced.'
                        : _format.singlePayload
                        ? 'Select one local file, up to 64 MiB. Its name after decompression comes from the output filename.'
                        : _format == ArchiveCreationFormat.ar
                        ? 'Select regular local files without folders. Up to 64 MiB per file and 256 MiB total.'
                        : 'Local files only. Up to 64 MiB per file and 256 MiB total. Existing files are never replaced.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_format.wrapper != null && !_format.singlePayload)
                  Text(
                    tr(
                      'Compressed TAR is limited to 64 MiB after decompression, including archive headers.',
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
                        : progress.completed / progress.total,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      _cancelled
                          ? 'Cancelling…'
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
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (_busy)
            TextButton(
              onPressed: _cancelled
                  ? null
                  : () => setState(() => _cancelled = true),
              child: Text(tr('Cancel')),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(context).pop(_result),
              child: Text(tr(_result == null ? 'Cancel' : 'Close')),
            ),
          if (_result == null)
            FilledButton(
              key: const ValueKey('archive-create-submit'),
              onPressed: _busy ? null : _create,
              child: Text(tr('Create archive')),
            ),
        ],
      ),
    );
  }
}
