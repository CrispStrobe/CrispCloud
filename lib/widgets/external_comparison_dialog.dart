import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/external_comparison_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/core_providers.dart';
import '../providers/external_comparison_provider.dart';
import '../providers/panel_provider.dart';
import '../services/command_entry_service.dart';
import '../services/external_comparison_service.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import '../services/local_file_service.dart';

export '../models/external_comparison.dart';

/// Call while constructing the menu, before any menu-selection await. Neither
/// the returned pair nor showExternalComparisonDialog re-reads a selection.
ExternalComparisonPair captureExternalComparisonPair(
  WidgetRef ref, {
  required PanelSide leftSide,
  required FileItem leftFile,
  required PanelSide rightSide,
  required FileItem rightFile,
}) {
  final local = ref.read(localFileServiceProvider);
  ExternalComparisonInput capture(PanelSide side, FileItem file) {
    final panel = ref.read(panelProvider(side));
    final origin = panel.captureOperationOrigin([file]);
    final session = panel.captureOperationSession();
    final navigation = panel.navigationIntentRevision;
    final path = file.path ?? origin.source.currentPath;
    final identities = local is LocalFileSourceIdentity
        ? local as LocalFileSourceIdentity
        : null;
    final grant = origin.source.isLocal
        ? identities?.sourceIdentityForPath(path)
        : null;
    if (origin.source.isLocal && identities != null && grant == null) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.unavailable,
      );
    }
    var lost = false;
    bool current() {
      if (lost) return false;
      lost =
          !ref.context.mounted ||
          !session() ||
          !origin.isCurrent ||
          panel.navigationIntentRevision != navigation ||
          origin.source.isLocal &&
              identities != null &&
              !identical(identities.sourceIdentityForPath(path), grant);
      return !lost;
    }

    final backend = fileOperationBackend(
      source: origin.source,
      local: local,
      isCurrent: current,
    );
    final fullPath =
        file.path ?? backend.paths.join(origin.source.currentPath, file.name);
    return ExternalComparisonInput(
      backend: backend,
      file: file.copyWith(path: fullPath),
      storage: origin.storageReference,
      isCurrent: current,
    );
  }

  return ExternalComparisonPair(
    left: capture(leftSide, leftFile),
    right: capture(rightSide, rightFile),
  );
}

ExternalComparisonPair captureExternalComparisonSelection(WidgetRef ref) {
  final side = ref.read(activePanelProvider);
  final active = ref.read(panelProvider(side));
  final selected = active.selection.toList(growable: false);
  if (selected.length == 2) {
    return captureExternalComparisonPair(
      ref,
      leftSide: side,
      leftFile: selected[0],
      rightSide: side,
      rightFile: selected[1],
    );
  }
  FileItem one(PanelSide sourceSide) {
    final panel = ref.read(panelProvider(sourceSide));
    final files = panel.selection.isNotEmpty
        ? panel.selection.toList()
        : [if (panel.cursorItem case final row? when row.name != '..') row];
    if (files.length != 1) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.unavailable,
      );
    }
    return files.single;
  }

  return captureExternalComparisonPair(
    ref,
    leftSide: PanelSide.local,
    leftFile: one(PanelSide.local),
    rightSide: PanelSide.remote,
    rightFile: one(PanelSide.remote),
  );
}

Future<void> showExternalComparisonForSelection(
  BuildContext context,
  WidgetRef ref,
) async {
  ExternalComparisonPair? pair;
  Object? error;
  try {
    pair = captureExternalComparisonSelection(ref);
  } catch (_) {
    error = const ExternalComparisonException(
      ExternalComparisonFailure.unavailable,
    );
  }
  await showExternalComparisonDialog(
    context,
    ref,
    pair: pair,
    initialError: error,
  );
}

/// With no pair this is the preferences/retained-session surface. Passing a
/// pair transfers ownership; it is invalidated when the dialog closes.
Future<void> showExternalComparisonDialog(
  BuildContext context,
  WidgetRef ref, {
  ExternalComparisonPair? pair,
  Object? initialError,
}) async {
  final service = ref.read(externalComparisonServiceProvider);
  try {
    await showDialog<void>(
      context: context,
      builder: (_) => ExternalComparisonDialog(
        service: service,
        pair: pair,
        initialError: initialError,
      ),
    );
  } finally {
    pair?.dispose();
  }
}

class ExternalComparisonDialog extends StatefulWidget {
  const ExternalComparisonDialog({
    super.key,
    required this.service,
    this.pair,
    this.initialError,
  });
  final ExternalComparisonService service;
  final ExternalComparisonPair? pair;
  final Object? initialError;
  @override
  State<ExternalComparisonDialog> createState() =>
      _ExternalComparisonDialogState();
}

class _ExternalComparisonDialogState extends State<ExternalComparisonDialog> {
  final _executable = TextEditingController();
  final _arguments = TextEditingController(text: '{left} {right}');
  ExternalComparisonKind _kind = ExternalComparisonKind.text;
  FileOperationControl? _control;
  int _revision = 0;
  bool _busy = false, _reviewing = false, _closing = false, _saved = false;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
    widget.service.addListener(_refresh);
    if (widget.service.loaded) {
      _restore();
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    await widget.service.ready;
    if (mounted) setState(_restore);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _restore() {
    final saved = widget.service.configuration(_kind);
    _executable.text = saved?.executable ?? '';
    _arguments.text =
        saved?.arguments.map(encodeCommandEntryArgument).join(' ') ??
        '{left} {right}';
    _error ??= widget.service.loadError;
  }

  void _changed([String? value]) => setState(() {
    _revision++;
    _error = null;
    _saved = false;
  });
  ExternalComparisonConfiguration _configuration() {
    try {
      return ExternalComparisonConfiguration(
        platform: widget.service.platform ?? 'unsupported',
        kind: _kind,
        executable: _executable.text.trim(),
        arguments: parseCommandEntryArguments(_arguments.text),
      );
    } catch (_) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.invalidConfiguration,
      );
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
      _saved = false;
    });
    try {
      await widget.service.saveConfiguration(_configuration());
      if (mounted) setState(() => _saved = true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepare() async {
    final pair = widget.pair;
    if (_busy || pair == null) return;
    final revision = _revision;
    final control = _control = FileOperationControl();
    PreparedExternalComparison? prepared;
    setState(() {
      _busy = true;
      _error = null;
      _saved = false;
    });
    try {
      prepared = await widget.service.prepare(
        _configuration(),
        pair,
        control: control,
        isCurrent: () => mounted && !_closing && _revision == revision,
      );
      if (!mounted || _closing) return;
      setState(() => _reviewing = true);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ExternalComparisonReview(
          service: widget.service,
          prepared: prepared!,
        ),
      );
    } catch (error) {
      if (mounted && !_closing) setState(() => _error = error);
    } finally {
      if (prepared != null) {
        try {
          await widget.service.discard(prepared);
        } catch (error) {
          if (mounted && !_closing) setState(() => _error = error);
        }
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _reviewing = false;
        });
      }
    }
  }

  Future<void> _release(ExternalComparisonSession session) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) {
        var confirmed = false;
        final s = ExternalComparisonStrings(context);
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(s.text('release')),
            scrollable: true,
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.text('retention')),
                  CheckboxListTile(
                    value: confirmed,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(s.text('toolClosed')),
                    onChanged: (value) =>
                        setState(() => confirmed = value == true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(s.text('cancel')),
              ),
              FilledButton(
                onPressed: confirmed
                    ? () => Navigator.pop(context, true)
                    : null,
                child: Text(s.text('release')),
              ),
            ],
          ),
        );
      },
    );
    if (accepted != true || !mounted) return;
    try {
      await widget.service.release(session.id, toolClosed: true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _closing = true;
    _control?.cancel();
    widget.pair?.dispose();
    widget.service.removeListener(_refresh);
    _executable.dispose();
    _arguments.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ExternalComparisonStrings(context);
    final available = widget.service.platform != null && widget.service.loaded;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _closing = true;
          _control?.cancel();
        }
      },
      child: AlertDialog(
        title: Text(s.text('title')),
        scrollable: true,
        content: SizedBox(
          width: 660,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.service.platform == null) Text(s.text('unsupported')),
              Text(s.text('copies')),
              Text(
                s.text('limits', [
                  widget.service.maxInputBytes ~/ (1024 * 1024),
                ]),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ExternalComparisonKind>(
                key: const ValueKey('external-comparison-kind'),
                initialValue: _kind,
                isExpanded: true,
                items: [
                  for (final kind in ExternalComparisonKind.values)
                    DropdownMenuItem(
                      value: kind,
                      child: Text(s.text(kind.name)),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (kind) {
                        if (kind != null) {
                          setState(() {
                            _kind = kind;
                            _revision++;
                            _restore();
                            _saved = false;
                          });
                        }
                      },
              ),
              TextField(
                key: const ValueKey('external-comparison-executable'),
                controller: _executable,
                enabled: available && !_busy,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: s.text('executable')),
                onChanged: _changed,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('external-comparison-arguments'),
                controller: _arguments,
                enabled: available && !_busy,
                minLines: 2,
                maxLines: 5,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: s.text('arguments')),
                onChanged: _changed,
              ),
              const SizedBox(height: 8),
              Text(s.text('argumentHelp')),
              if (widget.pair case final pair?) ...[
                const Divider(),
                _source(s.text('left'), pair.left),
                _source(s.text('right'), pair.right),
              ] else ...[
                const SizedBox(height: 12),
                Text(s.text('choosePair')),
              ],
              if (_busy && !_reviewing) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                Text(s.text('preparing')),
              ],
              if (_saved) Text(s.text('saved')),
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    s.failure(_error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const Divider(),
              Text(
                s.text('sessions'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(s.text('retention')),
              if (widget.service.sessions.isEmpty) Text(s.text('none')),
              for (final session in widget.service.sessions)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        session.executable,
                        textDirection: TextDirection.ltr,
                      ),
                      SelectableText(
                        session.sourceLabel('left'),
                        textDirection: TextDirection.ltr,
                      ),
                      SelectableText(
                        session.sourceLabel('right'),
                        textDirection: TextDirection.ltr,
                      ),
                      SelectableText(
                        session.stage.directoryPath,
                        textDirection: TextDirection.ltr,
                      ),
                      if (session.state == 'launchFailed')
                        Text(s.text('launchFailed')),
                      TextButton(
                        onPressed: session.busy
                            ? null
                            : () => _release(session),
                        child: Text(s.text('release')),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _closing = true;
              _control?.cancel();
              Navigator.pop(context);
            },
            child: Text(s.text('close')),
          ),
          TextButton(
            key: const ValueKey('external-comparison-save'),
            onPressed: available && !_busy ? _save : null,
            child: Text(s.text('save')),
          ),
          FilledButton(
            key: const ValueKey('external-comparison-prepare'),
            onPressed: available && !_busy && widget.pair != null
                ? _prepare
                : null,
            child: Text(s.text('prepare')),
          ),
        ],
      ),
    );
  }

  Widget _source(String title, ExternalComparisonInput input) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        SelectableText(
          '${input.storage.provider} · ${input.storage.accountKey} · ${input.storage.root}\n${input.file.path}',
          textDirection: TextDirection.ltr,
        ),
      ],
    ),
  );
}

class ExternalComparisonReview extends StatefulWidget {
  const ExternalComparisonReview({
    super.key,
    required this.service,
    required this.prepared,
  });
  final ExternalComparisonService service;
  final PreparedExternalComparison prepared;
  @override
  State<ExternalComparisonReview> createState() =>
      _ExternalComparisonReviewState();
}

class _ExternalComparisonReviewState extends State<ExternalComparisonReview> {
  final _control = FileOperationControl();
  bool _busy = false, _attempted = false, _opened = false, _closing = false;
  Object? _error;
  @override
  void initState() {
    super.initState();
    widget.service.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _launch() async {
    setState(() {
      _busy = true;
      _attempted = true;
    });
    try {
      await widget.service.launch(
        widget.prepared,
        control: _control,
        isReviewCurrent: () =>
            mounted && !_closing && ModalRoute.of(context)?.isCurrent != false,
      );
      if (mounted) setState(() => _opened = true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _closing = true;
    _control.cancel();
    widget.service.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ExternalComparisonStrings(context);
    final prepared = widget.prepared;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(s.text('review')),
        scrollable: true,
        content: SizedBox(
          width: 660,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.text('copies')),
              Text(s.text('left')),
              SelectableText(
                prepared.session.sourceLabel('left'),
                textDirection: TextDirection.ltr,
              ),
              Text(s.text('right')),
              SelectableText(
                prepared.session.sourceLabel('right'),
                textDirection: TextDirection.ltr,
              ),
              const Divider(),
              SelectableText(
                prepared.executable.resolvedPath,
                textDirection: TextDirection.ltr,
              ),
              for (final argument in prepared.arguments)
                SelectableText(argument, textDirection: TextDirection.ltr),
              const SizedBox(height: 12),
              Text(s.text('retention')),
              if (_busy) const LinearProgressIndicator(),
              if (_opened || prepared.session.launchRequested)
                Text(s.text('launched')),
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    s.failure(_error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (_busy && !prepared.session.launchRequested)
            TextButton(
              onPressed: _control.cancel,
              child: Text(s.text('cancel')),
            ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(s.text('close')),
          ),
          if (!_attempted)
            FilledButton(
              key: const ValueKey('external-comparison-launch'),
              onPressed: _launch,
              child: Text(s.text('launch')),
            ),
        ],
      ),
    );
  }
}
