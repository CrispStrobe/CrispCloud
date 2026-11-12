import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ebook_reading_data.dart';

export 'ebook_reading_data.dart';

typedef EbookPreferenceWriter = Future<bool> Function(String key, String value);

/// Local sidecars are scoped to both source identity and exact book bytes.
/// Editing a book cannot silently apply a CFI to a different text position.
class EbookAnnotations {
  EbookAnnotations._(
    this._preferences,
    this.key,
    this.contentSha256,
    this.contentByteLength,
    this.renderer,
    this._writePreference,
  );
  final SharedPreferences _preferences;
  final String key;
  final String contentSha256;
  final int contentByteLength;
  final EbookReaderRenderer renderer;
  final EbookPreferenceWriter? _writePreference;
  EbookLocation? location;
  EbookAppearance appearance = const EbookAppearance();
  final highlights = <EbookHighlight>[];
  final bookmarks = <EbookLocation>[];
  Future<void> _pending = Future.value();
  bool _applyingReadingData = false;
  bool get isApplyingReadingData => _applyingReadingData;

  static Future<EbookAnnotations> open(
    String documentId,
    Uint8List bytes, {
    SharedPreferences? preferences,
    EbookReaderRenderer? renderer,
    EbookPreferenceWriter? writePreference,
  }) async {
    final resolvedRenderer =
        renderer ??
        (documentId.endsWith(':chapter-reader')
            ? EbookReaderRenderer.portable
            : EbookReaderRenderer.foliate);
    final scopedIdentity =
        resolvedRenderer == EbookReaderRenderer.portable &&
            !documentId.endsWith(':chapter-reader')
        ? '$documentId:chapter-reader'
        : documentId;
    final identity = sha256.convert(utf8.encode(scopedIdentity));
    final revision = sha256.convert(bytes);
    final result = EbookAnnotations._(
      preferences ?? await SharedPreferences.getInstance(),
      'ebook.annotations.v1.$identity.$revision',
      revision.toString(),
      bytes.length,
      resolvedRenderer,
      writePreference,
    );
    final raw = result._preferences.get(result.key);
    if (raw is! String || raw.length > 2 * 1024 * 1024) return result;
    try {
      checkEbookJsonBounds(
        raw,
        maximumBytes: EbookReadingData.maximumJsonBytes,
      );
      final json = jsonDecode(raw) as Map<String, dynamic>;
      // Older local sidecars already have a renderer-specific document key.
      // New writes additionally make that binding explicit in their payload.
      if (json.containsKey('readerDataVersion') &&
          (json['readerDataVersion'] != 1 ||
              json['renderer'] != result.renderer.wireName ||
              json['contentSha256'] != result.contentSha256 ||
              json['contentByteLength'] != result.contentByteLength)) {
        return result;
      }
      if (json['location'] case final Map value) {
        result.location = EbookLocation.fromJson(
          Map<String, dynamic>.from(value),
        );
      }
      for (final value in (json['bookmarks'] as List? ?? const []).take(500)) {
        result.bookmarks.add(
          EbookLocation.fromJson(Map<String, dynamic>.from(value as Map)),
        );
      }
      for (final value in (json['highlights'] as List? ?? const []).take(500)) {
        final item = Map<String, dynamic>.from(value as Map);
        result.highlights.add(
          EbookHighlight(
            id: item['id'] as String,
            cfi: item['cfi'] as String,
            color: item['color'] as String? ?? '#f9d66b',
            note: item['note'] as String? ?? '',
          ),
        );
      }
      final style = json['appearance'] as Map?;
      if (style != null) {
        result.appearance = EbookAppearance.fromJson(
          Map<String, dynamic>.from(style),
        );
      }
    } catch (_) {
      // A corrupt local preference must not prevent the book from opening.
      result.location = null;
      result.highlights.clear();
      result.bookmarks.clear();
      result.appearance = const EbookAppearance();
    }
    return result;
  }

  Future<void> save() {
    if (_applyingReadingData) return _pending.then((_) => save());
    final String encoded;
    try {
      encoded = _encodeState();
    } on Object catch (error, stack) {
      return Future.error(error, stack);
    }
    final next = _pending.then((_) => _persist(encoded));
    _pending = next.catchError((Object _) {});
    return next;
  }

  String _encodeState({EbookReadingData? replacement}) {
    final encoded = jsonEncode({
      'readerDataVersion': 1,
      'renderer': renderer.wireName,
      'contentSha256': contentSha256,
      'contentByteLength': contentByteLength,
      'location': replacement == null
          ? location?.toJson()
          : replacement.location?.toJson(),
      'appearance': (replacement?.appearance ?? appearance).toJson(),
      'bookmarks': (replacement?.bookmarks ?? bookmarks)
          .take(500)
          .map((item) => item.toJson())
          .toList(),
      'highlights': (replacement?.highlights ?? highlights)
          .take(500)
          .map((item) => item.toJson())
          .toList(),
    });
    if (encoded.length > EbookReadingData.maximumJsonBytes ||
        utf8.encode(encoded).length > EbookReadingData.maximumJsonBytes) {
      throw StateError('The book annotation limit was reached.');
    }
    return encoded;
  }

  Future<void> _persist(String encoded) async {
    try {
      if (!await (_writePreference?.call(key, encoded) ??
          _preferences.setString(key, encoded))) {
        throw StateError('Could not save reading progress on this device.');
      }
    } on Object {
      // SharedPreferences updates its cache before the platform confirms a
      // write. Reload it after failure so reopening cannot see an unsaved draft.
      try {
        await _preferences.reload();
      } on Object {
        /* Keep the write error. */
      }
      rethrow;
    }
  }

  EbookReadingData snapshotReadingData() => EbookReadingData.capture(
    contentSha256: contentSha256,
    contentByteLength: contentByteLength,
    renderer: renderer,
    location: location,
    appearance: appearance,
    bookmarks: bookmarks,
    highlights: highlights,
  );

  String exportReadingData() => snapshotReadingData().encode();

  EbookReadingDataImportPlan previewReadingDataImport(
    String encoded, {
    EbookReadingDataMergeMode mode =
        EbookReadingDataMergeMode.mergeKeepExisting,
  }) => EbookReadingDataImportPlan.prepare(
    bindingKey: key,
    local: snapshotReadingData(),
    imported: EbookReadingData.decode(encoded),
    mode: mode,
  );

  /// Validate the entire reviewed batch before one preference write, then
  /// publish it together. A failed write leaves the live annotation lists alone.
  /// The host pauses passive relocation while [isApplyingReadingData] is true.
  Future<void> applyReadingDataImport(EbookReadingDataImportPlan plan) {
    final next = _pending.then((_) async {
      final current = snapshotReadingData();
      current.requireCompatible(plan.result);
      if (plan.bindingKey != key ||
          plan.localFingerprint != current.fingerprint) {
        throw const EbookReadingDataException(
          EbookReadingDataError.stale,
          'Reading data changed after the import preview. Review it again.',
        );
      }
      if (!plan.hasChanges) return;
      final before = _encodeState();
      final encoded = _encodeState(replacement: plan.result);
      _applyingReadingData = true;
      try {
        await _persist(encoded);
        // Existing UI consumers expose mutable lists. Never overwrite a newer
        // local edit if one arrived while the platform write was outstanding.
        final latest = _encodeState();
        if (latest != before) {
          await _persist(latest);
          throw const EbookReadingDataException(
            EbookReadingDataError.stale,
            'Reading data changed while importing. Review the import again.',
          );
        }
        location = plan.result.location;
        appearance = plan.result.appearance;
        bookmarks
          ..clear()
          ..addAll(plan.result.bookmarks);
        highlights
          ..clear()
          ..addAll(plan.result.highlights);
      } finally {
        _applyingReadingData = false;
      }
    });
    _pending = next.catchError((Object _) {});
    return next;
  }
}
