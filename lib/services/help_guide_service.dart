import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

enum HelpFallback { unsupportedLanguage, missing, outdated, invalid }

class HelpUnavailable implements Exception {
  const HelpUnavailable();
}

class HelpTopic {
  const HelpTopic(this.id, this.title, this.markdown);
  final String id;
  final String title;
  final String markdown;
}

class HelpGuide {
  HelpGuide({
    required this.requestedLanguage,
    required this.language,
    required this.title,
    required List<HelpTopic> topics,
    this.fallback,
  }) : topics = List.unmodifiable(topics);

  final String requestedLanguage;
  final String language;
  final String title;
  final List<HelpTopic> topics;
  final HelpFallback? fallback;

  HelpTopic? topic(String id) {
    for (final topic in topics) {
      if (topic.id == id) return topic;
    }
    return null;
  }
}

/// Offline, bundled guides. A translation is used only if both its bytes and
/// its declared English source revision match the bundle. No network fallback.
class HelpGuideService {
  HelpGuideService({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;
  final AssetBundle _bundle;

  static const manifestAsset = 'docs/help/manifest.json';
  static const assets = {
    'en': 'docs/USER_GUIDE.md',
    'de': 'docs/help/USER_GUIDE.de.md',
    'fr': 'docs/help/USER_GUIDE.fr.md',
  };
  static const maxGuideBytes = 256 * 1024;
  static const maxManifestBytes = 64 * 1024;
  static const maxTopics = 64;
  static final _topicId = RegExp(r'^[a-z][a-z0-9-]{0,79}$');
  static final _digest = RegExp(r'^[0-9a-f]{64}$');

  Future<String> _read(String asset, int limit) async {
    final data = await _bundle.load(asset);
    if (data.lengthInBytes > limit) throw const HelpUnavailable();
    return utf8.decode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  Future<HelpGuide> load(String language) async {
    final requested = language.toLowerCase().split(RegExp('[-_]')).first;
    late Map<String, dynamic> entries;
    late String sourceHash;
    late HelpGuide english;
    try {
      final manifest = jsonDecode(await _read(manifestAsset, maxManifestBytes));
      if (manifest is! Map<String, dynamic> ||
          manifest['version'] != 1 ||
          manifest['sourceLanguage'] != 'en' ||
          manifest['guides'] is! Map<String, dynamic>) {
        throw const HelpUnavailable();
      }
      entries = manifest['guides'] as Map<String, dynamic>;
      if (entries.length > assets.length ||
          entries.keys.any((key) => !assets.containsKey(key))) {
        throw const HelpUnavailable();
      }
      final entry = _entry(entries['en'], 'en');
      sourceHash = entry['sha256']!;
      english = _parse(await _readVerified('en', sourceHash), 'en', requested);
    } catch (_) {
      throw const HelpUnavailable();
    }
    if (requested == 'en') return english;
    HelpGuide fallback(HelpFallback reason) => HelpGuide(
      requestedLanguage: requested,
      language: 'en',
      title: english.title,
      topics: english.topics,
      fallback: reason,
    );
    if (!assets.containsKey(requested)) {
      return fallback(HelpFallback.unsupportedLanguage);
    }
    if (entries[requested] == null) return fallback(HelpFallback.missing);
    try {
      final entry = _entry(entries[requested], requested);
      if (entry['sourceSha256'] != sourceHash) {
        return fallback(HelpFallback.outdated);
      }
      final translated = _parse(
        await _readVerified(requested, entry['sha256']!),
        requested,
        requested,
      );
      if (translated.topics.map((topic) => topic.id).join('\n') !=
          english.topics.map((topic) => topic.id).join('\n')) {
        return fallback(HelpFallback.invalid);
      }
      return translated;
    } catch (_) {
      return fallback(HelpFallback.invalid);
    }
  }

  Map<String, String> _entry(Object? value, String language) {
    if (value is! Map<String, dynamic> ||
        value['asset'] != assets[language] ||
        value['sha256'] is! String ||
        !_digest.hasMatch(value['sha256'] as String) ||
        (language != 'en' &&
            (value['sourceSha256'] is! String ||
                !_digest.hasMatch(value['sourceSha256'] as String)))) {
      throw const HelpUnavailable();
    }
    return {
      for (final key in ['asset', 'sha256', 'sourceSha256'])
        if (value[key] is String) key: value[key] as String,
    };
  }

  Future<String> _readVerified(String language, String expected) async {
    final markdown = await _read(assets[language]!, maxGuideBytes);
    if (sha256.convert(utf8.encode(markdown)).toString() != expected) {
      throw const HelpUnavailable();
    }
    return markdown;
  }

  HelpGuide _parse(String markdown, String language, String requested) {
    final title = RegExp(
      r'^# ([^\r\n]+)',
      multiLine: true,
    ).firstMatch(markdown)?.group(1);
    final anchors = RegExp(
      r'^<a id="([^"]+)"></a>\r?\n## ([^\r\n]+)\r?\n',
      multiLine: true,
    ).allMatches(markdown).toList();
    if (title == null ||
        title.length > 160 ||
        anchors.isEmpty ||
        anchors.length > maxTopics) {
      throw const HelpUnavailable();
    }
    final ids = <String>{};
    final topics = <HelpTopic>[];
    for (var index = 0; index < anchors.length; index++) {
      final match = anchors[index];
      final id = match.group(1)!;
      final heading = match.group(2)!;
      if (!_topicId.hasMatch(id) || !ids.add(id) || heading.length > 160) {
        throw const HelpUnavailable();
      }
      final body = markdown
          .substring(
            match.end,
            index + 1 < anchors.length
                ? anchors[index + 1].start
                : markdown.length,
          )
          .trim();
      if (body.isEmpty || RegExp(r'^## ', multiLine: true).hasMatch(body)) {
        throw const HelpUnavailable();
      }
      topics.add(HelpTopic(id, heading, body));
    }
    return HelpGuide(
      requestedLanguage: requested,
      language: language,
      title: title,
      topics: topics,
    );
  }

  /// Only stable in-bundle topics and explicitly clicked HTTPS documentation
  /// links are eligible. Relative asset/file/script links are never launched.
  static String? internalTopic(String href, HelpGuide guide) {
    if (!href.startsWith('#')) return null;
    final id = href.substring(1);
    return guide.topic(id) == null ? null : id;
  }

  static Uri? externalLink(String href) {
    final uri = Uri.tryParse(href);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !RegExp(r'^/CrispStrobe/CrispCloud/blob/[^/]+/docs/')
            .hasMatch(uri.path) ||
        uri.pathSegments.any(
          (segment) => segment == '..' || segment.contains('/'),
        )) {
      return null;
    }
    return uri;
  }
}
