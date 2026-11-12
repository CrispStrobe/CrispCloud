import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/archive_member_move_strings.dart';
import '../models/file_item.dart';
import '../services/archive_workspace.dart';

/// Captures one workspace revision and selection before opening the picker.
/// Confirmation changes only that draft; the normal archive review/save owns
/// physical publication. Cancellation never changes the draft.
Future<ArchiveMemberMoveResult?> showArchiveMemberMoveDialog(
  BuildContext context, {
  required ArchiveWorkspace workspace,
  required List<FileItem> members,
  String initialDirectory = '/',
}) {
  final captured = _CapturedMove(workspace, members);
  return showDialog<ArchiveMemberMoveResult>(
    context: context,
    builder: (_) => _ArchiveMemberMoveDialog(
      captured: captured,
      initialDirectory: initialDirectory,
    ),
  );
}

class _CapturedMove {
  _CapturedMove(this.workspace, List<FileItem> members)
    : revision = workspace.revision,
      outerRevision = workspace.outermost.revision,
      paths = List.unmodifiable(members.map((member) => member.path!)),
      names = List.unmodifiable(members.map((member) => member.name)),
      directories = Set.unmodifiable(
        members
            .where((member) => member.isFolder)
            .map((member) => _absolute(member.path!)),
      );

  final ArchiveWorkspace workspace;
  final int revision;
  final int outerRevision;
  final List<String> paths;
  final List<String> names;
  final Set<String> directories;

  bool get isCurrent =>
      workspace.isCurrent &&
      workspace.revision == revision &&
      workspace.outermost.revision == outerRevision;

  bool blocks(String directory) => directories.any(
    (source) => directory == source || directory.startsWith('$source/'),
  );
}

String _absolute(String path) =>
    path == '/' ? '/' : '/${path.replaceAll(RegExp(r'^/+|/+$'), '')}';

class _ArchiveMemberMoveDialog extends StatefulWidget {
  const _ArchiveMemberMoveDialog({
    required this.captured,
    required this.initialDirectory,
  });
  final _CapturedMove captured;
  final String initialDirectory;

  @override
  State<_ArchiveMemberMoveDialog> createState() =>
      _ArchiveMemberMoveDialogState();
}

class _ArchiveMemberMoveDialogState extends State<_ArchiveMemberMoveDialog> {
  late String _directory;
  ArchiveMemberMoveConflict _conflict = ArchiveMemberMoveConflict.fail;
  String? _error;

  @override
  void initState() {
    super.initState();
    _directory = _absolute(widget.initialDirectory);
  }

  String text(String key, [List<Object> values = const []]) =>
      archiveMemberMoveText(context, key, values);

  void _navigate(String directory) {
    if (!widget.captured.isCurrent) {
      setState(() {});
      return;
    }
    if (widget.captured.blocks(directory)) return;
    setState(() {
      _directory = directory;
      _error = null;
    });
  }

  void _stage() {
    final captured = widget.captured;
    // There is no await between this guard and the single draft mutation.
    if (!captured.isCurrent) {
      setState(() {});
      return;
    }
    try {
      final result = captured.workspace.moveMembers(
        captured.paths,
        _directory,
        conflict: _conflict,
      );
      Navigator.pop(context, result);
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final captured = widget.captured;
    final current = captured.isCurrent;
    final supported = captured.workspace.canMoveMembers;
    final directories = current
        ? captured.workspace
              .list(_directory)
              .where((file) => file.isFolder)
              .toList()
        : <FileItem>[];
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      child: SizedBox(
        width: math.min(640, size.width * .94),
        height: size.height * .86,
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                key: const ValueKey('archive-member-move-scroll'),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            text('title'),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          Text(text('instructions')),
                          const SizedBox(height: 12),
                          Text(
                            text('selection', [captured.names.length]),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          for (final name in captured.names.take(8))
                            Text(name, overflow: TextOverflow.ellipsis),
                          if (captured.names.length > 8)
                            Text(text('more', [captured.names.length - 8])),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<ArchiveMemberMoveConflict>(
                            key: const ValueKey('archive-member-move-conflict'),
                            initialValue: _conflict,
                            isExpanded: true,
                            itemHeight: null,
                            decoration: InputDecoration(
                              labelText: text('conflicts'),
                              border: const OutlineInputBorder(),
                            ),
                            selectedItemBuilder: (context) => [
                              for (final value
                                  in ArchiveMemberMoveConflict.values)
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    text(value.name),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            items: [
                              for (final value
                                  in ArchiveMemberMoveConflict.values)
                                DropdownMenuItem(
                                  value: value,
                                  child: Text(text(value.name)),
                                ),
                            ],
                            onChanged: current && supported
                                ? (value) => setState(() {
                                    _conflict = value!;
                                    _error = null;
                                  })
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Text(text('preservesDestinations')),
                          const SizedBox(height: 16),
                          Text(
                            text('destination'),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            _directory,
                            key: const ValueKey(
                              'archive-member-move-destination',
                            ),
                            textDirection: TextDirection.ltr,
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                key: const ValueKey('archive-member-move-root'),
                                onPressed: current && _directory != '/'
                                    ? () => _navigate('/')
                                    : null,
                                icon: const Icon(Icons.home_outlined),
                                label: Text(text('root')),
                              ),
                              TextButton.icon(
                                key: const ValueKey('archive-member-move-up'),
                                onPressed: current && _directory != '/'
                                    ? () =>
                                          _navigate(p.posix.dirname(_directory))
                                    : null,
                                icon: const Icon(Icons.arrow_upward),
                                label: Text(text('up')),
                              ),
                            ],
                          ),
                          if (!current || !supported || _error != null)
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                !current
                                    ? text('stale')
                                    : !supported
                                    ? text('unsupported')
                                    : text('failed', [_error!]),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          if (current && directories.isEmpty)
                            Text(text('noSubfolders')),
                        ],
                      ),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: directories.length,
                    itemBuilder: (context, index) {
                      final directory = directories[index];
                      final path = _absolute(directory.path!);
                      final blocked = captured.blocks(path);
                      return ListTile(
                        key: ValueKey('archive-member-move-folder-$path'),
                        enabled: !blocked && supported,
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(directory.name),
                        subtitle: blocked ? Text(text('blocked')) : null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: blocked || !supported
                            ? null
                            : () => _navigate(path),
                      );
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: OverflowBar(
                spacing: 12,
                overflowSpacing: 8,
                children: [
                  TextButton(
                    key: const ValueKey('archive-member-move-cancel'),
                    onPressed: () => Navigator.pop(context),
                    child: Text(text('cancel')),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('archive-member-move-stage'),
                    onPressed:
                        current &&
                            supported &&
                            captured.paths.isNotEmpty &&
                            !captured.blocks(_directory)
                        ? _stage
                        : null,
                    icon: const Icon(Icons.drive_file_move_outline),
                    label: Text(text('stage')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
