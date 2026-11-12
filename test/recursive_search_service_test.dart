import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/models/file_item.dart';
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

  test('oversized regex input is reported rather than silently treated as a non-match', () async {
    final cloud = WorkflowFakeClient()..put('/a.txt', utf8.encode('needle'));
    final result = await RecursiveSearchService().search(
      CloudOperationBackend(cloud, isCurrent: () => true),
      const FileSearchQuery(
        contentPattern: 'needle',
        contentRegex: true,
        maxContentBytes: 2,
      ),
      currentDirectory: '/',
    );
    expect(result.matches, isEmpty);
    expect(result.errors.single, contains('limit'));
  });

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

  test(
    'literal content reads beyond the bounded regex and document budget',
    () async {
      final cloud = WorkflowFakeClient()
        ..put('/large.txt', utf8.encode('${'x' * (128 * 1024)}needle'));
      final result = await RecursiveSearchService().search(
        CloudOperationBackend(cloud, isCurrent: () => true),
        const FileSearchQuery(contentPattern: 'needle', maxContentBytes: 2),
        currentDirectory: '/',
      );
      expect(result.errors, isEmpty);
      expect(result.matches.single.file.path, '/large.txt');
      expect(result.matches.single.snippet, endsWith('needle'));
    },
  );

  test('one oversized archive member reports its error and continues other members', () async {
    final cloud = WorkflowFakeClient()
      ..put(
        '/docs.zip',
        ZipEncoder().encode(
          Archive()
            ..addFile(ArchiveFile('large.txt', 10, '0123456789'.codeUnits))
            ..addFile(ArchiveFile('small.txt', 1, 'x'.codeUnits)),
        ),
      );
    final result = await RecursiveSearchService().search(
      CloudOperationBackend(cloud, isCurrent: () => true),
      const FileSearchQuery(
        namePattern: '*.txt',
        searchArchives: true,
        contentPattern: 'x',
        maxContentBytes: 2,
      ),
      currentDirectory: '/',
    );
    expect(result.errors.single, contains('/docs.zip!/large.txt'));
    expect(result.matches.single.archiveMember, 'small.txt');
  });

  test(
    'grouped archive evidence survives an outer-file hit and repeated members',
    () {
      final file = FileItem(
        name: 'docs.zip',
        path: '/docs.zip',
        isFolder: false,
      );
      final first = FileSearchMatch(
        file,
        archiveMember: 'a.txt',
      ).groupedFile(null);
      final repeat = FileSearchMatch(
        file,
        archiveMember: 'a.txt',
      ).groupedFile(first);
      final second = FileSearchMatch(
        file,
        archiveMember: 'b.txt',
      ).groupedFile(repeat);
      final outer = FileSearchMatch(file).groupedFile(second);
      expect(outer.path, '/docs.zip');
      expect(outer.metadata!['matchingArchiveMembers'], ['a.txt', 'b.txt']);
    },
  );

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

  test('Office search routes cloud files through referenced native note parts', () async {
    const word = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
    const office =
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
    const package =
        'http://schemas.openxmlformats.org/package/2006/relationships';
    final archive = Archive();
    for (final part in {
      '_rels/.rels':
          '<Relationships xmlns="$package">'
          '<Relationship Id="main" Type="$office/officeDocument" Target="content/body.xml"/>'
          '</Relationships>',
      'content/body.xml':
          '<w:document xmlns:w="$word"><w:body><w:p><w:r>'
          '<w:t>Body</w:t><w:footnoteReference w:id="7"/>'
          '</w:r></w:p></w:body></w:document>',
      'content/_rels/body.xml.rels':
          '<Relationships xmlns="$package">'
          '<Relationship Id="notes" Type="$office/footnotes" Target="../notes/native.xml"/>'
          '</Relationships>',
      'notes/native.xml':
          '<w:footnotes xmlns:w="$word"><w:footnote w:id="7">'
          '<w:p><w:r><w:t>Relocated searchable note</w:t></w:r></w:p>'
          '</w:footnote></w:footnotes>',
      'word/document.xml':
          '<document><text>Unrelated canonical text</text></document>',
    }.entries) {
      archive.addFile(ArchiveFile.bytes(part.key, utf8.encode(part.value)));
    }
    final cloud = WorkflowFakeClient()
      ..put('/native.docm', ZipEncoder().encode(archive));
    final result = await RecursiveSearchService().search(
      CloudOperationBackend(cloud, isCurrent: () => true),
      const FileSearchQuery(contentPattern: 'Relocated searchable note'),
      currentDirectory: '/',
    );
    expect(result.errors, isEmpty);
    expect(result.matches.single.file.path, '/native.docm');
    expect(
      result.matches.single.snippet,
      contains('Relocated searchable note'),
    );
  });

  test('Office extraction failures retain source paths and do not hide later matches', () async {
    List<int> document(String text) => ZipEncoder().encode(
      Archive()
        ..addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(text))),
    );
    final oversized = document(
      '<document><text>${'needle ' * 2000}</text></document>',
    );
    expect(oversized.length, lessThan(1024));
    final cloud = WorkflowFakeClient()
      ..put('/oversized.docx', oversized)
      ..put('/malformed.docx', document('<document>'))
      ..put(
        '/valid.docx',
        document('<document><text>needle survives</text></document>'),
      );
    final result = await RecursiveSearchService().search(
      CloudOperationBackend(cloud, isCurrent: () => true),
      const FileSearchQuery(contentPattern: 'needle', maxContentBytes: 1024),
      currentDirectory: '/',
    );
    expect(result.matches.single.file.path, '/valid.docx');
    expect(result.errors, hasLength(2));
    expect(
      result.errors,
      contains(
        predicate<String>(
          (error) =>
              error.contains('/oversized.docx') &&
              error.contains('content limit'),
        ),
      ),
    );
    expect(
      result.errors,
      contains(
        predicate<String>(
          (error) => error.contains('/malformed.docx') && error.contains('XML'),
        ),
      ),
    );
  });

  test(
    'archive dates, hidden ancestors, exclusions and depth follow the query',
    () async {
      final date = DateTime(2025, 4, 15, 12);
      final entries = Archive();
      for (final name in [
        'root.txt',
        'sub/visible.txt',
        'sub/deep/file.txt',
        '.hidden/secret.txt',
        'cache/skip.txt',
        'sub/cache/skip.txt',
      ]) {
        entries.addFile(
          ArchiveFile(name, 6, 'needle'.codeUnits)
            ..lastModTime = date.millisecondsSinceEpoch ~/ 1000,
        );
      }
      final cloud = WorkflowFakeClient()
        ..put('/docs.zip', ZipEncoder().encode(entries));
      final result = await RecursiveSearchService().search(
        CloudOperationBackend(cloud, isCurrent: () => true),
        FileSearchQuery(
          namePattern: '*.txt',
          searchArchives: true,
          includeHidden: false,
          excludeDirectories: 'cache',
          maxDepth: 1,
          modifiedAfter: DateTime(2025, 4, 14),
          modifiedBefore: DateTime(2025, 4, 16),
        ),
        currentDirectory: '/',
      );
      expect(result.errors, isEmpty);
      expect(result.matches.map((m) => m.archiveMember), [
        'root.txt',
        'sub/visible.txt',
      ]);
      final shallow = await RecursiveSearchService().search(
        CloudOperationBackend(cloud, isCurrent: () => true),
        const FileSearchQuery(
          namePattern: '*.txt',
          searchArchives: true,
          recursive: false,
        ),
        currentDirectory: '/',
      );
      expect(shallow.matches.map((m) => m.archiveMember), ['root.txt']);
    },
  );

  test('Office extraction is text regardless of the plain-file encoding, including archive members', () async {
    const phrase = 'Grüße 東京';
    final xml = utf8.encode('<document><text>$phrase</text></document>');
    final document = ZipEncoder().encode(
      Archive()..addFile(ArchiveFile('word/document.xml', xml.length, xml)),
    );
    final cloud = WorkflowFakeClient()
      ..put('/report.docx', document)
      ..put(
        '/bundle.zip',
        ZipEncoder().encode(
          Archive()..addFile(
            ArchiveFile('nested/report.docx', document.length, document),
          ),
        ),
      );
    for (final encoding in FileSearchQuery.contentEncodings) {
      final result = await RecursiveSearchService().search(
        CloudOperationBackend(cloud, isCurrent: () => true),
        FileSearchQuery(
          namePattern: '*.docx',
          contentPattern: phrase,
          searchArchives: true,
          contentEncoding: encoding,
        ),
        currentDirectory: '/',
      );
      expect(result.errors, isEmpty, reason: encoding);
      expect(
        result.matches.map((m) => m.file.path),
        unorderedEquals(['/report.docx', '/bundle.zip']),
        reason: encoding,
      );
      expect(result.matches.every((m) => m.snippet.contains(phrase)), isTrue);
    }
  });

  test('unknown saved content encodings are rejected before reading', () async {
    final cloud = WorkflowFakeClient();
    await expectLater(
      RecursiveSearchService().search(
        CloudOperationBackend(cloud, isCurrent: () => false),
        FileSearchQuery.fromJson({'contentEncoding': 'guess-a-code-page'}),
        currentDirectory: '/',
      ),
      throwsFormatException,
    );
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
