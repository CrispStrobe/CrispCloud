import 'package:shared_preferences/shared_preferences.dart';

enum PdfViewerBackend { pdfEditor, crispOffice, native }

enum PdfEditorBackend { pdfEditor, crispOffice }

enum PdfAlternateEditAction { chooser, secondary }

class PdfOpenPreferences {
  const PdfOpenPreferences({
    this.viewer = PdfViewerBackend.pdfEditor,
    this.secondaryViewer = PdfViewerBackend.native,
    this.editor = PdfEditorBackend.pdfEditor,
    this.secondaryEditor = PdfEditorBackend.crispOffice,
    this.shiftF4 = PdfAlternateEditAction.chooser,
  });
  final PdfViewerBackend viewer;
  final PdfViewerBackend secondaryViewer;
  final PdfEditorBackend editor;
  final PdfEditorBackend secondaryEditor;
  final PdfAlternateEditAction shiftF4;
  static T _read<T extends Enum>(
    SharedPreferences prefs,
    String key,
    List<T> values,
    T fallback,
  ) {
    final name = prefs.getString('pdf.open.$key');
    return values.where((v) => v.name == name).firstOrNull ?? fallback;
  }

  static Future<void>? _writes;
  static Future<PdfOpenPreferences> load() async {
    final writing = _writes;
    if (writing != null) {
      try {
        await writing;
      } catch (_) {
        /* The save caller reports failures. */
      }
    }
    final p = await SharedPreferences.getInstance();
    return PdfOpenPreferences(
      viewer: _read(
        p,
        'viewer',
        PdfViewerBackend.values,
        PdfViewerBackend.pdfEditor,
      ),
      secondaryViewer: _read(
        p,
        'secondaryViewer',
        PdfViewerBackend.values,
        PdfViewerBackend.native,
      ),
      editor: _read(
        p,
        'editor',
        PdfEditorBackend.values,
        PdfEditorBackend.pdfEditor,
      ),
      secondaryEditor: _read(
        p,
        'secondaryEditor',
        PdfEditorBackend.values,
        PdfEditorBackend.crispOffice,
      ),
      shiftF4: _read(
        p,
        'shiftF4',
        PdfAlternateEditAction.values,
        PdfAlternateEditAction.chooser,
      ),
    );
  }

  Future<void> save() {
    final previous = _writes;
    final operation = previous == null
        ? _save()
        : previous.then(
            (_) => _save(),
            onError: (Object _, StackTrace __) => _save(),
          );
    late final Future<void> queued;
    queued = operation.whenComplete(() {
      if (identical(_writes, queued)) _writes = null;
    });
    _writes = queued;
    return queued;
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    for (final e in {
      'viewer': viewer.name,
      'secondaryViewer': secondaryViewer.name,
      'editor': editor.name,
      'secondaryEditor': secondaryEditor.name,
      'shiftF4': shiftF4.name,
    }.entries) {
      await p.setString('pdf.open.${e.key}', e.value);
    }
  }
}

String pdfViewerBackendLabel(PdfViewerBackend backend) => switch (backend) {
  PdfViewerBackend.pdfEditor => 'CrispCloud PDF viewer',
  PdfViewerBackend.crispOffice => 'CrispOffice PDF viewer',
  PdfViewerBackend.native => 'Native compatibility viewer',
};
String pdfEditorBackendLabel(PdfEditorBackend backend) => switch (backend) {
  PdfEditorBackend.pdfEditor => 'CrispCloud PDF Editor',
  PdfEditorBackend.crispOffice => 'CrispOffice PDF editor',
};
