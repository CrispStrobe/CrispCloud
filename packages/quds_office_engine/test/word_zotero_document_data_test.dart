import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _custom = OfficeNamespaces.customProperties;
const _vt = OfficeNamespaces.docPropsVt;
const _customType =
    'application/vnd.openxmlformats-officedocument.custom-properties+xml';
const _native =
    '<data data-version="3" zotero-version="8.0"><session id="session-1"/>'
    '<style id="http://www.zotero.org/styles/chicago-note-bibliography" '
    'locale="de-DE" hasBibliography="1" bibliographyStyleHasBeenSet="1"/>'
    '<prefs><pref name="fieldType" value="Field"/>'
    '<pref name="noteType" value="1"/></prefs>'
    '<extension xmlns="urn:quds:test" keep="yes">Füße 😀</extension></data>';

String _property(String name, String text, {int id = 2}) {
  return '<property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" '
      'pid="$id" name="$name"><vt:lpwstr>'
      '${encodeXmlText(text)}</vt:lpwstr></property>';
}

String _properties(Iterable<String> children) =>
    '<Properties xmlns="$_custom" xmlns:vt="$_vt" '
    'xmlns:a="urn:quds:extra" a:flag="preserve">'
    '${children.join()}<a:unknown a:value="retain"/></Properties>';

Iterable<String> _nativeProperties(String data) sync* {
  for (var offset = 0, index = 1; offset < data.length; index++) {
    var end = (offset + 255).clamp(0, data.length);
    if (end < data.length &&
        data.codeUnitAt(end - 1) >= 0xd800 &&
        data.codeUnitAt(end - 1) <= 0xdbff) {
      end--;
    }
    yield _property(
      'ZOTERO_PREF_$index',
      data.substring(offset, end),
      id: index + 2,
    );
    offset = end;
  }
}

WmlDocument _documentWithProperties(
  String xml, {
  String uri = '/unusual/owned-properties.xml',
  Uint8List? bytes,
}) {
  final document = WmlDocument.empty(text: 'Before citation after');
  final package = WordSerializer().write(document);
  package.createPart(uri, _customType, bytes ?? utf8.encode(xml));
  package.packageRelationships.add(
    type: RelationshipTypes.customProperties,
    target: uri.substring(1),
    id: 'sourceProperties',
  );
  return document;
}

XmlElement _savedProperties(WmlDocument document) {
  final package = document.package!;
  final relationships = package.packageRelationships;
  final relationship = relationships.firstByType(
    RelationshipTypes.customProperties,
  )!;
  return XmlDocument.parse(
    package.getPart(relationships.resolve(relationship))!.readText(),
  ).root!;
}

void main() {
  test('new document has no preference data', () {
    final document = WmlDocument.empty();
    expect(WordZoteroDocumentData.read(document), '');
    expect(WordZoteroDocumentData.toHttp(''), '');
    expect(WordZoteroDocumentData.toNative(''), '');
  });

  test('XML adaptation retains session, style, locale and unknown data', () {
    final http = WordZoteroDocumentData.toHttp(_native);
    final root = XmlDocument.parse(http).root!;
    expect(root.getAttribute('data-version'), '3');
    expect(root.firstChild('session')!.getAttribute('id'), 'session-1');
    expect(root.firstChild('style')!.getAttribute('locale'), 'de-DE');
    expect(
      root.firstChild('extension', namespaceUri: 'urn:quds:test')!.text,
      'Füße 😀',
    );
    final prefs = root.firstChild('prefs')!;
    expect(prefs.childElements.first.getAttribute('value'), 'Http');
    expect(prefs.childElements.last.getAttribute('value'), '1');
    expect(WordZoteroDocumentData.toNative(http), contains('value="Field"'));
  });

  test('JSON adaptation preserves unknown objects and boolean preferences', () {
    final values = <String, Object?>{
      'dataVersion': 4,
      'sessionID': 'abc',
      'style': {'styleID': 'style', 'locale': 'de-DE', 'custom': true},
      'prefs': {'fieldType': 'Field', 'noteType': 1, 'custom': false},
      'extension': {
        'order': [1, 2, 3],
        'value': 'ß😀',
      },
    };
    final http =
        jsonDecode(WordZoteroDocumentData.toHttp(jsonEncode(values)))
            as Map<String, dynamic>;
    expect((http['prefs'] as Map<String, dynamic>)['fieldType'], 'Http');
    final native = jsonDecode(
      WordZoteroDocumentData.toNative(jsonEncode(http)),
    );
    expect(native, values);
  });

  test('unchanged native XML and JSON retain their exact source text', () {
    expect(WordZoteroDocumentData.toNative(_native), _native);
    const json = ' {"prefs": {"fieldType": "Field"}, "unknown": 42} ';
    expect(WordZoteroDocumentData.toNative(json), json);
  });

  for (final type in ['Bookmark', 'ReferenceMark', '', 'unknown']) {
    test('rejects unsupported field storage $type', () {
      expect(
        () => WordZoteroDocumentData.toHttp(
          _native.replaceFirst('value="Field"', 'value="$type"'),
        ),
        throwsFormatException,
      );
    });
  }

  for (final invalid in [
    '<data><prefs/></data>',
    '<data><prefs><pref name="fieldType" value="Field"/>',
    '<data><prefs><pref name="fieldType" value="Field"/><pref name="fieldType" value="Http"/></prefs></data>',
    '<data><prefs><pref name="fieldType" value="Field" value="Http"/></prefs></data>',
    '<data/><data/>',
    '<!DOCTYPE data><data/>',
    '{"prefs":{}}',
    '{"prefs":{"fieldType":false}}',
  ]) {
    test('rejects malformed or ambiguous data ${invalid.hashCode}', () {
      expect(
        () => WordZoteroDocumentData.toHttp(invalid),
        throwsFormatException,
      );
    });
  }

  test('native property chunks survive save reopen and repeated save', () {
    final document = WmlDocument.empty(text: 'Keep body')
      ..zoteroDocumentData = WordZoteroDocumentData.toHttp(_native);
    final bytes = WordSerializer().writeBytes(document);
    final properties = _savedProperties(
      document,
    ).childrenNamed('property', namespaceUri: _custom);
    expect(properties.length, greaterThan(1));
    for (var i = 0; i < properties.length; i++) {
      expect(properties[i].getAttribute('name'), 'ZOTERO_PREF_${i + 1}');
      final value = properties[i].firstChild('lpwstr', namespaceUri: _vt)!;
      expect(value.text.length, lessThanOrEqualTo(255));
    }
    var reopened = WordDeserializer().read(
      OpcPackage.open(MemoryByteSource(bytes)),
    );
    expect(WordZoteroDocumentData.read(reopened), contains('value="Field"'));
    final original = WordZoteroDocumentData.read(reopened);
    for (var i = 0; i < 2; i++) {
      reopened = WordDeserializer().read(
        OpcPackage.open(
          MemoryByteSource(WordSerializer().writeBytes(reopened)),
        ),
      );
      expect(WordZoteroDocumentData.read(reopened), original);
      expect(reopened.paragraphs.first.text, 'Keep body');
    }
  });

  test('preference override crosses isolate save', () async {
    final document = WmlDocument.empty()..zoteroDocumentData = _native;
    final reopened = WordDeserializer().read(
      OpcPackage.open(MemoryByteSource(await OfficeIsolateSave.word(document))),
    );
    expect(WordZoteroDocumentData.read(reopened), _native);
  });

  test(
    'updates the source-owned nonstandard part and preserves unrelated data',
    () {
      final document = _documentWithProperties(
        _properties([
          _property('CustomerValue', 'untouched', id: 50),
          ..._nativeProperties(_native),
        ]),
      );
      final package = document.package!;
      package.createPart(
        '/docProps/custom.xml',
        _customType,
        utf8.encode('<unrelated/>'),
      );
      package
          .relationshipsFor('/unusual/owned-properties.xml')
          .add(
            type: 'urn:unrelated',
            target: 'keep.xml',
            id: 'keepRelationship',
          );
      expect(WordZoteroDocumentData.read(document), _native);
      document.zoteroDocumentData = _native.replaceFirst('de-DE', 'en-US');
      WordSerializer().write(document);
      final root = _savedProperties(document);
      final custom = root
          .childrenNamed('property', namespaceUri: _custom)
          .firstWhere((p) => p.getAttribute('name') == 'CustomerValue');
      expect(custom.getAttribute('pid'), '50');
      expect(custom.text, 'untouched');
      expect(
        root.getAttribute('flag', namespaceUri: 'urn:quds:extra'),
        'preserve',
      );
      expect(
        root.firstChild('unknown', namespaceUri: 'urn:quds:extra'),
        isNotNull,
      );
      expect(
        package.getPart('/docProps/custom.xml')!.readText(),
        '<unrelated/>',
      );
      expect(
        package.packageRelationships
            .firstByType(RelationshipTypes.customProperties)!
            .id,
        'sourceProperties',
      );
      expect(
        package
            .relationshipsFor('/unusual/owned-properties.xml')
            .byId('keepRelationship')!
            .target,
        'keep.xml',
      );
      expect(
        WordZoteroDocumentData.read(
          WordDeserializer().read(
            OpcPackage.open(MemoryByteSource(package.save())),
          ),
        ),
        contains('locale="en-US"'),
      );
    },
  );

  test('new preferences do not adopt an unowned canonical part', () {
    final document = WmlDocument.empty();
    final package = WordSerializer().write(document);
    package.createPart(
      '/docProps/custom.xml',
      _customType,
      utf8.encode('<orphan/>'),
    );
    document.zoteroDocumentData = _native;
    WordSerializer().write(document);
    expect(package.getPart('/docProps/custom.xml')!.readText(), '<orphan/>');
    expect(
      package.packageRelationships
          .firstByType(RelationshipTypes.customProperties)!
          .target,
      'docProps/custom2.xml',
    );
  });

  test('clear and restore remain effective after an intervening save', () {
    final document = _documentWithProperties(
      _properties([
        _property('CustomerValue', 'keep'),
        ..._nativeProperties(_native),
      ]),
    );
    final previous = WordZoteroDocumentData.read(document);
    document.zoteroDocumentData = '';
    WordSerializer().write(document);
    expect(WordZoteroDocumentData.read(document), '');
    expect(
      _savedProperties(document)
          .childrenNamed('property', namespaceUri: _custom)
          .single
          .getAttribute('name'),
      'CustomerValue',
    );
    document.zoteroDocumentData = previous;
    WordSerializer().write(document);
    document.zoteroDocumentData = null;
    expect(WordZoteroDocumentData.read(document), _native);
  });

  test('null override preserves an imported custom part byte for byte', () {
    final xml = _properties(_nativeProperties(_native));
    final document = _documentWithProperties(xml);
    WordSerializer().write(document);
    expect(
      document.package!.getPart('/unusual/owned-properties.xml')!.readText(),
      xml,
    );
  });

  test('reads UTF-16 custom properties before saving as UTF-8', () {
    final xml = _properties(_nativeProperties(_native));
    final bytes = Uint8List.fromList([
      0xff,
      0xfe,
      for (final unit in xml.codeUnits) ...[unit & 255, unit >> 8],
    ]);
    final document = _documentWithProperties(xml, bytes: bytes);
    expect(WordZoteroDocumentData.read(document), _native);
    document.zoteroDocumentData = _native.replaceFirst('de-DE', 'ar');
    WordSerializer().write(document);
    document.zoteroDocumentData = null;
    expect(WordZoteroDocumentData.read(document), contains('locale="ar"'));
  });

  test('rejects external and duplicate custom-property ownership', () {
    final document = WmlDocument.empty();
    final package = WordSerializer().write(document);
    package.packageRelationships.add(
      type: RelationshipTypes.customProperties,
      target: 'https://example.invalid/preferences.xml',
      targetMode: RelationshipTargetMode.external,
    );
    expect(() => WordZoteroDocumentData.read(document), throwsFormatException);
    final duplicate = _documentWithProperties(
      _properties(_nativeProperties(_native)),
    );
    duplicate.package!.packageRelationships.add(
      type: RelationshipTypes.customProperties,
      target: 'unusual/owned-properties.xml',
    );
    expect(() => WordZoteroDocumentData.read(duplicate), throwsFormatException);
  });

  for (final entries in [
    [_property('ZOTERO_PREF_2', 'orphan')],
    [_property('ZOTERO_PREF_1', 'a'), _property('ZOTERO_PREF_1', 'b', id: 3)],
    [_property('ZOTERO_PREF_01', 'a')],
    [_property('ZOTERO_PREF_broken', 'a')],
    [_property('ZOTERO_PREF_1', '')],
    [_property('ZOTERO_PREF_1', 'x' * 256)],
    ['<property name="ZOTERO_PREF_1"><vt:i4>42</vt:i4></property>'],
  ]) {
    test(
      'damaged native chunk refuses read and replacement ${entries.hashCode}',
      () {
        final document = _documentWithProperties(_properties(entries));
        expect(
          () => WordZoteroDocumentData.read(document),
          throwsFormatException,
        );
        final before = document.package!
            .getPart('/word/document.xml')!
            .readText();
        document.paragraphs.first.inlines.add(WmlRun(text: 'unsaved'));
        document.zoteroDocumentData = _native;
        expect(() => WordSerializer().write(document), throwsFormatException);
        expect(
          document.package!.getPart('/word/document.xml')!.readText(),
          before,
        );
      },
    );
  }

  test('excessive document data is rejected before persistence', () {
    final document = WmlDocument.empty()
      ..zoteroDocumentData = 'x' * (WordZoteroDocumentData.maxDataLength + 1);
    expect(() => WordSerializer().write(document), throwsFormatException);
    expect(document.package, isNull);
  });
}
