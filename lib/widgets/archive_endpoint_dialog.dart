import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/archive_endpoint_strings.dart';
import '../l10n/commander_strings.dart';
import '../models/file_item.dart';
import '../services/archive_container_publisher.dart';
import '../services/archive_endpoint.dart';
import '../services/archive_publication_journal.dart';
import '../services/archive_workspace.dart';
import '../services/file_operation_service.dart';
import '../utils/formatters.dart';

Future<ArchiveEndpointTransferResult?> showArchiveEndpointImportDialog(
  BuildContext context, {
  required FileOperationBackend source,
  required List<FileItem> files,
  required FileOperationBackend containerBackend,
  required FileItem containerFile,
  List<String> nestedMembers = const [],
  String directory = '/',
  String? expectedOuterFingerprint,
  bool moveSources = false,
  ArchivePublicationJournal? journal,
}) => showDialog<ArchiveEndpointTransferResult>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ArchiveEndpointDialog(
    source: source,
    files: List.unmodifiable(files),
    containerBackend: containerBackend,
    containerFile: containerFile,
    nestedMembers: List.unmodifiable(nestedMembers),
    directory: directory,
    expectedOuterFingerprint: expectedOuterFingerprint,
    moveSources: moveSources,
    journal: journal ?? ArchivePublicationJournal(),
  ),
);

Future<ArchivePublicationReceipt?> showArchiveWorkspacePublicationDialog(
  BuildContext context,
  ArchiveWorkspace workspace,
) async => (await showDialog<ArchiveEndpointTransferResult>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ArchiveEndpointDialog(
    workspace: workspace,
    containerBackend: workspace.outermost.source,
    containerFile: workspace.outermost.file,
    journal: workspace.journal,
  ),
))?.receipt;

class _ArchiveEndpointDialog extends StatefulWidget {
  const _ArchiveEndpointDialog({
    required this.containerBackend,
    required this.containerFile,
    required this.journal,
    this.source,
    this.files = const [],
    this.nestedMembers = const [],
    this.directory = '/',
    this.expectedOuterFingerprint,
    this.moveSources = false,
    this.workspace,
  });
  final FileOperationBackend containerBackend;
  final FileItem containerFile;
  final ArchivePublicationJournal journal;
  final FileOperationBackend? source;
  final List<FileItem> files;
  final List<String> nestedMembers;
  final String directory;
  final String? expectedOuterFingerprint;
  final bool moveSources;
  final ArchiveWorkspace? workspace;
  @override
  State<_ArchiveEndpointDialog> createState() => _ArchiveEndpointDialogState();
}

class _ArchiveEndpointDialogState extends State<_ArchiveEndpointDialog> {
  ArchiveEndpoint? _endpoint;
  ArchiveEndpointImportPlan? _plan;
  ArchiveWorkspaceReview? _review;
  ArchiveEndpointTransferResult? _result;
  FileConflictPolicy _conflict = FileConflictPolicy.keepBoth;
  FileOperationControl _control = FileOperationControl();
  bool _busy = true, _cancelled = false;
  String? _error;
  String _activity = 'preparing';
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _cancelled = true;
    _control.cancel();
    unawaited(_endpoint?.close());
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String activity) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _cancelled = false;
      _activity = activity;
    });
    _control = FileOperationControl();
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() => _run(() async {
    if (widget.workspace != null) {
      _endpoint = ArchiveEndpoint.fromWorkspace(widget.workspace!);
      _review = await _endpoint!.review(
        isCancelled: () => _cancelled || !mounted,
      );
      return;
    }
    await widget.journal.initialize();
    final pending = widget.journal.records.where(
      (record) =>
          !record.isFinished &&
          record.storage == widget.containerBackend.storageReference &&
          record.original.path == widget.containerFile.path,
    );
    if (pending.isNotEmpty) {
      if (!mounted) return;
      await showArchivePublicationRecoveryDialog(
        context,
        backend: widget.containerBackend,
        journal: widget.journal,
        containerPath: widget.containerFile.path,
      );
      if (!mounted) return;
      throw StateError(archiveEndpointText(context, 'reopen'));
    }
    final passwords = List<String?>.filled(
      widget.nestedMembers.length + 1,
      null,
    );
    while (mounted && !_cancelled) {
      try {
        final endpoint = await ArchiveEndpoint.open(
          containerBackend: widget.containerBackend,
          containerFile: widget.containerFile,
          nestedMembers: widget.nestedMembers,
          passwords: passwords,
          expectedOuterFingerprint: widget.expectedOuterFingerprint,
          journal: widget.journal,
        );
        if (!mounted || _cancelled) {
          await endpoint.close();
          return;
        }
        _endpoint = endpoint;
        break;
      } on ArchiveNestedPasswordRequiredException catch (error) {
        if (!mounted || _cancelled) return;
        final password = await _password(
          context,
          error.containerName,
          error.wrongPassword,
        );
        if (password == null) {
          _cancelled = true;
          return;
        }
        passwords[error.level] = password;
      }
    }
    if (_endpoint != null) await _prepare();
  }, 'preparing');

  Future<void> _prepare() async {
    _plan = await _endpoint!.prepareImport(
      source: widget.source!,
      files: widget.files,
      directory: widget.directory,
      moveSources: widget.moveSources,
      conflict: _conflict,
      control: _control,
    );
  }

  Future<void> _stage() => _run(() async {
    _review = await _endpoint!.stageImport(_plan!, control: _control);
  }, 'preparing');
  Future<void> _reviewAgain() => _run(() async {
    _review = await _endpoint!.review(
      isCancelled: () => _cancelled || !mounted,
    );
  }, 'preparing');
  Future<void> _publish() => _run(() async {
    _result = await _endpoint!.commit(
      reviewed: _review!,
      isCancelled: () => _cancelled || !mounted,
    );
  }, 'publishing');
  void _close() => Navigator.pop(context, _result);

  @override
  Widget build(BuildContext context) {
    String t(String key, [List<Object?> values = const []]) =>
        archiveEndpointText(context, key, values);
    final workspace = _endpoint?.workspace;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(t(_review == null ? 'importTitle' : 'reviewTitle')),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  [
                    widget.containerFile.path,
                    ...widget.nestedMembers,
                  ].join('!/'),
                ),
                if (widget.source != null)
                  Text('${widget.source!.label} → ${widget.directory}'),
                const SizedBox(height: 12),
                if (_busy) ...[
                  const LinearProgressIndicator(),
                  Text(t(_activity)),
                ],
                if (_error != null)
                  SelectableText(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_result != null) ...[
                  Text(t('published')),
                  if (_result!.receipt.cleanupPending)
                    Text(t('cleanupPending')),
                  if (_result!.retainedSources.isNotEmpty)
                    Text(t('retained', [_result!.retainedSources.length])),
                  for (final warning in _result!.warnings)
                    SelectableText(warning),
                ] else ...[
                  if (workspace != null && !workspace.canUpdate)
                    Text(workspace.updateSupport),
                  if (workspace != null) ...[
                    Text(
                      t('protection', [
                        workspace.encrypted
                            ? t(
                                workspace.encryptNames
                                    ? 'namesProtected'
                                    : 'dataProtected',
                              )
                            : t('unencrypted'),
                      ]),
                    ),
                    Text(t('metadata')),
                  ],
                  Text(t('publicationSafety')),
                  Text(t(widget.moveSources ? 'movePolicy' : 'copyPolicy')),
                  if (widget.moveSources) Text(t('directoriesRemain')),
                  if (workspace?.pendingPublication != null)
                    Text(t('recoveryClose')),
                  Text(t('bounds')),
                  if (_review == null &&
                      widget.source != null &&
                      _endpoint != null) ...[
                    DropdownButtonFormField<FileConflictPolicy>(
                      initialValue: _conflict,
                      decoration: InputDecoration(labelText: t('collision')),
                      items: [
                        for (final value in [
                          FileConflictPolicy.keepBoth,
                          FileConflictPolicy.skip,
                          FileConflictPolicy.replace,
                        ])
                          DropdownMenuItem(
                            value: value,
                            child: Text(t(value.name)),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _conflict = value);
                                unawaited(_run(_prepare, 'preparing'));
                              }
                            },
                    ),
                    if (_plan != null) ...[
                      for (final error in _plan!.errors)
                        Text(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      Text(t('entries', [_plan!.entries.length])),
                      for (final entry in _plan!.entries.take(100))
                        Text(
                          '${entry.source.path} → ${entry.destination}${entry.existing == null ? '' : ' • ${t('collision')}'}',
                        ),
                    ],
                  ],
                  if (_review != null) ...[
                    Text(t('packed', [formatBytes(_review!.packedBytes)])),
                    Text(t('entries', [_review!.changes.length])),
                    for (final change in _review!.changes.take(100))
                      Text(
                        '${t(change.kind.name)}: ${change.from == null ? '' : '${change.from} → '}${change.path}',
                      ),
                    if (_review!.changes.length > 100)
                      Text(t('moreEntries', [_review!.changes.length - 100])),
                  ],
                  Text(t('draftOnly')),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (_busy)
            TextButton(
              onPressed: () {
                setState(() => _cancelled = true);
                _control.cancel();
              },
              child: Text(context.commanderTr('Cancel')),
            ),
          if (!_busy)
            TextButton(
              onPressed: _close,
              child: Text(context.commanderTr('Close')),
            ),
          if (!_busy &&
              _result == null &&
              _review == null &&
              _endpoint?.workspace.dirty == true)
            TextButton(onPressed: _reviewAgain, child: Text(t('reviewTitle'))),
          if (!_busy &&
              _result == null &&
              _review == null &&
              _plan?.canStage == true)
            FilledButton(onPressed: _stage, child: Text(t('stage'))),
          if (!_busy && _result == null && _review != null)
            FilledButton(onPressed: _publish, child: Text(t('publish'))),
        ],
      ),
    );
  }
}

Future<String?> _password(BuildContext context, String name, bool wrong) async {
  final controller = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
          context.commanderTr(
            wrong ? 'Incorrect password. Try again' : 'Archive password',
          ),
        ),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(labelText: name),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.commanderTr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(context.commanderTr('Continue')),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

/// Recovery is scoped to one already captured account. A true result means an
/// explicit recovery action was attempted; callers should refresh and recapture
/// the container before a new edit, even if the path now exists again.
Future<bool> showArchivePublicationRecoveryDialog(
  BuildContext context, {
  required FileOperationBackend backend,
  ArchivePublicationJournal? journal,
  String? containerPath,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ArchiveRecoveryDialog(
        backend: backend,
        journal: journal ?? ArchivePublicationJournal(),
        containerPath: containerPath,
      ),
    ) ??
    false;

class _ArchiveRecoveryDialog extends StatefulWidget {
  const _ArchiveRecoveryDialog({
    required this.backend,
    required this.journal,
    this.containerPath,
  });
  final FileOperationBackend backend;
  final ArchivePublicationJournal journal;
  final String? containerPath;
  @override
  State<_ArchiveRecoveryDialog> createState() => _ArchiveRecoveryDialogState();
}

class _ArchiveRecoveryDialogState extends State<_ArchiveRecoveryDialog> {
  List<ArchiveRecoveryInspection> _records = [];
  bool _busy = true, _changed = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.journal.initialize();
      final publisher = ArchiveContainerPublisher(
        widget.backend,
        widget.journal,
      );
      final records = <ArchiveRecoveryInspection>[];
      for (final record in widget.journal.records.where(
        (record) =>
            !record.isFinished &&
            record.storage == widget.backend.storageReference &&
            (widget.containerPath == null ||
                record.original.path == widget.containerPath),
      )) {
        try {
          records.add(await publisher.inspect(record));
        } catch (error) {
          records.add(
            ArchiveRecoveryInspection(
              record: record,
              canFinish: false,
              canRestore: false,
              message: '$error',
            ),
          );
        }
      }
      if (mounted) setState(() => _records = records);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover(
    ArchiveRecoveryInspection item,
    ArchiveRecoveryAction action,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
      _changed = true;
    });
    try {
      await ArchiveContainerPublisher(
        widget.backend,
        widget.journal,
      ).recover(item.record, action, isCancelled: () => !mounted);
      if (mounted) await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => archiveEndpointText(context, key);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(t('recoveryTitle')),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('recoveryDetail')),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null) SelectableText(_error!),
                if (!_busy && _records.isEmpty) Text(t('noRecovery')),
                for (final item in _records)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(item.record.original.path!),
                          Text(item.message),
                          SelectableText(
                            item.record.candidatePath(widget.backend.paths),
                          ),
                          SelectableText(
                            item.record.backupPath(widget.backend.paths),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: !_busy && item.canFinish
                                    ? () => _recover(
                                        item,
                                        ArchiveRecoveryAction.finishPublication,
                                      )
                                    : null,
                                child: Text(t('finish')),
                              ),
                              TextButton(
                                onPressed: !_busy && item.canRestore
                                    ? () => _recover(
                                        item,
                                        ArchiveRecoveryAction.restoreOriginal,
                                      )
                                    : null,
                                child: Text(t('restore')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : _reload,
            child: Text(t('recheck')),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, _changed),
            child: Text(context.commanderTr('Close')),
          ),
        ],
      ),
    );
  }
}
