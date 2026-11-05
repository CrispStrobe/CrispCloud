import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/archive_viewer_service.dart';
import '../services/archive_workspace.dart';
import '../services/editor_document.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import '../utils/file_editability.dart';
import '../utils/formatters.dart';
import 'file_operation_dialog.dart';
import 'internal_viewer_dialog.dart';

enum ArchiveWorkspaceAction { browse, copyOut, moveOut, edit }

/// Reuses the actual archive account and the member selection of an archive
/// panel. Member paths are archive-relative; the container path is kept separate.
Future<void> showCurrentArchiveWorkspaceDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side, {
  ArchiveWorkspaceAction action = ArchiveWorkspaceAction.browse,
  FileItem? focusedMember,
}) async {
  try {
    final panel = ref.read(panelProvider(side));
    final origin = panel.captureArchiveOrigin();
    final archive = panel.archiveSource!;
    final selected = focusedMember != null
        ? [focusedMember]
        : panel.selection.isNotEmpty
        ? panel.selection.toList()
        : panel.cursorItem == null
        ? <FileItem>[]
        : [panel.cursorItem!];
    String memberPath(String path) =>
        '/${path.replaceAll(RegExp(r'^/+|/+$'), '')}';
    await showArchiveWorkspaceDialog(
      context,
      ref,
      side,
      FileItem(
        name: archive.archiveName,
        path: archive.archivePath,
        isFolder: false,
      ),
      sourceOrigin: origin,
      initialDirectory: memberPath(archive.innerPath),
      initialSelectedPaths: selected
          .where((file) => file.name != '..' && file.path != null)
          .map((file) => memberPath(file.path!))
          .toSet(),
      initialAction: action,
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

Future<void> showArchiveWorkspaceDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  FileItem file, {
  PanelFileOrigin? sourceOrigin,
  String initialDirectory = '/',
  Set<String> initialSelectedPaths = const {},
  ArchiveWorkspaceAction initialAction = ArchiveWorkspaceAction.browse,
}) async {
  try {
    final origin =
        sourceOrigin ??
        ref.read(panelProvider(side)).captureOperationOrigin([file]);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ArchiveWorkspaceDialog(
        side: side,
        file: file,
        origin: origin,
        initialDirectory: initialDirectory,
        initialSelectedPaths: initialSelectedPaths,
        initialAction: initialAction,
      ),
    );
    if (context.mounted) await ref.read(panelProvider(side)).refresh();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class _ArchiveWorkspaceDialog extends ConsumerStatefulWidget {
  const _ArchiveWorkspaceDialog({
    required this.side,
    required this.file,
    required this.origin,
    required this.initialDirectory,
    required this.initialSelectedPaths,
    required this.initialAction,
  });
  final PanelSide side;
  final FileItem file;
  final PanelFileOrigin origin;
  final String initialDirectory;
  final Set<String> initialSelectedPaths;
  final ArchiveWorkspaceAction initialAction;
  @override
  ConsumerState<_ArchiveWorkspaceDialog> createState() =>
      _ArchiveWorkspaceDialogState();
}

class _ArchiveWorkspaceDialogState
    extends ConsumerState<_ArchiveWorkspaceDialog> {
  ArchiveWorkspace? _workspace;
  final _selected = <String>{};
  String _path = '/';
  bool _busy = false;
  bool _cancelled = false;
  bool _replaceOnAdd = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_openInitial());
  }

  Future<void> _openInitial() async {
    await _open();
    if (!mounted || _workspace == null) return;
    if (widget.initialAction == ArchiveWorkspaceAction.copyOut &&
        _selection.isNotEmpty) {
      await _copyOut();
    } else if (widget.initialAction == ArchiveWorkspaceAction.moveOut &&
        _selection.isNotEmpty) {
      if (_workspace!.canUpdate) {
        await _moveOut();
      } else {
        setState(() => _message = _workspace!.updateSupport);
      }
    } else if (widget.initialAction == ArchiveWorkspaceAction.edit &&
        _selection.length == 1) {
      if (_workspace!.canUpdate && isTextEditableName(_selection.single.name)) {
        await _edit();
      } else {
        setState(
          () => _message = 'Copy this member out, edit it, then add it with replacement enabled.',
        );
      }
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    unawaited(_workspace?.close());
    super.dispose();
  }

  Future<String?> _prompt(
    String title,
    String initial, {
    bool password = false,
  }) => showDialog<String>(
    context: context,
    builder: (_) =>
        _ArchiveTextDialog(title: title, text: initial, password: password),
  );

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? password;
    try {
      final source = fileOperationBackend(
        source: widget.origin.source,
        local: ref.read(localFileServiceProvider),
        isCurrent: () => mounted && widget.origin.isCurrent,
      );
      while (mounted) {
        try {
          final workspace = await ArchiveWorkspace.open(
            source,
            widget.file,
            password: password,
          );
          if (!mounted) {
            await workspace.close();
            return;
          }
          setState(() {
            _workspace = workspace;
            _path = widget.initialDirectory;
            _selected
              ..clear()
              ..addAll(
                workspace
                    .list(_path)
                    .where(
                      (file) => widget.initialSelectedPaths.contains(file.path),
                    )
                    .map((file) => file.path!),
              );
          });
          return;
        } on ArchivePasswordRequiredException catch (error) {
          if (!mounted) return;
          password = await _prompt(
            error.wrongPassword
                ? 'Incorrect password. Try again'
                : 'Archive password',
            '',
            password: true,
          );
          if (password == null) return;
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<FileItem> get _files =>
      _workspace?.isCurrent == true ? _workspace!.list(_path) : [];
  List<FileItem> get _selection =>
      _files.where((file) => _selected.contains(file.path)).toList();

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _cancelled = false;
      _error = null;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _view(FileItem file) async {
    if (file.isFolder) {
      setState(() {
        _path = file.path!;
        _selected.clear();
      });
      return;
    }
    await _run(() async {
      final bytes = await _workspace!.read(file.path!);
      if (!mounted) return;
      await showInternalViewer(
        context,
        file: file,
        side: widget.side,
        bytesOverride: bytes,
        displayName: file.name,
      );
    });
  }

  Future<void> _edit() async {
    await _run(() async {
      final file = _selection.single;
      if ((file.size ?? 0) > 2 * 1024 * 1024) {
        throw StateError(
          'Archive text editing is limited to 2 MiB. Extract and edit larger members, then add them back.',
        );
      }
      final bytes = await _workspace!.read(file.path!);
      if (bytes.length > 2 * 1024 * 1024) {
        throw StateError('Archive text editing is limited to 2 MiB.');
      }
      final document = EditorDocument.decode(bytes);
      if (!mounted) return;
      final edited = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ArchiveTextDialog(
          title: 'Edit ${file.name}',
          text: document.text,
          multiline: true,
          detail: '${document.encoding.label} · ${document.lineEnding.label}',
        ),
      );
      if (edited != null) {
        _workspace!.replace(file.path!, document.encode(edited));
      }
    });
  }

  Future<void> _rename() async {
    final selected = _selection;
    if (selected.length != 1) {
      setState(() => _error = 'Select an available archive member.');
      return;
    }
    final file = selected.single;
    final name = await _prompt('Rename member', file.name);
    if (name == null || !mounted) return;
    await _run(() async {
      if (name.trim().isEmpty || name.contains('/') || name.contains('\\')) {
        throw StateError('Enter a single member name.');
      }
      _workspace!.rename(file.path!, p.posix.join(_path.substring(1), name));
      _selected.clear();
    });
  }

  Future<void> _remove() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${_selected.length} selected member(s)?'),
        content: const Text(
          'This changes the working archive. Save archive applies the changes to the original file.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove members'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    await _run(() async {
      _workspace!.remove(_selected);
      _selected.clear();
    });
  }

  Future<void> _add() async {
    await _run(() async {
      final otherSide = widget.side == PanelSide.local
          ? PanelSide.remote
          : PanelSide.local;
      final other = ref.read(panelProvider(otherSide));
      final files = other.selection.isNotEmpty
          ? other.selection.toList()
          : [
              if (other.cursorItem != null && other.cursorItem!.name != '..')
                other.cursorItem!,
            ];
      if (files.isEmpty) {
        throw StateError(
          'Select files in the other panel before opening the archive.',
        );
      }
      final origin = other.captureOperationOrigin(files);
      await _workspace!.addFiles(
        fileOperationBackend(
          source: origin.source,
          local: ref.read(localFileServiceProvider),
          isCurrent: () => mounted && origin.isCurrent,
        ),
        files,
        directory: _path,
        replaceExisting: _replaceOnAdd,
        isCancelled: () => _cancelled || !mounted,
      );
      if (mounted) {
        setState(
          () => _message =
              'Added ${files.length} selected item(s). Save archive to apply.',
        );
      }
    });
  }

  Future<void> _copyOut() async {
    final files = _selection;
    await _run(() async {
      await showFileOperationDialog(
        context,
        ref,
        widget.side,
        files,
        kind: FileOperationKind.copy,
        sourceOrigin: widget.origin,
        sourceBackend: _workspace!.backend,
      );
    });
  }

  Future<void> _moveOut() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move members out of this archive?'),
        content: const Text(
          'Choose copy options next. Only successfully copied and verified members are removed from the working archive. Save archive to commit the removal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    final files = _selection;
    await _run(() async {
      final plan = await showFileOperationDialog(
        context,
        ref,
        widget.side,
        files,
        kind: FileOperationKind.copy,
        sourceOrigin: widget.origin,
        sourceBackend: _workspace!.backend,
      );
      if (plan == null || !mounted) return;
      final count = await _workspace!.stageCopiedMemberRemoval(
        plan,
        isCancelled: () => _cancelled || !mounted,
      );
      if (mounted) {
        setState(() {
          _selected.clear();
          _message = count == 0
              ? 'No copied members were removed.'
              : 'Moved $count member(s) in the working copy. Save archive to commit removal.';
        });
      }
    });
  }

  Future<void> _save() async => _run(() async {
    await _workspace!.save(isCancelled: () => _cancelled || !mounted);
    if (mounted) setState(() => _message = 'Archive saved and verified.');
  });

  Future<void> _close() async {
    if (_busy) return;
    if (_workspace?.dirty == true) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard unsaved archive changes?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard changes'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final workspace = _workspace;
    // An invalidated source remains visible with its error instead of causing
    // a rebuild to read the disconnected archive.
    final files = workspace?.isCurrent == true ? _files : <FileItem>[];
    final selected = files
        .where((file) => _selected.contains(file.path))
        .toList();
    final enabled = !_busy && workspace?.isCurrent == true;
    final editable = enabled && workspace!.canUpdate;
    final size = MediaQuery.sizeOf(context);
    return PopScope(
      canPop: !_busy && workspace?.dirty != true,
      child: Dialog(
        child: SizedBox(
          width: math.min(960, size.width * .95),
          height: size.height * .9,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.archive_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.file.name,
                        style: Theme.of(context).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (workspace?.dirty == true) const Text('Unsaved changes'),
                    IconButton(
                      tooltip: 'Close archive',
                      onPressed: _busy ? null : _close,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              if (workspace != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '${workspace.format.toUpperCase()} · ${workspace.updateSupport}',
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: enabled && _path != '/'
                          ? () => setState(() {
                              _path = p.posix.dirname(_path);
                              _selected.clear();
                            })
                          : null,
                      icon: const Icon(Icons.arrow_upward),
                      label: const Text('Up'),
                    ),
                    TextButton(
                      onPressed: enabled
                          ? () => setState(() {
                              _selected
                                ..clear()
                                ..addAll(files.map((file) => file.path!));
                            })
                          : null,
                      child: const Text('Select all'),
                    ),
                    TextButton.icon(
                      onPressed: enabled && selected.isNotEmpty
                          ? _copyOut
                          : null,
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy out with options…'),
                    ),
                    TextButton.icon(
                      onPressed: editable && selected.isNotEmpty
                          ? _moveOut
                          : null,
                      icon: const Icon(Icons.drive_file_move_outline),
                      label: const Text('Move out with options…'),
                    ),
                    TextButton.icon(
                      onPressed: editable ? _add : null,
                      icon: const Icon(Icons.add),
                      label: const Text('Add from other panel'),
                    ),
                    FilterChip(
                      label: const Text('Replace members on add'),
                      selected: _replaceOnAdd,
                      onSelected: editable
                          ? (value) => setState(() => _replaceOnAdd = value)
                          : null,
                    ),
                    TextButton(
                      onPressed:
                          editable &&
                              selected.length == 1 &&
                              !selected.single.isFolder &&
                              isTextEditableName(selected.single.name)
                          ? _edit
                          : null,
                      child: const Text('Edit text'),
                    ),
                    TextButton(
                      onPressed: editable && selected.length == 1
                          ? _rename
                          : null,
                      child: const Text('Rename'),
                    ),
                    TextButton(
                      onPressed: editable && selected.isNotEmpty
                          ? _remove
                          : null,
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              ),
              SelectableText(_path),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_message!),
                ),
              if (_busy) const LinearProgressIndicator(),
              if (workspace != null && !workspace.isCurrent)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'The original account is unavailable. Reconnect and reopen this archive.',
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return Row(
                      children: [
                        Checkbox(
                          value: _selected.contains(file.path),
                          onChanged: enabled
                              ? (value) => setState(() {
                                  value!
                                      ? _selected.add(file.path!)
                                      : _selected.remove(file.path);
                                })
                              : null,
                          semanticLabel: 'Select ${file.name}',
                        ),
                        Expanded(
                          child: ListTile(
                            leading: Icon(
                              file.isFolder
                                  ? Icons.folder_outlined
                                  : Icons.insert_drive_file_outlined,
                            ),
                            title: Text(file.name),
                            subtitle: file.isFolder
                                ? null
                                : Text(formatBytes(file.size ?? 0)),
                            onTap: enabled ? () => _view(file) : null,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 12,
                  children: [
                    if (_busy)
                      TextButton(
                        onPressed: () => setState(() => _cancelled = true),
                        child: const Text('Stop'),
                      ),
                    TextButton(
                      onPressed: _busy ? null : _close,
                      child: const Text('Close'),
                    ),
                    FilledButton.icon(
                      onPressed: editable && workspace.dirty ? _save : null,
                      icon: const Icon(Icons.save),
                      label: const Text('Save archive'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArchiveTextDialog extends StatefulWidget {
  const _ArchiveTextDialog({
    required this.title,
    required this.text,
    this.password = false,
    this.multiline = false,
    this.detail,
  });
  final String title, text;
  final bool password, multiline;
  final String? detail;
  @override
  State<_ArchiveTextDialog> createState() => _ArchiveTextDialogState();
}

class _ArchiveTextDialogState extends State<_ArchiveTextDialog> {
  late final _controller = TextEditingController(text: widget.text);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: widget.multiline ? 800 : 360,
      height: widget.multiline ? MediaQuery.sizeOf(context).height * .6 : null,
      child: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: widget.password,
        expands: widget.multiline,
        maxLines: widget.multiline ? null : 1,
        decoration: InputDecoration(helperText: widget.detail),
        style: widget.multiline
            ? const TextStyle(fontFamily: 'monospace')
            : null,
        onSubmitted: widget.multiline
            ? null
            : (value) => Navigator.pop(context, value),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(widget.multiline ? 'Apply to working archive' : 'OK'),
      ),
    ],
  );
}
