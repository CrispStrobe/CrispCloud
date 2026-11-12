import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/external_terminal_strings.dart';
import '../providers/providers.dart';
import '../services/external_terminal_service.dart';

final externalTerminalServiceProvider = Provider<ExternalTerminalService>(
  (_) => const ExternalTerminalService(),
);

Future<void> showExternalTerminalDialog(BuildContext context, WidgetRef ref) {
  final service = ref.read(externalTerminalServiceProvider);
  ExternalTerminalDirectory? directory;
  try {
    final side = ref.read(activePanelProvider);
    final panel = ref.read(panelProvider(side));
    final origin = panel.captureCurrentOrigin();
    if (!origin.source.isLocal ||
        panel.isInArchive ||
        panel.showingSearchResults ||
        panel.isFlatView) {
      throw const ExternalTerminalException(
        ExternalTerminalFailure.localFolderRequired,
      );
    }
    final session = panel.captureOperationSession();
    final tab = panel.activeTabId;
    final revision = panel.navigationIntentRevision;
    final local = ref.read(localFileServiceProvider);
    final path = origin.source.currentPath;
    directory = ExternalTerminalDirectory(
      path: path,
      isCurrent: () =>
          context.mounted &&
          ref.read(activePanelProvider) == side &&
          session() &&
          origin.isCurrent &&
          panel.activeTabId == tab &&
          panel.navigationIntentRevision == revision &&
          panel.currentPath == path &&
          panel.hasVerifiedDirectoryListing &&
          !panel.isLoading,
      hasExistingAccess: () => local.hasAccessToPath(path),
    );
  } catch (_) {
    // Preferences remain editable when there is no usable local launch target.
  }
  return showDialog<void>(
    context: context,
    builder: (_) =>
        ExternalTerminalDialog(service: service, directory: directory),
  );
}

class ExternalTerminalDialog extends StatefulWidget {
  const ExternalTerminalDialog({
    super.key,
    required this.service,
    this.directory,
  });
  final ExternalTerminalService service;
  final ExternalTerminalDirectory? directory;
  @override
  State<ExternalTerminalDialog> createState() => _ExternalTerminalDialogState();
}

class _ExternalTerminalDialogState extends State<ExternalTerminalDialog> {
  final _executable = TextEditingController();
  final _arguments = TextEditingController();
  late final ExternalTerminalStore _store;
  bool _loading = true, _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _store = ExternalTerminalStore(widget.service.platform ?? 'unsupported');
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await _store.load();
      if (!mounted) return;
      _executable.text = value?.executable ?? '';
      _arguments.text = value?.arguments.join('\n') ?? '';
    } catch (error) {
      if (mounted) _error = error;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  ExternalTerminalConfiguration _configuration() =>
      ExternalTerminalConfiguration(
        platform: widget.service.platform!,
        executable: _executable.text,
        arguments: _arguments.text.isEmpty
            ? const []
            : _arguments.text.replaceAll('\r\n', '\n').split('\n'),
      );

  Future<void> _save({bool open = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = _configuration();
      // Launch rechecks the captured location after preference persistence.
      await _store.save(value);
      if (!mounted) return;
      if (open) {
        final original = widget.directory;
        if (original == null) {
          throw const ExternalTerminalException(
            ExternalTerminalFailure.localFolderRequired,
          );
        }
        await widget.service.launch(
          value,
          ExternalTerminalDirectory(
            path: original.path,
            isCurrent: () => mounted && original.isCurrent(),
            hasExistingAccess: original.hasExistingAccess,
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _store.reset();
      if (!mounted) return;
      _executable.clear();
      _arguments.clear();
    } catch (_) {
      if (mounted) {
        _error = const ExternalTerminalException(
          ExternalTerminalFailure.saveFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _executable.dispose();
    _arguments.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ExternalTerminalStrings(context);
    final supported = widget.service.platform != null;
    final directory = widget.directory;
    final editable = supported && !_loading && !_busy;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(strings.text('title')),
        scrollable: true,
        content: SizedBox(
          width: 580,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (!supported) Text(strings.text('unsupported')),
              Text(strings.text('review')),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('external-terminal-executable'),
                controller: _executable,
                enabled: editable,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: strings.text('executable'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('external-terminal-arguments'),
                controller: _arguments,
                enabled: editable,
                autocorrect: false,
                minLines: 2,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: strings.text('arguments'),
                ),
              ),
              const SizedBox(height: 8),
              Text(strings.text('help')),
              const SizedBox(height: 16),
              Text(
                strings.text('folder'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              if (directory == null)
                Text(strings.text('localFolderRequired'))
              else
                SelectableText(
                  directory.path,
                  key: const ValueKey('external-terminal-directory'),
                ),
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Text(
                  strings.failure(error),
                  key: const ValueKey('external-terminal-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: editable ? _reset : null,
            child: Text(strings.text('reset')),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: editable ? () => _save() : null,
            child: Text(strings.text('save')),
          ),
          FilledButton(
            onPressed: editable && directory != null
                ? () => _save(open: true)
                : null,
            child: Text(strings.text('saveOpen')),
          ),
        ],
      ),
    );
  }
}
