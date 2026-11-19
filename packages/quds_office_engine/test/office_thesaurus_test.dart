import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/src/opc/zip/deflate_codec.dart';
import 'package:quds_office_engine/src/thesaurus/office_thesaurus.dart';
import 'package:test/test.dart';

void main() {
  test('UTF-8 shard vectors match the compiler on VM and JavaScript', () {
    expect(['bank', 'häuser', 'maße', 'ice cream', '😀'].map(thesaurusShard), [
      '97',
      'eb',
      '30',
      '1e',
      '08',
    ]);
  });
  test('unsupported language and missing pack are distinct', () async {
    final service = OfficeThesaurusService(loadAsset: (_) async => null);
    expect(
      (await service.lookup(query('bank', 'fr-FR'))).status,
      OfficeThesaurusStatus.unsupportedLanguage,
    );
    expect(
      (await service.lookup(query('bank'))).status,
      OfficeThesaurusStatus.missingPack,
    );
  });

  test('source meanings, labels and relations remain separate', () async {
    final fixture = PackFixture()
      ..sense('finance', ['bank', 'depository'])
      ..sense('shore', ['bank', 'riverbank']);
    fixture.senses['finance']!['relations'] = [
      {'type': 'hypernym', 'target': 'institution'},
    ];
    fixture.senses['finance']!['labels'] = ['finance'];
    final result = await fixture.service().lookup(query('bank'));
    expect(result.status, OfficeThesaurusStatus.ready);
    expect(result.senses.map((s) => s.id), ['finance', 'shore']);
    expect(result.senses.first.labels, ['finance']);
    expect(result.senses.first.relations.single.target, 'institution');
    expect(result.senses.first.terms.map((t) => t.text), [
      'bank',
      'depository',
    ]);
    expect(result.containsTerm(result.senses.first.terms.last), isTrue);
    expect(
      result.containsTerm(
        OfficeThesaurusTerm(id: 'finance-1', text: 'depository'),
      ),
      isFalse,
    );
  });

  test(
    'normalization keeps original source query and phrase spellings',
    () async {
      final fixture = PackFixture()..sense('phrase', ['ice cream', 'ice']);
      final result = await fixture.service().lookup(query(' ICE\u00a0CREAM '));
      expect(result.status, OfficeThesaurusStatus.ready);
      expect(result.query.text, ' ICE\u00a0CREAM ');
      expect(result.senses.single.terms.first.text, 'ice cream');
      expect(normalizeThesaurusTerm('co\u00adoperate'), 'cooperate');
    },
  );

  test('German sharp-s and umlauts are not folded', () async {
    final fixture = PackFixture(locale: 'de')
      ..sense('measure', ['Maße', 'Abmessungen'])
      ..sense('mass', ['Masse', 'Stoffmenge']);
    final service = fixture.service();
    expect(
      (await service.lookup(query('Maße', 'de-DE'))).senses.single.id,
      'measure',
    );
    expect(
      (await service.lookup(query('Masse', 'de-DE'))).senses.single.id,
      'mass',
    );
    expect(
      normalizeThesaurusTerm('Häuser'),
      isNot(normalizeThesaurusTerm('Hauser')),
    );
  });

  test('source aliases preserve ambiguity and compatible POS', () async {
    final fixture = PackFixture()
      ..sense('noun', ['saw', 'handsaw'], pos: 'n')
      ..sense('verb', ['see', 'observe'], pos: 'v')
      ..alias('saw', 'see', 'v');
    final result = await fixture.service().lookup(query('saw'));
    expect(result.senses.map((s) => s.id).toSet(), {'noun', 'verb'});
    expect(result.matchedTerms.map((m) => m.reason), [
      'lexical',
      'source-form',
    ]);
  });

  test(
    'German noun fallback normalizes lookup whitespace and soft hyphens',
    () async {
      final fixture = PackFixture(locale: 'de')
        ..sense('house', ['Haus', 'Gebäude']);
      final result = await fixture.service().lookup(
        query(' Häu\u00adsern\u00a0', 'de-DE'),
      );
      expect(result.status, OfficeThesaurusStatus.ready);
      expect(result.matchedTerms.single.text, 'Haus');
      expect(result.matchedTerms.single.reason, 'unicode-noun-form');
      expect(result.query.text, ' Häu\u00adsern\u00a0');
    },
  );

  test('detachment fallback cannot import an incompatible POS', () async {
    final fixture = PackFixture()
      ..sense('noun', ['walk', 'walkway'], pos: 'n')
      ..sense('verb', ['walk', 'stroll'], pos: 'v');
    fixture.morphology = {
      'source': 'princeton-wordnet',
      'version': '3.0',
      'rules': [
        {'suffix': 'ed', 'ending': '', 'pos': 'v'},
      ],
    };
    final result = await fixture.service().lookup(query('walked'));
    expect(result.senses.map((s) => s.id), ['verb']);
    expect(result.matchedTerms.single.reason, 'wordnet-detachment');
  });

  test('no entry remains separate from malformed index', () async {
    final fixture = PackFixture()..sense('good', ['good', 'fine']);
    final service = fixture.service();
    expect(
      (await service.lookup(query('not-present'))).status,
      OfficeThesaurusStatus.noEntry,
    );
    fixture.index['broken'] = {};
    final malformed = await fixture.service().lookup(query('broken'));
    expect(malformed.status, OfficeThesaurusStatus.failedPack);
  });

  test('null index record is a damaged pack', () async {
    final fixture = PackFixture();
    fixture.index['broken'] = null;
    expect(
      (await fixture.service().lookup(query('broken'))).status,
      OfficeThesaurusStatus.failedPack,
    );
  });

  test('a missing referenced meaning is a damaged pack', () async {
    final fixture = PackFixture();
    fixture.index['broken'] = {
      'senseIds': ['absent'],
    };
    expect(
      (await fixture.service().lookup(query('broken'))).status,
      OfficeThesaurusStatus.failedPack,
    );
  });

  test('source identity mismatch fails closed', () async {
    final fixture = PackFixture()..sense('good', ['good', 'fine']);
    fixture.senses['good']!['source'] = 'foreign';
    expect(
      (await fixture.service().lookup(query('good'))).status,
      OfficeThesaurusStatus.failedPack,
    );
  });

  test(
    'control characters in literal replacement terms are rejected',
    () async {
      final fixture = PackFixture()..sense('good', ['good', 'bad\ntext']);
      expect(
        (await fixture.service().lookup(query('good'))).status,
        OfficeThesaurusStatus.failedPack,
      );
    },
  );

  test('pinned manifest rejects modification', () async {
    final fixture = PackFixture()..sense('good', ['good', 'fine']);
    final files = fixture.files();
    final pin = sha256
        .convert(utf8.encode(files['en/manifest.json']!))
        .toString();
    files['en/manifest.json'] = '${files['en/manifest.json']} ';
    final service = OfficeThesaurusService(
      loadAsset: (p) async => files[p],
      manifestSha256: {'en': pin},
    );
    expect(
      (await service.lookup(query('good'))).status,
      OfficeThesaurusStatus.failedPack,
    );
  });

  test('logical digest detects damaged shard bytes', () async {
    final fixture = PackFixture()..sense('good', ['good', 'fine']);
    final files = fixture.files();
    files['en/index/${thesaurusShard('good')}.json'] = '{}';
    final service = OfficeThesaurusService(loadAsset: (p) async => files[p]);
    expect(
      (await service.lookup(query('good'))).status,
      OfficeThesaurusStatus.failedPack,
    );
  });

  test('compressed shards verify both forms and load on demand', () async {
    final fixture = PackFixture()..sense('good', ['good', 'fine']);
    final files = fixture.files(compress: true);
    final reads = <String>[];
    final service = OfficeThesaurusService(
      loadAsset: (p) async => files[p],
      loadCompressedAsset: (p) async {
        reads.add(p);
        return fixture.compressed[p];
      },
    );
    expect(
      (await service.lookup(query('good'))).status,
      OfficeThesaurusStatus.ready,
    );
    expect(reads.length, 2);
    expect(reads.every((p) => p.endsWith('.json.deflate')), isTrue);
    expect(service.cachedShardCount, 2);
  });

  test('compressed digest detects damage before decompression', () async {
    final fixture = PackFixture()..sense('good', ['good', 'fine']);
    final files = fixture.files(compress: true);
    fixture.compressed['en/index/${thesaurusShard('good')}.json.deflate'] = [
      1,
      2,
      3,
    ];
    final service = OfficeThesaurusService(
      loadAsset: (p) async => files[p],
      loadCompressedAsset: (p) async => fixture.compressed[p],
    );
    expect(
      (await service.lookup(query('good'))).status,
      OfficeThesaurusStatus.failedPack,
    );
  });

  test('decompression cannot exceed declared logical size', () async {
    final fixture = PackFixture()..sense('good', ['good', 'fine']);
    final files = fixture.files(compress: true);
    final manifest =
        jsonDecode(files['en/manifest.json']!) as Map<String, Object?>;
    final manifestFiles = manifest['files']! as Map<String, Object?>;
    final entry =
        manifestFiles['index/${thesaurusShard('good')}.json']!
            as Map<String, Object?>;
    entry['size'] = 1;
    files['en/manifest.json'] = jsonEncode(manifest);
    final service = OfficeThesaurusService(
      loadAsset: (p) async => files[p],
      loadCompressedAsset: (p) async => fixture.compressed[p],
    );
    expect(
      (await service.lookup(query('good'))).status,
      OfficeThesaurusStatus.failedPack,
    );
  });

  test('compressed packs require an explicit byte loader', () async {
    final fixture = PackFixture()..sense('good', ['good', 'fine']);
    final files = fixture.files(compress: true);
    final service = OfficeThesaurusService(loadAsset: (p) async => files[p]);
    expect(
      (await service.lookup(query('good'))).status,
      OfficeThesaurusStatus.failedPack,
    );
  });

  test(
    'missing shard is a failed pack, not missing corpus or no entry',
    () async {
      final fixture = PackFixture()..sense('good', ['good', 'fine']);
      final files = fixture.files()
        ..remove('en/index/${thesaurusShard('good')}.json');
      final service = OfficeThesaurusService(loadAsset: (p) async => files[p]);
      expect(
        (await service.lookup(query('good'))).status,
        OfficeThesaurusStatus.failedPack,
      );
    },
  );

  test(
    'pack clear rejects an in-flight result without restoring old caches',
    () async {
      final fixture = PackFixture()..sense('good', ['good', 'fine']);
      final files = fixture.files();
      final started = Completer<void>(), release = Completer<void>();
      final service = OfficeThesaurusService(
        loadAsset: (p) async {
          if (p.contains('/index/')) {
            started.complete();
            await release.future;
          }
          return files[p];
        },
      );
      final pending = service.lookup(query('good'));
      await started.future;
      service.clear();
      release.complete();
      expect((await pending).status, OfficeThesaurusStatus.failedPack);
      expect(service.cachedShardCount, 0);
      expect(service.cachedResultCount, 0);
      expect(service.revision, 1);
    },
  );

  test(
    'cache limits remain bounded and repeated results retain candidate identity',
    () async {
      final fixture = PackFixture()
        ..sense('first', ['alpha', 'first'])
        ..sense('second', ['omega', 'last']);
      final files = fixture.files();
      final service = OfficeThesaurusService(
        loadAsset: (p) async => files[p],
        maxCachedShards: 1,
        maxCachedResults: 1,
      );
      final first = await service.lookup(query('alpha'));
      expect(identical(await service.lookup(query('alpha')), first), isTrue);
      await service.lookup(query('omega'));
      expect(service.cachedShardCount, 1);
      expect(service.cachedResultCount, 1);
    },
  );

  test('pack notices are read through integrity checks', () async {
    final fixture = PackFixture()..sense('good', ['good', 'fine']);
    final files = fixture.files();
    final service = OfficeThesaurusService(loadAsset: (p) async => files[p]);
    final result = await service.lookup(query('good'));
    expect(
      (await service.notices(result)).single.text,
      'Fixture source notice',
    );
    files['en/notices/LICENSE.txt'] = 'tampered';
    await expectLater(service.notices(result), throwsFormatException);
  });

  test(
    'default cache retains high-polysemy meanings across equivalent queries',
    () async {
      final fixture = PackFixture();
      final usedShards = <String>{};
      for (var i = 0; usedShards.length < 50; i++) {
        final id = 'polysemy-$i';
        if (usedShards.add(thesaurusShard(id))) {
          fixture.sense(id, ['run', 'alternative-$i']);
        }
      }
      final files = fixture.files();
      var reads = 0;
      final service = OfficeThesaurusService(
        loadAsset: (path) async {
          reads++;
          return files[path];
        },
      );
      final first = await service.lookup(query('run'));
      expect(first.senses, hasLength(50));
      final firstReads = reads;
      // Different original text bypasses the result cache but uses the same
      // normalized term. The former32-shard limit thrashed on such queries.
      final second = await service.lookup(query(' run '));
      expect(second.senses, hasLength(50));
      expect(reads, firstReads);
      expect(service.cachedShardCount, lessThanOrEqualTo(64));
    },
  );
}

OfficeThesaurusQuery query(String text, [String language = 'en-US']) =>
    OfficeThesaurusQuery(text: text, language: language);

class PackFixture {
  PackFixture({this.locale = 'en'});
  final String locale;
  final senses = <String, Map<String, Object?>>{};
  final index = <String, Object?>{};
  final compressed = <String, List<int>>{};
  Map<String, Object?>? morphology;

  void sense(String id, List<String> terms, {String? pos}) {
    senses[id] = {
      'id': id,
      'source': 'fixture',
      'pos': ?pos,
      'terms': [
        for (var i = 0; i < terms.length; i++)
          {'id': '$id-$i', 'text': terms[i]},
      ],
    };
    for (final term in terms) {
      final entry =
          index.putIfAbsent(
                normalizeThesaurusTerm(term),
                () => <String, Object?>{
                  'senseIds': <String>[],
                  'aliases': <Object?>[],
                },
              )
              as Map<String, Object?>;
      (entry['senseIds']! as List<String>).add(id);
    }
  }

  void alias(String surface, String lemma, String pos) {
    final entry =
        index.putIfAbsent(
              normalizeThesaurusTerm(surface),
              () => <String, Object?>{
                'senseIds': <String>[],
                'aliases': <Object?>[],
              },
            )
            as Map<String, Object?>;
    (entry['aliases']! as List<Object?>).add({
      'lemma': lemma,
      'pos': pos,
      'reason': 'source-form',
    });
  }

  Map<String, String> files({bool compress = false}) {
    final files = <String, String>{};
    final metadata = <String, Object?>{};
    void add(String path, String text, {bool zipped = false}) {
      final bytes = utf8.encode(text);
      final info = <String, Object?>{
        'sha256': sha256.convert(bytes).toString(),
        'size': bytes.length,
      };
      if (zipped) {
        final binary = RawDeflate.deflate(bytes);
        compressed['$locale/$path.deflate'] = binary;
        info.addAll({
          'compression': 'deflate-raw',
          'compressedSha256': sha256.convert(binary).toString(),
          'compressedSize': binary.length,
        });
      } else {
        files['$locale/$path'] = text;
      }
      metadata[path] = info;
    }

    for (var i = 0; i < 256; i++) {
      final suffix = i.toRadixString(16).padLeft(2, '0');
      add(
        'index/$suffix.json',
        jsonEncode({
          for (final e in index.entries)
            if (thesaurusShard(e.key) == suffix) e.key: e.value,
        }),
        zipped: compress,
      );
      add(
        'senses/$suffix.json',
        jsonEncode({
          for (final e in senses.entries)
            if (thesaurusShard(e.key) == suffix) e.key: e.value,
        }),
        zipped: compress,
      );
    }
    add('notices/LICENSE.txt', 'Fixture source notice');
    if (morphology != null) {
      add('morphology.json', jsonEncode(morphology), zipped: compress);
    }
    files['$locale/manifest.json'] = jsonEncode({
      'schemaVersion': 1,
      'locale': locale,
      'normalization': 'lower-whitespace-v1',
      'shardAlgorithm': 'fnv1a32-utf8-low8',
      'packId': 'fixture-$locale',
      'version': '1',
      'source': 'fixture',
      'name': 'Fixture',
      'license': 'MIT',
      'sourceUrl': 'https://example.invalid',
      'attribution': 'Fixture',
      'noticePaths': ['notices/LICENSE.txt'],
      'files': metadata,
    });
    return files;
  }

  OfficeThesaurusService service() {
    final content = files();
    return OfficeThesaurusService(loadAsset: (p) async => content[p]);
  }
}
