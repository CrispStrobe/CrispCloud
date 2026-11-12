import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../l10n/commander_strings.dart';
import '../l10n/command_entry_strings.dart';
import '../models/command_entry.dart';
import '../models/panel_side.dart';
import '../providers/custom_command_provider.dart';
import '../providers/panel_provider.dart';
import '../services/custom_toolbar_command_service.dart';

String _t(
  BuildContext context,
  String text, [
  List<Object?> arguments = const [],
]) => CommanderStrings.translate(context, text, arguments);

Future<void> showCustomCommandsDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
) => showDialog<void>(
  context: context,
  builder: (_) => CustomCommandsDialog(side: side),
);

CommandInvocationContext captureCommandContext(WidgetRef ref, PanelSide side) {
  final panel = ref.read(panelProvider(side));
  final files = panel.selection.isNotEmpty
      ? panel.selection.toList()
      : [if (panel.cursorItem case final item? when item.name != '..') item];
  final origin = files.isEmpty
      ? panel.captureCurrentOrigin()
      : panel.captureOperationOrigin(files);
  PanelFileOrigin? target;
  try {
    final other = ref
        .read(
          panelProvider(
            side == PanelSide.local ? PanelSide.remote : PanelSide.local,
          ),
        )
        .captureCurrentOrigin();
    if (other.storageReference.isLocal) target = other;
  } on StateError {
    /* The target is optional unless {TARGET} is used. */
  }
  return CommandInvocationContext(
    storage: origin.storageReference,
    currentPath: origin.source.currentPath,
    selectedPaths: files
        .map(
          (file) => file.path ?? p.join(origin.source.currentPath, file.name),
        )
        .toList(),
    isCurrent: () => origin.isCurrent,
    targetPath: target?.source.currentPath,
    targetIsCurrent: target == null ? null : () => target!.isCurrent,
  );
}

Future<void> showCustomCommandRunDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  CustomToolbarCommand command,
) async {
  try {
    final captured = captureCommandContext(ref, side);
    final service = ref.read(customToolbarCommandServiceProvider);
    final prepared = service.prepare(command, captured);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CommandRunDialog(
        command: command,
        captured: captured,
        prepared: prepared,
        service: service,
      ),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t(context, 'Command failed: {0}', [error]))),
      );
    }
  }
}

class CustomCommandsDialog extends ConsumerWidget {
  const CustomCommandsDialog({super.key, required this.side});
  final PanelSide side;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(customToolbarCommandServiceProvider);
    final commands = service.commands;
    Future<void> edit([CustomToolbarCommand? command]) async {
      final updated = await showDialog<CustomToolbarCommand>(
        context: context,
        builder: (_) => CustomCommandEditor(command: command),
      );
      if (updated == null) return;
      try {
        if (command == null) {
          await service.addCommand(updated);
        } else {
          await service.updateCommand(updated);
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$error')));
        }
      }
    }

    return AlertDialog(
      title: Text(_t(context, 'Custom commands')),
      content: SizedBox(
        width: 680,
        height: math.min(440, MediaQuery.sizeOf(context).height * .4),
        child: ReorderableListView.builder(
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_t(context, 'Commands use verified local files.')),
              if (service.loadError != null)
                SelectableText(
                  service.loadError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (commands.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(_t(context, 'No custom commands.')),
                ),
            ],
          ),
          itemCount: commands.length,
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) =>
              service.reorderCommands(from, to > from ? to + 1 : to),
          itemBuilder: (context, index) {
            final command = commands[index];
            return ListTile(
              key: ValueKey(command.id),
              leading: ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle),
              ),
              title: Text(
                command.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                command.requiresReview
                    ? _t(context, 'Legacy shell command')
                    : command.executable,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => edit(command),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _t(context, 'Run'),
                    icon: const Icon(Icons.play_arrow),
                    onPressed: command.requiresReview
                        ? null
                        : () => showCustomCommandRunDialog(
                            context,
                            ref,
                            side,
                            command,
                          ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: _t(context, 'More options'),
                    onSelected: (value) async {
                      if (value == 'up') {
                        await service.reorderCommands(index, index - 1);
                      }
                      if (value == 'down') {
                        await service.reorderCommands(index, index + 2);
                      }
                      if (value == 'remove') {
                        await service.removeCommand(command.id);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'up',
                        enabled: index > 0,
                        child: Text(_t(context, 'Move up')),
                      ),
                      PopupMenuItem(
                        value: 'down',
                        enabled: index + 1 < commands.length,
                        child: Text(_t(context, 'Move down')),
                      ),
                      PopupMenuItem(
                        value: 'remove',
                        child: Text(_t(context, 'Delete')),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        PopupMenuButton<String>(
          tooltip: _t(context, 'More options'),
          onSelected: (value) async {
            if (value == 'import') {
              await _importCommands(context, service);
            } else {
              await Clipboard.setData(
                ClipboardData(text: service.exportConfiguration()),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_t(context, 'Copied to clipboard'))),
                );
              }
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'import',
              child: Text(_t(context, 'Import configuration')),
            ),
            PopupMenuItem(
              value: 'export',
              child: Text(_t(context, 'Export configuration')),
            ),
          ],
        ),
        TextButton(
          onPressed: () => edit(),
          child: Text(_t(context, 'Add command')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_t(context, 'Close')),
        ),
      ],
    );
  }
}

Future<void> _importCommands(
  BuildContext context,
  CustomToolbarCommandService service,
) async {
  final controller = TextEditingController();
  String? error;
  List<CustomToolbarCommand>? reviewed;
  try {
    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(_t(context, 'Import configuration')),
          scrollable: true,
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 10,
                  decoration: const InputDecoration(labelText: 'JSON'),
                  onChanged: (_) => setState(() {
                    reviewed = null;
                    error = null;
                  }),
                ),
                if (reviewed != null)
                  for (final command in reviewed!)
                    ListTile(
                      title: Text(command.label),
                      subtitle: Text(
                        command.executable.isEmpty
                            ? command.command
                            : command.executable,
                      ),
                    ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_t(context, 'Cancel')),
            ),
            TextButton(
              onPressed: () {
                try {
                  setState(() {
                    reviewed = CustomToolbarCommandService.parseConfiguration(
                      controller.text,
                    );
                    error = null;
                  });
                } catch (failure) {
                  setState(() => error = '$failure');
                }
              },
              child: Text(_t(context, 'Preview')),
            ),
            FilledButton(
              onPressed: reviewed == null
                  ? null
                  : () async {
                      try {
                        await service.importConfiguration(controller.text);
                        if (context.mounted) Navigator.pop(context);
                      } catch (failure) {
                        if (context.mounted) setState(() => error = '$failure');
                      }
                    },
              child: Text(_t(context, 'Import')),
            ),
          ],
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}

class CustomCommandEditor extends StatefulWidget {
  const CustomCommandEditor({super.key, this.command});
  final CustomToolbarCommand? command;
  @override
  State<CustomCommandEditor> createState() => _CustomCommandEditorState();
}

class _CustomCommandEditorState extends State<CustomCommandEditor> {
  late final _label = TextEditingController(text: widget.command?.label);
  late final _executable = TextEditingController(
    text: widget.command?.executable,
  );
  late final _arguments = TextEditingController(
    text: widget.command?.arguments.join('\n'),
  );
  late final _directory = TextEditingController(
    text: widget.command?.workingDir,
  );
  late final _timeout = TextEditingController(
    text: '${widget.command?.timeoutSeconds ?? 300}',
  );
  late bool _current = widget.command?.useCurrentPanelPath ?? true;
  String? _error;
  @override
  void dispose() {
    for (final controller in [
      _label,
      _executable,
      _arguments,
      _directory,
      _timeout,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    try {
      final command = CustomToolbarCommand(
        id: widget.command?.id ?? const Uuid().v4(),
        label: _label.text.trim(),
        executable: _executable.text.trim(),
        arguments: _arguments.text.isEmpty ? [] : _arguments.text.split('\n'),
        useCurrentPanelPath: _current,
        workingDir: _directory.text.trim(),
        timeoutSeconds: int.parse(_timeout.text),
      );
      command.validate();
      if (!_current && !p.isAbsolute(command.workingDir!)) {
        throw const FormatException('Choose an absolute working directory.');
      }
      Navigator.pop(context, command);
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _t(context, widget.command == null ? 'Add command' : 'Edit command'),
    ),
    scrollable: true,
    content: SizedBox(
      width: 620,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.command?.requiresReview == true) ...[
            Text(
              _t(
                context,
                'Review and convert this saved shell command before running it.',
              ),
            ),
            SelectableText(widget.command!.command),
          ],
          TextField(
            controller: _label,
            autofocus: true,
            decoration: InputDecoration(labelText: _t(context, 'Name')),
          ),
          TextField(
            controller: _executable,
            decoration: InputDecoration(labelText: _t(context, 'Executable')),
          ),
          TextField(
            controller: _arguments,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(
              labelText: _t(context, 'Arguments (one per line)'),
            ),
          ),
          Text(
            _t(
              context,
              '{SELECTED} expands to separate file arguments. {FILE}, {NAME}, {BASENAME}, {EXT}, {CURRENT} and {TARGET} are also available.',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_t(context, 'Use current folder')),
            value: _current,
            onChanged: (value) => setState(() => _current = value),
          ),
          if (!_current)
            TextField(
              controller: _directory,
              decoration: InputDecoration(
                labelText: _t(context, 'Working directory'),
              ),
            ),
          TextField(
            controller: _timeout,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _t(context, 'Timeout (seconds)'),
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_t(context, 'Cancel')),
      ),
      FilledButton(onPressed: _save, child: Text(_t(context, 'Save'))),
    ],
  );
}

class CommandRunDialog extends StatefulWidget {
  const CommandRunDialog({
    super.key,
    required this.command,
    required this.captured,
    required this.prepared,
    required this.service,
    this.reviewedStart,
    this.errorText,
  });
  final CustomToolbarCommand command;
  final CommandInvocationContext captured;
  final PreparedToolbarCommand prepared;
  final CustomToolbarCommandService service;

  /// Optional source-bound preparation with literal argv. The callback must
  /// check the supplied review lifetime around every await before launching.
  final Future<RunningToolbarCommand> Function(bool Function() isReviewCurrent)?
  reviewedStart;
  final String Function(Object error)? errorText;
  @override
  State<CommandRunDialog> createState() => _CommandRunDialogState();
}

class _CommandRunDialogState extends State<CommandRunDialog> {
  RunningToolbarCommand? _run;
  CommandExecutionResult? _result;
  String? _error;
  bool _starting = false;
  int _startGeneration = 0;
  Future<void> _start() async {
    if (_starting || _run != null || _error != null) return;
    final generation = ++_startGeneration;
    bool isReviewCurrent() =>
        mounted &&
        generation == _startGeneration &&
        _starting &&
        ModalRoute.of(context)?.isCurrent != false;
    setState(() => _starting = true);
    try {
      if (widget.reviewedStart == null) {
        final now = widget.service.prepare(widget.command, widget.captured);
        if (now.executable != widget.prepared.executable ||
            now.workingDirectory != widget.prepared.workingDirectory ||
            !listEquals(now.arguments, widget.prepared.arguments)) {
          throw const CommandEntryException(CommandEntryFailure.changed);
        }
      }
      final run =
          await (widget.reviewedStart?.call(isReviewCurrent) ??
              widget.service.start(widget.command, widget.captured));
      if (!isReviewCurrent()) {
        run.dispose();
        if (mounted && generation == _startGeneration) {
          setState(() {
            _starting = false;
            _error = CommandEntryStrings(context).text('changed');
          });
        }
        return;
      }
      _run = run;
      run.addListener(_refresh);
      setState(() => _starting = false);
      final result = await run.completed;
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted && generation == _startGeneration) {
        setState(() {
          _error =
              widget.errorText?.call(error) ??
              (error is CommandEntryException
                  ? CommandEntryStrings(context).failure(error)
                  : '$error');
          _starting = false;
        });
      }
    }
  }

  void _cancelStart() {
    _startGeneration++;
    setState(() {
      _starting = false;
      _error = _t(context, 'Cancelled');
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _startGeneration++;
    _run?.removeListener(_refresh);
    _run?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = _starting || (_run?.isRunning ?? false);
    return PopScope(
      canPop: !running,
      child: AlertDialog(
        title: Text(
          '${_t(context, 'Command output')} · ${widget.command.label}',
        ),
        content: SizedBox(
          width: 680,
          height: math.min(440, MediaQuery.sizeOf(context).height * .55),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  widget.prepared.executable,
                  textDirection: TextDirection.ltr,
                ),
                for (final argument in widget.prepared.arguments)
                  SelectableText(argument, textDirection: TextDirection.ltr),
                const SizedBox(height: 12),
                Text(_t(context, 'Working directory')),
                SelectableText(
                  widget.prepared.workingDirectory,
                  textDirection: TextDirection.ltr,
                ),
                Text(
                  '${_t(context, 'Timeout (seconds)')}: ${widget.command.timeoutSeconds}',
                ),
                const Divider(),
                SelectableText(
                  _run?.output ?? '',
                  textDirection: TextDirection.ltr,
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_result != null)
                  Text(
                    _result!.timedOut
                        ? _t(context, 'Timed out')
                        : _result!.cancelled
                        ? _t(context, 'Cancelled')
                        : _t(context, 'Exit code: {0}', [_result!.exitCode]),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (_run == null && !_starting && _error == null)
            FilledButton(onPressed: _start, child: Text(_t(context, 'Run'))),
          if (running)
            TextButton(
              onPressed: _run?.cancel ?? _cancelStart,
              child: Text(_t(context, 'Cancel')),
            ),
          TextButton(
            onPressed: running ? null : () => Navigator.pop(context),
            child: Text(_t(context, 'Close')),
          ),
        ],
      ),
    );
  }
}
