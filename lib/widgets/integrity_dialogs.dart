import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/checksum_service.dart';
import '../services/file_integrity_service.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import '../services/file_split_service.dart';
import '../services/integrity_recovery_service.dart';
import '../services/transfer_journal.dart';
import 'integrity_recovery_dialog.dart';
import 'commander_review_dialog.dart';
import '../utils/formatters.dart';

class _IntegrityFile {
  const _IntegrityFile(this.file, this.origin);
  final FileItem file;
  final PanelFileOrigin origin;
  String get label => '${origin.source.displayName}: ${file.path ?? file.name}';
}

List<_IntegrityFile> _captureFiles(
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files,
) {
  if (files.isEmpty ||
      files.any((file) => file.isFolder || file.path == null)) {
    throw StateError('Select regular files for this command.');
  }
  final panel = ref.read(panelProvider(side));
  return [
    for (final file in files)
      _IntegrityFile(
        file,
        panel.originForOperation(file) ??
            (throw StateError(
              'Reopen ${file.name} from its original storage account.',
            )),
      ),
  ];
}

void _showIntegrityError(BuildContext context, Object error) {
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$error')));
  }
}

bool isChecksumManifest(String name) => RegExp(
  r'\.(md5|sha1|sha256|sha512|sfv)$',
  caseSensitive: false,
).hasMatch(name);
bool isSplitPartOrManifest(String name) =>
    name.toLowerCase().endsWith('.split.json') ||
    RegExp(r'\.(?:part)?\d{3,}$', caseSensitive: false).hasMatch(name);

Future<void> showChecksumToolsDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files, {
  bool verifyInitially = false,
}) async {
  try {
    final prepared = await ref
        .read(panelProvider(side))
        .prepareOperationFiles(files);
    if (!context.mounted) return;
    final captured = _captureFiles(ref, side, prepared);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _ChecksumDialog(files: captured, verifyInitially: verifyInitially),
    );
    if (context.mounted) await ref.read(panelProvider(side)).refresh();
  } catch (error) {
    if (context.mounted) _showIntegrityError(context, error);
  }
}

class _ChecksumDialog extends ConsumerStatefulWidget {
  const _ChecksumDialog({required this.files, required this.verifyInitially});
  final List<_IntegrityFile> files;
  final bool verifyInitially;
  @override
  ConsumerState<_ChecksumDialog> createState() => _ChecksumDialogState();
}

class _ChecksumDialogState extends ConsumerState<_ChecksumDialog> {
  ChecksumAlgorithm _algorithm = ChecksumAlgorithm.sha256;
  final _output = TextEditingController(text: 'checksums.sha256');
  final _results = <({String name, String digest, String? detail, bool? ok})>[];
  bool _running = false;
  bool _cancelled = false;
  String? _error;
  String Function(BuildContext)? _status;
  double? _progress;
  bool get _singleAccount =>
      widget.files.map((file) => file.origin.storageId).toSet().length == 1;
  bool get _canVerify =>
      widget.files.every((file) => isChecksumManifest(file.file.name));
  @override
  void initState() {
    super.initState();
    if (widget.verifyInitially) unawaited(_verify());
  }

  @override
  void dispose() {
    _cancelled = true;
    _output.dispose();
    super.dispose();
  }

  FileOperationBackend _backend(_IntegrityFile file) => fileOperationBackend(
    source: file.origin.source,
    local: ref.read(localFileServiceProvider),
    isCurrent: () => mounted && file.origin.isCurrent,
  );
  void _update(String phase, int bytes, int? total) {
    if (mounted) {
      setState(() {
        _status = (_) =>
            '$phase · ${formatBytes(bytes)}${total == null ? '' : ' / ${formatBytes(total)}'}';
        _progress = total == null || total == 0
            ? null
            : (bytes / total).clamp(0.0, 1.0);
      });
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _running = true;
      _cancelled = false;
      _error = null;
      _status = null;
      _progress = null;
      _results.clear();
    });
    try {
      await work();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _calculate() => _run(() async {
    for (final file in widget.files) {
      final digest = await ChecksumService.hashFile(
        _backend(file),
        file.file,
        _algorithm,
        isCancelled: () => _cancelled || !mounted,
        onProgress: (bytes, total) => _update(file.label, bytes, total),
      );
      if (mounted) {
        setState(
          () => _results.add((
            name: file.label,
            digest: digest,
            detail: null,
            ok: null,
          )),
        );
      }
    }
    if (mounted) {
      setState(
        () => _status = (context) => context.commanderTr(
          "Calculated {0} {1} checksum(s).",
          [_results.length, _algorithm.label],
        ),
      );
    }
  });
  String _commonDirectory(FileOperationBackend source) {
    var base = source.paths.dirname(widget.files.first.file.path!);
    for (final file in widget.files.skip(1)) {
      while (!source.isWithin(base, file.file.path!)) {
        final parent = source.paths.dirname(base);
        if (source.samePath(base, parent)) {
          throw StateError('The selected paths have no common directory.');
        }
        base = parent;
      }
    }
    return base;
  }

  Future<void> _create() => _run(() async {
    if (!_singleAccount) {
      throw StateError(
        'Select files from one storage account to create a manifest.',
      );
    }
    for (final file in widget.files) {
      if (!file.origin.isCurrent) {
        throw StateError('A selected source account is unavailable.');
      }
    }
    final source = _backend(widget.files.first);
    final output = await ChecksumService.createManifest(
      source,
      widget.files.map((file) => file.file).toList(),
      baseDirectory: _commonDirectory(source),
      outputName: _output.text,
      algorithm: _algorithm,
      isCancelled: () => _cancelled || !mounted,
      onProgress: (file, bytes, total) => _update(file.name, bytes, total),
    );
    if (mounted) {
      setState(
        () =>
            _status = (context) =>
                context.commanderTr("Created and verified {0}", [output]),
      );
    }
  });
  Future<void> _verify() => _run(() async {
    if (!_canVerify) {
      throw StateError(
        'Select .md5, .sha1, .sha256, .sha512 or .sfv manifests.',
      );
    }
    for (final file in widget.files) {
      final results = await ChecksumService.verifyManifest(
        _backend(file),
        file.file,
        isCancelled: () => _cancelled || !mounted,
        onProgress: (name, bytes, total) => _update(name, bytes, total),
      );
      if (mounted) {
        setState(
          () => _results.addAll(
            results.map(
              (result) => (
                name: '${file.file.name}: ${result.filename}',
                digest: result.actual,
                detail:
                    result.error ??
                    (result.ok
                        ? null
                        : context.commanderTr("Expected {0}", [
                            result.expected,
                          ])),
                ok: result.ok,
              ),
            ),
          ),
        );
      }
    }
    if (mounted) {
      setState(
        () =>
            _status = (context) =>
                context.commanderTr("{0} verified; {1} failed.", [
                  _results.where((result) => result.ok == true).length,
                  _results.where((result) => result.ok == false).length,
                ]),
      );
    }
  });
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return PopScope(
      canPop: !_running,
      child: AlertDialog(
        scrollable: true,
        title: Text(
          context.commanderTr("Checksums · {0} file(s)", [widget.files.length]),
        ),
        content: SizedBox(
          width: math.min(760, size.width - 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<ChecksumAlgorithm>(
                initialValue: _algorithm,
                decoration: InputDecoration(
                  labelText: context.commanderTr("Algorithm"),
                ),
                isExpanded: true,
                items: [
                  for (final algorithm in ChecksumAlgorithm.values)
                    DropdownMenuItem(
                      value: algorithm,
                      child: Text(algorithm.label),
                    ),
                ],
                onChanged: _running
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _algorithm = value;
                            _output.text = 'checksums.${value.extension}';
                          });
                        }
                      },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _output,
                enabled: !_running && _singleAccount,
                decoration: InputDecoration(
                  labelText: context.commanderTr("Checksum filename"),
                  helperText: context.commanderTr(
                    "Created in the common source directory; existing files are preserved.",
                  ),
                  helperMaxLines: 3,
                ),
              ),
              if (!_singleAccount)
                Text(
                  context.commanderTr(
                    "Mixed accounts: calculate or verify each source. Select one account to create a manifest.",
                  ),
                ),
              if (_running) LinearProgressIndicator(value: _progress),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(_status!(context)),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_results.isNotEmpty)
                SizedBox(
                  height: math.min(260, size.height * .3),
                  child: ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final result = _results[index];
                      return ListTile(
                        dense: true,
                        leading: result.ok == null
                            ? null
                            : Icon(
                                result.ok!
                                    ? Icons.check_circle_outline
                                    : Icons.error_outline,
                                color: result.ok!
                                    ? Colors.green
                                    : Theme.of(context).colorScheme.error,
                              ),
                        title: Text(result.name),
                        subtitle: SelectableText(
                          '${result.digest}${result.detail == null ? '' : '\n${result.detail}'}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: context.commanderTr("Copy checksum"),
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: result.digest),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (_running)
            TextButton(
              onPressed: () => setState(() => _cancelled = true),
              child: Text(context.commanderTr("Cancel operation")),
            )
          else ...[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.commanderTr("Close")),
            ),
            TextButton(
              onPressed: _canVerify ? _verify : null,
              child: Text(context.commanderTr("Verify selected manifests")),
            ),
            OutlinedButton(
              onPressed: _singleAccount ? _create : null,
              child: Text(context.commanderTr("Create checksum file")),
            ),
            FilledButton(
              onPressed: _calculate,
              child: Text(context.commanderTr("Calculate")),
            ),
          ],
        ],
      ),
    );
  }
}

class _IntegrityDestination {
  const _IntegrityDestination(this.origin, this.path, this.isSource);
  final PanelFileOrigin origin;
  final String path;
  final bool isSource;
  String label(BuildContext context) =>
      '${origin.source.displayName} · ${context.commanderTr(isSource ? "Source folder" : "Opposite panel")}';
}

Future<void> showSplitFileDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  FileItem file,
) => _showSplitCombineDialog(context, ref, side, [file], combining: false);
Future<void> showCombinePartsDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files,
) => _showSplitCombineDialog(context, ref, side, files, combining: true);

Future<void> _showSplitCombineDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files, {
  required bool combining,
}) async {
  try {
    final panel = ref.read(panelProvider(side));
    final prepared = await panel.prepareOperationFiles(files);
    if (!context.mounted) return;
    final captured = _captureFiles(ref, side, prepared);
    final origin = panel.captureOperationOrigin(prepared);
    final backend = fileOperationBackend(
      source: origin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: () => origin.isCurrent,
    );
    final destinations = [
      _IntegrityDestination(
        origin,
        backend.paths.dirname(prepared.first.path!),
        true,
      ),
    ];
    try {
      final other = ref
          .read(
            panelProvider(
              side == PanelSide.local ? PanelSide.remote : PanelSide.local,
            ),
          )
          .captureCurrentOrigin();
      destinations.add(
        _IntegrityDestination(other, other.source.currentPath, false),
      );
    } catch (_) {
      /* An unavailable or virtual panel cannot be a destination. */
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SplitCombineDialog(
        files: captured,
        destinations: destinations,
        combining: combining,
      ),
    );
    if (context.mounted) {
      await ref.read(panelProvider(side)).refresh();
      await ref
          .read(
            panelProvider(
              side == PanelSide.local ? PanelSide.remote : PanelSide.local,
            ),
          )
          .refresh();
    }
  } catch (error) {
    if (context.mounted) _showIntegrityError(context, error);
  }
}

class _SplitCombineDialog extends ConsumerStatefulWidget {
  const _SplitCombineDialog({
    required this.files,
    required this.destinations,
    required this.combining,
  });
  final List<_IntegrityFile> files;
  final List<_IntegrityDestination> destinations;
  final bool combining;
  @override
  ConsumerState<_SplitCombineDialog> createState() =>
      _SplitCombineDialogState();
}

class _SplitCombineDialogState extends ConsumerState<_SplitCombineDialog> {
  final _partSize = TextEditingController(text: '10');
  final _directory = TextEditingController();
  final _outputName = TextEditingController();
  int _destination = 0;
  bool _loading = false;
  bool _running = false;
  bool _cancelled = false;
  bool _legacyConfirmed = false;
  bool _finished = false;
  FileOperationControl _recoveryControl = FileOperationControl();
  String? _recoveryJobId;
  FileItem? _manifestFile;
  SplitManifest? _manifest;
  List<FileItem> _legacy = [];
  String? _error;
  String Function(BuildContext)? _status;
  double? _progress;
  FileOperationBackend _backend(PanelFileOrigin origin) => fileOperationBackend(
    source: origin.source,
    local: ref.read(localFileServiceProvider),
    isCurrent: () => mounted && origin.isCurrent,
  );
  @override
  void initState() {
    super.initState();
    _directory.text = widget.destinations.first.path;
    if (widget.combining) unawaited(_inspectParts());
  }

  @override
  void dispose() {
    _cancelled = true;
    _recoveryControl.cancel();
    _partSize.dispose();
    _directory.dispose();
    _outputName.dispose();
    super.dispose();
  }

  Future<void> _inspectParts() async {
    setState(() => _loading = true);
    try {
      final source = _backend(widget.files.first.origin);
      final file = widget.files.first.file;
      FileItem? manifest;
      if (file.name.toLowerCase().endsWith('.split.json')) {
        if (widget.files.length != 1) {
          throw StateError('Choose one split manifest at a time.');
        }
        manifest = file;
      } else {
        final match = RegExp(
          r'^(.*?)\.(?:part)?\d{3,}$',
          caseSensitive: false,
        ).firstMatch(file.path!);
        if (match == null) {
          throw StateError('Choose a split manifest or numbered parts.');
        }
        final prefix = match[1]!;
        if (widget.files.any(
          (selected) => !source.samePath(
            selected.file.path!.replaceFirst(
              RegExp(r'\.(?:part)?\d{3,}$', caseSensitive: false),
              '',
            ),
            prefix,
          ),
        )) {
          throw StateError('The selected parts belong to different files.');
        }
        manifest = await source.stat('$prefix.split.json');
        if (manifest == null) {
          final siblings = await source.list(source.paths.dirname(file.path!));
          final matching = siblings
              .where(
                (candidate) =>
                    !candidate.isFolder &&
                    RegExp(
                      '^${RegExp.escape(source.paths.basename(prefix))}\\.(?:part)?\\d{3,}\$',
                      caseSensitive: false,
                    ).hasMatch(candidate.name),
              )
              .toList();
          _legacy = FileSplitService.orderedLegacyParts(source, matching);
          _outputName.text = '${source.paths.basename(prefix)}.combined';
        }
      }
      if (manifest != null) {
        _manifest = await FileSplitService.readManifest(
          source,
          manifest,
          isCancelled: () => _cancelled || !mounted,
        );
        if (_manifest!.status != SplitManifestStatus.complete) {
          throw StateError(
            'The split is ${_manifest!.status.name}: ${_manifest!.parts.length} of ${_manifest!.expectedParts} recorded parts.',
          );
        }
        _manifestFile = manifest;
        _outputName.text = '${_manifest!.originalName}.combined';
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _start() async {
    if (_running || _loading || _finished) return;
    _recoveryControl = FileOperationControl();
    setState(() {
      _running = true;
      _cancelled = false;
      _error = null;
      _progress = null;
    });
    try {
      final source = _backend(widget.files.first.origin);
      final destination = _backend(widget.destinations[_destination].origin);
      final recovery = IntegrityRecoveryService(
        ref.read(transferJournalProvider),
      );
      void created(String id) {
        if (mounted) {
          setState(() => _recoveryJobId = id);
          unawaited(_refreshRecoveryHistory());
        }
      }

      void progress(String _, int bytes, int total) {
        if (mounted) {
          setState(() {
            _status = (context) => context.commanderTr(
              widget.combining
                  ? "Combining and verifying parts… {0} / {1}"
                  : "Splitting and verifying parts… {0} / {1}",
              [formatBytes(bytes), formatBytes(total)],
            );
            _progress = total == 0 ? null : (bytes / total).clamp(0.0, 1.0);
          });
        }
      }

      if (widget.combining) {
        final output = resolveIntegrityPath(
          destination,
          _directory.text,
          _outputName.text,
        );
        if (!destination.samePath(
          destination.paths.dirname(output),
          _directory.text,
        )) {
          throw StateError(
            'Enter a filename, and choose its directory separately.',
          );
        }
        final manifest = _manifestFile;
        if (manifest != null) {
          await recovery.startCombine(
            source: source,
            manifestFile: manifest,
            reviewedManifest: _manifest!,
            destination: destination,
            outputPath: output,
            control: _recoveryControl,
            onProgress: progress,
            onJobCreated: created,
          );
        } else {
          await recovery.startCombine(
            source: source,
            legacyParts: _legacy,
            destination: destination,
            outputPath: output,
            allowUnverifiedLegacy: _legacyConfirmed,
            control: _recoveryControl,
            onProgress: progress,
            onJobCreated: created,
          );
        }
        if (mounted) {
          setState(() {
            _status = (context) => context.commanderTr(
              manifest == null
                  ? "Combined legacy parts: {0}"
                  : "Combined and verified: {0}",
              [output],
            );
            _finished = true;
          });
        }
      } else {
        final size = int.tryParse(_partSize.text);
        if (size == null || size <= 0) {
          throw ArgumentError('Enter a positive whole part size in MiB.');
        }
        final result = await recovery.startSplit(
          source: source,
          file: widget.files.single.file,
          destination: destination,
          targetDirectory: _directory.text,
          chunkSizeBytes: size * 1024 * 1024,
          control: _recoveryControl,
          onProgress: progress,
          onJobCreated: created,
        );
        if (mounted) {
          setState(() {
            _status = (context) => context.commanderTr(
              "Created {0} verified part(s). Keep {1} with the parts.",
              [result.partPaths.length, result.manifestPath],
            );
            _finished = true;
          });
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is SplitManifestChangedException
              ? context.commanderTr(SplitManifestChangedException.message)
              : '$error',
        );
      }
    } finally {
      await _refreshRecoveryHistory();
      if (mounted) {
        setState(() {
          _running = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _refreshRecoveryHistory() async {
    if (!mounted) return;
    try {
      await ref.read(transferProvider).refreshIntegrityHistory();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _running || _loading;
    return PopScope(
      canPop: !busy,
      child: CommanderReviewDialog(
        width: 640,
        title: widget.combining
            ? context.commanderTr("Combine file parts")
            : context.commanderTr("Split {0}", [widget.files.single.file.name]),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _destination,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.commanderTr("Destination account"),
                  ),
                  items: [
                    for (
                      var index = 0;
                      index < widget.destinations.length;
                      index++
                    )
                      DropdownMenuItem(
                        value: index,
                        child: Text(
                          widget.destinations[index].label(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: busy || _finished
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _destination = value;
                              _directory.text = widget.destinations[value].path;
                            });
                          }
                        },
                ),
                TextField(
                  controller: _directory,
                  enabled: !busy && !_finished,
                  decoration: InputDecoration(
                    labelText: context.commanderTr("Destination directory"),
                  ),
                ),
                if (!widget.combining) ...[
                  TextField(
                    controller: _partSize,
                    enabled: !busy && !_finished,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.commanderTr("Part size (MiB)"),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      context.commanderTr(
                        "Each part and the original file receive a SHA-256 checksum. Keep the .split.json manifest with the numbered parts. Cancelling keeps completed parts and an incomplete manifest.",
                      ),
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: _outputName,
                    enabled: !busy && !_finished,
                    decoration: InputDecoration(
                      labelText: context.commanderTr("Combined filename"),
                    ),
                  ),
                  if (_manifest != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        context.commanderTr(
                          "{0} parts · {1} · original SHA-256 verified before commit",
                          [
                            _manifest!.expectedParts,
                            formatBytes(_manifest!.totalBytes),
                          ],
                        ),
                      ),
                    ),
                  if (!_loading && _manifestFile == null && _legacy.isNotEmpty)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _legacyConfirmed,
                      onChanged: busy || _finished
                          ? null
                          : (value) => setState(
                              () => _legacyConfirmed = value ?? false,
                            ),
                      title: Text(
                        context.commanderTr(
                          "Combine {0} legacy parts without an original checksum",
                          [_legacy.length],
                        ),
                      ),
                      subtitle: Text(
                        context.commanderTr(
                          "A missing final part cannot be detected without a manifest.",
                        ),
                      ),
                    ),
                ],
                if (busy) LinearProgressIndicator(value: _progress),
                if (_status != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Semantics(
                      liveRegion: true,
                      child: SelectableText(_status!(context)),
                    ),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                Text(
                  context.commanderTr(
                    "Existing files are preserved. Choose a new filename or destination when a collision is reported.",
                  ),
                ),
              ],
            ),
          ),
        ],
        actions: [
          if (_running)
            TextButton(
              onPressed: () {
                _recoveryControl.cancel();
                setState(() => _cancelled = true);
              },
              child: Text(context.commanderTr("Cancel operation")),
            )
          else ...[
            TextButton(
              onPressed: _loading
                  ? null
                  : () async {
                      await showIntegrityRecoveryDialog(
                        context,
                        ref,
                        jobId: _recoveryJobId,
                      );
                      if (mounted && _recoveryJobId != null) {
                        setState(() {
                          _finished =
                              ref
                                  .read(transferJournalProvider)
                                  .job(_recoveryJobId!)
                                  ?.isFinished ==
                              true;
                          if (_finished) {
                            _error = null;
                            _status = (context) => context.commanderTr(
                              'Saved operation completed and verified.',
                            );
                          }
                        });
                      }
                    },
              child: Text(context.commanderTr('Split/combine recovery')),
            ),
            TextButton(
              onPressed: _loading ? null : () => Navigator.pop(context),
              child: Text(context.commanderTr("Close")),
            ),
            if (!_finished)
              FilledButton(
                onPressed:
                    _loading ||
                        widget.combining &&
                            _manifestFile == null &&
                            (!_legacyConfirmed || _legacy.isEmpty)
                    ? null
                    : _start,
                child: Text(
                  widget.combining
                      ? context.commanderTr("Verify and combine")
                      : context.commanderTr("Split and verify"),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
