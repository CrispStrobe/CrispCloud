import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/native_metadata.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalOperationBackend backend;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final temporary = await Directory.systemTemp.createTemp('crisp-metadata-');
    // macOS exposes the temporary directory through /var -> /private/var.
    // Transfer paths deliberately reject unreviewed ancestor symlinks.
    root = Directory(await temporary.resolveSymbolicLinks());
    backend = LocalOperationBackend(LocalFileService(), isCurrent: () => true);
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('native metadata capabilities describe implemented descriptor APIs', () {
    expect(backend.capabilities.ownership, supportsNativeOwnership);
    expect(
      backend.capabilities.extendedAttributes,
      supportsNativeExtendedAttributes,
    );
    expect(
      backend.capabilities.accessControlLists,
      supportsNativeAccessControlLists,
    );
    expect(
      backend.capabilities.windowsAttributes,
      supportsNativeWindowsAttributes,
    );
    expect(backend.capabilities.setCreatedTime, supportsNativeCreatedTime);
  });

  test('ownership reads actual UID/GID and same-owner preservation retains content', () async {
    final file = await File('${root.path}/owned.txt')
        .writeAsString('owned data');
    final before = await backend.readMetadata(file.path);
    final uid = await Process.run('id', ['-u']);
    final gid = await Process.run('id', ['-g']);
    expect(before.owner, uid.stdout.toString().trim());
    expect(before.group, gid.stdout.toString().trim());
    await backend.writeMetadata(
      file.path,
      TransferMetadata(owner: before.owner, group: before.group, mode: 0x1a0),
    );
    expect((await file.stat()).mode & 0xfff, 0x1a0);
    expect(await file.readAsString(), 'owned data');
  }, skip: Platform.isWindows || !supportsNativeOwnership);

  test('selective reads omit unrelated native fields and preserve requested values', () async {
    final file = await File('${root.path}/selective')
        .writeAsString('selective');
    await backend.writeMetadata(
      file.path,
      TransferMetadata(
        extendedAttributes: {
          'user.crisp-selective': Uint8List.fromList([42]),
        },
      ),
    );
    final selected = await backend.readMetadataFields(
      file.path,
      permissions: true,
      modified: true,
      accessed: false,
      ownership: false,
      extendedAttributes: false,
      acl: false,
    );
    expect(selected.mode, (await file.stat()).mode & 0xfff);
    expect(selected.modified, (await file.stat()).modified);
    expect(selected.owner, isNull);
    expect(selected.group, isNull);
    expect(selected.accessed, isNull);
    expect(selected.extendedAttributes, isEmpty);
    expect(selected.acl, isNull);
  }, skip: !supportsNativeExtendedAttributes);

  test('binary and empty xattrs survive a real streamed copy', () async {
    final source = await File('${root.path}/original').writeAsString('payload');
    final destination = await Directory('${root.path}/destination').create();
    const key = 'user.crispcloud-test';
    const emptyKey = 'user.crispcloud-empty';
    final bytes = Uint8List.fromList([0, 255, 128, 65, 0]);
    await backend.writeMetadata(
      source.path,
      TransferMetadata(
        extendedAttributes: {key: bytes, emptyKey: Uint8List(0)},
      ),
    );
    final plan = await const FileOperationService().prepare(
      source: backend,
      destination: backend,
      files: [(await backend.stat(source.path))!],
      targetDirectory: destination.path,
      options: const FileOperationOptions(
        preserveExtendedAttributes: true,
        preferNative: false,
      ),
    );
    expect(plan.errors, isEmpty);
    await const FileOperationService().execute(
      plan,
      control: FileOperationControl(),
    );
    expect(plan.entries.single.outcome, FileOperationOutcome.copied);
    final copied = '${destination.path}/original';
    final metadata = await backend.readMetadata(copied);
    expect(metadata.extendedAttributes[key], bytes);
    expect(metadata.extendedAttributes[emptyKey], isEmpty);
    // Independent OS reader verifies the representation, not just a round trip
    // through our own serialization and FFI wrappers.
    final external = await Process.run('python3', [
      '-c',
      'import os,sys; print(os.getxattr(sys.argv[1],sys.argv[2]).hex())',
      copied,
      key,
    ]);
    expect(external.exitCode, 0, reason: external.stderr.toString());
    expect(external.stdout.toString().trim(), '00ff804100');
  }, skip: !supportsNativeExtendedAttributes);

  test(
    'modification and access timestamps are independently editable',
    () async {
      final file = await File('${root.path}/times')
          .writeAsString('timestamp data');
      final modified = DateTime.utc(2024, 2, 3, 4, 5, 6);
      final accessed = DateTime.utc(2024, 3, 4, 5, 6, 7);
      await backend.writeMetadata(
        file.path,
        TransferMetadata(modified: modified, accessed: accessed),
      );
      expect((await file.stat()).modified.toUtc(), modified);
      expect((await file.stat()).accessed.toUtc(), accessed);
      final next = DateTime.utc(2024, 4, 5, 6, 7, 8);
      await backend.writeMetadata(file.path, TransferMetadata(modified: next));
      final finalStat = await file.stat();
      expect(finalStat.modified.toUtc(), next);
      expect(finalStat.accessed.toUtc(), accessed);
    },
    skip: !supportsNativeMetadata,
  );

  test(
    'symbolic links never redirect metadata writes to their targets',
    () async {
      final file = await File('${root.path}/target').writeAsString('target');
      final link = await Link('${root.path}/link').create(file.path);
      final before = await file.stat();
      await expectLater(
        backend.writeMetadata(link.path, const TransferMetadata(mode: 0)),
        throwsA(isA<FileSystemException>()),
      );
      final after = await file.stat();
      expect(after.mode, before.mode);
      expect(await file.readAsString(), 'target');
    },
    skip: Platform.isWindows || !supportsNativeMetadata,
  );

  test(
    'Linux metadata edits can restore mode 0000 without opening file data',
    () async {
      final file = await File('${root.path}/locked')
          .writeAsString('retain payload');
      final directory = await Directory('${root.path}/locked-directory')
          .create();
      final original = await backend.readMetadata(file.path);
      try {
        await backend.writeMetadata(file.path, const TransferMetadata(mode: 0));
        await backend.writeMetadata(
          directory.path,
          const TransferMetadata(mode: 0),
        );
        expect((await file.stat()).mode & 0xfff, 0);
        expect((await directory.stat()).mode & 0xfff, 0);
        final owners = await readNativeMetadata(
          file.path,
          ownership: true,
          extendedAttributes: false,
          acl: false,
        );
        expect(owners.owner, original.owner);
        expect(owners.group, original.group);
        final modified = DateTime.utc(2024, 5, 6, 7, 8, 9);
        await backend.writeMetadata(
          file.path,
          TransferMetadata(
            mode: 0x180,
            owner: original.owner,
            group: original.group,
            modified: modified,
          ),
        );
        await backend.writeMetadata(
          directory.path,
          const TransferMetadata(mode: 0x1c0),
        );
        expect((await file.stat()).mode & 0xfff, 0x180);
        expect((await file.stat()).modified.toUtc(), modified);
        expect((await directory.stat()).mode & 0xfff, 0x1c0);
        expect(await file.readAsString(), 'retain payload');
      } finally {
        // Cleanup remains possible if a future regression reintroduces a data
        // read permission requirement. chmod itself only requires ownership.
        await Process.run('chmod', ['600', file.path]);
        await Process.run('chmod', ['700', directory.path]);
      }
    },
    skip: !Platform.isLinux || !supportsNativeOwnership,
  );

  test(
    'unsupported Linux filesystem ACLs remain unavailable, not an empty ACL',
    () async {
      final metadata = await readNativeMetadata(
        '/proc/version',
        ownership: false,
        extendedAttributes: false,
        acl: true,
      );
      expect(metadata.acl, isNull);
    },
    skip: !Platform.isLinux || !supportsNativeAccessControlLists,
  );

  test('invalid native ACL contents are rejected before changing permissions', () async {
    final file = await File('${root.path}/invalid-acl').writeAsString('retain');
    final before = await file.stat();
    final malformed = Platform.isMacOS
        ? 'darwin-acl-v1:not a valid ACL'
        : 'linux-posix-v1:${jsonEncode({
            'access': base64Encode([2, 0, 0, 0, 1, 0, 7, 0, 255, 255, 255, 255]),
            'default': null,
          })}';
    try {
      await expectLater(
        backend.writeMetadata(
          file.path,
          TransferMetadata(acl: malformed, mode: 0),
        ),
        throwsFormatException,
      );
      expect((await file.stat()).mode, before.mode);
      expect(await file.readAsString(), 'retain');
    } finally {
      await Process.run('chmod', ['600', file.path]);
    }
  }, skip: Platform.isWindows || !supportsNativeAccessControlLists);

  test(
    'malformed ownership or ACL payload is rejected before mode changes',
    () async {
      final file = await File('${root.path}/validated').writeAsString('data');
      final before = await file.stat();
      for (final metadata in [
        const TransferMetadata(owner: 'root;bad', mode: 0),
        const TransferMetadata(group: '-1', mode: 0),
        const TransferMetadata(acl: 'foreign-format', mode: 0),
        TransferMetadata(
          extendedAttributes: {'bad\u0000name': Uint8List(0)},
          mode: 0,
        ),
      ]) {
        await expectLater(
          backend.writeMetadata(file.path, metadata),
          throwsFormatException,
        );
        expect((await file.stat()).mode, before.mode);
      }
    },
    skip: Platform.isWindows || !supportsNativeMetadata,
  );

  test(
    'Unix refuses unsupported creation and Windows attributes before mutation',
    () async {
      final file = await File('${root.path}/unsupported')
          .writeAsString('intact');
      final before = await file.stat();
      for (final metadata in [
        TransferMetadata(created: DateTime.utc(2020), mode: 0),
        const TransferMetadata(windowsAttributes: 1, mode: 0),
      ]) {
        await expectLater(
          backend.writeMetadata(file.path, metadata),
          throwsUnsupportedError,
        );
        expect((await file.stat()).mode, before.mode);
        expect(await file.readAsString(), 'intact');
      }
    },
    skip: Platform.isWindows || !supportsNativeMetadata,
  );

  test('Linux access and default directory ACLs are independent from ordinary xattrs', () async {
    final directory = await Directory('${root.path}/acl-source').create();
    final target = await Directory('${root.path}/acl-target').create();
    final ownership = await backend.readMetadata(directory.path);
    final raw = _linuxAcl(int.parse(ownership.owner!));
    final acl =
        'linux-posix-v1:${jsonEncode({'access': base64Encode(raw), 'default': base64Encode(raw)})}';
    await backend.writeMetadata(directory.path, TransferMetadata(acl: acl));
    final read = await backend.readMetadata(directory.path);
    expect(
      read.extendedAttributes.keys,
      isNot(contains('system.posix_acl_access')),
    );
    expect(
      read.extendedAttributes.keys,
      isNot(contains('system.posix_acl_default')),
    );
    expect(read.acl, acl);
    await backend.writeMetadata(target.path, TransferMetadata(acl: read.acl));
    final child = await File('${target.path}/child').writeAsString('inherited');
    final childAcl = await backend.readMetadata(child.path);
    final decoded =
        jsonDecode(childAcl.acl!.substring('linux-posix-v1:'.length)) as Map;
    expect(
      decoded['access'],
      isNotNull,
      reason: 'New children must inherit the copied default ACL.',
    );
    expect(decoded['default'], isNull);
    final clear =
        'linux-posix-v1:${jsonEncode({'access': null, 'default': null})}';
    await backend.writeMetadata(target.path, TransferMetadata(acl: clear));
    expect((await backend.readMetadata(target.path)).acl, clear);
  }, skip: !Platform.isLinux || !supportsNativeAccessControlLists);

  test(
    'macOS ACLs preserve an actual named-user entry on another file',
    () async {
      final source = await File('${root.path}/acl-source')
          .writeAsString('source');
      final target = await File('${root.path}/acl-target')
          .writeAsString('target');
      final username = (await Process.run('id', [
        '-un',
      ])).stdout.toString().trim();
      final result = await Process.run('chmod', [
        '+a',
        'user:$username allow read',
        source.path,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final metadata = await backend.readMetadata(source.path);
      expect(metadata.acl, startsWith('darwin-acl-v1:'));
      await backend.writeMetadata(
        target.path,
        TransferMetadata(acl: metadata.acl),
      );
      expect((await backend.readMetadata(target.path)).acl, metadata.acl);
      final listing = await Process.run('ls', ['-le', target.path]);
      expect(listing.stdout.toString(), contains('allow read'));
    },
    skip: !Platform.isMacOS || !supportsNativeAccessControlLists,
  );
}

Uint8List _linuxAcl(int uid) {
  final data = ByteData(4 + 5 * 8)..setUint32(0, 2, Endian.little);
  final entries = [
    (1, 7, 0xffffffff),
    (2, 5, uid),
    (4, 0, 0xffffffff),
    (16, 5, 0xffffffff),
    (32, 0, 0xffffffff),
  ];
  for (var index = 0; index < entries.length; index++) {
    final offset = 4 + index * 8;
    final entry = entries[index];
    data
      ..setUint16(offset, entry.$1, Endian.little)
      ..setUint16(offset + 2, entry.$2, Endian.little)
      ..setUint32(offset + 4, entry.$3, Endian.little);
  }
  return data.buffer.asUint8List();
}
