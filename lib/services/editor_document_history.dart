import 'editor_document.dart';

/// Newline sidecars follow the actual immutable editor history objects. Undo
/// restores metadata along with text; formatting choices remain explicit host
/// policy. Expando does not keep discarded undo states alive.
class EditorDocumentHistory {
  final Expando<EditorDocument> _states = Expando<EditorDocument>();
  void remember(Object historyValue, EditorDocument document) {
    _states[historyValue] = document;
  }
  EditorDocument apply(Object historyValue, String text, EditorDocument current) {
    final remembered = _states[historyValue];
    final next = remembered != null && remembered.text == text
        ? current.restoreText(remembered) : current.copyWith(text: text);
    _states[historyValue] = next;
    return next;
  }
}
