import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../models/storage_reference.dart';
import '../models/file_search_query.dart';
import '../providers/core_providers.dart';
import '../providers/panel_provider.dart';
import '../providers/transfer_provider.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import '../services/file_selection_pattern.dart';
import '../services/file_operation_profiles.dart';
import '../services/read_only_operation_backend.dart';
import '../services/saved_search_service.dart';
import 'file_operation_conflict_dialog.dart';

/// Returns the completed foreground plan for callers that need to apply a
/// follow-up operation to successful entries. Cancellation/background is null.
Future<FileOperationPlan?> showFileOperationDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files, {
  required FileOperationKind kind,
  PanelFileOrigin? sourceOrigin,
  PanelFileOrigin? destinationOrigin,
  String? destinationPath,
  FileOperationBackend? sourceBackend,
  Map<PanelFileOrigin, List<FileItem>>? sourceGroups,
}) async {
  if (files.isEmpty) return null;
  var groups = sourceGroups;
  if (groups == null && sourceOrigin == null && sourceBackend == null) {
    try {
      groups = ref.read(panelProvider(side)).captureOperationGroups(files);
    } catch (_) {
      /* The single dialog displays the precise validation error. */
    }
  }
  if (groups != null && groups.length > 1) {
    if (sourceBackend != null) {
      throw ArgumentError('A snapshot copy uses one captured source.');
    }
    if (!groups.keys.every((origin) => origin.isCurrent)) {
      throw StateError(
        'An original source disconnected. Copy the items again.',
      );
    }
    PanelFileOrigin destination;
    try {
      destination =
          destinationOrigin ??
          ref
              .read(
                panelProvider(
                  side == PanelSide.local ? PanelSide.remote : PanelSide.local,
                ),
              )
              .captureCurrentOrigin();
    } catch (error) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Choose a destination folder'),
            content: Text(
              'Open a verified destination in the other panel before transferring a mixed collection. $error',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
      return null;
    }
    final protected = [
      for (final group in groups.entries)
        for (final file in group.value)
          FileReference(
            storage: group.key.storageReference,
            path: file.path!,
            objectId: file.uuid,
          ),
    ];
    FileOperationPlan? last;
    var index = 0;
    for (final group in groups.entries) {
      if (!context.mounted) return last;
      index++;
      last = await showDialog<FileOperationPlan>(
        context: context,
        barrierDismissible: false,
        builder: (_) => FileOperationDialog(
          side: side,
          files: group.value,
          kind: kind,
          sourceOrigin: group.key,
          destinationOrigin: destination,
          destinationPath: destinationPath ?? destination.source.currentPath,
          protectedSources: protected,
          allowBackground: false,
          reviewGroup:
              'Account $index of ${groups!.length}: ${ref.read(panelProvider(side)).storageDisplayName(group.key.storageReference)}',
        ),
      );
      if (last == null ||
          last.entries.any(
            (entry) => entry.outcome == FileOperationOutcome.cancelled,
          )) {
        return last;
      }
    }
    if (context.mounted) ref.read(panelProvider(side)).focusList();
    return last;
  }
  sourceOrigin ??= groups?.keys.firstOrNull;
  final result = await showDialog<FileOperationPlan>(
    context: context,
    barrierDismissible: false,
    builder: (_) => FileOperationDialog(
      side: side,
      files: List.unmodifiable(files),
      kind: kind,
      sourceOrigin: sourceOrigin,
      destinationOrigin: destinationOrigin,
      destinationPath: destinationPath,
      sourceBackend: sourceBackend,
    ),
  );
  if (context.mounted) ref.read(panelProvider(side)).focusList();
  return result;
}

class FileOperationDialog extends ConsumerStatefulWidget {
  const FileOperationDialog({
    super.key,
    required this.side,
    required this.files,
    required this.kind,
    this.sourceOrigin,
    this.destinationOrigin,
    this.destinationPath,
    this.sourceBackend,
    this.protectedSources = const [],
    this.allowBackground = true,
    this.reviewGroup,
  });
  final PanelSide side;
  final List<FileItem> files;
  final FileOperationKind kind;
  final PanelFileOrigin? sourceOrigin;
  final PanelFileOrigin? destinationOrigin;
  final String? destinationPath;

  /// Read-only snapshot source, e.g. archive members. Requires [sourceOrigin]
  /// for the original account guard. These copies finish in this dialog.
  final FileOperationBackend? sourceBackend;
  final List<FileReference> protectedSources;
  final bool allowBackground;
  final String? reviewGroup;
  @override
  ConsumerState<FileOperationDialog> createState() =>
      _FileOperationDialogState();
}

class _FileOperationDialogState extends ConsumerState<FileOperationDialog> {
  final _destination = TextEditingController();
  final _relativeBase = TextEditingController();
  final _mask = TextEditingController(text: '*');
  final _nameMask = TextEditingController(text: '*.*');
  final _targetName = TextEditingController();
  final _minimumSize = TextEditingController();
  final _maximumSize = TextEditingController();
  final _modifiedAfter = TextEditingController();
  final _modifiedBefore = TextEditingController();
  final _excludedDirectories = TextEditingController();
  Map<String, FileOperationOptions> _profiles = {};
  FileSearchQuery? _searchCriteria;
  bool _edited = false;
  bool _excludeEmpty = false;
  bool _includeHidden = true;
  bool _native = true;
  bool _preservePermissions = false;
  bool _preserveOwnership = false;
  bool _preserveXattrs = false;
  bool _preserveAcl = false;
  FileOperationControl _control = FileOperationControl();
  final _origins = <PanelSide, PanelFileOrigin>{};
  late final PanelNotifier _panel;
  PanelFileOrigin? _sourceOrigin;
  FileOperationBackend? _capturedSourceBackend;
  PanelSide? _destinationSide;
  FileConflictPolicy _fileConflict = FileConflictPolicy.ask;
  DirectoryConflictPolicy _directoryConflict = DirectoryConflictPolicy.merge;
  bool _recursive = true;
  bool _relative = false;
  bool _preserveTime = false;
  bool _verify = false;
  bool _stopOnError = true;
  bool _copyLinks = false;
  bool _regex = false;
  bool _caseSensitive = false;
  bool _matchPath = false;
  bool _preparing = false;
  bool _running = false;
  bool _finished = false;
  String? _error;
  String? _current;
  int _bytes = 0;
  int? _total;
  FileOperationPlan? _plan;

  String get _verb => widget.kind == FileOperationKind.copy ? 'Copy' : 'Move';
  bool get _busy => _preparing || _running;

  @override
  void initState() {
    super.initState();
    _panel = ref.read(panelProvider(widget.side));
    try {
      if (widget.sourceBackend != null &&
          (widget.sourceOrigin == null ||
              widget.kind != FileOperationKind.copy)) {
        throw StateError(
          'A snapshot copy requires its captured source account and Copy mode.',
        );
      }
      _sourceOrigin =
          widget.sourceOrigin ?? _panel.captureOperationOrigin(widget.files);
      _capturedSourceBackend = widget.sourceBackend == null
          ? _backend(_sourceOrigin!)
          : ReadOnlyOperationBackend(
              widget.sourceBackend!,
              isAvailable: () => _sourceOrigin!.isCurrent,
            );
      _origins[widget.side] = _sourceOrigin!;
      final opposite = widget.side == PanelSide.local
          ? PanelSide.remote
          : PanelSide.local;
      try {
        _origins[opposite] =
            widget.destinationOrigin ??
            ref.read(panelProvider(opposite)).captureCurrentOrigin();
      } catch (_) {
        /* A disconnected opposite panel is not a destination. */
      }
      _destinationSide = _origins.containsKey(opposite)
          ? opposite
          : widget.side;
      _destination.text =
          widget.destinationPath ??
          _origins[_destinationSide]!.source.currentPath;
      final backend = _capturedSourceBackend!;
      var base = backend.paths.dirname(widget.files.first.path!);
      while (widget.files.any(
        (file) => !backend.paths.isWithin(base, file.path!),
      )) {
        final parent = backend.paths.dirname(base);
        if (parent == base) break;
        base = parent;
      }
      _relativeBase.text = base;
      _loadProfiles();
    } catch (error) {
      _error = error.toString();
    }
  }

  FileOperationBackend _backend(PanelFileOrigin origin) => fileOperationBackend(
    source: origin.source,
    local: ref.read(localFileServiceProvider),
    isCurrent: () => origin.isCurrent,
  );

  @override
  void dispose() {
    _destination.dispose();
    _relativeBase.dispose();
    _mask.dispose();
    for (final controller in [
      _nameMask,
      _targetName,
      _minimumSize,
      _maximumSize,
      _modifiedAfter,
      _modifiedBefore,
      _excludedDirectories,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _change(VoidCallback change) {
    if (_busy) return;
    setState(() {
      _edited = true;
      change();
      _plan = null;
      _finished = false;
      _error = null;
    });
  }

  Future<void> _preview() async {
    final origin = _sourceOrigin;
    final destinationOrigin = _origins[_destinationSide];
    if (origin == null || destinationOrigin == null) return;
    setState(() {
      _control = FileOperationControl();
      _preparing = true;
      _error = null;
      _plan = null;
      _finished = false;
    });
    try {
      final plan = await const FileOperationService().prepare(
        files: widget.files,
        source: _capturedSourceBackend!,
        destination: _backend(destinationOrigin),
        targetDirectory: _destination.text,
        control: _control,
        options: _options(),
        protectedDestinationPaths: [
          for (final file in widget.protectedSources)
            if (file.storage == destinationOrigin.storageReference) file.path,
        ],
      );
      if (mounted) setState(() => _plan = plan);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  FileOperationOptions _options() => FileOperationOptions(
    kind: widget.kind,
    fileConflict: _fileConflict,
    directoryConflict: _directoryConflict,
    recursive: _recursive,
    preserveRelativePaths: _relative,
    relativeBase: _relativeBase.text,
    preserveModified: _preserveTime,
    verifyContents: _verify,
    stopOnError: _stopOnError,
    copySymbolicLinks: _copyLinks,
    preservePermissions: _preservePermissions,
    preserveOwnership: _preserveOwnership,
    preserveExtendedAttributes: _preserveXattrs,
    preserveAcl: _preserveAcl,
    destinationName: _targetName.text.trim().isEmpty
        ? null
        : _targetName.text.trim(),
    destinationMask: _nameMask.text,
    minimumSize: _minimumSize.text.trim().isEmpty
        ? null
        : int.parse(_minimumSize.text.trim()),
    maximumSize: _maximumSize.text.trim().isEmpty
        ? null
        : int.parse(_maximumSize.text.trim()),
    modifiedAfter: _modifiedAfter.text.trim().isEmpty
        ? null
        : DateTime.parse(_modifiedAfter.text.trim()),
    modifiedBefore: _modifiedBefore.text.trim().isEmpty
        ? null
        : DateTime.parse(_modifiedBefore.text.trim()),
    excludedDirectories: _excludedDirectories.text.trim().isEmpty
        ? null
        : FileSelectionPattern(
            _excludedDirectories.text,
            matchFullPath: _matchPath,
          ),
    excludeEmptyDirectories: _excludeEmpty,
    includeHidden: _includeHidden,
    preferNative: _native,
    searchCriteria: _searchCriteria,
    pattern: FileSelectionPattern(
      _mask.text,
      mode: _regex ? FilePatternMode.regex : FilePatternMode.wildcard,
      caseSensitive: _caseSensitive,
      matchFullPath: _matchPath,
    ),
  );

  void _applyProfile(FileOperationOptions options) {
    _fileConflict = options.fileConflict;
    _directoryConflict = options.directoryConflict;
    _recursive = options.recursive;
    _relative = options.preserveRelativePaths;
    _preserveTime = options.preserveModified;
    _preservePermissions = options.preservePermissions;
    _preserveOwnership = options.preserveOwnership;
    _preserveXattrs = options.preserveExtendedAttributes;
    _preserveAcl = options.preserveAcl;
    _verify = options.verifyContents;
    _stopOnError = options.stopOnError;
    _copyLinks = options.copySymbolicLinks;
    _mask.text = options.pattern?.expression ?? '*';
    _regex = options.pattern?.mode == FilePatternMode.regex;
    _caseSensitive = options.pattern?.caseSensitive ?? false;
    _matchPath = options.pattern?.matchFullPath ?? false;
    _nameMask.text = options.destinationMask;
    _minimumSize.text = options.minimumSize?.toString() ?? '';
    _maximumSize.text = options.maximumSize?.toString() ?? '';
    _modifiedAfter.text = options.modifiedAfter?.toIso8601String() ?? '';
    _modifiedBefore.text = options.modifiedBefore?.toIso8601String() ?? '';
    _excludedDirectories.text = options.excludedDirectories?.expression ?? '';
    _excludeEmpty = options.excludeEmptyDirectories;
    _includeHidden = options.includeHidden;
    _native = options.preferNative;
    _searchCriteria = options.searchCriteria;
  }

  Future<void> _chooseSearchCriteria() async {
    try {
      final saved = await SavedSearchService().getAll(strict: true);
      if (!mounted) return;
      final selected = await showDialog<SavedSearch>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Saved search criteria'),
          children: [
            if (saved.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Save criteria in Search or Select by pattern first.',
                ),
              ),
            for (final item in saved)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, item),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text(item.name), Text(item.filterSummary)],
                  ),
                ),
              ),
          ],
        ),
      );
      if (!mounted || selected == null) return;
      final query =
          selected.settings ??
          FileSearchQuery(
            namePattern: selected.query.isEmpty ? '*' : selected.query,
            extensions: selected.filterByType,
            minSize: selected.filterByMinSize,
            maxSize: selected.filterByMaxSize,
            modifiedAfter: selected.filterByDateAfter,
            modifiedBefore: selected.filterByDateBefore,
          );
      FileOperationOptions(searchCriteria: query).validateSearchCriteria();
      _change(() => _searchCriteria = query);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _loadProfiles() async {
    try {
      final profiles = await FileOperationProfiles().load();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        final defaults = profiles['@default:${widget.kind.name}'];
        if (!_edited && !_busy && defaults != null) _applyProfile(defaults);
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Transfer defaults could not be loaded: $error',
        );
      }
    }
  }

  Future<void> _saveProfile({bool defaults = false}) async {
    try {
      final options = _options();
      String? name = '@default:${widget.kind.name}';
      if (!defaults) {
        final controller = TextEditingController();
        name = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Save transfer profile'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Profile name'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Save'),
              ),
            ],
          ),
        );
        // The route may still be animating; dispose after its widgets detach.
        Future<void>.delayed(
          const Duration(milliseconds: 500),
          controller.dispose,
        );
      }
      if (name == null) return;
      await FileOperationProfiles().save(name, options);
      final profiles = await FileOperationProfiles().load();
      if (mounted) setState(() => _profiles = profiles);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<FileConflictResolution> _resolve(
    FileOperationEntry entry,
    FileItem existing,
  ) {
    if (!mounted) {
      return Future.value(
        const FileConflictResolution(FileConflictDecision.cancel),
      );
    }
    return showFileOperationConflict(
      context,
      entry: entry,
      existing: existing,
      source: _plan!.source,
      destination: _plan!.destination,
    );
  }

  Future<void> _start({bool background = false}) async {
    if (background &&
        (widget.sourceBackend != null || !widget.allowBackground)) {
      return;
    }
    final plan = _plan;
    final sourceOrigin = _sourceOrigin;
    if (plan == null || !plan.canExecute || sourceOrigin == null) return;
    final notifier = ref.read(transferProvider);
    final targetPanel = ref.read(panelProvider(_destinationSide!));
    setState(() {
      _running = true;
      _error = null;
    });
    final future = notifier.runFileOperation(
      plan,
      control: _control,
      resolveDetailedConflict: background ? null : _resolve,
      onProgress: (entry, bytes, total) {
        if (mounted) {
          setState(() {
            _current = entry.source.path;
            _bytes = bytes;
            _total = total;
          });
        }
      },
      onEntryComplete: (entry) {
        if (entry.outcome == FileOperationOutcome.moved) {
          _panel.applyFileListChanges({
            entry.source.path!: null,
          }, origin: sourceOrigin);
        }
        if (mounted) setState(() {});
      },
    );
    if (background && mounted) Navigator.pop(context);
    try {
      await future;
      await _panel.refresh();
      if (!identical(_panel, targetPanel)) await targetPanel.refresh();
      if (mounted) {
        setState(() {
          _running = false;
          _finished = true;
          _current = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _running = false;
          _finished = true;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final destinationOrigin = _origins[_destinationSide];
    final destinationBackend = destinationOrigin == null
        ? null
        : _backend(destinationOrigin);
    final sourceBackend = _capturedSourceBackend;
    final supportsTime = destinationBackend?.supportsModifiedTime ?? false;
    final supportsLinks =
        (destinationBackend?.supportsSymbolicLinks ?? false) &&
        (sourceBackend?.supportsSymbolicLinks ?? false);
    final plan = _plan;
    final completed =
        plan?.entries.where((entry) => entry.completed).length ?? 0;
    final failed = plan?.entries.where((entry) => entry.failed).length ?? 0;
    final skipped =
        plan?.entries
            .where(
              (entry) =>
                  entry.outcome == FileOperationOutcome.skipped ||
                  entry.outcome == FileOperationOutcome.filtered,
            )
            .length ??
        0;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text('$_verb ${widget.files.length} selected item(s)'),
        content: SizedBox(
          width: math.min(920, math.max(280, size.width - 96)),
          height: math.min(700, math.max(240, size.height - 190)),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.reviewGroup != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      widget.reviewGroup!,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                if (_sourceOrigin != null)
                  Text(
                    'From ${sourceBackend?.label ?? _sourceOrigin!.source.displayName} · original item paths',
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<PanelSide>(
                  isExpanded: true,
                  initialValue: _destinationSide,
                  decoration: const InputDecoration(
                    labelText: 'Destination storage',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _origins.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(
                            '${entry.key == widget.side ? 'This panel' : 'Opposite panel'} · ${entry.value.source.displayName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (side) => _change(() {
                          _destinationSide = side;
                          _destination.text =
                              _origins[side]!.source.currentPath;
                          _preserveTime = false;
                          _copyLinks = false;
                        }),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _destination,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Destination directory',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _change(() {}),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_profiles.keys.any(
                      (name) => !name.startsWith('@default:'),
                    ))
                      PopupMenuButton<String>(
                        tooltip: 'Load transfer profile',
                        onSelected: (name) =>
                            _change(() => _applyProfile(_profiles[name]!)),
                        itemBuilder: (_) => _profiles.keys
                            .where((name) => !name.startsWith('@default:'))
                            .map(
                              (name) =>
                                  PopupMenuItem(value: name, child: Text(name)),
                            )
                            .toList(),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('Load profile'),
                        ),
                      ),
                    TextButton(
                      onPressed: _busy ? null : () => _saveProfile(),
                      child: const Text('Save profile'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _saveProfile(defaults: true),
                      child: const Text('Save as defaults'),
                    ),
                  ],
                ),
                if (widget.files.length == 1)
                  TextField(
                    controller: _targetName,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Destination item name (optional)',
                      helperText: 'A new name for the selected file or folder.',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _change(() {}),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameMask,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Destination filename mask',
                    helperText: '*.* keeps names · *.bak changes extension · *.*.bak appends · [N]_[C:000].[E]',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _change(() {}),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 270,
                      child: DropdownButtonFormField<FileConflictPolicy>(
                        isExpanded: true,
                        initialValue: _fileConflict,
                        decoration: const InputDecoration(
                          labelText: 'Existing files',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: FileConflictPolicy.ask,
                            child: Text(
                              'Ask for each conflict',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: FileConflictPolicy.skip,
                            child: Text(
                              'Skip existing files',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: FileConflictPolicy.replace,
                            child: Text(
                              'Replace existing files',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: FileConflictPolicy.replaceIfNewer,
                            child: Text(
                              'Replace only if source is newer',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: FileConflictPolicy.replaceIfLarger,
                            child: Text(
                              'Replace if source is larger',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: FileConflictPolicy.replaceIfSmaller,
                            child: Text(
                              'Replace if source is smaller',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: FileConflictPolicy.resumeVerified,
                            child: Text(
                              'Resume after prefix verification',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: FileConflictPolicy.append,
                            child: Text(
                              'Append source to destination',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: FileConflictPolicy.keepBoth,
                            child: Text(
                              'Keep both (number new copies)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => _change(() => _fileConflict = value!),
                      ),
                    ),
                    SizedBox(
                      width: 245,
                      child: DropdownButtonFormField<DirectoryConflictPolicy>(
                        isExpanded: true,
                        initialValue: _directoryConflict,
                        decoration: const InputDecoration(
                          labelText: 'Existing folders',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: DirectoryConflictPolicy.merge,
                            child: Text(
                              'Merge contents',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: DirectoryConflictPolicy.skip,
                            child: Text(
                              'Skip whole folder',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: DirectoryConflictPolicy.ask,
                            child: Text(
                              'Ask for each folder',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) =>
                                  _change(() => _directoryConflict = value!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _chooseSearchCriteria,
                      icon: const Icon(Icons.saved_search),
                      label: const Text('Use saved search criteria'),
                    ),
                    if (_searchCriteria != null)
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _change(() => _searchCriteria = null),
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear saved criteria'),
                      ),
                  ],
                ),
                if (_searchCriteria != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Additional criteria: ${_searchCriteria!.nameMode.name} '
                      '${_searchCriteria!.namePattern}'
                      '${_searchCriteria!.extensions.isEmpty ? "" : " · types: ${_searchCriteria!.extensions.join(", ")}"}. '
                      'Applied together with the filters below. Selected items and Include subfolders define the scope.',
                    ),
                  ),
                TextField(
                  controller: _mask,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'File filter',
                    hintText: '*.jpg;*.png|thumb*',
                    helperText: 'Filters files within selected folders. Excluded files stay in the source.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _change(() {}),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    _field(_minimumSize, 'Minimum size (bytes)', width: 190),
                    _field(_maximumSize, 'Maximum size (bytes)', width: 190),
                    _field(
                      _modifiedAfter,
                      'Modified on/after (ISO date)',
                      width: 250,
                    ),
                    _field(
                      _modifiedBefore,
                      'Modified on/before (ISO date)',
                      width: 250,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _field(
                  _excludedDirectories,
                  'Exclude directories (wildcards; optional)',
                  width: 800,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    _toggle(
                      'Exclude empty folders after filtering',
                      _excludeEmpty,
                      (v) => _excludeEmpty = v,
                    ),
                    _toggle(
                      'Include hidden names',
                      _includeHidden,
                      (v) => _includeHidden = v,
                    ),
                    _toggle(
                      'Use native/server operations when supported',
                      _native,
                      (v) => _native = v,
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    _toggle(
                      'Regular expression',
                      _regex,
                      (value) => _regex = value,
                    ),
                    _toggle(
                      'Case sensitive',
                      _caseSensitive,
                      (value) => _caseSensitive = value,
                    ),
                    _toggle(
                      'Match full source path',
                      _matchPath,
                      (value) => _matchPath = value,
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    _toggle(
                      'Include subfolders',
                      _recursive,
                      (value) => _recursive = value,
                    ),
                    _toggle(
                      'Preserve relative paths',
                      _relative,
                      (value) => _relative = value,
                    ),
                    _toggle(
                      'Stop on first error',
                      _stopOnError,
                      (value) => _stopOnError = value,
                    ),
                  ],
                ),
                if (_relative)
                  TextField(
                    controller: _relativeBase,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Relative to source directory',
                      helperText:
                          'All selected paths must be below this directory.',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _change(() {}),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    _toggle(
                      'Verify contents (SHA-256)',
                      _verify,
                      (value) => _verify = value,
                    ),
                    _toggle(
                      'Preserve file modification times',
                      _preserveTime,
                      (value) => _preserveTime = value,
                      enabled: supportsTime,
                    ),
                    _toggle(
                      'Copy symbolic links as links',
                      _copyLinks,
                      (value) => _copyLinks = value,
                      enabled: supportsLinks,
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    _toggle(
                      'Preserve permissions',
                      _preservePermissions,
                      (v) => _preservePermissions = v,
                      enabled:
                          (sourceBackend?.capabilities.permissions ?? false) &&
                          (destinationBackend?.capabilities.permissions ??
                              false),
                    ),
                    _toggle(
                      'Preserve owner/group',
                      _preserveOwnership,
                      (v) => _preserveOwnership = v,
                      enabled:
                          (sourceBackend?.capabilities.ownership ?? false) &&
                          (destinationBackend?.capabilities.ownership ?? false),
                    ),
                    _toggle(
                      'Preserve extended attributes',
                      _preserveXattrs,
                      (v) => _preserveXattrs = v,
                      enabled:
                          (sourceBackend?.capabilities.extendedAttributes ??
                              false) &&
                          (destinationBackend
                                  ?.capabilities
                                  .extendedAttributes ??
                              false),
                    ),
                    _toggle(
                      'Preserve ACL',
                      _preserveAcl,
                      (v) => _preserveAcl = v,
                      enabled:
                          (sourceBackend?.capabilities.accessControlLists ??
                              false) &&
                          (destinationBackend
                                  ?.capabilities
                                  .accessControlLists ??
                              false),
                    ),
                  ],
                ),
                Text(
                  'Links are never followed. SHA-256 verification reads both copies and can add cloud traffic.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (!supportsTime)
                  Text(
                    'The destination does not expose modification-time preservation.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (widget.kind == FileOperationKind.move &&
                        sourceBackend is! LocalOperationBackend ||
                    (widget.kind == FileOperationKind.move &&
                        !(sourceBackend?.supportsSymbolicLinks ?? false)))
                  const Text(
                    'Empty source folders are retained where storage lacks a safe empty-folder delete.',
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SelectableText(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_preparing)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  ),
                if (plan != null) ...[
                  const Divider(height: 24),
                  Text(
                    _finished
                        ? '$completed completed · $skipped skipped/filtered · $failed failed'
                        : '${plan.fileCount} files in preview · ${plan.entries.length} total rows',
                  ),
                  for (final error in plan.errors)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 230,
                    child: ListView.builder(
                      itemCount: plan.entries.length,
                      itemBuilder: (context, index) {
                        final entry = plan.entries[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            entry.failed
                                ? Icons.error_outline
                                : entry.source.isFolder
                                ? Icons.folder_outlined
                                : Icons.insert_drive_file_outlined,
                          ),
                          title: Text(
                            '${entry.source.path} → ${entry.destination}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            entry.message ??
                                (entry.outcome != FileOperationOutcome.pending
                                    ? entry.outcome.name
                                    : entry.existing == null
                                    ? 'New destination'
                                    : 'Destination exists'),
                            style: TextStyle(
                              color: entry.failed
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (_running) ...[
                  LinearProgressIndicator(
                    value: _total != null && _total! > 0
                        ? (_bytes / _total!).clamp(0, 1)
                        : null,
                  ),
                  Text(
                    _current ?? 'Waiting for the transfer queue…',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (_running) ...[
            TextButton(
              onPressed: () => setState(() {
                _control.isPaused ? _control.resume() : _control.pause();
              }),
              child: Text(_control.isPaused ? 'Resume' : 'Pause'),
            ),
            TextButton(
              onPressed: () => setState(_control.cancel),
              child: const Text('Cancel operation'),
            ),
          ] else ...[
            TextButton(
              onPressed: _preparing
                  ? null
                  : () => Navigator.pop(context, _finished ? _plan : null),
              child: Text(_finished ? 'Close' : 'Cancel'),
            ),
            OutlinedButton(
              onPressed: _preparing || _sourceOrigin == null ? null : _preview,
              child: const Text('Preview'),
            ),
            if (widget.allowBackground &&
                widget.sourceBackend == null &&
                _fileConflict != FileConflictPolicy.ask &&
                _directoryConflict != DirectoryConflictPolicy.ask)
              TextButton(
                onPressed:
                    !_finished && (plan?.canExecute ?? false) && !_preparing
                    ? () => _start(background: true)
                    : null,
                child: const Text('Queue in background'),
              ),
            FilledButton(
              onPressed:
                  !_finished && (plan?.canExecute ?? false) && !_preparing
                  ? _start
                  : null,
              child: Text('Start $_verb'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    required double width,
  }) => SizedBox(
    width: width,
    child: TextField(
      controller: controller,
      enabled: !_busy,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (_) => _change(() {}),
    ),
  );

  Widget _toggle(
    String text,
    bool value,
    ValueChanged<bool> change, {
    bool enabled = true,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Checkbox(
        value: value,
        onChanged: _busy || !enabled
            ? null
            : (value) => _change(() => change(value!)),
      ),
      Flexible(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
    ],
  );
}
