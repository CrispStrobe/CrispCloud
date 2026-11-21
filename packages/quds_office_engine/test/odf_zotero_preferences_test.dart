import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _meta = 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0';
const _json =
    ' {"prefs":{"fieldType":"ReferenceMark","noteType":0},'
    '"extension":{"keep":"العربية 😀","enabled":true}} ';
const _xml =
    '<data data-version="3"><session id="session-1"/>'
    '<prefs><pref name="fieldType" value="ReferenceMark"/>'
    '<pref name="noteType" value="1"/></prefs>'
    '<extra xmlns="urn:test">retain 😀</extra></data>';

String _property(String name, String value, {String? type = 'string'}) =>
    '<m:user-defined m:name="${encodeXmlAttribute(name)}"'
    '${type == null ? '' : ' m:value-type="${encodeXmlAttribute(type)}"'}>'
    '${encodeXmlText(value)}</m:user-defined>';

XmlElement _root(String contents) {
  final reader = XmlPullReader(
    '<o:document-meta xmlns:o="$_office" xmlns:m="$_meta" '
    'xmlns:f="urn:foreign"><o:meta>$contents</o:meta></o:document-meta>',
  );
  while (reader.next()) {
    if (reader.eventType == XmlEventType.startElement) {
      return XmlDocument.readElement(reader);
    }
  }
  throw StateError('Missing fixture root.');
}

List<String> _chunks(String data, {String family = 'ZOTERO_PREF'}) {
  final result = <String>[];
  var offset = 0;
  var index = 1;
  while (offset < data.length) {
    var end = (offset + 255).clamp(0, data.length);
    if (end < data.length &&
        data.codeUnitAt(end - 1) >= 0xd800 &&
        data.codeUnitAt(end - 1) <= 0xdbff) {
      end--;
    }
    result.add(_property('${family}_${index++}', data.substring(offset, end)));
    offset = end;
  }
  return result;
}

Set<OdfZoteroPreferenceIssueCode> _codes(OdfZoteroPreferences preferences) =>
    preferences.issues.map((issue) => issue.code).toSet();

void main() {
  test(
    'absent metadata and absent properties are clean absent inventories',
    () {
      for (final root in <XmlElement?>[null, _root('')]) {
        final result = OdfZoteroPreferences.read(root);
        expect(result.isPresent, isFalse);
        expect(result.isValid, isTrue);
        expect(result.rawData, '');
        expect(result.family, isNull);
        expect(result.fieldType, isNull);
        expect(result.usesReferenceMarks, isFalse);
        expect(result.issues, isEmpty);
      }
    },
  );

  test(
    'reads original JSON without converting ReferenceMark or extensions',
    () {
      final result = OdfZoteroPreferences.read(_root(_chunks(_json).join()));
      expect(result.isPresent, isTrue);
      expect(result.isValid, isTrue);
      expect(result.usesReferenceMarks, isTrue);
      expect(result.fieldType, 'ReferenceMark');
      expect(result.family, OdfZoteroPreferenceFamily.zotero);
      expect(result.rawData, _json);
      expect(result.properties.single.value, _json);
      expect(result.issues, isEmpty);
      expect(
        () => WordZoteroDocumentData.toHttp(result.rawData!),
        throwsFormatException,
      );
    },
  );

  test('reads original XML and retains styles and unknown namespaces', () {
    final result = OdfZoteroPreferences.read(_root(_chunks(_xml).join()));
    expect(result.rawData, _xml);
    expect(result.fieldType, 'ReferenceMark');
    expect(result.isValid, isTrue);
    expect(result.issues, isEmpty);
  });

  test('orders chunks numerically beyond nine, independently of XML order', () {
    final data = jsonEncode(<String, Object?>{
      'prefs': <String, Object?>{'fieldType': 'ReferenceMark'},
      'extension': 'x' * 4000,
    });
    final pieces = _chunks(data);
    expect(pieces.length, greaterThan(10));
    final result = OdfZoteroPreferences.read(_root(pieces.reversed.join()));
    expect(result.rawData, data);
    expect(result.isValid, isTrue);
    // Snapshots retain source order; sorting the decode never reorders them.
    expect(result.properties.first.index, pieces.length);
    expect(result.properties.last.index, 1);
  });

  test(
    'legacy CSL family is recognized separately and retains original data',
    () {
      final result = OdfZoteroPreferences.read(
        _root(_chunks(_xml, family: 'CSL_PREF').join()),
      );
      expect(result.rawData, _xml);
      expect(result.family, OdfZoteroPreferenceFamily.csl);
      expect(result.usesReferenceMarks, isTrue);
    },
  );

  test('omitted value-type uses the ODF string default', () {
    final result = OdfZoteroPreferences.read(
      _root(_property('ZOTERO_PREF_1', _json, type: null)),
    );
    expect(result.rawData, _json);
    expect(result.properties.single.valueType, 'string');
    expect(result.isValid, isTrue);
  });

  test('empty chunks including trailing cleanup slots remain legitimate', () {
    final split = _json.indexOf('ReferenceMark');
    final result = OdfZoteroPreferences.read(
      _root(
        _property('ZOTERO_PREF_1', _json.substring(0, split)) +
            _property('ZOTERO_PREF_2', '') +
            _property('ZOTERO_PREF_3', _json.substring(split)) +
            _property('ZOTERO_PREF_4', ''),
      ),
    );
    expect(result.rawData, _json);
    expect(result.isValid, isTrue);
    expect(result.chunks.length, 4);
  });

  test('a sequence of empty cleanup properties is present and empty', () {
    final result = OdfZoteroPreferences.read(
      _root(_property('ZOTERO_PREF_1', '') + _property('ZOTERO_PREF_2', '')),
    );
    expect(result.isPresent, isTrue);
    expect(result.rawData, '');
    expect(result.isValid, isTrue);
    expect(result.fieldType, isNull);
  });

  test(
    'whitespace-only chunks and CDATA retain the exact preference string',
    () {
      final root = _root(
        '${_property('ZOTERO_PREF_1', ' \n')}'
        '<m:user-defined m:name="ZOTERO_PREF_2"><![CDATA['
        '$_json]]><!-- preserved source comment --></m:user-defined>'
        '${_property('ZOTERO_PREF_3', '\t ')}',
      );
      final result = OdfZoteroPreferences.read(root);
      expect(result.rawData, ' \n$_json\t ');
      expect(result.isValid, isTrue);
    },
  );

  test('read preserves the entire source tree and unrelated properties', () {
    final root = _root(
      '${_property('Customer', 'untouched & < > 😀')}'
      '<m:user-defined m:name="Business" m:value-type="float" '
      'm:value="2.0">2</m:user-defined>'
      '${_chunks(_json).join()}',
    );
    final before = XmlDocument(root: root).toXmlString();
    final first = OdfZoteroPreferences.read(root);
    final second = OdfZoteroPreferences.read(root);
    expect(XmlDocument(root: root).toXmlString(), before);
    expect(first.toJson(), second.toJson());
    expect(first.properties.length, 3);
    expect(first.properties.first.family, isNull);
    expect(first.properties.first.value, 'untouched & < > 😀');
    expect(first.properties[1].valueType, 'float');
    expect(first.properties.last.ownerIndex, 0);
    expect(first.properties.last.propertyIndex, 2);
    expect(first.isValid, isTrue);
  });

  test('returned lists and property attribute lists are immutable', () {
    final result = OdfZoteroPreferences.read(_root(_chunks(_json).join()));
    expect(() => result.properties.clear(), throwsUnsupportedError);
    expect(() => result.issues.clear(), throwsUnsupportedError);
    expect(
      () => result.properties.single.nameAttributes.clear(),
      throwsUnsupportedError,
    );
  });

  test('uses expanded namespaces, not conventional prefix spelling', () {
    final root = XmlDocument.parse(
      '<document-meta xmlns="$_office" xmlns:property="$_meta">'
      '<meta><property:user-defined property:name="ZOTERO_PREF_1">'
      '${encodeXmlText(_json)}'
      '</property:user-defined></meta></document-meta>',
    ).root!;
    expect(OdfZoteroPreferences.read(root).rawData, _json);
  });

  test(
    'foreign elements, foreign attributes and nested decoys are ignored',
    () {
      final result = OdfZoteroPreferences.read(
        _root(
          '<f:user-defined m:name="ZOTERO_PREF_1">broken</f:user-defined>'
          '<m:user-defined f:name="ZOTERO_PREF_1">broken</m:user-defined>'
          '<f:wrapper>${_property('ZOTERO_PREF_1', 'broken')}</f:wrapper>'
          '${_property('ZOTERO_PREF_1', _json)}',
        ),
      );
      expect(result.rawData, _json);
      expect(result.chunks.length, 1);
      expect(result.isValid, isTrue);
    },
  );

  test('a foreign office:meta owner contributes no preferences', () {
    final root = XmlDocument.parse(
      '<o:document-meta xmlns:o="$_office" xmlns:m="$_meta" '
      'xmlns:f="urn:foreign"><f:meta>'
      '${_property('ZOTERO_PREF_1', _json)}</f:meta></o:document-meta>',
    ).root!;
    final result = OdfZoteroPreferences.read(root);
    expect(result.isPresent, isFalse);
    expect(result.rawData, '');
  });

  test('wrong root cannot make descendant properties authoritative', () {
    final root = XmlDocument.parse(
      '<f:document-meta xmlns:o="$_office" xmlns:m="$_meta" '
      'xmlns:f="urn:foreign"><o:meta>'
      '${_property('ZOTERO_PREF_1', _json)}</o:meta></f:document-meta>',
    ).root!;
    final result = OdfZoteroPreferences.read(root);
    expect(result.isValid, isFalse);
    expect(result.isPresent, isFalse);
    expect(result.rawData, isNull);
    expect(_codes(result), {OdfZoteroPreferenceIssueCode.invalidRoot});
  });

  test('duplicate office:meta owners are ambiguous even with one family', () {
    final root = _root(_property('ZOTERO_PREF_1', _json));
    root.addChild(XmlElement(localName: 'meta', namespaceUri: _office));
    final result = OdfZoteroPreferences.read(root);
    expect(result.rawData, isNull);
    expect(result.isPresent, isTrue);
    expect(
      _codes(result),
      contains(OdfZoteroPreferenceIssueCode.duplicateMetaOwner),
    );
  });

  for (final name in <String>[
    'ZOTERO_PREF',
    'ZOTERO_PREF_',
    'ZOTERO_PREF_0',
    'ZOTERO_PREF_01',
    'ZOTERO_PREF_-1',
    'ZOTERO_PREF_+1',
    'ZOTERO_PREF_1 ',
    'ZOTERO_PREF_1e0',
    'ZOTERO_PREF_4097',
    'ZOTERO_PREF_999999999999999999999999999999999',
  ]) {
    test('reports noncanonical preference name $name', () {
      final result = OdfZoteroPreferences.read(_root(_property(name, _json)));
      expect(result.isPresent, isTrue);
      expect(result.rawData, isNull);
      expect(result.properties.single.name, name);
      expect(
        _codes(result),
        contains(OdfZoteroPreferenceIssueCode.invalidIndex),
      );
    });
  }

  test('duplicate chunk names never choose a winner', () {
    final result = OdfZoteroPreferences.read(
      _root(
        _property('ZOTERO_PREF_1', _json) + _property('ZOTERO_PREF_1', _xml),
      ),
    );
    expect(result.rawData, isNull);
    expect(result.chunks.length, 2);
    expect(
      _codes(result),
      contains(OdfZoteroPreferenceIssueCode.duplicateChunk),
    );
  });

  for (final indexes in <List<int>>[
    [2],
    [1, 3],
  ]) {
    test('reports missing chunks in $indexes', () {
      final result = OdfZoteroPreferences.read(
        _root(
          indexes.map((index) => _property('ZOTERO_PREF_$index', '')).join(),
        ),
      );
      expect(result.rawData, isNull);
      expect(
        _codes(result),
        contains(OdfZoteroPreferenceIssueCode.missingChunk),
      );
    });
  }

  test('conflicting families retain all chunks without fallback', () {
    final result = OdfZoteroPreferences.read(
      _root(_property('ZOTERO_PREF_1', _json) + _property('CSL_PREF_1', _xml)),
    );
    expect(result.rawData, isNull);
    expect(result.family, isNull);
    expect(result.chunks.length, 2);
    expect(
      _codes(result),
      contains(OdfZoteroPreferenceIssueCode.conflictingFamilies),
    );
  });

  test('empty primary cleanup chunks permit the legacy family fallback', () {
    final result = OdfZoteroPreferences.read(
      _root(
        _property('ZOTERO_PREF_1', '') +
            _property('ZOTERO_PREF_2', '') +
            _chunks(_json, family: 'CSL_PREF').join(),
      ),
    );
    expect(result.rawData, _json);
    expect(result.family, OdfZoteroPreferenceFamily.csl);
    expect(result.isValid, isTrue);
    expect(result.issues, isEmpty);
    expect(result.chunks.length, 3);
  });

  test('empty legacy cleanup chunks do not displace primary data', () {
    final result = OdfZoteroPreferences.read(
      _root(
        _chunks(_json).join() +
            _property('CSL_PREF_1', '') +
            _property('CSL_PREF_2', ''),
      ),
    );
    expect(result.rawData, _json);
    expect(result.family, OdfZoteroPreferenceFamily.zotero);
    expect(result.isValid, isTrue);
    expect(result.issues, isEmpty);
  });

  test(
    'two valid empty families retain primary preference without conflict',
    () {
      final result = OdfZoteroPreferences.read(
        _root(_property('CSL_PREF_1', '') + _property('ZOTERO_PREF_1', '')),
      );
      expect(result.rawData, '');
      expect(result.family, OdfZoteroPreferenceFamily.zotero);
      expect(result.isPresent, isTrue);
      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
    },
  );

  test('identical nonempty families still require explicit resolution', () {
    final result = OdfZoteroPreferences.read(
      _root(_property('ZOTERO_PREF_1', _json) + _property('CSL_PREF_1', _json)),
    );
    expect(result.rawData, isNull);
    expect(result.family, isNull);
    expect(
      _codes(result),
      contains(OdfZoteroPreferenceIssueCode.conflictingFamilies),
    );
  });

  test('an invalid empty primary sequence cannot silently enable fallback', () {
    final result = OdfZoteroPreferences.read(
      _root(_property('ZOTERO_PREF_2', '') + _property('CSL_PREF_1', _json)),
    );
    expect(result.rawData, isNull);
    expect(result.isValid, isFalse);
    expect(_codes(result), contains(OdfZoteroPreferenceIssueCode.missingChunk));
  });

  for (final type in <String>['float', 'boolean', '', 'String']) {
    test('non-string value type $type is explicit', () {
      final result = OdfZoteroPreferences.read(
        _root(_property('ZOTERO_PREF_1', _json, type: type)),
      );
      expect(result.rawData, isNull);
      expect(result.properties.single.value, _json);
      expect(
        _codes(result),
        contains(OdfZoteroPreferenceIssueCode.invalidType),
      );
    });
  }

  test('qualified duplicate property attributes are not collapsed', () {
    final root = _root(_property('ZOTERO_PREF_1', _json));
    final property = root
        .firstChild('meta', namespaceUri: _office)!
        .childElements
        .single;
    property.attributes.add(
      XmlAttribute(
        localName: 'name',
        namespaceUri: _meta,
        value: 'ZOTERO_PREF_2',
      ),
    );
    final result = OdfZoteroPreferences.read(root);
    expect(result.rawData, isNull);
    expect(result.properties.single.nameAttributes, [
      'ZOTERO_PREF_1',
      'ZOTERO_PREF_2',
    ]);
    expect(
      _codes(result),
      contains(OdfZoteroPreferenceIssueCode.invalidPropertyAttributes),
    );
  });

  test('qualified duplicate value-type attributes remain ambiguous', () {
    final root = _root(_property('ZOTERO_PREF_1', _json));
    root
        .firstChild('meta', namespaceUri: _office)!
        .childElements
        .single
        .attributes
        .add(
          XmlAttribute(
            localName: 'value-type',
            namespaceUri: _meta,
            value: 'float',
          ),
        );
    final result = OdfZoteroPreferences.read(root);
    expect(result.rawData, isNull);
    expect(
      _codes(result),
      contains(OdfZoteroPreferenceIssueCode.invalidPropertyAttributes),
    );
  });

  test('nested property elements cannot be flattened into preference data', () {
    final result = OdfZoteroPreferences.read(
      _root(
        '<m:user-defined m:name="ZOTERO_PREF_1">'
        '<f:span>${encodeXmlText(_json)}</f:span></m:user-defined>',
      ),
    );
    expect(result.rawData, isNull);
    expect(result.properties.single.value, isNull);
    expect(_codes(result), contains(OdfZoteroPreferenceIssueCode.nestedValue));
  });

  test(
    'chunk limit counts UTF-16 units, including supplementary characters',
    () {
      final result = OdfZoteroPreferences.read(
        _root(_property('ZOTERO_PREF_1', '😀' * 128)),
      );
      expect(result.properties.single.value!.length, 256);
      expect(
        _codes(result),
        contains(OdfZoteroPreferenceIssueCode.oversizedChunk),
      );
    },
  );

  test('an exact 255 UTF-16-unit string chunk is accepted', () {
    final data = _json.padRight(255);
    final result = OdfZoteroPreferences.read(
      _root(_property('ZOTERO_PREF_1', data)),
    );
    expect(result.rawData, data);
    expect(result.isValid, isTrue);
  });

  for (final data in <String>[
    '{broken',
    '{"prefs":{"fieldType":"ReferenceMark"}} trailing',
    '{"prefs":{"fieldType":"ReferenceMark","fieldType":"Bookmark"}}',
    '{"prefs":{"fieldType":false}}',
    '{"prefs":{"fieldType":"Unknown"}}',
    '<data><prefs><pref name="fieldType" value="ReferenceMark"/>',
    '<data><prefs><pref name="fieldType" value="ReferenceMark"/>'
        '<pref name="fieldType" value="Bookmark"/></prefs></data>',
    '<!DOCTYPE data><data><prefs><pref name="fieldType" value="ReferenceMark"/>'
        '</prefs></data>',
  ]) {
    test('malformed payload retains raw data ${data.hashCode}', () {
      final result = OdfZoteroPreferences.read(_root(_chunks(data).join()));
      expect(result.rawData, data);
      expect(result.isValid, isFalse);
      expect(
        _codes(result),
        contains(OdfZoteroPreferenceIssueCode.malformedData),
      );
    });
  }

  for (final storage in <String>['Bookmark', 'Field', 'Http']) {
    test('$storage is valid data with an explicit storage boundary', () {
      final data = _json.replaceFirst('ReferenceMark', storage);
      final result = OdfZoteroPreferences.read(_root(_chunks(data).join()));
      expect(result.rawData, data);
      expect(result.fieldType, storage);
      expect(result.isValid, isTrue);
      expect(result.usesReferenceMarks, isFalse);
      expect(_codes(result), {
        OdfZoteroPreferenceIssueCode.unsupportedStorageType,
      });
    });
  }

  test(
    'configured exact preference limit is accepted and over-limit throws',
    () {
      final root = _root(_chunks(_json).join());
      expect(
        OdfZoteroPreferences.read(root, maxDataLength: _json.length).rawData,
        _json,
      );
      expect(
        () => OdfZoteroPreferences.read(root, maxDataLength: _json.length - 1),
        throwsFormatException,
      );
    },
  );

  test('full 256 Ki-unit limit is accepted, the next unit is rejected', () {
    const prefix = '{"prefs":{"fieldType":"ReferenceMark"},"extra":"';
    const suffix = '"}';
    final data =
        prefix +
        ('x' *
            (WordZoteroDocumentData.maxDataLength -
                prefix.length -
                suffix.length)) +
        suffix;
    expect(data.length, WordZoteroDocumentData.maxDataLength);
    final result = OdfZoteroPreferences.read(_root(_chunks(data).join()));
    expect(result.rawData, data);
    expect(result.isValid, isTrue);
    expect(
      () => OdfZoteroPreferences.read(_root(_chunks('$data ').join())),
      throwsFormatException,
    );
  });

  test('invalid configurable limits cannot relax the document bound', () {
    for (final limit in [-1, WordZoteroDocumentData.maxDataLength + 1]) {
      expect(
        () => OdfZoteroPreferences.read(null, maxDataLength: limit),
        throwsArgumentError,
      );
    }
    expect(OdfZoteroPreferences.read(null, maxDataLength: 0).rawData, '');
  });

  test('property-count exhaustion cannot return a partial clean inventory', () {
    final properties = Iterable<String>.generate(
      4097,
      (index) => _property('ZOTERO_PREF_${index + 1}', ''),
    ).join();
    expect(
      () => OdfZoteroPreferences.read(_root(properties)),
      throwsFormatException,
    );
  });

  test('oversized property names fail before index parsing', () {
    expect(
      () => OdfZoteroPreferences.read(
        _root(_property('ZOTERO_PREF_${'1' * 1024}', '')),
      ),
      throwsFormatException,
    );
  });
}
