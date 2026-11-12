import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:xml/xml.dart';

const int kKeePassMaxFileBytes = 32 * 1024 * 1024;
const int kKeePassMaxKeyFileBytes = 1024 * 1024;
const int _maxFieldBytes = 1024 * 1024;
const int _maxItems = 20000;
const int kKeePassMaxCustomFields = 256;
const int kKeePassMaxHistoryItems = 2048;
const _standardFields = {'Title', 'UserName', 'Password', 'URL', 'Notes'};

enum KeePassErrorCode {
  invalidCredentials,
  unsupported,
  corrupt,
  resourceLimit,
  locked,
  invalidOperation,
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
    KeePassErrorCode.invalidOperation =>
      'The requested KeePass change is not valid.',
  };
}

class KeePassGroupInfo {
  const KeePassGroupInfo({
    required this.id,
    required this.name,
    required this.path,
    this.parentId,
    this.isRoot = false,
    this.isRecycleBin = false,
    this.isRecycled = false,
  });
  final String id;
  final String name;
  final String path;
  final String? parentId;
  final bool isRoot;
  final bool isRecycleBin;
  final bool isRecycled;
}

/// The original key identifies an existing XML field when its name is edited.
/// Unknown attributes/children on that String node remain with the same field.
class KeePassCustomField {
  const KeePassCustomField({
    required this.name,
    required this.value,
    this.isProtected = true,
    this.originalName,
  });
  final String name;
  final String value;
  final bool isProtected;
  final String? originalName;
}

class KeePassHistoryInfo {
  const KeePassHistoryInfo({
    required this.index,
    required this.title,
    required this.userName,
    this.modifiedAt,
  });
  final int index;
  final String title;
  final String userName;
  final DateTime? modifiedAt;
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
    final recycle = _recycleEnabled ? _recycleGroup : null;
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
    return _fieldsOf(_entry(id));
  }

  KeePassEntryFields _fieldsOf(XmlElement entry) {
    final raw = _openDocument;
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
    List<KeePassCustomField> customFields = const [],
  }) {
    _checkMutable();
    final raw = _openDocument;
    final group = _groups[groupId];
    if (group == null) throw const KeePassException(KeePassErrorCode.corrupt);
    _validateFields(fields);
    _validateCustomFields(customFields);
    _checkGrowth(fields, customFields: customFields);
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
    _setCustomFields(entry, customFields);
    group.children.add(entry);
    _entries[id] = entry;
    _entryGroups[id] = groupId;
    return id;
  }

  void updateEntry(
    String id,
    KeePassEntryFields fields, {
    List<KeePassCustomField>? customFields,
    String? groupId,
  }) {
    _checkMutable();
    _validateFields(fields);
    final raw = _openDocument;
    final entry = _entries[id];
    if (entry == null) throw const KeePassException(KeePassErrorCode.corrupt);
    final destination = groupId == null ? null : _group(groupId);
    final moving = destination != null && groupId != _entryGroups[id];
    if (moving) _validateEntryMove(entry, destination);
    if (customFields != null) {
      _validateCustomFields(customFields, existing: entry);
    }
    final old = entryFields(id)._values;
    final changed =
        !fields._values.entries.every(
          (value) => old[value.key] == value.value,
        ) ||
        (customFields != null && _customFieldsChanged(entry, customFields));
    if (changed) {
      _validateTouch(entry);
      _checkGrowth(fields, history: entry, customFields: customFields);
      _appendHistory(entry);
      _setFields(raw, entry, fields);
      if (customFields != null) _setCustomFields(entry, customFields);
      _touch(entry);
    }
    if (moving) {
      if (!changed) _checkCapacity(bytes: 4096, events: 64);
      _moveEntry(entry, destination, groupId!);
    }
  }

  String addGroup({required String parentId, required String name}) {
    _checkMutable();
    _validateName(name);
    final parent = _group(parentId);
    if (_groups.length + _entries.length >= _maxItems ||
        _groupDepth(parent) >= 48 ||
        _xmlDepth(parent) + 4 > 64) {
      throw const KeePassException(KeePassErrorCode.resourceLimit);
    }
    _checkCapacity(bytes: 4096 + utf8.encode(name).length * 6, events: 64);
    final id = _newId();
    parent.children.add(
      XmlElement(XmlName('Group'), [], [
        _element('UUID', id),
        _element('Name', name),
        _element('IconID', '48'),
        _newTimes(),
        _element('IsExpanded', 'True'),
      ]),
    );
    _reindex();
    return id;
  }

  void renameGroup(String id, String name) {
    _checkMutable();
    _validateName(name);
    final group = _group(id);
    final value = _singleText(group, 'Name');
    if (value != null && _openDocument.textOf(value) == name) return;
    _validateTouch(group);
    _checkCapacity(bytes: 4096 + utf8.encode(name).length * 6, events: 64);
    _setValue(group, 'Name', name);
    _touch(group);
    _reindex();
  }

  void moveGroup(String id, String parentId) {
    _checkMutable();
    final group = _group(id);
    final parent = _group(parentId);
    _validateGroupMove(group, parent);
    if (identical(group.parent, parent)) return;
    _checkCapacity(bytes: 4096, events: 64);
    _moveGroup(group, parent);
    _reindex();
  }

  void moveEntry(String id, String groupId) {
    _checkMutable();
    final entry = _entry(id);
    final group = _group(groupId);
    if (_entryGroups[id] == groupId) return;
    _validateEntryMove(entry, group);
    _checkCapacity(bytes: 4096, events: 64);
    _moveEntry(entry, group, groupId);
  }

  /// Deleting outside the recycle bin moves the complete subtree there. A
  /// second deletion, or disabled recycling, records every removed active UUID.
  void deleteGroup(String id) {
    _checkMutable();
    final group = _group(id);
    final recycle = _recycleGroup;
    if (_isRoot(group) ||
        identical(group, recycle) ||
        (recycle != null && recycle.ancestors.contains(group))) {
      throw const KeePassException(KeePassErrorCode.invalidOperation);
    }
    if (_recycleEnabled &&
        (recycle == null || !group.ancestors.contains(recycle))) {
      if (recycle != null) {
        _validateGroupMove(group, recycle);
      } else {
        _validateTouch(group);
        _singleText(group, 'PreviousParentGroup');
        final root = _groups[_groupInfo.first.id]!;
        _checkGroupPlacement(
          group,
          parentGroupDepth: _groupDepth(root) + 1,
          parentXmlDepth: _xmlDepth(root) + 1,
        );
        _validateRecycleCreation();
      }
      _checkCapacity(bytes: 8192, events: 128);
      _moveGroup(group, recycle ?? _createRecycleBin());
    } else {
      final removed = <String>[
        for (final item in _groups.entries)
          if (identical(item.value, group) ||
              item.value.ancestors.contains(group))
            item.key,
        for (final item in _entries.entries)
          if (item.value.ancestors.contains(group)) item.key,
      ];
      _deleteObjects(group, removed);
    }
    _reindex();
  }

  void deleteEntry(String id) {
    _checkMutable();
    final entry = _entry(id);
    var recycle = _recycleGroup;
    if (_recycleEnabled &&
        (recycle == null || !entry.ancestors.contains(recycle))) {
      if (recycle != null) {
        _validateEntryMove(entry, recycle);
      } else {
        _validateTouch(entry);
        _singleText(entry, 'PreviousParentGroup');
        final root = _groups[_groupInfo.first.id]!;
        if (_xmlDepth(root) + 1 + _subtreeDepth(entry) > 64) {
          throw const KeePassException(KeePassErrorCode.resourceLimit);
        }
        _validateRecycleCreation();
      }
      _checkCapacity(bytes: 8192, events: 128);
      recycle ??= _createRecycleBin();
      _moveEntry(entry, recycle, _id(recycle));
      _reindex();
    } else {
      _deleteObjects(entry, [id]);
      _entries.remove(id);
      _entryGroups.remove(id);
    }
  }

  List<KeePassCustomField> customFields(String id) =>
      _customFieldsOf(_entry(id));

  List<KeePassCustomField> _customFieldsOf(XmlElement entry) {
    final raw = _openDocument;
    final fields = _fieldNodes(entry, includeCustom: true);
    final custom = fields.entries.where(
      (item) => !_standardFields.contains(item.key),
    );
    if (custom.length > kKeePassMaxCustomFields) {
      throw const KeePassException(KeePassErrorCode.resourceLimit);
    }
    return List.unmodifiable(
      custom.map(
        (field) => KeePassCustomField(
          name: field.key,
          originalName: field.key,
          value: raw.textOf(field.value),
          isProtected: raw.isProtected(field.value),
        ),
      ),
    );
  }

  List<KeePassHistoryInfo> entryHistory(String id) {
    final raw = _openDocument;
    final records = _historyRecords(_entry(id));
    return List.unmodifiable([
      for (var index = 0; index < records.length; index++)
        KeePassHistoryInfo(
          index: index,
          title: _fieldsOf(records[index]).title,
          userName: _fieldsOf(records[index]).userName,
          modifiedAt: KdbxTime.fromXmlText(
            text:
                records[index]
                    .getElement('Times')
                    ?.getElement('LastModificationTime')
                    ?.innerText ??
                '',
            isBinary: raw.header.version.$1 >= 4,
          ).time,
        ),
    ]);
  }

  KeePassEntryFields historyFields(String id, int index) =>
      _fieldsOf(_historyRecord(id, index));

  List<KeePassCustomField> historyCustomFields(String id, int index) =>
      _customFieldsOf(_historyRecord(id, index));

  /// Restore the complete snapshot, including opaque fields and attachments.
  /// The current entry becomes a new history record; existing history and the
  /// entry's UUID/current group remain intact.
  void restoreEntryHistory(String id, int index) {
    _checkMutable();
    final raw = _openDocument;
    final entry = _entry(id);
    final historical = _historyRecord(id, index);
    if (_id(historical) != id ||
        historical.findElements('History').isNotEmpty) {
      throw const KeePassException(KeePassErrorCode.unsupported);
    }
    _fieldNodes(historical, includeCustom: true);
    _validateTouch(historical);
    _singleText(entry, 'PreviousParentGroup');
    _singleText(historical, 'PreviousParentGroup');
    final oldLocation = entry
        .getElement('Times')
        ?.getElement('LocationChanged');
    if (oldLocation != null) {
      _singleText(entry.getElement('Times')!, 'LocationChanged');
    }
    final records = _historyRecords(entry);
    if (records.length >= kKeePassMaxHistoryItems) {
      throw const KeePassException(KeePassErrorCode.resourceLimit);
    }
    _checkCapacity(
      bytes:
          raw.estimateHistorySnapshot(entry) +
          raw.estimateHistorySnapshot(historical) +
          4096,
      events: _snapshotEvents(entry) + _eventCount(historical) + 64,
    );
    final restored = raw.cloneElement(historical, omitHistory: true);
    final previous = raw.cloneElement(entry, omitHistory: true);
    final oldParent = entry.getElement('PreviousParentGroup');
    final restoredParent = restored.getElement('PreviousParentGroup');
    if (restoredParent != null) {
      restored.children.remove(restoredParent);
      raw.forgetElement(restoredParent);
    }
    if (oldParent != null) restored.children.add(raw.cloneElement(oldParent));
    final times = restored.getElement('Times') ?? XmlElement(XmlName('Times'));
    if (times.parent == null) restored.children.add(times);
    final restoredLocation = times.getElement('LocationChanged');
    if (restoredLocation != null) {
      times.children.remove(restoredLocation);
      raw.forgetElement(restoredLocation);
    }
    if (oldLocation != null) times.children.add(raw.cloneElement(oldLocation));
    final history =
        entry.getElement('History') ?? XmlElement(XmlName('History'));
    entry.children.remove(history);
    history.children.add(previous);
    restored.children.add(history);
    _touch(restored);
    final parent = entry.parent!;
    parent.children[parent.children.indexOf(entry)] = restored;
    raw.forgetElement(entry);
    _entries[id] = restored;
  }

  XmlElement _entry(String id) {
    _openDocument;
    final entry = _entries[id];
    if (entry == null) {
      throw const KeePassException(KeePassErrorCode.invalidOperation);
    }
    return entry;
  }

  XmlElement _group(String id) {
    _openDocument;
    final group = _groups[id];
    if (group == null) {
      throw const KeePassException(KeePassErrorCode.invalidOperation);
    }
    return group;
  }

  List<XmlElement> _historyRecords(XmlElement entry) {
    if (entry.findElements('History').length > 1) {
      throw const KeePassException(KeePassErrorCode.unsupported);
    }
    final records =
        entry.getElement('History')?.findElements('Entry').toList() ??
        <XmlElement>[];
    if (records.length > kKeePassMaxHistoryItems) {
      throw const KeePassException(KeePassErrorCode.resourceLimit);
    }
    return records;
  }

  XmlElement _historyRecord(String id, int index) {
    final records = _historyRecords(_entry(id));
    if (index < 0 || index >= records.length) {
      throw const KeePassException(KeePassErrorCode.invalidOperation);
    }
    return records[index];
  }

  void _appendHistory(XmlElement entry) {
    if (_historyRecords(entry).length >= kKeePassMaxHistoryItems) {
      throw const KeePassException(KeePassErrorCode.resourceLimit);
    }
    final history =
        entry.getElement('History') ?? XmlElement(XmlName('History'));
    final snapshot = _openDocument.cloneElement(entry, omitHistory: true);
    if (history.parent == null) entry.children.add(history);
    history.children.add(snapshot);
  }

  bool _customFieldsChanged(XmlElement entry, List<KeePassCustomField> fields) {
    final old = {for (final value in _customFieldsOf(entry)) value.name: value};
    return old.length != fields.length ||
        fields.any((field) {
          final previous = old[field.name];
          return previous == null ||
              previous.value != field.value ||
              previous.isProtected != field.isProtected ||
              (field.originalName != null && field.originalName != field.name);
        });
  }

  void _validateCustomFields(
    List<KeePassCustomField> fields, {
    XmlElement? existing,
  }) {
    if (fields.length > kKeePassMaxCustomFields) {
      throw const KeePassException(KeePassErrorCode.resourceLimit);
    }
    final old = existing == null
        ? <String, XmlElement>{}
        : _fieldNodes(existing, includeCustom: true);
    final names = <String>{};
    final origins = <String>{};
    for (final field in fields) {
      _validateName(field.name);
      _validateText(field.value);
      if (_standardFields.contains(field.name) || !names.add(field.name)) {
        throw const KeePassException(KeePassErrorCode.invalidOperation);
      }
      final origin = field.originalName ?? field.name;
      if (_standardFields.contains(origin) ||
          !origins.add(origin) ||
          (existing != null &&
              field.originalName != null &&
              !old.containsKey(origin))) {
        throw const KeePassException(KeePassErrorCode.invalidOperation);
      }
    }
  }

  void _setCustomFields(XmlElement entry, List<KeePassCustomField> fields) {
    final raw = _openDocument;
    final old = _fieldNodes(entry, includeCustom: true);
    final retained = <XmlElement>{};
    for (final field in fields) {
      var value = old[field.originalName ?? field.name];
      if (value == null) {
        value = XmlElement(XmlName('Value'));
        entry.children.add(
          XmlElement(XmlName('String'), [], [
            _element('Key', field.name),
            value,
          ]),
        );
      } else {
        retained.add(value);
        final key = (value.parent! as XmlElement).getElement('Key')!;
        if (key.innerText != field.name) raw.setText(key, field.name);
      }
      if (raw.textOf(value) != field.value ||
          raw.isProtected(value) != field.isProtected) {
        raw.setText(value, field.value, protected: field.isProtected);
      }
    }
    for (final field in old.entries) {
      if (_standardFields.contains(field.key) ||
          retained.contains(field.value)) {
        continue;
      }
      final node = field.value.parent! as XmlElement;
      entry.children.remove(node);
      raw.forgetElement(node);
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
    final groups = <String, XmlElement>{};
    final entries = <String, XmlElement>{};
    final entryGroups = <String, String>{};
    final recycleId = doc
        .getElement('Meta')!
        .getElement('RecycleBinUUID')
        ?.innerText;
    void group(
      XmlElement node,
      String parentPath,
      String? parentId,
      int depth,
      bool recycled,
    ) {
      if (depth > 48 || seen.length >= _maxItems) {
        throw const KeePassException(KeePassErrorCode.resourceLimit);
      }
      final id = _id(node);
      if (!seen.add(id)) throw const KeePassException(KeePassErrorCode.corrupt);
      groups[id] = node;
      final nameNode = _singleText(node, 'Name');
      final name = nameNode == null ? '' : raw.textOf(nameNode);
      final path = parentPath.isEmpty ? name : '$parentPath / $name';
      final isRecycled = recycled || (_recycleEnabled && id == recycleId);
      if (parentId == null && id == recycleId && _recycleEnabled) {
        throw const KeePassException(KeePassErrorCode.unsupported);
      }
      info.add(
        KeePassGroupInfo(
          id: id,
          name: name,
          path: path,
          parentId: parentId,
          isRoot: parentId == null,
          isRecycleBin: id == recycleId,
          isRecycled: isRecycled,
        ),
      );
      for (final child in node.childElements) {
        if (child.name.qualified == 'Group') {
          group(child, path, id, depth + 1, isRecycled);
        } else if (child.name.qualified == 'Entry') {
          final entryId = _id(child);
          if (!seen.add(entryId)) {
            throw const KeePassException(KeePassErrorCode.corrupt);
          }
          if (seen.length > _maxItems) {
            throw const KeePassException(KeePassErrorCode.resourceLimit);
          }
          _fieldNodes(child);
          entries[entryId] = child;
          entryGroups[entryId] = id;
        }
      }
    }

    for (final node in doc.getElement('Root')!.findElements('Group')) {
      group(node, '', null, 0, false);
    }
    if (info.isEmpty) throw const KeePassException(KeePassErrorCode.corrupt);
    _groups
      ..clear()
      ..addAll(groups);
    _entries
      ..clear()
      ..addAll(entries);
    _entryGroups
      ..clear()
      ..addAll(entryGroups);
    _groupInfo = List.unmodifiable(info);
  }

  bool get _recycleEnabled =>
      _openDocument.xml.rootElement
          .getElement('Meta')!
          .getElement('RecycleBinEnabled')
          ?.innerText
          .toLowerCase() ==
      'true';

  XmlElement? get _recycleGroup {
    final id = _openDocument.xml.rootElement
        .getElement('Meta')!
        .getElement('RecycleBinUUID')
        ?.innerText;
    return _groups[id];
  }

  static bool _isRoot(XmlElement group) =>
      group.parent is XmlElement &&
      (group.parent! as XmlElement).name.qualified == 'Root';

  static int _xmlDepth(XmlElement node) =>
      node.ancestors.whereType<XmlElement>().length + 1;

  static int _groupDepth(XmlElement node) => node.ancestors
      .whereType<XmlElement>()
      .where((item) => item.name.qualified == 'Group')
      .length;

  static int _subtreeDepth(XmlElement node) {
    var depth = 1;
    for (final child in node.childElements) {
      final nested = 1 + _subtreeDepth(child);
      if (nested > depth) depth = nested;
    }
    return depth;
  }

  void _checkGroupPlacement(
    XmlElement group, {
    required int parentGroupDepth,
    required int parentXmlDepth,
  }) {
    int height(XmlElement node) {
      var result = 0;
      for (final child in node.findElements('Group')) {
        final next = 1 + height(child);
        if (next > result) result = next;
      }
      return result;
    }

    if (parentGroupDepth + 1 + height(group) > 48 ||
        parentXmlDepth + _subtreeDepth(group) > 64) {
      throw const KeePassException(KeePassErrorCode.resourceLimit);
    }
  }

  void _validateGroupMove(XmlElement group, XmlElement parent) {
    if (_isRoot(group) ||
        identical(group, _recycleGroup) ||
        identical(group, parent) ||
        parent.ancestors.contains(group)) {
      throw const KeePassException(KeePassErrorCode.invalidOperation);
    }
    _validateTouch(group);
    _singleText(group, 'PreviousParentGroup');
    _checkGroupPlacement(
      group,
      parentGroupDepth: _groupDepth(parent),
      parentXmlDepth: _xmlDepth(parent),
    );
  }

  void _validateEntryMove(XmlElement entry, XmlElement group) {
    _validateTouch(entry);
    _singleText(entry, 'PreviousParentGroup');
    if (_xmlDepth(group) + _subtreeDepth(entry) > 64) {
      throw const KeePassException(KeePassErrorCode.resourceLimit);
    }
  }

  void _moveGroup(XmlElement group, XmlElement parent) {
    final previous = _id(group.parent! as XmlElement);
    group.parent!.children.remove(group);
    parent.children.add(group);
    _setValue(group, 'PreviousParentGroup', previous);
    _touch(group, location: true);
  }

  void _moveEntry(XmlElement entry, XmlElement group, String groupId) {
    final id = _id(entry);
    final previous = _entryGroups[id]!;
    entry.parent!.children.remove(entry);
    group.children.add(entry);
    _setValue(entry, 'PreviousParentGroup', previous);
    _touch(entry, location: true);
    _entryGroups[id] = groupId;
  }

  void _validateRecycleCreation() {
    if (_groups.length + _entries.length >= _maxItems) {
      throw const KeePassException(KeePassErrorCode.resourceLimit);
    }
    final meta = _openDocument.xml.rootElement.getElement('Meta')!;
    _singleText(meta, 'RecycleBinUUID');
    _singleText(meta, 'RecycleBinChanged');
  }

  XmlElement _createRecycleBin() {
    final root = _groups[_groupInfo.first.id]!;
    final id = _newId();
    final recycle = XmlElement(XmlName('Group'), [], [
      _element('UUID', id),
      _element('Name', 'Recycle Bin'),
      _element('IconID', '43'),
      _newTimes(),
      _element('EnableSearching', 'False'),
      _element('EnableAutoType', 'False'),
    ]);
    root.children.add(recycle);
    _groups[id] = recycle;
    final meta = _openDocument.xml.rootElement.getElement('Meta')!;
    _setValue(meta, 'RecycleBinUUID', id);
    _setValue(meta, 'RecycleBinChanged', _now());
    return recycle;
  }

  void _deleteObjects(XmlElement subtree, List<String> ids) {
    final raw = _openDocument;
    final root = raw.xml.rootElement.getElement('Root')!;
    if (root.findElements('DeletedObjects').length > 1) {
      throw const KeePassException(KeePassErrorCode.unsupported);
    }
    final deleted =
        root.getElement('DeletedObjects') ??
        XmlElement(XmlName('DeletedObjects'));
    final existing = <String, XmlElement>{};
    for (final node in deleted.findElements('DeletedObject')) {
      final id = _id(node);
      if (existing.containsKey(id)) {
        throw const KeePassException(KeePassErrorCode.unsupported);
      }
      existing[id] = node;
    }
    for (final id in ids) {
      if (existing[id] case final node?) _singleText(node, 'DeletionTime');
    }
    final netBytes = ids.length * 256 - raw.estimateHistorySnapshot(subtree);
    final netEvents = ids.length * 8 - _eventCount(subtree);
    _checkCapacity(
      bytes: netBytes > 0 ? netBytes + 4096 : 4096,
      events: netEvents > 0 ? netEvents + 32 : 32,
    );
    final meta = raw.xml.rootElement.getElement('Meta')!;
    final reset = <String>[];
    for (final name in [
      'EntryTemplatesGroup',
      'LastSelectedGroup',
      'LastTopVisibleGroup',
    ]) {
      final value = _singleText(meta, name);
      if (value != null && ids.contains(raw.textOf(value))) reset.add(name);
    }
    if (reset.contains('EntryTemplatesGroup')) {
      _singleText(meta, 'EntryTemplatesGroupChanged');
    }
    if (deleted.parent == null) root.children.add(deleted);
    final now = _now();
    for (final id in ids) {
      final node = existing[id];
      if (node == null) {
        deleted.children.add(
          XmlElement(XmlName('DeletedObject'), [], [
            _element('UUID', id),
            _element('DeletionTime', now),
          ]),
        );
      } else {
        _setValue(node, 'DeletionTime', now);
      }
    }
    for (final name in reset) {
      _setValue(
        meta,
        name,
        name == 'EntryTemplatesGroup'
            ? 'AAAAAAAAAAAAAAAAAAAAAA=='
            : _groupInfo.first.id,
      );
    }
    if (reset.contains('EntryTemplatesGroup')) {
      _setValue(meta, 'EntryTemplatesGroupChanged', now);
    }
    subtree.parent!.children.remove(subtree);
    raw.forgetElement(subtree);
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
    _setValue(times, 'LastModificationTime', _now());
    _setValue(times, 'LastAccessTime', _now());
    if (location) _setValue(times, 'LocationChanged', _now());
  }

  static XmlElement? _singleText(XmlElement parent, String name) {
    final values = parent.findElements(name).toList();
    if (values.length > 1 ||
        (values.isNotEmpty &&
            values.single.children.any(
              (node) => node is! XmlText && node is! XmlCDATA,
            ))) {
      throw const KeePassException(KeePassErrorCode.unsupported);
    }
    return values.isEmpty ? null : values.single;
  }

  static void _validateTouch(XmlElement item) {
    if (item.findElements('Times').length > 1) {
      throw const KeePassException(KeePassErrorCode.unsupported);
    }
    final times = item.getElement('Times');
    if (times == null) return;
    for (final field in [
      'LastModificationTime',
      'LastAccessTime',
      'LocationChanged',
    ]) {
      _singleText(times, field);
    }
  }

  void _setValue(XmlElement node, String name, String text) {
    final element = _singleText(node, name) ?? XmlElement(XmlName(name));
    if (element.parent == null) node.children.add(element);
    _openDocument.setText(element, text);
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

  static Map<String, XmlElement> _fieldNodes(
    XmlElement entry, {
    bool includeCustom = false,
  }) {
    final fields = <String, XmlElement>{};
    for (final field in entry.findElements('String')) {
      final key = field.getElement('Key')?.innerText;
      if (!includeCustom && !_standardFields.contains(key)) continue;
      final values = field.findElements('Value').toList();
      final keyNode = field.getElement('Key');
      if (key == null ||
          fields.containsKey(key) ||
          values.length != 1 ||
          field.findElements('Key').length != 1 ||
          keyNode!.children.any(
            (child) => child is! XmlText && child is! XmlCDATA,
          ) ||
          keyNode.getAttribute('Protected')?.toLowerCase() == 'true' ||
          values.single.children.any(
            (child) => child is! XmlText && child is! XmlCDATA,
          )) {
        throw const KeePassException(KeePassErrorCode.unsupported);
      }
      fields[key] = values.single;
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

  void _checkGrowth(
    KeePassEntryFields fields, {
    XmlElement? history,
    List<KeePassCustomField>? customFields,
  }) {
    final raw = _openDocument;
    var added = 4096;
    for (final value in [
      ...fields._values.values,
      for (final field in customFields ?? const <KeePassCustomField>[]) ...[
        field.name,
        field.value,
      ],
    ]) {
      // Account for XML escaping and protected base64 expansion before changing
      // original values or creating a potentially large history snapshot.
      added += utf8.encode(XmlText(value).toXmlString()).length;
      added += ((utf8.encode(value).length + 2) ~/ 3) * 4;
    }
    if (history != null) added += raw.estimateHistorySnapshot(history);
    _checkCapacity(
      bytes: added,
      events:
          128 +
          (customFields?.length ?? 0) * 8 +
          (history == null ? 0 : _snapshotEvents(history)),
    );
  }

  int _eventCount(XmlNode node) {
    var total = node is XmlDocument
        ? 0
        : node is XmlElement
        ? 2
        : 1;
    if (node is XmlElement && _openDocument.isProtected(node)) total++;
    for (final child in node.children) {
      total += _eventCount(child);
    }
    return total;
  }

  int _snapshotEvents(XmlElement entry) =>
      2 +
      entry.children
          .where(
            (node) => node is! XmlElement || node.name.qualified != 'History',
          )
          .fold<int>(0, (total, node) => total + _eventCount(node));

  void _checkCapacity({required int bytes, required int events}) {
    final raw = _openDocument;
    if (raw.estimatedBytes + bytes > kKeePassMaxFileBytes ||
        _eventCount(raw.xml) + events > 200000) {
      throw const KeePassException(KeePassErrorCode.resourceLimit);
    }
  }

  static void _validateFields(KeePassEntryFields fields) {
    for (final value in fields._values.values) {
      _validateText(value);
    }
  }

  static void _validateName(String value) {
    if (value.trim().isEmpty) {
      throw const KeePassException(KeePassErrorCode.invalidOperation);
    }
    if (value.length > 1024 || utf8.encode(value).length > 1024) {
      throw const KeePassException(KeePassErrorCode.resourceLimit);
    }
    _validateText(value);
  }

  static void _validateText(String value) {
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

XmlElement _element(String name, String text) =>
    XmlElement(XmlName(name))..innerText = text;

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
