import 'dart:typed_data';

import 'ebook_edit_session.dart';
import 'pdf_file_store.dart';

const kEbookInputLimitBytes = 64 * 1024 * 1024;
const kEbookOutputLimitBytes = 128 * 1024 * 1024;

bool isEbookFileName(String name) => const {
  'epub',
  'mobi',
  'azw',
  'azw3',
  'fb2',
  'fbz',
  'cbz',
}.contains(name.toLowerCase().split('.').last);

EbookSaveOutcome ebookSaveOutcome(PdfSaveOutcome outcome) => switch (outcome) {
  PdfSaveOutcome.savedOriginal => EbookSaveOutcome.savedOriginal,
  PdfSaveOutcome.savedCopy => EbookSaveOutcome.savedCopy,
  PdfSaveOutcome.downloadedCopy => EbookSaveOutcome.downloadedCopy,
};

/// Reuses the existing fresh-read/conflict/account and staged-write store.
/// The host supplies copyExtension:null so EPUB and Kindle copies keep their
/// declared formats. EPUB bytes may only update an original EPUB.
class EbookFileStore {
  const EbookFileStore(this._store);
  final PdfFileStore _store;
  String get documentId => _store.documentId;
  String get displayName => _store.displayName;
  String get path => _store.path;

  Future<Uint8List> load() => _store.load();

  Future<EbookSaveOutcome> save(Uint8List bytes) async {
    if (!displayName.toLowerCase().endsWith('.epub')) {
      throw StateError('Save the converted book as a new EPUB file.');
    }
    return ebookSaveOutcome(await _store.save(bytes));
  }

  Future<EbookSaveOutcome> saveCopy(Uint8List bytes, String name) async {
    if (!const {
      'epub',
      'mobi',
      'azw3',
    }.contains(name.toLowerCase().split('.').last)) {
      throw ArgumentError('Choose an EPUB, MOBI or AZW3 filename.');
    }
    return ebookSaveOutcome(await _store.saveCopy(bytes, name));
  }

  /// Only the Kindle metadata API may write native Kindle bytes in place.
  Future<EbookSaveOutcome> saveKindleMetadata(Uint8List bytes) async {
    if (!const {
      'mobi',
      'azw',
      'azw3',
    }.contains(displayName.toLowerCase().split('.').last)) {
      throw StateError('This is not a Kindle file.');
    }
    return ebookSaveOutcome(await _store.save(bytes));
  }
}
