// lib/widgets/diff_viewer_dialog.dart
//
// Side-by-side file comparison viewer.
// Compares two text files (local vs remote, or two selected files).

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/log_service.dart';
import '../services/file_comparison_service.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import '../services/editor_document.dart';
import '../l10n/diff_viewer_strings.dart';
export '../services/file_comparison_service.dart' show DiffLine, DiffType;

/// Show a diff dialog comparing two raw text strings.
/// Used for version diff where content is already loaded.
void showDiffViewerFromContent(
  BuildContext context, {
  required String leftContent,
  required String rightContent,
  String? leftLabel,
  String? rightLabel,
}) {
  showDialog(
    context: context,
    builder: (_) => _ContentDiffDialog(
      leftContent: leftContent,
      rightContent: rightContent,
      leftLabel: leftLabel ?? DiffViewerStrings(context).text('left'),
      rightLabel: rightLabel ?? DiffViewerStrings(context).text('right'),
    ),
  );
}

void showDiffViewerDialog(
  BuildContext context,
  WidgetRef ref,
  FileItem leftFile,
  FileItem rightFile, {
  PanelSide leftSide = PanelSide.local,
  PanelSide rightSide = PanelSide.remote,
}) {
  showDialog(
    context: context,
    builder: (_) => _DiffViewerDialog(
      leftFile: leftFile,
      rightFile: rightFile,
      leftSide: leftSide,
      rightSide: rightSide,
    ),
  );
}

class _DiffViewerDialog extends ConsumerStatefulWidget {
  final FileItem leftFile;
  final FileItem rightFile;
  final PanelSide leftSide;
  final PanelSide rightSide;

  const _DiffViewerDialog({
    required this.leftFile,
    required this.rightFile,
    required this.leftSide,
    required this.rightSide,
  });

  @override
  ConsumerState<_DiffViewerDialog> createState() => _DiffViewerDialogState();
}

class _DiffViewerDialogState extends ConsumerState<_DiffViewerDialog> {
  static const _log = Log('DiffViewer');
  static const _binaryLimits = BinaryComparisonLimits();
  final _scroll = ScrollController();
  final _merged = TextEditingController();
  final _binaryAddress = TextEditingController(text: '0');
  FileOperationBackend? _leftSource;
  FileOperationBackend? _rightSource;
  FileItem? _leftVersion, _rightVersion;
  PanelFileOrigin? _leftOrigin;
  PanelFileOrigin? _writeOrigin;
  bool _swapped = false;
  FileItem get _leftFile => _swapped ? widget.rightFile : widget.leftFile;
  FileItem get _rightFile => _swapped ? widget.leftFile : widget.rightFile;
  PanelSide get _leftSide => _swapped ? widget.rightSide : widget.leftSide;
  PanelSide get _rightSide => _swapped ? widget.leftSide : widget.rightSide;
  MergeDocumentSession? _leftDocument;
  MergeDocumentSession? _rightDocument;
  BinaryComparison? _binaryResult;
  BinaryComparisonSession? _binarySession;
  BinaryComparisonWindow? _binaryWindow;
  BinaryDifferenceRange? _binaryRange;
  int _binaryRangeIndex = 0;
  bool _binaryBusy = false;
  EditorEncoding? _leftEncoding, _rightEncoding;
  List<DiffLine> _rows = [];
  List<DiffHunk> _hunks = [];
  int _hunkIndex = 0;
  bool _loading = true;
  bool _binary = false;
  bool _edit = false;
  bool _ignoreWhitespace = false;
  bool _ignoreCase = false;
  bool _dirty = false;
  bool _cancel = false;
  bool _capturing = false;
  int _loadGeneration = 0;
  int _navigationGeneration = 0;
  String? _error;
  int _comparedBytes = 0;

  @override
  void initState() {
    super.initState();
    _binary =
        (_leftFile.size ?? 0) > MergeDocumentSession.maxTextBytes ||
        (_rightFile.size ?? 0) > MergeDocumentSession.maxTextBytes;
    _loadFiles();
  }

  FileOperationBackend _source(FileItem file, PanelSide side) {
    final origin = ref.read(panelProvider(side)).captureOperationOrigin([file]);
    return fileOperationBackend(
      source: origin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: () => mounted && origin.isCurrent,
    );
  }

  Future<void> _loadFiles() async {
    final generation = ++_loadGeneration;
    ++_navigationGeneration;
    final previousSession = _binarySession;
    BinaryComparisonSession? openingSession;
    bool ownsLoad() => mounted && generation == _loadGeneration;
    bool cancelled() => !ownsLoad() || _cancel;
    setState(() {
      _loading = true;
      _binaryBusy = false;
      _cancel = false;
      _capturing = _binary;
      _error = null;
      _comparedBytes = 0;
      _binaryResult = null;
      _binarySession = null;
      _binaryWindow = null;
      _binaryRange = null;
      _rows = [];
      _hunks = [];
      _leftDocument = null;
      _rightDocument = null;
    });
    try {
      // Retire the previous immutable copies before allocating replacements.
      // An older load owns its unpublished session and closes it in finally.
      await _releaseBinarySession(previousSession);
      if (cancelled()) return;
      _leftOrigin ??= ref
          .read(panelProvider(_leftSide))
          .originForOperation(_leftFile);
      _leftSource ??= _source(_leftFile, _leftSide);
      _rightSource ??= _source(_rightFile, _rightSide);
      _writeOrigin ??= ref
          .read(panelProvider(_rightSide))
          .originForOperation(_rightFile);
      final leftSource = _leftSource!;
      final rightSource = _rightSource!;
      final leftFile = _leftVersion ?? _leftFile;
      final rightFile = _rightVersion ?? _rightFile;
      bool sourceCancelled() =>
          cancelled() || !leftSource.isCurrent || !rightSource.isCurrent;
      if (_binary) {
        var lastProgress = 0;
        final session = await BinaryComparisonSession.open(
          leftSource,
          leftFile,
          rightSource,
          rightFile,
          limits: _binaryLimits,
          isCancelled: sourceCancelled,
          onProgress: (bytes) {
            if (!sourceCancelled() &&
                (_capturing || bytes - lastProgress >= 256 * 1024)) {
              lastProgress = bytes;
              setState(() {
                _capturing = false;
                _comparedBytes = bytes;
              });
            }
          },
        );
        openingSession = session;
        if (sourceCancelled()) return;
        final result = session.result;
        BinaryDifferenceRange? range;
        if (result.rangeCount > 0) {
          range = await session.difference(0, isCancelled: sourceCancelled);
        }
        if (sourceCancelled()) return;
        final window = await session.window(
          ((range?.start ?? 0) ~/ 16) * 16,
          isCancelled: sourceCancelled,
        );
        if (sourceCancelled()) return;
        // Publish one complete generation. Stale futures never own UI state.
        setState(() {
          _binarySession = session;
          _binaryResult = result;
          _binaryRangeIndex = 0;
          _binaryRange = range;
          _binaryWindow = window;
          _binaryAddress.text = window.offset.toString();
        });
        openingSession = null;
      } else {
        final leftDocument = await MergeDocumentSession.open(
          leftSource,
          leftFile,
          encodingOverride: _leftEncoding,
          isCancelled: sourceCancelled,
        );
        if (sourceCancelled()) return;
        final rightDocument = await MergeDocumentSession.open(
          rightSource,
          rightFile,
          encodingOverride: _rightEncoding,
          isCancelled: sourceCancelled,
        );
        if (sourceCancelled()) return;
        setState(() {
          _leftDocument = leftDocument;
          _rightDocument = rightDocument;
          _leftVersion = leftDocument.file;
          _rightVersion = rightDocument.file;
          _merged.text = rightDocument.document.text;
          _dirty = false;
          _recompute();
        });
      }
    } catch (error) {
      if (ownsLoad()) {
        _log.warn('Comparison failed', error);
        setState(() => _error = error.toString());
      }
    } finally {
      await _releaseBinarySession(openingSession);
      if (ownsLoad()) setState(() => _loading = false);
    }
  }

  Future<void> _releaseBinarySession(BinaryComparisonSession? session) async {
    if (session == null) return;
    try {
      await session.close();
    } catch (error) {
      _log.warn('Could not close comparison copies', error);
    }
  }

  Future<void> _navigateBinary({int? difference, int? offset}) async {
    final session = _binarySession;
    if (session == null || _loading || _binaryBusy) return;
    final load = _loadGeneration;
    final navigation = ++_navigationGeneration;
    bool ownsOperation() =>
        mounted &&
        load == _loadGeneration &&
        navigation == _navigationGeneration;
    bool ownsNavigation() =>
        ownsOperation() && identical(session, _binarySession);
    bool cancelled() => !ownsNavigation() || _cancel;
    setState(() {
      _binaryBusy = true;
      _cancel = false;
      _error = null;
    });
    try {
      var range = _binaryRange;
      var rangeIndex = _binaryRangeIndex;
      if (difference != null) {
        range = await session.difference(difference, isCancelled: cancelled);
        rangeIndex = difference;
        offset = (range.start ~/ 16) * 16;
      }
      final window = await session.window(offset ?? 0, isCancelled: cancelled);
      if (cancelled()) return;
      setState(() {
        _binaryRange = range;
        _binaryRangeIndex = rangeIndex;
        _binaryWindow = window;
        _binaryAddress.text = window.offset.toString();
      });
    } catch (error) {
      if (ownsNavigation()) {
        // The service invalidates a failed or cancelled operation. Retire its
        // view as well so navigation cannot reuse a closed captured source.
        setState(() {
          _error = error.toString();
          _binarySession = null;
          _binaryResult = null;
          _binaryWindow = null;
          _binaryRange = null;
        });
        await _releaseBinarySession(session);
      }
    } finally {
      if (ownsOperation()) setState(() => _binaryBusy = false);
    }
  }

  void _goToByte(String value) {
    final input = value.trim();
    final offset = input.toLowerCase().startsWith('0x')
        ? int.tryParse(input.substring(2), radix: 16)
        : int.tryParse(input);
    if (offset == null ||
        offset < 0 ||
        offset >= (_binarySession?.totalBytes ?? 0)) {
      setState(
        () => _error = context.commanderTr(
          'Enter a byte offset inside the file (decimal or 0x hexadecimal).',
        ),
      );
      return;
    }
    _navigateBinary(offset: offset);
  }

  Widget _encodingPicker(bool left) => SizedBox(
    width: 190,
    child: DropdownButtonFormField<String>(
      key: ValueKey(
        'diff-${left ? "left" : "right"}-${(left ? _leftEncoding : _rightEncoding)?.name ?? "auto"}',
      ),
      initialValue: (left ? _leftEncoding : _rightEncoding)?.name ?? 'auto',
      isExpanded: true,
      decoration: InputDecoration(
        labelText: context.commanderTr(
          left ? 'Left encoding' : 'Right encoding',
        ),
      ),
      items: [
        DropdownMenuItem(
          value: 'auto',
          child: Text(context.commanderTr('Auto-detect')),
        ),
        for (final encoding in EditorEncoding.values)
          DropdownMenuItem(value: encoding.name, child: Text(encoding.label)),
      ],
      onChanged: _loading || _dirty
          ? null
          : (value) {
              if (value == null) return;
              setState(() {
                final encoding = value == 'auto'
                    ? null
                    : EditorEncoding.values.byName(value);
                if (left) {
                  _leftEncoding = encoding;
                } else {
                  _rightEncoding = encoding;
                }
              });
              _loadFiles();
            },
    ),
  );

  void _recompute() {
    _rows = compareTextLines(
      _leftDocument!.document.text.split('\n'),
      _merged.text.split('\n'),
      ignoreWhitespace: _ignoreWhitespace,
      ignoreCase: _ignoreCase,
    );
    _hunks = differenceHunks(_rows);
    _hunkIndex = _hunks.isEmpty ? 0 : _hunkIndex.clamp(0, _hunks.length - 1);
  }

  void _jump(int delta) {
    if (_hunks.isEmpty) return;
    setState(
      () => _hunkIndex = (_hunkIndex + delta).clamp(0, _hunks.length - 1),
    );
    if (_scroll.hasClients) {
      _scroll.jumpTo(
        (_hunks[_hunkIndex].firstRow * 24.0).clamp(
          0,
          _scroll.position.maxScrollExtent,
        ),
      );
    }
  }

  void _useLeftHunk() {
    if (_hunks.isEmpty) return;
    setState(() {
      _merged.text = mergeHunk(
        _leftDocument!.document.text,
        _merged.text,
        _hunks[_hunkIndex],
      );
      _dirty = true;
      _recompute();
    });
  }

  Future<void> _save() async {
    if (_writeOrigin?.isCurrent != true) {
      setState(
        () => _error = 'The original file source is no longer available. Reopen it before saving.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _rightDocument!.save(_merged.text);
      _rightVersion = _rightDocument!.file;
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _recompute();
      });
      await ref.read(panelProvider(_rightSide)).refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _close() async {
    if (_loading || _binaryBusy) {
      setState(() => _cancel = true);
      return;
    }
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.commanderTr("Discard unsaved merge?")),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.commanderTr("Keep editing")),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.commanderTr("Discard")),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_loading && !_binaryBusy && !_dirty,
    child: Dialog(
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width * .9,
        height: MediaQuery.sizeOf(context).height * .85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.compare_arrows),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_leftFile.name} ↔ ${_rightFile.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: _close,
                    tooltip: _loading || _binaryBusy
                        ? context.commanderTr("Stop comparison")
                        : context.commanderTr("Close"),
                    icon: Icon(
                      _loading || _binaryBusy ? Icons.stop : Icons.close,
                    ),
                  ),
                ],
              ),
            ),
            if (_dirty) Text(context.commanderTr("Unsaved merge")),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .35,
              ),
              child: SingleChildScrollView(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    IconButton(
                      tooltip: context.commanderTr(
                        "Swap files and merge target",
                      ),
                      onPressed:
                          _loading ||
                              _binaryBusy ||
                              _dirty ||
                              _leftSource == null ||
                              _rightSource == null
                          ? null
                          : () {
                              setState(() {
                                _swapped = !_swapped;
                                final previousLeftSource = _leftSource;
                                _leftSource = _rightSource;
                                _rightSource = previousLeftSource;
                                final previousLeftOrigin = _leftOrigin;
                                _leftOrigin = _writeOrigin;
                                _writeOrigin = previousLeftOrigin;
                                final previousVersion = _leftVersion;
                                _leftVersion = _rightVersion;
                                _rightVersion = previousVersion;
                                final previousEncoding = _leftEncoding;
                                _leftEncoding = _rightEncoding;
                                _rightEncoding = previousEncoding;
                                _leftDocument = null;
                                _rightDocument = null;
                                _rows = [];
                                _hunks = [];
                              });
                              _loadFiles();
                            },
                      icon: const Icon(Icons.swap_horiz),
                    ),
                    FilterChip(
                      label: Text(context.commanderTr("Binary")),
                      selected: _binary,
                      onSelected: _loading || _binaryBusy || _dirty
                          ? null
                          : (value) {
                              setState(() => _binary = value);
                              _loadFiles();
                            },
                    ),
                    if (!_binary) ...[
                      _encodingPicker(true),
                      _encodingPicker(false),
                      FilterChip(
                        label: Text(context.commanderTr("Ignore whitespace")),
                        selected: _ignoreWhitespace,
                        onSelected:
                            _loading ||
                                _leftDocument == null ||
                                _rightDocument == null
                            ? null
                            : (value) => setState(() {
                                _ignoreWhitespace = value;
                                _recompute();
                              }),
                      ),
                      FilterChip(
                        label: Text(context.commanderTr("Ignore case")),
                        selected: _ignoreCase,
                        onSelected:
                            _loading ||
                                _leftDocument == null ||
                                _rightDocument == null
                            ? null
                            : (value) => setState(() {
                                _ignoreCase = value;
                                _recompute();
                              }),
                      ),
                      IconButton(
                        onPressed: _hunks.isEmpty ? null : () => _jump(-1),
                        tooltip: context.commanderTr("Previous difference"),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      Text(
                        _hunks.isEmpty
                            ? context.commanderTr("No differences")
                            : context.commanderTr("{0} / {1} blocks", [
                                _hunkIndex + 1,
                                _hunks.length,
                              ]),
                      ),
                      IconButton(
                        onPressed: _hunks.isEmpty ? null : () => _jump(1),
                        tooltip: context.commanderTr("Next difference"),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                      TextButton.icon(
                        onPressed: _loading || _hunks.isEmpty
                            ? null
                            : _useLeftHunk,
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(context.commanderTr("Use left block")),
                      ),
                      FilterChip(
                        label: Text(
                          context.commanderTr("Edit merged right file"),
                        ),
                        selected: _edit,
                        onSelected: _loading || _rightDocument == null
                            ? null
                            : (value) => setState(() {
                                _edit = value;
                                if (!value) _recompute();
                              }),
                      ),
                      FilledButton(
                        onPressed:
                            _loading ||
                                !_dirty ||
                                _writeOrigin?.isCurrent != true
                            ? null
                            : _save,
                        child: Text(context.commanderTr("Save merge to right")),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_loading || _binaryBusy) ...[
              const LinearProgressIndicator(),
              if (_binary)
                Text(
                  _capturing
                      ? context.commanderTr(
                          'Preparing and comparing captured copies…',
                        )
                      : context.commanderTr("Compared {0} bytes", [
                          _comparedBytes,
                        ]),
                ),
            ],
            Expanded(
              child: _loading
                  ? const SizedBox.shrink()
                  : _binary
                  ? _binaryView()
                  : _textView(),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _binaryView() {
    final result = _binaryResult;
    final window = _binaryWindow;
    final session = _binarySession;
    if (result == null || window == null || session == null) {
      return Center(child: Text(context.commanderTr('No comparison result.')));
    }
    final disabled = _loading || _binaryBusy;
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final range = _binaryRange;
    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .28,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Text(
                    context.commanderTr(
                      'Verified captured copies • up to {0} per file',
                      [
                        _binaryLimits.maxBytes >= 1024 * 1024 * 1024
                            ? '${_binaryLimits.maxBytes ~/ (1024 * 1024 * 1024)} GiB'
                            : '${_binaryLimits.maxBytes ~/ (1024 * 1024)} MiB',
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SelectableText(
                    result.equal
                        ? context.commanderTr(
                            'Files are byte-for-byte identical ({0} bytes).',
                            [result.leftBytes],
                          )
                        : context.commanderTr(
                            '{0} differing bytes in {1} ranges',
                            [result.differingBytes, result.rangeCount],
                          ),
                  ),
                  if (range != null)
                    Text(
                      context.commanderTr(
                        'Difference {0} / {1}: bytes {2}–{3}',
                        [
                          _binaryRangeIndex + 1,
                          result.rangeCount,
                          range.start,
                          range.end - 1,
                        ],
                      ),
                    ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: context.commanderTr('First difference'),
                        icon: const Icon(Icons.first_page),
                        onPressed:
                            disabled ||
                                result.rangeCount == 0 ||
                                _binaryRangeIndex == 0
                            ? null
                            : () => _navigateBinary(difference: 0),
                      ),
                      IconButton(
                        tooltip: context.commanderTr('Previous difference'),
                        icon: const Icon(Icons.arrow_upward),
                        onPressed:
                            disabled ||
                                result.rangeCount == 0 ||
                                _binaryRangeIndex == 0
                            ? null
                            : () => _navigateBinary(
                                difference: _binaryRangeIndex - 1,
                              ),
                      ),
                      IconButton(
                        tooltip: context.commanderTr('Next difference'),
                        icon: const Icon(Icons.arrow_downward),
                        onPressed:
                            disabled ||
                                _binaryRangeIndex + 1 >= result.rangeCount
                            ? null
                            : () => _navigateBinary(
                                difference: _binaryRangeIndex + 1,
                              ),
                      ),
                      IconButton(
                        tooltip: context.commanderTr('Last difference'),
                        icon: const Icon(Icons.last_page),
                        onPressed:
                            disabled ||
                                _binaryRangeIndex + 1 >= result.rangeCount
                            ? null
                            : () => _navigateBinary(
                                difference: result.rangeCount - 1,
                              ),
                      ),
                      SizedBox(
                        width: 175,
                        child: TextField(
                          controller: _binaryAddress,
                          enabled: !disabled,
                          decoration: InputDecoration(
                            labelText: context.commanderTr('Go to byte'),
                            hintText: '0x1000',
                          ),
                          onSubmitted: _goToByte,
                          textInputAction: TextInputAction.go,
                        ),
                      ),
                      IconButton(
                        tooltip: context.commanderTr('Previous bytes'),
                        icon: const Icon(Icons.chevron_left),
                        onPressed: disabled || window.offset == 0
                            ? null
                            : () => _navigateBinary(
                                offset: (window.offset - 1024).clamp(
                                  0,
                                  session.totalBytes,
                                ),
                              ),
                      ),
                      IconButton(
                        tooltip: context.commanderTr('Next bytes'),
                        icon: const Icon(Icons.chevron_right),
                        onPressed:
                            disabled ||
                                window.offset + window.length >=
                                    session.totalBytes
                            ? null
                            : () => _navigateBinary(
                                offset: window.offset + window.length,
                              ),
                      ),
                      Text(
                        context.commanderTr('Bytes {0}–{1} of {2}', [
                          window.offset,
                          window.offset + window.length,
                          session.totalBytes,
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 1160 * scale,
                child: Column(
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 140 * scale,
                          child: Text(context.commanderTr('Offset')),
                        ),
                        Expanded(
                          child: Text(
                            _leftFile.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _rightFile.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: (window.length + 15) ~/ 16,
                        itemExtent: 28 * scale,
                        itemBuilder: (context, row) {
                          final start = row * 16;
                          return Row(
                            key: ValueKey(
                              'binary-row-${window.offset + start}',
                            ),
                            children: [
                              SizedBox(
                                width: 140 * scale,
                                child: Text(
                                  (window.offset + start)
                                      .toRadixString(16)
                                      .padLeft(12, '0'),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: _hexBytes(
                                  window.left,
                                  window.right,
                                  start,
                                ),
                              ),
                              Expanded(
                                child: _hexBytes(
                                  window.right,
                                  window.left,
                                  start,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _hexBytes(List<int> bytes, List<int> other, int start) {
    final colors = Theme.of(context).colorScheme;
    TextStyle? highlight(int index) =>
        (index < bytes.length || index < other.length) &&
            (index >= bytes.length ||
                index >= other.length ||
                bytes[index] != other[index])
        ? TextStyle(
            backgroundColor: colors.errorContainer,
            color: colors.onErrorContainer,
          )
        : null;
    return SelectableText.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: colors.onSurface,
        ),
        children: [
          for (var i = start; i < start + 16; i++)
            TextSpan(
              text:
                  '${i < bytes.length ? bytes[i].toRadixString(16).padLeft(2, '0') : '--'} ',
              style: highlight(i),
            ),
          const TextSpan(text: '  '),
          for (var i = start; i < start + 16; i++)
            TextSpan(
              text: i >= bytes.length
                  ? ' '
                  : bytes[i] >= 32 && bytes[i] < 127
                  ? String.fromCharCode(bytes[i])
                  : '.',
              style: highlight(i),
            ),
        ],
      ),
      maxLines: 1,
    );
  }

  Widget _textView() {
    if (_rightDocument == null) return const SizedBox.shrink();
    if (_edit) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _merged,
          expands: true,
          maxLines: null,
          minLines: null,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: context.commanderTr("Merged right • {0} • {1}", [
              _rightDocument!.document.encoding.label,
              _rightDocument!.document.lineEnding.label,
            ]),
          ),
          onChanged: (_) => setState(() {
            _dirty = true;
            _recompute();
          }),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      itemExtent: 24,
      itemCount: _rows.length,
      itemBuilder: (context, index) {
        final row = _rows[index];
        Widget cell(bool left) {
          final absent = left
              ? row.type == DiffType.added
              : row.type == DiffType.removed;
          return Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: row.type == DiffType.equal
                  ? null
                  : (left ? Colors.red : Colors.green).withValues(alpha: .12),
              child: Text(
                absent
                    ? ''
                    : '${left ? row.leftLine : row.rightLine}  ${left ? row.text : row.rightText ?? row.text}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          );
        }

        return Row(
          children: [cell(true), const VerticalDivider(width: 1), cell(false)],
        );
      },
    );
  }

  @override
  void dispose() {
    _cancel = true;
    ++_loadGeneration;
    ++_navigationGeneration;
    final session = _binarySession;
    _binarySession = null;
    unawaited(_releaseBinarySession(session));
    _scroll.dispose();
    _merged.dispose();
    _binaryAddress.dispose();
    super.dispose();
  }
}

/// Compatibility API for version comparisons; implementation is memory-bounded.
List<DiffLine> computeLcsDiff(List<String> left, List<String> right) =>
    compareTextLines(left, right);

/// Diff viewer for pre-loaded content (used by version diff).
class _ContentDiffDialog extends StatelessWidget {
  final String leftContent;
  final String rightContent;
  final String leftLabel;
  final String rightLabel;

  const _ContentDiffDialog({
    required this.leftContent,
    required this.rightContent,
    required this.leftLabel,
    required this.rightLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final leftLines = leftContent.split('\n');
    final rightLines = rightContent.split('\n');
    final diffResult = computeLcsDiff(leftLines, rightLines);

    final added = diffResult.where((d) => d.type == DiffType.added).length;
    final removed = diffResult.where((d) => d.type == DiffType.removed).length;
    final addedColor = Colors.green.withValues(alpha: 0.15);
    final removedColor = Colors.red.withValues(alpha: 0.15);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  const Icon(Icons.compare, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    context.commanderTr("Version Diff"),
                    style: theme.textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Text(
                    '+$added',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '-$removed',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: diffResult.isEmpty
                  ? Center(
                      child: Text(context.commanderTr("Files are identical")),
                    )
                  : Row(
                      children: [
                        _buildPane(
                          theme,
                          leftLabel,
                          diffResult,
                          true,
                          addedColor,
                          removedColor,
                        ),
                        Container(width: 1, color: theme.dividerColor),
                        _buildPane(
                          theme,
                          rightLabel,
                          diffResult,
                          false,
                          addedColor,
                          removedColor,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPane(
    ThemeData theme,
    String label,
    List<DiffLine> diff,
    bool isLeft,
    Color addedColor,
    Color removedColor,
  ) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            child: Row(
              children: [
                const Icon(Icons.description, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: diff.length,
              itemExtent: 20,
              itemBuilder: (_, index) {
                final d = diff[index];
                // Skip lines not visible on this side
                if (isLeft && d.type == DiffType.added) {
                  return Container(height: 20, color: addedColor);
                }
                if (!isLeft && d.type == DiffType.removed) {
                  return Container(height: 20, color: removedColor);
                }

                return Container(
                  height: 20,
                  color: d.type == DiffType.removed
                      ? removedColor
                      : d.type == DiffType.added
                      ? addedColor
                      : null,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          (isLeft ? d.leftLine : d.rightLine)?.toString() ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          d.text,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.clip,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
