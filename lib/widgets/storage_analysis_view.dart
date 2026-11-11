import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/storage_analyzer_strings.dart';
import '../models/storage_analysis.dart';
import '../utils/formatters.dart';
import 'storage_sunburst.dart';
import 'storage_treemap.dart';

enum _StorageVisualization { treemap, sunburst }

/// Browses a completed or partial scan without issuing further storage reads.
class StorageAnalysisView extends StatefulWidget {
  const StorageAnalysisView({super.key, required this.analysis, this.onReveal});

  final StorageScanResult analysis;
  final Future<void> Function(StorageNode)? onReveal;

  @override
  State<StorageAnalysisView> createState() => _StorageAnalysisViewState();
}

class _StorageAnalysisViewState extends State<StorageAnalysisView>
    with TickerProviderStateMixin {
  late final TabController _wideTabs;
  late final TabController _compactTabs;
  final _queryController = TextEditingController();
  final _parents = <StorageNode, StorageNode>{};
  late List<StorageNode> _trail;
  late StorageNode _selected;
  List<StorageNode> _children = [];
  List<StorageNode> _files = [];
  List<StorageNode> _shownFiles = [];
  int _matchingFileCount = 0;
  List<_FileType> _types = [];
  String? _extension;
  String _query = '';
  _StorageVisualization _visualization = _StorageVisualization.treemap;

  StorageNode get _folder => _trail.last;

  @override
  void initState() {
    super.initState();
    _wideTabs = TabController(length: 3, vsync: this);
    _compactTabs = TabController(length: 4, vsync: this);
    _loadAnalysis();
  }

  @override
  void didUpdateWidget(StorageAnalysisView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.analysis, oldWidget.analysis)) _loadAnalysis();
  }

  @override
  void dispose() {
    _wideTabs.dispose();
    _compactTabs.dispose();
    _queryController.dispose();
    super.dispose();
  }

  void _loadAnalysis() {
    _parents.clear();
    final pending = <StorageNode>[widget.analysis.root];
    while (pending.isNotEmpty) {
      final parent = pending.removeLast();
      for (final child in parent.children) {
        _parents[child] = parent;
        if (child.isFolder) pending.add(child);
      }
    }
    _trail = [widget.analysis.root];
    _selected = widget.analysis.root;
    _loadFolder();
  }

  static int _bySize(StorageNode a, StorageNode b) {
    final size = b.bytes.compareTo(a.bytes);
    return size != 0 ? size : a.path.compareTo(b.path);
  }

  void _loadFolder() {
    _children = [..._folder.children]..sort(_bySize);
    _files = [];
    final types = <String, _FileType>{};
    final pending = <StorageNode>[_folder];
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      if (node.item.isSymlink == true) continue;
      if (node.isFolder) {
        pending.addAll(node.children);
      } else {
        _files.add(node);
        final extension = node.item.extension;
        final type = types.putIfAbsent(extension, () => _FileType(extension));
        type.bytes += node.bytes;
        type.count++;
        type.unknown += node.unknownSizeCount;
      }
    }
    _files.sort(_bySize);
    _types = types.values.toList()
      ..sort((a, b) {
        final size = b.bytes.compareTo(a.bytes);
        return size != 0 ? size : a.extension.compareTo(b.extension);
      });
    _extension = null;
    _query = '';
    _queryController.clear();
    _updateFileFilter();
  }

  // Selection and map updates must not re-walk a 200,000-file snapshot.
  void _updateFileFilter() {
    final query = _query.toLowerCase();
    _shownFiles = [];
    _matchingFileCount = 0;
    for (final node in _files) {
      if (_extension != null && node.item.extension != _extension) continue;
      if (query.isNotEmpty && !node.path.toLowerCase().contains(query)) {
        continue;
      }
      _matchingFileCount++;
      if (_shownFiles.length < 200) _shownFiles.add(node);
    }
  }

  void _openFolder(StorageNode node) {
    if (!node.isFolder || node.item.isSymlink == true) return;
    final trail = <StorageNode>[node];
    var parent = _parents[node];
    while (parent != null) {
      trail.add(parent);
      parent = _parents[parent];
    }
    setState(() {
      _trail = trail.reversed.toList();
      _selected = node;
      _loadFolder();
    });
  }

  String _sizeLabel(StorageNode node, StorageAnalyzerStrings strings) {
    if (node.item.isSymlink == true) return strings.text('skippedLink');
    if (!node.isFolder && node.unknownSizeCount > 0) {
      return strings.text('unknownSize');
    }
    return '${formatBytes(node.bytes)}${node.isComplete ? '' : ' + ?'}';
  }

  String _percentage(int bytes) =>
      (_folder.bytes == 0 ? 0 : bytes / _folder.bytes * 100)
          .clamp(0, 100)
          .toStringAsFixed(1);

  String _typeName(String extension, StorageAnalyzerStrings strings) =>
      extension.isEmpty ? strings.text('noExtension') : '.$extension';

  @override
  Widget build(BuildContext context) {
    final strings = StorageAnalyzerStrings(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 850;
        final header = _header(strings);
        final breadcrumbs = _breadcrumbs(strings);
        final body = wide ? _wideBody(strings) : _compactBody(strings);
        final selection = _selectionDetails(strings, wide);
        // At small heights the whole report can scroll; the lists retain a
        // bounded viewport, so accessibility text scaling never clips actions.
        if (constraints.maxHeight < 460 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.5) {
          return SingleChildScrollView(
            child: Column(
              children: [
                header,
                breadcrumbs,
                SizedBox(height: 420, child: body),
                selection,
              ],
            ),
          );
        }
        return Column(
          children: [
            header,
            breadcrumbs,
            Expanded(child: body),
            selection,
          ],
        );
      },
    );
  }

  Widget _header(StorageAnalyzerStrings strings) {
    final theme = Theme.of(context);
    final result = widget.analysis;
    final status = result.cancelled
        ? 'cancelled'
        : result.isComplete
        ? 'complete'
        : 'partial';
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 24,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.text('knownSize'),
                style: theme.textTheme.labelSmall,
              ),
              Text(
                formatBytes(_folder.bytes),
                style: theme.textTheme.headlineSmall,
              ),
            ],
          ),
          Text('${_folder.fileCount} ${strings.text('files')}'),
          Text('${_folder.folderCount} ${strings.text('folders')}'),
          TextButton.icon(
            onPressed: () => _showDetails(strings),
            icon: Icon(
              result.isComplete
                  ? Icons.check_circle_outline
                  : Icons.info_outline,
              size: 18,
            ),
            label: Text(strings.text(status)),
          ),
        ],
      ),
    );
  }

  Widget _breadcrumbs(StorageAnalyzerStrings strings) {
    return Row(
      children: [
        IconButton(
          tooltip: strings.text('up'),
          onPressed: _trail.length > 1
              ? () => _openFolder(_trail[_trail.length - 2])
              : null,
          icon: const Icon(Icons.arrow_upward, size: 20),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < _trail.length; index++) ...[
                  if (index > 0) const Icon(Icons.chevron_right, size: 16),
                  TextButton(
                    onPressed: () => _openFolder(_trail[index]),
                    child: Text(
                      index == 0 ? strings.text('home') : _trail[index].name,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _wideBody(StorageAnalyzerStrings strings) {
    return Row(
      children: [
        Expanded(flex: 6, child: _map(strings)),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 5,
          child: Column(
            children: [
              TabBar(
                controller: _wideTabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: _detailTabLabels(strings),
              ),
              Expanded(
                child: TabBarView(
                  controller: _wideTabs,
                  children: _detailTabs(strings),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _compactBody(StorageAnalyzerStrings strings) {
    return Column(
      children: [
        TabBar(
          controller: _compactTabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: strings.text('visualization')),
            ..._detailTabLabels(strings),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _compactTabs,
            children: [_map(strings), ..._detailTabs(strings)],
          ),
        ),
      ],
    );
  }

  List<Widget> _detailTabLabels(StorageAnalyzerStrings strings) => [
    Tab(text: strings.text('items')),
    Tab(text: strings.text('largest')),
    Tab(text: strings.text('types')),
  ];

  List<Widget> _detailTabs(StorageAnalyzerStrings strings) => [
    _children.isEmpty
        ? _empty(strings.text('empty'))
        : ListView.builder(
            key: PageStorageKey('storage-children-${_folder.path}'),
            itemCount: _children.length,
            itemBuilder: (_, index) => _nodeRow(_children[index], strings),
          ),
    _largestFiles(strings),
    _fileTypes(strings),
  ];

  Widget _map(StorageAnalyzerStrings strings) {
    final controls = Align(
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final mode in _StorageVisualization.values)
            ChoiceChip(
              key: ValueKey('storage-view-${mode.name}'),
              showCheckmark: false,
              avatar: Icon(
                mode == _StorageVisualization.treemap
                    ? Icons.grid_view
                    : Icons.donut_large,
                size: 18,
              ),
              label: Text(strings.text(mode.name)),
              selected: _visualization == mode,
              onSelected: (_) => setState(() => _visualization = mode),
            ),
        ],
      ),
    );
    final map = _visualization == _StorageVisualization.treemap
        ? StorageTreemap(
            root: _folder,
            selected: _selected,
            onSelected: (node) => setState(() => _selected = node),
            onOpenFolder: _openFolder,
            aggregateLabel: (count) =>
                strings.text('aggregate', {'count': count}),
            emptyLabel: strings.text('noBytes'),
          )
        : StorageSunburst(
            root: _folder,
            selected: _selected,
            onSelected: (node) => setState(() => _selected = node),
            onOpenFolder: _openFolder,
            onOpenParent: _trail.length > 1
                ? () => _openFolder(_trail[_trail.length - 2])
                : null,
            onInspectGroup: (folder) {
              _openFolder(folder);
              _wideTabs.animateTo(0);
              _compactTabs.animateTo(1);
            },
            aggregateLabel: (count) =>
                strings.text('aggregate', {'count': count}),
            shareLabel: (percent) =>
                strings.text('share', {'percent': percent}),
            centerLabel: strings.text(_trail.length > 1 ? 'up' : 'home'),
            emptyLabel: strings.text('noBytes'),
          );
    final hint = Text(
      strings.text(
        _visualization == _StorageVisualization.treemap
            ? 'mapHint'
            : 'sunburstHint',
      ),
      style: Theme.of(context).textTheme.bodySmall,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Help text and view choices can exceed a compact panel at large
          // text scales. Keep a useful map height and scroll the entire panel.
          if (MediaQuery.textScalerOf(context).scale(1) > 1.5 ||
              constraints.maxHeight < 240) {
            return SingleChildScrollView(
              child: Column(
                children: [
                  controls,
                  const SizedBox(height: 8),
                  SizedBox(
                    height: math.min(360, constraints.maxWidth),
                    child: map,
                  ),
                  const SizedBox(height: 8),
                  hint,
                ],
              ),
            );
          }
          return Column(
            children: [
              controls,
              const SizedBox(height: 8),
              Expanded(child: map),
              const SizedBox(height: 8),
              hint,
            ],
          );
        },
      ),
    );
  }

  Widget _nodeRow(
    StorageNode node,
    StorageAnalyzerStrings strings, {
    bool showPath = false,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      selected: identical(node, _selected),
      leading: Icon(
        node.item.isSymlink == true
            ? Icons.link
            : node.isFolder
            ? Icons.folder_outlined
            : Icons.insert_drive_file_outlined,
        color: node.isFolder
            ? theme.colorScheme.primary
            : storageExtensionColor(
                node.item.extension,
                brightness: theme.brightness,
              ),
      ),
      title: Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        showPath
            ? node.path
            : node.isFolder
            ? strings.text('fileCount', {'count': node.fileCount})
            : strings.text('share', {'percent': _percentage(node.bytes)}),
        textDirection: showPath ? TextDirection.ltr : null,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 95),
            child: Text(
              _sizeLabel(node, strings),
              style: theme.textTheme.labelMedium,
              maxLines: 2,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (node.isFolder && node.item.isSymlink != true)
            IconButton(
              tooltip: strings.text('openFolder'),
              onPressed: () => _openFolder(node),
              icon: const Icon(Icons.chevron_right),
            ),
        ],
      ),
      onTap: () => setState(() => _selected = node),
      onLongPress: node.isFolder ? () => _openFolder(node) : null,
    );
  }

  Widget _largestFiles(StorageAnalyzerStrings strings) {
    final shown = _shownFiles;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _queryController,
            onChanged: (value) => setState(() {
              _query = value;
              _updateFileFilter();
            }),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              labelText: strings.text('filter'),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (_extension != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: InputChip(
              label: Text(
                strings.text('typeFilter', {
                  'type': _typeName(_extension!, strings),
                }),
              ),
              onDeleted: () => setState(() {
                _extension = null;
                _updateFileFilter();
              }),
              deleteButtonTooltipMessage: strings.text('clearFilter'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            strings.text('largestCount', {
              'shown': shown.length,
              'total': _matchingFileCount,
            }),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? _empty(strings.text('noMatches'))
              : ListView.builder(
                  key: ValueKey(
                    'storage-largest-${_folder.path}-$_extension-$_query',
                  ),
                  itemCount: shown.length,
                  itemBuilder: (_, index) =>
                      _nodeRow(shown[index], strings, showPath: true),
                ),
        ),
      ],
    );
  }

  Widget _fileTypes(StorageAnalyzerStrings strings) {
    if (_types.isEmpty) return _empty(strings.text('noMatches'));
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            strings.text('typesHint'),
            style: theme.textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _types.length,
            itemBuilder: (_, index) {
              final type = _types[index];
              return ListTile(
                leading: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: storageExtensionColor(
                      type.extension,
                      brightness: theme.brightness,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                title: Text(
                  _typeName(type.extension, strings),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  strings.text('fileCount', {'count': type.count}),
                ),
                trailing: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Text(
                    '${formatBytes(type.bytes)}${type.unknown > 0 ? ' + ?' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
                onTap: () {
                  setState(() {
                    _extension = type.extension;
                    _updateFileFilter();
                  });
                  _wideTabs.animateTo(1);
                  _compactTabs.animateTo(2);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _selectionDetails(StorageAnalyzerStrings strings, bool wide) {
    final node = _selected;
    final parent = _parents[node];
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            node.path,
            textDirection: TextDirection.ltr,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  _sizeLabel(node, strings),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (node.isFolder &&
                  node.item.isSymlink != true &&
                  node != _folder)
                IconButton(
                  tooltip: strings.text('openFolder'),
                  onPressed: () => _openFolder(node),
                  icon: const Icon(Icons.zoom_in),
                ),
              if (!node.isFolder && parent != null && parent != _folder)
                IconButton(
                  tooltip: strings.text('containingFolder'),
                  onPressed: () => _openFolder(parent),
                  icon: const Icon(Icons.folder_open),
                ),
              IconButton(
                tooltip: strings.text('copyPath'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: node.path));
                  if (!mounted) return;
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(content: Text(strings.text('copied'))),
                  );
                },
                icon: const Icon(Icons.copy, size: 18),
              ),
              if (widget.onReveal != null)
                if (wide)
                  TextButton.icon(
                    onPressed: () => widget.onReveal!(node),
                    icon: const Icon(Icons.drive_file_move_outline),
                    label: Text(strings.text('reveal')),
                  )
                else
                  IconButton(
                    tooltip: strings.text('reveal'),
                    onPressed: () => widget.onReveal!(node),
                    icon: const Icon(Icons.drive_file_move_outline),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _empty(String text) => Center(
    child: Padding(padding: const EdgeInsets.all(24), child: Text(text)),
  );

  Future<void> _showDetails(StorageAnalyzerStrings strings) async {
    final result = widget.analysis;
    final root = result.root;
    final notes = <String>[
      strings.text('scope'),
      if (!result.isComplete) strings.text('partialHint'),
      if (result.sourceChanged) strings.text('sourceChanged'),
      if (result.limited) strings.text('limited'),
      if (root.unknownSizeCount > 0)
        strings.text('unknown', {'count': root.unknownSizeCount}),
      if (root.skippedLinkCount > 0)
        strings.text('links', {'count': root.skippedLinkCount}),
      if (result.suppressedIssueCount > 0)
        strings.text('moreIssues', {'count': result.suppressedIssueCount}),
    ];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          strings.text('issues', {
            'count': result.issues.length + result.suppressedIssueCount,
          }),
        ),
        content: SizedBox(
          width: 600,
          height: math.min(440, MediaQuery.sizeOf(context).height * 0.6),
          child: ListView(
            children: [
              for (final note in notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(note),
                ),
              for (final issue in result.issues)
                ExpansionTile(
                  title: Text(strings.text(issue.code.name)),
                  subtitle: Text(
                    issue.path,
                    textDirection: TextDirection.ltr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(issue.message),
                    ),
                  ],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.text('close')),
          ),
        ],
      ),
    );
  }
}

class _FileType {
  _FileType(this.extension);
  final String extension;
  int bytes = 0;
  int count = 0;
  int unknown = 0;
}
