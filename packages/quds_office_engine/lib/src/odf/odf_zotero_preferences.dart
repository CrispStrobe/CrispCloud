import 'dart:convert';

import '../word/model/word_zotero_data.dart';
import '../xml/xml_node.dart';
import 'odf_text.dart';

/// Namespace of ODF document metadata and user-defined property attributes.
const odfMetadataNamespace = 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0';

/// Preference property families read by the Zotero LibreOffice integration.
enum OdfZoteroPreferenceFamily {
  /// The family written by current Zotero versions.
  zotero,

  /// The legacy family retained by Zotero's reader.
  csl,
}

/// An explicit problem with native ODT Zotero preference data.
enum OdfZoteroPreferenceIssueCode {
  invalidRoot,
  duplicateMetaOwner,
  invalidPropertyAttributes,
  invalidIndex,
  duplicateChunk,
  missingChunk,
  conflictingFamilies,
  invalidType,
  nestedValue,
  oversizedChunk,
  malformedData,
  unsupportedStorageType,
}

/// A diagnostic that does not discard the original detected properties.
final class OdfZoteroPreferenceIssue {
  const OdfZoteroPreferenceIssue(this.code, this.message, {this.propertyName});

  final OdfZoteroPreferenceIssueCode code;
  final String message;
  final String? propertyName;

  Map<String, Object?> toJson() => {
    'code': code.name,
    'message': message,
    if (propertyName != null) 'propertyName': propertyName,
  };
}

/// An immutable snapshot of one correctly owned ODF user-defined property.
///
/// [value] is null when child elements prevent an unambiguous plain string.
/// [nameAttributes] retains duplicate qualified name attributes for diagnosis.
/// Neither the source element nor any other metadata is modified.
final class OdfZoteroPreferenceProperty {
  OdfZoteroPreferenceProperty._({
    required this.ownerIndex,
    required this.propertyIndex,
    required List<String> nameAttributes,
    required this.name,
    required this.valueType,
    required this.value,
    required this.family,
    required this.index,
  }) : nameAttributes = List<String>.unmodifiable(nameAttributes);

  /// Zero-based element position of the direct office:meta owner.
  final int ownerIndex;

  /// Zero-based element position within the office:meta owner.
  final int propertyIndex;
  final List<String> nameAttributes;
  final String? name;

  /// Omitted meta:value-type is represented by its ODF default, "string".
  final String valueType;
  final String? value;
  final OdfZoteroPreferenceFamily? family;

  /// Null for unrelated properties and noncanonical preference indexes.
  final int? index;

  Map<String, Object?> toJson() => {
    'ownerIndex': ownerIndex,
    'propertyIndex': propertyIndex,
    'nameAttributes': nameAttributes,
    'name': name,
    'valueType': valueType,
    'value': value,
    'family': family?.name,
    'index': index,
  };
}

/// Read-only inventory of Zotero preferences in a native ODT metadata part.
///
/// This does not convert preferences or authorize active citation fields. The
/// source string and unknown metadata survive unchanged. Native field-type
/// adaptation remains the responsibility of a future explicit rich importer.
final class OdfZoteroPreferences {
  OdfZoteroPreferences._({
    required this.rawData,
    required this.family,
    required this.fieldType,
    required List<OdfZoteroPreferenceProperty> properties,
    required List<OdfZoteroPreferenceIssue> issues,
  }) : properties = List<OdfZoteroPreferenceProperty>.unmodifiable(properties),
       issues = List<OdfZoteroPreferenceIssue>.unmodifiable(issues);

  /// Original concatenated data; null if ownership or chunks are ambiguous.
  /// Absent preferences and a valid sequence of empty chunks produce "".
  final String? rawData;
  final OdfZoteroPreferenceFamily? family;

  /// Original validated storage preference, without normalization to Field.
  final String? fieldType;

  /// All direct, namespace-qualified user-defined properties, in source order.
  final List<OdfZoteroPreferenceProperty> properties;
  final List<OdfZoteroPreferenceIssue> issues;

  bool get isPresent => properties.any((property) => property.family != null);

  /// Syntactic/semantic validity is separate from native ReferenceMark support.
  bool get isValid => issues.every(
    (issue) =>
        issue.code == OdfZoteroPreferenceIssueCode.unsupportedStorageType,
  );

  /// Whether validated settings describe the storage inventoried by this reader.
  bool get usesReferenceMarks => isValid && fieldType == 'ReferenceMark';

  Iterable<OdfZoteroPreferenceProperty> get chunks =>
      properties.where((property) => property.family != null);

  Map<String, Object?> toJson() => {
    'isPresent': isPresent,
    'isValid': isValid,
    'usesReferenceMarks': usesReferenceMarks,
    'rawData': rawData,
    'family': family?.name,
    'fieldType': fieldType,
    'properties': [for (final property in properties) property.toJson()],
    'issues': [for (final issue in issues) issue.toJson()],
  };

  /// Reads an already bounded, structurally validated meta.xml root.
  ///
  /// Only office:document-meta / office:meta / meta:user-defined ownership is
  /// authoritative. Foreign namespace lookalikes and nested properties are
  /// ignored. Duplicate owners are reported without choosing one silently.
  /// Numbered chunks are ordered numerically, starting at one. Current Zotero
  /// uses at most 255 UTF-16 code units per property; empty cleanup chunks are
  /// legitimate and do not terminate the sequence. A valid empty ZOTERO_PREF
  /// family permits the native CSL_PREF fallback. Two nonempty families are
  /// reported as conflicting rather than silently selecting either one.
  ///
  /// Resource exhaustion throws [FormatException], never a partial inventory.
  /// In addition to [maxDataLength], this helper bounds direct properties to
  /// 4,096, names to 1,024 code units and their collected text to 2 Mi code units.
  /// The caller must bound and validate the XML before constructing its tree.
  static OdfZoteroPreferences read(
    XmlElement? root, {
    int maxDataLength = WordZoteroDocumentData.maxDataLength,
  }) {
    if (maxDataLength < 0 ||
        maxDataLength > WordZoteroDocumentData.maxDataLength) {
      throw ArgumentError.value(maxDataLength, 'maxDataLength');
    }
    final properties = <OdfZoteroPreferenceProperty>[];
    final issues = <OdfZoteroPreferenceIssue>[];
    OdfZoteroPreferences result({
      String? rawData = '',
      OdfZoteroPreferenceFamily? family,
      String? fieldType,
    }) => OdfZoteroPreferences._(
      rawData: rawData,
      family: family,
      fieldType: fieldType,
      properties: properties,
      issues: issues,
    );

    if (root == null) return result();
    if (root.namespaceUri != odfOfficeNamespace ||
        root.localName != 'document-meta') {
      issues.add(
        const OdfZoteroPreferenceIssue(
          OdfZoteroPreferenceIssueCode.invalidRoot,
          'Native ODT preferences require an office:document-meta root.',
        ),
      );
      return result(rawData: null);
    }

    var ownerCount = 0;
    var ownerIndex = 0;
    var totalTextLength = 0;
    var preferenceTextLength = 0;
    for (final owner in root.childElements) {
      final currentOwnerIndex = ownerIndex++;
      if (owner.namespaceUri != odfOfficeNamespace ||
          owner.localName != 'meta') {
        continue;
      }
      ownerCount++;
      var propertyIndex = 0;
      for (final property in owner.childElements) {
        final currentPropertyIndex = propertyIndex++;
        if (property.namespaceUri != odfMetadataNamespace ||
            property.localName != 'user-defined') {
          continue;
        }
        if (properties.length == 4096) {
          throw const FormatException(
            'ODT metadata property count exceeds its limit.',
          );
        }
        final names = <String>[];
        final types = <String>[];
        for (final attribute in property.attributes) {
          if (attribute.namespaceUri != odfMetadataNamespace) continue;
          if (attribute.localName == 'name') {
            if (attribute.value.length > 1024) {
              throw const FormatException(
                'ODT metadata property name exceeds its limit.',
              );
            }
            names.add(attribute.value);
          } else if (attribute.localName == 'value-type') {
            types.add(attribute.value);
          }
        }
        final name =
            names.where((name) => _familyOf(name) != null).firstOrNull ??
            names.firstOrNull;
        final family = name == null ? null : _familyOf(name);
        final type = types.firstOrNull ?? 'string';
        final index = family == null ? null : _indexOf(name!, family);
        final parts = <String>[];
        var hasElements = false;
        for (final node in property.children) {
          final String? text;
          if (node is XmlText) {
            text = node.text;
          } else if (node is XmlCdata) {
            text = node.text;
          } else {
            text = null;
            if (node is XmlElement) hasElements = true;
          }
          if (text == null) continue;
          totalTextLength += text.length;
          if (totalTextLength > 2 * 1024 * 1024) {
            throw const FormatException('ODT metadata text exceeds its limit.');
          }
          if (family != null) {
            preferenceTextLength += text.length;
            if (preferenceTextLength > maxDataLength) {
              throw const FormatException(
                'Zotero document preferences exceed the limit.',
              );
            }
          }
          parts.add(text);
        }
        final value = hasElements ? null : parts.join();
        properties.add(
          OdfZoteroPreferenceProperty._(
            ownerIndex: currentOwnerIndex,
            propertyIndex: currentPropertyIndex,
            nameAttributes: names,
            name: name,
            valueType: type,
            value: value,
            family: family,
            index: index,
          ),
        );
        if (family == null) continue;
        void issue(OdfZoteroPreferenceIssueCode code, String message) => issues
            .add(OdfZoteroPreferenceIssue(code, message, propertyName: name));
        if (names.length != 1 || types.length > 1) {
          issue(
            OdfZoteroPreferenceIssueCode.invalidPropertyAttributes,
            'A Zotero preference property has ambiguous qualified attributes.',
          );
        }
        if (index == null) {
          issue(
            OdfZoteroPreferenceIssueCode.invalidIndex,
            'A Zotero preference chunk needs a canonical positive index.',
          );
        }
        if (type != 'string') {
          issue(
            OdfZoteroPreferenceIssueCode.invalidType,
            'A Zotero preference chunk must have string value type.',
          );
        }
        if (value == null) {
          issue(
            OdfZoteroPreferenceIssueCode.nestedValue,
            'A Zotero preference chunk contains unsupported child elements.',
          );
        } else if (value.length > 255) {
          issue(
            OdfZoteroPreferenceIssueCode.oversizedChunk,
            'A Zotero preference chunk exceeds 255 UTF-16 code units.',
          );
        }
      }
    }
    if (ownerCount > 1) {
      issues.add(
        const OdfZoteroPreferenceIssue(
          OdfZoteroPreferenceIssueCode.duplicateMetaOwner,
          'Multiple direct office:meta owners make preferences ambiguous.',
        ),
      );
    }

    final chunks = properties
        .where((property) => property.family != null)
        .toList();
    if (chunks.isEmpty) return result(rawData: issues.isEmpty ? '' : null);
    final families = chunks.map((property) => property.family!).toSet();
    var family = families.length == 1 ? families.single : null;
    final indexes = <OdfZoteroPreferenceFamily, Set<int>>{};
    for (final chunk in chunks) {
      final index = chunk.index;
      if (index == null) continue;
      final used = indexes.putIfAbsent(chunk.family!, () => <int>{});
      if (!used.add(index)) {
        issues.add(
          OdfZoteroPreferenceIssue(
            OdfZoteroPreferenceIssueCode.duplicateChunk,
            'A Zotero preference chunk index occurs more than once.',
            propertyName: chunk.name,
          ),
        );
      }
    }
    for (final used in indexes.values) {
      final sorted = used.toList()..sort();
      if (Iterable<int>.generate(
        sorted.length,
      ).any((index) => sorted[index] != index + 1)) {
        issues.add(
          const OdfZoteroPreferenceIssue(
            OdfZoteroPreferenceIssueCode.missingChunk,
            'Zotero preference chunks must be contiguous and start at one.',
          ),
        );
      }
    }
    if (issues.isNotEmpty) return result(rawData: null, family: family);

    chunks.sort((left, right) => left.index!.compareTo(right.index!));
    final familyData = <OdfZoteroPreferenceFamily, String>{
      for (final currentFamily in families)
        currentFamily: chunks
            .where((chunk) => chunk.family == currentFamily)
            .map((chunk) => chunk.value!)
            .join(),
    };
    final nonempty = familyData.entries.where(
      (entry) => entry.value.isNotEmpty,
    );
    if (nonempty.length > 1) {
      issues.add(
        const OdfZoteroPreferenceIssue(
          OdfZoteroPreferenceIssueCode.conflictingFamilies,
          'ZOTERO_PREF and CSL_PREF both contain data; neither is selected silently.',
        ),
      );
      return result(rawData: null);
    }
    family =
        nonempty.firstOrNull?.key ??
        (families.contains(OdfZoteroPreferenceFamily.zotero)
            ? OdfZoteroPreferenceFamily.zotero
            : OdfZoteroPreferenceFamily.csl);
    final data = familyData[family]!;
    String? fieldType;
    try {
      // Validation only: the normalized return value is deliberately discarded.
      WordZoteroDocumentData.fromTransfer(data);
      if (data.isNotEmpty) {
        if (data.trim().startsWith('{')) {
          final decoded = jsonDecode(data) as Map<String, Object?>;
          fieldType =
              (decoded['prefs'] as Map<String, Object?>)['fieldType'] as String;
        } else {
          final preferences = XmlDocument.parse(
            data,
          ).root!.childrenNamed('prefs', namespaceUri: '').single;
          fieldType = preferences
              .childrenNamed('pref', namespaceUri: '')
              .singleWhere((pref) => pref.getAttribute('name') == 'fieldType')
              .getAttribute('value');
        }
      }
    } on FormatException catch (error) {
      issues.add(
        OdfZoteroPreferenceIssue(
          OdfZoteroPreferenceIssueCode.malformedData,
          'Invalid Zotero preference data: ${error.message}',
        ),
      );
    }
    if (fieldType != null && fieldType != 'ReferenceMark') {
      issues.add(
        OdfZoteroPreferenceIssue(
          OdfZoteroPreferenceIssueCode.unsupportedStorageType,
          'The saved $fieldType storage is not a native ReferenceMark inventory.',
        ),
      );
    }
    return result(rawData: data, family: family, fieldType: fieldType);
  }

  static OdfZoteroPreferenceFamily? _familyOf(String name) {
    if (name == 'ZOTERO_PREF' || name.startsWith('ZOTERO_PREF_')) {
      return OdfZoteroPreferenceFamily.zotero;
    }
    if (name == 'CSL_PREF' || name.startsWith('CSL_PREF_')) {
      return OdfZoteroPreferenceFamily.csl;
    }
    return null;
  }

  static int? _indexOf(String name, OdfZoteroPreferenceFamily family) {
    final prefix = family == OdfZoteroPreferenceFamily.zotero
        ? 'ZOTERO_PREF_'
        : 'CSL_PREF_';
    if (!name.startsWith(prefix)) return null;
    final suffix = name.substring(prefix.length);
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(suffix)) return null;
    final index = int.tryParse(suffix);
    // Count is bounded too; refusing larger indexes avoids sparse index scans.
    return index == null || index > 4096 ? null : index;
  }
}
