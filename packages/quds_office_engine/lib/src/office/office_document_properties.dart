import 'dart:convert';

import '../opc/content_types.dart';
import '../opc/opc_archive.dart';
import '../xml/namespaces.dart';
import '../xml/xml_reader.dart';

/// Dublin Core / App properties stored in `docProps/core.xml` and `app.xml`.
class OfficeDocumentProperties {
  /// OfficeDocumentProperties API.
  OfficeDocumentProperties({
    this.title = '',
    this.subject = '',
    this.creator = '',
    this.keywords = '',
    this.description = '',
    this.lastModifiedBy = '',
    this.company = '',
    this.category = '',
    this.revision = '1',
    this.createdIso = '',
    this.modifiedIso = '',
  });

  /// title API.
  String title;

  /// subject API.
  String subject;

  /// creator API.
  String creator;

  /// keywords API.
  String keywords;

  /// description API.
  String description;

  /// lastModifiedBy API.
  String lastModifiedBy;

  /// company API.
  String company;

  /// category API.
  String category;

  /// revision API.
  String revision;

  /// createdIso API.
  String createdIso;

  /// modifiedIso API.
  String modifiedIso;

  /// copy API.
  OfficeDocumentProperties copy() => OfficeDocumentProperties(
    title: title,
    subject: subject,
    creator: creator,
    keywords: keywords,
    description: description,
    lastModifiedBy: lastModifiedBy,
    company: company,
    category: category,
    revision: revision,
    createdIso: createdIso,
    modifiedIso: modifiedIso,
  );

  /// Reads existing core/app parts when present.
  factory OfficeDocumentProperties.fromPackage(OpcPackage? package) {
    final OfficeDocumentProperties props = OfficeDocumentProperties();
    if (package == null) {
      return props;
    }
    final String? core = package.getPart('/docProps/core.xml')?.readText();
    if (core != null) {
      _readCore(core, props);
    }
    final String? app = package.getPart('/docProps/app.xml')?.readText();
    if (app != null) {
      _readApp(app, props);
    }
    return props;
  }

  /// Writes `docProps/core.xml` and `docProps/app.xml`.
  void writeToPackage(OpcPackage package) {
    final String now = DateTime.now().toUtc().toIso8601String();
    if (createdIso.isEmpty) {
      createdIso = now;
    }
    modifiedIso = now;
    package.contentTypes.setOverride(
      '/docProps/core.xml',
      OfficeContentTypes.coreProperties,
    );
    package.contentTypes.setOverride(
      '/docProps/app.xml',
      OfficeContentTypes.extendedProperties,
    );
    if (package.getPart('/docProps/core.xml') == null) {
      package.createPart(
        '/docProps/core.xml',
        OfficeContentTypes.coreProperties,
      );
    }
    if (package.getPart('/docProps/app.xml') == null) {
      package.createPart(
        '/docProps/app.xml',
        OfficeContentTypes.extendedProperties,
      );
    }
    package.getPart('/docProps/core.xml')!.writeText(_coreXml());
    package.getPart('/docProps/app.xml')!.writeText(_appXml());
    _ensureRel(
      package,
      RelationshipTypes.coreProperties,
      'docProps/core.xml',
    );
    _ensureRel(
      package,
      RelationshipTypes.extendedProperties,
      'docProps/app.xml',
    );
  }

  static void _ensureRel(OpcPackage package, String type, String target) {
    if (package.packageRelationships.firstByType(type) != null) {
      return;
    }
    package.packageRelationships.add(type: type, target: target);
  }

  static void _readCore(String xml, OfficeDocumentProperties props) {
    final XmlPullReader reader = XmlPullReader(xml);
    var current = '';
    while (reader.next()) {
      if (reader.eventType == XmlEventType.startElement) {
        current = reader.localName;
      } else if (reader.eventType == XmlEventType.characters) {
        final String text = reader.text.trim();
        switch (current) {
          case 'title':
            props.title = text;
          case 'subject':
            props.subject = text;
          case 'creator':
            props.creator = text;
          case 'keywords':
            props.keywords = text;
          case 'description':
            props.description = text;
          case 'lastModifiedBy':
            props.lastModifiedBy = text;
          case 'revision':
            props.revision = text;
          case 'created':
            props.createdIso = text;
          case 'modified':
            props.modifiedIso = text;
          case 'category':
            props.category = text;
        }
      } else if (reader.eventType == XmlEventType.endElement) {
        current = '';
      }
    }
  }

  static void _readApp(String xml, OfficeDocumentProperties props) {
    final XmlPullReader reader = XmlPullReader(xml);
    var current = '';
    while (reader.next()) {
      if (reader.eventType == XmlEventType.startElement) {
        current = reader.localName;
      } else if (reader.eventType == XmlEventType.characters &&
          current == 'Company') {
        props.company = reader.text.trim();
      } else if (reader.eventType == XmlEventType.endElement) {
        current = '';
      }
    }
  }

  String _coreXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:title>${_esc(title)}</dc:title>'
        '<dc:subject>${_esc(subject)}</dc:subject>'
        '<dc:creator>${_esc(creator)}</dc:creator>'
        '<cp:keywords>${_esc(keywords)}</cp:keywords>'
        '<dc:description>${_esc(description)}</dc:description>'
        '<cp:lastModifiedBy>${_esc(lastModifiedBy)}</cp:lastModifiedBy>'
        '<cp:revision>${_esc(revision)}</cp:revision>'
        '<cp:category>${_esc(category)}</cp:category>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">${_esc(createdIso)}</dcterms:created>'
        '<dcterms:modified xsi:type="dcterms:W3CDTF">${_esc(modifiedIso)}</dcterms:modified>'
        '</cp:coreProperties>';
  }

  String _appXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
        'xmlns:vt="${OfficeNamespaces.docPropsVt}">'
        '<Application>Quds Office</Application>'
        '<Company>${_esc(company)}</Company>'
        '</Properties>';
  }

  static String _esc(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}

/// UTF-8 helper used when creating empty parts.
List<int> officeEmptyXmlBytes(String xml) => utf8.encode(xml);
