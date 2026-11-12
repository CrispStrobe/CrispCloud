import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/external_editing_strings.dart';
import '../services/command_entry_service.dart';
import '../services/external_edit_copy_export.dart';
import '../services/external_editor_service.dart';
import '../services/external_remote_editing_service.dart';

export '../services/external_remote_editing_service.dart'
    show ExternalEditSource, ExternalEditSession, ExternalRemoteEditingService;

typedef ExternalEditExport = Future<bool> Function(
  ExternalEditSession session,
  String title,
);

/// The host supplies a source captured before opening its menu or awaiting
/// navigation. Closing this dialog retains application-owned editing sessions.
Future<void> showExternalEditingDialog(
  BuildContext context, {
  required ExternalRemoteEditingService service,
  ExternalEditSource? source,
  ExternalEditorLauncher? launcher,
  ExternalEditorStore? preferences,
  ExternalEditExport? exportCopy,
  Object? initialError,
}) => showDialog<void>(
  context: context,
  builder: (_) => ExternalEditingDialog(
    service: service,
    source: source,
    launcher: launcher,
    preferences: preferences,
    exportCopy: exportCopy,
    initialError: initialError,
  ),
);

class ExternalEditingDialog extends StatefulWidget {
  const ExternalEditingDialog({
    super.key,
    required this.service,
    this.source,
    this.launcher,
    this.preferences,
    this.exportCopy,
    this.initialError,
  });
  final ExternalRemoteEditingService service;
  final ExternalEditSource? source;
  final ExternalEditorLauncher? launcher;
  final ExternalEditorStore? preferences;
  final ExternalEditExport? exportCopy;
  final Object? initialError;
  @override
  State<ExternalEditingDialog> createState() => _ExternalEditingDialogState();
}

class _ExternalEditingDialogState extends State<ExternalEditingDialog> {
  final _executable = TextEditingController();
  final _arguments = TextEditingController(text: '{file}');
  late final ExternalEditorLauncher _launcher;
  late final ExternalEditorStore _preferences;
  bool _loaded = false, _busy = false, _reviewing = false, _closing = false;
  int _revision = 0;
  Object? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _launcher = widget.launcher ?? const ExternalEditorLauncher();
    _preferences =
        widget.preferences ??
        ExternalEditorStore(_launcher.platform ?? 'unsupported');
    _error = widget.initialError;
    widget.service.addListener(_refresh);
    unawaited(_load());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      if (_launcher.platform != null) {
        try {
          final saved = await _preferences.load();
          if (!mounted) return;
          _executable.text = saved?.executable ?? '';
          _arguments.text =
              saved?.arguments.map(encodeCommandEntryArgument).join(' ') ??
              '{file}';
        } catch (error) {
          if (mounted) _error = error;
        }
        // Preference corruption must not hide retained edits or their export
        // and cleanup actions.
        await widget.service.restore();
      }
    } catch (error) {
      if (mounted) _error = error;
    } finally {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _changed(String _) => setState(() {
    _revision++;
    _error = null;
    _notice = null;
  });

  ExternalEditorConfiguration _configuration() {
    try {
      return ExternalEditorConfiguration(
        platform: _launcher.platform ?? 'unsupported',
        executable: _executable.text.trim(),
        arguments: parseCommandEntryArguments(_arguments.text),
      );
    } catch (_) {
      throw const ExternalEditException(ExternalEditFailure.invalid);
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted && !_closing) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _reviewing = false;
        });
      }
    }
  }

  Future<void> _save() => _run(() async {
    await _preferences.save(_configuration());
    if (mounted) setState(() => _notice = 'preferenceSaved');
  });

  Future<void> _prepare() => _run(() async {
    final original = widget.source;
    if (original == null) return;
    final revision = _revision;
    final configuration = _configuration();
    final source = ExternalEditSource(
      reference: original.reference,
      file: original.file,
      client: original.client,
      isCurrent: original.isCurrent,
      isReviewCurrent: () =>
          mounted &&
          !_closing &&
          _revision == revision &&
          original.isReviewCurrent(),
    );
    final session = await widget.service.prepare(source);
    if (!mounted || _closing) return;
    if (session.record?.localSha256 == null) {
      throw ExternalEditException(
        session.record?.failure ?? ExternalEditFailure.stagingFailed,
      );
    }
    await _showLaunch(session, configuration, revision);
  });

  Future<void> _open(ExternalEditSession session) =>
      _run(() => _showLaunch(session, _configuration(), _revision));

  Future<void> _showLaunch(
    ExternalEditSession session,
    ExternalEditorConfiguration configuration,
    int revision,
  ) async {
    var reviewAlive = true;
    try {
      final prepared = await _launcher.prepare(
        session,
        configuration,
        isCurrent: () =>
            mounted && !_closing && reviewAlive && _revision == revision,
      );
      if (!mounted || _closing) return;
      setState(() => _reviewing = true);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            ExternalEditorLaunchReview(launcher: _launcher, prepared: prepared),
      );
    } finally {
      reviewAlive = false;
      if (mounted) setState(() => _reviewing = false);
    }
  }

  Future<void> _reviewConflict(ExternalEditSession session) => _run(() async {
    final review = await session.reviewConflict();
    if (!mounted || _closing) return;
    setState(() => _reviewing = true);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          ExternalEditConflictDialog(session: session, review: review),
    );
  });

  Future<void> _export(ExternalEditSession session) => _run(() async {
    final title = ExternalEditingStrings(context).text('export');
    final exported = await (widget.exportCopy ?? exportExternalEditCopy)(
      session,
      title,
    );
    if (exported && mounted) setState(() => _notice = 'exported');
  });

  Future<void> _discard(ExternalEditSession session) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) {
        var editorClosed = false;
        final s = ExternalEditingStrings(context);
        return StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(s.text('discard')),
            scrollable: true,
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.text('discardHelp')),
                  CheckboxListTile(
                    key: const ValueKey('external-editing-editor-closed'),
                    value: editorClosed,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(s.text('editorClosed')),
                    onChanged: (value) =>
                        update(() => editorClosed = value == true),
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
                key: const ValueKey('external-editing-confirm-discard'),
                onPressed: editorClosed
                    ? () => Navigator.pop(context, true)
                    : null,
                child: Text(s.text('discard')),
              ),
            ],
          ),
        );
      },
    );
    if (accepted == true && mounted && !_closing) {
      await _run(() => session.discard(editorClosed: true));
    }
  }

  bool _matches(ExternalEditSession session) {
    final source = widget.source;
    final reference = session.record?.reference;
    return source != null &&
        reference != null &&
        source.reference.storage == reference.storage &&
        source.reference.path == reference.path;
  }

  @override
  void dispose() {
    _closing = true;
    widget.service.removeListener(_refresh);
    _executable.dispose();
    _arguments.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ExternalEditingStrings(context);
    final available = _launcher.platform != null && _loaded;
    return TickerMode(
      enabled: !_reviewing,
      child: PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) _closing = true;
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
                if (_launcher.platform == null)
                  Text(s.text('failure_unsupported')),
                Text(s.text('intro')),
                const SizedBox(height: 8),
                Text(s.text('limits')),
                TextField(
                  key: const ValueKey('external-editing-executable'),
                  controller: _executable,
                  enabled: available && !_busy,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: s.text('executable')),
                  onChanged: _changed,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('external-editing-arguments'),
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
                const Divider(),
                if (widget.source case final source?) ...[
                  Text(
                    s.text('original'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  _reference(
                    source.reference.storage.provider,
                    source.reference.storage.accountKey,
                    source.reference.storage.root,
                    source.reference.path,
                  ),
                ] else
                  Text(s.text('selectOriginal')),
                if (!_loaded || _busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  Text(s.text('working')),
                ],
                if (_notice != null)
                  Semantics(liveRegion: true, child: Text(s.text(_notice!))),
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
                  AnimatedBuilder(
                    key: ValueKey('external-editing-session-${session.id}'),
                    animation: session,
                    builder: (context, _) => _session(context, session),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('external-editing-close'),
              onPressed: () {
                _closing = true;
                Navigator.pop(context);
              },
              child: Text(s.text('close')),
            ),
            TextButton(
              key: const ValueKey('external-editing-save'),
              onPressed: available && !_busy ? _save : null,
              child: Text(s.text('savePreference')),
            ),
            FilledButton(
              key: const ValueKey('external-editing-prepare'),
              onPressed: available && !_busy && widget.source != null
                  ? _prepare
                  : null,
              child: Text(s.text('prepare')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _session(BuildContext context, ExternalEditSession session) {
    final s = ExternalEditingStrings(context);
    final record = session.record;
    final enabled =
        !_busy &&
        !session.isClosed &&
        !session.isClosing &&
        record?.phase != ExternalEditPhase.uploading;
    final publishing = session.isBound && session.canPublish;
    Widget action(String key, VoidCallback? run) => TextButton(
      key: ValueKey('external-editing-$key-${session.id}'),
      onPressed: enabled ? run : null,
      child: Text(s.text(key)),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (record != null) ...[
            Text(record.name, style: Theme.of(context).textTheme.titleSmall),
            _reference(
              record.reference.storage.provider,
              record.reference.storage.accountKey,
              record.reference.storage.root,
              record.reference.path,
            ),
            Text(s.phase(record.phase)),
            if (record.savedGeneration > 0)
              Text(s.text('savedOriginal', [record.savedGeneration])),
            if (record.hasLocalChanges) Text(s.text('unsent')),
            if (record.failure case final failure?)
              Text(
                s.text('failure_${failure.name}'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (!session.isBound) Text(s.text('recovered')),
            if (record.baseline == null && record.localSha256 != null)
              Text(s.text('localOnly')),
            if (session.watching)
              Text(s.text(session.autoUpload ? 'autoActive' : 'watchingLocal')),
          ] else
            Text(s.text('failure_retainedUnavailable')),
          SelectableText(
            session.directoryPath,
            textDirection: TextDirection.ltr,
          ),
          if (record != null)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                action(
                  'launch',
                  record.localSha256 == null ? null : () => _open(session),
                ),
                action('scan', () => _run(session.scan)),
                if (session.watching)
                  action('pause', () => _run(session.pause))
                else
                  action(
                    'watchLocal',
                    record.localSha256 == null
                        ? null
                        : () => _run(() => session.watch(autoUpload: false)),
                  ),
                action(
                  'upload',
                  publishing &&
                          record.phase != ExternalEditPhase.conflict &&
                          record.phase != ExternalEditPhase.uncertain
                      ? () => _run(session.upload)
                      : null,
                ),
                action(
                  'reconcile',
                  publishing ? () => _run(session.reconcile) : null,
                ),
                if (_matches(session) ||
                    !session.isBound ||
                    record.failure == ExternalEditFailure.sourceChanged)
                  action(
                    'rebind',
                    _matches(session)
                        ? () => _run(() async {
                            await session.pause();
                            await session.rebind(widget.source!);
                          })
                        : null,
                  ),
                if (record.phase == ExternalEditPhase.conflict)
                  action(
                    'reviewConflict',
                    publishing ? () => _reviewConflict(session) : null,
                  ),
                action('export', () => _export(session)),
              ],
            ),
          action('discard', () => _discard(session)),
        ],
      ),
    );
  }
}

Widget _reference(String provider, String account, String root, String path) =>
    SelectableText(
      '$provider · $account · $root\n$path',
      textDirection: TextDirection.ltr,
    );

class ExternalEditorLaunchReview extends StatefulWidget {
  const ExternalEditorLaunchReview({
    super.key,
    required this.launcher,
    required this.prepared,
  });
  final ExternalEditorLauncher launcher;
  final PreparedExternalEditorLaunch prepared;
  @override
  State<ExternalEditorLaunchReview> createState() =>
      _ExternalEditorLaunchReviewState();
}

class _ExternalEditorLaunchReviewState
    extends State<ExternalEditorLaunchReview> {
  bool _autoUpload = false,
      _busy = false,
      _attempted = false,
      _launched = false;
  Object? _error;
  Future<void> _launch() async {
    setState(() {
      _busy = true;
      _attempted = true;
    });
    try {
      await widget.launcher.launch(widget.prepared, autoUpload: _autoUpload);
      if (mounted) setState(() => _launched = true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ExternalEditingStrings(context), prepared = widget.prepared;
    final record = prepared.session.record!;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(s.text('reviewLaunch')),
        scrollable: true,
        content: SizedBox(
          width: 660,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.text('intro')),
              Text(s.text('original')),
              _reference(
                record.reference.storage.provider,
                record.reference.storage.accountKey,
                record.reference.storage.root,
                record.reference.path,
              ),
              const Divider(),
              Text(s.text('privateCopy')),
              SelectableText(
                prepared.file.path,
                textDirection: TextDirection.ltr,
              ),
              SelectableText(
                prepared.executable,
                textDirection: TextDirection.ltr,
              ),
              for (final argument in prepared.arguments)
                SelectableText(argument, textDirection: TextDirection.ltr),
              CheckboxListTile(
                key: const ValueKey('external-editing-auto-consent'),
                value: _autoUpload,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(s.text('autoConsent')),
                onChanged: !_attempted && prepared.session.canPublish
                    ? (value) => setState(() => _autoUpload = value == true)
                    : null,
              ),
              Text(
                s.text(prepared.session.canPublish ? 'autoHelp' : 'localOnly'),
              ),
              Text(s.text('retention')),
              if (_busy) const LinearProgressIndicator(),
              if (_launched ||
                  _attempted && prepared.session.record?.launched == true)
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
          TextButton(
            key: const ValueKey('external-editing-review-close'),
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(s.text('close')),
          ),
          if (!_attempted)
            FilledButton(
              key: const ValueKey('external-editing-confirm-launch'),
              onPressed: _launch,
              child: Text(s.text('launch')),
            ),
        ],
      ),
    );
  }
}

class ExternalEditConflictDialog extends StatefulWidget {
  const ExternalEditConflictDialog({
    super.key,
    required this.session,
    required this.review,
  });
  final ExternalEditSession session;
  final ExternalEditConflictReview review;
  @override
  State<ExternalEditConflictDialog> createState() =>
      _ExternalEditConflictDialogState();
}

class _ExternalEditConflictDialogState
    extends State<ExternalEditConflictDialog> {
  bool _accepted = false, _busy = false, _attempted = false;
  Object? _error;
  Future<void> _replace() async {
    setState(() {
      _busy = true;
      _attempted = true;
    });
    try {
      await widget.session.replaceReviewed(widget.review);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ExternalEditingStrings(context);
    final record = widget.session.record!;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(s.text('reviewConflict')),
        scrollable: true,
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.text('conflictHelp')),
              _reference(
                record.reference.storage.provider,
                record.reference.storage.accountKey,
                record.reference.storage.root,
                record.reference.path,
              ),
              SelectableText(
                s.text('revision', [widget.review.remote.revision]),
                textDirection: TextDirection.ltr,
              ),
              CheckboxListTile(
                key: const ValueKey('external-editing-replace-consent'),
                value: _accepted,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(s.text('replaceConsent')),
                onChanged: _attempted
                    ? null
                    : (value) => setState(() => _accepted = value == true),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  s.failure(_error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(s.text('cancel')),
          ),
          FilledButton(
            key: const ValueKey('external-editing-confirm-replace'),
            onPressed: _accepted && !_attempted ? _replace : null,
            child: Text(s.text('replace')),
          ),
        ],
      ),
    );
  }
}
