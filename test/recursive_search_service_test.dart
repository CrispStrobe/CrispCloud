import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/models/file_search_query.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_selection_pattern.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/recursive_search_service.dart';
import 'package:crisp_cloud/services/saved_search_service.dart';

import 'support/workflow_fake_client.dart';

void main() {
  test('recurses with multi-mask excludes, directory pruning and full source paths', () async {
    final cloud = WorkflowFakeClient()
      ..put('/docs/a.txt', [1])
      ..put('/docs/nested/b.md', [2])
      ..put('/docs/nested/thumb.txt', [3])
      ..put('/docs/cache/c.txt', [4]);
    final backend = CloudOperationBackend(cloud, isCurrent: () => true);
    final matches = <String>[];
    final result = await RecursiveSearchService().search(
      backend,
      const FileSearchQuery(
        namePattern: '*.txt;*.md|thumb*',
        excludeDirectories: 'cache',
      ),
      currentDirectory: '/docs',
      onMatch: (match) => matches.add(match.file.path!),
    );
    expect(matches, unorderedEquals(['/docs/a.txt', '/docs/nested/b.md']));
    expect(result.errors, isEmpty);
  });

  test('depth zero includes direct files but no descendant matches', () async {
    final cloud = WorkflowFakeClient()
      ..put('/a.txt', [1])
      ..put('/sub/b.txt', [2]);
    final result = await RecursiveSearchService().search(
      CloudOperationBackend(cloud, isCurrent: () => true),
      const FileSearchQuery(namePattern: '*.txt', maxDepth: 0),
      currentDirectory: '/',
    );
    expect(result.matches.map((m) => m.file.path), ['/a.txt']);
  });

  test('content regex searches UTF-16 and honors case/negation', () async {
    final cloud = WorkflowFakeClient()
      ..put('/a.txt', [
        0xff,
        0xfe,
        for (final c in 'Alpha 123'.codeUnits) ...[c, 0],
      ])
      ..put('/b.txt', utf8.encode('Other text'));
    final backend = CloudOperationBackend(cloud, isCurrent: () => true);
    final result = await RecursiveSearchService().search(
      backend,
      const FileSearchQuery(
        namePattern: '*.txt',
        contentPattern: r'alpha\s+\d+',
        contentRegex: true,
      ),
      currentDirectory: '/',
    );
    expect(result.matches.single.file.path, '/a.txt');
    expect(result.matches.single.snippet, contains('Alpha 123'));
    final negative = await RecursiveSearchService().search(
      backend,
      const FileSearchQuery(
        contentPattern: 'Alpha',
        contentCaseSensitive: true,
        contentNegated: true,
      ),
      currentDirectory: '/',
    );
    expect(negative.matches.single.file.path, '/b.txt');
  });

  test('invalid regex is rejected before reading a source', () async {
    final cloud = WorkflowFakeClient();
    await expectLater(
      RecursiveSearchService().search(
        CloudOperationBackend(cloud, isCurrent: () => false),
        const FileSearchQuery(
          namePattern: '[',
          nameMode: FilePatternMode.regex,
        ),
        currentDirectory: '/',
      ),
      throwsFormatException,
    );
  });

  test(
    'cancellation retains progressive matches and stops further traversal',
    () async {
      final cloud = WorkflowFakeClient()
        ..put('/a', [1])
        ..put('/b', [2]);
      var cancelled = false;
      final result = await RecursiveSearchService().search(
        CloudOperationBackend(cloud, isCurrent: () => true),
        const FileSearchQuery(),
        currentDirectory: '/',
        isCancelled: () => cancelled,
        onMatch: (_) {
          cancelled = true;
        },
      );
      expect(result.cancelled, isTrue);
      expect(result.matches, hasLength(1));
      expect(result.scanned, 1);
    },
  );

  test(
    'oversized content is reported rather than silently treated as a non-match',
    () async {
      final cloud = WorkflowFakeClient()..put('/a.txt', utf8.encode('needle'));
      final result = await RecursiveSearchService().search(
        CloudOperationBackend(cloud, isCurrent: () => true),
        const FileSearchQuery(contentPattern: 'needle', maxContentBytes: 2),
        currentDirectory: '/',
      );
      expect(result.matches, isEmpty);
      expect(result.errors.single, contains('limit'));
    },
  );

  test('archive content hit remains bound to real containing file', () async {
    final bytes = ZipEncoder().encode(
      Archive()..addFile(ArchiveFile('nested/a.txt', 6, 'needle'.codeUnits)),
    );
    final cloud = WorkflowFakeClient()..put('/docs.zip', bytes);
    final result = await RecursiveSearchService().search(
      CloudOperationBackend(cloud, isCurrent: () => true),
      const FileSearchQuery(
        namePattern: '*.txt',
        searchArchives: true,
        contentPattern: 'needle',
      ),
      currentDirectory: '/',
    );
    expect(result.errors, isEmpty);
    expect(result.matches.single.file.path, '/docs.zip');
    expect(result.matches.single.archiveMember, 'nested/a.txt');
  });

  test('Office document content is searched after bounded XML extraction', () async {
    const xml =
        '<w:document xmlns:w="urn:word"><w:body><w:p><w:r><w:t>needle in document</w:t></w:r></w:p></w:body></w:document>';
    final archive = Archive()
      ..addFile(ArchiveFile('word/document.xml', xml.length, xml.codeUnits));
    final cloud = WorkflowFakeClient()
      ..put('/report.docx', ZipEncoder().encode(archive));
    final result = await RecursiveSearchService().search(
      CloudOperationBackend(cloud, isCurrent: () => true),
      const FileSearchQuery(contentPattern: 'needle in document'),
      currentDirectory: '/',
    );
    expect(result.errors, isEmpty);
    expect(result.matches.single.file.path, '/report.docx');
  });

  test('native directories use the same recursive search semantics', () async {
    final temp = await Directory.systemTemp.createTemp('search-local-');
    addTearDown(() => temp.delete(recursive: true));
    await Directory('${temp.path}/nested').create();
    await File('${temp.path}/nested/a.txt').writeAsString('needle');
    final result = await RecursiveSearchService().search(
      LocalOperationBackend(LocalFileService(), isCurrent: () => true),
      const FileSearchQuery(namePattern: '*.txt', contentPattern: 'needle'),
      currentDirectory: temp.path,
    );
    expect(result.errors, isEmpty);
    expect(result.matches.single.file.path, '${temp.path}/nested/a.txt');
  });

  test(
    'saved query roundtrip preserves semantics and yields identical results',
    () async {
      SharedPreferences.setMockInitialValues({});
      const query = FileSearchQuery(
        namePattern: r'\.txt$',
        nameMode: FilePatternMode.regex,
        caseSensitive: true,
        roots: ['/scope'],
        recursive: true,
        maxDepth: 3,
        includeFolders: false,
        includeHidden: false,
        excludeDirectories: 'cache',
        contentPattern: 'needle',
        contentRegex: true,
        contentCaseSensitive: true,
        contentEncoding: 'utf8',
        searchArchives: true,
        minSize: 2,
        maxSize: 100,
      );
      final service = SavedSearchService();
      await service.save(
        SavedSearch(
          name: 'Exact semantics',
          query: 'needle',
          createdAt: DateTime.utc(2026),
          settings: query,
        ),
      );
      final loaded = (await service.getAll()).single;
      expect(loaded.settings!.toJson(), query.toJson());
      final cloud = WorkflowFakeClient()
        ..put('/scope/a.txt', utf8.encode('needle'))
        ..put('/scope/cache/b.txt', utf8.encode('needle'));
      final source = CloudOperationBackend(cloud, isCurrent: () => true);
      final before = await RecursiveSearchService().search(
        source,
        query,
        currentDirectory: '/',
      );
      final after = await RecursiveSearchService().search(
        source,
        loaded.settings!,
        currentDirectory: '/elsewhere',
      );
      expect(
        after.matches.map((m) => m.file.path),
        before.matches.map((m) => m.file.path),
      );
      expect(after.matches.single.file.path, '/scope/a.txt');
    },
  );
}
