import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../l10n/installed_office_strings.dart';
import '../l10n/legacy_word_conversion_strings.dart';
import '../providers/office_conversion_provider.dart';
import '../services/installed_office_converter.dart';
import '../services/legacy_word_conversion.dart';
import '../services/word_conversion_inspection.dart';

/// Creates a separate copy. Installed engines return their package unchanged;
/// the user reviews the package evidence and any detected loss before saving.
Future<LegacyWordCopy?> showLegacyWordConversionDialog(
  BuildContext context, {
  required String sourceName,
  required Uint8List bytes,
  Future<void> Function(LegacyWordCopy)? onSave,
  String Function(Object)? describeSaveError,
  InstalledOfficeDiscovery? discover,
  InstalledOfficeConversion? convert,
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
  });

  final String sourceName;
  final Uint8List bytes;
  final Future<void> Function(LegacyWordCopy)? onSave;
  final String Function(Object)? describeSaveError;
  final InstalledOfficeDiscovery? discover;
  final InstalledOfficeConversion? convert;

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
  Object? _error;
  bool _checking = true;
  bool _converting = false;
  bool _saving = false;
  bool _saveError = false;
  bool _automaticName = true;
  bool _acceptLoss = false;

  bool get _textOnly => _method == 'text';
  bool get _busy => _converting || _saving;
  InstalledOfficeInstallation? get _installation {
    final method = _method;
    if (method == null || method == 'text') return null;
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
      available = [...available]
        ..sort(
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
    _error = null;
    _acceptLoss = false;
    final installation = _installation;
    _output =
        !_textOnly &&
            _source?.hasVba == true &&
            installation?.supportsMacros == true
        ? InstalledOfficeOutput.docm
        : InstalledOfficeOutput.docx;
    if (installation != null &&
        !installation.supportedOutputs.contains(_output)) {
      _output = installation.supportedOutputs.first;
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
        (!_textOnly && _installation == null)) {
      return;
    }
    try {
      final extension = _textOnly ? 'docx' : _output.extension;
      final name = validateLegacyWordCopyName(_name.text, extension: extension);
      setState(() {
        _converting = true;
        _saveError = false;
        _error = null;
      });
      if (_textOnly) {
        final bytes = await compute(convertLegacyWordToDocx, widget.bytes);
        if (!mounted) return;
        await _save(LegacyWordCopy(fileName: name, bytes: bytes));
        return;
      }
      final installation = _installation!;
      final convert =
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
      final result = await convert(
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
      final bytes = Uint8List.fromList(result.bytes).asUnmodifiableView();
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
          converterName: installation.displayName,
          inspection: report,
        );
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
        (_textOnly || _installation != null);
    final canSave =
        !_busy &&
        prepared != null &&
        (prepared.inspection!.losses.isEmpty || _acceptLoss);
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
                      Text(strings.text('unavailable')),
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
                  ] else if (_installation != null) ...[
                    const SizedBox(height: 16),
                    Text(strings.text('nativeNotice')),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<InstalledOfficeOutput>(
                      key: ValueKey('word-conversion-output-${_method ?? ''}'),
                      initialValue: _output,
                      decoration: InputDecoration(
                        labelText: strings.text('outputFormat'),
                      ),
                      items: [
                        for (final output in _installation!.supportedOutputs)
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
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    Text(strings.text('macroNotice')),
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
                  const SizedBox(height: 8),
                  Text(strings.text('signatureNotice')),
                  if (prepared.inspection!.losses.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      strings.text('losses'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    for (final loss in prepared.inspection!.losses)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(strings.text(loss.name)),
                      ),
                    CheckboxListTile(
                      key: const ValueKey('word-conversion-accept-loss'),
                      contentPadding: EdgeInsets.zero,
                      value: _acceptLoss,
                      title: Text(strings.text('acceptLoss')),
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
                        _saving ? textStrings.saving : textStrings.converting,
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
