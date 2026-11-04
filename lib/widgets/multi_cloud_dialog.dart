// lib/widgets/multi_cloud_dialog.dart
//
// Dialog for managing multiple cloud connections, initiating cloud-to-cloud
// transfers, and viewing cross-provider comparison results.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/multi_cloud_strings.dart';
import '../models/file_item.dart';
import '../models/operation_progress.dart';
import '../providers/providers.dart';

void showMultiCloudDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const _MultiCloudDialog(),
  );
}

class _MultiCloudDialog extends ConsumerStatefulWidget {
  const _MultiCloudDialog();

  @override
  ConsumerState<_MultiCloudDialog> createState() => _MultiCloudDialogState();
}

class _MultiCloudDialogState extends ConsumerState<_MultiCloudDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // Transfer UI state
  String? _sourceConnectionId;
  String? _targetConnectionId;
  final _sourcePathCtrl = TextEditingController(text: '/');
  final _targetPathCtrl = TextEditingController(text: '/');

  // Compare UI state
  String? _compareIdA;
  String? _compareIdB;
  final _comparePathACtrl = TextEditingController(text: '/');
  final _comparePathBCtrl = TextEditingController(text: '/');

  // Search UI state
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _sourcePathCtrl.dispose();
    _targetPathCtrl.dispose();
    _comparePathACtrl.dispose();
    _comparePathBCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _t(String key, [Map<String, Object> values = const {}]) =>
      MultiCloudStrings(context).text(key, values);

  @override
  Widget build(BuildContext context) {
    final mc = ref.watch(multiCloudProvider);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.cloud_sync),
          const SizedBox(width: 8),
          Text(_t('multi')),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          children: [
            TabBar(
              controller: _tabs,
              labelColor: theme.colorScheme.primary,
              tabs: [
                Tab(text: _t('connections'), icon: const Icon(Icons.hub, size: 16)),
                Tab(text: _t('transfer'), icon: const Icon(Icons.swap_horiz, size: 16)),
                Tab(text: _t('compareSearch'), icon: const Icon(Icons.compare_arrows, size: 16)),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _buildConnectionsTab(mc),
                  _buildTransferTab(mc),
                  _buildCompareSearchTab(mc),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Connections tab
  // ---------------------------------------------------------------------------

  Widget _buildConnectionsTab(MultiCloudNotifier mc) {
    final auth = ref.watch(authProvider);
    final connections = mc.connections;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (auth.isConnected)
          OutlinedButton.icon(
            icon: const Icon(Icons.add_circle_outline, size: 16),
            label: Text(_t('addCurrent', {'name': auth.providerName})),
            onPressed: () {
              final id = '${auth.currentProvider.name}_${DateTime.now().millisecondsSinceEpoch}';
              mc.addConnection(
                id: id,
                label: '${auth.providerName} (${auth.userEmail ?? id})',
                provider: auth.currentProvider,
                client: auth.client,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(_t('added', {'name': auth.providerName}))),
              );
            },
          )
        else
          Text(
            _t('connectFirst'),
            style: const TextStyle(fontSize: 12),
          ),
        const SizedBox(height: 12),
        if (connections.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_t('empty')),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: connections.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final conn = connections[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.cloud, size: 20),
                  title: Text(conn.label),
                  subtitle: Text(conn.provider.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.link_off, size: 16),
                    tooltip: _t('disconnect'),
                    onPressed: () async => mc.removeConnection(conn.id),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Transfer tab
  // ---------------------------------------------------------------------------

  Widget _buildTransferTab(MultiCloudNotifier mc) {
    final connections = mc.connections;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (connections.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                _t('needTwo'),
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            _sectionLabel(_t('source')),
            _connectionDropdown(
              value: _sourceConnectionId,
              connections: connections,
              onChanged: (v) => setState(() => _sourceConnectionId = v),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _sourcePathCtrl,
              decoration: InputDecoration(
                labelText: _t('sourcePath'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _sectionLabel(_t('target')),
            _connectionDropdown(
              value: _targetConnectionId,
              connections: connections,
              onChanged: (v) => setState(() => _targetConnectionId = v),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _targetPathCtrl,
              decoration: InputDecoration(
                labelText: _t('targetPath'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (mc.isTransferring)
              _buildTransferProgress(mc)
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.swap_horiz),
                label: Text(_t('start')),
                onPressed: _canTransfer(mc) ? () => _startTransfer(mc) : null,
              ),
            if (mc.activeTransfer != null && !mc.isTransferring)
              _buildTransferResult(mc.activeTransfer!),
          ],
        ],
      ),
    );
  }

  bool _canTransfer(MultiCloudNotifier mc) =>
      _sourceConnectionId != null &&
      _targetConnectionId != null &&
      _sourceConnectionId != _targetConnectionId &&
      !mc.isTransferring;

  Future<void> _startTransfer(MultiCloudNotifier mc) async {
    final src = mc.getConnection(_sourceConnectionId!);
    final tgt = mc.getConnection(_targetConnectionId!);
    if (src == null || tgt == null) return;

    Map<String, dynamic> result;
    try {
      result = await src.client.listPath(_sourcePathCtrl.text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('listError', {'error': e}))),
        );
      }
      return;
    }

    final files = <FileItem>[
      ...(result['files'] as List<dynamic>? ?? []).map((raw) => _mapToFileItem(raw, _sourcePathCtrl.text)),
      ...(result['folders'] as List<dynamic>? ?? []).map((raw) => _mapToFileItem(raw, _sourcePathCtrl.text, isFolder: true)),
    ];

    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('noFiles'))),
        );
      }
      return;
    }

    await mc.transferBetweenClouds(
      sourceClient: src.client,
      sourcePath: _sourcePathCtrl.text,
      targetClient: tgt.client,
      targetPath: _targetPathCtrl.text,
      files: files,
    );
  }

  Widget _buildTransferProgress(MultiCloudNotifier mc) {
    final op = mc.activeTransfer;
    return Column(
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text(op != null ? _operationSummary(op) : _t('progress')),
      ],
    );
  }

  Widget _buildTransferResult(OperationProgress op) {
    final ok = op.status == OperationStatus.completed;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: ok ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ok ? Colors.green : Colors.red),
      ),
      child: Text(_operationSummary(op), style: const TextStyle(fontSize: 12)),
    );
  }

  // ---------------------------------------------------------------------------
  // Compare & Search tab
  // ---------------------------------------------------------------------------

  Widget _buildCompareSearchTab(MultiCloudNotifier mc) {
    return ListView(
      children: [
        _sectionLabel(_t('compareDirs')),
        if (mc.connections.length < 2)
          Text(_t('needsTwo'), style: const TextStyle(fontSize: 12))
        else ...[
          Row(
            children: [
              Expanded(
                child: _connectionDropdown(
                  value: _compareIdA,
                  connections: mc.connections,
                  hint: _t('providerA'),
                  onChanged: (v) => setState(() => _compareIdA = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _connectionDropdown(
                  value: _compareIdB,
                  connections: mc.connections,
                  hint: _t('providerB'),
                  onChanged: (v) => setState(() => _compareIdB = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _comparePathACtrl,
                  decoration: InputDecoration(
                    labelText: _t('pathA'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _comparePathBCtrl,
                  decoration: InputDecoration(
                    labelText: _t('pathB'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          mc.isComparing
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton.icon(
                  icon: const Icon(Icons.compare_arrows),
                  label: Text(_t('compare')),
                  onPressed: _compareIdA != null && _compareIdB != null
                      ? () => _runCompare(mc)
                      : null,
                ),
          if (mc.lastDiffs.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildDiffResults(mc.lastDiffs),
          ] else if (!mc.isComparing && _compareIdA != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_t('noDiffs'), style: const TextStyle(fontSize: 12)),
            ),
        ],
        const Divider(height: 24),
        _sectionLabel(_t('searchAll')),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  labelText: _t('query'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search, size: 18),
                ),
                onSubmitted: (_) => _runSearch(mc),
              ),
            ),
            const SizedBox(width: 8),
            mc.isSearching
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: _t('search'),
                    onPressed: () => _runSearch(mc),
                  ),
          ],
        ),
        if (mc.lastSearchResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildSearchResults(mc.lastSearchResults),
        ] else if (!mc.isSearching && _searchCtrl.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_t('noResults'), style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }

  Future<void> _runCompare(MultiCloudNotifier mc) async {
    final a = mc.getConnection(_compareIdA!);
    final b = mc.getConnection(_compareIdB!);
    if (a == null || b == null) return;
    await mc.compareFiles(
      clientA: a.client,
      pathA: _comparePathACtrl.text,
      clientB: b.client,
      pathB: _comparePathBCtrl.text,
    );
  }

  Future<void> _runSearch(MultiCloudNotifier mc) async {
    if (_searchCtrl.text.trim().isEmpty) return;
    await mc.searchAcrossProviders(_searchCtrl.text.trim());
  }

  Widget _buildDiffResults(List<FileDiff> diffs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_t('diffs', {'count': diffs.length}),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 4),
        ...diffs.map(_buildDiffTile),
      ],
    );
  }

  Widget _buildDiffTile(FileDiff diff) {
    final (IconData icon, Color color) = switch (diff.kind) {
      FileDiffKind.onlyInA     => (Icons.looks_one_outlined, Colors.blue),
      FileDiffKind.onlyInB     => (Icons.looks_two_outlined, Colors.purple),
      FileDiffKind.sizeDiffers => (Icons.straighten, Colors.orange),
      FileDiffKind.dateDiffers => (Icons.schedule, Colors.amber),
      FileDiffKind.bothDiffer  => (Icons.difference, Colors.red),
    };
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 18),
      title: Text(diff.name, style: const TextStyle(fontSize: 13)),
      subtitle: Text(_diffDescription(diff), style: const TextStyle(fontSize: 11)),
    );
  }

  Widget _buildSearchResults(List<MultiCloudSearchResult> results) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_t('results', {'count': results.length}),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 4),
        ...results.map(
          (r) => ListTile(
            dense: true,
            leading: Icon(
              r.item.isFolder ? Icons.folder : Icons.insert_drive_file,
              size: 18,
            ),
            title: Text(r.item.name, style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              '${r.connectionLabel} — ${r.item.path ?? ''}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }

  String _operationSummary(OperationProgress op) {
    final label = _t(op.type.name);
    final name = op.isBatch
        ? _t('batchName', {'operation': label, 'count': op.totalFiles})
        : '$label: ${op.fileName}';
    if (!op.isBatch) return name;
    if (op.status == OperationStatus.failed) {
      return _t('failed', {'operation': name, 'count': op.failedFiles});
    }
    if (op.status == OperationStatus.completed) {
      return _t('complete', {'operation': name});
    }
    return _t('batchProgress', {
      'operation': name, 'done': op.completedFiles, 'total': op.totalFiles,
    });
  }

  String _diffDescription(FileDiff diff) => switch (diff.kind) {
        FileDiffKind.onlyInA => _t('onlyA'),
        FileDiffKind.onlyInB => _t('onlyB'),
        FileDiffKind.sizeDiffers => _t('sizeDiff', {
          'a': diff.itemA?.size ?? '—', 'b': diff.itemB?.size ?? '—',
        }),
        FileDiffKind.dateDiffers => _t('dateDiff', {
          'a': diff.itemA?.updatedAt ?? '—', 'b': diff.itemB?.updatedAt ?? '—',
        }),
        FileDiffKind.bothDiffer => _t('bothDiff'),
      };

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      );

  Widget _connectionDropdown({
    required String? value,
    required List<CloudConnection> connections,
    String? hint,
    required ValueChanged<String?> onChanged,
  }) =>
      DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          hintText: hint ?? _t('select'),
        ),
        items: connections
            .map((c) => DropdownMenuItem(
                  value: c.id,
                  child: Text(c.label, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: onChanged,
      );

  FileItem _mapToFileItem(dynamic raw, String basePath, {bool isFolder = false}) {
    final name = raw['name'] as String? ?? '';
    final size = raw['size'] != null ? int.tryParse(raw['size'].toString()) : null;
    final updatedAt = raw['updatedAt'] != null
        ? DateTime.tryParse(raw['updatedAt'].toString())
        : null;
    return FileItem(
      name: name,
      isFolder: isFolder,
      path: '${basePath.endsWith('/') ? basePath : '$basePath/'}$name',
      size: size,
      updatedAt: updatedAt,
    );
  }
}
