import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/l10n/help_guide_strings.dart';
import 'package:crisp_cloud/services/help_guide_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class HelpTestBundle extends CachingAssetBundle {
  HelpTestBundle(this.values);
  final Map<String, String> values;
  final reads = <String>[];
  @override
  Future<ByteData> load(String key) async {
    reads.add(key);
    final value = values[key];
    if (value == null) throw StateError('Missing test asset');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
  }
}

const helpEnglish = '''# Guide

<a id="getting-started"></a>
## Getting started

Read [Recovery](#backup-engine), [Project docs](https://github.com/CrispStrobe/CrispCloud/blob/main/docs/USER_GUIDE.md) or [Invalid link](file:///private).

<a id="backup-engine"></a>
## Transfer recovery

Verify the original account and saved partial file before resuming.
''';
const helpGerman = '''# Handbuch

<a id="getting-started"></a>
## Erste Schritte

Lesen Sie [Wiederherstellung](#backup-engine).

<a id="backup-engine"></a>
## Wiederherstellung

Prüfen Sie das ursprüngliche Konto und die gespeicherte Teildatei.
''';
const helpFrench = '''# Guide français

<a id="getting-started"></a>
## Premiers pas

Lisez [Récupération](#backup-engine).

<a id="backup-engine"></a>
## Récupération

Vérifiez le compte d’origine et le fichier partiel enregistré.
''';

Map<String, String> helpAssets({Map<String, String>? guides}) {
  final contents =
      guides ?? {'en': helpEnglish, 'de': helpGerman, 'fr': helpFrench};
  String digest(String value) => sha256.convert(utf8.encode(value)).toString();
  return {
    for (final entry in contents.entries)
      HelpGuideService.assets[entry.key]!: entry.value,
    HelpGuideService.manifestAsset: jsonEncode({
      'version': 1,
      'sourceLanguage': 'en',
      'guides': {
        for (final entry in contents.entries)
          entry.key: {
            'asset': HelpGuideService.assets[entry.key],
            'sha256': digest(entry.value),
            if (entry.key != 'en') 'sourceSha256': digest(contents['en']!),
          },
      },
    }),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled English German and French guides have matching offline topics and links', () async {
    final values = {
      for (final asset in [
        HelpGuideService.manifestAsset,
        ...HelpGuideService.assets.values,
      ])
        asset: await File(asset).readAsString(),
    };
    final service = HelpGuideService(bundle: HelpTestBundle(values));
    List<String>? ids;
    for (final language in HelpGuideService.assets.keys) {
      final guide = await service.load(language);
      expect(guide.language, language);
      expect(guide.fallback, isNull);
      expect(guide.topics, hasLength(23));
      final current = guide.topics.map((topic) => topic.id).toList();
      if (ids != null) expect(current, ids);
      ids = current;
      for (final match in RegExp(
        r'\]\(([^)]+)\)',
      ).allMatches(values[HelpGuideService.assets[language]]!)) {
        final href = match.group(1)!;
        expect(
          HelpGuideService.internalTopic(href, guide) != null ||
              HelpGuideService.externalLink(href) != null,
          isTrue,
          reason: '$language: $href',
        );
      }
    }
  });

  for (final locale in ['de-DE', 'fr_CA', 'en']) {
    test(
      'regional locale $locale resolves to a verified bundled guide',
      () async {
        final guide = await HelpGuideService(
          bundle: HelpTestBundle(helpAssets()),
        ).load(locale);
        expect(guide.language, locale.substring(0, 2));
        expect(guide.fallback, isNull);
        expect(guide.topic('backup-engine'), isNotNull);
      },
    );
  }

  test('unsupported app language has explicit English fallback without arbitrary asset loads', () async {
    final bundle = HelpTestBundle(helpAssets());
    final guide = await HelpGuideService(bundle: bundle).load('ar');
    expect(guide.requestedLanguage, 'ar');
    expect(guide.language, 'en');
    expect(guide.fallback, HelpFallback.unsupportedLanguage);
    expect(bundle.reads, [
      HelpGuideService.manifestAsset,
      HelpGuideService.assets['en'],
    ]);
  });

  test(
    'an English source update makes an old translation visibly stale',
    () async {
      final values = helpAssets();
      final manifest = jsonDecode(
        values[HelpGuideService.manifestAsset]!,
      ) as Map<String, dynamic>;
      const updated = '$helpEnglish\nNew recovery instructions.\n';
      values[HelpGuideService.assets['en']!] = updated;
      manifest['guides']['en']['sha256'] = sha256
          .convert(utf8.encode(updated))
          .toString();
      values[HelpGuideService.manifestAsset] = jsonEncode(manifest);
      final guide = await HelpGuideService(bundle: HelpTestBundle(values))
          .load('de');
      expect(guide.fallback, HelpFallback.outdated);
      expect(guide.language, 'en');
      expect(guide.topics.last.markdown, contains('New recovery instructions'));
    },
  );

  test(
    'missing translation metadata reports missing, not a claimed translation',
    () async {
      final service = HelpGuideService(
        bundle: HelpTestBundle(helpAssets(guides: {'en': helpEnglish})),
      );
      expect((await service.load('fr')).fallback, HelpFallback.missing);
    },
  );

  for (final failure in [
    'missing asset',
    'bad hash',
    'wrong topic',
    'duplicate topic',
    'oversized',
    'wrong asset',
  ]) {
    test('translation $failure falls back to verified English', () async {
      final values = helpAssets();
      final path = HelpGuideService.assets['de']!;
      if (failure == 'missing asset') values.remove(path);
      if (failure == 'bad hash') {
        values[path] = '$helpGerman\nChanged without review.';
      }
      if (failure == 'wrong topic' ||
          failure == 'duplicate topic' ||
          failure == 'oversized') {
        final replacement = failure == 'wrong topic'
            ? helpGerman.replaceAll('backup-engine', 'different-topic')
            : failure == 'duplicate topic'
            ? helpGerman.replaceAll('backup-engine', 'getting-started')
            : '$helpGerman${'x' * HelpGuideService.maxGuideBytes}';
        values.addAll(
          helpAssets(
            guides: {'en': helpEnglish, 'de': replacement, 'fr': helpFrench},
          ),
        );
      }
      if (failure == 'wrong asset') {
        final manifest = jsonDecode(values[HelpGuideService.manifestAsset]!);
        manifest['guides']['de']['asset'] = '/private/secret';
        values[HelpGuideService.manifestAsset] = jsonEncode(manifest);
      }
      final bundle = HelpTestBundle(values);
      final guide = await HelpGuideService(bundle: bundle).load('de');
      expect(guide.language, 'en');
      expect(guide.fallback, HelpFallback.invalid);
      expect(bundle.reads, isNot(contains('/private/secret')));
    });
  }

  for (final failure in [
    'missing manifest',
    'bad manifest',
    'large manifest',
    'missing English',
    'bad English hash',
    'unsafe topic',
    'empty topic',
  ]) {
    test('$failure produces bounded help-unavailable failure', () async {
      final values = helpAssets();
      switch (failure) {
        case 'missing manifest':
          values.remove(HelpGuideService.manifestAsset);
        case 'bad manifest':
          values[HelpGuideService.manifestAsset] = '{}';
        case 'large manifest':
          values[HelpGuideService.manifestAsset] =
              ' ' * (HelpGuideService.maxManifestBytes + 1);
        case 'missing English':
          values.remove(HelpGuideService.assets['en']);
        case 'bad English hash':
          values[HelpGuideService.assets['en']!] = '$helpEnglish changed';
        case 'unsafe topic':
          values.addAll(
            helpAssets(
              guides: {
                'en': helpEnglish.replaceAll('backup-engine', '../private'),
              },
            ),
          );
        case 'empty topic':
          values.addAll(
            helpAssets(
              guides: {'en': '# Guide\n<a id="empty"></a>\n## Empty\n'},
            ),
          );
      }
      await expectLater(
        HelpGuideService(bundle: HelpTestBundle(values)).load('en'),
        throwsA(isA<HelpUnavailable>()),
      );
    });
  }

  test(
    'link policy allows known topics and exact repository HTTPS routes only',
    () async {
      final guide = await HelpGuideService(bundle: HelpTestBundle(helpAssets()))
          .load('en');
      expect(
        HelpGuideService.internalTopic('#backup-engine', guide),
        'backup-engine',
      );
      expect(HelpGuideService.internalTopic('#missing', guide), isNull);
      for (final href in [
        'javascript:alert(1)',
        'file:///private',
        'data:text/plain,secret',
        'http://github.com/CrispStrobe/CrispCloud/docs',
        'https://github.com.evil.test/CrispStrobe/CrispCloud/docs',
        'https://user@github.com/CrispStrobe/CrispCloud/docs',
        'https://github.com/other/repository',
        'https://github.com/CrispStrobe/CrispCloud/issues',
        'https://github.com/CrispStrobe/CrispCloud/blob/main/docs/../../../settings',
        '../guide.md',
      ]) {
        expect(HelpGuideService.externalLink(href), isNull, reason: href);
      }
      expect(
        HelpGuideService.externalLink(
          'https://github.com/CrispStrobe/CrispCloud/blob/main/docs/USER_GUIDE.md',
        ),
        isNotNull,
      );
    },
  );

  test('all existing UI locales have nonempty help controls and fallback explanations', () {
    for (final language in HelpGuideStrings.languages) {
      final strings = HelpGuideStrings.forLanguage(language);
      for (final key in HelpGuideStrings.keys) {
        expect(strings.text(key), isNotEmpty);
      }
      if (language != 'en') {
        expect(
          strings.text('title'),
          isNot(const HelpGuideStrings.forLanguage('en').text('title')),
        );
      }
    }
  });
}
