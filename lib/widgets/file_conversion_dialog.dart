import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/file_conversion_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/file_conversion_service.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';

Future<void> showFileConversionDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  FileItem file, {
  required PanelFileOrigin sourceOrigin,
}) async {
  try {
    if (!sourceOrigin.isCurrent ||
        file.path == null ||
        file.isFolder ||
        file.isSymlink == true) {
      throw const FileConversionException(
        FileConversionProblem.sourceUnavailable,
      );
    }
    final selected = file.copyWith(
      metadata: Map.unmodifiable(file.metadata ?? {}),
    );
    final backend = fileOperationBackend(
      source: sourceOrigin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: () => sourceOrigin.isCurrent,
    );
    final remember = ref
        .read(panelProvider(side))
        .captureSelectionMemoryForOperation([selected]);
    await showDialog<FileConversionResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FileConversionDialog(
        source: backend,
        destination: backend,
        file: selected,
        destinationDirectory: backend.paths.dirname(selected.path!),
        onCreated: remember,
      ),
    );
    if (context.mounted && sourceOrigin.isCurrent) {
      await ref.read(panelProvider(side)).refresh();
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FileConversionStrings(context).error(error))),
      );
    }
  }
}

class FileConversionDialog extends StatefulWidget {
  const FileConversionDialog({
    super.key,
    required this.source,
    required this.destination,
    required this.file,
    required this.destinationDirectory,
    this.service = const FileConversionService(),
    this.onCreated,
  });
  final FileOperationBackend source, destination;
  final FileItem file;
  final String destinationDirectory;
  final FileConversionService service;
  final VoidCallback? onCreated;
  @override
  State<FileConversionDialog> createState() => _FileConversionDialogState();
}

class _FileConversionDialogState extends State<FileConversionDialog> {
  late final TextEditingController _name;
  late final FileItem _file;
  late final Object _sourceIdentity, _destinationIdentity;
  late final Timer _watch;
  FileConversionFormat _format = FileConversionFormat.mime;
  FileConversionDirection _direction = FileConversionDirection.encode;
  FileOperationControl? _control;
  FileConversionProgress? _progress;
  FileConversionResult? _result;
  Object? _error;
  bool _busy = false, _stale = false;

  bool get _current =>
      !_stale &&
      widget.source.isCurrent &&
      widget.destination.isCurrent &&
      _sourceIdentity == widget.source.identity &&
      _destinationIdentity == widget.destination.identity;
  bool get _supported =>
      widget.source.capabilities.boundedDownload &&
      FileConversionService.supportsDestination(widget.destination);
  String _defaultName() {
    if (_direction == FileConversionDirection.encode) {
      return '${_file.name}${_format.extension}';
    }
    final extension = _file.name.lastIndexOf('.');
    final stem = extension > 0
        ? _file.name.substring(0, extension)
        : _file.name;
    // Never infer the destination from the untrusted encoded header. Keep the
    // generated default distinct from a likely still-existing original file.
    return '$stem.decoded';
  }

  @override
  void initState() {
    super.initState();
    _file = widget.file.copyWith(
      metadata: Map.unmodifiable(widget.file.metadata ?? {}),
    );
    _sourceIdentity = widget.source.identity;
    _destinationIdentity = widget.destination.identity;
    final extension = _file.extension;
    if (const ['uue', 'uu', 'xxe', 'xx', 'mime', 'eml'].contains(extension)) {
      _direction = FileConversionDirection.decode;
      _format = const ['uue', 'uu'].contains(extension)
          ? FileConversionFormat.uue
          : const ['xxe', 'xx'].contains(extension)
          ? FileConversionFormat.xxe
          : FileConversionFormat.mime;
    }
    _name = TextEditingController(text: _defaultName());
    _watch = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _stale || _result != null || _current) return;
      _control?.cancel();
      setState(() {
        _stale = true;
        _error = const FileConversionException(
          FileConversionProblem.sourceUnavailable,
        );
      });
    });
  }

  @override
  void dispose() {
    _control?.cancel();
    _watch.cancel();
    _name.dispose();
    super.dispose();
  }

  void _change({
    FileConversionFormat? format,
    FileConversionDirection? direction,
  }) {
    setState(() {
      final defaultName = _name.text == _defaultName();
      _format = format ?? _format;
      _direction = direction ?? _direction;
      if (defaultName) _name.text = _defaultName();
      _error = null;
    });
  }

  Future<void> _convert() async {
    if (!_current) {
      setState(
        () => _error = const FileConversionException(
          FileConversionProblem.sourceUnavailable,
        ),
      );
      return;
    }
    final options = FileConversionOptions(
      direction: _direction,
      format: _format,
      outputName: _name.text,
    );
    try {
      options.validate();
      if (_direction == FileConversionDirection.encode) {
        const FileConversionCodec().validateFilename(_file.name, _format);
      }
      setState(() {
        _busy = true;
        _error = null;
        _progress = null;
        _control = FileOperationControl();
      });
      final result = await widget.service.convert(
        source: widget.source,
        file: _file,
        destination: widget.destination,
        destinationDirectory: widget.destinationDirectory,
        options: options,
        control: _control,
        onProgress: (value) {
          if (mounted && _current) setState(() => _progress = value);
        },
      );
      // Success can arrive just after an enclosing window is closed. Selection
      // memory follows the actual accepted operation, never an attempted one.
      widget.onCreated?.call();
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = _current
              ? error
              : const FileConversionException(
                  FileConversionProblem.sourceUnavailable,
                ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = FileConversionStrings(context);
    final tr = strings.text;
    final available = !_busy && _result == null && _current && _supported;
    final progress = _progress;
    final result = _result;
    final error =
        _error ??
        (!_supported
            ? const FileConversionException(
                FileConversionProblem.unsupportedStorage,
              )
            : null);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(tr('Encode / decode file')),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(
                  _file.path ?? _file.name,
                  textDirection: TextDirection.ltr,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  tr('Destination: {0}', [widget.destinationDirectory]),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<FileConversionDirection>(
                  key: const ValueKey('file-conversion-direction'),
                  initialValue: _direction,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr('Operation'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final direction in FileConversionDirection.values)
                      DropdownMenuItem(
                        value: direction,
                        child: Text(
                          tr(
                            direction == FileConversionDirection.encode
                                ? 'Encode to text'
                                : 'Decode to file',
                          ),
                        ),
                      ),
                  ],
                  onChanged: available
                      ? (value) => _change(direction: value)
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<FileConversionFormat>(
                  key: const ValueKey('file-conversion-format'),
                  initialValue: _format,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr('Format'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final format in FileConversionFormat.values)
                      DropdownMenuItem(
                        value: format,
                        child: Text(format.label),
                      ),
                  ],
                  onChanged: available
                      ? (value) => _change(format: value)
                      : null,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('file-conversion-name'),
                  controller: _name,
                  enabled: available,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: tr('Output name'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  tr(
                    'Creates a new file in this folder. Existing files are never overwritten.',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(
                    _format == FileConversionFormat.mime
                        ? 'Single-part Base64 MIME only. Multipart messages and other transfer encodings are unsupported.'
                        : 'One UUE or XXE block. Embedded names and file modes are ignored.',
                  ),
                ),
                if (_format == FileConversionFormat.mime)
                  Text(tr('Embedded names never choose the output path.')),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: progress?.total != null && progress!.total! > 0
                        ? (progress.bytes / progress.total!).clamp(0, 1)
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    progress == null
                        ? tr('Checking input')
                        : strings.phase(progress.phase),
                  ),
                  if (progress != null)
                    Text(
                      '${progress.bytes} / ${progress.total ?? '…'} B',
                      textDirection: TextDirection.ltr,
                    ),
                ],
                if (error != null && result == null) ...[
                  const SizedBox(height: 12),
                  Text(
                    strings.error(error),
                    key: const ValueKey('file-conversion-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (result != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    tr('Created {0} ({1} bytes)', [
                      result.path,
                      result.outputBytes,
                    ]),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    'SHA-256: ${result.outputSha256}',
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (_busy)
            TextButton(
              key: const ValueKey('file-conversion-cancel'),
              onPressed: () => _control?.cancel(),
              child: Text(tr('Cancel')),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(context).pop(result),
              child: Text(tr('Close')),
            ),
          if (result == null)
            FilledButton(
              key: const ValueKey('file-conversion-start'),
              onPressed: available ? _convert : null,
              child: Text(tr('Convert')),
            ),
        ],
      ),
    );
  }
}
