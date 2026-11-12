import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../l10n/command_entry_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/custom_command_provider.dart';
import '../providers/providers.dart';
import '../services/command_entry_service.dart';
import '../services/custom_toolbar_command_service.dart';
import '../services/keyboard_shortcut_service.dart';
import 'custom_command_dialog.dart';

final commandEntryServiceProvider = Provider<CommandEntryService>(
  (ref) => CommandEntryService(
    processStarter: ref
        .read(customToolbarCommandServiceProvider)
        .processStarter,
  ),
);

bool commandEntryAvailable(WidgetRef ref) {
  if (ref.read(commandEntryServiceProvider).platform == null) return false;
  try {
    final panel = ref.read(panelProvider(ref.read(activePanelProvider)));
    return !panel.isInArchive &&
        !panel.showingSearchResults &&
        !panel.isFlatView &&
        panel.captureCurrentOrigin().storageReference.isLocal;
  } on StateError {
    return false;
  }
}

/// Capture the actual source and immutable row values before opening a dialog
/// or awaiting preferences, access probes, PATH lookup, or file inspection.
CommandEntryContext captureCommandEntryContext(WidgetRef ref) {
  final side = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(side));
  if (panel.isInArchive || panel.showingSearchResults || panel.isFlatView) {
    throw const CommandEntryException(CommandEntryFailure.localRequired);
  }
  final origin = panel.captureCurrentOrigin();
  if (!origin.storageReference.isLocal) {
    throw const CommandEntryException(CommandEntryFailure.localRequired);
  }
  List<FileItem> selected() => panel.selection.isNotEmpty
      ? panel.selection.toList(growable: false)
      : [if (panel.cursorItem case final item? when item.name != '..') item];
  final files = List<FileItem>.unmodifiable(selected());
  final selectionOrigin = files.isEmpty
      ? origin
      : panel.captureOperationOrigin(files);
  if (selectionOrigin.storageReference != origin.storageReference) {
    throw const CommandEntryException(CommandEntryFailure.localRequired);
  }
  final session = panel.captureOperationSession();
  final tab = panel.activeTabId;
  final revision = panel.navigationIntentRevision;
  final path = origin.source.currentPath;
  final local = ref.read(localFileServiceProvider);
  var current = true;
  bool stillCurrent() {
    if (!current) return false;
    final now = selected();
    current =
        ref.context.mounted &&
        ref.read(activePanelProvider) == side &&
        session() &&
        origin.isCurrent &&
        selectionOrigin.isCurrent &&
        panel.activeTabId == tab &&
        panel.navigationIntentRevision == revision &&
        panel.currentPath == path &&
        panel.hasVerifiedDirectoryListing &&
        !panel.isLoading &&
        now.length == files.length &&
        now.every((row) => files.any((original) => identical(original, row)));
    return current;
  }

  String? targetPath;
  bool Function()? targetCurrent;
  try {
    final target = ref.read(
      panelProvider(
        side == PanelSide.local ? PanelSide.remote : PanelSide.local,
      ),
    );
    final targetOrigin = target.captureCurrentOrigin();
    if (targetOrigin.storageReference.isLocal &&
        !target.showingSearchResults &&
        !target.isFlatView) {
      targetPath = targetOrigin.source.currentPath;
      final targetSession = target.captureOperationSession();
      final targetNavigation = target.navigationIntentRevision;
      targetCurrent = () =>
          targetSession() &&
          targetOrigin.isCurrent &&
          target.navigationIntentRevision == targetNavigation &&
          target.currentPath == targetPath &&
          target.hasVerifiedDirectoryListing &&
          !target.isLoading;
    }
  } on StateError {
    // The opposite pane is required only by a saved {TARGET} argument.
  }
  final selection = [
    for (final file in files)
      CommandEntrySelection(
        path: file.path ?? p.join(path, file.name),
        name: file.name,
        isDirectory: file.isFolder,
        size: file.size,
        modified: file.updatedAt,
      ),
  ];
  void changed() => stillCurrent();
  panel.addListener(changed);
  final activeSubscription = ref.listenManual<PanelSide>(activePanelProvider, (
    _,
    active,
  ) {
    if (active != side) current = false;
  });
  return CommandEntryContext(
    invocation: CommandInvocationContext(
      storage: origin.storageReference,
      currentPath: path,
      selectedPaths: selection.map((row) => row.path).toList(),
      isCurrent: stillCurrent,
      targetPath: targetPath,
      targetIsCurrent: targetCurrent,
    ),
    selection: selection,
    hasExistingAccess: local.hasAccessToPath,
    onDispose: () {
      current = false;
      activeSubscription.close();
      panel.removeListener(changed);
    },
  );
}

Future<void> showCommandEntryDialog(BuildContext context, WidgetRef ref) async {
  CommandEntryContext? captured;
  try {
    captured = captureCommandEntryContext(ref);
  } catch (_) {
    // The unavailable reason is visible; no remote path becomes a local path.
  }
  try {
    await showDialog<void>(
      context: context,
      builder: (_) => CommandEntryDialog(
        captured: captured,
        service: ref.read(commandEntryServiceProvider),
        commands: ref.read(customToolbarCommandServiceProvider),
        shortcuts: ref.read(keyboardShortcutServiceProvider),
      ),
    );
  } finally {
    captured?.dispose();
  }
}

class CommandEntryDialog extends StatefulWidget {
  const CommandEntryDialog({
    super.key,
    this.captured,
    required this.service,
    required this.commands,
    required this.shortcuts,
  });
  final CommandEntryContext? captured;
  final CommandEntryService service;
  final CustomToolbarCommandService commands;
  final KeyboardShortcutService shortcuts;

  @override
  State<CommandEntryDialog> createState() => _CommandEntryDialogState();
}

class _CommandEntryDialogState extends State<CommandEntryDialog> {
  final _program = TextEditingController();
  final _arguments = TextEditingController();
  late final _argumentFocus = FocusNode(onKeyEvent: _onKey);
  late final _programFocus = FocusNode(onKeyEvent: _onKey);
  String? _savedId;
  String _typedProgram = '';
  int _revision = 0;
  bool _busy = false, _reviewing = false, _closing = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.commands.addListener(_commandsChanged);
    unawaited(
      widget.commands.load().catchError((Object error) {
        if (mounted) {
          setState(
            () => _error = const CommandEntryException(
              CommandEntryFailure.savedUnavailable,
            ),
          );
        }
      }),
    );
  }

  void _commandsChanged() {
    if (mounted) setState(() {});
  }

  void _changed([String? value]) => setState(() {
    _revision++;
    _error = null;
  });

  void _insert(bool fullPaths) {
    final captured = widget.captured;
    if (_busy || captured == null || captured.selection.isEmpty) return;
    try {
      if (captured.isDisposed || !captured.invocation.isCurrent()) {
        throw const CommandEntryException(CommandEntryFailure.changed);
      }
      _arguments.value = insertCommandEntryArguments(
        _arguments.value,
        captured.selection.map((row) => fullPaths ? row.path : row.name),
      );
      _changed();
      _argumentFocus.requestFocus();
    } catch (error) {
      setState(() => _error = error);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    final action = widget.shortcuts.resolveCommandEntry(
      event,
      isCtrl: keyboard.isControlPressed,
      isMeta: keyboard.isMetaPressed,
      isShift: keyboard.isShiftPressed,
      isAlt: keyboard.isAltPressed,
    );
    if (action != null) {
      if (event is KeyDownEvent) {
        _insert(action == ShortcutAction.insertCommandPath);
      }
      return KeyEventResult.handled;
    }
    return widget.shortcuts.suppressesCommandEntryDefault(
          event,
          isCtrl: keyboard.isControlPressed,
          isMeta: keyboard.isMetaPressed,
          isShift: keyboard.isShiftPressed,
          isAlt: keyboard.isAltPressed,
        )
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  Future<void> _review() async {
    final captured = widget.captured;
    if (_busy || captured == null) return;
    final revision = _revision;
    final programText = _program.text;
    final argumentText = _arguments.text;
    final savedId = _savedId;
    final saved = widget.commands.commands
        .where((command) => command.id == _savedId)
        .firstOrNull;
    if (_savedId != null && saved == null) {
      setState(
        () => _error = const CommandEntryException(
          CommandEntryFailure.savedUnavailable,
        ),
      );
      return;
    }
    final definition = saved == null ? null : jsonEncode(saved.toJson());
    bool draftCurrent() =>
        mounted &&
        !_closing &&
        revision == _revision &&
        programText == _program.text &&
        argumentText == _arguments.text &&
        savedId == _savedId &&
        (saved == null ||
            widget.commands.commands.any(
              (command) =>
                  command.id == saved.id &&
                  jsonEncode(command.toJson()) == definition,
            ));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final prepared = await widget.service.prepare(
        CommandEntryDraft(
          program: programText,
          arguments: argumentText,
          savedCommand: saved,
        ),
        captured,
        isDraftCurrent: draftCurrent,
      );
      if (!mounted || !draftCurrent()) return;
      setState(() => _reviewing = true);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => CommandRunDialog(
          command: prepared.command,
          captured: captured.invocation,
          prepared: prepared.prepared,
          service: widget.commands,
          reviewedStart: (isReviewCurrent) =>
              widget.service.start(prepared, isReviewCurrent: isReviewCurrent),
          errorText: CommandEntryStrings(context).failure,
        ),
      );
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

  @override
  void dispose() {
    _closing = true;
    widget.commands.removeListener(_commandsChanged);
    widget.captured?.dispose();
    _program.dispose();
    _arguments.dispose();
    _argumentFocus.dispose();
    _programFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = CommandEntryStrings(context);
    final l = AppLocalizations.of(context)!;
    final captured = widget.captured;
    final commands = widget.commands.commands;
    final available = widget.service.platform != null && captured != null;
    final canInsert = available && captured.selection.isNotEmpty && !_busy;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _closing = true;
      },
      child: Focus(
        onKeyEvent: _onKey,
        child: AlertDialog(
          title: Text(s.text('title')),
          scrollable: true,
          content: SizedBox(
            width: 640,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!available)
                  Text(
                    s.text(
                      widget.service.platform == null
                          ? 'unsupported'
                          : 'localRequired',
                    ),
                  ),
                if (captured != null) ...[
                  Text(s.text('capturedFolder')),
                  SelectableText(
                    captured.invocation.currentPath,
                    textDirection: TextDirection.ltr,
                  ),
                  Text(
                    s.text('selectedCount', {
                      'count': captured.selection.length,
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<String>(
                  key: const ValueKey('command-entry-program-choice'),
                  initialValue:
                      commands.any((command) => command.id == _savedId)
                      ? _savedId
                      : '',
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: s.text('savedProgram'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(s.text('typedProgram')),
                    ),
                    for (final command in commands)
                      DropdownMenuItem(
                        value: command.id,
                        enabled: !command.requiresReview,
                        child: Text(
                          command.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (id) {
                          if (_savedId == null) _typedProgram = _program.text;
                          _savedId = id == '' ? null : id;
                          _program.text = _savedId == null
                              ? _typedProgram
                              : commands
                                    .firstWhere(
                                      (command) => command.id == _savedId,
                                    )
                                    .executable;
                          _changed();
                        },
                ),
                TextField(
                  key: const ValueKey('command-entry-executable'),
                  controller: _program,
                  focusNode: _programFocus,
                  readOnly: _savedId != null,
                  enabled: !_busy,
                  autofocus: true,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: s.text('executable')),
                  onChanged: _changed,
                ),
                if (_savedId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(s.text('savedHelp')),
                  ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('command-entry-arguments'),
                  controller: _arguments,
                  focusNode: _argumentFocus,
                  enabled: !_busy,
                  minLines: 2,
                  maxLines: 5,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: s.text('arguments')),
                  onChanged: _changed,
                ),
                const SizedBox(height: 8),
                Text(s.text('argumentHelp')),
                const SizedBox(height: 12),
                for (final action in commandEntryShortcutActions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: ValueKey('command-entry-${action.name}'),
                        onPressed: canInsert
                            ? () => _insert(
                                action == ShortcutAction.insertCommandPath,
                              )
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            children: [
                              Text(
                                s.text(
                                  action == ShortcutAction.insertCommandPath
                                      ? 'insertPaths'
                                      : 'insertNames',
                                ),
                                textAlign: TextAlign.center,
                              ),
                              Text(
                                widget.shortcuts.browserDisplay(action),
                                textDirection: TextDirection.ltr,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Text(
                  s.text(
                    captured?.selection.isNotEmpty == true
                        ? 'insertionHelp'
                        : 'noSelection',
                  ),
                ),
                if (_busy && !_reviewing) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  Text(s.text('preparing')),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        s.failure(_error!),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _closing = true;
                Navigator.pop(context);
              },
              child: Text(l.close),
            ),
            FilledButton(
              key: const ValueKey('command-entry-review'),
              onPressed: available && !_busy ? _review : null,
              child: Text(s.text('review')),
            ),
          ],
        ),
      ),
    );
  }
}
