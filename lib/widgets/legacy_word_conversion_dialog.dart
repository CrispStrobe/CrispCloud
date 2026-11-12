import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../l10n/installed_office_strings.dart';
import '../l10n/legacy_word_conversion_strings.dart';
import '../providers/office_conversion_provider.dart';
import '../services/installed_office_converter.dart';
import '../services/legacy_word_conversion.dart';
import '../services/word_conversion_inspection.dart';

LegacyWordStructuredConversion _convertStructuredWord(
  ({Uint8List bytes, bool docm}) request,
) => convertLegacyWord(
  request.bytes,
  format: request.docm
      ? LegacyWordOutputFormat.docm
      : LegacyWordOutputFormat.docx,
);

/// Creates a separate copy. Structured and installed conversions are reviewed
/// before saving; the explicit text-only choice retains its copy workflow.
Future<LegacyWordCopy?> showLegacyWordConversionDialog(
  BuildContext context, {
  required String sourceName,
  required Uint8List bytes,
  Future<void> Function(LegacyWordCopy)? onSave,
  String Function(Object)? describeSaveError,
  InstalledOfficeDiscovery? discover,
  InstalledOfficeConversion? convert,
  Future<void> Function(Uint8List bytes, String fileName)? onPreviewPdf,
}) => showDialog<LegacyWordCopy>(
  context: context,
  barrierDismissible: false,
  builder: (_) => LegacyWordConversionDialog(
    sourceName: sourceName,
    bytes: bytes,
    onSave: onSave,
    describeSaveError: describeSaveError,
    discover: discover,
    convert: convert,
    onPreviewPdf: onPreviewPdf,
  ),
);

class LegacyWordConversionDialog extends StatefulWidget {
  const LegacyWordConversionDialog({
    super.key,
    required this.sourceName,
    required this.bytes,
    this.onSave,
    this.describeSaveError,
    this.discover,
    this.convert,
    this.onPreviewPdf,
  });

  final String sourceName;
  final Uint8List bytes;
  final Future<void> Function(LegacyWordCopy)? onSave;
  final String Function(Object)? describeSaveError;
  final InstalledOfficeDiscovery? discover;
  final InstalledOfficeConversion? convert;
  final Future<void> Function(Uint8List bytes, String fileName)? onPreviewPdf;

  @override
  State<LegacyWordConversionDialog> createState() =>
      _LegacyWordConversionDialogState();
}

class _LegacyWordConversionDialogState
    extends State<LegacyWordConversionDialog> {
  late final TextEditingController _name = TextEditingController(
    text: suggestedLegacyWordCopyName(widget.sourceName),
  );
  List<InstalledOfficeInstallation> _installations = const [];
  LegacyWordSourceInspection? _source;
  InstalledOfficeOutput _output = InstalledOfficeOutput.docx;
  String? _method;
  LegacyWordCopy? _prepared;
  List<LegacyWordConversionLimitation> _limitations = const [];
  Object? _error;
  bool _checking = true;
  bool _converting = false;
  bool _saving = false;
  bool _previewing = false;
  bool _previewError = false;
  bool _saveError = false;
  bool _automaticName = true;
  bool _acceptLoss = false;

  bool get _textOnly => _method == 'text';
  bool get _structured => _method == 'structured';
  bool get _builtIn => _textOnly || _structured;
  bool get _busy => _converting || _saving || _previewing;
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
  InstalledOfficeInstallation? get _installation {
    final method = _method;
    if (method == null || _builtIn) return null;
    final index = int.tryParse(method);
    return index != null && index >= 0 && index < _installations.length
        ? _installations[index]
        : null;
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final source = await compute(inspectLegacyWordSource, widget.bytes);
      List<InstalledOfficeInstallation> available;
      try {
        available =
            await (widget.discover ??
                () => discoverInstalledOfficeConverters())();
      } catch (_) {
        available = const [];
      }
      if (!mounted) return;
      available =
          [
            for (final installation in available)
              if (installation.supportedOutputs.any(
                (output) => output != InstalledOfficeOutput.pdf,
              ))
                installation,
          ]..sort(
            (a, b) => (a.kind == InstalledOfficeKind.microsoftWord ? 0 : 1)
                .compareTo(b.kind == InstalledOfficeKind.microsoftWord ? 0 : 1),
          );
      setState(() {
        _source = source;
        _installations = available;
        _checking = false;
        if (available.isNotEmpty) _changeMethod('0');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = error;
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _changeMethod(String? value) {
    _method = value;
    _prepared = null;
    _limitations = const [];
    _error = null;
    _previewError = false;
    _acceptLoss = false;
    final installation = _installation;
    _output =
        !_builtIn &&
            _source?.hasVba == true &&
            installation?.supportsMacros == true
        ? InstalledOfficeOutput.docm
        : InstalledOfficeOutput.docx;
    if (installation != null &&
        !installation.supportedOutputs.contains(_output)) {
      _output = installation.supportedOutputs.firstWhere(
        (output) => output != InstalledOfficeOutput.pdf,
      );
    }
    _updateName();
  }

  void _updateName() {
    if (_automaticName) {
      _name.text = suggestedLegacyWordCopyName(
        widget.sourceName,
        textOnly: _textOnly,
        extension: _output.extension,
      );
    } else {
      _name.text = _name.text.replaceFirst(
        RegExp(r'\.(docx|docm)$', caseSensitive: false),
        '.${_output.extension}',
      );
    }
  }

  Future<void> _convert() async {
    if (_busy ||
        _checking ||
        _source == null ||
        (!_builtIn && _installation == null)) {
      return;
    }
    try {
      final extension = _textOnly ? 'docx' : _output.extension;
      final name = validateLegacyWordCopyName(_name.text, extension: extension);
      setState(() {
        _converting = true;
        _saveError = false;
        _previewError = false;
        _error = null;
      });
      if (_textOnly) {
        final bytes = await compute(convertLegacyWordToDocx, widget.bytes);
        if (!mounted) return;
        await _save(LegacyWordCopy(fileName: name, bytes: bytes));
        return;
      }
      final Uint8List bytes;
      final String converterName;
      List<LegacyWordConversionLimitation> limitations = const [];
      if (_structured) {
        final result = await compute(_convertStructuredWord, (
          bytes: widget.bytes,
          docm: _output == InstalledOfficeOutput.docm,
        ));
        if (!mounted) return;
        if (result.extension != extension) {
          throw const WordConversionInspectionException(
            WordConversionInspectionIssue.invalidOutput,
          );
        }
        bytes = Uint8List.fromList(result.bytes).asUnmodifiableView();
        limitations = List.unmodifiable(result.limitations);
        converterName = LegacyWordConversionStrings(
          Localizations.localeOf(context),
        ).builtInName;
      } else {
        final installation = _installation!;
        final result = await _converter(
          bytes: widget.bytes,
          sourceName: widget.sourceName,
          installation: installation,
          output: _output,
        );
        if (!mounted) return;
        if (result.output != _output ||
            result.installation.kind != installation.kind) {
          throw const WordConversionInspectionException(
            WordConversionInspectionIssue.invalidOutput,
          );
        }
        bytes = Uint8List.fromList(result.bytes).asUnmodifiableView();
        converterName = installation.displayName;
      }
      final report = await inspectConvertedWord(
        bytes,
        extension: extension,
        source: _source!,
      );
      if (!mounted) return;
      setState(() {
        _prepared = LegacyWordCopy(
          fileName: name,
          bytes: bytes,
          extension: extension,
          converterName: converterName,
          inspection: report,
        );
        _limitations = limitations;
        _converting = false;
        _acceptLoss = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _converting = false;
        _error = error;
      });
    }
  }

  Future<void> _previewPages() async {
    final prepared = _prepared;
    final installation = _installation;
    final preview = widget.onPreviewPdf;
    if (_busy ||
        prepared == null ||
        installation == null ||
        preview == null ||
        !installation.supportsPagePreview) {
      return;
    }
    setState(() {
      _previewing = true;
      _previewError = false;
      _saveError = false;
      _error = null;
    });
    try {
      final result = await _converter(
        bytes: prepared.bytes,
        sourceName: prepared.fileName,
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
      final pdf = Uint8List.fromList(result.bytes).asUnmodifiableView();
      validateInstalledOfficePdf(pdf);
      final name = prepared.fileName.replaceFirst(
        RegExp(r'\.(docx|docm)$', caseSensitive: false),
        '.pdf',
      );
      await preview(pdf, name);
    } catch (error) {
      if (mounted) {
        setState(() {
          _previewError = true;
          _error = error;
        });
      }
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _save(LegacyWordCopy copy) async {
    try {
      final name = validateLegacyWordCopyName(
        _name.text,
        extension: copy.extension,
      );
      final named = LegacyWordCopy(
        fileName: name,
        bytes: copy.bytes,
        extension: copy.extension,
        converterName: copy.converterName,
        inspection: copy.inspection,
      );
      setState(() {
        _saving = true;
        _saveError = false;
        _previewError = false;
        _error = null;
      });
      if (widget.onSave case final save?) await save(named);
      if (!mounted) return;
      Navigator.of(context).pop(named);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _converting = false;
        _saving = false;
        _saveError = true;
        _error = error;
      });
    }
  }

  String _describeError(
    Object error,
    InstalledOfficeStrings strings,
    LegacyWordConversionStrings textStrings,
  ) {
    if (_previewError) {
      return strings.text(switch (error) {
        InstalledOfficeConversionException(
          code: InstalledOfficeConversionErrorCode.invalidOutput,
        ) =>
          'invalidPdf',
        InstalledOfficeConversionException(
          code: InstalledOfficeConversionErrorCode.timeout,
        ) =>
          'timedOut',
        InstalledOfficeConversionException(
          code: InstalledOfficeConversionErrorCode.engineBusy,
        ) =>
          'engineBusy',
        InstalledOfficeConversionException(
          code: InstalledOfficeConversionErrorCode.outputTooLarge ||
              InstalledOfficeConversionErrorCode.inputTooLarge,
        ) =>
          'tooLarge',
        InstalledOfficeConversionException(
          code: InstalledOfficeConversionErrorCode.unsafeAutomation,
        ) =>
          'unsafe',
        _ => 'previewFailed',
      });
    }
    if (_saveError && error is! LegacyWordConversionException) {
      return widget.describeSaveError?.call(error) ?? textStrings.error(error);
    }
    if (error is LegacyWordConversionException &&
        error.issue == LegacyWordConversionIssue.invalidName) {
      return strings.text(
        'filename',
        arguments: {'extension': _textOnly ? 'docx' : _output.extension},
      );
    }
    if (error is WordConversionInspectionException) {
      return strings.text(switch (error.issue) {
        WordConversionInspectionIssue.invalidInput ||
        WordConversionInspectionIssue.encrypted => 'invalidInput',
        WordConversionInspectionIssue.invalidOutput => 'invalidOutput',
        WordConversionInspectionIssue.tooLarge => 'tooLarge',
      });
    }
    if (error is InstalledOfficeConversionException) {
      return strings.text(switch (error.code) {
        InstalledOfficeConversionErrorCode.timeout => 'timedOut',
        InstalledOfficeConversionErrorCode.unsafeAutomation => 'unsafe',
        InstalledOfficeConversionErrorCode.engineBusy => 'engineBusy',
        InstalledOfficeConversionErrorCode.inputTooLarge ||
        InstalledOfficeConversionErrorCode.outputTooLarge => 'tooLarge',
        InstalledOfficeConversionErrorCode.invalidInput ||
        InstalledOfficeConversionErrorCode.encryptedInput => 'invalidInput',
        InstalledOfficeConversionErrorCode.invalidOutput => 'invalidOutput',
        InstalledOfficeConversionErrorCode.unsupportedPlatform ||
        InstalledOfficeConversionErrorCode.unavailable ||
        InstalledOfficeConversionErrorCode.unsupportedOutput => 'unsupported',
        _ => 'nativeError',
      });
    }
    return textStrings.error(error);
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final strings = InstalledOfficeStrings(locale);
    final textStrings = LegacyWordConversionStrings(locale);
    final prepared = _prepared;
    final canConvert =
        !_checking &&
        !_busy &&
        _source != null &&
        (_builtIn || _installation != null);
    final requiresAcknowledgement =
        prepared != null &&
        (_structured || prepared.inspection!.losses.isNotEmpty);
    final canSave =
        !_busy && prepared != null && (!requiresAcknowledgement || _acceptLoss);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(strings.text(prepared == null ? 'title' : 'review')),
        content: SizedBox(
          width: 590,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.sourceName),
                const SizedBox(height: 12),
                if (prepared == null) ...[
                  if (_checking)
                    Text(strings.text('checking'))
                  else ...[
                    if (_installations.isEmpty && _source != null) ...[
                      Text(textStrings.unavailable),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<String>(
                      key: const ValueKey('word-conversion-method'),
                      initialValue: _method,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: strings.text('method'),
                      ),
                      hint: Text(strings.text('chooseMethod')),
                      items: [
                        for (var i = 0; i < _installations.length; i++)
                          DropdownMenuItem(
                            value: '$i',
                            child: Text(
                              strings.text(
                                'installed',
                                arguments: {
                                  'app': _installations[i].displayName,
                                },
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        DropdownMenuItem(
                          value: 'structured',
                          child: Text(textStrings.structuredMethod),
                        ),
                        DropdownMenuItem(
                          value: 'text',
                          child: Text(strings.text('textOnly')),
                        ),
                      ],
                      onChanged: _busy || _source == null
                          ? null
                          : (value) => setState(() => _changeMethod(value)),
                    ),
                  ],
                  if (_textOnly) ...[
                    const SizedBox(height: 16),
                    Text(textStrings.lossNotice),
                  ] else if (_structured) ...[
                    const SizedBox(height: 16),
                    Text(textStrings.structuredNotice),
                  ] else if (_installation != null) ...[
                    const SizedBox(height: 16),
                    Text(strings.text('nativeNotice')),
                  ],
                  if (_structured || _installation != null) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<InstalledOfficeOutput>(
                      key: ValueKey('word-conversion-output-${_method ?? ''}'),
                      initialValue: _output,
                      decoration: InputDecoration(
                        labelText: strings.text('outputFormat'),
                      ),
                      items: [
                        for (final output
                            in (_structured
                                    ? const [
                                        InstalledOfficeOutput.docx,
                                        InstalledOfficeOutput.docm,
                                      ]
                                    : _installation!.supportedOutputs)
                                .where(
                                  (output) =>
                                      output != InstalledOfficeOutput.pdf,
                                ))
                          DropdownMenuItem(
                            value: output,
                            child: Text(
                              output == InstalledOfficeOutput.docx
                                  ? 'DOCX'
                                  : strings.text('docm'),
                            ),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (output) {
                              if (output == null) return;
                              setState(() {
                                _output = output;
                                _updateName();
                                _error = null;
                                _prepared = null;
                                _limitations = const [];
                                _acceptLoss = false;
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _structured
                          ? textStrings.structuredMacroNotice
                          : strings.text('macroNotice'),
                    ),
                    const SizedBox(height: 8),
                    Text(strings.text('signatureNotice')),
                  ],
                ] else ...[
                  Text(
                    prepared.converterName!,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    strings.text('detected'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final count in prepared.inspection!.counts.entries)
                        if (count.value > 0 || count.key == 'paragraphs')
                          Chip(
                            label: Text(
                              '${strings.text(count.key)}: ${count.value}',
                            ),
                          ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(strings.text('evidenceNotice')),
                  if (_installation?.supportsPagePreview == true &&
                      widget.onPreviewPdf != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const ValueKey('word-conversion-preview-pages'),
                      onPressed: _busy ? null : _previewPages,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(strings.text('previewPages')),
                    ),
                    const SizedBox(height: 6),
                    Text(strings.text('previewNotice')),
                  ],
                  const SizedBox(height: 8),
                  Text(strings.text('signatureNotice')),
                  if (requiresAcknowledgement) ...[
                    const SizedBox(height: 16),
                    Text(
                      _structured
                          ? textStrings.limitationsTitle
                          : strings.text('losses'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (_structured) ...[
                      const SizedBox(height: 6),
                      Text(textStrings.structuredNotice),
                      const SizedBox(height: 6),
                      Text(textStrings.structuredMacroNotice),
                      for (final limitation in _limitations)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(textStrings.limitation(limitation)),
                        ),
                    ],
                    for (final loss in prepared.inspection!.losses)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(strings.text(loss.name)),
                      ),
                    CheckboxListTile(
                      key: const ValueKey('word-conversion-accept-loss'),
                      contentPadding: EdgeInsets.zero,
                      value: _acceptLoss,
                      title: Text(
                        _structured
                            ? textStrings.structuredAcceptLoss
                            : strings.text('acceptLoss'),
                      ),
                      onChanged: _busy
                          ? null
                          : (value) =>
                                setState(() => _acceptLoss = value ?? false),
                    ),
                  ],
                ],
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('word-conversion-filename'),
                  controller: _name,
                  enabled: !_busy,
                  decoration: InputDecoration(labelText: textStrings.fileName),
                  onChanged: (_) => _automaticName = false,
                  onSubmitted: (_) {
                    if (prepared == null && canConvert) _convert();
                    if (prepared != null && canSave) _save(prepared);
                  },
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: 12),
                  Text(
                    _describeError(error, strings, textStrings),
                    key: const ValueKey('word-conversion-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _previewing
                            ? strings.text('previewingPages')
                            : _saving
                            ? textStrings.saving
                            : textStrings.converting,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(textStrings.cancel),
          ),
          if (prepared != null)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _prepared = null;
                      _limitations = const [];
                      _acceptLoss = false;
                      _error = null;
                    }),
              child: Text(strings.text('back')),
            ),
          FilledButton(
            key: const ValueKey('word-conversion-primary'),
            onPressed: prepared == null
                ? (canConvert ? _convert : null)
                : (canSave ? () => _save(prepared) : null),
            child: Text(
              prepared == null
                  ? (_textOnly ? textStrings.create : strings.text('convert'))
                  : strings.text('saveCopy'),
            ),
          ),
        ],
      ),
    );
  }
}
