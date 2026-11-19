import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/file_item.dart';
import 'file_operation_service.dart';
import 'storage_transfer_contract.dart';

/// Immutable, portable, per-directory records. Each record is addressed by its
/// own digest, so concurrent backups never merge/overwrite a shared manifest.
class MetadataSidecarService {
  static const prefix = '.crispmeta-';
  static const maxBytes = 1024 * 1024;
  static bool isSidecarName(String name) =>
      RegExp(r'^\.crispmeta-[0-9a-f]{64}\.json$').hasMatch(name);

  static Future<String> _digest(
    FileOperationBackend backend,
    FileItem file, {
    FileOperationControl? control,
  }) async {
    var size = 0;
    final digest = await sha256
        .bind(
          (control?.bind(backend.readFile(file)) ?? backend.readFile(file))
              .asyncMap((part) async {
                await control?.checkpoint();
                size += part.length;
                if (file.size != null && size > file.size!) {
                  throw StateError('File changed while verifying metadata.');
                }
                return part;
              }),
        )
        .single;
    if (file.size != null && size != file.size) {
      throw StateError('File changed while verifying metadata.');
    }
    final after = await backend.stat(file.path!);
    if (after == null ||
        after.uuid != file.uuid ||
        after.size != file.size ||
        after.updatedAt != file.updatedAt) {
      throw StateError('File changed while verifying metadata.');
    }
    return digest.toString();
  }

  static Map<String, dynamic> _encode(TransferMetadata m) => {
    if (m.modified != null) 'modified': m.modified!.toUtc().toIso8601String(),
    if (m.accessed != null) 'accessed': m.accessed!.toUtc().toIso8601String(),
    if (m.created != null) 'created': m.created!.toUtc().toIso8601String(),
    if (m.mode != null) 'mode': m.mode,
    if (m.owner != null) 'owner': m.owner,
    if (m.group != null) 'group': m.group,
    if (m.acl != null) 'acl': m.acl,
    if (m.windowsAttributes != null) 'windowsAttributes': m.windowsAttributes,
    'xattrs': {
      for (final key in (m.extendedAttributes.keys.toList()..sort()))
        key: base64Encode(m.extendedAttributes[key]!),
    },
  };

  static Future<void> save(
    FileOperationBackend source,
    FileOperationBackend target,
    FileOperationEntry entry, {
    FileOperationControl? control,
  }) async {
    await control?.checkpoint();
    if (entry.source.isSymlink == true || isSidecarName(entry.source.name)) {
      return;
    }
    final actual = await target.stat(entry.destination);
    if (actual == null ||
        actual.isSymlink == true ||
        actual.isFolder != entry.source.isFolder) {
      throw StateError('Metadata destination changed.');
    }
    String? digest;
    if (!actual.isFolder) {
      digest = await _digest(target, actual, control: control);
      final expected =
          entry.recovery?['contentSha256'] ?? entry.recovery?['sourceSha256'];
      if (expected is! String || digest != expected) {
        throw StateError('Sidecars require a verified copy.');
      }
    }
    final caps = source.capabilities;
    final metadata = await source.readMetadataFields(
      entry.source.path!,
      permissions: caps.permissions,
      ownership: caps.ownership,
      extendedAttributes: caps.extendedAttributes,
      acl: caps.accessControlLists,
      windowsAttributes: caps.windowsAttributes,
      created: caps.setCreatedTime,
    );
    final fields = _encode(metadata);
    fields.putIfAbsent(
      'modified',
      () => entry.source.updatedAt?.toUtc().toIso8601String(),
    );
    fields.removeWhere((key, value) => value == null);
    final record = <String, dynamic>{
      'format': 'crispcloud-metadata',
      'version': 1,
      'name': target.paths.basename(entry.destination),
      'directory': actual.isFolder,
      if (digest != null) 'contentSha256': digest,
      'metadata': fields,
    };
    final bytes = utf8.encode(jsonEncode(record));
    if (bytes.length > maxBytes) {
      throw StateError('Metadata sidecar exceeds 1 MiB.');
    }
    final path = target.paths.join(
      target.paths.dirname(entry.destination),
      '$prefix${sha256.convert(bytes)}.json',
    );
    final previous = await target.stat(path);
    if (previous != null) {
      final saved = await _read(target, previous);
      if (sha256.convert(saved).toString() !=
          sha256.convert(bytes).toString()) {
        throw StateError('An existing sidecar has unexpected content.');
      }
      return;
    }
    await control?.checkpoint();
    if (!source.isCurrent || !target.isCurrent) {
      throw StateError("The metadata storage disconnected.");
    }
    await target.writePreparedFile(
      path,
      Stream.value(bytes),
      bytes.length,
      replace: false,
    );
  }

  static Future<List<int>> _read(
    FileOperationBackend backend,
    FileItem file,
  ) async {
    if (file.isFolder ||
        file.isSymlink == true ||
        (file.size != null && file.size! > maxBytes)) {
      throw const FormatException('Invalid metadata sidecar.');
    }
    final bytes = <int>[];
    await for (final part in backend.readFile(file)) {
      if (bytes.length + part.length > maxBytes) {
        throw const FormatException('Metadata sidecar exceeds 1 MiB.');
      }
      bytes.addAll(part);
    }
    return bytes;
  }

  static Future<Map<String, dynamic>> read(
    FileOperationBackend backend,
    FileItem file,
  ) async {
    if (!isSidecarName(file.name)) {
      throw const FormatException('Not a metadata sidecar.');
    }
    final bytes = await _read(backend, file);
    if (file.name != '$prefix${sha256.convert(bytes)}.json') {
      throw const FormatException('Sidecar digest mismatch.');
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map ||
        value['format'] != 'crispcloud-metadata' ||
        value['version'] != 1 ||
        value['metadata'] is! Map ||
        value['directory'] is! bool) {
      throw const FormatException('Unsupported metadata sidecar.');
    }
    final name = value['name'];
    if (name is! String ||
        name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains('\u0000')) {
      throw const FormatException('Invalid metadata destination name.');
    }
    if (value['directory'] == false &&
        (value['contentSha256'] is! String ||
            !RegExp(r'^[0-9a-f]{64}$')
                .hasMatch(value['contentSha256'] as String))) {
      throw const FormatException('Missing metadata content identity.');
    }
    return Map<String, dynamic>.from(value);
  }

  /// Only explicit restoration applies records. Permissions/owner/ACL/xattrs are
  /// independently opted in; timestamp-only restoration is the default.
  static Future<void> restore(
    FileOperationBackend target,
    FileItem sidecar, {
    bool permissions = false,
    bool ownership = false,
    bool extendedAttributes = false,
    bool acl = false,
    bool windowsAttributes = false,
  }) async {
    final record = await read(target, sidecar);
    final path = target.paths.join(
      target.paths.dirname(sidecar.path!),
      record['name'] as String,
    );
    final actual = await target.stat(path);
    if (actual == null ||
        actual.isSymlink == true ||
        actual.isFolder != record['directory']) {
      throw StateError('Metadata target is missing or has changed type.');
    }
    if (!actual.isFolder &&
        await _digest(target, actual) != record['contentSha256']) {
      throw StateError('File content differs from this metadata record.');
    }
    final m = Map<String, dynamic>.from(record['metadata'] as Map);
    DateTime? time(String key) {
      final v = m[key];
      if (v == null) return null;
      return DateTime.parse(v as String).toUtc();
    }

    final rawMode = m['mode'];
    if (rawMode != null &&
        (rawMode is! int || rawMode < 0 || rawMode > 0xfff)) {
      throw const FormatException('Invalid permissions in sidecar.');
    }
    final xattrs = m['xattrs'];
    final attributes = <String, List<int>>{};
    if (extendedAttributes) {
      if (xattrs is! Map || xattrs.length > 256) {
        throw const FormatException('Invalid extended attributes.');
      }
      for (final item in xattrs.entries) {
        if (item.key is! String ||
            (item.key as String).contains('\u0000') ||
            item.value is! String) {
          throw const FormatException('Invalid extended attribute.');
        }
        attributes[item.key as String] = base64Decode(item.value as String);
      }
    }
    final caps = target.capabilities;
    if (!caps.setModifiedTime ||
        (permissions && !caps.permissions) ||
        (ownership && !caps.ownership) ||
        (extendedAttributes && !caps.extendedAttributes) ||
        (acl && !caps.accessControlLists) ||
        (windowsAttributes && !caps.windowsAttributes)) {
      throw UnsupportedError(
        'The destination cannot restore the selected metadata fields.',
      );
    }
    if (!target.isCurrent) {
      throw StateError('The metadata destination disconnected.');
    }
    await target.writeMetadata(
      path,
      TransferMetadata(
        modified: time('modified'),
        accessed: target.capabilities.setAccessedTime ? time('accessed') : null,
        created: target.capabilities.setCreatedTime ? time('created') : null,
        mode: permissions ? rawMode as int? : null,
        owner: ownership ? m['owner'] as String? : null,
        group: ownership ? m['group'] as String? : null,
        acl: acl ? m['acl'] as String? : null,
        windowsAttributes: windowsAttributes
            ? m['windowsAttributes'] as int?
            : null,
        extendedAttributes: {
          for (final item in attributes.entries)
            item.key: Uint8List.fromList(item.value),
        },
      ),
    );
  }
}
