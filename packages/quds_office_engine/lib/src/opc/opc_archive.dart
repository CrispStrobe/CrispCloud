import 'dart:convert';
import 'dart:typed_data';

import '../io/byte_source.dart';
import '../xml/namespaces.dart';
import 'content_types.dart';
import 'crypto/office_crypto.dart';
import 'ole/cfbf_reader.dart';
import 'package_part.dart';
import 'relationships.dart';
import 'zip/zip_reader.dart';
import 'zip/zip_writer.dart';

/// Kind of office package, inferred from the officeDocument relationship
/// and `[Content_Types].xml` overrides.
enum OpcPackageKind { word, sheet, slide, unknown }

/// In-memory OPC package backed by a streaming ZIP archive.
///
/// Part payloads are loaded lazily from the source ZIP the first time they
/// are read. Mutations stay in heap until [save] rebuilds the archive.
class OpcPackage {
  OpcPackage._({
    required this.contentTypes,
    required this._packageRelationships,
    this._source,
    Map<String, PackagePart>? parts,
  }) : _parts = parts ?? <String, PackagePart>{};

  /// contentTypes API.
  final ContentTypes contentTypes;
  final RelationshipCollection _packageRelationships;
  final ZipReader? _source;
  final Map<String, PackagePart> _parts;
  final Map<String, RelationshipCollection> _partRels =
      <String, RelationshipCollection>{};
  final Set<String> _deleted = <String>{};

  /// empty API.
  factory OpcPackage.empty() {
    return OpcPackage._(
      contentTypes: ContentTypes.standard(),
      packageRelationships: RelationshipCollection(sourcePartUri: '/'),
    );
  }

  /// openBytes API.
  factory OpcPackage.openBytes(Uint8List bytes, {String? password}) {
    return OpcPackage.open(MemoryByteSource(bytes), password: password);
  }

  /// open API.
  factory OpcPackage.open(ByteSource source, {String? password}) {
    ByteSource zipSource = source;
    if (source.length >= 8 && CfbfFile.isCfbf(source.view(0, 8))) {
      zipSource = MemoryByteSource(
        OfficeCrypto.unlock(source.read(0, source.length), password: password),
      );
    }
    final ZipReader zip = ZipReader.open(zipSource);
    final ContentTypes types;
    if (zip.contains('[Content_Types].xml')) {
      types = ContentTypes.parse(utf8.decode(zip.read('[Content_Types].xml')));
    } else {
      types = ContentTypes.standard();
    }

    RelationshipCollection packageRels = RelationshipCollection(
      sourcePartUri: '/',
    );
    if (zip.contains('_rels/.rels')) {
      packageRels = RelationshipCollection.parse(
        utf8.decode(zip.read('_rels/.rels')),
        '/',
      );
    }

    final OpcPackage package = OpcPackage._(
      contentTypes: types,
      packageRelationships: packageRels,
      source: zip,
    );

    for (final ZipEntry entry in zip.entries) {
      if (entry.isDirectory) {
        continue;
      }
      final String opcUri = OpcUris.fromZipName(entry.fileName);
      if (OpcUris.isContentTypes(opcUri)) {
        continue;
      }
      if (OpcUris.isRelationshipsPart(opcUri)) {
        final String? owner = OpcUris.sourcePartForRelationships(opcUri);
        if (owner != null && owner != '/') {
          package._partRels[owner] = RelationshipCollection.parse(
            utf8.decode(zip.read(entry.fileName)),
            owner,
          );
        }
        continue;
      }
      package._parts[opcUri] = PackagePart(
        package: package,
        uri: opcUri,
        contentType: types.contentTypeFor(opcUri),
        loaded: false,
      );
    }
    return package;
  }

  /// Creates a minimal but valid Word / Excel / PowerPoint package shell.
  factory OpcPackage.create(OpcPackageKind kind) {
    final OpcPackage package = OpcPackage.empty();
    switch (kind) {
      case OpcPackageKind.word:
        package.contentTypes.setOverride(
          '/word/document.xml',
          OfficeContentTypes.wordMain,
        );
        package.createPart(
          '/word/document.xml',
          OfficeContentTypes.wordMain,
          utf8.encode(_wordDocumentXml),
        );
        package.packageRelationships.add(
          type: RelationshipTypes.officeDocument,
          target: 'word/document.xml',
        );
        package.relationshipsFor('/word/document.xml');
      case OpcPackageKind.sheet:
        package.contentTypes.setOverride(
          '/xl/workbook.xml',
          OfficeContentTypes.sheetMain,
        );
        package.contentTypes.setOverride(
          '/xl/worksheets/sheet1.xml',
          OfficeContentTypes.sheetWorksheet,
        );
        package.createPart(
          '/xl/workbook.xml',
          OfficeContentTypes.sheetMain,
          utf8.encode(_workbookXml),
        );
        package.createPart(
          '/xl/worksheets/sheet1.xml',
          OfficeContentTypes.sheetWorksheet,
          utf8.encode(_worksheetXml),
        );
        package.packageRelationships.add(
          type: RelationshipTypes.officeDocument,
          target: 'xl/workbook.xml',
        );
        package
            .relationshipsFor('/xl/workbook.xml')
            .add(
              type: RelationshipTypes.worksheet,
              target: 'worksheets/sheet1.xml',
            );
      case OpcPackageKind.slide:
        package.contentTypes.setOverride(
          '/ppt/presentation.xml',
          OfficeContentTypes.slideMain,
        );
        package.contentTypes.setOverride(
          '/ppt/slides/slide1.xml',
          OfficeContentTypes.slide,
        );
        package.createPart(
          '/ppt/presentation.xml',
          OfficeContentTypes.slideMain,
          utf8.encode(_presentationXml),
        );
        package.createPart(
          '/ppt/slides/slide1.xml',
          OfficeContentTypes.slide,
          utf8.encode(_slideXml),
        );
        package.packageRelationships.add(
          type: RelationshipTypes.officeDocument,
          target: 'ppt/presentation.xml',
        );
        package
            .relationshipsFor('/ppt/presentation.xml')
            .add(type: RelationshipTypes.slide, target: 'slides/slide1.xml');
      case OpcPackageKind.unknown:
        break;
    }
    return package;
  }

  /// Byte length of the original ZIP, or `0` when the package is in-memory only.
  int get sourceLength => _source?.byteLength ?? 0;

  /// packageRelationships API.
  RelationshipCollection get packageRelationships => _packageRelationships;

  /// partNames API.
  Iterable<String> get partNames => _parts.keys;

  /// parts API.
  Iterable<PackagePart> get parts => _parts.values;

  /// kind API.
  OpcPackageKind get kind {
    final PackageRelationship? office = _packageRelationships.firstByType(
      RelationshipTypes.officeDocument,
    );
    if (office == null) {
      return OpcPackageKind.unknown;
    }
    final String target = _packageRelationships.resolve(office).toLowerCase();
    if (target.contains('/word/')) {
      return OpcPackageKind.word;
    }
    if (target.contains('/xl/')) {
      return OpcPackageKind.sheet;
    }
    if (target.contains('/ppt/')) {
      return OpcPackageKind.slide;
    }
    final String type = contentTypes.contentTypeFor(target);
    if (type.contains('wordprocessingml')) {
      return OpcPackageKind.word;
    }
    if (type.contains('spreadsheetml')) {
      return OpcPackageKind.sheet;
    }
    if (type.contains('presentationml')) {
      return OpcPackageKind.slide;
    }
    return OpcPackageKind.unknown;
  }

  /// getPart API.
  PackagePart? getPart(String uri) {
    final String n = OpcUris.normalize(uri);
    final PackagePart? existing = _parts[n];
    if (existing != null) {
      _materialize(existing);
      return existing;
    }
    return null;
  }

  /// createPart API.
  PackagePart createPart(String uri, String contentType, [List<int>? bytes]) {
    final String n = OpcUris.normalize(uri);
    if (_parts.containsKey(n)) {
      throw StateError('Part already exists: $n');
    }
    contentTypes.setOverride(n, contentType);
    final PackagePart part = PackagePart(
      package: this,
      uri: n,
      contentType: contentType,
      bytes: bytes == null ? Uint8List(0) : Uint8List.fromList(bytes),
      loaded: true,
    );
    _parts[n] = part;
    _deleted.remove(n);
    return part;
  }

  /// deletePart API.
  bool deletePart(String uri) {
    final String n = OpcUris.normalize(uri);
    final bool removed = _parts.remove(n) != null;
    _partRels.remove(n);
    contentTypes.removeOverride(n);
    if (removed) {
      _deleted.add(n);
    }
    return removed;
  }

  /// relationshipsFor API.
  RelationshipCollection relationshipsFor(String partUri) {
    final String n = OpcUris.normalize(partUri);
    return _partRels.putIfAbsent(
      n,
      () => RelationshipCollection(sourcePartUri: n),
    );
  }

  /// attachRelationships API.
  void attachRelationships(String partUri, RelationshipCollection rels) {
    _partRels[OpcUris.normalize(partUri)] = rels;
  }

  /// markDirty API.
  void markDirty(PackagePart part) {
    _parts[part.uri] = part;
  }

  /// Serializes the package as a ZIP byte array (Deflate).
  ///
  /// When [password] is set, the ZIP is wrapped in MS-OFFCRYPTO Agile
  /// encryption so Word/Excel/PowerPoint prompt before opening.
  Uint8List save({int deflateLevel = 6, String? password}) {
    final ZipWriter writer = ZipWriter(deflateLevel: deflateLevel);
    writer.addFile('[Content_Types].xml', utf8.encode(contentTypes.toXml()));
    writer.addFile('_rels/.rels', utf8.encode(_packageRelationships.toXml()));
    for (final MapEntry<String, RelationshipCollection> entry
        in _partRels.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      final String relsUri = OpcUris.relationshipsUriFor(entry.key);
      writer.addFile(
        OpcUris.toZipName(relsUri),
        utf8.encode(entry.value.toXml()),
      );
    }
    for (final PackagePart part in _parts.values) {
      _materialize(part);
      writer.addFile(OpcUris.toZipName(part.uri), part.bytesView);
    }
    final Uint8List zip = writer.close();
    if (password == null || password.isEmpty) {
      return zip;
    }
    return OfficeCrypto.encrypt(zip, password);
  }

  void _materialize(PackagePart part) {
    if (part.isLoaded) {
      return;
    }
    final ZipReader? zip = _source;
    if (zip == null) {
      return;
    }
    final String zipName = OpcUris.toZipName(part.uri);
    if (!zip.contains(zipName)) {
      return;
    }
    part.writeBytes(zip.read(zipName));
  }
}

const String _wordDocumentXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:body><w:p><w:r><w:t></w:t></w:r></w:p></w:body></w:document>';

const String _workbookXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>';

const String _worksheetXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<sheetData/></worksheet>';

const String _presentationXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    '<p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst>'
    '</p:presentation>';

const String _slideXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
    '<p:cSld><p:spTree>'
    '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
    '<p:grpSpPr/>'
    '</p:spTree></p:cSld></p:sld>';
