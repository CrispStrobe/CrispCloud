import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/commander_strings.dart';
import '../l10n/app_localizations.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../models/rename_batch.dart';
import '../providers/action_history_provider.dart';
import '../providers/panel_provider.dart';
import '../services/log_service.dart';
import '../services/multi_rename_service.dart';
import '../services/rename_batch_service.dart';
import '../services/rename_batch_storage.dart';
import '../services/rename_batch_store.dart';
import '../services/rename_preset_store.dart';
import 'rename_history_dialog.dart';
import 'rename_names_dialog.dart';
import 'rename_text_dialog.dart';

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
  static const _service = MultiRenameService();
  final _presetStore = RenamePresetStore();

  final _name = TextEditingController(text: '[N]');
  final _extension = TextEditingController(text: '[E]');
  final _find = TextEditingController();
  final _replace = TextEditingController();
  final _start = TextEditingController(text: '1');
  final _step = TextEditingController(text: '1');
  final _width = TextEditingController(text: '3');
  final _dateOffset = TextEditingController(text: '0');
  final _variables = TextEditingController();
  DateTime _referenceTime = DateTime.now();
  late DateTime _optionsChangedAt = _referenceTime;
  final _targetNames = <String, String>{};
  final _excludedPaths = <String>{};
  final _steps = <MultiRenameOptions>[const MultiRenameOptions()];
  int _selectedStep = 0;
  Set<String> _existingPaths = {};
  bool _namesChecked = false;
  bool _checkingNames = false;
  bool _caseSensitivePaths = false;
  RenameMaskDialect _dialect = RenameMaskDialect.crispCloud;
  RenameDateSource _dateSource = RenameDateSource.modified;
  RenameDateZone _dateZone = RenameDateZone.original;
  bool _multiplePairs = false;
  RenameCollisionPolicy _collisions = RenameCollisionPolicy.error;
  late final List<FileItem> _files;
  late final PanelNotifier _panel;
  late final String _directory;
  p.Context _paths = p.posix;
  PanelFileOrigin? _origin;
  SourceRenameBatchStorage? _storage;
  late final _batchService = RenameBatchService(
    ref.read(renameBatchStoreProvider),
  );
  RenameBatchRecord? _batch;
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
  RenameBatchProgress? _progress;
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
        _originError =
            'These items no longer have a verified storage source. Refresh the panel.';
      } else if (_origin!.source.isLocal && !kIsWeb) {
        _paths = p.context;
      }
      if (_origin != null) {
        _storage = createPanelRenameStorage(ref, _panel, _origin!);
        _caseSensitivePaths = _storage!.caseSensitivePaths;
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
      _dateOffset,
      _variables,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _editable => !_processing && !_checkingNames && _result == null;

  MultiRenameOptions get _currentOptions => MultiRenameOptions(
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
    dialect: _dialect,
    dateSource: _dateSource,
    dateZone: _dateZone,
    dateOffsetMinutes: int.tryParse(_dateOffset.text) ?? 0,
    variables: {
      for (final line in const LineSplitter().convert(_variables.text))
        if (line.contains('='))
          line.substring(0, line.indexOf('=')).trim(): line.substring(
            line.indexOf('=') + 1,
          ),
    },
    multipleLiteralPairs: _multiplePairs,
    collisionPolicy: _collisions,
  );

  MultiRenameOptions get _options {
    final steps = List<MultiRenameOptions>.of(_steps);
    steps[_selectedStep] = _currentOptions;
    return steps.first.copyWith(
      additionalSteps: steps.skip(1).toList(),
      collisionPolicy: _collisions,
    );
  }

  String _filePath(FileItem file) =>
      _paths.normalize(file.path ?? _paths.join(_directory, file.name));

  List<FileItem> get _includedFiles => _files
      .where((file) => !_excludedPaths.contains(_filePath(file)))
      .toList(growable: false);

  String? get _inputError {
    if (_collisions == RenameCollisionPolicy.number && !_namesChecked) {
      return 'Check existing names before using collision numbering.';
    }
    for (final field in {
      'Counter start': _start,
      'Counter step': _step,
      'Counter digits': _width,
      'Date offset': _dateOffset,
    }.entries) {
      if (int.tryParse(field.value.text) == null) {
        return '${field.key} must be a whole number.';
      }
    }
    for (final line in const LineSplitter().convert(_variables.text)) {
      if (line.trim().isEmpty) continue;
      if (!line.contains('=') || line.split('=').first.trim().isEmpty) {
        return 'Enter each variable as a name=value pair on its own line.';
      }
    }
    return null;
  }

  MultiRenamePlan get _plan =>
      _executionPlan ??
      _service.preview(
        _includedFiles,
        _options,
        directory: _directory,
        pathContext: _paths,
        targetNames: _targetNames,
        existingPaths: _existingPaths,
        caseSensitivePaths: _caseSensitivePaths,
        allowDependencies: true,
        referenceTime: _referenceTime,
        optionsChangedAt: _optionsChangedAt,
      );

  void _changed([String? _]) {
    setState(() {
      _optionsChangedAt = DateTime.now();
      _executionErrors = {};
      _executionPlan = null;
      _message = null;
      _preset = null;
    });
  }

  String _t(String key, [Map<String, Object> values = const {}]) =>
      BatchRenameStrings(context).text(key, values);

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
                  context.commanderTr("Multi-rename ({0} items)", [
                    _files.length,
                  ]),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  context.commanderTr(
                    "Combine masks, replacement and case changes. The counter follows preview order.",
                  ),
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
                            _advancedOptions(half),
                            _pipelineBar(),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                SizedBox(
                                  width: half,
                                  child: _field(
                                    _name,
                                    context.commanderTr("Name mask"),
                                    'rename-name-mask',
                                    helper: context.commanderTr(
                                      "[N] original name · [C] counter · [P] parent",
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: half,
                                  child: _field(
                                    _extension,
                                    context.commanderTr("Extension mask"),
                                    'rename-extension-mask',
                                    helper: context.commanderTr(
                                      "[E] original extension · empty removes it",
                                    ),
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
                                    context.commanderTr("Name case"),
                                    _nameCase,
                                    (value) => _nameCase = value,
                                  ),
                                ),
                                SizedBox(
                                  width: half,
                                  child: _casePicker(
                                    context.commanderTr("Extension case"),
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
                                    context.commanderTr("Counter start"),
                                    'rename-counter-start',
                                    number: true,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _field(
                                    _step,
                                    context.commanderTr("Step"),
                                    'rename-counter-step',
                                    number: true,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _field(
                                    _width,
                                    context.commanderTr("Digits (1–12)"),
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
                                  child: _field(
                                    _find,
                                    context.commanderTr("Find"),
                                    'rename-find',
                                  ),
                                ),
                                SizedBox(
                                  width: half,
                                  child: _field(
                                    _replace,
                                    context.commanderTr("Replace with"),
                                    'rename-replace',
                                    helper: _useRegex
                                        ? context.commanderTr(
                                            "Captures: \$1, \${name} · literal dollar: \$\$",
                                          )
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
                                _chip(context.commanderTr("Regex"), _useRegex, (
                                  value,
                                ) {
                                  _useRegex = value;
                                  if (value) _multiplePairs = false;
                                }),
                                _chip(
                                  context.commanderTr("Multiple literal pairs"),
                                  _multiplePairs,
                                  (value) {
                                    _multiplePairs = value;
                                    if (value) _useRegex = false;
                                  },
                                ),
                                _chip(
                                  context.commanderTr("Match case"),
                                  _caseSensitive,
                                  (value) => _caseSensitive = value,
                                ),
                                _chip(
                                  context.commanderTr("First match only"),
                                  _firstMatch,
                                  (value) => _firstMatch = value,
                                ),
                                SizedBox(
                                  width: math.min(360.0, constraints.maxWidth),
                                  child: DropdownButton<RenameReplaceScope>(
                                    value: _scope,
                                    isExpanded: true,
                                    items: [
                                      DropdownMenuItem(
                                        value: RenameReplaceScope.fullName,
                                        child: Text(
                                          context.commanderTr(
                                            "Replace in full name",
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: RenameReplaceScope.name,
                                        child: Text(
                                          context.commanderTr(
                                            "Replace in name only",
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: RenameReplaceScope.extension,
                                        child: Text(
                                          context.commanderTr(
                                            "Replace in extension",
                                          ),
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
                            if (_multiplePairs)
                              Text(
                                context.commanderTr(
                                  "Separate simultaneous search/replacement pairs with |, for example red|blue → blue|green.",
                                ),
                                style: theme.textTheme.bodySmall,
                              ),
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                context.commanderTr("Mask reference"),
                                style: const TextStyle(fontSize: 13),
                              ),
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(
                                      context.commanderTr(
                                        "[N] name without the last extension; [E] extension without a dot; [C] counter; [C:4] counter with four digits; [P] original parent folder.\n[N1-4] first four characters; [N3-] from character 3; [N-4--1] last four characters. Positions start at 1.\n[YMD] and [hms] use the selected date source in CrispCloud/TC syntax. DC uses [YYYY][MM][DD] and [hh][nn][ss].\n[T1] modified; [T2] created; [T3] accessed; [T4] captured; [T5] batch time. [T4+60m] shifts the captured date one hour. [meta:artist] uses supplied metadata.\n[V:Project] uses a named variable; [G] creates a stable identifier for this preview. [C7+2:4] starts at 7, steps by 2 and uses four digits.\nTC inline case: [U] uppercase, [L] lowercase, [F] title case, [n] reset. [B0] is the parent and [B1] the grandparent.\nUse [[ and ]] for literal brackets, or [[] and []] in TC/DC syntax. External Commander content plugins are not loaded; unsupported fields produce a preview error.\nFolder names use the name mask only. A leading dot is part of a file name. Masks are applied first, then replacement, then case changes. Each transformation consumes the previous proposed name. Manual targets override the rule pipeline for that row.",
                                      ),
                                      style: const TextStyle(fontSize: 12),
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
                                  context.commanderTr("Preview · {0} changes", [
                                    plan.changeCount,
                                  ]),
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
                                      label: Text(
                                        context.commanderTr("Sort by name"),
                                      ),
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
                                      label: Text(
                                        context.commanderTr("Reverse"),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            _previewTools(plan),
                            _preview(plan),
                            if (_excludedPaths.isNotEmpty)
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                children: [
                                  Text(
                                    context.commanderTr(
                                      "{0} excluded from this batch",
                                      [_excludedPaths.length],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: !_editable
                                        ? null
                                        : () {
                                            _excludedPaths.clear();
                                            _changed();
                                          },
                                    child: Text(
                                      context.commanderTr(
                                        "Restore excluded rows",
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 8),
                            Text(
                              plan.requiresStaging
                                  ? context.commanderTr(
                                      "This plan uses temporary sibling names to resolve case changes, dependencies or selected folders. Each physical move is saved for recovery.",
                                    )
                                  : context.commanderTr(
                                      "Original items and existing destinations are checked before starting. Every completed move is recorded for batch restore.",
                                    ),
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            _chip(
                              context.commanderTr("Stop on error"),
                              _stopOnError,
                              (value) => _stopOnError = value,
                            ),
                            if (_storage != null && !_storage!.exclusiveMoves)
                              Text(
                                context.commanderTr(
                                  "This provider checks destination names before each move but does not guarantee an exclusive rename.",
                                ),
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                if (_originError != null) _error(_originError!),
                if (_inputError != null) _error(_inputError!),
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
                        ? context.commanderTr(
                            "Stopping after the current operation…",
                          )
                        : _progress == null
                        ? context.commanderTr(
                            "Checking original paths and destinations…",
                          )
                        : '${_progress!.message} · ${_progress!.completed} / ${_progress!.total}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (_result != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      context.commanderTr(
                        "{0}{1} renamed, {2} failed, {3} unchanged, {4} not run.",
                        [
                          _result!.cancelled
                              ? "${context.commanderTr("Stopped.")} "
                              : "",
                          _result!.renamed,
                          _result!.failed,
                          _result!.unchanged,
                          _result!.notRun,
                        ],
                      ),
                      key: const ValueKey('rename-result'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                if ((_result?.renamed ?? 0) > 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'After closing, Edit → Undo restores this batch as one action.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 12),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  overflowSpacing: 8,
                  children: [
                    TextButton.icon(
                      key: const ValueKey('rename-history'),
                      onPressed: _processing ? null : _openHistory,
                      icon: const Icon(Icons.history, size: 18),
                      label: Text(context.commanderTr("History / recovery")),
                    ),
                    if (_batch?.isComplete == true)
                      TextButton(
                        onPressed: _processing ? null : _restoreBatch,
                        child: Text(context.commanderTr("Undo batch")),
                      ),
                    if (_batch?.isComplete == true ||
                        _batch?.isRestored == true)
                      TextButton(
                        key: const ValueKey('rename-next-batch'),
                        onPressed: _processing ? null : _nextBatch,
                        child: Text(
                          context.commanderTr("Continue with these items"),
                        ),
                      ),
                    if (_batch != null)
                      TextButton(
                        onPressed: _processing ? null : _exportReport,
                        child: Text(context.commanderTr("Export report")),
                      ),
                    TextButton(
                      onPressed: _processing
                          ? _cancelRequested
                                ? null
                                : () => setState(() => _cancelRequested = true)
                          : () => Navigator.pop(context, _result),
                      child: Text(
                        _processing
                            ? context.commanderTr("Stop after current item")
                            : _result != null
                            ? (text?.close ?? 'Close')
                            : (text?.cancel ?? 'Cancel'),
                      ),
                    ),
                    if (_result == null)
                      FilledButton.icon(
                        key: const ValueKey('rename-apply'),
                        onPressed:
                            _editable &&
                                _originError == null &&
                                _inputError == null &&
                                plan.canExecute
                            ? () => _execute(plan)
                            : null,
                        icon: const Icon(
                          Icons.drive_file_rename_outline,
                          size: 18,
                        ),
                        label: Text(
                          context.commanderTr("Rename {0} items", [
                            plan.changeCount,
                          ]),
                        ),
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

  Widget _advancedOptions(double width) => ExpansionTile(
    key: const ValueKey('rename-advanced'),
    tilePadding: EdgeInsets.zero,
    title: Text(
      context.commanderTr("Advanced rename rules"),
      style: const TextStyle(fontSize: 13),
    ),
    childrenPadding: const EdgeInsets.only(bottom: 12),
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: width,
            child: _optionPicker<RenameMaskDialect>(
              context.commanderTr("Mask dialect"),
              _dialect,
              {
                RenameMaskDialect.crispCloud: context.commanderTr("CrispCloud"),
                RenameMaskDialect.totalCommander: context.commanderTr(
                  "Total Commander",
                ),
                RenameMaskDialect.doubleCommander: context.commanderTr(
                  "Double Commander",
                ),
              },
              (value) => _dialect = value,
            ),
          ),
          SizedBox(
            width: width,
            child: _optionPicker<RenameDateSource>(
              context.commanderTr("Date source"),
              _dateSource,
              {
                RenameDateSource.modified: context.commanderTr("Modified time"),
                RenameDateSource.created: context.commanderTr(
                  "Created time (metadata)",
                ),
                RenameDateSource.accessed: context.commanderTr(
                  "Accessed time (metadata)",
                ),
                RenameDateSource.captured: context.commanderTr(
                  "Captured time (metadata)",
                ),
                RenameDateSource.current: context.commanderTr(
                  "Time this dialog opened",
                ),
              },
              (value) => _dateSource = value,
            ),
          ),
          SizedBox(
            width: width,
            child: _optionPicker<RenameDateZone>(
              context.commanderTr("Time zone"),
              _dateZone,
              {
                RenameDateZone.original: context.commanderTr(
                  "Original time zone",
                ),
                RenameDateZone.local: context.commanderTr("Local time zone"),
                RenameDateZone.utc: context.commanderTr("UTC"),
              },
              (value) => _dateZone = value,
            ),
          ),
          SizedBox(
            width: width,
            child: _field(
              _dateOffset,
              context.commanderTr("Date offset (minutes)"),
              'rename-date-offset',
              number: true,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _field(
        _variables,
        context.commanderTr("Variables (one name=value per line)"),
        'rename-variables',
        helper: context.commanderTr("[V:Project] uses Project=Holiday"),
      ),
      const SizedBox(height: 8),
      Text(
        context.commanderTr(
          "TC ranges: [N1-5]. DC ranges: [N1:5] or [N1,5]. [meta:artist] uses metadata already supplied by the source; unavailable fields block the preview. The dialect is stored with presets.",
        ),
        style: const TextStyle(fontSize: 12),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilterChip(
          label: Text(context.commanderTr("Number colliding targets")),
          selected: _collisions == RenameCollisionPolicy.number,
          onSelected: !_editable
              ? null
              : (value) {
                  _collisions = value
                      ? RenameCollisionPolicy.number
                      : RenameCollisionPolicy.error;
                  _changed();
                  if (value) _checkExistingNames();
                },
        ),
      ),
    ],
  );

  Widget _pipelineBar() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_steps.length > 1) ...[
        Text(
          context.commanderTr(
            "Transformation {0} of {1} · steps run in this order",
            [_selectedStep + 1, _steps.length],
          ),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (var index = 0; index < _steps.length; index++)
              InputChip(
                key: ValueKey('rename-step-$index'),
                selected: index == _selectedStep,
                label: Text(
                  context.commanderTr("Step {0}: {1}", [
                    index + 1,
                    index == _selectedStep
                        ? _name.text
                        : _steps[index].nameMask,
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: !_editable ? null : () => _selectStep(index),
                onDeleted: !_editable ? null : () => _removeStep(index),
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: !_editable || _selectedStep == 0
                  ? null
                  : () => _moveStep(-1),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: Text(context.commanderTr("Step earlier")),
            ),
            TextButton.icon(
              onPressed: !_editable || _selectedStep == _steps.length - 1
                  ? null
                  : () => _moveStep(1),
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: Text(context.commanderTr("Step later")),
            ),
          ],
        ),
      ],
    ],
  );

  void _selectStep(int index) {
    if (_inputError != null) return;
    _steps[_selectedStep] = _currentOptions;
    _selectedStep = index;
    _assignOptions(_steps[index]);
    _changed();
  }

  void _removeStep(int index) {
    if (index != _selectedStep && _inputError != null) return;
    _steps[_selectedStep] = _currentOptions;
    _steps.removeAt(index);
    if (_steps.isEmpty) _steps.add(const MultiRenameOptions());
    if (index < _selectedStep) _selectedStep--;
    _selectedStep = _selectedStep.clamp(0, _steps.length - 1);
    _assignOptions(_steps[_selectedStep]);
    _changed();
  }

  void _moveStep(int direction) {
    if (_inputError != null) return;
    _steps[_selectedStep] = _currentOptions;
    final next = _selectedStep + direction;
    if (next < 0 || next >= _steps.length) return;
    final current = _steps[_selectedStep];
    _steps[_selectedStep] = _steps[next];
    _steps[next] = current;
    _selectedStep = next;
    _assignOptions(current);
    _changed();
  }

  Widget _optionPicker<T>(
    String label,
    T value,
    Map<T, String> labels,
    ValueChanged<T> changed,
  ) => DropdownButtonFormField<T>(
    key: ValueKey('rename-$label-$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    ),
    items: [
      for (final entry in labels.entries)
        DropdownMenuItem(
          value: entry.key,
          child: Text(
            entry.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: !_editable
        ? null
        : (next) {
            if (next == null) return;
            changed(next);
            _changed();
          },
  );

  Widget _previewTools(MultiRenamePlan plan) => Wrap(
    spacing: 8,
    children: [
      TextButton.icon(
        key: const ValueKey('rename-edit-names'),
        onPressed: !_editable || plan.entries.isEmpty
            ? null
            : () => _editNames(plan),
        icon: const Icon(Icons.edit_note, size: 18),
        label: Text(context.commanderTr("Edit / import names")),
      ),
      TextButton.icon(
        key: const ValueKey('rename-add-step'),
        onPressed:
            !_editable ||
                !plan.isValid ||
                _inputError != null ||
                _steps.length >= 101 ||
                _targetNames.isNotEmpty
            ? null
            : () {
                _steps[_selectedStep] = _currentOptions;
                _steps.add(const MultiRenameOptions());
                _selectedStep = _steps.length - 1;
                _assignOptions(const MultiRenameOptions());
                _changed();
              },
        icon: const Icon(Icons.add, size: 18),
        label: Text(context.commanderTr("Add transformation")),
      ),
      TextButton.icon(
        key: const ValueKey('rename-export-names'),
        onPressed: plan.entries.isEmpty || _processing
            ? null
            : () => showDialog<String>(
                context: context,
                builder: (_) => RenameTextDialog(
                  title: context.commanderTr("Proposed names"),
                  instructions: context.commanderTr(
                    "One target name per current preview row. Save or copy this list for editing.",
                  ),
                  initialText: plan.entries
                      .map((entry) => entry.newName)
                      .join('\n'),
                  submitLabel: context.commanderTr("Close"),
                ),
              ),
        icon: const Icon(Icons.file_download_outlined, size: 18),
        label: Text(context.commanderTr("Export names")),
      ),
      TextButton.icon(
        onPressed: !_editable || _originError != null
            ? null
            : _checkExistingNames,
        icon: const Icon(Icons.fact_check_outlined, size: 18),
        label: Text(
          _checkingNames
              ? context.commanderTr("Checking names…")
              : context.commanderTr("Check existing names"),
        ),
      ),
      if (_targetNames.isNotEmpty)
        TextButton(
          onPressed: !_editable
              ? null
              : () {
                  _targetNames.clear();
                  _changed();
                },
          child: Text(context.commanderTr("Clear manual names")),
        ),
    ],
  );

  Future<void> _editNames(MultiRenamePlan plan) async {
    final names = await showDialog<List<String>>(
      context: context,
      builder: (_) => RenameNamesDialog(
        names: plan.entries.map((entry) => entry.newName).toList(),
      ),
    );
    if (!mounted || names == null) return;
    for (var index = 0; index < names.length; index++) {
      _targetNames[plan.entries[index].sourcePath] = names[index];
    }
    _changed();
  }

  Future<void> _editRow(MultiRenameEntry entry) async {
    final names = await showDialog<List<String>>(
      context: context,
      builder: (_) => RenameNamesDialog(names: [entry.newName]),
    );
    if (!mounted || names == null) return;
    _targetNames[entry.sourcePath] = names.single;
    _changed();
  }

  void _moveRow(MultiRenameEntry entry, int direction) {
    final included = _includedFiles;
    final index = included.indexWhere((file) => identical(file, entry.file));
    final next = index + direction;
    if (index < 0 || next < 0 || next >= included.length) return;
    final oldIndex = _files.indexWhere((file) => identical(file, entry.file));
    final nextIndex = _files.indexWhere(
      (file) => identical(file, included[next]),
    );
    final previous = _files[oldIndex];
    _files[oldIndex] = _files[nextIndex];
    _files[nextIndex] = previous;
    _changed();
  }

  Future<void> _checkExistingNames() async {
    final origin = _origin;
    if (origin == null) return;
    setState(() {
      _checkingNames = true;
      _namesChecked = false;
      _message = null;
    });
    try {
      final paths = <String>{};
      final parents = _files
          .map((file) => _paths.dirname(_filePath(file)))
          .toSet();
      for (final parent in parents) {
        if (!mounted) return;
        final siblings = await _storage!.list(parent);
        paths.addAll(
          siblings.map(
            (file) =>
                _paths.normalize(file.path ?? _paths.join(parent, file.name)),
          ),
        );
      }
      if (mounted) {
        setState(() {
          _existingPaths = paths;
          _namesChecked = true;
          _executionErrors = {};
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Could not check existing names: $error');
      }
    } finally {
      if (mounted) setState(() => _checkingNames = false);
    }
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
    minLines: key == 'rename-variables' ? 2 : 1,
    maxLines: key == 'rename-variables' ? 4 : 1,
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
              RenameCase.unchanged => context.commanderTr("Keep case"),
              RenameCase.lower => context.commanderTr("lowercase"),
              RenameCase.upper => context.commanderTr("UPPERCASE"),
              RenameCase.title => context.commanderTr("Title Case"),
              RenameCase.sentence => context.commanderTr(
                "First letter uppercase",
              ),
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
                    errors.isEmpty ? status : context.commanderTr("Check"),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              if (_paths.dirname(entry.targetPath) !=
                  _paths.dirname(entry.sourcePath))
                Text(
                  entry.targetPath,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (_batch != null &&
                  _batch!.items[index].currentPath != entry.targetPath)
                Text(
                  context.commanderTr("Current: {0}", [
                    _batch!.items[index].currentPath,
                  ]),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (_editable)
                Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      key: ValueKey('rename-edit-${entry.sourcePath}'),
                      tooltip: context.commanderTr("Edit this proposed name"),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _editRow(entry),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                    IconButton(
                      tooltip: context.commanderTr("Move earlier in preview"),
                      visualDensity: VisualDensity.compact,
                      onPressed: index == 0 ? null : () => _moveRow(entry, -1),
                      icon: const Icon(Icons.arrow_upward, size: 18),
                    ),
                    IconButton(
                      tooltip: context.commanderTr("Move later in preview"),
                      visualDensity: VisualDensity.compact,
                      onPressed: index == plan.entries.length - 1
                          ? null
                          : () => _moveRow(entry, 1),
                      icon: const Icon(Icons.arrow_downward, size: 18),
                    ),
                    IconButton(
                      key: ValueKey('rename-exclude-${entry.sourcePath}'),
                      tooltip: context.commanderTr(
                        "Exclude from this batch (keep file)",
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        _excludedPaths.add(entry.sourcePath);
                        _changed();
                      },
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
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
          decoration: InputDecoration(
            labelText: context.commanderTr("Preset"),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          hint: Text(context.commanderTr("Custom settings")),
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
        label: Text(context.commanderTr("Save preset")),
      ),
      if (_preset != null)
        TextButton.icon(
          onPressed: _editable ? _deletePreset : null,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(context.commanderTr("Remove preset")),
        ),
      TextButton(
        onPressed: !_editable
            ? null
            : () => _setOptions(const MultiRenameOptions()),
        child: Text(context.commanderTr("Reset")),
      ),
      TextButton.icon(
        onPressed: _editable ? _exchangePresets : null,
        icon: const Icon(Icons.import_export, size: 18),
        label: Text(context.commanderTr("Import / export presets")),
      ),
    ],
  );

  void _setOptions(MultiRenameOptions options) {
    final all = [options, ...options.additionalSteps];
    _steps
      ..clear()
      ..addAll(all.map((step) => step.copyWith(additionalSteps: const [])));
    _selectedStep = 0;
    _assignOptions(all.first);
    _collisions = options.collisionPolicy;
    _targetNames.clear();
    _changed();
    if (_collisions == RenameCollisionPolicy.number) _checkExistingNames();
  }

  void _assignOptions(MultiRenameOptions options) {
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
    _dialect = options.dialect;
    _dateSource = options.dateSource;
    _dateZone = options.dateZone;
    _dateOffset.text = options.dateOffsetMinutes.toString();
    _variables.text = options.variables.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('\n');
    _multiplePairs = options.multipleLiteralPairs;
  }

  Future<void> _loadPresets() async {
    try {
      final presets = await _presetStore.load();
      if (mounted) setState(() => _presets = presets);
    } catch (error) {
      _log.warn('Could not load multi-rename presets', error);
      if (mounted) setState(() => _message = 'Could not load presets: $error');
    }
  }

  Future<void> _writePresets() => _presetStore.save(_presets);

  Future<void> _exchangePresets() async {
    final content = await showDialog<String>(
      context: context,
      builder: (_) => RenameTextDialog(
        title: context.commanderTr("Rename presets"),
        instructions: context.commanderTr(
          "Save or copy this versioned preset export, or load another export to import it. Imported names replace same-named saved presets.",
        ),
        initialText: _presetStore.export(
          _presets.isEmpty ? {'Current settings': _options} : _presets,
        ),
        submitLabel: context.commanderTr("Import presets"),
        filename: 'rename-presets.json',
        fileExtensions: const ['json'],
        validate: (value) {
          try {
            _presetStore.import(value);
            return null;
          } catch (error) {
            return error.toString();
          }
        },
      ),
    );
    if (content == null || !mounted) return;
    try {
      final combined = {..._presets, ..._presetStore.import(content)};
      await _presetStore.save(combined);
      if (mounted) {
        setState(() {
          _presets = combined;
          _message = 'Preset import saved.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'Preset import failed: $error');
    }
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
    final storage = _storage;
    if (origin == null || storage == null || !origin.isCurrent) {
      setState(
        () => _originError =
            'The storage source changed. Close this dialog and select the items again.',
      );
      return;
    }
    // The journal and normal Undo entry must outlive this dialog, including
    // disposal while a provider is completing a physical rename.
    final history = ref.read(actionHistoryProvider.notifier);
    final service = _batchService;
    final options = _options.toJson();
    setState(() {
      _processing = true;
      _executionPlan = plan;
      _cancelRequested = false;
      _executionErrors = {};
      _message = null;
    });
    try {
      void progress(RenameBatchProgress value) {
        if (mounted) setState(() => _progress = value);
      }

      final record = await service.prepare(
        plan,
        storage,
        options: options,
        isCancelled: () => _cancelRequested || !mounted,
        onProgress: progress,
      );
      _batch = record;
      await service.run(
        record,
        storage,
        isCancelled: () => _cancelRequested || !mounted,
        continueOnError: !_stopOnError,
        onProgress: progress,
      );
      if (record.message != null && mounted) {
        setState(() => _message = record.message);
      }
    } on MultiRenamePreflightException catch (error) {
      if (mounted) {
        setState(() {
          _executionErrors = error.problems;
          _message =
              'Nothing was renamed. Resolve the path errors shown in the preview.';
        });
      }
    } on RenameBatchPersistenceException catch (error) {
      if (error.record.steps.any(
        (step) => step.state != RenameStepState.pending,
      )) {
        _batch = error.record;
      }
      if (mounted) setState(() => _message = error.toString());
    } catch (error, stackTrace) {
      _log.error('Multi-rename failed', error, stackTrace);
      if (mounted) setState(() => _message = 'Rename failed: $error');
    } finally {
      final record = _batch;
      if (record != null) {
        // A stopped or partially failed batch still owns completed physical
        // steps. Its one Undo entry restores exactly the journalled work.
        if (record.canRestore) {
          _recordBatchUndo(record, origin, storage, history, service);
        }
        if (mounted) setState(() => _result = _resultFor(plan, record));
        if (origin.isCurrent) {
          _panel.applyFileListChanges(
            RenameBatchService.changes(record),
            origin: origin,
          );
          await _panel.refresh();
        }
      }
      if (mounted) {
        setState(() {
          _processing = false;
          if (_result == null) _executionPlan = null;
        });
      }
    }
  }

  MultiRenameResult _resultFor(
    MultiRenamePlan plan,
    RenameBatchRecord record,
  ) => MultiRenameResult([
    for (var index = 0; index < plan.entries.length; index++)
      MultiRenameOutcome(
        plan.entries[index],
        !plan.entries[index].changed
            ? MultiRenameStatus.unchanged
            : record.items[index].currentPath == plan.entries[index].targetPath
            ? MultiRenameStatus.renamed
            : record.items[index].error != null
            ? MultiRenameStatus.failed
            : MultiRenameStatus.notRun,
        message: record.items[index].error,
      ),
  ], cancelled: record.state == RenameBatchState.paused);

  void _recordBatchUndo(
    RenameBatchRecord record,
    PanelFileOrigin origin,
    SourceRenameBatchStorage storage,
    ActionHistoryNotifier history,
    RenameBatchService service,
  ) {
    final panel = _panel;
    history.record(
      type: ActionType.rename,
      originalPath: record.items.first.sourcePath,
      newPath: record.items.first.targetPath,
      provider: record.storage.provider,
      metadata: {
        'renameBatchId': record.id,
        'renameBatchCount': record.changedCount,
      },
      isCurrent: () => origin.isCurrent,
      undoAction: () async {
        final latest = await service.store.read(record.id);
        if (latest == null) {
          return const UndoResult.failure(
            'The rename recovery record is missing.',
          );
        }
        final before = {
          for (final item in latest.items) item.sourcePath: item.currentPath,
        };
        try {
          await service.restore(latest, storage);
          return latest.isRestored
              ? UndoResult.success(
                  'Restored ${latest.changedCount} original names.',
                )
              : UndoResult.failure(
                  latest.message ?? 'Restore stopped. Review rename history.',
                );
        } finally {
          if (origin.isCurrent) {
            panel.applyFileListChanges({
              for (final item in latest.items)
                if (before[item.sourcePath] != item.currentPath)
                  before[item.sourcePath]!: item.asFile(
                    storage.paths.basename(item.currentPath),
                    storageId: latest.storage.id,
                  ),
            }, origin: origin);
            await panel.refresh();
          }
        }
      },
    );
  }

  Future<void> _restoreBatch() async {
    final record = _batch;
    if (record == null || _storage == null || _origin?.isCurrent != true) {
      return;
    }
    final before = {
      for (final item in record.items) item.sourcePath: item.currentPath,
    };
    setState(() {
      _processing = true;
      _cancelRequested = false;
      _message = null;
    });
    try {
      await _batchService.restore(
        record,
        _storage!,
        isCancelled: () => _cancelRequested,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (mounted) {
        setState(
          () => _message = record.isRestored
              ? 'Original names restored for ${record.changedCount} items.'
              : record.message,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'Restore stopped: $error');
    } finally {
      if (_origin?.isCurrent == true) {
        _panel.applyFileListChanges({
          for (final item in record.items)
            if (before[item.sourcePath] != item.currentPath)
              before[item.sourcePath]!: item.asFile(
                _paths.basename(item.currentPath),
                storageId: record.storage.id,
              ),
        }, origin: _origin);
        await _panel.refresh();
      }
      if (mounted) {
        setState(() {
          _processing = false;
          if (_executionPlan != null) {
            _result = _resultFor(_executionPlan!, record);
          }
        });
      }
    }
  }

  Future<void> _nextBatch() async {
    final record = _batch;
    if (record == null || _storage == null) return;
    setState(() => _processing = true);
    try {
      final current = <FileItem>[];
      for (final item in record.items) {
        final file = await _storage!.stat(item.currentPath);
        if (file == null) {
          throw StateError('An item no longer exists: ${item.currentPath}');
        }
        current.add(file);
      }
      if (!mounted) return;
      setState(() {
        _files
          ..clear()
          ..addAll(current);
        _excludedPaths.clear();
        _targetNames.clear();
        _steps
          ..clear()
          ..add(const MultiRenameOptions());
        _selectedStep = 0;
        _assignOptions(const MultiRenameOptions());
        _collisions = RenameCollisionPolicy.error;
        _namesChecked = false;
        _existingPaths = {};
        _referenceTime = DateTime.now();
        _executionPlan = null;
        _result = null;
        _batch = null;
        _executionErrors = {};
        _message = null;
        _preset = null;
      });
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _openHistory() async {
    final updated = await showRenameHistoryDialog(context, ref, widget.side);
    if (mounted && updated != null && updated.id == _batch?.id) {
      setState(() {
        _batch = updated;
        if (_executionPlan != null) {
          _result = _resultFor(_executionPlan!, updated);
        }
        _message = updated.isRestored
            ? 'Original names restored.'
            : updated.message;
      });
    }
  }

  Future<void> _exportReport() => showDialog<String>(
    context: context,
    builder: (_) => RenameTextDialog(
      title: context.commanderTr("Rename batch report"),
      instructions: context.commanderTr(
        "A complete record of intended names, confirmed current paths and recovery steps.",
      ),
      initialText: const JsonEncoder.withIndent('  ').convert(_batch!.toJson()),
      submitLabel: context.commanderTr("Close"),
      filename: 'rename-${_batch!.id}.json',
      fileExtensions: const ['json'],
    ),
  );
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
    title: Text(context.commanderTr("Save rename preset")),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 80,
      decoration: InputDecoration(
        labelText: context.commanderTr("Preset name"),
      ),
      onSubmitted: (_) => Navigator.pop(context, _controller.text.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.commanderTr("Cancel")),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: Text(context.commanderTr("Save")),
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
