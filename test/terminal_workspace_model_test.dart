import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/models/terminal_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = 'ws-00000000-0000-4000-8000-000000000000';
  const digest =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  const storage = StorageReference(
    kind: 'remote',
    provider: 'test',
    accountKey: 'account',
  );

  TerminalWorkspace workspace() => TerminalWorkspace(
    id: id,
    title: 'Workspace',
    storage: storage,
    remoteRoot: '/remote',
    remoteRootFingerprint: TerminalWorkspaceFingerprint(
      isDirectory: true,
      objectId: 'dir',
    ),
    directoryPath: '/local/files',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026, 2),
    revision: 3,
    status: TerminalWorkspaceStatus.ready,
    entries: [
      TerminalWorkspaceEntry(
        relativePath: 'file.txt',
        remotePath: '/remote/file.txt',
        fingerprint: TerminalWorkspaceFingerprint(
          isDirectory: false,
          objectId: 'object',
          version: 'rev',
          size: 4,
        ),
        status: TerminalWorkspaceEntryStatus.ready,
        originalDigest: digest,
        originalSize: 4,
      ),
    ],
  );

  group('remote fingerprints', () {
    test('uses the transfer backend revision precedence and preserves alternate tags', () {
      final fingerprint = TerminalWorkspaceFingerprint.fromFile(
        FileItem(
          name: 'file',
          isFolder: false,
          metadata: {
            'version': 'preferred',
            'etag': 'alternate',
            'cTag': 'content-tag',
          },
        ),
      );
      expect(fingerprint.version, 'preferred');
      expect(fingerprint.metadata['etag'], 'alternate');
      expect(fingerprint.metadata['cTag'], 'content-tag');
    });
    test(
      'extracts stable identity and revision fields but never credentials',
      () {
        final value = TerminalWorkspaceFingerprint.fromFile(
          FileItem(
            name: 'file',
            path: '/file',
            isFolder: false,
            size: 10,
            updatedAt: DateTime.utc(2026),
            metadata: {
              'id': 'id-from-provider',
              'etag': 'revision',
              'password': 'secret',
              'signedUrl': 'https://private.example/token',
              'metadata': {'lastModified': 'then', 'token': 'secret'},
            },
          ),
        );
        expect(value.objectId, 'id-from-provider');
        expect(value.version, 'revision');
        expect(value.metadata['lastModified'], 'then');
        expect(
          value.metadata['modified'],
          DateTime.utc(2026).toIso8601String(),
        );
        expect(value.toJson().toString(), isNot(contains('secret')));
        expect(value.toJson().toString(), isNot(contains('private.example')));
        expect(
          value.matches(TerminalWorkspaceFingerprint.fromJson(value.toJson())),
          isTrue,
        );
      },
    );

    test(
      'compares file identity, revision, size, type and metadata exactly',
      () {
        final base = TerminalWorkspaceFingerprint(
          isDirectory: false,
          objectId: 'id',
          version: 'v',
          size: 1,
          metadata: {'updatedAt': 'date'},
        );
        for (final altered in [
          {...base.toJson(), 'objectId': 'other'},
          {...base.toJson(), 'version': 'new'},
          {...base.toJson(), 'size': 2},
          {...base.toJson(), 'directory': true},
          {
            ...base.toJson(),
            'metadata': {'updatedAt': 'new'},
          },
          {...base.toJson(), 'metadata': <String, String>{}},
        ]) {
          expect(
            base.matches(TerminalWorkspaceFingerprint.fromJson(altered)),
            isFalse,
          );
        }
        expect(base.sameDirectory(base), isFalse);
      },
    );

    test(
      'directory anchors compare identity while allowing children to change',
      () {
        final before = TerminalWorkspaceFingerprint.fromFile(
          FileItem(
            name: 'dir',
            uuid: 'same-dir',
            isFolder: true,
            size: 500,
            metadata: {'version': 'old'},
          ),
        );
        final after = TerminalWorkspaceFingerprint.fromFile(
          FileItem(
            name: 'dir',
            uuid: 'same-dir',
            isFolder: true,
            size: 600,
            metadata: {'version': 'new'},
          ),
        );
        expect(before.size, isNull);
        expect(before.sameDirectory(after), isTrue);
        expect(before.matches(after), isFalse);
        expect(
          before.sameDirectory(
            TerminalWorkspaceFingerprint(
              isDirectory: true,
              objectId: 'new-dir',
            ),
          ),
          isFalse,
        );
      },
    );

    test('invalid lengths, identities and malformed metadata are rejected', () {
      for (final json in [
        {'directory': 'yes', 'metadata': {}},
        {'directory': false, 'size': -1, 'metadata': {}},
        {'directory': false, 'size': 1.1, 'metadata': {}},
        {'directory': false, 'objectId': 3, 'metadata': {}},
        {'directory': false, 'version': [], 'metadata': {}},
      ]) {
        expect(
          () => TerminalWorkspaceFingerprint.fromJson(
            Map<String, dynamic>.from(json),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => TerminalWorkspaceFingerprint(
          isDirectory: false,
          metadata: {'key': 'value'},
        ).metadata['key'] = 'changed',
        throwsUnsupportedError,
      );
    });
  });

  group('persistent workspace models', () {
    test(
      'round-trips the complete manifest while deriving local path externally',
      () {
        final original = workspace();
        final loaded = TerminalWorkspace.fromJson(
          original.toJson(),
          directoryPath: '/new/container/files',
        );
        expect(loaded.toJson(), original.toJson());
        expect(loaded.directoryPath, '/new/container/files');
        expect(original.toJson().containsKey('directoryPath'), isFalse);
        expect(loaded.entries.single.fingerprint.objectId, 'object');
        expect(() => loaded.entries.clear(), throwsUnsupportedError);
        expect(() => loaded.warnings.clear(), throwsUnsupportedError);
      },
    );

    test('copyWith preserves anchors and supports clearing errors and pending receipts', () {
      final original = workspace();
      final changed = original.copyWith(
        revision: 4,
        updatedAt: DateTime.utc(2027),
        status: TerminalWorkspaceStatus.interrupted,
        error: 'interrupted',
        warnings: ['retained backup'],
      );
      expect(changed.storage, original.storage);
      expect(changed.remoteRoot, original.remoteRoot);
      expect(changed.directoryPath, original.directoryPath);
      expect(changed.error, 'interrupted');
      expect(changed.warnings, ['retained backup']);
      expect(changed.copyWith(clearError: true).error, isNull);
      final entry = original.entries.single.copyWith(
        pendingUpload: {'phase': 'uploading'},
      );
      expect(entry.pendingUpload!['phase'], 'uploading');
      expect(
        () => entry.pendingUpload!['phase'] = 'tampered',
        throwsUnsupportedError,
      );
      expect(entry.copyWith(clearPendingUpload: true).pendingUpload, isNull);
      expect(entry.copyWith(originalSize: 9).originalSize, 9);
      expect(
        TerminalWorkspaceEntry.fromJson(entry.toJson()).toJson(),
        entry.toJson(),
      );
      final warningsLoaded = TerminalWorkspace.fromJson(
        changed.toJson(),
        directoryPath: '/files',
      );
      expect(warningsLoaded.warnings, ['retained backup']);
    });

    test('rejects mismatched paths, duplicate case aliases and incomplete baselines', () {
      final cases = <void Function(Map<String, dynamic>)>[
        (json) => json['schema'] = 2,
        (json) => json['revision'] = -1,
        (json) => json['id'] = '../../outside',
        (json) => json['remoteRoot'] = '/remote/../outside',
        (json) => (json['entries'] as List).add(<String, dynamic>{
          ...((json['entries'] as List).single as Map),
          'relativePath': 'FILE.txt',
        }),
        (json) => ((json['entries'] as List).single as Map)['remotePath'] =
            '/outside/file.txt',
        (json) => ((json['entries'] as List).single as Map)['relativePath'] =
            '../file.txt',
        (json) => ((json['entries'] as List).single as Map)['originalDigest'] =
            'invalid',
        (json) =>
            ((json['entries'] as List).single as Map)['originalSize'] = -1,
        (json) =>
            ((json['entries'] as List).single as Map).remove('originalSize'),
        (json) {
          ((json['entries'] as List).single as Map).remove('originalDigest');
        },
      ];
      for (final mutate in cases) {
        final json = workspace().toJson();
        mutate(json);
        expect(
          () => TerminalWorkspace.fromJson(json, directoryPath: '/files'),
          throwsFormatException,
        );
      }
    });

    test('pending staging and new upload receipts legitimately have no original digest', () {
      final original = workspace();
      final pending = TerminalWorkspaceEntry(
        relativePath: 'new',
        remotePath: '/remote/new',
        fingerprint: TerminalWorkspaceFingerprint(isDirectory: false),
      );
      final receipt = pending.copyWith(
        status: TerminalWorkspaceEntryStatus.ready,
        pendingUpload: {'phase': 'prepared', 'digest': digest, 'length': 4},
      );
      for (final entry in [pending, receipt]) {
        final value = original.copyWith(entries: [entry]);
        expect(
          TerminalWorkspace.fromJson(
            value.toJson(),
            directoryPath: '/files',
          ).entries.single.originalDigest,
          isNull,
        );
      }
    });

    test(
      'results and review tokens expose only safe regular-file upload choices',
      () {
        TerminalWorkspaceChange change(
          TerminalWorkspaceChangeKind kind, {
          bool directory = false,
          String? content = digest,
        }) => TerminalWorkspaceChange(
          workspaceId: id,
          manifestRevision: 3,
          relativePath: 'file.txt',
          remotePath: '/remote/file.txt',
          kind: kind,
          isDirectory: directory,
          digest: content,
          size: 4,
        );
        expect(change(TerminalWorkspaceChangeKind.added).canUpload, isTrue);
        expect(change(TerminalWorkspaceChangeKind.modified).canUpload, isTrue);
        expect(change(TerminalWorkspaceChangeKind.deleted).canUpload, isFalse);
        expect(change(TerminalWorkspaceChangeKind.unsafe).canUpload, isFalse);
        expect(
          change(TerminalWorkspaceChangeKind.added, directory: true).canUpload,
          isFalse,
        );
        expect(
          change(TerminalWorkspaceChangeKind.modified, content: null).canUpload,
          isFalse,
        );
        final result = TerminalWorkspaceUploadResult(
          workspace: workspace(),
          uploadedPaths: ['file.txt'],
          skippedPaths: ['removed'],
          failures: {'other': 'conflict'},
        );
        expect(result.succeeded, isFalse);
        expect(() => result.failures.clear(), throwsUnsupportedError);
        expect(() => result.uploadedPaths.clear(), throwsUnsupportedError);
        expect(() => result.skippedPaths.clear(), throwsUnsupportedError);
        expect(
          TerminalWorkspaceUploadResult(
            workspace: workspace(),
            uploadedPaths: [],
            skippedPaths: [],
            failures: {},
          ).succeeded,
          isTrue,
        );
        expect(
          const TerminalWorkspaceException(
            'Failure',
            workspaceId: id,
          ).toString(),
          'Failure',
        );
      },
    );
  });

  group('untrusted path validation', () {
    test('identifiers must be opaque UUID workspace identifiers', () {
      validateTerminalWorkspaceId(id);
      for (final invalid in [
        '',
        '../escape',
        'ws-${'-' * 36}',
        'ws-00000000-0000-0000-0000-000000000000/elsewhere',
      ]) {
        expect(
          () => validateTerminalWorkspaceId(invalid),
          throwsFormatException,
        );
      }
    });

    test(
      'rejects traversal, aliases, Windows paths, controls and empty segments',
      () {
        for (final invalid in [
          '',
          '.',
          '..',
          '../file',
          '/file',
          'folder/../file',
          'folder//file',
          'folder/./file',
          'folder/',
          r'folder\file',
          r'C:\file',
          'file:stream',
          'nul\u0000file',
          'newline\nfile',
        ]) {
          expect(
            () => validateTerminalWorkspaceRelativePath(invalid),
            throwsFormatException,
            reason: invalid,
          );
        }
        for (final valid in [
          'file',
          'folder/file',
          '.hidden',
          '-option',
          'space ; \$(touch no).txt',
          '日本語.txt',
        ]) {
          validateTerminalWorkspaceRelativePath(valid);
        }
      },
    );

    test('requires normalized absolute cloud roots', () {
      for (final valid in ['/', '/cloud', '/cloud/folder']) {
        validateTerminalWorkspaceRemoteRoot(valid);
      }
      for (final invalid in [
        '',
        '.',
        'cloud',
        '/cloud/../other',
        '/cloud/',
        '/cloud//folder',
        '/cloud\\folder',
        '/nul\u0000',
      ]) {
        expect(
          () => validateTerminalWorkspaceRemoteRoot(invalid),
          throwsFormatException,
          reason: invalid,
        );
      }
    });
  });
}
