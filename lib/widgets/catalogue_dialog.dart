import 'dart:async';
import 'dart:math' as math;

import 'package:crisp_catalog/crisp_catalog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../l10n/catalogue_strings.dart';
import '../models/file_item.dart';
import '../models/storage_analysis.dart';
import '../services/catalogue_files.dart';
import '../services/catalogue_format.dart';
import '../services/catalogue_library.dart';
import '../services/catalogue_service.dart';
import '../services/local_file_service.dart';
import '../utils/formatters.dart';
import 'storage_treemap.dart';
import 'storage_sunburst.dart';

typedef CatalogueReveal = Future<void> Function(
  String root,
  Map<String, dynamic> row,
);

class CatalogueInput {
  const CatalogueInput({
    required this.name,
    required this.format,
    required this.read,
    required this.isCurrent,
  });
  final String name;
  final CatalogueFormat format;
  final Stream<List<int>> Function() read;
  final bool Function() isCurrent;
}

Future<void> showCatalogueLibrary(
  BuildContext context, {
  required LocalFileService local,
  String? initialPath,
  CatalogueFormat? initialFormat,
  CatalogueInput? incoming,
  CatalogueReveal? onReveal,
  Future<void> Function()? onSavedReports,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => CatalogueDialog(
    local: local,
    initialPath: initialPath,
    initialFormat: initialFormat,
    incoming: incoming,
    onReveal: onReveal,
    onSavedReports: onSavedReports,
  ),
);

/// The list and maps request one page at a time. No whole-catalogue tree is
/// materialized in Flutter. Opening historical metadata never activates file
/// mutations or grants access to an indexed source path.
class CatalogueDialog extends StatefulWidget {
  const CatalogueDialog({
    super.key,
    required this.local,
    this.backend,
    this.library,
    this.initialPath,
    this.initialFormat,
    this.incoming,
    this.chooseFolder,
    this.chooseOpen,
    this.chooseSave,
    this.onReveal,
    this.onSavedReports,
  });
  final CatalogueReveal? onReveal;
  final Future<void> Function()? onSavedReports;
  final LocalFileService local;
  final CatalogBackend? backend;
  final CatalogueLibrary? library;
  final String? initialPath;
  final CatalogueFormat? initialFormat;
  final CatalogueInput? incoming;
  final Future<String?> Function()? chooseFolder;
  final Future<String?> Function(bool caf)? chooseOpen;
  final Future<String?> Function(bool caf)? chooseSave;
  @override
  State<CatalogueDialog> createState() => _CatalogueDialogState();
}

class _CatalogueSearchHit {
  const _CatalogueSearchHit(this.record, this.row, this.catalogueId);
  final CatalogueRecord record;
  final Map<String, dynamic> row;
  final String catalogueId;
}

class _CatalogueDialogState extends State<CatalogueDialog> {
  late final CatalogBackend _backend = widget.backend ?? const CrispCatalog();
  late final CatalogueLibrary _library = widget.library ?? CatalogueLibrary();
  List<CatalogueRecord> _records = [];
  CatalogueRecord? _record;
  Map<String, dynamic>? _info, _report;
  Map<String, Object?> _filters = {};
  CatalogueJob? _job, _queryJob;
  Completer<void>? _actionSettled;
  final _search = TextEditingController();
  final _librarySearch = TextEditingController();
  final _libraryJobs = <CatalogueJob>[];
  final _libraryHits = <_CatalogueSearchHit>[];
  int _libraryGeneration = 0;
  bool _libraryLoading = false;
  String _exactPath = '';
  String? _linkedRoot, _linkedId;
  Timer? _debounce;
  String _path = '', _mode = 'browse', _order = 'name', _visual = 'table';
  int _offset = 0, _generation = 0;
  bool _busy = false,
      _loading = false,
      _closing = false,
      _transferStopped = false;
  String? _error, _notice;
  Map<String, dynamic>? _selected;
  static const _pageSize = 200;
  CatalogueStrings get s => CatalogueStrings(context);
  String t(String value) => s.text(value);
  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _loadLibrary();
      if (!mounted || !_backend.supported) return;
      if (widget.incoming != null) {
        await _incoming(widget.incoming!);
      } else if (widget.initialPath != null) {
        if (widget.initialFormat == CatalogueFormat.caf) {
          await _import(widget.initialPath!);
        } else {
          await _open(widget.initialPath!);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _librarySearch.dispose();
    ++_libraryGeneration;
    for (final job in _libraryJobs) {
      unawaited(job.stop().catchError((Object _) {}));
    }
    ++_generation;
    _transferStopped = true;
    unawaited(
      _queryJob?.stop().catchError((Object _) {}) ?? Future<void>.value(),
    );
    unawaited(_job?.stop().catchError((Object _) {}) ?? Future<void>.value());
    super.dispose();
  }

  Future<void> _loadLibrary() async {
    final rows = await _library.list();
    if (mounted) setState(() => _records = rows);
  }

  Future<T?> _action<T>(Future<T> Function() action) async {
    if (_busy) return null;
    final settled = Completer<void>();
    _actionSettled = settled;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      return await action();
    } catch (e) {
      if (mounted) {
        setState(() {
          if (e is CatalogException && e.code == 'cancelled') {
            _notice = t('Stopped. Unpublished changes were discarded.');
          } else {
            _error = '$e';
          }
        });
      }
      return null;
    } finally {
      settled.complete();
      if (mounted) {
        setState(() {
          _busy = false;
          _job = null;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _run(
    Map<String, Object?> request,
    List<String> scopes,
  ) async {
    final job = CatalogueJob(_backend, widget.local, request, scopes);
    if (mounted) setState(() => _job = job);
    return job.future;
  }

  Future<String?> _folder() async {
    if (widget.chooseFolder != null) return widget.chooseFolder!();
    // Picking a grant must not navigate an unrelated pane through its shared
    // LocalFileService.currentPath side effect.
    final previous = widget.local.currentPath;
    try {
      return await widget.local.requestDirectoryAccess(
        initialDirectory: _info?['root'] is String
            ? _info!['root'] as String
            : null,
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      return null;
    } finally {
      widget.local.currentPath = previous;
    }
  }

  Future<String?> _pick(bool caf) async {
    if (widget.chooseOpen != null) return widget.chooseOpen!(caf);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: caf ? ['caf'] : ['crispindex'],
      lockParentWindow: true,
    );
    final path = result?.files.single.path;
    if (path != null) await rememberPickedCatalogue(path);
    return path;
  }

  Future<String?> _savePath(bool caf) async {
    if (widget.chooseSave != null) return widget.chooseSave!(caf);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: t(caf ? 'Export CAF' : 'Save a copy'),
      fileName:
          '${(_record?.label ?? 'catalogue').replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')}-${DateTime.fromMillisecondsSinceEpoch(((_info?['sourceCapturedAtUnix'] ?? _info?['indexedAtUnix']) as int? ?? 0) * 1000, isUtc: true).toIso8601String().substring(0, 10)}.${caf ? 'caf' : 'crispindex'}',
      type: FileType.custom,
      allowedExtensions: [caf ? 'caf' : 'crispindex'],
      lockParentWindow: true,
    );
    return path;
  }

  Future<void> _remember(
    CatalogueRecord record,
    Map<String, dynamic> info,
  ) async {
    // The native publication already succeeded. Never delete its file because
    // registry acknowledgement failed; expose the path for recovery instead.
    try {
      await _library.remember(record);
      await _loadLibrary();
    } catch (e) {
      if (mounted) setState(() => _notice = '${record.path}\n$e');
    }
    if (!mounted) return;
    setState(() {
      _record = record;
      _info = info;
      _path = '';
      _offset = 0;
      _selected = null;
      _search.clear();
      _filters = {};
      _linkedRoot = null;
      _linkedId = null;
      _exactPath = '';
      _mode = 'browse';
      _order = 'name';
      _visual = 'table';
      _report = null;
    });
    await _query();
  }

  Future<void> _create() async {
    final root = await _folder();
    if (root == null || !mounted) return;
    await _action(() async {
      final id = const Uuid().v4();
      final output = await allocateCataloguePath(id);
      final result = await _run(
        {'op': 'scan', 'path': root, 'output': output},
        [root, p.dirname(output)],
      );
      final record = CatalogueRecord(
        id: id,
        path: output,
        label: p.basename(root).isEmpty ? root : p.basename(root),
        managed: true,
        root: result['root'] as String,
        savedAt: DateTime.now(),
      );
      await _remember(record, result);
      if (mounted) {
        setState(() {
          _linkedRoot = root;
          _linkedId = result['catalogueId'] as String;
        });
      }
    });
  }

  Future<void> _open(
    String path, {
    bool managed = false,
    String? label,
    String? expectedId,
  }) async {
    ++_libraryGeneration;
    _libraryLoading = false;
    for (final job in List<CatalogueJob>.of(_libraryJobs)) {
      unawaited(job.stop().catchError((Object _) {}));
    }
    await _action(() async {
      final info = await _run(
        {
          'op': 'validate',
          'index': path,
          if (expectedId != null) 'expectedCatalogueId': expectedId,
        },
        [path],
      );
      final existing = _records
          .where((e) => p.equals(e.path, path))
          .firstOrNull;
      await _remember(
        CatalogueRecord(
          id: existing?.id ?? const Uuid().v4(),
          path: path,
          label: label ?? existing?.label ?? p.basenameWithoutExtension(path),
          managed: managed || existing?.managed == true,
          root: info['root'] as String,
          savedAt: DateTime.now(),
        ),
        info,
      );
    });
  }

  Future<void> _chooseOpen(bool caf) async {
    try {
      final path = await _pick(caf);
      if (path == null || !mounted) return;
      if (caf) {
        await _import(path);
      } else {
        await _open(path);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _import(String path, {String? label}) async {
    await _action(() async {
      final id = const Uuid().v4();
      final output = await allocateCataloguePath(id);
      final result = await _run(
        {'op': 'import', 'path': path, 'output': output},
        [path, p.dirname(output)],
      );
      await _remember(
        CatalogueRecord(
          id: id,
          path: output,
          label: label ?? p.basenameWithoutExtension(path),
          managed: true,
          root: result['root'] as String,
          savedAt: DateTime.now(),
        ),
        result,
      );
    });
  }

  Future<void> _incoming(CatalogueInput input) async {
    final path = await allocateCataloguePath(
      const Uuid().v4(),
      extension: input.format == CatalogueFormat.caf ? 'caf' : 'crispindex',
    );
    var retained = false;
    await _action(() async {
      _transferStopped = false;
      try {
        await stageCatalogueStream(
          path,
          input.read(),
          cancelled: () => _transferStopped || !mounted || !input.isCurrent(),
        );
        if (!input.isCurrent() || _transferStopped) {
          throw CatalogException(
            'Catalogue transfer stopped.',
            code: 'cancelled',
          );
        }
        final output = input.format == CatalogueFormat.caf
            ? await allocateCataloguePath(const Uuid().v4())
            : path;
        final info = await _run(
          input.format == CatalogueFormat.caf
              ? {'op': 'import', 'path': path, 'output': output}
              : {'op': 'validate', 'index': path},
          [path, p.dirname(output)],
        );
        retained = input.format == CatalogueFormat.native;
        await _remember(
          CatalogueRecord(
            id: const Uuid().v4(),
            path: output,
            label: input.name,
            managed: true,
            root: info['root'] as String,
            savedAt: DateTime.now(),
          ),
          info,
        );
      } finally {
        if (!retained) await discardOwnedCatalogueFile(path);
      }
    });
  }

  Future<bool> _confirm(
    String title,
    String message, {
    String button = 'Continue',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t(title)),
          content: SelectableText(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t(button)),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _refresh() async {
    final record = _record, info = _info;
    if (record == null || info == null) return;
    final root = await _folder();
    if (root == null || !mounted) return;
    if (!await _confirm(
      'Refresh this catalogue from the selected folder?',
      '${t('Choose the original root folder. To catalogue another folder, create a new catalogue.')}\n\n${record.root}\n→ $root',
    )) {
      return;
    }
    if (!mounted) return;
    await _action(() async {
      final result = await _run(
        {
          'op': 'scan',
          'path': root,
          'output': record.path,
          'replace': true,
          'expectedRoot': record.root,
          'expectedCatalogueId': info['catalogueId'],
        },
        [root, p.dirname(record.path)],
      );
      await _remember(record, result);
      if (mounted) {
        setState(() {
          _linkedRoot = root;
          _linkedId = result['catalogueId'] as String;
        });
      }
    });
  }

  Future<void> _export(bool caf) async {
    final record = _record, info = _info;
    if (record == null || info == null) return;
    var lossy = false;
    if (caf && info['complete'] != true) {
      lossy = await _confirm(
        'CAF coverage warning',
        t(
          'CAF cannot store scan errors or completeness. Export only the observed entries?',
        ),
      );
      if (!lossy || !mounted) return;
    }
    final output = await _savePath(caf);
    if (output == null || !mounted) return;
    await _action(() async {
      await _run(
        {
          'op': caf ? 'export' : 'copy',
          'index': record.path,
          'output': output,
          'replace': true,
          'allowLossy': lossy,
          'expectedCatalogueId': info['catalogueId'],
        },
        [record.path, p.dirname(output)],
      );
      if (mounted) setState(() => _notice = '${t('Saved.')} $output');
    });
  }

  Future<void> _remove() async {
    final record = _record;
    if (record == null) return;
    if (!await _confirm(
      'Remove this catalogue?',
      t(
        'Only this saved metadata is removed. Original files are never deleted. External catalogue files are kept.',
      ),
      button: 'Remove',
    )) {
      return;
    }
    if (!mounted) return;
    await _action(() async {
      if (record.managed) await discardOwnedCatalogueFile(record.path);
      await _library.forget(record.id);
      await _loadLibrary();
      if (mounted) {
        setState(() {
          ++_generation;
          _record = null;
          _info = null;
          _report = null;
        });
      }
    });
  }

  Future<void> _rename() async {
    final record = _record;
    if (record == null) return;
    final edit = TextEditingController(text: record.label);
    try {
      final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('Rename catalogue')),
          content: TextField(
            controller: edit,
            autofocus: true,
            maxLength: 256,
            decoration: InputDecoration(labelText: t('Catalogue name')),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, edit.text),
              child: Text(t('Apply')),
            ),
          ],
        ),
      );
      if (value == null || value.trim().isEmpty || !mounted) return;
      final renamed = record.renamed(value.trim());
      await _action(() async {
        await _library.remember(renamed);
        await _loadLibrary();
        if (mounted) setState(() => _record = renamed);
      });
    } finally {
      edit.dispose();
    }
  }

  Future<void> _query({bool reset = false}) async {
    final record = _record, info = _info;
    if (record == null || info == null) return;
    if (reset) _offset = 0;
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _selected = null;
      });
    }
    try {
      unawaited(
        _queryJob?.stop().catchError((Object _) {}) ?? Future<void>.value(),
      );
      final query = CatalogueJob(
        _backend,
        widget.local,
        {
          'op': 'query',
          'index': record.path,
          'expectedCatalogueId': info['catalogueId'],
          'path': _path,
          'top': _pageSize,
          'offset': _offset,
          'countMatches': true,
          'order': _order,
          'search': _search.text,
          'exactPath': _exactPath,
          'recursive': _mode != 'browse' || _search.text.isNotEmpty,
          'filesOnly': _mode == 'files',
          'directoriesOnly': _mode == 'folders',
          ..._filters,
        },
        [record.path],
      );
      _queryJob = query;
      final report = await query.future;
      if (mounted && generation == _generation) {
        setState(() => _report = report);
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = '$e';
          _linkedRoot = null;
          _linkedId = null;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _enter(String path) {
    setState(() {
      _exactPath = '';
      _path = path;
      _search.clear();
      _mode = 'browse';
      _order = _visual == 'table' ? 'name' : 'size';
      _offset = 0;
    });
    unawaited(_query());
  }

  Future<void> _stop() async {
    _transferStopped = true;
    try {
      await _job?.stop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    if (_busy) {
      await _stop();
      try {
        await _actionSettled?.future;
      } catch (_) {}
    }
    await _queryJob?.stop().catchError((Object _) {});
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _filterDialog() async {
    final fields = <String, TextEditingController>{
      for (final key in [
        'minBytes',
        'maxBytes',
        'extension',
        'modifiedAfter',
        'modifiedBefore',
      ])
        key: TextEditingController(text: _filters[key]?.toString() ?? ''),
    };
    String? error;
    final labels = {
      'minBytes': 'Minimum bytes',
      'maxBytes': 'Maximum bytes',
      'extension': 'Extension',
      'modifiedAfter': 'Modified after (YYYY-MM-DD)',
      'modifiedBefore': 'Modified before (YYYY-MM-DD)',
    };
    for (final key in ['modifiedAfter', 'modifiedBefore']) {
      final value = _filters[key];
      if (value is int) {
        fields[key]!.text = DateTime.fromMillisecondsSinceEpoch(
          value * 1000,
          isUtc: true,
        ).toIso8601String().substring(0, 10);
      }
    }
    try {
      final value = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, state) => AlertDialog(
            title: Text(t('Filters')),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in fields.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          controller: entry.value,
                          decoration: InputDecoration(
                            labelText: t(labels[entry.key]!),
                          ),
                        ),
                      ),
                    if (error != null) Text(error!),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, <String, Object?>{}),
                child: Text(t('Reset')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('Cancel')),
              ),
              FilledButton(
                onPressed: () {
                  try {
                    final filters = <String, Object?>{};
                    for (final entry in fields.entries) {
                      final text = entry.value.text.trim();
                      if (text.isEmpty) continue;
                      if (entry.key == 'extension') {
                        filters[entry.key] = text.startsWith('.')
                            ? text
                            : '.$text';
                      } else if (entry.key.startsWith('modified')) {
                        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
                          throw FormatException(labels[entry.key]!);
                        }
                        final date = DateTime.parse('${text}T00:00:00Z');
                        if (date.toIso8601String().substring(0, 10) != text) {
                          throw FormatException(labels[entry.key]!);
                        }
                        filters[entry.key] =
                            date.millisecondsSinceEpoch ~/ 1000 +
                            (entry.key == 'modifiedBefore' ? 86399 : 0);
                      } else {
                        final n = int.parse(text);
                        if (n < 0 || n > 9007199254740991) {
                          throw FormatException(labels[entry.key]!);
                        }
                        filters[entry.key] = n;
                      }
                    }
                    Navigator.pop(context, filters);
                  } catch (e) {
                    state(() => error = '$e');
                  }
                },
                child: Text(t('Apply')),
              ),
            ],
          ),
        ),
      );
      if (value != null && mounted) {
        setState(() {
          _filters = value;
          if (value.isNotEmpty) _visual = 'table';
        });
        await _query(reset: true);
      }
    } finally {
      for (final field in fields.values) {
        field.dispose();
      }
    }
  }

  Future<void> _link() async {
    final id = _info?['catalogueId'];
    final root = await _folder();
    if (root != null && mounted && id == _info?['catalogueId']) {
      setState(() {
        _linkedRoot = root;
        _linkedId = id as String;
      });
    }
  }

  Future<void> _reveal() async {
    final row = _selected, root = _linkedRoot;
    if (row == null ||
        root == null ||
        widget.onReveal == null ||
        _linkedId != _info?['catalogueId']) {
      return;
    }
    final success = await _action(() async {
      await widget.onReveal!(root, row);
      return true;
    });
    if (success == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _details() async {
    final record = _record, report = _report, info = _info;
    if (record == null || info == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Details')),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: SelectableText(
              '${record.path}\n${record.root}\n${t('Indexed at')}: ${_date(info['indexedAtUnix'])}\n'
              '${t('Source catalogue date')}: ${_date(info['sourceCapturedAtUnix'])}\n'
              '${t('Issue count')}: ${info['issueCount']}\n\n'
              '${t('Logical file bytes; hard links count per path and child symlinks are skipped.')}\n'
              '${t('Some files may be missing from a partial catalogue. Rankings are observations, not live disk allocation.')}\n\n'
              '${(report?['issues'] as List? ?? []).map((e) => '${e['path']} · ${e['code']}\n${e['detail']}').join('\n\n')}',
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Close')),
          ),
        ],
      ),
    );
  }

  String _date(dynamic seconds) => seconds is int
      ? DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
          isUtc: true,
        ).toLocal().toString()
      : '—';
  List<Map<String, dynamic>> get _rows => (_report?['entries'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  StorageNode _node(
    Map<String, dynamic> row, {
    List<StorageNode> children = const [],
  }) => StorageNode(
    item: FileItem(
      name: row['relativePath'] == null
          ? p.basename('${row['path']}')
          : '${row['relativePath']}'.split('/').last,
      path: '${row['relativePath'] ?? _path}',
      isFolder: row['type'] == 'directory',
      size: row['bytes'] as int,
    ),
    children: children,
    bytes: row['bytes'] as int,
    fileCount: row['files'] as int,
    folderCount: row['directories'] as int,
    isComplete: row['complete'] == true,
  );
  Widget _map() {
    final report = _report;
    if (report == null) return const SizedBox();
    final children = _rows.map(_node).toList();
    var root = _node(
      Map<String, dynamic>.from(report['root'] as Map),
      children: children,
    );
    final visible = children.fold<int>(0, (sum, node) => sum + node.bytes);
    if (root.bytes > visible) {
      children.add(
        StorageNode(
          item: FileItem(name: t('Other entries — use pages'), isFolder: false),
          bytes: root.bytes - visible,
          fileCount: 0,
          folderCount: 0,
        ),
      );
    }
    root = _node(
      Map<String, dynamic>.from(report['root'] as Map),
      children: children,
    );
    final selected = children
        .where((e) => e.path == _selected?['relativePath'])
        .firstOrNull;
    void select(StorageNode node) {
      final row = _rows
          .where((r) => r['relativePath'] == node.path)
          .firstOrNull;
      if (row != null) setState(() => _selected = row);
    }

    void open(StorageNode node) {
      if (node.isFolder) _enter(node.path);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            t(
              'Map shows this page only. Folder totals include all indexed descendants.',
            ),
          ),
        ),
        Expanded(
          child: _visual == 'treemap'
              ? StorageTreemap(
                  root: root,
                  selected: selected,
                  onSelected: select,
                  onOpenFolder: open,
                  aggregateLabel: (count) => '$count ${t('Rows')}',
                  emptyLabel: t('No matching entries.'),
                )
              : StorageSunburst(
                  root: root,
                  selected: selected,
                  onSelected: select,
                  onOpenFolder: open,
                  onOpenParent: _path.isEmpty
                      ? null
                      : () => _enter(_parent(_path)),
                  aggregateLabel: (n) => '$n ${t('Rows')}',
                  shareLabel: (n) => n,
                  centerLabel: t('Up'),
                  emptyLabel: t('No matching entries.'),
                ),
        ),
        if (_selected != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: SelectableText(
              '${_selected!['path']} · ${formatBytes(_selected!['bytes'] as int)}',
              textDirection: TextDirection.ltr,
            ),
          ),
      ],
    );
  }

  static String _parent(String path) =>
      path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
  Widget _table() {
    final rows = _rows;
    if (rows.isEmpty && _path.isEmpty) {
      return Center(child: Text(t('No matching entries.')));
    }
    return ListView.builder(
      itemCount: rows.length + (_path.isEmpty ? 0 : 1),
      itemBuilder: (context, index) {
        if (_path.isNotEmpty && index == 0) {
          return ListTile(
            key: const ValueKey('catalogue-parent'),
            leading: const Icon(Icons.folder_open),
            title: const Text('..'),
            onTap: () => _enter(_parent(_path)),
          );
        }
        final row = rows[index - (_path.isEmpty ? 0 : 1)];
        final directory = row['type'] == 'directory';
        return ListTile(
          key: ValueKey('catalogue-row-${row['relativePath']}'),
          selected: _selected?['relativePath'] == row['relativePath'],
          leading: Icon(
            directory
                ? Icons.folder_outlined
                : Icons.insert_drive_file_outlined,
          ),
          title: Text(
            _mode == 'browse' && _search.text.isEmpty
                ? '${row['relativePath']}'.split('/').last
                : '${row['relativePath']}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.ltr,
          ),
          subtitle: Text(
            '${row['complete'] == true ? '' : '>='}${formatBytes(row['bytes'] as int)} · ${_date(row['mtimeUnix'])}',
            textDirection: TextDirection.ltr,
          ),
          trailing: directory
              ? IconButton(
                  tooltip: t('Browse folders'),
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _enter(row['relativePath'] as String),
                )
              : null,
          onTap: () {
            if (directory) {
              _enter(row['relativePath'] as String);
            } else {
              setState(() => _selected = row);
            }
          },
          minTileHeight: math.max(
            72,
            MediaQuery.textScalerOf(context).scale(16) * 5 + 12,
          ),
          onLongPress: () =>
              Clipboard.setData(ClipboardData(text: '${row['path']}')),
          onFocusChange: (focused) {
            if (focused) setState(() => _selected = row);
          },
        );
      },
    );
  }

  Widget _boundedDropdown({
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?>? onChanged,
  }) => SizedBox(
    width: math.min(280, MediaQuery.sizeOf(context).width - 70),
    child: DropdownButton<String>(
      value: value,
      isExpanded: true,
      itemHeight: null,
      selectedItemBuilder: (context) => items
          .map(
            (item) => Align(
              alignment: Alignment.centerLeft,
              child: Text(
                (item.child as Text).data ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      items: items
          .map(
            (item) => DropdownMenuItem<String>(
              value: item.value,
              child: Text(
                (item.child as Text).data ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    ),
  );
  Widget _workspace({bool compact = false}) {
    final info = _info!, report = _report;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: t('Up'),
                onPressed: _path.isEmpty || _busy
                    ? null
                    : () => _enter(_parent(_path)),
                icon: const Icon(Icons.arrow_upward),
              ),
              TextButton(
                onPressed: _busy ? null : () => _enter(''),
                child: Text(_record!.label),
              ),
              if (_path.isNotEmpty)
                SelectableText(_path, textDirection: TextDirection.ltr),
              TextButton.icon(
                onPressed: _busy ? null : _details,
                icon: const Icon(Icons.info_outline),
                label: Text(t('Details')),
              ),
              if (info['origin'] == 'native_scan')
                TextButton.icon(
                  onPressed: _busy ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                  label: Text(t('Refresh from folder')),
                ),
              TextButton(
                onPressed: _busy ? null : () => _export(true),
                child: Text(t('Export CAF')),
              ),
              TextButton(
                onPressed: _busy ? null : () => _export(false),
                child: Text(t('Save a copy')),
              ),
              if (widget.onReveal != null)
                TextButton.icon(
                  onPressed: _busy ? null : _link,
                  icon: const Icon(Icons.link),
                  label: Text(t('Link local folder')),
                ),
              TextButton(
                onPressed: _busy ? null : _rename,
                child: Text(t('Rename catalogue')),
              ),
              TextButton(
                onPressed: _busy ? null : _remove,
                child: Text(t('Remove from library')),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                '${info['root']}',
                textDirection: TextDirection.ltr,
              ),
              if (_linkedRoot != null)
                SelectableText('${t('Linked local folder')}: $_linkedRoot'),
              Text(
                '${t('Indexed at')}: ${_date(info['indexedAtUnix'])} · ${formatBytes(info['bytes'] as int)} · ${info['files']} ${t('Files')} · ${info['directories']} ${t('Folders')}',
              ),
              Text(
                t(
                  'Historical metadata — source availability has not been checked.',
                ),
              ),
              if (info['complete'] != true)
                Text(
                  t('Partial or unknown source coverage'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: math.min(320, MediaQuery.sizeOf(context).width - 70),
                child: TextField(
                  key: const ValueKey('catalogue-search'),
                  controller: _search,
                  decoration: InputDecoration(
                    labelText: t('Search all paths'),
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (_) {
                    _exactPath = '';
                    if (_search.text.isNotEmpty && _visual != 'table') {
                      setState(() => _visual = 'table');
                    }
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 300),
                      () => unawaited(_query(reset: true)),
                    );
                  },
                  onSubmitted: (_) => unawaited(_query(reset: true)),
                ),
              ),
              _boundedDropdown(
                value: _mode,
                items: [
                  for (final pair in const [
                    ('browse', 'Browse folders'),
                    ('files', 'Largest files'),
                    ('folders', 'Largest folders'),
                  ])
                    DropdownMenuItem(value: pair.$1, child: Text(t(pair.$2))),
                ],
                onChanged: _busy
                    ? null
                    : (v) {
                        setState(() {
                          _mode = v!;
                          _exactPath = '';
                          _visual = 'table';
                          _order = _mode == 'browse' ? 'name' : 'size';
                        });
                        unawaited(_query(reset: true));
                      },
              ),
              _boundedDropdown(
                value: _order,
                items: [
                  for (final pair in const [
                    ('name', 'Name'),
                    ('size', 'Size'),
                    ('date', 'Modified'),
                  ])
                    DropdownMenuItem(value: pair.$1, child: Text(t(pair.$2))),
                ],
                onChanged: _busy
                    ? null
                    : (v) {
                        setState(() => _order = v!);
                        unawaited(_query(reset: true));
                      },
              ),
              TextButton.icon(
                onPressed: _busy ? null : _filterDialog,
                icon: Icon(
                  _filters.isEmpty ? Icons.filter_list : Icons.filter_alt,
                ),
                label: Text(t('Filters')),
              ),
              _boundedDropdown(
                value: _visual,
                items: [
                  for (final pair in const [
                    ('table', 'Table'),
                    ('treemap', 'Treemap'),
                    ('sunburst', 'Sunburst'),
                  ])
                    DropdownMenuItem(value: pair.$1, child: Text(t(pair.$2))),
                ],
                onChanged:
                    _mode != 'browse' ||
                        _search.text.isNotEmpty ||
                        _filters.isNotEmpty
                    ? null
                    : (v) => setState(() => _visual = v!),
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (compact)
          SizedBox(height: 360, child: _data(report))
        else
          Expanded(child: _data(report)),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: _offset == 0 || _loading || _busy
                    ? null
                    : () {
                        _offset = math.max(0, _offset - _pageSize);
                        unawaited(_query());
                      },
                child: Text(t('Previous')),
              ),
              Text(
                '${t('Rows')}: ${_offset + (_rows.isEmpty ? 0 : 1)}–${_offset + _rows.length} / ${report?['totalMatches'] ?? '—'}',
              ),
              TextButton(
                onPressed: report?['hasMore'] != true || _loading || _busy
                    ? null
                    : () {
                        _offset += _pageSize;
                        unawaited(_query());
                      },
                child: Text(t('Next')),
              ),
              if (widget.onReveal != null)
                TextButton.icon(
                  onPressed:
                      _selected == null ||
                          _linkedRoot == null ||
                          _linkedId != _info?['catalogueId'] ||
                          _busy
                      ? null
                      : _reveal,
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: Text(t('Show in file pane')),
                ),
              TextButton.icon(
                onPressed: _selected == null
                    ? null
                    : () => Clipboard.setData(
                        ClipboardData(text: '${_selected!['path']}'),
                      ),
                icon: const Icon(Icons.copy),
                label: Text(t('Copy path')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _data(Map<String, dynamic>? report) => report == null
      ? Center(child: Text(t('Loading…')))
      : _visual == 'table'
      ? _table()
      : _map();
  Widget _progress() {
    final job = _job;
    Widget content(Map<String, dynamic> value) {
      final phase = value['phase'];
      final label = t(switch (phase) {
        'scanning' => 'Scanning…',
        'reading_caf' => 'Reading CAF…',
        'importing' => 'Importing…',
        'aggregating' => 'Calculating totals…',
        'exporting' => 'Exporting…',
        'copying' => 'Copying…',
        'publishing' => 'Publishing…',
        _ => 'Preparing…',
      });
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$label ${value['entries'] ?? ''} ${value['bytes'] is int ? formatBytes(value['bytes'] as int) : ''}',
              ),
            ),
            TextButton(
              onPressed: value['stopRequested'] == true ? null : _stop,
              child: Text(
                t(value['stopRequested'] == true ? 'Stopping…' : 'Stop'),
              ),
            ),
          ],
        ),
      );
    }

    return job == null
        ? content({})
        : ValueListenableBuilder<Map<String, dynamic>>(
            valueListenable: job.progress,
            builder: (_, v, _) => content(v),
          );
  }

  Future<void> _searchLibrary() async {
    final generation = ++_libraryGeneration;
    for (final job in List<CatalogueJob>.of(_libraryJobs)) {
      unawaited(job.stop().catchError((Object _) {}));
    }
    final query = _librarySearch.text.trim();
    setState(() {
      _libraryHits.clear();
      _libraryLoading = query.isNotEmpty;
      _error = null;
    });
    if (query.isEmpty) return;
    var cursor = 0;
    final errors = <String>[];
    Future<void> worker() async {
      while (mounted &&
          generation == _libraryGeneration &&
          cursor < _records.length &&
          _libraryHits.length < 200) {
        final record = _records[cursor++];
        final job = CatalogueJob(
          _backend,
          widget.local,
          {
            'op': 'query',
            'index': record.path,
            'search': query,
            'recursive': true,
            'filesOnly': true,
            'top': 20,
            'order': 'name',
          },
          [record.path],
        );
        _libraryJobs.add(job);
        try {
          final result = await job.future;
          if (!mounted || generation != _libraryGeneration) return;
          final rows = (result['entries'] as List).map(
            (e) => Map<String, dynamic>.from(e as Map),
          );
          setState(
            () => _libraryHits.addAll(
              rows
                  .take(200 - _libraryHits.length)
                  .map(
                    (row) => _CatalogueSearchHit(
                      record,
                      row,
                      result['catalogueId'] as String,
                    ),
                  ),
            ),
          );
        } catch (e) {
          if (generation == _libraryGeneration) {
            errors.add('${record.label}: $e');
          }
        } finally {
          _libraryJobs.remove(job);
        }
      }
    }

    await Future.wait([worker(), worker()]);
    if (mounted && generation == _libraryGeneration) {
      setState(() {
        _libraryLoading = false;
        if (errors.isNotEmpty) _error = errors.join('\n');
      });
    }
  }

  Future<void> _openHit(_CatalogueSearchHit hit) async {
    ++_libraryGeneration;
    for (final job in List<CatalogueJob>.of(_libraryJobs)) {
      unawaited(job.stop().catchError((Object _) {}));
    }
    await _open(
      hit.record.path,
      managed: hit.record.managed,
      label: hit.record.label,
      expectedId: hit.catalogueId,
    );
    if (!mounted ||
        _record?.path != hit.record.path ||
        _info?['catalogueId'] != hit.catalogueId) {
      return;
    }
    setState(() {
      _path = '';
      _exactPath = hit.row['relativePath'] as String;
      _mode = 'files';
      _order = 'name';
      _search.text = _exactPath;
    });
    await _query(reset: true);
    if (mounted) setState(() => _selected = hit.row);
  }

  Widget _libraryList() {
    final searching = _librarySearch.text.trim().isNotEmpty;
    final list = searching
        ? ListView.builder(
            itemCount: _libraryHits.length,
            itemBuilder: (context, index) {
              final hit = _libraryHits[index];
              return ListTile(
                title: Text(
                  '${hit.row['relativePath']}',
                  textDirection: TextDirection.ltr,
                ),
                subtitle: Text(
                  '${hit.record.label} · ${formatBytes(hit.row['bytes'] as int)}',
                ),
                onTap: _busy ? null : () => _openHit(hit),
              );
            },
          )
        : _records.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                t(
                  'No catalogues yet. Create one, open a .crispindex file, or import a Cathy/Catfish .caf file.',
                ),
              ),
            ),
          )
        : ListView.builder(
            itemCount: _records.length,
            itemBuilder: (context, index) {
              final row = _records[index];
              return ListTile(
                key: ValueKey('catalogue-library-${row.id}'),
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(row.label),
                subtitle: Text(
                  '${row.root}\n${row.path}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                ),
                onTap: _busy
                    ? null
                    : () => _open(
                        row.path,
                        managed: row.managed,
                        label: row.label,
                      ),
              );
            },
          );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            key: const ValueKey('catalogue-library-search'),
            controller: _librarySearch,
            decoration: InputDecoration(
              labelText: t('Search files across catalogues'),
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 300),
                () => unawaited(_searchLibrary()),
              );
            },
            onSubmitted: (_) => unawaited(_searchLibrary()),
          ),
        ),
        if (searching)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              t(
                'Showing up to 200 matches. Open a catalogue to browse all matches.',
              ),
            ),
          ),
        if (_libraryLoading) const LinearProgressIndicator(),
        Expanded(
          child: searching && _libraryHits.isEmpty && !_libraryLoading
              ? Center(child: Text(t('No matching entries.')))
              : list,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact =
        size.width < 700 ||
        size.height < 650 ||
        MediaQuery.textScalerOf(context).scale(16) > 24;
    final controls = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: Text(t('New catalogue')),
          ),
          TextButton.icon(
            onPressed: _busy ? null : () => _chooseOpen(false),
            icon: const Icon(Icons.folder_open),
            label: Text(t('Open catalogue')),
          ),
          TextButton.icon(
            onPressed: _busy ? null : () => _chooseOpen(true),
            icon: const Icon(Icons.file_open_outlined),
            label: Text(t('Import CAF')),
          ),
          if (widget.onSavedReports != null)
            TextButton(
              onPressed: _busy ? null : widget.onSavedReports,
              child: Text(t('Saved analyzer reports')),
            ),
          if (_record != null)
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      setState(() {
                        ++_generation;
                        _record = null;
                        _info = null;
                        _report = null;
                      });
                    },
              child: Text(t('Catalogues')),
            ),
        ],
      ),
    );
    final notice = ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 130),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: SelectableText(
          _error ?? _notice ?? '',
          style: TextStyle(
            color: _error == null ? null : Theme.of(context).colorScheme.error,
          ),
          textDirection: TextDirection.ltr,
        ),
      ),
    );
    final content = _record != null
        ? _workspace(compact: compact)
        : compact
        ? SizedBox(height: 360, child: _libraryList())
        : _libraryList();
    final body = Column(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        controls,
        if (_error != null || _notice != null) notice,
        if (_busy) _progress(),
        const Divider(height: 1),
        if (compact) content else Expanded(child: content),
      ],
    );
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_close());
      },
      child: Dialog(
        insetPadding: EdgeInsets.all(size.width < 600 ? 6 : 20),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: math.min(1280, size.width - 12),
          height: math.min(920, size.height - 24),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t('Catalogues'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: t('Close'),
                      onPressed: _close,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: !_backend.supported
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            t(
                              'Catalogue tools currently require the desktop app.',
                            ),
                          ),
                        ),
                      )
                    : compact
                    ? SingleChildScrollView(child: body)
                    : body,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
