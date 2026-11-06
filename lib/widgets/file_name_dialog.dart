import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/commander_strings.dart';
import '../models/file_item.dart';
import '../providers/panel_provider.dart';

/// A prompt stays open while its captured operation runs, and only returns a
/// name after success. Enter and the action button share the same guarded path.
class FileNameDialog extends StatefulWidget {
  const FileNameDialog({
    super.key,
    required this.title,
    required this.label,
    required this.confirmLabel,
    required this.submit,
    this.initialName = '',
    this.selectStem = false,
    this.target,
    this.cancel,
  });
  final String title, label, confirmLabel, initialName;
  final String? target;
  final bool selectStem;
  final Future<void> Function(String name) submit;
  final VoidCallback? cancel;

  @override
  State<FileNameDialog> createState() => _FileNameDialogState();
}

class _FileNameDialogState extends State<FileNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  bool _busy = false;
  bool _cancelRequested = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final dot = widget.initialName.lastIndexOf('.');
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.selectStem && dot > 0
          ? dot
          : widget.initialName.length,
    );
  }

  @override
  void dispose() {
    if (_busy) widget.cancel?.call();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text;
    if (_busy || name.isEmpty) return;
    setState(() {
      _busy = true;
      _cancelRequested = false;
      _error = null;
    });
    try {
      await widget.submit(name);
      if (mounted) Navigator.pop(context, name);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.target != null) ...[
              Text(context.commanderTr('Target: {0}', [widget.target!])),
              const SizedBox(height: 12),
            ],
            TextField(
              key: const ValueKey('file-name-input'),
              controller: _controller,
              enabled: !_busy,
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.label,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_busy && widget.cancel != null)
          TextButton(
            onPressed: _cancelRequested
                ? null
                : () {
                    setState(() => _cancelRequested = true);
                    widget.cancel!();
                  },
            child: Text(context.commanderTr('Cancel operation')),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        FilledButton(
          key: const ValueKey('file-name-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    ),
  );
}

Future<String?> showCapturedRenameDialog(
  BuildContext context,
  PanelNotifier panel,
  FileItem file,
) async {
  late final PanelFileOrigin origin;
  try {
    origin = panel.captureOperationOrigin([file]);
  } catch (error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$error')));
    return null;
  }
  final strings = AppLocalizations.of(context)!;
  var cancelled = false;
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => FileNameDialog(
      title: strings.rename,
      label: strings.newName,
      confirmLabel: strings.rename,
      initialName: file.name,
      selectStem: !file.isFolder,
      target: '${origin.source.displayName}: ${file.path ?? file.name}',
      submit: (name) {
        cancelled = false;
        return panel.renameFile(
          file,
          name,
          operationOrigin: origin,
          rethrowErrors: true,
          isCancelled: () => cancelled,
        );
      },
      cancel: () => cancelled = true,
    ),
  );
}

Future<String?> showCapturedCreateFolderDialog(
  BuildContext context,
  PanelNotifier panel,
) async {
  late final PanelFileOrigin origin;
  try {
    origin = panel.captureCurrentOrigin();
  } catch (error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$error')));
    return null;
  }
  final strings = AppLocalizations.of(context)!;
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => FileNameDialog(
      title: strings.newFolder,
      label: strings.folderName,
      confirmLabel: strings.create,
      target: '${origin.source.displayName}: ${origin.source.currentPath}',
      submit: (name) => panel.createFolder(
        name,
        operationOrigin: origin,
        rethrowErrors: true,
      ),
    ),
  );
}
