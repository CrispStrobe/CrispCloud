import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/keepass_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:kpasslib/src/crypto/hashed_block_transform.dart';
import 'package:kpasslib/src/utils/byte_utils.dart';
import 'package:kpasslib/src/utils/parameters_map.dart';
import 'package:xml/xml.dart';

Uint8List _fixture(String name) => base64.decode(
  File('test/fixtures/keepass/$name.b64')
      .readAsStringSync()
      .replaceAll(RegExp(r'\s'), ''),
);

KdbxCredentials _credentials({String? password = 'demo', Uint8List? keyFile}) {
  final protected = password == null
      ? null
      : ProtectedData.fromString(password);
  try {
    return KdbxCredentials(
      password: protected,
      keyData: keyFile ?? _fixture('demo.key'),
    );
  } finally {
    protected?.dispose();
  }
}

Future<KdbxRawDocument> _raw(Uint8List data) => KdbxRawDocument.open(
  data: data,
  credentials: _credentials(),
  validateHeader: (_) {},
);

XmlElement _mainEntry(KdbxRawDocument raw) =>
    raw.xml.descendants.whereType<XmlElement>().firstWhere(
      (node) =>
          node.name.qualified == 'Entry' &&
          node.getElement('UUID')?.innerText == 'vqcoCvE9/k6PSgutKI6snw==',
    );

String _field(KdbxRawDocument raw, XmlElement entry, String key) {
  final node = entry
      .findElements('String')
      .firstWhere((node) => node.getElement('Key')?.innerText == key);
  return raw.textOf(node.getElement('Value')!);
}

Matcher _error(KeePassErrorCode code) =>
    isA<KeePassException>().having((error) => error.code, 'code', code);

void main() {
  test('caps tiny inner binary records before allocation and before save', () {
    final writer = BytesWriter()
      ..writeUint8(1)
      ..writeUint32(4)
      ..writeUint32(2)
      ..writeUint8(2)
      ..writeUint32(32)
      ..writeBytes(Uint8List(32));
    for (var index = 0; index < 4097; index++) {
      writer
        ..writeUint8(3)
        ..writeUint32(1)
        ..writeUint8(0);
    }
    writer
      ..writeUint8(0)
      ..writeUint32(0);
    final header = KdbxHeader.create(credentials: KdbxCredentials());
    expect(
      () => header.readInnerHeader(BytesReader(writer.bytes)),
      throwsA(isA<ResourceLimitError>()),
    );
    expect(header.binaries.length, 4096);
    header.binaries.appendFromInnerHeader(
      PlainBinary(data: Uint8List(0), compressed: false),
    );
    expect(() => header.innerBytes, throwsA(isA<ResourceLimitError>()));
    header.binaries.dispose();
    header.credentials.dispose();
  });

  test(
    'opens a KeePass-authored KDBX3 file with XML v1 key and decoded fields',
    () async {
      final session = await KeePassSession.open(
        _fixture('demo.kdbx'),
        password: 'demo',
        keyFile: _fixture('demo.key'),
      );
      addTearDown(session.dispose);
      expect(session.databaseName, 'demo');
      expect(session.formatLabel, contains('KDBX 3.1'));
      expect(session.groups.map((group) => group.name), contains('General'));
      final info = session.entries.firstWhere(
        (entry) => entry.title == 'my entry',
      );
      final entry = session.entryFields(info.id);
      expect(entry.userName, 'me');
      expect(entry.password, 'mypass');
      expect(entry.url, 'http://me.me');
      expect(entry.notes, 'some notes');
    },
  );

  for (final fixture in ['argon2id.kdbx', 'argon2ChaCha.kdbx']) {
    test(
      'edits and reopens KeePass-authored $fixture without changing KDF or cipher',
      () async {
        final original = await _raw(_fixture(fixture));
        addTearDown(original.dispose);
        final session = await KeePassSession.open(
          _fixture(fixture),
          password: 'demo',
          keyFile: _fixture('demo.key'),
        );
        addTearDown(session.dispose);
        final id = session.entries
            .firstWhere((entry) => entry.title == 'my entry')
            .id;
        session.updateEntry(
          id,
          const KeePassEntryFields(
            title: 'Edited account',
            userName: 'new user',
            password: 'new secret 🔑',
            url: 'https://example.test',
            notes: 'New notes',
          ),
        );
        final saved = await session.save();
        final reopened = await _raw(saved);
        addTearDown(reopened.dispose);
        expect(
          _field(reopened, _mainEntry(reopened), 'Password'),
          'new secret 🔑',
        );
        expect(reopened.header.version, original.header.version);
        expect(reopened.header.dataCipherUuid, original.header.dataCipherUuid);
        expect(reopened.header.compression, original.header.compression);
        for (final key in [r'$UUID', 'I', 'M', 'P', 'V']) {
          expect(
            reopened.header.kdfParameters?.get(key),
            original.header.kdfParameters?.get(key),
          );
        }
        expect(
          reopened.header.kdfParameters?.get('S'),
          isNot(original.header.kdfParameters?.get('S')),
        );
        // The independent upstream object-model reader also accepts our output.
        final model = await KdbxDatabase.fromBytes(
          data: saved,
          credentials: _credentials(),
        );
        expect(
          model.root.allEntries
              .firstWhere((entry) => entry.uuid.string == id)
              .fields['Title']
              ?.text,
          'Edited account',
        );
      },
    );
  }

  for (final sample in [
    (database: 'keyV2.kdbx', key: 'keyV2.keyx', password: null),
    (
      database: 'noPassWithKeyFile.kdbx',
      key: 'noPassWithKeyFile.key',
      password: null,
    ),
    (database: 'key32.kdbx', key: 'key32.key', password: 'test'),
    (database: 'key64.kdbx', key: 'key64.key', password: 'test'),
  ]) {
    test('supports KeePass key-file variant ${sample.key}', () async {
      final key = _fixture(sample.key);
      final before = Uint8List.fromList(key);
      final session = await KeePassSession.open(
        _fixture(sample.database),
        password: sample.password,
        keyFile: key,
      );
      addTearDown(session.dispose);
      expect(session.groups, isNotEmpty);
      expect(
        key,
        before,
        reason: 'The caller owns and may reuse its key file bytes.',
      );
      final saved = await session.save();
      final reopened = await KeePassSession.open(
        saved,
        password: sample.password,
        keyFile: key,
      );
      addTearDown(reopened.dispose);
      expect(reopened.databaseName, session.databaseName);
    });
  }

  test('retains KDBX4.1 custom metadata on an unchanged round trip', () async {
    final data = _fixture('kdbx4.1.kdbx');
    KdbxCredentials credentials() =>
        KdbxCredentials(password: ProtectedData.fromString('test'));
    final original = await KdbxRawDocument.open(
      data: data,
      credentials: credentials(),
      validateHeader: (_) {},
    );
    addTearDown(original.dispose);
    final before = original.xml.rootElement
        .getElement('Meta')!
        .getElement('CustomData')!
        .toXmlString();
    final session = await KeePassSession.open(data, password: 'test');
    addTearDown(session.dispose);
    final reopened = await KdbxRawDocument.open(
      data: await session.save(),
      credentials: credentials(),
      validateHeader: (_) {},
    );
    addTearDown(reopened.dispose);
    expect(reopened.header.version, (4, 1));
    expect(
      reopened.xml.rootElement
          .getElement('Meta')!
          .getElement('CustomData')!
          .toXmlString(),
      before,
    );
  });

  test(
    'retains unknown XML, protected custom values, full history and binary IDs',
    () async {
      final source = await _raw(_fixture('argon2id.kdbx'));
      addTearDown(source.dispose);
      final entry = _mainEntry(source);
      final meta = source.xml.rootElement.getElement('Meta')!;
      meta.children.add(
        XmlElement(
          XmlName('FutureMeta'),
          [XmlAttribute(XmlName('flag'), 'preserve')],
          [XmlCDATA('unknown <metadata>')],
        ),
      );
      entry.children.add(
        XmlElement(XmlName('CustomData'), [], [
          XmlElement(XmlName('Item'), [], [
            XmlElement(XmlName('Key'))..innerText = 'plugin',
            XmlElement(XmlName('Value'))..innerText = 'custom data',
          ]),
        ]),
      );
      final beforeSecret = XmlElement(XmlName('FutureSecretBefore'), [
        XmlAttribute(XmlName('flag'), 'first'),
      ]);
      final afterSecret = XmlElement(XmlName('FutureSecretAfter'), [
        XmlAttribute(XmlName('flag'), 'last'),
      ]);
      entry.children.insert(0, beforeSecret);
      entry.children.add(afterSecret);
      source.setText(beforeSecret, 'secret before password', protected: true);
      source.setText(afterSecret, 'secret after password', protected: true);
      final attachment = Uint8List.fromList(
        utf8.encode('duplicate attachment bytes'),
      );
      final binaryCount = source.header.binaries.all.length;
      source.header.binaries.appendFromInnerHeader(
        PlainBinary(data: Uint8List.fromList(attachment), compressed: false),
      );
      source.header.binaries.appendFromInnerHeader(
        ProtectedBinary(protectedData: ProtectedData.fromBytes(attachment)),
      );
      for (var index = 0; index < 2; index++) {
        entry.children.add(
          XmlElement(XmlName('Binary'), [], [
            XmlElement(XmlName('Key'))..innerText = 'duplicate$index.bin',
            XmlElement(XmlName('Value'), [
              XmlAttribute(XmlName('Ref'), '${binaryCount + index}'),
            ]),
          ]),
        );
      }
      source.header.comment = Uint8List.fromList(
        utf8.encode('keep header comment'),
      );
      source.header.publicCustomData = ParametersMap()
        ..add(
          key: 'plugin-public',
          type: ParameterType.string,
          value: 'opaque public metadata',
        );
      final initialHistory = entry
          .getElement('History')!
          .findElements('Entry')
          .length;
      final fixture = await source.save();
      final session = await KeePassSession.open(
        fixture,
        password: 'demo',
        keyFile: _fixture('demo.key'),
      );
      addTearDown(session.dispose);
      final id = session.entries
          .firstWhere((info) => info.title == 'my entry')
          .id;
      final old = session.entryFields(id);
      session.updateEntry(
        id,
        KeePassEntryFields(
          title: 'Changed title',
          userName: old.userName,
          password: 'replaced password',
          url: old.url,
          notes: old.notes,
        ),
      );
      final saved = await session.save();
      final result = await _raw(saved);
      addTearDown(result.dispose);
      final changed = _mainEntry(result);
      final history = changed
          .getElement('History')!
          .findElements('Entry')
          .toList();
      expect(history.length, initialHistory + 1);
      expect(_field(result, history.last, 'Password'), 'mypass');
      expect(_field(result, changed, 'Password'), 'replaced password');
      for (final node in [changed, history.last]) {
        expect(
          result.textOf(node.getElement('FutureSecretBefore')!),
          'secret before password',
        );
        expect(
          result.textOf(node.getElement('FutureSecretAfter')!),
          'secret after password',
        );
        expect(
          node.getElement('FutureSecretBefore')!.getAttribute('flag'),
          'first',
        );
        expect(
          node.getElement('CustomData')!.innerText,
          contains('custom data'),
        );
        expect(_field(result, node, 'my field protected'), 'protected val');
      }
      expect(
        result.xml.rootElement
            .getElement('Meta')!
            .getElement('FutureMeta')!
            .toXmlString(),
        meta.getElement('FutureMeta')!.toXmlString(),
      );
      expect(utf8.decode(result.header.comment!), 'keep header comment');
      expect(
        result.header.publicCustomData?.get('plugin-public'),
        'opaque public metadata',
      );
      final binaries = result.header.binaries.all;
      expect(binaries.length, binaryCount + 2);
      expect(binaries[binaryCount], isA<PlainBinary>());
      expect(binaries[binaryCount + 1], isA<ProtectedBinary>());
      expect(binaries[binaryCount].data, attachment);
      expect(binaries[binaryCount + 1].data, attachment);
      expect(
        utf8.decode(saved, allowMalformed: true),
        isNot(contains('replaced password')),
      );
    },
  );

  test('KDBX3 saves refresh salts and header hash and preserve original file buffers', () async {
    final bytes = _fixture('demo.kdbx');
    final original = Uint8List.fromList(bytes);
    final session = await KeePassSession.open(
      bytes,
      password: 'demo',
      keyFile: _fixture('demo.key'),
    );
    addTearDown(session.dispose);
    final saved1 = await session.save();
    final firstCopy = Uint8List.fromList(saved1);
    final saved2 = await session.save();
    expect(saved1, firstCopy);
    expect(saved1, isNot(saved2));
    expect(bytes, original);
    final first = await _raw(saved1);
    final second = await _raw(saved2);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    expect(first.header.masterSeed, isNot(second.header.masterSeed));
    expect(first.header.encryptionIV, isNot(second.header.encryptionIV));
    expect(first.header.transformSeed, isNot(second.header.transformSeed));
    expect(first.header.keyEncryptionRounds, second.header.keyEncryptionRounds);
  });

  test('creates entries and honors the existing recycle bin before permanent deletion', () async {
    final session = await KeePassSession.open(
      _fixture('demo.kdbx'),
      password: 'demo',
      keyFile: _fixture('demo.key'),
    );
    addTearDown(session.dispose);
    final root = session.groups.first.id;
    final id = session.addEntry(
      groupId: root,
      fields: const KeePassEntryFields(title: 'Created', password: 'new'),
    );
    expect(session.entryFields(id).password, 'new');
    session.deleteEntry(id);
    expect(
      session.entries.firstWhere((entry) => entry.id == id).groupId,
      session.groups.firstWhere((group) => group.name == 'Recycle Bin').id,
    );
    session.deleteEntry(id);
    expect(session.entries.where((entry) => entry.id == id), isEmpty);
    final reopened = await _raw(await session.save());
    addTearDown(reopened.dispose);
    expect(
      reopened.xml.rootElement
          .getElement('Root')!
          .getElement('DeletedObjects')!
          .innerText,
      contains(id),
    );
  });

  test(
    'wrong credentials produce sanitized errors and never mutate input',
    () async {
      final bytes = _fixture('demo.kdbx');
      final before = Uint8List.fromList(bytes);
      await expectLater(
        KeePassSession.open(
          bytes,
          password: 'do-not-log-this-secret',
          keyFile: _fixture('demo.key'),
        ),
        throwsA(_error(KeePassErrorCode.invalidCredentials)),
      );
      await expectLater(
        KeePassSession.open(bytes, password: 'demo', keyFile: Uint8List(32)),
        throwsA(_error(KeePassErrorCode.invalidCredentials)),
      );
      expect(bytes, before);
      expect(
        const KeePassException(KeePassErrorCode.invalidCredentials).toString(),
        isNot(contains('do-not-log-this-secret')),
      );
    },
  );

  test(
    'rejects hostile KDF costs before checking credentials or decrypting',
    () async {
      for (final name in ['demo.kdbx', 'argon2id.kdbx']) {
        final bytes = _fixture(name);
        final reader = BytesReader(bytes);
        final header = KdbxHeader.fromBytes(
          credentials: _credentials(),
          reader: reader,
        );
        final suffix = reader.readBytesToEnd();
        if (header.version.$1 == 3) {
          header.keyEncryptionRounds = 2000001;
        } else {
          header.kdfParameters!.add(
            key: 'M',
            type: ParameterType.uInt64,
            value: 1024 * 1024 * 1024,
          );
        }
        final hostile = Uint8List.fromList([...header.bytes, ...suffix]);
        await expectLater(
          KeePassSession.open(hostile, password: 'wrong on purpose'),
          throwsA(_error(KeePassErrorCode.resourceLimit)),
        );
      }
    },
  );

  test('authenticates terminal HMAC blocks and rejects truncation or appended data', () async {
    final bytes = _fixture('argon2id.kdbx');
    final modified = Uint8List.fromList(bytes)..[bytes.length - 36] ^= 1;
    for (final corrupt in [
      modified,
      Uint8List.fromList(bytes.sublist(0, bytes.length - 36)),
      Uint8List.fromList([...bytes, 0]),
    ]) {
      await expectLater(
        KeePassSession.open(
          corrupt,
          password: 'demo',
          keyFile: _fixture('demo.key'),
        ),
        throwsA(_error(KeePassErrorCode.corrupt)),
      );
    }
    final hashed = HashedBlockTransform.encrypt([1, 2, 3]);
    hashed[hashed.length - 36] = 1;
    expect(
      () => HashedBlockTransform.decrypt(hashed),
      throwsA(isA<FileCorruptedError>()),
    );
  });

  test(
    'rejects malformed variant maps instead of dropping unknown metadata',
    () {
      final map = ParametersMap()
        ..add(key: 'x', type: ParameterType.uInt32, value: 1);
      final bytes = map.bytes;
      expect(
        () => ParametersMap.fromBytes([...bytes, 1]),
        throwsA(isA<FileCorruptedError>()),
      );
      expect(
        () => ParametersMap.fromBytes(bytes.sublist(0, bytes.length - 1)),
        throwsA(anything),
      );
      expect(
        () => ParametersMap.fromBytes([
          ...bytes.sublist(0, bytes.length - 1),
          ...bytes.sublist(2),
        ]),
        throwsA(isA<FileCorruptedError>()),
      );
    },
  );

  test('limits saved XML as well as loaded XML, and lock invalidates session access', () async {
    final raw = await _raw(_fixture('argon2id.kdbx'));
    addTearDown(raw.dispose);
    var parent = raw.xml.rootElement;
    for (var depth = 0; depth < 70; depth++) {
      final child = XmlElement(XmlName('Nested'));
      parent.children.add(child);
      parent = child;
    }
    await expectLater(raw.save(), throwsA(isA<ResourceLimitError>()));
    final session = await KeePassSession.open(
      _fixture('demo.kdbx'),
      password: 'demo',
      keyFile: _fixture('demo.key'),
    );
    session.dispose();
    session.dispose();
    expect(() => session.entries, throwsA(_error(KeePassErrorCode.locked)));
    expect(() => session.save(), throwsA(_error(KeePassErrorCode.locked)));
  });
}
