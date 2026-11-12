import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local sidecars are scoped to both source identity and exact book bytes.
/// Editing a book cannot silently apply a CFI to a different text position.
class EbookAnnotations {
  EbookAnnotations._(this._preferences, this.key);
  final SharedPreferences _preferences;
  final String key;
  EbookLocation? location;
  EbookAppearance appearance = const EbookAppearance();
  final highlights = <EbookHighlight>[];
  final bookmarks = <EbookLocation>[];
  Future<void> _pending = Future.value();

  static Future<EbookAnnotations> open(
    String documentId,
    Uint8List bytes, {
    SharedPreferences? preferences,
  }) async {
    final identity = sha256.convert(utf8.encode(documentId));
    final revision = sha256.convert(bytes);
    final result = EbookAnnotations._(
      preferences ?? await SharedPreferences.getInstance(),
      'ebook.annotations.v1.$identity.$revision',
    );
    final raw = result._preferences.get(result.key);
    if (raw is! String || raw.length > 2 * 1024 * 1024) return result;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
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
        result.appearance = EbookAppearance(
          fontSize: (style['fontSize'] as num?)?.toDouble() ?? 18,
          lineHeight: (style['lineHeight'] as num?)?.toDouble() ?? 1.6,
          theme: const {'light', 'sepia', 'dark'}.contains(style['theme'])
              ? style['theme'] as String
              : 'light',
          flow: const {'paginated', 'scrolled'}.contains(style['flow'])
              ? style['flow'] as String
              : 'paginated',
          fontFamily: style['fontFamily'] as String? ?? 'serif',
        );
      }
    } catch (_) {
      // A corrupt local preference must not prevent the book from opening.
      result.location = null;
      result.highlights.clear();
      result.bookmarks.clear();
    }
    return result;
  }

  Future<void> save() {
    final encoded = jsonEncode({
      'location': location?.toJson(),
      'appearance': appearance.toJson(),
      'bookmarks': bookmarks.take(500).map((item) => item.toJson()).toList(),
      'highlights': highlights.take(500).map((item) => item.toJson()).toList(),
    });
    if (encoded.length > 2 * 1024 * 1024) {
      return Future.error(StateError('The book annotation limit was reached.'));
    }
    final next = _pending.then((_) async {
      if (!await _preferences.setString(key, encoded)) {
        throw StateError('Could not save reading progress on this device.');
      }
    });
    _pending = next.catchError((Object _) {});
    return next;
  }
}
