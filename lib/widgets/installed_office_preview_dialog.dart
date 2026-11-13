import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/installed_office_preview_strings.dart';
import '../providers/office_conversion_provider.dart';
import '../services/installed_office_converter.dart';

/// This route uses a separately installed desktop application. It never
/// downloads an engine or substitutes an app on an unsupported platform.
bool get supportsInstalledOfficePreview =>
    !kIsWeb &&
    const {
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }.contains(defaultTargetPlatform);

bool isInstalledOfficePreviewFileName(String name) => const {
  '.doc',
  '.dot',
  '.docx',
  '.docm',
}.contains(p.extension(name).toLowerCase());

/// Makes an explicit installed-application PDF preview without creating or
/// saving a Word copy. [onPreviewPdf] opens the existing app PDF viewer.
///
/// The converter owns its bounded temporary workspace and child-process
/// cleanup. It has no stop API, so this dialog does not offer an ineffective
/// cancel action while conversion is running.
Future<void> showInstalledOfficePreviewDialog(
  BuildContext context, {
  required String sourceName,
  required Uint8List bytes,
  required Future<void> Function(Uint8List bytes, String fileName) onPreviewPdf,
  InstalledOfficeDiscovery? discover,
  InstalledOfficeConversion? convert,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => InstalledOfficePreviewDialog(
    sourceName: sourceName,
    bytes: bytes,
    onPreviewPdf: onPreviewPdf,
    discover: discover,
    convert: convert,
  ),
);

class InstalledOfficePreviewDialog extends StatefulWidget {
  const InstalledOfficePreviewDialog({
    super.key,
    required this.sourceName,
    required this.bytes,
    required this.onPreviewPdf,
    this.discover,
    this.convert,
  });

  final String sourceName;
  final Uint8List bytes;
  final Future<void> Function(Uint8List bytes, String fileName) onPreviewPdf;
  final InstalledOfficeDiscovery? discover;
  final InstalledOfficeConversion? convert;

  @override
  State<InstalledOfficePreviewDialog> createState() =>
      _InstalledOfficePreviewDialogState();
}

class _InstalledOfficePreviewDialogState
    extends State<InstalledOfficePreviewDialog> {
  Uint8List? _source;
  List<InstalledOfficeInstallation> _installations = const [];
  int? _selected;
  Object? _error;
  bool _checking = false;
  bool _busy = false;
  bool _opening = false;
  bool _validRequest = false;
  String? _completedWith;

  InstalledOfficeConversion get _converter =>
      widget.convert ??
      ({
        required bytes,
        required sourceName,
        required installation,
        output = InstalledOfficeOutput.docx,
      }) => convertWithInstalledOffice(
        bytes: bytes,
        sourceName: sourceName,
        installation: installation,
        output: output,
      );

  @override
  void initState() {
    super.initState();
    if (!supportsInstalledOfficePreview) {
      _error = const InstalledOfficeConversionException(
        InstalledOfficeConversionErrorCode.unsupportedPlatform,
      );
    } else if (!isInstalledOfficePreviewFileName(widget.sourceName) ||
        widget.bytes.isEmpty) {
      _error = const InstalledOfficeConversionException(
        InstalledOfficeConversionErrorCode.invalidInput,
      );
    } else if (widget.bytes.length > kInstalledOfficeInputLimit) {
      _error = const InstalledOfficeConversionException(
        InstalledOfficeConversionErrorCode.inputTooLarge,
      );
    } else {
      // Snapshot only after the cap check. The converter cannot mutate the
      // viewer's buffer and a later source-buffer change cannot change which
      // document the user chose to preview.
      _source = Uint8List.fromList(widget.bytes).asUnmodifiableView();
      _validRequest = true;
      _discover();
    }
  }

  Future<void> _discover() async {
    if (!_validRequest || _checking || _busy) return;
    setState(() {
      _checking = true;
      _error = null;
      _installations = const [];
      _selected = null;
      _completedWith = null;
    });
    try {
      final found =
          await (widget.discover ??
              () => discoverInstalledOfficeConverters())();
      if (!mounted) return;
      final available = [
        for (final installation in found)
          if (installation.supportsPagePreview) installation,
      ];
      setState(() {
        _installations = List.unmodifiable(available);
        // Selecting a default does not start conversion; the user still must
        // invoke Preview pages with the chosen application shown.
        _selected = available.isEmpty ? null : 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = const InstalledOfficeConversionException(
          InstalledOfficeConversionErrorCode.unavailable,
        );
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _preview() async {
    final source = _source;
    final selected = _selected;
    if (_checking ||
        _busy ||
        !_validRequest ||
        source == null ||
        selected == null ||
        selected >= _installations.length) {
      return;
    }
    final installation = _installations[selected];
    setState(() {
      _busy = true;
      _opening = false;
      _error = null;
      _completedWith = null;
    });
    try {
      final result = await _converter(
        bytes: source,
        sourceName: widget.sourceName,
        installation: installation,
        output: InstalledOfficeOutput.pdf,
      );
      if (!mounted) return;
      if (result.output != InstalledOfficeOutput.pdf ||
          result.installation.kind != installation.kind ||
          result.installation.executablePath != installation.executablePath) {
        throw const InstalledOfficeConversionException(
          InstalledOfficeConversionErrorCode.invalidOutput,
        );
      }
      // Validate before allocating a snapshot of externally produced bytes.
      validateInstalledOfficePdf(result.bytes);
      final pdf = Uint8List.fromList(result.bytes).asUnmodifiableView();
      final name = '${p.basenameWithoutExtension(widget.sourceName)}.pdf';
      setState(() => _opening = true);
      await widget.onPreviewPdf(pdf, name);
      if (mounted) {
        setState(() => _completedWith = installation.displayName);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _opening = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = InstalledOfficePreviewStrings(
      Localizations.localeOf(context),
    );
    final theme = Theme.of(context);
    final canPreview = !_busy && !_checking && _selected != null;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(strings.text('title')),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.sourceName,
                  key: const ValueKey('installed-preview-source'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                Text(strings.text('notice')),
                const SizedBox(height: 8),
                Text(
                  strings.text('layoutNotice'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                if (_checking)
                  _progress(strings.text('checking'))
                else if (_installations.isNotEmpty)
                  DropdownButtonFormField<int>(
                    key: const ValueKey('installed-preview-application'),
                    initialValue: _selected,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: strings.text('application'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (
                        var index = 0;
                        index < _installations.length;
                        index++
                      )
                        DropdownMenuItem(
                          value: index,
                          child: Text(
                            strings.text(
                              'installed',
                              arguments: {
                                'app': _installations[index].displayName,
                              },
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (index) => setState(() {
                            _selected = index;
                            _error = null;
                            _completedWith = null;
                          }),
                  )
                else if (_validRequest && _error == null)
                  Text(
                    strings.text('unavailable'),
                    key: const ValueKey('installed-preview-unavailable'),
                  ),
                if (_error case final error?) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      strings.error(error),
                      key: const ValueKey('installed-preview-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
                if (_completedWith case final application?) ...[
                  const SizedBox(height: 12),
                  Text(
                    strings.text('completed', arguments: {'app': application}),
                    key: const ValueKey('installed-preview-completed'),
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 16),
                  _progress(strings.text(_opening ? 'opening' : 'rendering')),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('installed-preview-close'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(strings.text('close')),
          ),
          if (_validRequest)
            TextButton(
              key: const ValueKey('installed-preview-check-again'),
              onPressed: _busy || _checking ? null : _discover,
              child: Text(strings.text('checkAgain')),
            ),
          FilledButton(
            key: const ValueKey('installed-preview-primary'),
            onPressed: canPreview ? _preview : null,
            child: Text(strings.text('preview')),
          ),
        ],
      ),
    );
  }

  Widget _progress(String label) => Semantics(
    liveRegion: true,
    child: Row(
      children: [
        const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    ),
  );
}
