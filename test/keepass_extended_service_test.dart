import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/keepass_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:xml/xml.dart';

Uint8List _fixture(String name) => base64.decode(
  File('test/fixtures/keepass/$name.b64')
      .readAsStringSync()
      .replaceAll(RegExp(r'\s'), ''),
);

Future<KeePassSession> _open([Uint8List? bytes]) async {
  final session = await KeePassSession.open(
    bytes ?? _fixture('demo.kdbx'),
    password: 'demo',
    keyFile: _fixture('demo.key'),
  );
  addTearDown(session.dispose);
  return session;
}

Future<KdbxRawDocument> _raw(Uint8List bytes) async {
  final password = ProtectedData.fromString('demo');
  final credentials = KdbxCredentials(
    password: password,
    keyData: _fixture('demo.key'),
  );
  password.dispose();
  final raw = await KdbxRawDocument.open(
    data: bytes,
    credentials: credentials,
    validateHeader: (_) {},
  );
  addTearDown(raw.dispose);
  return raw;
}

XmlElement _node(KdbxRawDocument raw, String kind, String id) =>
    raw.xml.descendants.whereType<XmlElement>().firstWhere(
      (node) =>
          node.name.qualified == kind &&
          node.getElement('UUID')?.innerText == id,
    );

Matcher _error(KeePassErrorCode code) =>
    isA<KeePassException>().having((error) => error.code, 'code', code);

void main() {
  test('combined edits and moves reject excessive history depth before any mutation', () async {
    final raw = await _raw(_fixture('demo.kdbx'));
    const id = 'vqcoCvE9/k6PSgutKI6snw==';
    final entry = _node(raw, 'Entry', id);
    var node = entry;
    while (node.ancestors.whereType<XmlElement>().length + 1 < 61) {
      final child = XmlElement(XmlName('FutureNested'));
      node.children.add(child);
      node = child;
    }
    node.innerText = 'preserve deep opaque data';
    final session = await _open(await raw.save());
    final original = session.entryFields(id);
    final oldGroup = session.entries
        .firstWhere((item) => item.id == id)
        .groupId;
    final historyCount = session.entryHistory(id).length;
    var group = session.groups.first.id;
    for (var index = 0; index < 4; index++) {
      group = session.addGroup(parentId: group, name: 'Destination $index');
    }
    expect(
      () => session.updateEntry(
        id,
        const KeePassEntryFields(title: 'Rejected'),
        groupId: group,
      ),
      throwsA(_error(KeePassErrorCode.resourceLimit)),
    );
    expect(session.entryFields(id).title, original.title);
    expect(session.entryHistory(id).length, historyCount);
    expect(
      session.entries.firstWhere((item) => item.id == id).groupId,
      oldGroup,
    );
    await _open(await session.save());
  });

  test('disabled recycling deletes complete subtrees and clears known group references', () async {
    final initial = await _open();
    final group = initial.addGroup(
      parentId: initial.groups.first.id,
      name: 'Templates',
    );
    final child = initial.addGroup(parentId: group, name: 'Nested');
    final id = initial.addEntry(
      groupId: child,
      fields: const KeePassEntryFields(title: 'Deleted'),
    );
    final raw = await _raw(await initial.save());
    final meta = raw.xml.rootElement.getElement('Meta')!;
    meta.getElement('RecycleBinEnabled')!.innerText = 'False';
    for (final name in [
      'EntryTemplatesGroup',
      'LastSelectedGroup',
      'LastTopVisibleGroup',
    ]) {
      final value = meta.getElement(name) ?? XmlElement(XmlName(name));
      if (value.parent == null) meta.children.add(value);
      value.innerText = group;
    }
    final session = await _open(await raw.save());
    session.deleteGroup(group);
    expect(
      session.groups.where((item) => item.id == group || item.id == child),
      isEmpty,
    );
    expect(session.entries.where((item) => item.id == id), isEmpty);
    final saved = await _raw(await session.save());
    expect(
      saved.xml.rootElement
          .getElement('Meta')!
          .getElement('EntryTemplatesGroup')!
          .innerText,
      'AAAAAAAAAAAAAAAAAAAAAA==',
    );
    final deleted = saved.xml.rootElement
        .getElement('Root')!
        .getElement('DeletedObjects')!
        .findElements('DeletedObject')
        .map((item) => item.getElement('UUID')!.innerText);
    expect(deleted, containsAll([group, child, id]));
  });

  test('group creation, rename, subtree moves and entry moves survive encrypted save', () async {
    final session = await _open();
    final root = session.groups.first;
    final first = session.addGroup(parentId: root.id, name: '日本語 Work');
    final child = session.addGroup(parentId: first, name: 'Accounts');
    final other = session.addGroup(parentId: root.id, name: 'Personal');
    final entry = session.addEntry(
      groupId: child,
      fields: const KeePassEntryFields(
        title: 'Private',
        password: 'move-secret',
      ),
    );
    session.renameGroup(first, 'Renamed');
    expect(
      session.groups.firstWhere((group) => group.id == child).path,
      endsWith('Renamed / Accounts'),
    );
    session.moveGroup(first, other);
    session.moveEntry(entry, other);
    final bytes = await session.save();
    final reopened = await _open(bytes);
    expect(
      reopened.groups.firstWhere((group) => group.id == first).parentId,
      other,
    );
    expect(
      reopened.groups.firstWhere((group) => group.id == child).path,
      endsWith('Personal / Renamed / Accounts'),
    );
    expect(
      reopened.entries.firstWhere((item) => item.id == entry).groupId,
      other,
    );
    expect(reopened.entryFields(entry).password, 'move-secret');
    expect(
      utf8.decode(bytes, allowMalformed: true),
      isNot(contains('move-secret')),
    );
    final raw = await _raw(bytes);
    expect(
      _node(raw, 'Group', first).getElement('PreviousParentGroup')!.innerText,
      root.id,
    );
    expect(
      _node(raw, 'Entry', entry).getElement('PreviousParentGroup')!.innerText,
      child,
    );
  });

  test(
    'root, recycle bin, cycles and invalid destinations cannot be changed',
    () async {
      final session = await _open();
      final root = session.groups.first.id;
      final first = session.addGroup(parentId: root, name: 'First');
      final child = session.addGroup(parentId: first, name: 'Child');
      final entry = session.addEntry(
        groupId: child,
        fields: const KeePassEntryFields(title: 'Before'),
      );
      session.deleteEntry(entry);
      final recycle = session.groups.firstWhere((group) => group.isRecycleBin);
      for (final operation in <void Function()>[
        () => session.moveGroup(root, first),
        () => session.deleteGroup(root),
        () => session.moveGroup(first, child),
        () => session.moveGroup(first, first),
        () => session.moveGroup(recycle.id, first),
        () => session.deleteGroup(recycle.id),
        () => session.moveEntry(entry, 'missing'),
        () => session.renameGroup(first, '  '),
        () => session.updateEntry(
          entry,
          const KeePassEntryFields(title: 'Must not change'),
          groupId: 'missing',
        ),
      ]) {
        expect(operation, throwsA(_error(KeePassErrorCode.invalidOperation)));
      }
      expect(session.entryFields(entry).title, 'Before');
      expect(
        session.groups.firstWhere((group) => group.id == first).parentId,
        root,
      );
      final reopened = await _open(await session.save());
      expect(
        reopened.groups.firstWhere((group) => group.id == child).parentId,
        first,
      );
    },
  );

  test('recycled group subtrees are restored by moving and tombstoned on permanent deletion', () async {
    final session = await _open();
    final root = session.groups.first.id;
    final group = session.addGroup(parentId: root, name: 'Delete subtree');
    final child = session.addGroup(parentId: group, name: 'Child');
    final entry = session.addEntry(
      groupId: child,
      fields: const KeePassEntryFields(password: 'keep until delete'),
    );
    session.deleteGroup(group);
    expect(
      session.groups.firstWhere((item) => item.id == child).isRecycled,
      isTrue,
    );
    expect(
      session.entries.firstWhere((item) => item.id == entry).isRecycled,
      isTrue,
    );
    session.moveGroup(group, root);
    expect(
      session.entries.firstWhere((item) => item.id == entry).isRecycled,
      isFalse,
    );
    session.deleteGroup(group);
    session.deleteGroup(group);
    expect(
      session.groups.where((item) => item.id == group || item.id == child),
      isEmpty,
    );
    expect(session.entries.where((item) => item.id == entry), isEmpty);
    final raw = await _raw(await session.save());
    final ids = raw.xml.rootElement
        .getElement('Root')!
        .getElement('DeletedObjects')!
        .findElements('DeletedObject')
        .map((item) => item.getElement('UUID')!.innerText);
    expect(ids, containsAll([group, child, entry]));
  });

  test('custom fields preserve unknown attributes through rename, protection changes and deletion', () async {
    final raw = await _raw(_fixture('demo.kdbx'));
    const id = 'vqcoCvE9/k6PSgutKI6snw==';
    final entry = _node(raw, 'Entry', id);
    final custom = entry
        .findElements('String')
        .firstWhere(
          (node) => node.getElement('Key')?.innerText == 'my field protected',
        );
    custom.setAttribute('future', 'retained');
    custom.children.add(
      XmlElement(XmlName('FutureMetadata'))..innerText = 'opaque',
    );
    custom.getElement('Value')!.setAttribute('vendor', 'kept');
    final session = await _open(await raw.save());
    final fields = session.customFields(id);
    expect(
      fields
          .firstWhere((field) => field.name == 'my field protected')
          .isProtected,
      isTrue,
    );
    session.updateEntry(
      id,
      session.entryFields(id),
      customFields: [
        for (final field in fields)
          if (field.name == 'my field protected')
            KeePassCustomField(
              name: 'Renamed secret',
              originalName: field.name,
              value: 'new custom secret',
              isProtected: true,
            )
          else
            field,
        const KeePassCustomField(
          name: 'Visible custom',
          value: 'plain value',
          isProtected: false,
        ),
      ],
    );
    final saved = await session.save();
    expect(
      utf8.decode(saved, allowMalformed: true),
      isNot(contains('new custom secret')),
    );
    final result = await _raw(saved);
    final renamed = _node(result, 'Entry', id)
        .findElements('String')
        .firstWhere(
          (node) => node.getElement('Key')?.innerText == 'Renamed secret',
        );
    expect(renamed.getAttribute('future'), 'retained');
    expect(renamed.getElement('FutureMetadata')!.innerText, 'opaque');
    expect(renamed.getElement('Value')!.getAttribute('vendor'), 'kept');
    expect(result.isProtected(renamed.getElement('Value')!), isTrue);
    expect(result.textOf(renamed.getElement('Value')!), 'new custom secret');
    final reopened = await _open(saved);
    reopened.updateEntry(
      id,
      reopened.entryFields(id),
      customFields: [
        const KeePassCustomField(
          name: 'Visible custom',
          value: 'now protected',
        ),
      ],
    );
    final finalSession = await _open(await reopened.save());
    expect(finalSession.customFields(id).single.name, 'Visible custom');
    expect(finalSession.customFields(id).single.isProtected, isTrue);
    expect(
      finalSession.entryHistory(id).length,
      session.entryHistory(id).length + 1,
    );
  });

  test('history restore retains full opaque snapshot, current group and all previous versions', () async {
    final raw = await _raw(_fixture('demo.kdbx'));
    const id = 'vqcoCvE9/k6PSgutKI6snw==';
    final initial = _node(raw, 'Entry', id);
    final unknown = XmlElement(XmlName('FutureProtected'), [
      XmlAttribute(XmlName('vendor'), 'retained'),
    ]);
    initial.children.add(unknown);
    raw.setText(unknown, 'future protected value', protected: true);
    final session = await _open(await raw.save());
    final historyBefore = session.entryHistory(id).length;
    final initialFields = session.entryFields(id);
    final initialCustom = session.customFields(id);
    final group = session.addGroup(
      parentId: session.groups.first.id,
      name: 'Moved',
    );
    session.updateEntry(
      id,
      const KeePassEntryFields(title: 'New version', password: 'later secret'),
      customFields: const [
        KeePassCustomField(name: 'New field', value: 'later custom secret'),
      ],
      groupId: group,
    );
    expect(
      session.historyFields(id, historyBefore).password,
      initialFields.password,
    );
    expect(
      session.historyCustomFields(id, historyBefore).map((field) => field.name),
      initialCustom.map((field) => field.name),
    );
    session.restoreEntryHistory(id, historyBefore);
    expect(session.entryFields(id).password, initialFields.password);
    expect(session.entryHistory(id).length, historyBefore + 2);
    expect(
      session.historyFields(id, historyBefore + 1).password,
      'later secret',
    );
    expect(
      session.entries.firstWhere((entry) => entry.id == id).groupId,
      group,
    );
    final result = await _raw(await session.save());
    final restored = _node(result, 'Entry', id);
    expect(
      result.textOf(restored.getElement('FutureProtected')!),
      'future protected value',
    );
    expect(
      restored.getElement('FutureProtected')!.getAttribute('vendor'),
      'retained',
    );
    expect(
      restored.findElements('Binary').length,
      initial.findElements('Binary').length,
    );
    expect(
      restored.getElement('History')!.findElements('Entry').length,
      historyBefore + 2,
    );
  });

  test('invalid custom fields and excessive growth fail before adding history or changing values', () async {
    final session = await _open();
    const id = 'vqcoCvE9/k6PSgutKI6snw==';
    final old = session.entryFields(id);
    final count = session.entryHistory(id).length;
    for (final fields in <List<KeePassCustomField>>[
      const [KeePassCustomField(name: 'Password', value: 'reserved')],
      const [
        KeePassCustomField(name: 'x', value: 'one'),
        KeePassCustomField(name: 'x', value: 'two'),
      ],
      const [
        KeePassCustomField(name: 'new', originalName: 'missing', value: 'bad'),
      ],
      const [KeePassCustomField(name: ' ', value: 'empty')],
    ]) {
      expect(
        () => session.updateEntry(
          id,
          const KeePassEntryFields(title: 'Rejected'),
          customFields: fields,
        ),
        throwsA(_error(KeePassErrorCode.invalidOperation)),
      );
    }
    expect(
      () => session.updateEntry(
        id,
        old,
        customFields: List.generate(
          kKeePassMaxCustomFields + 1,
          (index) => KeePassCustomField(name: 'field$index', value: 'value'),
        ),
      ),
      throwsA(_error(KeePassErrorCode.resourceLimit)),
    );
    expect(session.entryFields(id).title, old.title);
    expect(session.entryHistory(id).length, count);
    expect(
      () => session.restoreEntryHistory(id, -1),
      throwsA(_error(KeePassErrorCode.invalidOperation)),
    );
    final saving = session.save();
    expect(
      () => session.addGroup(parentId: session.groups.first.id, name: 'Busy'),
      throwsA(_error(KeePassErrorCode.locked)),
    );
    await saving;
  });
}
