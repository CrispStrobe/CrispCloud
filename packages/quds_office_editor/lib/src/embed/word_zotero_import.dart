import 'package:quds_office_engine/quds_office_engine.dart';

import 'word_zotero_format.dart';

/// A searchable view of one imported record. Its original position is part of
/// the selection key, so filtering never conflates duplicate CSL identifiers.
class ZoteroImportedReference {
  factory ZoteroImportedReference({
    required int index,
    required ZoteroCitationItem item,
  }) {
    final data = item.itemData ?? const <String, Object?>{};
    final title = zoteroHtmlToPlainText(_text(data['title'], '${item.id}'));
    final authors = _names(data['author']);
    final editors = _names(data['editor']);
    final year = _year(data['issued']);
    final creators = [
      ...authors,
      ...editors,
      for (final role in const [
        'translator',
        'collection-editor',
        'container-author',
        'original-author',
        'reviewed-author',
        'editorial-director',
        'illustrator',
        'composer',
        'interviewer',
        'recipient',
      ])
        ..._names(data[role]),
    ];
    final searchText = [
      title,
      ...creators,
      year,
      _text(data['DOI']),
    ].join('\n').toLowerCase();
    return ZoteroImportedReference._(
      searchText,
      index: index,
      item: item,
      title: title,
      subtitle: [
        if (authors.isNotEmpty)
          authors.join(', ')
        else if (editors.isNotEmpty)
          editors.join(', '),
        if (year.isNotEmpty) year,
      ].join(' · '),
    );
  }

  const ZoteroImportedReference._(
    this._searchText, {
    required this.index,
    required this.item,
    required this.title,
    required this.subtitle,
  });

  final int index;
  final ZoteroCitationItem item;
  final String title;
  final String subtitle;
  final String _searchText;

  String get selectionKey => 'import:$index:${item.id}';
}

/// Matches every whitespace-separated term literally, ignoring case. Metadata
/// and the original import order remain untouched, including hidden selections.
List<ZoteroImportedReference> filterZoteroImportedReferences(
  Iterable<ZoteroImportedReference> references,
  String query,
) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList(growable: false);
  return List.unmodifiable(
    references.where(
      (reference) => terms.every(reference._searchText.contains),
    ),
  );
}

String _text(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

List<String> _names(Object? value) {
  if (value is! List<Object?>) return const [];
  return [
    for (final name in value)
      if (name is Map<String, Object?>)
        if (_text(name['literal']).isNotEmpty)
          _text(name['literal'])
        else
          [
            for (final field in const [
              'given',
              'dropping-particle',
              'non-dropping-particle',
              'family',
              'suffix',
            ])
              if (_text(name[field]).isNotEmpty) _text(name[field]),
          ].join(' '),
  ].where((name) => name.isNotEmpty).toList(growable: false);
}

String _year(Object? value) {
  if (value is! Map<String, Object?>) return '';
  final parts = value['date-parts'];
  if (parts is List<Object?> && parts.isNotEmpty) {
    final first = parts.first;
    if (first is List<Object?> && first.isNotEmpty) {
      final year = first.first;
      if (year is int || year is String) return '$year';
    }
  }
  final literal = _text(value['literal'], _text(value['raw']));
  return RegExp(r'\b\d{4}\b').firstMatch(literal)?.group(0) ?? literal;
}
