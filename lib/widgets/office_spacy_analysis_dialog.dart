import 'package:flutter/material.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';

import '../services/office_spacy.dart';

Future<void> showOfficeSpacyAnalysisDialog(
  BuildContext context,
  String text, {
  Future<LinguisticAnalysisResult> Function(String, {bool includeEntities})
      analyze =
      analyzeOfficeSpacyText,
}) => showDialog<void>(
  context: context,
  builder: (_) => _AnalysisDialog(text: text, analyze: analyze),
);

class _AnalysisDialog extends StatefulWidget {
  const _AnalysisDialog({required this.text, required this.analyze});
  final String text;
  final Future<LinguisticAnalysisResult> Function(
    String, {
    bool includeEntities,
  })
  analyze;
  @override
  State<_AnalysisDialog> createState() => _AnalysisDialogState();
}

class _AnalysisDialogState extends State<_AnalysisDialog> {
  late final _text = TextEditingController(text: widget.text);
  LinguisticAnalysisResult? _result;
  String? _error;
  bool _busy = false;
  bool _entities = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.analyze(
        _text.text,
        includeEntities: _entities,
      );
      if (mounted) {
        setState(() {
          _result = result;
          if (!result.isSuccess) {
            _error = result.message ?? 'Analysis could not complete.';
          }
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('German analysis'),
    content: SizedBox(
      width: 720,
      height: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Analyze German text locally. This does not change your document.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Text'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('People, places and organizations'),
            value: _entities,
            onChanged: _busy
                ? null
                : (value) => setState(() => _entities = value ?? false),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SelectableText(_error!),
            ),
          if (_result case final result?) ...[
            Text(
              '${result.tokens.length} words and punctuation · ${result.sentences.length} sentences',
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  (result.entitiesAvailable
                          ? [
                              for (final entity in result.entities)
                                '${entity.text} · ${entity.label}',
                              '',
                            ].join('\n')
                          : '') +
                      result.tokens
                          .map(
                            (token) =>
                                '${token.text}  ·  ${token.lemma}  ·  ${token.pos}  ·  ${token.morphology}',
                          )
                          .join('\n'),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      FilledButton(
        onPressed: _busy ? null : _analyze,
        child: const Text('Analyze'),
      ),
    ],
  );
}
