import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:xml/xml.dart';

const int kKeePassMaxFileBytes = 32 * 1024 * 1024;
const int kKeePassMaxKeyFileBytes = 1024 * 1024;
const int _maxFieldBytes = 1024 * 1024;
const int _maxItems = 20000;

enum KeePassErrorCode {
  invalidCredentials,
  unsupported,
  corrupt,
  resourceLimit,
  locked,
}

/// Only fixed, non-sensitive errors cross the backend/UI boundary.
class KeePassException implements Exception {
  const KeePassException(this.code);
  final KeePassErrorCode code;

  @override
  String toString() => switch (code) {
    KeePassErrorCode.invalidCredentials =>
      'The database credentials are incorrect.',
    KeePassErrorCode.unsupported =>
      'This KeePass database uses unsupported features.',
    KeePassErrorCode.corrupt => 'The KeePass database could not be verified.',
    KeePassErrorCode.resourceLimit =>
      'The KeePass database exceeds the supported resource limits.',
    KeePassErrorCode.locked => 'The KeePass database is locked or busy.',
  };
}

class KeePassGroupInfo {
  const KeePassGroupInfo({
    required this.id,
    required this.name,
    required this.path,
  });
  final String id;
  final String name;
  final String path;
}

class KeePassEntryInfo {
  const KeePassEntryInfo({
    required this.id,
    required this.groupId,
    required this.title,
    required this.userName,
    this.isRecycled = false,
  });
  final String id;
  final String groupId;
  final String title;
  final String userName;
  final bool isRecycled;
}

class KeePassEntryFields {
  const KeePassEntryFields({
    this.title = '',
    this.userName = '',
    this.password = '',
    this.url = '',
    this.notes = '',
  });
  final String title;
  final String userName;
  final String password;
  final String url;
  final String notes;

  Map<String, String> get _values => {
    'Title': title,
    'UserName': userName,
    'Password': password,
    'URL': url,
    'Notes': notes,
  };
}

/// An unlocked in-memory database. It performs no filesystem writes, logging,
/// network access, plaintext exports, backups, or credential persistence.
///
/// The caller owns source-bound encrypted saves and discards all UI controllers
/// on lock. Mutable key buffers are cleared best-effort; immutable Dart strings
/// and garbage-collected copies cannot be guaranteed to be erased.
class KeePassSession {
  KeePassSession._(this._document) {
    _reindex();
  }

  KdbxRawDocument? _document;
  final _groups = <String, XmlElement>{};
  final _entries = <String, XmlElement>{};
  final _entryGroups = <String, String>{};
  List<KeePassGroupInfo> _groupInfo = const [];
  Future<Uint8List>? _pendingSave;
  bool _disposed = false;

  static Future<KeePassSession> open(
    Uint8List bytes, {
    required String? password,
    Uint8List? keyFile,
  }) async {
    if (bytes.length > kKeePassMaxFileBytes ||
        (keyFile?.length ?? 0) > kKeePassMaxKeyFileBytes ||
        (password?.length ?? 0) > _maxFieldBytes) {
      throw const KeePassException(KeePassErrorCode.resourceLimit);
    }
    if (password == null && keyFile == null) {
      throw const KeePassException(KeePassErrorCode.invalidCredentials);
    }
    final raw = await compute(_unlockKeePass, (
      bytes: Uint8List.fromList(bytes),
      password: password,
      keyFile: keyFile == null ? null : Uint8List.fromList(keyFile),
    ));
    try {
      return KeePassSession._(raw);
    } catch (error) {
      raw.dispose();
      throw _safeError(error);
    }
  }

  KdbxRawDocument get _openDocument {
    if (_disposed || _document == null) {
      throw const KeePassException(KeePassErrorCode.locked);
    }
    return _document!;
  }

  void _checkMutable() {
    _openDocument;
    if (_pendingSave != null) {
      throw const KeePassException(KeePassErrorCode.locked);
    }
  }

  String get databaseName {
    final raw = _openDocument;
    final name = raw.xml.rootElement
        .getElement('Meta')
        ?.getElement('DatabaseName');
    return name == null ? _groupInfo.first.name : raw.textOf(name);
  }

  String get formatLabel {
    final header = _openDocument.header;
    final cipher = header.dataCipherUuid?.string == CipherId.chaCha20
        ? 'ChaCha20'
        : 'AES-256';
    final kdf = header.version.$1 == 3
        ? KdfId.aes
        : base64.encode(header.kdfParameters!.get(r'$UUID') as List<int>);
    final derivation = switch (kdf) {
      KdfId.argon2d => 'Argon2d',
      KdfId.argon2id => 'Argon2id',
      _ => 'AES-KDF',
    };
    return 'KDBX ${header.version.$1}.${header.version.$2} · $cipher · $derivation';
  }

  List<KeePassGroupInfo> get groups {
    _openDocument;
    return _groupInfo;
  }

  List<KeePassEntryInfo> get entries {
    final raw = _openDocument;
    final meta = raw.xml.rootElement.getElement('Meta')!;
    final recycle =
        meta.getElement('RecycleBinEnabled')?.innerText.toLowerCase() == 'true'
        ? _groups[meta.getElement('RecycleBinUUID')?.innerText]
        : null;
    return List.unmodifiable(
      _entries.entries.map((entry) {
        final fields = _fieldNodes(entry.value);
        return KeePassEntryInfo(
          id: entry.key,
          groupId: _entryGroups[entry.key]!,
          title: fields['Title'] == null ? '' : raw.textOf(fields['Title']!),
          userName: fields['UserName'] == null
              ? ''
              : raw.textOf(fields['UserName']!),
          isRecycled:
              recycle != null && entry.value.ancestors.contains(recycle),
        );
      }),
    );
  }

  KeePassEntryFields entryFields(String id) {
    final raw = _openDocument;
    final entry = _entries[id];
    if (entry == null) throw const KeePassException(KeePassErrorCode.corrupt);
    final fields = _fieldNodes(entry);
    String value(String name) =>
        fields[name] == null ? '' : raw.textOf(fields[name]!);
    return KeePassEntryFields(
      title: value('Title'),
      userName: value('UserName'),
      password: value('Password'),
      url: value('URL'),
      notes: value('Notes'),
    );
  }

  String addEntry({
    required String groupId,
    required KeePassEntryFields fields,
  }) {
    _checkMutable();
    final raw = _openDocument;
    final group = _groups[groupId];
    if (group == null) throw const KeePassException(KeePassErrorCode.corrupt);
    _validateFields(fields);
    _checkGrowth(fields);
    if (_groups.length + _entries.length >= _maxItems) {
      throw const KeePassException(KeePassErrorCode.resourceLimit);
    }
    final id = _newId();
    final entry = XmlElement(XmlName('Entry'), [], [
      _element('UUID', id),
      _element('IconID', '0'),
      _newTimes(),
      XmlElement(XmlName('History')),
    ]);
    _setFields(raw, entry, fields);
    group.children.add(entry);
    _entries[id] = entry;
    _entryGroups[id] = groupId;
    return id;
  }

  void updateEntry(String id, KeePassEntryFields fields) {
    _checkMutable();
    _validateFields(fields);
    final raw = _openDocument;
    final entry = _entries[id];
    if (entry == null) throw const KeePassException(KeePassErrorCode.corrupt);
    final old = entryFields(id)._values;
    if (fields._values.entries.every(
      (value) => old[value.key] == value.value,
    )) {
      return;
    }
    _checkGrowth(fields, history: entry);
    final snapshot = raw.cloneElement(entry, omitHistory: true);
    final history =
        entry.getElement('History') ?? XmlElement(XmlName('History'));
    if (history.parent == null) entry.children.add(history);
    history.children.add(snapshot);
    _setFields(raw, entry, fields);
    _touch(entry);
  }

  void deleteEntry(String id) {
    _checkMutable();
    final raw = _openDocument;
    final entry = _entries[id];
    if (entry == null) throw const KeePassException(KeePassErrorCode.corrupt);
    final meta = raw.xml.rootElement.getElement('Meta')!;
    final recycleEnabled =
        meta.getElement('RecycleBinEnabled')?.innerText.toLowerCase() == 'true';
    var recycle = recycleEnabled
        ? _groups[meta.getElement('RecycleBinUUID')?.innerText]
        : null;
    if (recycleEnabled && recycle == null) {
      final rootGroup = _groups[_groupInfo.first.id]!;
      final recycleId = _newId();
      recycle = XmlElement(XmlName('Group'), [], [
        _element('UUID', recycleId),
        _element('Name', 'Recycle Bin'),
        _element('IconID', '43'),
        _newTimes(),
        _element('EnableSearching', 'False'),
        _element('EnableAutoType', 'False'),
      ]);
      rootGroup.children.add(recycle);
      _groups[recycleId] = recycle;
      _groupInfo = List.unmodifiable([
        ..._groupInfo,
        KeePassGroupInfo(
          id: recycleId,
          name: 'Recycle Bin',
          path: '${_groupInfo.first.path} / Recycle Bin',
        ),
      ]);
      _setChild(meta, 'RecycleBinUUID', recycleId);
      _setChild(meta, 'RecycleBinChanged', _now());
    }
    final alreadyRecycled =
        recycle != null && entry.ancestors.contains(recycle);
    entry.parent?.children.remove(entry);
    if (recycle != null && !alreadyRecycled) {
      recycle.children.add(entry);
      _setChild(entry, 'PreviousParentGroup', _entryGroups[id]!);
      _touch(entry, location: true);
      _entryGroups[id] = _id(recycle);
    } else {
      final root = raw.xml.rootElement.getElement('Root')!;
      final deleted =
          root.getElement('DeletedObjects') ??
          XmlElement(XmlName('DeletedObjects'));
      if (deleted.parent == null) root.children.add(deleted);
      deleted.children.add(
        XmlElement(XmlName('DeletedObject'), [], [
          _element('UUID', id),
          _element('DeletionTime', _now()),
        ]),
      );
      raw.forgetElement(entry);
      _entries.remove(id);
      _entryGroups.remove(id);
    }
  }

  Future<Uint8List> save() {
    final existing = _pendingSave;
    if (existing != null) return existing.then(Uint8List.fromList);
    final raw = _openDocument;
    final future = _save(raw);
    _pendingSave = future;
    return future;
  }

  Future<Uint8List> _save(KdbxRawDocument raw) async {
    try {
      final data = await compute(_saveKeePass, raw);
      if (_disposed) throw const KeePassException(KeePassErrorCode.locked);
      return data;
    } catch (error) {
      throw _safeError(error);
    } finally {
      _pendingSave = null;
      if (_disposed) raw.dispose();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final raw = _document;
    _document = null;
    _groups.clear();
    _entries.clear();
    _entryGroups.clear();
    _groupInfo = const [];
    if (_pendingSave == null) raw?.dispose();
  }

  void _reindex() {
    final raw = _openDocument;
    final doc = raw.xml.rootElement;
    if (doc.findElements('Meta').length != 1 ||
        doc.findElements('Root').length != 1) {
      throw const KeePassException(KeePassErrorCode.corrupt);
    }
    final info = <KeePassGroupInfo>[];
    final seen = <String>{};
    void group(XmlElement node, String parentPath, int depth) {
      if (depth > 48 || seen.length >= _maxItems) {
        throw const KeePassException(KeePassErrorCode.resourceLimit);
      }
      final id = _id(node);
      if (!seen.add(id)) throw const KeePassException(KeePassErrorCode.corrupt);
      _groups[id] = node;
      final nameNode = node.getElement('Name');
      final name = nameNode == null ? '' : raw.textOf(nameNode);
      final path = parentPath.isEmpty ? name : '$parentPath / $name';
      info.add(KeePassGroupInfo(id: id, name: name, path: path));
      for (final child in node.childElements) {
        if (child.name.qualified == 'Group') {
          group(child, path, depth + 1);
        } else if (child.name.qualified == 'Entry') {
          final entryId = _id(child);
          if (!seen.add(entryId)) {
            throw const KeePassException(KeePassErrorCode.corrupt);
          }
          if (seen.length > _maxItems) {
            throw const KeePassException(KeePassErrorCode.resourceLimit);
          }
          _fieldNodes(child);
          _entries[entryId] = child;
          _entryGroups[entryId] = id;
        }
      }
    }

    for (final node in doc.getElement('Root')!.findElements('Group')) {
      group(node, '', 0);
    }
    if (info.isEmpty) throw const KeePassException(KeePassErrorCode.corrupt);
    _groupInfo = List.unmodifiable(info);
  }

  String _newId() {
    String id;
    do {
      id = KdbxUuid.random().string;
    } while (_groups.containsKey(id) || _entries.containsKey(id));
    return id;
  }

  String _now() =>
      KdbxTime(DateTime.now().toUtc())
          .toXmlText(isBinary: _openDocument.header.version.$1 >= 4)!;

  XmlElement _newTimes() {
    final now = _now();
    return XmlElement(XmlName('Times'), [], [
      for (final name in [
        'CreationTime',
        'LastModificationTime',
        'LastAccessTime',
        'ExpiryTime',
        'LocationChanged',
      ])
        _element(name, now),
      _element('Expires', 'False'),
      _element('UsageCount', '0'),
    ]);
  }

  void _touch(XmlElement entry, {bool location = false}) {
    final times = entry.getElement('Times') ?? XmlElement(XmlName('Times'));
    if (times.parent == null) entry.children.add(times);
    _setChild(times, 'LastModificationTime', _now());
    _setChild(times, 'LastAccessTime', _now());
    if (location) _setChild(times, 'LocationChanged', _now());
  }

  static void _setFields(
    KdbxRawDocument raw,
    XmlElement entry,
    KeePassEntryFields fields,
  ) {
    final nodes = _fieldNodes(entry);
    for (final field in fields._values.entries) {
      var value = nodes[field.key];
      if (value != null && raw.textOf(value) == field.value) continue;
      if (value == null) {
        value = XmlElement(XmlName('Value'));
        entry.children.add(
          XmlElement(XmlName('String'), [], [
            _element('Key', field.key),
            value,
          ]),
        );
      }
      raw.setText(
        value,
        field.value,
        protected: field.key == 'Password' ? true : null,
      );
    }
  }

  static Map<String, XmlElement> _fieldNodes(XmlElement entry) {
    final fields = <String, XmlElement>{};
    const standard = {'Title', 'UserName', 'Password', 'URL', 'Notes'};
    for (final field in entry.findElements('String')) {
      final key = field.getElement('Key')?.innerText;
      if (!standard.contains(key)) continue;
      final values = field.findElements('Value').toList();
      if (fields.containsKey(key) ||
          values.length != 1 ||
          field.findElements('Key').length != 1 ||
          values.single.children.any(
            (child) => child is! XmlText && child is! XmlCDATA,
          )) {
        throw const KeePassException(KeePassErrorCode.unsupported);
      }
      fields[key!] = values.single;
    }
    return fields;
  }

  static String _id(XmlElement node) {
    if (node.findElements('UUID').length != 1) {
      throw const KeePassException(KeePassErrorCode.corrupt);
    }
    final id = node.getElement('UUID')!.innerText;
    final decoded = base64.decode(id);
    if (decoded.length != 16 || base64.encode(decoded) != id) {
      throw const KeePassException(KeePassErrorCode.corrupt);
    }
    return id;
  }

  void _checkGrowth(KeePassEntryFields fields, {XmlElement? history}) {
    final raw = _openDocument;
    var added = 4096;
    for (final value in fields._values.values) {
      // Account for XML escaping and protected base64 expansion before changing
      // original values or creating a potentially large history snapshot.
      added += utf8.encode(XmlText(value).toXmlString()).length;
      added += ((utf8.encode(value).length + 2) ~/ 3) * 4;
    }
    if (history != null) added += raw.estimateHistorySnapshot(history);
    if (raw.estimatedBytes + added > kKeePassMaxFileBytes) {
      throw const KeePassException(KeePassErrorCode.resourceLimit);
    }
  }

  static void _validateFields(KeePassEntryFields fields) {
    for (final value in fields._values.values) {
      if (value.length > _maxFieldBytes ||
          utf8.encode(value).length > _maxFieldBytes) {
        throw const KeePassException(KeePassErrorCode.resourceLimit);
      }
      for (final rune in value.runes) {
        if (!(rune == 9 ||
            rune == 10 ||
            rune == 13 ||
            (rune >= 0x20 && rune <= 0xd7ff) ||
            (rune >= 0xe000 && rune <= 0xfffd) ||
            (rune >= 0x10000 && rune <= 0x10ffff))) {
          throw const KeePassException(KeePassErrorCode.unsupported);
        }
      }
    }
  }
}

XmlElement _element(String name, String text) =>
    XmlElement(XmlName(name))..innerText = text;

void _setChild(XmlElement node, String name, String text) {
  final element = node.getElement(name) ?? XmlElement(XmlName(name));
  if (element.parent == null) node.children.add(element);
  element.innerText = text;
}

typedef _UnlockRequest = ({
  Uint8List bytes,
  String? password,
  Uint8List? keyFile,
});

Future<KdbxRawDocument> _unlockKeePass(_UnlockRequest request) async {
  final password = request.password == null
      ? null
      : ProtectedData.fromString(request.password!);
  KdbxCredentials? credentials;
  try {
    credentials = KdbxCredentials(password: password, keyData: request.keyFile);
    return await KdbxRawDocument.open(
      data: request.bytes,
      credentials: credentials,
      validateHeader: _validateHeader,
      maxDecodedBytes: kKeePassMaxFileBytes,
    );
  } catch (error) {
    credentials?.dispose();
    throw _safeError(error);
  } finally {
    password?.dispose();
    final keyFile = request.keyFile;
    if (keyFile != null) keyFile.fillRange(0, keyFile.length, 0);
  }
}

Future<Uint8List> _saveKeePass(KdbxRawDocument document) async {
  try {
    _validateHeader(document.header);
    final data = await document.save(maxDecodedBytes: kKeePassMaxFileBytes);
    if (data.length > kKeePassMaxFileBytes) {
      throw const KeePassException(KeePassErrorCode.resourceLimit);
    }
    return data;
  } catch (error) {
    throw _safeError(error);
  }
}

void _validateHeader(KdbxHeader header) {
  final cipher = header.dataCipherUuid?.string;
  if (cipher != CipherId.aes && cipher != CipherId.chaCha20) {
    throw const KeePassException(KeePassErrorCode.unsupported);
  }
  if (header.masterSeed?.length != 32 ||
      header.encryptionIV?.length != (cipher == CipherId.aes ? 16 : 12)) {
    throw const KeePassException(KeePassErrorCode.corrupt);
  }
  void aesRounds(Object? rounds) {
    if (rounds is! int || rounds < 1) {
      throw const KeePassException(KeePassErrorCode.corrupt);
    }
    if (rounds > 2000000) {
      throw const KeePassException(KeePassErrorCode.resourceLimit);
    }
  }

  if (header.version.$1 == 3) {
    if (header.transformSeed?.length != 32 ||
        header.protectedStreamKey?.length != 32 ||
        header.streamStartBytes?.length != 32) {
      throw const KeePassException(KeePassErrorCode.corrupt);
    }
    if (header.crsAlgorithm != CrsAlgorithm.salsa20 &&
        header.crsAlgorithm != CrsAlgorithm.chaCha20) {
      throw const KeePassException(KeePassErrorCode.unsupported);
    }
    aesRounds(header.keyEncryptionRounds);
    return;
  }
  final parameters = header.kdfParameters;
  final uuid = parameters?.get(r'$UUID');
  final salt = parameters?.get('S');
  if (uuid is! List<int> ||
      uuid.length != 16 ||
      salt is! List<int> ||
      salt.length != 32) {
    throw const KeePassException(KeePassErrorCode.corrupt);
  }
  final kdf = base64.encode(uuid);
  if (kdf == KdfId.aes) {
    aesRounds(parameters?.get('R'));
    return;
  }
  if (kdf != KdfId.argon2d && kdf != KdfId.argon2id) {
    throw const KeePassException(KeePassErrorCode.unsupported);
  }
  if (parameters?.get('K') != null ||
      parameters?.get('A') != null ||
      !const {0x10, 0x13}.contains(parameters?.get('V'))) {
    throw const KeePassException(KeePassErrorCode.unsupported);
  }
  final memory = parameters?.get('M');
  final iterations = parameters?.get('I');
  final parallelism = parameters?.get('P');
  if (memory is! int ||
      memory < 1024 ||
      memory % 1024 != 0 ||
      iterations is! int ||
      iterations < 1 ||
      parallelism is! int ||
      parallelism < 1 ||
      memory ~/ 1024 < 8 * parallelism) {
    throw const KeePassException(KeePassErrorCode.corrupt);
  }
  const maxMemory = kIsWeb ? 16 * 1024 * 1024 : 64 * 1024 * 1024;
  const maxWork = kIsWeb ? 32 * 1024 * 1024 : 256 * 1024 * 1024;
  if (memory > maxMemory ||
      iterations > 10 ||
      parallelism > 16 ||
      memory * iterations > maxWork) {
    throw const KeePassException(KeePassErrorCode.resourceLimit);
  }
}

KeePassException _safeError(Object error) {
  if (error is KeePassException) return error;
  if (error is InvalidCredentialsError) {
    return const KeePassException(KeePassErrorCode.invalidCredentials);
  }
  if (error is UnsupportedValueError) {
    return const KeePassException(KeePassErrorCode.unsupported);
  }
  if (error is ResourceLimitError || error is ArchiveLimitException) {
    return const KeePassException(KeePassErrorCode.resourceLimit);
  }
  return const KeePassException(KeePassErrorCode.corrupt);
}
