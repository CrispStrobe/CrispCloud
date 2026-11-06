import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/native_metadata.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// These are real Win32 handle tests. They belong to the Windows CI gate and
// never substitute mocks for unavailable native functionality on Linux/macOS.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Windows native metadata', () {
    late Directory root;
    late LocalOperationBackend backend;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('crisp-win-metadata-');
      backend = LocalOperationBackend(
        LocalFileService(),
        isCurrent: () => true,
      );
    });
    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('the Windows implementation is present, with no POSIX fallback', () {
      expect(supportsNativeMetadata, isTrue);
      expect(backend.capabilities.ownership, isTrue);
      expect(backend.capabilities.accessControlLists, isTrue);
      expect(backend.capabilities.windowsAttributes, isTrue);
      expect(backend.capabilities.setCreatedTime, isTrue);
      expect(backend.capabilities.permissions, isFalse);
      expect(backend.capabilities.extendedAttributes, isFalse);
    });

    test('metadata handles support file paths longer than MAX_PATH', () async {
      final directory = await Directory(
        p.join(root.path, 'long-${'a' * 120}', 'long-${'b' * 120}'),
      ).create(recursive: true);
      final file = await File(p.join(directory.path, 'long-file.txt'))
          .writeAsString('long path');
      expect(file.path.length, greaterThan(260));
      addTearDown(
        () => backend.writeMetadata(
          file.path,
          const TransferMetadata(
            windowsAttributes: 0,
            windowsAttributesMask: 2,
          ),
        ),
      );
      await backend.writeMetadata(
        file.path,
        const TransferMetadata(windowsAttributes: 2, windowsAttributesMask: 2),
      );
      final metadata = await backend.readMetadataFields(
        file.path,
        permissions: false,
        modified: false,
        accessed: false,
        created: false,
        ownership: false,
        extendedAttributes: false,
        acl: false,
      );
      expect(metadata.windowsAttributes! & 2, 2);
      expect(await file.readAsString(), 'long path');
    });

    test(
      'actual owner and group SIDs match independent Windows security reads',
      () async {
        final file = await File(p.join(root.path, 'owner.txt'))
            .writeAsString('owner data');
        final native = await backend.readMetadata(file.path);
        final external = await _inspect(file.path);
        expect(native.owner, external['owner']);
        expect(native.group, external['group']);
        expect(native.acl, 'windows-sddl-v1:${external['dacl']}');
        await backend.writeMetadata(
          file.path,
          TransferMetadata(owner: native.owner, group: native.group),
        );
        final after = await _inspect(file.path);
        expect(after['owner'], external['owner']);
        expect(after['group'], external['group']);
        expect(after['dacl'], external['dacl']);
        expect(await file.readAsString(), 'owner data');
      },
    );

    test('a real streamed copy preserves Windows metadata after content verification', () async {
      final source = await File(p.join(root.path, 'source.txt'))
          .writeAsString('verified copy');
      final destination = await Directory(p.join(root.path, 'destination'))
          .create();
      final target = p.join(destination.path, 'source.txt');
      addTearDown(() async {
        for (final path in [source.path, target]) {
          if (await File(path).exists()) {
            await backend.writeMetadata(
              path,
              const TransferMetadata(
                windowsAttributes: 0,
                windowsAttributesMask: 0x27,
              ),
            );
          }
        }
      });
      await backend.writeMetadata(
        source.path,
        const TransferMetadata(
          windowsAttributes: 0x23,
          windowsAttributesMask: 0x27,
        ),
      );
      final plan = await const FileOperationService().prepare(
        files: [(await backend.stat(source.path))!],
        source: backend,
        destination: backend,
        targetDirectory: destination.path,
        options: const FileOperationOptions(
          copyMethod: FileCopyMethod.stream,
          verifyContents: true,
          preserveOwnership: true,
          preserveAcl: true,
          preserveWindowsAttributes: true,
        ),
      );
      expect(plan.errors, isEmpty);
      await const FileOperationService().execute(
        plan,
        control: FileOperationControl(),
      );
      expect(
        plan.entries.single.outcome,
        FileOperationOutcome.copied,
        reason: plan.entries.single.message,
      );
      final from = await _inspect(source.path);
      final to = await _inspect(target);
      expect(to['owner'], from['owner']);
      expect(to['group'], from['group']);
      expect((to['attributes'] as int) & 0x27, 0x23);
      expect(await File(target).readAsString(), 'verified copy');
    });

    test('an explicit null DACL is not confused with an empty ACL', () async {
      final file = await File(p.join(root.path, 'null-acl.txt'))
          .writeAsString('public fixture');
      final before = await backend.readMetadata(file.path);
      addTearDown(
        () =>
            backend.writeMetadata(file.path, TransferMetadata(acl: before.acl)),
      );
      await backend.writeMetadata(
        file.path,
        const TransferMetadata(acl: 'windows-sddl-v1:D:PNO_ACCESS_CONTROL'),
      );
      final native = await backend.readMetadataFields(
        file.path,
        permissions: false,
        modified: false,
        accessed: false,
        created: false,
        ownership: false,
        extendedAttributes: false,
        windowsAttributes: false,
      );
      expect(native.acl, 'windows-sddl-v1:D:PNO_ACCESS_CONTROL');
      expect(await file.readAsString(), 'public fixture');
    });

    for (final autoInherited in [false, true]) {
      test('DACL protection and native ACEs survive write and independent read'
          '${autoInherited ? ' with auto-inherited ACEs' : ''}', () async {
        final file = await File(p.join(root.path, 'acl.txt'))
            .writeAsString('acl data');
        if (autoInherited) {
          await _enableAutomaticInheritance(file.path);
        }
        final before = await backend.readMetadata(file.path);
        final original = await _inspect(file.path);
        expect(before.acl, 'windows-sddl-v1:${original['dacl']}');
        if (autoInherited) {
          expect(original['dacl'], contains('AI'));
          expect(
            (original['rules'] as List).where(
              (dynamic rule) => (rule['flags'] as int) & 0x10 != 0,
            ),
            isNotEmpty,
          );
        }
        addTearDown(
          () => backend.writeMetadata(
            file.path,
            TransferMetadata(acl: before.acl),
          ),
        );
        final dacl = 'D:P(A;;FA;;;${before.owner})(A;;FR;;;WD)';
        await backend.writeMetadata(
          file.path,
          TransferMetadata(acl: 'windows-sddl-v1:$dacl'),
        );
        final external = await _inspect(file.path);
        expect(external['protected'], isTrue);
        expect(
          (external['rules'] as List).where(
            (dynamic rule) =>
                rule['sid'] == before.owner &&
                rule['type'] == 'AccessAllowed' &&
                rule['rights'] == 0x1f01ff,
          ),
          isNotEmpty,
        );
        expect(external['dacl'], contains('(A;;FR;;;WD)'));
        expect(external['owner'], before.owner);
        expect(external['group'], before.group);
        expect(await file.readAsString(), 'acl data');
        final read = await backend.readMetadataFields(
          file.path,
          permissions: false,
          modified: false,
          accessed: false,
          created: false,
          ownership: false,
          extendedAttributes: false,
          windowsAttributes: false,
        );
        expect(read.acl, 'windows-sddl-v1:${external['dacl']}');
        expect(read.owner, isNull);
        expect(read.created, isNull);
        expect(read.windowsAttributes, isNull);
        await backend.writeMetadata(
          file.path,
          TransferMetadata(acl: before.acl),
        );
        final restored = await _inspect(file.path);
        expect(restored['protected'], original['protected']);
        expect(restored['dacl'], original['dacl']);
      });
    }

    for (final autoInherited in [false, true]) {
      test('a directory ACL edit does not rewrite existing descendant ACLs'
          '${autoInherited ? ' with auto-inherited ACEs' : ''}', () async {
        final directory = await Directory(p.join(root.path, 'directory'))
            .create();
        if (autoInherited) {
          await _enableAutomaticInheritance(directory.path);
        }
        final child = await File(p.join(directory.path, 'child.txt'))
            .writeAsString('child data');
        final before = await backend.readMetadata(directory.path);
        final original = await _inspect(directory.path);
        if (autoInherited) expect(original['dacl'], contains('AI'));
        final childBefore = await _inspect(child.path);
        final nativeChildBefore = await backend.readMetadata(child.path);
        addTearDown(
          () => backend.writeMetadata(
            directory.path,
            TransferMetadata(acl: before.acl),
          ),
        );
        final dacl =
            'D:P${autoInherited ? 'AI' : ''}'
            '(A;OICI;FA;;;${before.owner})(A;OICI;FR;;;WD)';
        await backend.writeMetadata(
          directory.path,
          TransferMetadata(acl: 'windows-sddl-v1:$dacl'),
        );
        expect(
          (await _inspect(directory.path))['dacl'],
          contains('(A;OICI;FR;;;WD)'),
        );
        final childAfter = await _inspect(child.path);
        expect(
          childAfter['dacl'],
          childBefore['dacl'],
          reason:
              'Raw child descriptor must retain its ACE order, inherited '
              'flags, and DACL protection. Before: $childBefore; '
              'after: $childAfter',
        );
        expect(
          (await backend.readMetadata(child.path)).acl,
          nativeChildBefore.acl,
          reason: 'The handle-based reader must also retain the child ACL.',
        );
        if (autoInherited) {
          expect((await _inspect(directory.path))['dacl'], contains('AI'));
        }
        await backend.writeMetadata(
          directory.path,
          TransferMetadata(acl: before.acl),
        );
        expect((await _inspect(directory.path))['dacl'], original['dacl']);
        expect((await _inspect(child.path))['dacl'], childBefore['dacl']);
        expect(await child.readAsString(), 'child data');
      });
    }

    test('masked DOS attributes preserve unrelated native bits on files and directories', () async {
      final file = await File(p.join(root.path, 'attributes.txt'))
          .writeAsString('attributes');
      final directory = await Directory(
        p.join(root.path, 'attributes-directory'),
      ).create();
      for (final path in [file.path, directory.path]) {
        await _powershell(path, r'''
$item = Get-Item -Force -LiteralPath $env:CRISP_METADATA_TEST_PATH
$item.Attributes = $item.Attributes -bor [IO.FileAttributes]::NotContentIndexed
''');
        final before = (await _inspect(path))['attributes'] as int;
        addTearDown(
          () => backend.writeMetadata(
            path,
            const TransferMetadata(
              windowsAttributes: 0,
              windowsAttributesMask: 0x27,
            ),
          ),
        );
        await backend.writeMetadata(
          path,
          const TransferMetadata(
            windowsAttributes: 0x03,
            windowsAttributesMask: 0x03,
          ),
        );
        final after = (await _inspect(path))['attributes'] as int;
        expect(after & 3, 3);
        expect(after & ~0x83, before & ~0x83); // NORMAL is exclusive.
        expect(after & 0x2000, 0x2000);
        if (path == directory.path) expect(after & 0x10, 0x10);
        final native = await backend.readMetadataFields(
          path,
          permissions: false,
          modified: false,
          accessed: false,
          created: false,
          ownership: false,
          extendedAttributes: false,
          acl: false,
        );
        expect(native.windowsAttributes, after);
        await backend.writeMetadata(
          path,
          const TransferMetadata(
            windowsAttributes: 0,
            windowsAttributesMask: 1,
          ),
        );
        final cleared = (await _inspect(path))['attributes'] as int;
        expect(cleared & 1, 0);
        expect(cleared & 2, 2);
        expect(cleared & ~0x81, after & ~0x81);
      }
      expect(await file.readAsString(), 'attributes');
    });

    test(
      'creation, modification, and access times can change independently',
      () async {
        final file = await File(p.join(root.path, 'times.txt'))
            .writeAsString('times');
        final created = DateTime.utc(2019, 2, 3, 4, 5, 6, 123, 456);
        final accessed = DateTime.utc(2020, 3, 4, 5, 6, 7);
        final modified = DateTime.utc(2021, 4, 5, 6, 7, 8);
        await backend.writeMetadata(
          file.path,
          TransferMetadata(
            created: created,
            modified: modified,
            accessed: accessed,
          ),
        );
        var external = await _inspect(file.path);
        expect(DateTime.parse(external['created'] as String), created);
        expect(DateTime.parse(external['modified'] as String), modified);
        expect(DateTime.parse(external['accessed'] as String), accessed);
        final next = DateTime.utc(2018, 1, 2);
        await backend.writeMetadata(file.path, TransferMetadata(created: next));
        external = await _inspect(file.path);
        expect(DateTime.parse(external['created'] as String), next);
        expect(DateTime.parse(external['modified'] as String), modified);
        expect(DateTime.parse(external['accessed'] as String), accessed);
        final native = await backend.readMetadataFields(
          file.path,
          permissions: false,
          modified: false,
          accessed: false,
          ownership: false,
          extendedAttributes: false,
          acl: false,
          windowsAttributes: false,
        );
        expect(native.created, next);
        expect(native.modified, isNull);
        expect(native.accessed, isNull);
        expect(native.acl, isNull);
      },
    );

    test(
      'invalid values fail before changing other requested fields',
      () async {
        final file = await File(p.join(root.path, 'invalid.txt'))
            .writeAsString('retain');
        final before = await _inspect(file.path);
        final modified = DateTime.utc(2020);
        for (final metadata in [
          TransferMetadata(
            windowsAttributes: 0,
            windowsAttributesMask: 0x10,
            modified: modified,
          ),
          TransferMetadata(windowsAttributes: -1, modified: modified),
          TransferMetadata(owner: '1000', modified: modified),
          TransferMetadata(group: 'S-1-not-a-SID', modified: modified),
          TransferMetadata(
            acl: 'windows-sddl-v1:D:invalid',
            modified: modified,
          ),
          TransferMetadata(
            acl: 'windows-sddl-v1:D:P(A;;FA;;;WD)O:${before['owner']}',
            modified: modified,
          ),
          TransferMetadata(created: DateTime.utc(1600), modified: modified),
          TransferMetadata(mode: 0, modified: modified),
        ]) {
          await expectLater(
            backend.writeMetadata(file.path, metadata),
            throwsA(anything),
          );
          final after = await _inspect(file.path);
          expect(after['modified'], before['modified']);
          expect(after['created'], before['created']);
          expect(after['dacl'], before['dacl']);
          expect(after['attributes'], before['attributes']);
        }
        expect(await file.readAsString(), 'retain');
      },
    );

    test(
      'junction handles cannot redirect metadata writes into the target',
      () async {
        final target = await Directory(p.join(root.path, 'junction-target'))
            .create();
        final junction = p.join(root.path, 'junction');
        final result = await Process.run('cmd.exe', [
          '/c',
          'mklink',
          '/J',
          junction,
          target.path,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        addTearDown(() async {
          final removed = await Process.run('cmd.exe', [
            '/c',
            'rmdir',
            junction,
          ]);
          expect(
            removed.exitCode,
            0,
            reason: '${removed.stdout}\n${removed.stderr}',
          );
        });
        final before = await _inspect(target.path);
        await expectLater(
          writeNativeMetadata(
            junction,
            const TransferMetadata(
              windowsAttributes: 2,
              windowsAttributesMask: 2,
            ),
          ),
          throwsUnsupportedError,
        );
        final after = await _inspect(target.path);
        expect(after['attributes'], before['attributes']);
        expect(after['modified'], before['modified']);
      },
    );
  }, skip: !Platform.isWindows);
}

Future<String> _powershell(String path, String script) async {
  final result = await Process.run(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r"$ErrorActionPreference = 'Stop'; " + script,
    ],
    environment: {'CRISP_METADATA_TEST_PATH': path},
  );
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  return result.stdout.toString().trim();
}

Future<void> _enableAutomaticInheritance(String path) async {
  await _powershell(path, r'''
$item = Get-Item -Force -LiteralPath $env:CRISP_METADATA_TEST_PATH
$acl = $item.GetAccessControl()
$acl.SetAccessRuleProtection($false, $false)
$item.SetAccessControl($acl)
''');
}

Future<Map<String, dynamic>> _inspect(String path) async => jsonDecode(
  await _powershell(path, r'''
$item = Get-Item -Force -LiteralPath $env:CRISP_METADATA_TEST_PATH
# GetAccessControl wraps the native descriptor in CommonSecurityDescriptor,
# which canonicalizes ACE order. Read the raw descriptor through a separate
# documented file API so exact native order/protection/inheritance comparisons
# cannot be changed by that managed representation.
# https://learn.microsoft.com/windows/win32/api/securitybaseapi/nf-securitybaseapi-getfilesecurityw
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
public static class CrispRawFileSecurity {
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  private static extern bool GetFileSecurityW(
    string path, uint information, byte[] descriptor, uint length,
    out uint needed);
  public static RawSecurityDescriptor Read(string path) {
    uint needed;
    GetFileSecurityW(path, 7, null, 0, out needed);
    int error = Marshal.GetLastWin32Error();
    if (error != 122 || needed == 0)
      throw new Win32Exception(error);
    if (needed > 1048576)
      throw new InvalidOperationException("Unexpected security descriptor size.");
    byte[] descriptor = new byte[needed];
    if (!GetFileSecurityW(path, 7, descriptor, needed, out needed))
      throw new Win32Exception(Marshal.GetLastWin32Error());
    return new RawSecurityDescriptor(descriptor, 0);
  }
}
'@
$acl = [CrispRawFileSecurity]::Read($env:CRISP_METADATA_TEST_PATH)
[ordered]@{
  owner = $acl.Owner.Value
  group = $acl.Group.Value
  dacl = $acl.GetSddlForm([Security.AccessControl.AccessControlSections]::Access)
  protected = ([int]$acl.ControlFlags -band 0x1000) -ne 0
  rules = @(foreach ($rule in $acl.DiscretionaryAcl) {
    [ordered]@{
      sid = $rule.SecurityIdentifier.Value
      type = $rule.AceQualifier.ToString()
      rights = $rule.AccessMask
      flags = [int]$rule.AceFlags
    }
  })
  attributes = [int]$item.Attributes
  created = $item.CreationTimeUtc.ToString('o')
  modified = $item.LastWriteTimeUtc.ToString('o')
  accessed = $item.LastAccessTimeUtc.ToString('o')
} | ConvertTo-Json -Compress -Depth 4
'''),
) as Map<String, dynamic>;
