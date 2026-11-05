import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/panel_provider.dart';
import '../services/log_service.dart';
import '../services/multi_rename_service.dart';

/// A single, reviewable plan combines masks, counters, replacement and case.
/// The storage origin is captured when the dialog opens and never re-resolved
/// from whichever account or pane happens to be selected later.
class BatchRenameDialog extends ConsumerStatefulWidget {
  const BatchRenameDialog({
    super.key,
    required this.parentRef,
    required this.side,
    required this.files,
  });

  final WidgetRef parentRef;
  final PanelSide side;
  final List<FileItem> files;

  @override
  ConsumerState<BatchRenameDialog> createState() => _BatchRenameDialogState();
}

class _BatchRenameDialogState extends ConsumerState<BatchRenameDialog> {
  static const _log = Log('MultiRenameDialog');
  static const _presetKey = 'commander.multiRenamePresets.v1';
  static const _service = MultiRenameService();

  final _name = TextEditingController(text: '[N]');
  final _extension = TextEditingController(text: '[E]');
  final _find = TextEditingController();
  final _replace = TextEditingController();
  final _start = TextEditingController(text: '1');
  final _step = TextEditingController(text: '1');
  final _width = TextEditingController(text: '3');
  late final List<FileItem> _files;
  late final PanelNotifier _panel;
  late final String _directory;
  p.Context _paths = p.posix;
  PanelFileOrigin? _origin;
  String? _originError;

  bool _useRegex = false;
  bool _caseSensitive = true;
  bool _firstMatch = false;
  bool _stopOnError = true;
  RenameReplaceScope _scope = RenameReplaceScope.fullName;
  RenameCase _nameCase = RenameCase.unchanged;
  RenameCase _extensionCase = RenameCase.unchanged;
  Map<String, MultiRenameOptions> _presets = {};
  String? _preset;
  bool _processing = false;
  bool _cancelRequested = false;
  MultiRenameProgress? _progress;
  MultiRenamePlan? _executionPlan;
  MultiRenameResult? _result;
  Map<String, String> _executionErrors = {};
  String? _message;

  @override
  void initState() {
    super.initState();
    _files = List.of(widget.files);
    _panel = ref.read(panelProvider(widget.side));
    _directory = _panel.currentPath;
    try {
      _origin = _panel.captureOperationOrigin(_files);
      if (_origin == null) {
        _originError = 'These items no longer have a verified storage source. Refresh the panel.';
      } else if (_origin!.source.isLocal && !kIsWeb) {
        _paths = p.context;
      }
    } catch (error) {
      _originError = error.toString();
    }
    _loadPresets();
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _extension,
      _find,
      _replace,
      _start,
      _step,
      _width,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _editable => !_processing && _result == null;

  MultiRenameOptions get _options => MultiRenameOptions(
    nameMask: _name.text,
    extensionMask: _extension.text,
    find: _find.text,
    replace: _replace.text,
    useRegex: _useRegex,
    caseSensitive: _caseSensitive,
    firstMatchOnly: _firstMatch,
    replaceScope: _scope,
    nameCase: _nameCase,
    extensionCase: _extensionCase,
    counterStart: int.tryParse(_start.text) ?? -1,
    counterStep: int.tryParse(_step.text) ?? 1000000000000,
    counterWidth: int.tryParse(_width.text) ?? 0,
  );

  MultiRenamePlan get _plan =>
      _executionPlan ??
      _service.preview(
        _files,
        _options,
        directory: _directory,
        pathContext: _paths,
      );

  void _changed([String? _]) {
    setState(() {
      _executionErrors = {};
      _executionPlan = null;
      _message = null;
      _preset = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final theme = Theme.of(context);
    final text = AppLocalizations.of(context);
    return PopScope(
      canPop: !_processing,
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 920,
          height: math.min(810.0, MediaQuery.sizeOf(context).height - 32),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Multi-rename (${_files.length} items)',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Combine masks, replacement and case changes. The counter follows preview order.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final half = constraints.maxWidth >= 580
                            ? (constraints.maxWidth - 12) / 2
                            : constraints.maxWidth;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _presetBar(),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                SizedBox(
                                  width: half,
                                  child: _field(
                                    _name,
                                    'Name mask',
                                    'rename-name-mask',
                                    helper: '[N] original name · [C] counter · [P] parent',
                                  ),
                                ),
                                SizedBox(
                                  width: half,
                                  child: _field(
                                    _extension,
                                    'Extension mask',
                                    'rename-extension-mask',
                                    helper: '[E] original extension · empty removes it',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                SizedBox(
                                  width: half,
                                  child: _casePicker(
                                    'Name case',
                                    _nameCase,
                                    (value) => _nameCase = value,
                                  ),
                                ),
                                SizedBox(
                                  width: half,
                                  child: _casePicker(
                                    'Extension case',
                                    _extensionCase,
                                    (value) => _extensionCase = value,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _field(
                                    _start,
                                    'Counter start',
                                    'rename-counter-start',
                                    number: true,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _field(
                                    _step,
                                    'Step',
                                    'rename-counter-step',
                                    number: true,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _field(
                                    _width,
                                    'Digits (1–12)',
                                    'rename-counter-width',
                                    number: true,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                SizedBox(
                                  width: half,
                                  child: _field(_find, 'Find', 'rename-find'),
                                ),
                                SizedBox(
                                  width: half,
                                  child: _field(
                                    _replace,
                                    'Replace with',
                                    'rename-replace',
                                    helper: _useRegex
                                        ? r'Captures: $1, ${name} · literal dollar: $$'
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _chip(
                                  'Regex',
                                  _useRegex,
                                  (value) => _useRegex = value,
                                ),
                                _chip(
                                  'Match case',
                                  _caseSensitive,
                                  (value) => _caseSensitive = value,
                                ),
                                _chip(
                                  'First match only',
                                  _firstMatch,
                                  (value) => _firstMatch = value,
                                ),
                                SizedBox(
                                  width: math.min(360.0, constraints.maxWidth),
                                  child: DropdownButton<RenameReplaceScope>(
                                    value: _scope,
                                    isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(
                                        value: RenameReplaceScope.fullName,
                                        child: Text(
                                          'Replace in full name',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: RenameReplaceScope.name,
                                        child: Text(
                                          'Replace in name only',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: RenameReplaceScope.extension,
                                        child: Text(
                                          'Replace in extension',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                    onChanged: !_editable
                                        ? null
                                        : (value) {
                                            if (value == null) return;
                                            _scope = value;
                                            _changed();
                                          },
                                  ),
                                ),
                              ],
                            ),
                            const ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                'Mask reference',
                                style: TextStyle(fontSize: 13),
                              ),
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: EdgeInsets.only(bottom: 12),
                                    child: Text(
                                      '[N] name without the last extension; [E] extension without a dot; '
                                      '[C] counter; [C:4] counter with four digits; [P] original parent folder.\n'
                                      '[N1-4] first four characters; [N3-] from character 3; '
                                      '[N-4--1] last four characters. Positions start at 1.\n'
                                      '[Y][M][D] year/month/day; [h][m][s] hour/minute/second from the modified time. '
                                      'Use [[ and ]] for literal brackets.\n'
                                      'Folder names use the name mask only. A leading dot is part of a file name. '
                                      'Masks are applied first, then replacement, then case changes.',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Preview · ${plan.changeCount} changes',
                                  style: theme.textTheme.titleSmall,
                                ),
                                Wrap(
                                  children: [
                                    TextButton.icon(
                                      onPressed: !_editable
                                          ? null
                                          : () {
                                              _files.sort(
                                                (a, b) => a.name
                                                    .toLowerCase()
                                                    .compareTo(
                                                      b.name.toLowerCase(),
                                                    ),
                                              );
                                              _changed();
                                            },
                                      icon: const Icon(
                                        Icons.sort_by_alpha,
                                        size: 16,
                                      ),
                                      label: const Text('Sort by name'),
                                    ),
                                    TextButton.icon(
                                      onPressed: !_editable
                                          ? null
                                          : () {
                                              final reversed = _files.reversed
                                                  .toList();
                                              _files
                                                ..clear()
                                                ..addAll(reversed);
                                              _changed();
                                            },
                                      icon: const Icon(
                                        Icons.swap_vert,
                                        size: 16,
                                      ),
                                      label: const Text('Reverse'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            _preview(plan),
                            const SizedBox(height: 8),
                            Text(
                              'Existing destinations, duplicate names and overlapping folder selections are checked before starting.',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            _chip(
                              'Stop on error',
                              _stopOnError,
                              (value) => _stopOnError = value,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                if (_originError != null) _error(_originError!),
                if (plan.errors.isNotEmpty) _error(plan.errors.join('\n')),
                if (!plan.isValid && plan.errors.isEmpty)
                  _error('Resolve the marked preview errors before renaming.'),
                if (_message != null) _error(_message!),
                if (_processing) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _progress == null || _progress!.total == 0
                        ? null
                        : _progress!.completed / _progress!.total,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _cancelRequested
                        ? 'Stopping after the current operation…'
                        : _progress?.phase == MultiRenamePhase.renaming
                        ? 'Renaming ${_progress!.completed} / ${_progress!.total}…'
                        : 'Checking original paths and destinations…',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (_result != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${_result!.cancelled ? "Stopped. " : ""}${_result!.renamed} renamed, '
                      '${_result!.failed} failed, ${_result!.unchanged} unchanged, ${_result!.notRun} not run.',
                      key: const ValueKey('rename-result'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                const SizedBox(height: 12),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  overflowSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _processing
                          ? _cancelRequested
                                ? null
                                : () => setState(() => _cancelRequested = true)
                          : () => Navigator.pop(context, _result),
                      child: Text(
                        _processing
                            ? 'Stop after current item'
                            : _result != null
                            ? (text?.close ?? 'Close')
                            : (text?.cancel ?? 'Cancel'),
                      ),
                    ),
                    if (_result == null)
                      FilledButton.icon(
                        key: const ValueKey('rename-apply'),
                        onPressed:
                            _editable && _originError == null && plan.canExecute
                            ? () => _execute(plan)
                            : null,
                        icon: const Icon(
                          Icons.drive_file_rename_outline,
                          size: 18,
                        ),
                        label: Text('Rename ${plan.changeCount} items'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String key, {
    String? helper,
    bool number = false,
  }) => TextField(
    key: ValueKey(key),
    controller: controller,
    enabled: _editable,
    keyboardType: number
        ? const TextInputType.numberWithOptions(signed: true)
        : null,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 2,
      border: const OutlineInputBorder(),
      isDense: true,
    ),
    onChanged: _changed,
  );

  Widget _casePicker(
    String label,
    RenameCase selected,
    ValueChanged<RenameCase> changed,
  ) => DropdownButtonFormField<RenameCase>(
    initialValue: selected,
    isExpanded: true,
    key: ValueKey('$label-${selected.name}'),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    ),
    items: [
      for (final value in RenameCase.values)
        DropdownMenuItem(
          value: value,
          child: Text(
            switch (value) {
              RenameCase.unchanged => 'Keep case',
              RenameCase.lower => 'lowercase',
              RenameCase.upper => 'UPPERCASE',
              RenameCase.title => 'Title Case',
              RenameCase.sentence => 'First letter uppercase',
            },
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: !_editable
        ? null
        : (value) {
            if (value == null) return;
            changed(value);
            _changed();
          },
  );

  Widget _chip(String label, bool selected, ValueChanged<bool> changed) =>
      Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        child: FilterChip(
          label: Text(label),
          selected: selected,
          onSelected: !_editable
              ? null
              : (value) {
                  changed(value);
                  _changed();
                },
        ),
      );

  Widget _error(String message) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      message,
      style: TextStyle(
        color: Theme.of(context).colorScheme.error,
        fontSize: 12,
      ),
    ),
  );

  Widget _preview(MultiRenamePlan plan) => Container(
    height: 230,
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(6),
    ),
    child: ListView.separated(
      key: const ValueKey('rename-preview'),
      itemCount: plan.entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = plan.entries[index];
        final outcome = _result?.outcomes[index];
        final errors = [
          ...entry.errors,
          if (_executionErrors.containsKey(entry.sourcePath))
            _executionErrors[entry.sourcePath]!,
          if (outcome?.message != null) outcome!.message!,
        ];
        final status = switch (outcome?.status) {
          MultiRenameStatus.renamed => 'Renamed',
          MultiRenameStatus.failed => 'Failed',
          MultiRenameStatus.notRun => 'Not run',
          MultiRenameStatus.unchanged => 'Unchanged',
          null => entry.changed ? 'Ready' : 'Unchanged',
        };
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.sourcePath,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Icon(
                    entry.file.isFolder
                        ? Icons.folder_outlined
                        : Icons.insert_drive_file_outlined,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '→ ${entry.newName}',
                      style: TextStyle(
                        fontWeight: entry.changed
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: errors.isEmpty
                            ? null
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    errors.isEmpty ? status : 'Check',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              if (errors.isNotEmpty) _error(errors.join('\n')),
            ],
          ),
        );
      },
    ),
  );

  Widget _presetBar() => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SizedBox(
        width: 240,
        child: DropdownButtonFormField<String>(
          key: ValueKey('rename-preset-$_preset-${_presets.length}'),
          initialValue: _preset,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Preset',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          hint: const Text('Custom settings'),
          items: [
            for (final name in _presets.keys.toList()..sort())
              DropdownMenuItem(
                value: name,
                child: Text(name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: !_editable
              ? null
              : (name) {
                  if (name == null) return;
                  _setOptions(_presets[name]!);
                  setState(() => _preset = name);
                },
        ),
      ),
      TextButton.icon(
        onPressed: _editable ? _savePreset : null,
        icon: const Icon(Icons.save_outlined, size: 18),
        label: const Text('Save preset'),
      ),
      if (_preset != null)
        TextButton.icon(
          onPressed: _editable ? _deletePreset : null,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Remove preset'),
        ),
      TextButton(
        onPressed: !_editable
            ? null
            : () => _setOptions(const MultiRenameOptions()),
        child: const Text('Reset'),
      ),
    ],
  );

  void _setOptions(MultiRenameOptions options) {
    _name.text = options.nameMask;
    _extension.text = options.extensionMask;
    _find.text = options.find;
    _replace.text = options.replace;
    _start.text = options.counterStart.toString();
    _step.text = options.counterStep.toString();
    _width.text = options.counterWidth.toString();
    _useRegex = options.useRegex;
    _caseSensitive = options.caseSensitive;
    _firstMatch = options.firstMatchOnly;
    _scope = options.replaceScope;
    _nameCase = options.nameCase;
    _extensionCase = options.extensionCase;
    _changed();
  }

  Future<void> _loadPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_presetKey);
      if (stored == null) return;
      final decoded = jsonDecode(stored);
      if (decoded is! Map<String, dynamic>) return;
      final presets = <String, MultiRenameOptions>{};
      for (final entry in decoded.entries) {
        if (entry.value is Map<String, dynamic>) {
          presets[entry.key] = MultiRenameOptions.fromJson(
            entry.value as Map<String, dynamic>,
          );
        }
      }
      if (mounted) setState(() => _presets = presets);
    } catch (error) {
      _log.warn('Could not load multi-rename presets', error);
    }
  }

  Future<void> _writePresets() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _presetKey,
      jsonEncode(
        _presets.map((name, options) => MapEntry(name, options.toJson())),
      ),
    );
    if (!saved) throw StateError('The preset could not be saved.');
  }

  Future<void> _savePreset() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenamePresetNameDialog(initialName: _preset ?? ''),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final before = Map<String, MultiRenameOptions>.of(_presets);
    try {
      _presets[name] = _options;
      await _writePresets();
      if (mounted) setState(() => _preset = name);
    } catch (error) {
      _presets = before;
      if (mounted) setState(() => _message = 'Could not save preset: $error');
    }
  }

  Future<void> _deletePreset() async {
    final name = _preset;
    if (name == null) return;
    final before = Map<String, MultiRenameOptions>.of(_presets);
    try {
      _presets.remove(name);
      await _writePresets();
      if (mounted) setState(() => _preset = null);
    } catch (error) {
      _presets = before;
      if (mounted) setState(() => _message = 'Could not remove preset: $error');
    }
  }

  Future<void> _execute(MultiRenamePlan plan) async {
    final origin = _origin;
    if (origin == null || !origin.isCurrent) {
      setState(
        () => _originError = 'The storage source changed. Close this dialog and select the items again.',
      );
      return;
    }
    setState(() {
      _processing = true;
      _executionPlan = plan;
      _cancelRequested = false;
      _executionErrors = {};
      _message = null;
    });
    try {
      final result = await _service.execute(
        plan,
        exists: (path) => _panel.operationPathExists(path, origin),
        rename: (file, name) => _panel.renameFile(
          file,
          name,
          refreshAfter: false,
          rethrowErrors: true,
          operationOrigin: origin,
        ),
        isCancelled: () => _cancelRequested || !mounted,
        continueOnError: !_stopOnError,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (mounted) setState(() => _result = result);
      if (origin.isCurrent && result.changes.isNotEmpty) {
        _panel.applyFileListChanges(result.changes, origin: origin);
        await _panel.refresh();
      }
    } on MultiRenamePreflightException catch (error) {
      if (mounted) {
        setState(() {
          _executionErrors = error.problems;
          _message = 'Nothing was renamed. Resolve the path errors shown in the preview.';
        });
      }
    } catch (error, stackTrace) {
      _log.error('Multi-rename failed', error, stackTrace);
      if (mounted) setState(() => _message = 'Rename failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
          if (_result == null) _executionPlan = null;
        });
      }
    }
  }
}

class _RenamePresetNameDialog extends StatefulWidget {
  const _RenamePresetNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenamePresetNameDialog> createState() =>
      _RenamePresetNameDialogState();
}

class _RenamePresetNameDialogState extends State<_RenamePresetNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save rename preset'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 80,
      decoration: const InputDecoration(labelText: 'Preset name'),
      onSubmitted: (_) => Navigator.pop(context, _controller.text.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}

/// The tool also accepts one item, useful for testing a mask before a batch.
void showBatchRenameDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files,
) {
  if (files.isEmpty) return;
  showDialog<MultiRenameResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        BatchRenameDialog(parentRef: ref, side: side, files: List.of(files)),
  );
}
