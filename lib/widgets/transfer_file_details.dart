import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/commander_strings.dart';
import '../l10n/provider_operation_strings.dart';
import '../models/operation_progress.dart';
import '../models/transfer_job.dart';
import '../services/file_operation_options.dart';
import '../utils/formatters.dart' show formatBytes;

enum _FileFilter { all, attention, unfinished, completed, skipped }

enum _FileState {
  pending,
  running,
  paused,
  attention,
  completed,
  skipped,
  cancelled,
}

_FileState _stateOf(FileProgress file, OperationProgress operation) {
  // A copied payload can still need metadata repair. Such a row must remain
  // visible among unfinished work even when its byte counter is complete.
  if (file.error != null ||
      file.errorCause != null ||
      const {
        'failed',
        'metadataFailed',
        'needsDecision',
        'Waiting for a conflict decision',
      }.contains(file.statusLabel)) {
    return _FileState.attention;
  }
  if (file.isSkipped) return _FileState.skipped;
  if (file.isComplete ||
      const {
        'copied',
        'moved',
        'directoryCreated',
      }.contains(file.statusLabel)) {
    return _FileState.completed;
  }
  if (file.statusLabel == 'cancelled' || operation.isCancelled) {
    return _FileState.cancelled;
  }
  if (operation.currentFilePath == file.path && operation.isActive) {
    return operation.isPaused ? _FileState.paused : _FileState.running;
  }
  return _FileState.pending;
}

bool _matchesState(_FileState state, _FileFilter filter) => switch (filter) {
  _FileFilter.all => true,
  _FileFilter.attention => state == _FileState.attention,
  _FileFilter.unfinished =>
    state != _FileState.completed && state != _FileState.skipped,
  _FileFilter.completed => state == _FileState.completed,
  _FileFilter.skipped => state == _FileState.skipped,
};

String _filterLabel(_FileFilter filter) => switch (filter) {
  _FileFilter.all => 'All',
  _FileFilter.attention => 'Attention',
  _FileFilter.unfinished => 'Unfinished',
  _FileFilter.completed => 'Completed',
  _FileFilter.skipped => 'Skipped',
};

class _Member {
  const _Member(this.index, this.file, this.destinations, this.state);
  final int index;
  final FileProgress file;
  final List<String> destinations;
  final _FileState state;

  bool matches(String query) =>
      query.isEmpty ||
      [
        file.name,
        file.path,
        ...destinations,
      ].any((value) => value.toLowerCase().contains(query));
}

class _Detail {
  const _Detail(this.label, this.value, {this.isPath = false});
  final String label;
  final String value;
  final bool isPath;
}

/// Read-only inspection of a batch. Recovery and operation authority remain
/// with the reviewed transfer plan; filtering never changes its member list.
class TransferFileDetails extends StatefulWidget {
  const TransferFileDetails({
    super.key,
    required this.operation,
    this.savedEntries = const [],
    this.initialQuery = '',
  });

  final OperationProgress operation;
  final List<TransferEntryRecord> savedEntries;
  final String initialQuery;

  @override
  State<TransferFileDetails> createState() => _TransferFileDetailsState();
}

class _TransferFileDetailsState extends State<TransferFileDetails> {
  late final TextEditingController _search;
  _FileFilter _filter = _FileFilter.all;
  bool _followsQueueSearch = true;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: _queueQuery());
  }

  @override
  void didUpdateWidget(TransferFileDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.operation.id != widget.operation.id) {
      _filter = _FileFilter.all;
      _followsQueueSearch = true;
      _search.text = _queueQuery();
    } else if (_followsQueueSearch) {
      final query = _queueQuery();
      if (_search.text != query) _search.text = query;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_Member> _members() {
    final destinations = <String, Set<String>>{};
    for (final entry in widget.savedEntries) {
      final source = entry.source.path;
      if (source != null && entry.destination.isNotEmpty) {
        (destinations[source] ??= {}).add(entry.destination);
      }
    }
    return [
      for (final (index, file)
          in (widget.operation.files ?? const <FileProgress>[]).indexed)
        _Member(
          index,
          file,
          destinations[file.path]?.toList(growable: false) ?? const [],
          _stateOf(file, widget.operation),
        ),
    ];
  }

  String _queueQuery() {
    final query = widget.initialQuery.trim().toLowerCase();
    // A queue query may match the job title or account rather than a member.
    // Only narrow the files when the query actually identifies a member.
    return query.isNotEmpty && _members().any((member) => member.matches(query))
        ? widget.initialQuery
        : '';
  }

  void _clearFilters() => setState(() {
    _followsQueueSearch = false;
    _filter = _FileFilter.all;
    _search.clear();
  });

  @override
  Widget build(BuildContext context) {
    final members = _members();
    final query = _search.text.trim().toLowerCase();
    final counts = {for (final filter in _FileFilter.values) filter: 0};
    final visible = <_Member>[];
    for (final member in members) {
      if (!member.matches(query)) continue;
      counts[_FileFilter.all] = counts[_FileFilter.all]! + 1;
      if (member.state == _FileState.attention) {
        counts[_FileFilter.attention] = counts[_FileFilter.attention]! + 1;
      }
      final group = switch (member.state) {
        _FileState.completed => _FileFilter.completed,
        _FileState.skipped => _FileFilter.skipped,
        _ => _FileFilter.unfinished,
      };
      counts[group] = counts[group]! + 1;
      if (_matchesState(member.state, _filter)) visible.add(member);
    }
    final id = widget.operation.id;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: ValueKey('queue-file-search-$id'),
            controller: _search,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              labelText: context.commanderTr('Search files or paths'),
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: context.commanderTr('Clear search'),
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        _followsQueueSearch = false;
                        _search.clear();
                      }),
                    ),
            ),
            onChanged: (_) => setState(() => _followsQueueSearch = false),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final filter in _FileFilter.values)
                ChoiceChip(
                  key: ValueKey('queue-file-filter-$id-${filter.name}'),
                  selected: filter == _filter,
                  label: Text(
                    '${context.commanderTr(_filterLabel(filter))} '
                    '(${counts[filter]})',
                  ),
                  onSelected: (_) => setState(() => _filter = filter),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            context.commanderTr('{0} of {1} items', [
              visible.length,
              members.length,
            ]),
            key: ValueKey('queue-file-count-$id'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(context.commanderTr('No files match this view')),
                  TextButton(
                    onPressed: _clearFilters,
                    child: Text(context.commanderTr('Clear filters')),
                  ),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                key: ValueKey('queue-files-$id'),
                shrinkWrap: true,
                primary: false,
                itemCount: visible.length,
                itemBuilder: (context, index) =>
                    _buildMember(context, visible[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMember(BuildContext context, _Member member) {
    final file = member.file;
    final theme = Theme.of(context);
    final outcome = FileOperationOutcome.values
        .where((value) => value.name == file.statusLabel)
        .firstOrNull;
    final showOutcome =
        outcome != null &&
        outcome != FileOperationOutcome.pending &&
        (member.state != _FileState.attention ||
            const {
              FileOperationOutcome.failed,
              FileOperationOutcome.metadataFailed,
              FileOperationOutcome.needsDecision,
            }.contains(outcome));
    final storedStatus = switch (file.statusLabel) {
      'Waiting for a conflict decision' => 'Waiting for a conflict decision',
      'Not started (awaiting conflict decision)' =>
        'Not started (awaiting conflict decision)',
      _ => null,
    };
    final status = context.commanderTr(
      storedStatus ??
          (showOutcome
              ? CommanderStrings.labelForEnum(outcome!)
              : switch (member.state) {
                  _FileState.pending => 'Pending',
                  _FileState.running => 'Running',
                  _FileState.paused => 'Paused',
                  _FileState.attention => 'Needs review',
                  _FileState.completed => 'Completed',
                  _FileState.skipped => 'Skipped',
                  _FileState.cancelled => 'Cancelled',
                }),
    );
    final error = file.errorCause == null
        ? file.error
        : localizedKnownProviderError(context, file.errorCause!) ??
              file.error ??
              '${file.errorCause}';
    final color = member.state == _FileState.attention
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    final paths = [file.path, ...member.destinations].join(' → ');
    final details = <_Detail>[
      _Detail(context.commanderTr('Name'), file.name),
      _Detail(context.commanderTr('Source'), file.path, isPath: true),
      for (final destination in member.destinations)
        _Detail(context.commanderTr('Destination'), destination, isPath: true),
      _Detail(context.commanderTr('Status'), status),
      _Detail(context.commanderTr('Size'), formatBytes(file.size)),
      if (error != null) _Detail(context.commanderTr('Error'), error),
    ];
    void openDetails() => _showDetails(context, details);
    return Semantics(
      key: ValueKey('queue-file-${widget.operation.id}-${member.index}'),
      container: true,
      button: true,
      label: details
          .map((entry) => '${entry.label}: ${entry.value}')
          .join('\n'),
      hint: context.commanderTr('Show file details'),
      onTap: openDetails,
      child: InkWell(
        excludeFromSemantics: true,
        onTap: openDetails,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  switch (member.state) {
                    _FileState.attention => Icons.error_outline,
                    _FileState.completed => Icons.check_circle_outline,
                    _FileState.skipped => Icons.skip_next,
                    _FileState.cancelled => Icons.cancel_outlined,
                    _FileState.paused => Icons.pause_circle_outline,
                    _FileState.running => Icons.sync,
                    _FileState.pending => Icons.pending_outlined,
                  },
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Tooltip(
                        message: paths,
                        child: Text(
                          paths,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Text(
                        '$status · ${formatBytes(file.size)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: color,
                        ),
                      ),
                      if (error != null)
                        Tooltip(
                          message: error,
                          child: Text(
                            error,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDetails(BuildContext context, List<_Detail> details) async {
    final copyText = details
        .map((entry) => '${entry.label}: ${entry.value}')
        .join('\n');
    var copying = false;
    var copied = false;
    String? copyError;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(context.commanderTr('File details')),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final detail in details) ...[
                    Text(
                      detail.label,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    SelectableText(
                      detail.value,
                      textDirection: detail.isPath ? TextDirection.ltr : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (copyError != null)
                    Text(
                      copyError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: copying
                  ? null
                  : () async {
                      setState(() {
                        copying = true;
                        copyError = null;
                      });
                      try {
                        await Clipboard.setData(ClipboardData(text: copyText));
                        if (context.mounted) setState(() => copied = true);
                      } catch (error) {
                        if (context.mounted)
                          setState(
                            () => copyError = context.commanderTr(
                              'Could not copy details: {0}',
                              [error],
                            ),
                          );
                      } finally {
                        if (context.mounted) setState(() => copying = false);
                      }
                    },
              icon: Icon(copied ? Icons.check : Icons.copy),
              label: Text(
                context.commanderTr(copied ? 'Copied' : 'Copy details'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.commanderTr('Close')),
            ),
          ],
        ),
      ),
    );
  }
}
