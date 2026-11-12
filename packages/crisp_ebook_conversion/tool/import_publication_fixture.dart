import 'dart:convert';
import 'dart:io';

import 'package:crisp_ebook/crisp_ebook.dart';
import 'package:crypto/crypto.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Iterable<EpubTocEntry> flatten(Iterable<EpubTocEntry> items) sync* {
  for (final item in items) {
    yield item;
    yield* flatten(item.children);
  }
}

void main(List<String> args) {
  require(
    args.length == 1,
    'usage: import_publication_fixture.dart OUTPUT_DIRECTORY',
  );
  final directory = Directory(args.single);
  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.publication.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  require(files.isNotEmpty, 'No actual normalized publications found');
  final results = <Map<String, dynamic>>[];
  for (final file in files) {
    final payload = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final document = EpubDocument.fromPublication(payload);
    final initialIssues = document.validate();
    require(
      !initialIssues.any((issue) => issue.isError),
      'Core import validation failed: $initialIssues',
    );
    final bytes = document.toBytes();
    final reopened = EpubDocument.open(bytes);
    final metadata = payload['metadata'] as Map;
    require(reopened.title == metadata['title'], 'Title changed');
    require(
      jsonEncode(reopened.authors) == jsonEncode(metadata['authors']),
      'Authors changed',
    );
    require(
      reopened.chapters.length == (payload['readingOrder'] as List).length,
      'Reading order changed',
    );
    final issues = reopened.validate();
    require(
      !issues.any((issue) => issue.isError),
      'Reopened core validation failed: $issues',
    );
    final first = flatten(
      reopened.toc,
    ).where((item) => item.label == 'First Chapter').first;
    require(
      flatten(first.children).any((item) => item.label == 'The Answer'),
      'Nested TOC hierarchy lost',
    );
    final prose = reopened.chapters
        .map((chapter) => reopened.readText(chapter.path))
        .join('\n');
    for (final phrase in [
      'First Chapter',
      'Second Chapter',
      'silver heron',
      'café',
      'Ωμέγα',
      '日本語',
      'forty-two',
    ]) {
      require(prose.contains(phrase), 'Missing $phrase');
    }
    require(
      RegExp(r'href="\d+\.xhtml#').hasMatch(prose),
      'Cross-chapter link lost',
    );
    require(
      reopened.resources.any((item) => item.mediaType == 'image/png'),
      'Image lost',
    );
    var comparedAssets = 0;
    for (final resource in (payload['resources'] as List).cast<Map>()) {
      if ([
        'application/xhtml+xml',
        'text/html',
      ].contains(resource['mediaType'])) {
        continue;
      }
      final original = base64Decode(resource['data'] as String);
      final actual = reopened.readBytes(resource['href'] as String);
      require(
        sha256.convert(original).toString() ==
            sha256.convert(actual).toString(),
        'Resource bytes changed: ${resource['href']}',
      );
      comparedAssets++;
    }
    final epubPath = file.path.replaceFirst(
      RegExp(r'\.publication\.json$'),
      '.imported.epub',
    );
    File(epubPath).writeAsBytesSync(bytes);
    final result = <String, dynamic>{
      'publication': file.path,
      'epub': epubPath,
      'epubSha256': sha256.convert(bytes).toString(),
      'bytes': bytes.length,
      'chapters': reopened.chapters.length,
      'resources': reopened.resources.length,
      'comparedNonXhtmlAssets': comparedAssets,
      'title': reopened.title,
      'authors': reopened.authors,
      'coreIssues': issues.map((item) => item.toString()).toList(),
    };
    results.add(result);
    stdout.writeln(jsonEncode(result));
  }
  File('${directory.path}/import-results.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(results)}\n',
  );
}
