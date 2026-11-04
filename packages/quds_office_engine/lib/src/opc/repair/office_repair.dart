import 'dart:convert';
import 'dart:typed_data';

import '../../xml/namespaces.dart';
import '../../xml/xml_reader.dart';
import '../content_types.dart';
import '../crypto/office_crypto.dart';
import '../ole/cfbf_reader.dart';
import '../opc_archive.dart';
import '../package_part.dart';
import '../relationships.dart';
import '../zip/zip_reader.dart';
import '../zip/zip_writer.dart';
import 'xml_repair.dart';
import 'zip_recovery.dart';

/// Enum OfficeIssueSeverity.
enum OfficeIssueSeverity { info, warning, error, fatal }

/// Enum OfficeIssueCode.
enum OfficeIssueCode {
  emptyFile,
  unknownFormat,
  passwordRequired,
  passwordIncorrect,
  leadingJunk,
  missingZipDirectory,
  corruptZipEntry,
  missingContentTypes,
  missingPackageRels,
  missingOfficeDocument,
  missingPart,
  brokenXml,
  illegalXmlCharacters,
  missingWorksheet,
  missingSharedStrings,
}

/// Class OfficeIssue.
class OfficeIssue {
  /// OfficeIssue API.
  const OfficeIssue({
    required this.code,
    required this.severity,
    required this.message,
    this.partUri,
    this.repairable = false,
  });

  /// code API.
  final OfficeIssueCode code;

  /// severity API.
  final OfficeIssueSeverity severity;

  /// message API.
  final String message;

  /// partUri API.
  final String? partUri;

  /// repairable API.
  final bool repairable;

  @override
  bool operator ==(Object other) {
    return other is OfficeIssue &&
        other.code == code &&
        other.severity == severity &&
        other.message == message &&
        other.partUri == partUri &&
        other.repairable == repairable;
  }

  @override
  /// hashCode API.
  int get hashCode => Object.hash(code, severity, message, partUri, repairable);
}

/// Class OfficeDiagnosis.
class OfficeDiagnosis {
  /// OfficeDiagnosis API.
  OfficeDiagnosis({
    required this.kind,
    required this.encrypted,
    required this.issues,
  });

  /// kind API.
  final OpcPackageKind kind;

  /// encrypted API.
  final bool encrypted;

  /// issues API.
  final List<OfficeIssue> issues;

  /// canOpen API.
  bool get canOpen =>
      !issues.any((OfficeIssue i) => i.severity == OfficeIssueSeverity.fatal);

  /// needsRepair API.
  bool get needsRepair => issues.any(
    (OfficeIssue i) =>
        i.severity == OfficeIssueSeverity.error ||
        i.severity == OfficeIssueSeverity.warning,
  );

  /// canRepair API.
  bool get canRepair => issues.any((OfficeIssue i) => i.repairable);
}

/// Class OfficeRepairResult.
class OfficeRepairResult {
  /// OfficeRepairResult API.
  OfficeRepairResult({
    required this.diagnosis,
    required this.repaired,
    required this.remaining,
    this.bytes,
    this.package,
  });

  /// diagnosis API.
  final OfficeDiagnosis diagnosis;

  /// repaired API.
  final List<OfficeIssue> repaired;

  /// remaining API.
  final List<OfficeIssue> remaining;

  /// bytes API.
  final Uint8List? bytes;

  /// package API.
  final OpcPackage? package;

  /// succeeded API.
  bool get succeeded => package != null && bytes != null;
}

/// Class OfficeRepairException.
class OfficeRepairException implements Exception {
  /// OfficeRepairException API.
  OfficeRepairException(this.result);

  /// result API.
  final OfficeRepairResult result;
  @override
  /// toString API.
  String toString() {
    final String msgs = result.remaining
        .map((OfficeIssue i) => i.message)
        .join('; ');
    return 'OfficeRepairException: $msgs';
  }
}

/// Diagnoses why an Office file will not open and rebuilds a clean package
/// when the damage is recoverable.
abstract final class OfficeRepair {
  /// diagnose API.
  static OfficeDiagnosis diagnose(Uint8List bytes, {String? password}) {
    return _run(bytes, password: password, apply: false).diagnosis;
  }

  /// repair API.
  static OfficeRepairResult repair(Uint8List bytes, {String? password}) {
    return _run(bytes, password: password, apply: true);
  }

  /// Opens [bytes] strictly, then falls back to [repair] when the package
  /// cannot be read.
  static OpcPackage open(Uint8List bytes, {String? password}) {
    try {
      return OpcPackage.openBytes(bytes, password: password);
    } on OfficePasswordException {
      rethrow;
    } on Object {
      final OfficeRepairResult result = repair(bytes, password: password);
      if (result.package != null) {
        return result.package!;
      }
      throw OfficeRepairException(result);
    }
  }

  static OfficeRepairResult _run(
    Uint8List bytes, {
    String? password,
    required bool apply,
  }) {
    final List<OfficeIssue> issues = <OfficeIssue>[];
    final List<OfficeIssue> repaired = <OfficeIssue>[];
    if (bytes.isEmpty || bytes.length < 8) {
      final OfficeIssue empty = OfficeIssue(
        code: OfficeIssueCode.emptyFile,
        severity: OfficeIssueSeverity.fatal,
        message: 'File is empty or too small to be an Office package',
      );
      issues.add(empty);
      return OfficeRepairResult(
        diagnosis: OfficeDiagnosis(
          kind: OpcPackageKind.unknown,
          encrypted: false,
          issues: issues,
        ),
        repaired: repaired,
        remaining: issues,
      );
    }

    var working = bytes;
    if (OfficeCrypto.isEncrypted(working)) {
      if (password == null || password.isEmpty) {
        issues.add(
          const OfficeIssue(
            code: OfficeIssueCode.passwordRequired,
            severity: OfficeIssueSeverity.fatal,
            message: 'File is encrypted and a password is required',
          ),
        );
        return OfficeRepairResult(
          diagnosis: OfficeDiagnosis(
            kind: OpcPackageKind.unknown,
            encrypted: true,
            issues: issues,
          ),
          repaired: repaired,
          remaining: issues,
        );
      }
      try {
        working = OfficeCrypto.decrypt(working, password);
      } on OfficePasswordException catch (e) {
        issues.add(
          OfficeIssue(
            code: OfficeIssueCode.passwordIncorrect,
            severity: OfficeIssueSeverity.fatal,
            message: e.message,
          ),
        );
        return OfficeRepairResult(
          diagnosis: OfficeDiagnosis(
            kind: OpcPackageKind.unknown,
            encrypted: true,
            issues: issues,
          ),
          repaired: repaired,
          remaining: issues,
        );
      }
    } else if (CfbfFile.isCfbf(working)) {
      issues.add(
        const OfficeIssue(
          code: OfficeIssueCode.unknownFormat,
          severity: OfficeIssueSeverity.fatal,
          message: 'Compound file is not a recognized encrypted Office package',
        ),
      );
      return OfficeRepairResult(
        diagnosis: OfficeDiagnosis(
          kind: OpcPackageKind.unknown,
          encrypted: false,
          issues: issues,
        ),
        repaired: repaired,
        remaining: issues,
      );
    }

    final int local = ZipRecovery.firstLocalHeader(working);
    if (local < 0) {
      issues.add(
        const OfficeIssue(
          code: OfficeIssueCode.unknownFormat,
          severity: OfficeIssueSeverity.fatal,
          message: 'No ZIP local file header (PK) was found',
        ),
      );
      return OfficeRepairResult(
        diagnosis: OfficeDiagnosis(
          kind: OpcPackageKind.unknown,
          encrypted: false,
          issues: issues,
        ),
        repaired: repaired,
        remaining: issues,
      );
    }
    if (local > 0) {
      final OfficeIssue junk = OfficeIssue(
        code: OfficeIssueCode.leadingJunk,
        severity: OfficeIssueSeverity.error,
        message: 'Ignored $local leading bytes before the ZIP archive',
        repairable: true,
      );
      issues.add(junk);
      working = ZipRecovery.stripLeadingJunk(working);
      if (apply) {
        repaired.add(junk);
      }
    }

    ZipReader? zip = ZipRecovery.tryOpen(working);
    if (zip == null) {
      final OfficeIssue missingCd = const OfficeIssue(
        code: OfficeIssueCode.missingZipDirectory,
        severity: OfficeIssueSeverity.error,
        message: 'ZIP central directory is missing or unreadable',
        repairable: true,
      );
      issues.add(missingCd);
      final Uint8List? rebuilt = ZipRecovery.rebuildFromLocalHeaders(working);
      if (rebuilt == null) {
        issues.removeLast();
        issues.add(
          const OfficeIssue(
            code: OfficeIssueCode.missingZipDirectory,
            severity: OfficeIssueSeverity.fatal,
            message:
                'ZIP central directory is missing and local headers '
                'could not be recovered',
          ),
        );
        return OfficeRepairResult(
          diagnosis: OfficeDiagnosis(
            kind: OpcPackageKind.unknown,
            encrypted: false,
            issues: issues,
          ),
          repaired: repaired,
          remaining: issues,
        );
      }
      working = rebuilt;
      zip = ZipRecovery.tryOpen(working);
      if (zip != null && apply) {
        repaired.add(missingCd);
      }
    }
    if (zip == null) {
      return OfficeRepairResult(
        diagnosis: OfficeDiagnosis(
          kind: OpcPackageKind.unknown,
          encrypted: false,
          issues: issues,
        ),
        repaired: repaired,
        remaining: issues,
      );
    }

    final Map<String, Uint8List> parts = <String, Uint8List>{};
    for (final ZipEntry entry in zip.entries) {
      if (entry.isDirectory) {
        continue;
      }
      try {
        parts[entry.fileName] = zip.read(entry.fileName);
      } on Object {
        final OfficeIssue corrupt = OfficeIssue(
          code: OfficeIssueCode.corruptZipEntry,
          severity: OfficeIssueSeverity.warning,
          message: 'ZIP entry ${entry.fileName} failed CRC/size checks',
          partUri: entry.fileName,
          repairable: true,
        );
        issues.add(corrupt);
        try {
          parts[entry.fileName] = zip.readRelaxed(entry.fileName);
          if (apply) {
            repaired.add(corrupt);
          }
        } on Object {
          // drop unreadable member
        }
      }
    }

    _repairXmlParts(parts, issues, repaired, apply: apply);
    final OpcPackageKind kind = _inferKind(parts);
    _ensurePackageSkeleton(parts, kind, issues, repaired, apply: apply);
    _ensureWorkbookSheets(parts, issues, repaired, apply: apply);

    if (!apply) {
      return OfficeRepairResult(
        diagnosis: OfficeDiagnosis(
          kind: kind,
          encrypted: false,
          issues: issues,
        ),
        repaired: const <OfficeIssue>[],
        remaining: issues,
      );
    }

    _syncContentTypes(parts);
    final ZipWriter writer = ZipWriter();
    for (final MapEntry<String, Uint8List> e in parts.entries) {
      writer.addFile(e.key, e.value);
    }
    final Uint8List clean = writer.close();
    OpcPackage? package;
    try {
      package = OpcPackage.openBytes(clean);
    } on Object {
      issues.add(
        const OfficeIssue(
          code: OfficeIssueCode.unknownFormat,
          severity: OfficeIssueSeverity.fatal,
          message: 'Repaired archive still cannot be opened as an OPC package',
        ),
      );
    }
    return OfficeRepairResult(
      diagnosis: OfficeDiagnosis(kind: kind, encrypted: false, issues: issues),
      repaired: repaired,
      remaining: <OfficeIssue>[
        for (final OfficeIssue i in issues)
          if (!repaired.contains(i)) i,
      ],
      bytes: package == null ? null : clean,
      package: package,
    );
  }

  static void _repairXmlParts(
    Map<String, Uint8List> parts,
    List<OfficeIssue> issues,
    List<OfficeIssue> repaired, {
    required bool apply,
  }) {
    for (final String name in parts.keys.toList()) {
      final Uint8List raw = parts[name]!;
      if (!XmlRepair.looksLikeXml(raw)) {
        continue;
      }
      var text = XmlRepair.decode(raw);
      final bool hadNulls = raw.contains(0);
      if (hadNulls) {
        final OfficeIssue nuls = OfficeIssue(
          code: OfficeIssueCode.illegalXmlCharacters,
          severity: OfficeIssueSeverity.warning,
          message: 'Removed NUL bytes from $name',
          partUri: name,
          repairable: true,
        );
        issues.add(nuls);
        if (apply) {
          repaired.add(nuls);
        }
      }
      final String sanitized = XmlRepair.sanitize(text);
      if (sanitized != text) {
        final OfficeIssue xml = OfficeIssue(
          code: OfficeIssueCode.brokenXml,
          severity: OfficeIssueSeverity.error,
          message: 'Recovered well-formed XML in $name',
          partUri: name,
          repairable: true,
        );
        issues.add(xml);
        text = sanitized;
        if (apply) {
          repaired.add(xml);
        }
      }
      if (apply) {
        parts[name] = Uint8List.fromList(utf8.encode(text));
      }
    }
  }

  static OpcPackageKind _inferKind(Map<String, Uint8List> parts) {
    if (parts.containsKey('word/document.xml')) {
      return OpcPackageKind.word;
    }
    if (parts.containsKey('xl/workbook.xml')) {
      return OpcPackageKind.sheet;
    }
    if (parts.containsKey('ppt/presentation.xml')) {
      return OpcPackageKind.slide;
    }
    return OpcPackageKind.unknown;
  }

  static void _ensurePackageSkeleton(
    Map<String, Uint8List> parts,
    OpcPackageKind kind,
    List<OfficeIssue> issues,
    List<OfficeIssue> repaired, {
    required bool apply,
  }) {
    if (!parts.containsKey('[Content_Types].xml')) {
      final OfficeIssue issue = const OfficeIssue(
        code: OfficeIssueCode.missingContentTypes,
        severity: OfficeIssueSeverity.error,
        message: 'Rebuilt [Content_Types].xml from known parts',
        repairable: true,
      );
      issues.add(issue);
      if (apply) {
        parts['[Content_Types].xml'] = _contentTypesXml(parts);
        repaired.add(issue);
      }
    }
    if (!parts.containsKey('_rels/.rels')) {
      final OfficeIssue issue = const OfficeIssue(
        code: OfficeIssueCode.missingPackageRels,
        severity: OfficeIssueSeverity.error,
        message: 'Rebuilt package relationships (_rels/.rels)',
        repairable: true,
      );
      issues.add(issue);
      if (apply) {
        parts['_rels/.rels'] = utf8.encode(_packageRelsXml(kind));
        repaired.add(issue);
      }
    } else if (!_hasOfficeDocumentRel(parts['_rels/.rels']!)) {
      final OfficeIssue issue = const OfficeIssue(
        code: OfficeIssueCode.missingOfficeDocument,
        severity: OfficeIssueSeverity.error,
        message: 'Added missing officeDocument relationship',
        repairable: true,
      );
      issues.add(issue);
      if (apply) {
        parts['_rels/.rels'] = utf8.encode(_packageRelsXml(kind));
        repaired.add(issue);
      }
    }

    switch (kind) {
      case OpcPackageKind.word:
        if (!parts.containsKey('word/document.xml')) {
          final OfficeIssue issue = const OfficeIssue(
            code: OfficeIssueCode.missingPart,
            severity: OfficeIssueSeverity.error,
            message: 'Created an empty word/document.xml',
            partUri: 'word/document.xml',
            repairable: true,
          );
          issues.add(issue);
          if (apply) {
            parts['word/document.xml'] = utf8.encode(
              '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<w:document xmlns:w="${OfficeNamespaces.w}">'
              '<w:body><w:p/></w:body></w:document>',
            );
            repaired.add(issue);
          }
        }
      case OpcPackageKind.sheet:
        if (!parts.containsKey('xl/workbook.xml')) {
          final OfficeIssue issue = const OfficeIssue(
            code: OfficeIssueCode.missingPart,
            severity: OfficeIssueSeverity.error,
            message: 'Created an empty xl/workbook.xml',
            partUri: 'xl/workbook.xml',
            repairable: true,
          );
          issues.add(issue);
          if (apply) {
            parts['xl/workbook.xml'] = utf8.encode(
              '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<workbook xmlns="${OfficeNamespaces.x}" xmlns:r="${OfficeNamespaces.r}">'
              '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>'
              '</workbook>',
            );
            parts['xl/worksheets/sheet1.xml'] = utf8.encode(
              '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<worksheet xmlns="${OfficeNamespaces.x}"><sheetData/></worksheet>',
            );
            parts['xl/_rels/workbook.xml.rels'] = utf8.encode(
              '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<Relationships xmlns="${OfficeNamespaces.relationships}">'
              '<Relationship Id="rId1" Type="${RelationshipTypes.worksheet}" '
              'Target="worksheets/sheet1.xml"/></Relationships>',
            );
            repaired.add(issue);
          }
        }
      case OpcPackageKind.slide:
        if (!parts.containsKey('ppt/presentation.xml')) {
          final OfficeIssue issue = const OfficeIssue(
            code: OfficeIssueCode.missingPart,
            severity: OfficeIssueSeverity.error,
            message: 'Created an empty ppt/presentation.xml',
            partUri: 'ppt/presentation.xml',
            repairable: true,
          );
          issues.add(issue);
          if (apply) {
            parts['ppt/presentation.xml'] = utf8.encode(
              '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<p:presentation xmlns:p="${OfficeNamespaces.p}" '
              'xmlns:r="${OfficeNamespaces.r}">'
              '<p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst>'
              '</p:presentation>',
            );
            repaired.add(issue);
          }
        }
      case OpcPackageKind.unknown:
        break;
    }
  }

  static void _ensureWorkbookSheets(
    Map<String, Uint8List> parts,
    List<OfficeIssue> issues,
    List<OfficeIssue> repaired, {
    required bool apply,
  }) {
    final Uint8List? wb = parts['xl/workbook.xml'];
    if (wb == null) {
      return;
    }
    RelationshipCollection rels;
    try {
      rels = parts.containsKey('xl/_rels/workbook.xml.rels')
          ? RelationshipCollection.parse(
              XmlRepair.sanitize(
                XmlRepair.decode(parts['xl/_rels/workbook.xml.rels']!),
              ),
              '/xl/workbook.xml',
            )
          : RelationshipCollection(sourcePartUri: '/xl/workbook.xml');
    } on Object {
      rels = RelationshipCollection(sourcePartUri: '/xl/workbook.xml');
    }
    final XmlPullReader reader = XmlPullReader(
      XmlRepair.sanitize(XmlRepair.decode(wb)),
    );
    try {
      _scanWorkbookSheets(reader, rels, parts, issues, repaired, apply: apply);
    } on Object {
      // Workbook markup is still unreadable after sanitizing.
    }
  }

  static void _scanWorkbookSheets(
    XmlPullReader reader,
    RelationshipCollection rels,
    Map<String, Uint8List> parts,
    List<OfficeIssue> issues,
    List<OfficeIssue> repaired, {
    required bool apply,
  }) {
    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement ||
          reader.localName != 'sheet') {
        continue;
      }
      final String? rid =
          reader.getAttribute('id', namespaceUri: OfficeNamespaces.r) ??
          reader.getAttribute('id');
      if (rid == null) {
        continue;
      }
      final PackageRelationship? rel = rels.byId(rid);
      final String target = rel == null ? 'worksheets/sheet1.xml' : rel.target;
      final String zipName = OpcUris.toZipName(
        OpcUris.resolve('/xl/workbook.xml', target),
      );
      if (parts.containsKey(zipName)) {
        continue;
      }
      final OfficeIssue issue = OfficeIssue(
        code: OfficeIssueCode.missingWorksheet,
        severity: OfficeIssueSeverity.error,
        message: 'Created missing worksheet $zipName',
        partUri: zipName,
        repairable: true,
      );
      issues.add(issue);
      if (apply) {
        parts[zipName] = utf8.encode(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<worksheet xmlns="${OfficeNamespaces.x}"><sheetData/></worksheet>',
        );
        repaired.add(issue);
      }
    }
    final bool usesShared = parts.values.any(
      (Uint8List b) =>
          XmlRepair.looksLikeXml(b) && XmlRepair.decode(b).contains('t="s"'),
    );
    if (usesShared && !parts.containsKey('xl/sharedStrings.xml')) {
      final OfficeIssue issue = const OfficeIssue(
        code: OfficeIssueCode.missingSharedStrings,
        severity: OfficeIssueSeverity.warning,
        message: 'Created empty sharedStrings.xml referenced by cells',
        partUri: 'xl/sharedStrings.xml',
        repairable: true,
      );
      issues.add(issue);
      if (apply) {
        parts['xl/sharedStrings.xml'] = utf8.encode(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<sst xmlns="${OfficeNamespaces.x}" count="0" uniqueCount="0"/>',
        );
        repaired.add(issue);
      }
    }
  }

  static bool _hasOfficeDocumentRel(Uint8List rels) {
    try {
      final RelationshipCollection parsed = RelationshipCollection.parse(
        XmlRepair.decode(rels),
        '/',
      );
      return parsed.firstByType(RelationshipTypes.officeDocument) != null;
    } on Object {
      return false;
    }
  }

  static String _packageRelsXml(OpcPackageKind kind) {
    final String target = switch (kind) {
      OpcPackageKind.word => 'word/document.xml',
      OpcPackageKind.sheet => 'xl/workbook.xml',
      OpcPackageKind.slide => 'ppt/presentation.xml',
      OpcPackageKind.unknown => 'word/document.xml',
    };
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="${OfficeNamespaces.relationships}">'
        '<Relationship Id="rId1" Type="${RelationshipTypes.officeDocument}" '
        'Target="$target"/></Relationships>';
  }

  static void _syncContentTypes(Map<String, Uint8List> parts) {
    parts['[Content_Types].xml'] = _contentTypesXml(parts);
  }

  static Uint8List _contentTypesXml(Map<String, Uint8List> parts) {
    ContentTypes types;
    final Uint8List? existing = parts['[Content_Types].xml'];
    if (existing != null) {
      try {
        types = ContentTypes.parse(XmlRepair.decode(existing));
      } on Object {
        types = ContentTypes.standard();
      }
    } else {
      types = ContentTypes.standard();
    }
    for (final String name in parts.keys) {
      final String uri = OpcUris.fromZipName(name);
      if (OpcUris.isContentTypes(uri)) {
        continue;
      }
      types.setOverride(uri, _typeFor(uri));
    }
    return Uint8List.fromList(utf8.encode(types.toXml()));
  }

  static String _typeFor(String uri) {
    if (uri.endsWith('.rels')) {
      return OfficeContentTypes.relationships;
    }
    if (uri == '/word/document.xml') {
      return OfficeContentTypes.wordMain;
    }
    if (uri == '/word/styles.xml') {
      return OfficeContentTypes.wordStyles;
    }
    if (uri == '/xl/workbook.xml') {
      return OfficeContentTypes.sheetMain;
    }
    if (uri.contains('/xl/worksheets/')) {
      return OfficeContentTypes.sheetWorksheet;
    }
    if (uri == '/xl/sharedStrings.xml') {
      return OfficeContentTypes.sheetSharedStrings;
    }
    if (uri == '/xl/styles.xml') {
      return OfficeContentTypes.sheetStyles;
    }
    if (uri == '/ppt/presentation.xml') {
      return OfficeContentTypes.slideMain;
    }
    if (uri.contains('/ppt/slides/slide')) {
      return OfficeContentTypes.slide;
    }
    if (uri.contains('/ppt/slideLayouts/')) {
      return OfficeContentTypes.slideLayout;
    }
    if (uri.contains('/ppt/slideMasters/')) {
      return OfficeContentTypes.slideMaster;
    }
    if (uri.endsWith('.png')) {
      return 'image/png';
    }
    if (uri.endsWith('.xml')) {
      return 'application/xml';
    }
    return 'application/octet-stream';
  }
}
