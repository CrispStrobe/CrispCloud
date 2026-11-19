import 'package:quds_office_engine/quds_office_engine.dart';

import 'word_zotero_format.dart';

// CSL name variables, including the combined editor-translator role when it is
// explicitly stored. No derived role or missing name is invented here.
// https://docs.citationstyles.org/en/stable/specification.html#name-variables
const _creatorRoles = <String, String>{
  'author': 'Authors',
  'editor': 'Editors',
  'translator': 'Translators',
  'chair': 'Chairs',
  'collection-editor': 'Collection editors',
  'compiler': 'Compilers',
  'composer': 'Composers',
  'container-author': 'Container authors',
  'contributor': 'Contributors',
  'curator': 'Curators',
  'director': 'Directors',
  'editor-translator': 'Editors and translators',
  'editorial-director': 'Editorial directors',
  'executive-producer': 'Executive producers',
  'guest': 'Guests',
  'host': 'Hosts',
  'illustrator': 'Illustrators',
  'interviewer': 'Interviewers',
  'narrator': 'Narrators',
  'organizer': 'Organizers',
  'original-author': 'Original authors',
  'performer': 'Performers',
  'producer': 'Producers',
  'recipient': 'Recipients',
  'reviewed-author': 'Reviewed authors',
  'script-writer': 'Script writers',
  'series-creator': 'Series creators',
};

/// Readable fields from an embedded CSL snapshot, without fetching metadata or
/// interpreting its URLs. Missing or malformed optional shapes are omitted.
/// Citation locators, affixes and author-display options are not source data.
List<(String, String)> zoteroStoredReferenceDetailFields(
  ZoteroCitationItem item,
) {
  final data = item.itemData ?? const <String, Object?>{};
  final title = _plainText(data['title']);
  final issued = data['issued'];
  final issuedObject = issued is Map<String, Object?>
      ? issued
      : const <String, Object?>{};
  final linkedUris = item.uris
      .where((uri) => ZoteroSourceAddress.parse(uri) != null)
      .toSet();
  final storedUris = <String>{
    ...item.uris,
    if (data['uri'] case final String uri) uri,
    if (data['uris'] case final List<Object?> uris) ...uris.whereType<String>(),
  }..removeAll(linkedUris);
  final fields = <(String, String)>[
    ('Title', title.isEmpty ? '${item.id}' : title),
    for (final role in _creatorRoles.entries)
      (role.value, _names(data[role.key])),
    ('Reference type', _text(data['type'])),
    ('Publication', _plainText(data['container-title'])),
    ('Collection', _plainText(data['collection-title'])),
    ('Edition', _scalar(data['edition'])),
    ('Volume', _scalar(data['volume'])),
    ('Issue', _scalar(data['issue'])),
    ('Pages', _scalar(data['page'])),
    (
      'Issued date',
      issued is String ? issued : _dateParts(issuedObject['date-parts']),
    ),
    ('Issued date (literal)', _text(issuedObject['literal'])),
    ('Issued date (raw)', _text(issuedObject['raw'])),
    ('Issued season', _scalar(issuedObject['season'])),
    ('Approximate date', _flag(issuedObject['circa'])),
    ('Publisher', _plainText(data['publisher'])),
    ('Publisher place', _text(data['publisher-place'])),
    ('DOI', _text(data['DOI'])),
    ('URL', _text(data['URL'])),
    ('ISBN', _text(data['ISBN'])),
    ('ISSN', _text(data['ISSN'])),
    ('Language', _text(data['language'])),
    ('Reference ID', '${item.id}'),
    if (_scalar(data['id']).isNotEmpty && _scalar(data['id']) != '${item.id}')
      ('Stored CSL ID', _scalar(data['id'])),
    if (linkedUris.isEmpty) ('Source linkage', 'Embedded source only'),
    ('Zotero links', linkedUris.join('\n')),
    (
      'Stored URI metadata',
      storedUris.where((uri) => uri.isNotEmpty).join('\n'),
    ),
    // Abstracts can contain scientific comparisons such as A < B and C > D.
    // They are selectable literal text, never parsed as HTML or launched.
    ('Abstract', _text(data['abstract'])),
  ];
  return List.unmodifiable(fields.where((field) => field.$2.isNotEmpty));
}

/// The same stored fields shown in the details view, ready for plain-text copy.
String zoteroStoredReferenceDetailsText(ZoteroCitationItem item) =>
    zoteroStoredReferenceDetailFields(
      item,
    ).map((field) => '${field.$1}: ${field.$2}').join('\n\n');

String _text(Object? value) => value is String ? value : '';

String _plainText(Object? value) => zoteroHtmlToPlainText(_text(value));

String _scalar(Object? value) => switch (value) {
  final String text => text,
  final num number when number.isFinite => '$number',
  _ => '',
};

String _names(Object? value) {
  if (value is! List<Object?>) return '';
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
  ].where((name) => name.isNotEmpty).join('\n');
}

String _dateParts(Object? value) {
  if (value is! List<Object?> || value.isEmpty || value.length > 2) return '';
  final dates = <String>[];
  for (final date in value) {
    if (date is! List<Object?> || date.isEmpty || date.length > 3) return '';
    final parts = date.map(_scalar).toList(growable: false);
    if (parts.any((part) => part.isEmpty)) return '';
    dates.add(
      [
        parts.first,
        for (final part in parts.skip(1))
          RegExp(r'^\d{1,2}$').hasMatch(part) ? part.padLeft(2, '0') : part,
      ].join('-'),
    );
  }
  return dates.join(' – ');
}

String _flag(Object? value) => switch (value) {
  true || 1 || '1' || 'true' => 'Yes',
  false || 0 || '0' || 'false' => 'No',
  _ => '',
};
