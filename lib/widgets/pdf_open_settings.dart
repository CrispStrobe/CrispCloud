import 'package:flutter/material.dart';

import '../l10n/commander_strings.dart';
import '../services/pdf_open_preferences.dart';

class PdfOpenSettings extends StatefulWidget {
  const PdfOpenSettings({super.key});
  @override
  State<PdfOpenSettings> createState() => _PdfOpenSettingsState();
}

class _PdfOpenSettingsState extends State<PdfOpenSettings> {
  PdfOpenPreferences? _value;
  @override
  void initState() {
    super.initState();
    PdfOpenPreferences.load().then((v) {
      if (mounted) setState(() => _value = v);
    });
  }

  Future<void> _save({
    PdfViewerBackend? viewer,
    PdfViewerBackend? secondaryViewer,
    PdfEditorBackend? editor,
    PdfEditorBackend? secondaryEditor,
    PdfAlternateEditAction? shiftF4,
  }) async {
    final v = _value!;
    final next = PdfOpenPreferences(
      viewer: viewer ?? v.viewer,
      secondaryViewer: secondaryViewer ?? v.secondaryViewer,
      editor: editor ?? v.editor,
      secondaryEditor: secondaryEditor ?? v.secondaryEditor,
      shiftF4: shiftF4 ?? v.shiftF4,
    );
    setState(() => _value = next);
    try {
      await next.save();
    } catch (error) {
      if (!mounted) return;
      if (identical(_value, next)) setState(() => _value = v);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.commanderTr('Could not save PDF preferences')}: $error',
          ),
        ),
      );
    }
  }

  Widget _choice<T>(
    String label,
    T value,
    List<T> values,
    String Function(T) name,
    ValueChanged<T> change,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: DropdownButtonFormField<T>(
      key: ValueKey('$label:$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: context.commanderTr(label)),
      items: [
        for (final v in values)
          DropdownMenuItem(value: v, child: Text(context.commanderTr(name(v)))),
      ],
      onChanged: (v) {
        if (v != null) change(v);
      },
    ),
  );
  @override
  Widget build(BuildContext context) {
    final v = _value;
    if (v == null) return const SizedBox.shrink();
    return ExpansionTile(
      title: Text(context.commanderTr('PDF viewers and editors')),
      leading: const Icon(Icons.picture_as_pdf_outlined),
      children: [
        _choice(
          'Default PDF viewer (F3)',
          v.viewer,
          PdfViewerBackend.values,
          pdfViewerBackendLabel,
          (x) => _save(viewer: x),
        ),
        _choice(
          'Secondary PDF viewer',
          v.secondaryViewer,
          PdfViewerBackend.values,
          pdfViewerBackendLabel,
          (x) => _save(secondaryViewer: x),
        ),
        _choice(
          'Default PDF editor (F4)',
          v.editor,
          PdfEditorBackend.values,
          pdfEditorBackendLabel,
          (x) => _save(editor: x),
        ),
        _choice(
          'Secondary PDF editor',
          v.secondaryEditor,
          PdfEditorBackend.values,
          pdfEditorBackendLabel,
          (x) => _save(secondaryEditor: x),
        ),
        _choice(
          'Ctrl+Shift+F4',
          v.shiftF4,
          PdfAlternateEditAction.values,
          (x) => x == PdfAlternateEditAction.chooser
              ? 'Show editor chooser'
              : 'Open secondary PDF editor',
          (x) => _save(shiftF4: x),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            context.commanderTr(
              'Shift+F3 opens the secondary PDF viewer. Other file types keep their existing shortcuts.',
            ),
          ),
        ),
      ],
    );
  }
}
