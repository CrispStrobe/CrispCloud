import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

/// Small synthetic packs for editor protocol tests; lexical acceptance uses
/// the actual bundled corpora separately.
Map<String, String> thesaurusFixtureAssets({
  String locale = 'en',
  Map<String, List<String>>? entries,
  List<Map<String, Object?>>? senses,
}) {
  entries ??= locale == 'de'
      ? {
          'Bank': ['Geldinstitut', 'Sitzbank'],
          'Haus': ['Gebäude'],
        }
      : {
          'bank': ['depository', 'financial institution'],
          'financial institution': ['bank'],
          'café': ['coffeehouse'],
          'cafe\u0301': ['coffeehouse'],
          'fast': ['quick'],
          'hello': ['greetings'],
        };
  final records =
      senses ??
      [
        for (final entry in entries.entries)
          {
            'id': 'fixture:${entries.keys.toList().indexOf(entry.key)}',
            'source': 'fixture',
            'pos': 'n',
            'gloss': entry.key == 'bank'
                ? 'A financial business.'
                : 'A test meaning for ${entry.key}.',
            'examples': ['Use ${entry.key} in a sentence.'],
            'terms': [
              for (final text in [entry.key, ...entry.value])
                {
                  'id': '${entry.key}:$text',
                  'text': text,
                  'sourceIds': ['fixture-term:$text'],
                  if (text == 'depository') 'labels': ['formal'],
                },
            ],
            'relations': [
              {'type': 'hypernym', 'target': 'fixture:related'},
            ],
          },
      ];
  final shards = <String, Map<String, Object?>>{
    for (var i = 0; i < 256; i++)
      'index/${i.toRadixString(16).padLeft(2, '0')}.json': {},
    for (var i = 0; i < 256; i++)
      'senses/${i.toRadixString(16).padLeft(2, '0')}.json': {},
  };
  for (final sense in records) {
    final id = sense['id']! as String;
    shards['senses/${thesaurusShard(id)}.json']![id] = sense;
    for (final value in sense['terms']! as List) {
      final term = value as Map;
      final key = normalizeThesaurusTerm(term['text']! as String);
      final shard = shards['index/${thesaurusShard(key)}.json']!;
      final entry =
          shard.putIfAbsent(
                key,
                () => <String, Object?>{
                  'senseIds': <String>[],
                  'aliases': <Object?>[],
                },
              )!
              as Map<String, Object?>;
      final ids = entry['senseIds']! as List<String>;
      if (!ids.contains(id)) ids.add(id);
    }
  }
  final files = <String, String>{
    for (final entry in shards.entries) entry.key: jsonEncode(entry.value),
    'notices/LICENSE.txt': 'Synthetic fixture data, CC0. Not a lexical corpus.',
  };
  final manifest = jsonEncode({
    'schemaVersion': 1,
    'packId': 'fixture-$locale',
    'version': '1',
    'locale': locale,
    'source': 'fixture',
    'name': 'Test thesaurus',
    'license': 'CC0',
    'sourceUrl': 'https://example.invalid/test-fixture',
    'attribution': 'Synthetic editor test fixtures.',
    'normalization': 'lower-whitespace-v1',
    'shardAlgorithm': 'fnv1a32-utf8-low8',
    'noticePaths': ['notices/LICENSE.txt'],
    'files': {
      for (final entry in files.entries)
        entry.key: {
          'sha256': sha256.convert(utf8.encode(entry.value)).toString(),
          'size': utf8.encode(entry.value).length,
        },
    },
  });
  return {
    '$locale/manifest.json': manifest,
    for (final entry in files.entries) '$locale/${entry.key}': entry.value,
  };
}

OfficeThesaurusService testThesaurusService({
  String locale = 'en',
  Map<String, List<String>>? entries,
  Map<String, String>? assets,
  Future<void>? gate,
  void Function(String path)? onRead,
}) {
  final files =
      assets ?? thesaurusFixtureAssets(locale: locale, entries: entries);
  return OfficeThesaurusService(
    loadAsset: (path) async {
      onRead?.call(path);
      if (gate != null) await gate;
      return files[path];
    },
  );
}
