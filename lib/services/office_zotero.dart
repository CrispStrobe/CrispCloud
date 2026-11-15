import 'package:quds_office_editor/quds_office_editor.dart'
    show WordEditorController;

import 'office_zotero_transport.dart' show OfficeZoteroException;
import 'secure_storage_service.dart';

export 'office_zotero_transport.dart';

/// Captures the intended insertion target before asynchronous credential I/O.
/// Layout-only notifications preserve this value; document, content, story or
/// selection changes invalidate it even when the controller is still mounted.
Object officeZoteroEditTarget(WordEditorController controller) => (
  document: controller.document,
  revision: controller.contentRevision,
  caret: controller.caret,
  paragraph: controller.caret.paragraphIndex,
  offset: controller.caret.logicalIndex,
  anchorParagraph: controller.caret.selectionAnchorParagraph,
  anchorOffset: controller.caret.selectionAnchor,
  headerFooter: controller.isEditingHeaderFooter,
  footer: controller.isEditingFooter,
  section: controller.isEditingHeaderFooter
      ? controller.editingSectionIndex
      : null,
  comment: controller.isEditingComment ? controller.selectedComment : null,
  frame: controller.selectedFrame,
  editingFrame: controller.editingFrame,
  table: controller.selectedTable,
  tableBand: controller.selectedTableBand,
  visual: controller.selectedVisual,
  equation: controller.selectedEquation,
);

/// Optional persistence uses the credential store selected at app startup.
/// Session-only storage never pretends to remember a key across restarts.
class OfficeZoteroCredentials {
  OfficeZoteroCredentials(this._storage);

  static const storageKey = 'zotero_api_key';
  final SecureStorage _storage;

  bool get canPersist => _storage.isPersistent;

  Future<String?> load() async {
    if (!canPersist) return null;
    try {
      final key = await _storage.read(storageKey);
      if (key == null || key.trim().isEmpty) return null;
      return _validated(key);
    } catch (_) {
      throw const OfficeZoteroException(
        'Could not read the saved Zotero API key.',
      );
    }
  }

  Future<void> save(String? apiKey) async {
    if (!canPersist) {
      throw const OfficeZoteroException(
        'The current credential store cannot remember Zotero API keys.',
      );
    }
    final key = apiKey == null || apiKey.trim().isEmpty
        ? null
        : _validated(apiKey);
    try {
      if (key == null) {
        await _storage.delete(storageKey);
      } else {
        await _storage.write(storageKey, key);
      }
      if (await _storage.read(storageKey) != key) {
        throw const OfficeZoteroException(
          'The Zotero API key could not be saved in the credential store.',
        );
      }
    } catch (_) {
      throw const OfficeZoteroException(
        'The Zotero API key could not be saved in the credential store.',
      );
    }
  }

  String _validated(String key) {
    if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(key)) {
      throw const OfficeZoteroException('The Zotero API key is invalid.');
    }
    return key.trim();
  }
}
