import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/commander_strings.dart';
import '../l10n/archive_endpoint_strings.dart';
import '../l10n/archive_member_move_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/archive_browser_session.dart';
import '../services/archive_workspace.dart';
import '../services/archive_endpoint.dart';
import '../services/archive_publication_journal.dart';
import '../services/editor_document.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import '../utils/file_editability.dart';
import '../utils/formatters.dart';
import 'file_operation_dialog.dart';
import 'internal_viewer_dialog.dart';
import 'archive_endpoint_dialog.dart';
import 'archive_endpoint_actions.dart';
import 'archive_member_move_dialog.dart';

enum ArchiveWorkspaceAction { browse, copyOut, moveOut, edit }

/// A reviewed draft may outlive its original route and pane view. The captured
/// storage capability still rejects account disconnection or replacement.
class _ArchiveWorkspaceAuthority {
  _ArchiveWorkspaceAuthority(this.origin, this.location);

  final PanelFileOrigin origin;
  final ArchiveWorkspaceLocation? location;
  bool viewOpen = true;
  bool background = false;

  bool get isCurrent =>
      origin.isCurrent &&
      (background || (viewOpen && (location?.isCurrent() ?? true)));
}

/// Reuses the actual archive account and the member selection of an archive
/// panel. Member paths are archive-relative; the container path is kept separate.
Future<void> showCurrentArchiveWorkspaceDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side, {
  ArchiveWorkspaceAction action = ArchiveWorkspaceAction.browse,
  FileItem? focusedMember,
  ArchivePublicationJournal? journal,
}) async {
  try {
    final panel = ref.read(panelProvider(side));
    final origin = panel.captureArchiveOrigin();
    final archive = panel.archiveSource!;
    final location = panel.captureArchiveWorkspaceLocation();
    if (focusedMember != null &&
        !(panel.files?.any((file) => identical(file, focusedMember)) ??
            false)) {
      throw StateError('This archive row is no longer current. Reopen it.');
    }
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
      location.file,
      sourceOrigin: origin,
      location: location,
      initialDirectory: memberPath(archive.innerPath),
      initialSelectedPaths: selected
          .where((file) => file.name != '..' && file.path != null)
          .map((file) => memberPath(file.path!))
          .toSet(),
      initialAction: action,
      journal: journal,
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
  ArchiveWorkspaceLocation? location,
  String initialDirectory = '/',
  Set<String> initialSelectedPaths = const {},
  ArchiveWorkspaceAction initialAction = ArchiveWorkspaceAction.browse,
  ArchivePublicationJournal? journal,
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
        location: location,
        initialDirectory: initialDirectory,
        initialSelectedPaths: initialSelectedPaths,
        initialAction: initialAction,
        journal: journal,
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
    this.location,
    required this.initialDirectory,
    required this.initialSelectedPaths,
    required this.initialAction,
    this.journal,
  });
  final PanelSide side;
  final FileItem file;
  final PanelFileOrigin origin;
  final ArchiveWorkspaceLocation? location;
  final String initialDirectory;
  final Set<String> initialSelectedPaths;
  final ArchiveWorkspaceAction initialAction;
  final ArchivePublicationJournal? journal;
  @override
  ConsumerState<_ArchiveWorkspaceDialog> createState() =>
      _ArchiveWorkspaceDialogState();
}

class _ArchiveWorkspaceDialogState
    extends ConsumerState<_ArchiveWorkspaceDialog> {
  ArchiveWorkspace? _workspace;
  late final _ArchiveWorkspaceAuthority _authority;
  bool _backgroundAdmission = false;
  bool _workspaceHandedOff = false;
  final _selected = <String>{};
  String _path = '/';
  bool _busy = false;
  bool _cancelled = false;
  FileOperationControl? _importControl;
  bool _replaceOnAdd = false;
  String? _error;
  String Function(BuildContext)? _message;

  @override
  void initState() {
    super.initState();
    _authority = _ArchiveWorkspaceAuthority(widget.origin, widget.location);
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
        setState(
          () =>
              _message = (context) =>
                  context.commanderTr(_workspace!.updateSupport),
        );
      }
    } else if (widget.initialAction == ArchiveWorkspaceAction.edit &&
        _selection.length == 1) {
      if (_workspace!.canUpdate && isTextEditableName(_selection.single.name)) {
        await _edit();
      } else {
        setState(
          () => _message = (context) => context.commanderTr(
            "Copy this member out, edit it, then add it with replacement enabled.",
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _authority.viewOpen = false;
    _cancelled = true;
    _importControl?.cancel();
    // Admission owns cleanup until it either returns a queue handle or fails.
    // The accepted workspace (and its spools) then belongs to the queue.
    if (!_workspaceHandedOff && !_backgroundAdmission) {
      unawaited(_workspace?.close());
    }
    super.dispose();
  }

  Future<String?> _prompt(
    String title,
    String initial, {
    bool password = false,
  }) => showDialog<String>(
    context: context,
    builder: (_) => _ArchiveTextDialog(
      title: context.commanderTr(title),
      text: initial,
      password: password,
    ),
  );

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final passwords = List<String?>.filled(
      (widget.location?.nestedMembers.length ?? 0) + 1,
      null,
    );
    try {
      final authority = _authority;
      final source = fileOperationBackend(
        source: widget.origin.source,
        local: ref.read(localFileServiceProvider),
        isCurrent: () => authority.isCurrent,
      );
      final journal = widget.journal ?? ArchivePublicationJournal();
      await journal.initialize();
      if (journal.records.any(
        (record) =>
            !record.isFinished &&
            record.storage == source.storageReference &&
            record.original.path == widget.file.path,
      )) {
        if (!mounted) return;
        await showArchivePublicationRecoveryDialog(
          context,
          backend: source,
          journal: journal,
          containerPath: widget.file.path,
        );
        if (!mounted) return;
        throw StateError(archiveEndpointText(context, 'reopen'));
      }
      while (mounted) {
        try {
          final workspace = await ArchiveWorkspace.openNested(
            source,
            widget.file,
            widget.location?.nestedMembers ?? const [],
            passwords: passwords,
            journal: journal,
            expectedOuterFingerprint: widget.location?.fingerprint,
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
        } on ArchiveNestedPasswordRequiredException catch (error) {
          if (!mounted) return;
          final password = await _prompt(
            error.wrongPassword
                ? 'Incorrect password. Try again'
                : 'Archive password',
            '',
            password: true,
          );
          if (password == null) return;
          passwords[error.level] = password;
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
          title: context.commanderTr("Edit {0}", [file.name]),
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
      setState(
        () =>
            _error = context.commanderTr("Select an available archive member."),
      );
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

  Future<void> _moveWithin() async {
    final workspace = _workspace;
    final selected = List<FileItem>.unmodifiable(_selection);
    final directory = _path;
    if (workspace == null || selected.isEmpty || !workspace.canMoveMembers) {
      return;
    }
    await _run(() async {
      final result = await showArchiveMemberMoveDialog(
        context,
        workspace: workspace,
        members: selected,
        initialDirectory: directory,
      );
      if (!mounted || result == null || !identical(_workspace, workspace)) {
        return;
      }
      setState(() {
        // Skipped and unchanged members remain selected at the source. Moved
        // members are reviewed by the normal whole-container Save action.
        _selected
          ..clear()
          ..addAll(result.skipped)
          ..addAll(result.unchanged);
        _message = (context) => result.moved.isEmpty
            ? archiveMemberMoveText(context, 'noChanges', [
                result.skipped.length,
                result.unchanged.length,
              ])
            : archiveMemberMoveText(context, 'result', [
                result.moved.length,
                result.skipped.length,
                result.unchanged.length,
              ]);
      });
    });
  }

  Future<void> _remove() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          context.commanderTr("Remove {0} selected member(s)?", [
            _selected.length,
          ]),
        ),
        content: Text(
          context.commanderTr(
            "This changes the working archive. Save archive applies the changes to the original file.",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.commanderTr("Cancel")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.commanderTr("Remove members")),
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
      if (other.isInArchive) {
        throw UnsupportedError(
          archiveEndpointText(context, 'sourceArchiveUnsupported'),
        );
      }
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
      final endpoint = ArchiveEndpoint.fromWorkspace(_workspace!);
      final control = FileOperationControl();
      _importControl = control;
      try {
        final plan = await endpoint.prepareImport(
          source: fileOperationBackend(
            source: origin.source,
            local: ref.read(localFileServiceProvider),
            isCurrent: () => mounted && origin.isCurrent,
          ),
          files: files,
          directory: _path,
          conflict: _replaceOnAdd
              ? FileConflictPolicy.replace
              : FileConflictPolicy.keepBoth,
          control: control,
        );
        if (_cancelled || !mounted) control.cancel();
        await endpoint.stageImport(plan, control: control);
      } finally {
        _importControl = null;
        await endpoint.close();
      }
      if (mounted) {
        setState(
          () => _message = (context) => context.commanderTr(
            "Added {0} selected item(s). Save archive to apply.",
            [files.length],
          ),
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
    final files = List<FileItem>.unmodifiable(_selection);
    final otherSide = widget.side == PanelSide.local
        ? PanelSide.remote
        : PanelSide.local;
    if (ref.read(panelProvider(otherSide)).isInArchive) {
      ArchiveEndpointTransferResult? result;
      var sourceInvalidated = false;
      await _run(() async {
        final destination = CapturedArchiveImportDestination.capture(
          ref,
          otherSide,
        );
        result = await showCapturedArchiveWorkspaceCopy(
          context,
          source: _workspace!,
          files: files,
          destination: destination,
          moveSources: true,
          isReviewCurrent: () => mounted && widget.origin.isCurrent,
          onSourceInvalidated: () => sourceInvalidated = true,
        );
      });
      // Source removal is published from a separate reviewed candidate. Close
      // this borrowed view before its old in-memory members can be used again.
      if (mounted && (result != null || sourceInvalidated)) {
        Navigator.pop(context);
      }
      return;
    }
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.commanderTr("Move members out of this archive?")),
        content: Text(
          context.commanderTr(
            "Choose copy options next. Only successfully copied and verified members are removed from the working archive. Save archive to commit the removal.",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.commanderTr("Cancel")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.commanderTr("Continue")),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    await _run(() async {
      final plan = await showFileOperationDialog(
        context,
        ref,
        widget.side,
        files,
        kind: FileOperationKind.copy,
        sourceOrigin: widget.origin,
        sourceBackend: _workspace!.backend,
        archiveSourceMove: true,
      );
      if (plan == null || !mounted) return;
      final count = await _workspace!.stageCopiedMemberRemoval(
        plan,
        isCancelled: () => _cancelled || !mounted,
      );
      if (mounted) {
        setState(() {
          _selected.clear();
          _message = (context) => count == 0
              ? context.commanderTr("No copied members were removed.")
              : context.commanderTr(
                  "Moved {0} member(s) in the working copy. Save archive to commit removal.",
                  [count],
                );
        });
      }
    });
  }

  Future<void> _save() async => _run(() async {
    final receipt = await showArchiveWorkspacePublicationDialog(
      context,
      _workspace!,
    );
    if (mounted && receipt != null) {
      setState(
        () =>
            _message = (context) =>
                context.commanderTr("Archive saved and verified."),
      );
    }
  });

  Future<void> _saveInBackground() async {
    final workspace = _workspace;
    if (_busy || workspace == null || !workspace.dirty || !workspace.isCurrent) {
      return;
    }
    final revision = workspace.revision;
    final changes = workspace.draftChanges;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.commanderTr('Save archive in background?')),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dialogContext.commanderTr(
                    'Publish these draft changes to {0} in the background? The original archive will be replaced only after packing and verification succeed.',
                    [workspace.outermost.file.path ?? workspace.outermost.file.name],
                  ),
                ),
                if (workspace.nestedMemberPaths.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(workspace.nestedMemberPaths.join(' → ')),
                ],
                const SizedBox(height: 12),
                for (final change in changes)
                  Text(
                    '${archiveEndpointText(dialogContext, change.kind.name)}: '
                    '${change.from == null ? '' : '${change.from} → '}${change.path}',
                  ),
                const SizedBox(height: 12),
                Text(
                  dialogContext.commanderTr(
                    'Packing continues while CrispCloud is open. You can pause or stop it in the operation queue.',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.commanderTr('Keep editing')),
          ),
          FilledButton.icon(
            key: const ValueKey('archive-workspace-background-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.queue),
            label: Text(dialogContext.commanderTr('Save in background')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (!_authority.isCurrent || workspace.revision != revision) {
      setState(() => _error = context.commanderTr(
        'The archive draft changed. Review its current changes again.',
      ));
      return;
    }
    final transfers = ref.read(transferProvider);
    setState(() {
      _busy = true;
      _backgroundAdmission = true;
      _error = null;
    });
    // The scheduler can begin immediately after its durable admission, before
    // this await resumes. Release only the view guard now; the original account
    // capability and workspace fingerprint remain bound to the captured draft.
    _authority.background = true;
    try {
      await transfers.enqueueArchiveWorkspace(workspace);
      _workspaceHandedOff = true;
      if (mounted) Navigator.pop(context);
    } catch (error) {
      _authority.background = false;
      if (mounted) {
        setState(() => _error = '$error');
      } else {
        await workspace.close();
      }
    } finally {
      _backgroundAdmission = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createDirectory() async {
    final name = await _prompt('New folder', '');
    if (name == null || !mounted) return;
    await _run(() async {
      if (name.trim().isEmpty || name.contains('/') || name.contains('\\')) {
        throw StateError('Enter a single folder name.');
      }
      _workspace!.createDirectory(p.posix.join(_path, name));
    });
  }

  Future<void> _close() async {
    if (_busy) return;
    if (_workspace?.pendingPublication != null) {
      final close = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(archiveEndpointText(context, 'recoveryTitle')),
          content: Text(archiveEndpointText(context, 'recoveryClose')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.commanderTr('Keep editing')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.commanderTr('Close')),
            ),
          ],
        ),
      );
      if (close != true || !mounted) return;
    } else if (_workspace?.dirty == true) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.commanderTr("Discard unsaved archive changes?")),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.commanderTr("Keep editing")),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.commanderTr("Discard changes")),
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
      canPop: _workspaceHandedOff || (!_busy && workspace?.dirty != true),
      child: Dialog(
        child: SizedBox(
          width: math.min(960, size.width * .95),
          height: size.height * .9,
          child: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
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
                                    [
                                      widget.file.name,
                                      ...?widget.location?.nestedMembers,
                                    ].join('!/'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  tooltip: context.commanderTr("Close archive"),
                                  onPressed: _busy ? null : _close,
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                          if (workspace?.dirty == true)
                            Text(context.commanderTr("Unsaved changes")),
                          if (workspace != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                '${workspace.format.toUpperCase()} · ${context.commanderTr(workspace.updateSupport)}',
                              ),
                            ),
                          if (workspace?.supportsLargeFiles == true)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                archiveEndpointText(
                                  context,
                                  switch (workspace!.format) {
                                    'iso' => 'streamedIsoBounds',
                                    'dmg' => 'streamedDmgBounds',
                                    _ => 'streamedBounds',
                                  },
                                ),
                                style: Theme.of(context).textTheme.bodySmall,
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
                                  label: Text(context.commanderTr("Up")),
                                ),
                                TextButton(
                                  onPressed: enabled
                                      ? () => setState(() {
                                          _selected
                                            ..clear()
                                            ..addAll(
                                              files.map((file) => file.path!),
                                            );
                                        })
                                      : null,
                                  child: Text(
                                    context.commanderTr("Select all"),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: enabled && selected.isNotEmpty
                                      ? _copyOut
                                      : null,
                                  icon: const Icon(Icons.copy),
                                  label: Text(
                                    context.commanderTr(
                                      "Copy out with options…",
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: editable && selected.isNotEmpty
                                      ? _moveOut
                                      : null,
                                  icon: const Icon(
                                    Icons.drive_file_move_outline,
                                  ),
                                  label: Text(
                                    context.commanderTr(
                                      "Move out with options…",
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: editable ? _add : null,
                                  icon: const Icon(Icons.add),
                                  label: Text(
                                    context.commanderTr("Add from other panel"),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: editable ? _createDirectory : null,
                                  icon: const Icon(
                                    Icons.create_new_folder_outlined,
                                  ),
                                  label: Text(
                                    archiveEndpointText(
                                      context,
                                      'createDirectory',
                                    ),
                                  ),
                                ),
                                FilterChip(
                                  label: Text(
                                    context.commanderTr(
                                      "Replace members on add",
                                    ),
                                  ),
                                  selected: _replaceOnAdd,
                                  onSelected: editable
                                      ? (value) => setState(
                                          () => _replaceOnAdd = value,
                                        )
                                      : null,
                                ),
                                TextButton(
                                  onPressed:
                                      editable &&
                                          selected.length == 1 &&
                                          !selected.single.isFolder &&
                                          isTextEditableName(
                                            selected.single.name,
                                          )
                                      ? _edit
                                      : null,
                                  child: Text(context.commanderTr("Edit text")),
                                ),
                                TextButton(
                                  onPressed: editable && selected.length == 1
                                      ? _rename
                                      : null,
                                  child: Text(context.commanderTr("Rename")),
                                ),
                                TextButton.icon(
                                  key: const ValueKey(
                                    'archive-workspace-move-within',
                                  ),
                                  onPressed:
                                      editable &&
                                          workspace.canMoveMembers &&
                                          selected.isNotEmpty
                                      ? _moveWithin
                                      : null,
                                  icon: const Icon(
                                    Icons.drive_file_move_outline,
                                  ),
                                  label: Text(
                                    archiveMemberMoveText(context, 'action'),
                                  ),
                                ),
                                TextButton(
                                  onPressed: editable && selected.isNotEmpty
                                      ? _remove
                                      : null,
                                  child: Text(context.commanderTr("Remove")),
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
                              child: Semantics(
                                liveRegion: true,
                                child: Text(_message!(context)),
                              ),
                            ),
                          if (_busy) const LinearProgressIndicator(),
                          if (workspace != null && !workspace.isCurrent)
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                context.commanderTr(
                                  "The original account is unavailable. Reconnect and reopen this archive.",
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SliverList.builder(
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
                              semanticLabel: context.commanderTr("Select {0}", [
                                file.name,
                              ]),
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
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 12,
                  children: [
                    if (_busy)
                      TextButton(
                        onPressed: _backgroundAdmission ? null : () {
                          setState(() => _cancelled = true);
                          _importControl?.cancel();
                        },
                        child: Text(context.commanderTr("Stop")),
                      ),
                    TextButton(
                      onPressed: _busy ? null : _close,
                      child: Text(context.commanderTr("Close")),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('archive-workspace-background'),
                      onPressed: editable && workspace.dirty
                          ? _saveInBackground
                          : null,
                      icon: const Icon(Icons.queue),
                      label: Text(context.commanderTr('Save in background')),
                    ),
                    FilledButton.icon(
                      onPressed: editable && workspace.dirty ? _save : null,
                      icon: const Icon(Icons.save),
                      label: Text(context.commanderTr("Save archive")),
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
        child: Text(context.commanderTr("Cancel")),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(
          widget.multiline
              ? context.commanderTr("Apply to working archive")
              : context.commanderTr("OK"),
        ),
      ),
    ],
  );
}
