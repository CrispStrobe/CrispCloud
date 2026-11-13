import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/archive_creation_strings.dart';
import '../l10n/archive_external_packer_strings.dart';
import '../models/file_item.dart';
import '../services/archive_creation_service.dart';
import '../services/archive_external_packer.dart';
import '../services/file_operation_service.dart';

Future<ArchiveCreationResult?> showArchiveExternalPackerDialog(
  BuildContext context, {
  required FileOperationBackend source,
  required FileOperationBackend destination,
  required List<FileItem> files,
  required String destinationDirectory,
  ArchiveExternalPackerService? service,
  ArchiveExternalPackerPreferences? preferences,
  VoidCallback? onCreated,
  ValueChanged<ArchiveCreationResult>? onPublished,
}) async {
  ArchiveCreationResult? capturedReceipt;
  final dialogResult = await showDialog<ArchiveCreationResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ArchiveExternalPackerDialog(
      source: source,
      destination: destination,
      files: List.unmodifiable(files),
      destinationDirectory: destinationDirectory,
      service: service,
      preferences: preferences,
      onCreated: onCreated,
      onPublished: (result) {
        capturedReceipt = result;
        try {
          onPublished?.call(result);
        } catch (error) {
          capturedReceipt = _withPublicationWarning(result, error);
          rethrow;
        }
      },
    ),
  );
  // The publication receipt includes observer warnings that a route's earlier
  // return value may not contain. A pop cannot replace that verified outcome.
  return capturedReceipt ?? dialogResult;
}

ArchiveCreationResult _withPublicationWarning(
  ArchiveCreationResult result,
  Object error,
) => result.publicationWarning != null
    ? result
    : ArchiveCreationResult(
        result.path,
        result.entryCount,
        result.bytes,
        publicationWarning: error,
      );

class ArchiveExternalPackerDialog extends StatefulWidget {
  const ArchiveExternalPackerDialog({
    super.key,
    required this.source,
    required this.destination,
    required this.files,
    required this.destinationDirectory,
    this.service,
    this.preferences,
    this.onCreated,
    this.onPublished,
  });
  final FileOperationBackend source, destination;
  final List<FileItem> files;
  final String destinationDirectory;
  final ArchiveExternalPackerService? service;
  final ArchiveExternalPackerPreferences? preferences;
  final VoidCallback? onCreated;
  final ValueChanged<ArchiveCreationResult>? onPublished;

  @override
  State<ArchiveExternalPackerDialog> createState() =>
      _ArchiveExternalPackerDialogState();
}

class _ArchiveExternalPackerDialogState
    extends State<ArchiveExternalPackerDialog> {
  final _executable = TextEditingController();
  late final TextEditingController _name;
  late final ArchiveExternalPackerService _service;
  ArchiveExternalPackerPreferences? _preferences;
  ArchiveExternalPackerKind _kind = ArchiveExternalPackerKind.sevenZip;
  ArchiveExternalPackerFormat _format = ArchiveExternalPackerFormat.zip;
  ArchiveExternalPackerCompression _compression =
      ArchiveExternalPackerCompression.normal;
  ArchiveExternalSevenZipProfile _sevenZipProfile =
      const ArchiveExternalSevenZipProfile();
  ArchiveExternalPackerInstallation? _installation;
  List<ArchiveExternalPackerConfiguration> _candidates = const [];
  ArchiveCreationProgress? _progress;
  ArchiveCreationResult? _result;
  bool _busy = true, _cancelled = false, _saved = false, _searched = false;
  String? _activity;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ArchiveExternalPackerService();
    _preferences =
        widget.preferences ??
        (_service.platform == null
            ? null
            : ArchiveExternalPackerStore(_service.platform!));
    final first = widget.files.length == 1 ? widget.files.single : null;
    final stem = first == null
        ? 'archive'
        : first.isFolder
        ? first.name
        : p.basenameWithoutExtension(first.name);
    _name = TextEditingController(text: '$stem.zip');
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = await _preferences?.load();
      if (!mounted) return;
      if (saved != null) {
        _executable.text = saved.executable;
        _kind = saved.kind;
        _saved = true;
      }
    } catch (error) {
      if (mounted) _error = error;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    _executable.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(String activity, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _cancelled = false;
      _activity = activity;
      _error = null;
      _progress = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _activity = null;
        });
      }
    }
  }

  Future<void> _discover() => _run('Finding installed tools…', () async {
    final found = await _service.discover();
    if (mounted) {
      setState(() {
        _candidates = found;
        _searched = true;
      });
    }
  });

  Future<void> _probe() => _run('Checking tool capabilities…', () async {
    setState(() => _installation = null);
    final platform = _service.platform;
    if (platform == null) {
      throw const ArchiveExternalPackerException(
        ArchiveExternalPackerFailure.unsupportedPlatform,
      );
    }
    final installation = await _service.probe(
      ArchiveExternalPackerConfiguration(
        platform: platform,
        kind: _kind,
        executable: _executable.text,
      ),
      sevenZipProfile:
          _kind == ArchiveExternalPackerKind.sevenZip &&
              _format == ArchiveExternalPackerFormat.sevenZip
          ? _sevenZipProfile
          : const ArchiveExternalSevenZipProfile(),
      isCancelled: () => _cancelled || !mounted,
    );
    if (!mounted) return;
    setState(() {
      _installation = installation;
      if (!installation.formats.contains(_format)) {
        _chooseFormat(installation.formats.first);
      }
    });
  });

  Future<void> _remember() => _run('Saving tool settings…', () async {
    final installation = _installation;
    if (installation == null || _preferences == null) return;
    await _preferences!.save(installation.configuration);
    if (mounted) setState(() => _saved = true);
  });

  Future<void> _forget() => _run('Saving tool settings…', () async {
    await _preferences?.reset();
    if (mounted) setState(() => _saved = false);
  });

  void _chooseFormat(ArchiveExternalPackerFormat value) {
    if (_name.text.toLowerCase().endsWith(_format.extension)) {
      _name.text =
          '${_name.text.substring(0, _name.text.length - _format.extension.length)}${value.extension}';
    }
    _format = value;
  }

  Future<void> _create() async {
    if (!mounted || _busy || _result != null) return;
    await _run('Creating verified archive…', () async {
      final installation = _installation;
      if (installation == null) return;
      var result = await _service.create(
        source: widget.source,
        destination: widget.destination,
        files: widget.files,
        destinationDirectory: widget.destinationDirectory,
        installation: installation,
        options: ArchiveExternalPackerOptions(
          name: _name.text,
          format: _format,
          compression: _compression,
          sevenZipProfile: _format == ArchiveExternalPackerFormat.sevenZip
              ? _sevenZipProfile
              : const ArchiveExternalSevenZipProfile(),
        ),
        isCancelled: () => _cancelled || !mounted,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      // Publication is final before observers run. A route removal or observer
      // failure must not make this completed output eligible for another try.
      _result = result;
      if (mounted) setState(() {});
      try {
        widget.onCreated?.call();
      } catch (error) {
        result = _withPublicationWarning(result, error);
      }
      _result = result;
      try {
        widget.onPublished?.call(result);
      } catch (error) {
        result = _withPublicationWarning(result, error);
      }
      _result = result;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    String tr(String key, [List<Object?> values = const []]) =>
        archiveExternalPackerText(context, key, values);
    String common(String key, [List<Object?> values = const []]) =>
        archiveCreationText(context, key, values);
    final supported = _service.platform != null;
    final enabled = supported && !_busy && _result == null;
    final installation = _installation;
    final profileVerified =
        _format != ArchiveExternalPackerFormat.sevenZip ||
        installation?.sevenZipProfile == _sevenZipProfile;
    final formats =
        installation?.formats.toList() ?? const <ArchiveExternalPackerFormat>[];
    final progress = _progress;
    Widget profileChoice({
      required String key,
      required String label,
      required int value,
      required List<int> choices,
      required void Function(int) choose,
      bool available = true,
      bool memorySize = true,
    }) => DropdownButtonFormField<int>(
      key: ValueKey('archive-external-$key'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: tr(label),
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final choice in choices)
          DropdownMenuItem(
            value: choice,
            child: Text(
              choice == 0 ? tr('Off') : '$choice${memorySize ? ' MiB' : ''}',
            ),
          ),
      ],
      onChanged: enabled && available
          ? (value) {
              if (value == null) return;
              setState(() {
                choose(value);
                _error = null;
              });
            }
          : null,
    );
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(tr('External archive tool')),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(common('Selected items: {0}', [widget.files.length])),
                const SizedBox(height: 4),
                SelectableText(
                  common('Destination: {0}', [widget.destinationDirectory]),
                ),
                const SizedBox(height: 12),
                Text(
                  tr(
                    supported
                        ? 'Create a fresh ZIP, 7z or RAR5 archive with an installed tool. Up to 64 MiB per file and 256 MiB total. Contents are verified before saving.'
                        : 'External tools are available in desktop builds that permit local processes.',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<ArchiveExternalPackerKind>(
                  key: const ValueKey('archive-external-kind'),
                  initialValue: _kind,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr('Installed tool'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final kind in ArchiveExternalPackerKind.values)
                      DropdownMenuItem(
                        value: kind,
                        child: Text(
                          kind == ArchiveExternalPackerKind.sevenZip
                              ? '7-Zip (7z / 7zz)'
                              : 'RAR (rar)',
                        ),
                      ),
                  ],
                  onChanged: enabled
                      ? (kind) {
                          if (kind != null) {
                            setState(() {
                              _kind = kind;
                              _installation = null;
                              _error = null;
                            });
                          }
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('archive-external-path'),
                  controller: _executable,
                  enabled: enabled,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: tr('Executable path'),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {
                    _installation = null;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(
                    'Choose a separately installed 7-Zip 21+ or RAR 7+ command-line executable. Tool paths are saved only on this device.',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    OutlinedButton(
                      key: const ValueKey('archive-external-discover'),
                      onPressed: enabled ? _discover : null,
                      child: Text(tr('Find installed tools')),
                    ),
                    FilledButton.tonal(
                      key: const ValueKey('archive-external-probe'),
                      onPressed: enabled && _executable.text.isNotEmpty
                          ? _probe
                          : null,
                      child: Text(tr('Check tool')),
                    ),
                  ],
                ),
                if (_searched && _candidates.isEmpty)
                  Text(tr('No tool found. Enter its full executable path.')),
                if (_candidates.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ArchiveExternalPackerConfiguration>(
                    key: const ValueKey('archive-external-candidates'),
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr('Discovered tools'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final candidate in _candidates)
                        DropdownMenuItem(
                          value: candidate,
                          child: Text(
                            candidate.executable,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.ltr,
                          ),
                        ),
                    ],
                    onChanged: enabled
                        ? (candidate) {
                            if (candidate != null) {
                              setState(() {
                                _kind = candidate.kind;
                                _executable.text = candidate.executable;
                                _installation = null;
                                _error = null;
                              });
                            }
                          }
                        : null,
                  ),
                ],
                if (installation != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    tr('Checked version {0}. Verified formats: {1}.', [
                      installation.version,
                      formats.map((format) => format.label).join(', '),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const ValueKey('archive-external-remember'),
                    onPressed: enabled && _preferences != null
                        ? _remember
                        : null,
                    child: Text(tr('Remember tool on this device')),
                  ),
                ],
                if (_saved) ...[
                  Text(
                    tr(
                      'A tool path is saved. Check it again before creating an archive.',
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('archive-external-forget'),
                    onPressed: enabled ? _forget : null,
                    child: Text(tr('Forget saved tool')),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('archive-external-name'),
                  controller: _name,
                  enabled: enabled,
                  decoration: InputDecoration(
                    labelText: common('Archive name'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ArchiveExternalPackerFormat>(
                  key: ValueKey(
                    'archive-external-format-${installation?.identity.sha256}-${formats.join(',')}',
                  ),
                  initialValue: formats.contains(_format) ? _format : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: common('Format'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final format in formats)
                      DropdownMenuItem(
                        value: format,
                        child: Text(format.label),
                      ),
                  ],
                  onChanged: enabled && installation != null
                      ? (format) {
                          if (format != null) {
                            setState(() => _chooseFormat(format));
                          }
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ArchiveExternalPackerCompression>(
                  key: const ValueKey('archive-external-compression'),
                  initialValue: _compression,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: common('Compression'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final value in ArchiveExternalPackerCompression.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(
                          common(switch (value) {
                            ArchiveExternalPackerCompression.store =>
                              'Store (no compression)',
                            ArchiveExternalPackerCompression.normal => 'Normal',
                            ArchiveExternalPackerCompression.maximum =>
                              'Maximum',
                          }),
                        ),
                      ),
                  ],
                  onChanged: enabled && installation != null
                      ? (value) {
                          if (value != null) {
                            setState(() => _compression = value);
                          }
                        }
                      : null,
                ),
                if (_kind == ArchiveExternalPackerKind.sevenZip &&
                    _format == ArchiveExternalPackerFormat.sevenZip) ...[
                  const SizedBox(height: 16),
                  Text(tr('7z options')),
                  const SizedBox(height: 8),
                  Text(
                    tr('Changing these options requires another tool check.'),
                  ),
                  const SizedBox(height: 12),
                  profileChoice(
                    key: 'dictionary',
                    label: 'Dictionary size',
                    value: _sevenZipProfile.dictionaryMiB,
                    choices: ArchiveExternalSevenZipProfile.dictionarySizesMiB,
                    available:
                        _compression != ArchiveExternalPackerCompression.store,
                    choose: (value) =>
                        _sevenZipProfile = ArchiveExternalSevenZipProfile(
                          dictionaryMiB: value,
                          threads: _sevenZipProfile.threads,
                          solidBlockMiB: _sevenZipProfile.solidBlockMiB,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(tr('Dictionary size applies to Normal and Maximum.')),
                  const SizedBox(height: 12),
                  profileChoice(
                    key: 'threads',
                    label: 'Threads',
                    value: _sevenZipProfile.threads,
                    choices: ArchiveExternalSevenZipProfile.threadCounts,
                    memorySize: false,
                    choose: (value) =>
                        _sevenZipProfile = ArchiveExternalSevenZipProfile(
                          dictionaryMiB: _sevenZipProfile.dictionaryMiB,
                          threads: value,
                          solidBlockMiB: _sevenZipProfile.solidBlockMiB,
                        ),
                  ),
                  const SizedBox(height: 12),
                  profileChoice(
                    key: 'solid',
                    label: 'Solid block size',
                    value: _sevenZipProfile.solidBlockMiB,
                    choices: ArchiveExternalSevenZipProfile.solidBlockSizesMiB,
                    choose: (value) =>
                        _sevenZipProfile = ArchiveExternalSevenZipProfile(
                          dictionaryMiB: _sevenZipProfile.dictionaryMiB,
                          threads: _sevenZipProfile.threads,
                          solidBlockMiB: value,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      'Solid blocks group files for compression. Extracting a file can require reading its whole block.',
                    ),
                  ),
                  if (installation != null && !profileVerified) ...[
                    const SizedBox(height: 8),
                    Text(
                      tr('Check the tool again to verify these 7z options.'),
                      key: const ValueKey(
                        'archive-external-profile-unverified',
                      ),
                    ),
                  ],
                ],
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(tr(_activity ?? 'Loading tool settings…')),
                  if (progress != null)
                    Text('${progress.completed} / ${progress.total}'),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    archiveExternalPackerError(context, _error!),
                    key: const ValueKey('archive-external-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_result != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    common('Archive created: {0}', [_result!.path]),
                    key: const ValueKey('archive-external-success'),
                  ),
                  if (_result!.publicationWarning != null)
                    Text(
                      common(
                        'The archive was created. Recovery information: {0}',
                        [_result!.publicationWarning],
                      ),
                      key: const ValueKey('archive-external-warning'),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('archive-external-close'),
            onPressed: _busy
                ? () => setState(() => _cancelled = true)
                : () => Navigator.of(context).pop(_result),
            child: Text(common(_busy ? 'Cancel' : 'Close')),
          ),
          if (_result == null)
            FilledButton(
              key: const ValueKey('archive-external-create'),
              onPressed: enabled && installation != null && profileVerified
                  ? _create
                  : null,
              child: Text(common('Create archive')),
            ),
        ],
      ),
    );
  }
}
