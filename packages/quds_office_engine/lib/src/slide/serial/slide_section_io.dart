import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../model/pml_arrange.dart';
import '../model/pml_presentation.dart';

/// Native p14 section membership and opaque-property preservation.
/// MS-PPTX 2.3.3.24–27: a section has a GUID and an explicit, possibly empty,
/// slide ID list, followed by an optional extension list.
abstract final class SlideSectionXml {
  static const String namespace =
      'http://schemas.microsoft.com/office/powerpoint/2010/main';
  static const String extensionUri = '{521415D9-36F7-43E2-AB2F-B90AF26B5E84}';

  static void read(
    PmlPresentation presentation,
    XmlElement root, {
    String? slideRelationshipIssue,
  }) {
    final List<int> slideIds = [
      for (final slide in presentation.slides) slide.id,
    ];
    final List<XmlElement> lists = _descendants(root, 'sectionLst', namespace);
    final List<XmlElement> extensions = _extensions(root);
    final bool legacy =
        root.firstChild('sldSections', namespaceUri: OfficeNamespaces.p) !=
        null;
    if (lists.isEmpty && extensions.isEmpty && !legacy) return;

    void reject(String issue) {
      presentation.sections.clear();
      presentation.sectionSource = PmlSectionSource(
        slideIds: slideIds,
        issue: issue,
      );
    }

    if (legacy ||
        lists.length != 1 ||
        extensions.length != 1 ||
        !identical(lists.single.parent, extensions.single)) {
      reject(
        'Section markup is ambiguous or uses an unmodeled representation.',
      );
      return;
    }
    if (slideRelationshipIssue != null) {
      reject(slideRelationshipIssue);
      return;
    }
    final XmlElement list = lists.single;
    final List<XmlElement> sections = list.childrenNamed(
      'section',
      namespaceUri: namespace,
    );
    if (sections.isEmpty || sections.length != list.childElements.length) {
      reject('Native section list contains unmodeled children.');
      return;
    }
    final List<List<int>> members = <List<int>>[];
    for (final XmlElement section in sections) {
      final List<XmlElement> ids = section.childrenNamed(
        'sldIdLst',
        namespaceUri: namespace,
      );
      if (ids.length != 1 ||
          section.childElements.any(
            (child) =>
                child.namespaceUri != namespace ||
                !{'sldIdLst', 'extLst'}.contains(child.localName),
          )) {
        reject('Native section has an unmodeled membership representation.');
        return;
      }
      final List<int> values = <int>[];
      for (final XmlElement child in ids.single.childElements) {
        final int? id = int.tryParse(
          child.getAttribute('id', namespaceUri: '') ?? '',
        );
        if (child.namespaceUri != namespace ||
            child.localName != 'sldId' ||
            child.childElements.isNotEmpty ||
            child.attributes.any(
              (attribute) =>
                  !(attribute.localName == 'id' &&
                      attribute.namespaceUri.isEmpty) &&
                  attribute.prefix != 'xmlns' &&
                  attribute.qualifiedName != 'xmlns',
            ) ||
            id == null) {
          reject(
            'Native section contains an invalid or unmodeled slide reference.',
          );
          return;
        }
        values.add(id);
      }
      members.add(values);
    }
    final List<int> flattened = members.expand((values) => values).toList();
    final int prefix = flattened.isEmpty
        ? slideIds.length
        : slideIds.indexOf(flattened.first);
    if (slideIds.toSet().length != slideIds.length ||
        prefix < 0 ||
        flattened.length != slideIds.length - prefix ||
        !List.generate(
          flattened.length,
          (i) => flattened[i] == slideIds[prefix + i],
        ).every((same) => same)) {
      reject(
        'Native section membership is overlapping, nonconsecutive, incomplete, or orphaned.',
      );
      return;
    }
    var start = prefix;
    for (int i = 0; i < sections.length; i++) {
      final XmlElement section = sections[i];
      presentation.sections.add(
        PmlSection(
          name: section.getAttribute('name', namespaceUri: '') ?? 'Section',
          startIndex: start,
          id: section.getAttribute('id', namespaceUri: ''),
          nativeXml: section.copy(),
        ),
      );
      start += members[i].length;
    }
    try {
      PmlSections.validate(presentation);
    } on StateError catch (error) {
      reject(error.message.toString());
      return;
    }
    presentation.sectionSource = PmlSectionSource(slideIds: slideIds);
  }

  /// Guard before the serializer mutates the source package or model.
  static void validateForWrite(PmlPresentation presentation) {
    final PmlSectionSource? source = presentation.sectionSource;
    if (source?.issue != null) {
      final List<int> ids = [for (final slide in presentation.slides) slide.id];
      if (presentation.sections.isNotEmpty ||
          ids.length != source!.slideIds.length ||
          !List.generate(
            ids.length,
            (i) => ids[i] == source.slideIds[i],
          ).every((same) => same)) {
        throw StateError(
          'Cannot rewrite unmodeled native sections: ${source?.issue}',
        );
      }
      return;
    }
    if (presentation.sections.isNotEmpty) PmlSections.validate(presentation);
  }

  /// Replace only the native section list, keeping unrelated extensions and
  /// imported GUIDs, section properties, membership properties, and empties.
  static void write(PmlPresentation presentation, XmlElement extensions) {
    if (presentation.sectionSource?.issue != null) return;
    final List<XmlElement> native = extensions.childElements
        .where(
          (child) =>
              child.namespaceUri == OfficeNamespaces.p &&
              child.localName == 'ext' &&
              child.getAttribute('uri')?.toUpperCase() == extensionUri,
        )
        .toList();
    if (presentation.sections.isEmpty) {
      for (final XmlElement extension in native) {
        extension.children.removeWhere(
          (node) =>
              node is XmlElement &&
              node.namespaceUri == namespace &&
              node.localName == 'sectionLst',
        );
        if (extension.childElements.isEmpty) {
          extensions.children.remove(extension);
        }
      }
      return;
    }
    final XmlElement extension = native.isEmpty
        ? XmlElement(
            localName: 'ext',
            prefix: 'p',
            namespaceUri: OfficeNamespaces.p,
            attributes: [XmlAttribute(localName: 'uri', value: extensionUri)],
          )
        : native.single;
    if (native.isEmpty) extensions.addChild(extension);
    XmlElement? list = extension.firstChild(
      'sectionLst',
      namespaceUri: namespace,
    );
    if (list == null) {
      list = XmlElement(
        localName: 'sectionLst',
        prefix: 'p14',
        namespaceUri: namespace,
        attributes: [
          XmlAttribute(localName: 'p14', prefix: 'xmlns', value: namespace),
        ],
      );
      extension.addChild(list);
    }
    final String prefix = list.prefix;
    final Map<int, XmlElement> entryTemplates = <int, XmlElement>{};
    for (final PmlSection section in presentation.sections) {
      final XmlElement? sourceIds = section.nativeXml?.firstChild(
        'sldIdLst',
        namespaceUri: namespace,
      );
      for (final XmlElement entry
          in sourceIds?.childrenNamed('sldId', namespaceUri: namespace) ??
              <XmlElement>[]) {
        final int? id = int.tryParse(
          entry.getAttribute('id', namespaceUri: '') ?? '',
        );
        if (id != null) entryTemplates[id] = entry;
      }
    }
    final Set<String> usedIds = {
      for (final section in presentation.sections)
        if (section.id != null) section.id!.toUpperCase(),
    };
    var nextId = 1;
    String allocateId() {
      while (true) {
        final String id =
            '{00000000-0000-4000-8000-${(nextId++).toRadixString(16).padLeft(12, '0')}}';
        if (usedIds.add(id.toUpperCase())) return id;
      }
    }

    final List<XmlElement> rewritten = <XmlElement>[];
    for (int index = 0; index < presentation.sections.length; index++) {
      final PmlSection section = presentation.sections[index];
      final XmlElement node =
          section.nativeXml?.copy() ??
          XmlElement(
            localName: 'section',
            prefix: prefix,
            namespaceUri: namespace,
          );
      if (node.getAttribute('name', namespaceUri: '') != null ||
          section.name != 'Section' ||
          section.nativeXml == null) {
        _setUnqualified(node, 'name', section.name);
      }
      if (section.nativeXml == null) section.id ??= allocateId();
      if (section.id != null) _setUnqualified(node, 'id', section.id!);
      XmlElement? members = node.firstChild(
        'sldIdLst',
        namespaceUri: namespace,
      );
      if (members == null) {
        members = XmlElement(
          localName: 'sldIdLst',
          prefix: prefix,
          namespaceUri: namespace,
        );
        node.children.insert(0, members..parent = node);
      }
      members.children.removeWhere(
        (child) =>
            child is XmlElement &&
            child.namespaceUri == namespace &&
            child.localName == 'sldId',
      );
      final int end = index + 1 < presentation.sections.length
          ? presentation.sections[index + 1].startIndex
          : presentation.slides.length;
      for (int slide = section.startIndex; slide < end; slide++) {
        final int id = presentation.slides[slide].id;
        final XmlElement entry =
            entryTemplates[id]?.copy() ??
            XmlElement(
              localName: 'sldId',
              prefix: members.prefix,
              namespaceUri: namespace,
              attributes: [XmlAttribute(localName: 'id', value: '$id')],
            );
        // A retained entry can move away from the section that declared its
        // prefix. Give it its own binding before changing that ancestry.
        final String declaration = entry.prefix.isEmpty
            ? 'xmlns'
            : 'xmlns:${entry.prefix}';
        entry.attributes.removeWhere(
          (attribute) => attribute.qualifiedName == declaration,
        );
        entry.attributes.add(
          XmlAttribute(
            localName: entry.prefix.isEmpty ? 'xmlns' : entry.prefix,
            prefix: entry.prefix.isEmpty ? '' : 'xmlns',
            value: namespace,
          ),
        );
        members.addChild(entry);
      }
      rewritten.add(node);
    }
    list.children.removeWhere(
      (child) =>
          child is XmlElement &&
          child.namespaceUri == namespace &&
          child.localName == 'section',
    );
    for (final XmlElement section in rewritten) {
      list.addChild(section);
    }
  }

  static void _setUnqualified(XmlElement element, String name, String value) {
    for (final XmlAttribute attribute in element.attributes) {
      if (attribute.localName == name && attribute.namespaceUri.isEmpty) {
        attribute.value = value;
        return;
      }
    }
    element.attributes.add(XmlAttribute(localName: name, value: value));
  }

  static List<XmlElement> _extensions(XmlElement root) =>
      root
          .firstChild('extLst', namespaceUri: OfficeNamespaces.p)
          ?.childElements
          .where(
            (child) =>
                child.namespaceUri == OfficeNamespaces.p &&
                child.localName == 'ext' &&
                child.getAttribute('uri')?.toUpperCase() == extensionUri,
          )
          .toList() ??
      <XmlElement>[];

  static List<XmlElement> _descendants(
    XmlElement root,
    String name,
    String uri,
  ) => [
    for (final XmlElement child in root.childElements) ...[
      if (child.localName == name && child.namespaceUri == uri) child,
      ..._descendants(child, name, uri),
    ],
  ];
}
