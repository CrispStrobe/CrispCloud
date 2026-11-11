import '../../opc/package_part.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../model/wml_document.dart';
import '../model/word_notes.dart';

/// Materializes pending list restarts without changing editable paragraph IDs.
abstract final class WordNumberingIo {
  static Map<WmlParagraph, int> prepareRestarts(
    WmlDocument document,
    PackagePart part,
  ) {
    final result = Map<WmlParagraph, int>.identity();
    final stories = <List<WmlParagraph>>[
      document.paragraphs.toList(),
      for (final WmlSection section in document.sections) ...[
        section.header,
        section.footer,
        section.firstHeader,
        section.firstFooter,
        section.evenHeader,
        section.evenFooter,
      ],
      for (final WmlNote note in [...document.footnotes, ...document.endnotes])
        note.allParagraphs.toList(),
      for (final WmlComment comment in document.comments) comment.paragraphs,
    ];
    if (!stories
        .expand((story) => story)
        .any((paragraph) => paragraph.properties.listRestart != null)) {
      return result;
    }
    final xml = XmlDocument.parse(part.readText());
    final root = xml.root!;
    final instances = <int, XmlElement>{
      for (final node in root.childrenNamed('num'))
        if (int.tryParse(node.getAttribute('numId') ?? '') case final int id)
          id: node,
    };
    final definitions = <int, XmlElement>{
      for (final node in root.childrenNamed('abstractNum'))
        if (int.tryParse(node.getAttribute('abstractNumId') ?? '')
            case final int id)
          id: node,
    };
    final referenced = <int>{
      for (final paragraph in stories.expand((story) => story))
        if (paragraph.properties.numId case final int id) id,
      for (final style in document.styles)
        if (style.numId case final int id) id,
    };
    final claimed = <int>{};
    var changed = false;
    var nextId = 1;

    int start(XmlElement instance, int level) {
      final override = instance
          .childrenNamed('lvlOverride')
          .where((node) => node.getAttribute('ilvl') == '$level')
          .firstOrNull;
      final explicit = int.tryParse(
        override?.firstChild('startOverride')?.getAttribute('val') ?? '',
      );
      if (explicit != null) return explicit;
      final abstractId = int.tryParse(
        instance.firstChild('abstractNumId')?.getAttribute('val') ?? '',
      );
      final definition =
          override?.firstChild('lvl') ??
          definitions[abstractId]
              ?.childrenNamed('lvl')
              .where((node) => node.getAttribute('ilvl') == '$level')
              .firstOrNull;
      return int.tryParse(
            definition?.firstChild('start')?.getAttribute('val') ?? '',
          ) ??
          1;
    }

    for (final story in stories) {
      final active = <int, int>{};
      final counters = <int, List<int?>>{};
      for (final paragraph in story) {
        final properties = paragraph.properties;
        final original = properties.numId;
        if (original == null || original == 0) continue;
        var instance = instances[active[original] ?? original];
        if (instance == null) {
          if (properties.listRestart != null) {
            throw StateError(
              'Cannot restart undefined numbering instance $original',
            );
          }
          continue;
        }
        final level = properties.ilvl.clamp(0, 8);
        final stack = counters.putIfAbsent(
          original,
          () => List<int?>.filled(9, null),
        );
        final restart = properties.listRestart;
        if (restart != null) {
          final template = instance.copy()..removeAttribute('numId');
          template.setAttribute('w', OfficeNamespaces.w, prefix: 'xmlns');
          // A fresh numbering instance also needs its existing ancestor counts
          // or restarting level 2 under item 3 would incorrectly yield 1.5.
          for (var ancestor = 0; ancestor < level; ancestor++) {
            _setStart(
              template,
              ancestor,
              stack[ancestor] ?? start(instance, ancestor),
            );
          }
          _setStart(template, level, restart);
          final signature = _signature(template);
          int? id;
          for (final candidate in instances.entries) {
            if (!referenced.contains(candidate.key) &&
                !claimed.contains(candidate.key) &&
                _signature(candidate.value) == signature) {
              id = candidate.key;
              break;
            }
          }
          if (id == null) {
            while (instances.containsKey(nextId) ||
                referenced.contains(nextId)) {
              nextId++;
            }
            id = nextId++;
            template.setAttribute(
              'numId',
              '$id',
              prefix: 'w',
              namespaceUri: OfficeNamespaces.w,
            );
            final cleanup = root.children.indexWhere(
              (node) =>
                  node is XmlElement && node.localName == 'numIdMacAtCleanup',
            );
            if (cleanup < 0) {
              root.addChild(template);
            } else {
              root.children.insert(cleanup, template..parent = root);
            }
            instances[id] = template;
            changed = true;
          }
          claimed.add(id);
          active[original] = id;
          instance = instances[id]!;
        }
        stack[level] =
            restart ??
            (stack[level] == null ? start(instance, level) : stack[level]! + 1);
        for (var ancestor = 0; ancestor < level; ancestor++) {
          stack[ancestor] ??= start(instance, ancestor);
        }
        for (var deeper = level + 1; deeper < stack.length; deeper++) {
          stack[deeper] = null;
        }
        if (active[original] case final int id) result[paragraph] = id;
      }
    }
    if (changed) part.writeText(xml.toXmlString());
    return result;
  }

  static String _signature(XmlElement instance) => XmlDocument(
    root: instance.copy()..removeAttribute('numId'),
  ).toXmlString(declaration: false);

  static void _setStart(XmlElement instance, int level, int value) {
    var override = instance
        .childrenNamed('lvlOverride')
        .where((node) => node.getAttribute('ilvl') == '$level')
        .firstOrNull;
    if (override == null) {
      override =
          XmlElement(
            localName: 'lvlOverride',
            prefix: 'w',
            namespaceUri: OfficeNamespaces.w,
          )..setAttribute(
            'ilvl',
            '$level',
            prefix: 'w',
            namespaceUri: OfficeNamespaces.w,
          );
      instance.addChild(override);
    }
    override.setAttribute('w', OfficeNamespaces.w, prefix: 'xmlns');
    var start = override.firstChild('startOverride');
    if (start == null) {
      start = XmlElement(
        localName: 'startOverride',
        prefix: 'w',
        namespaceUri: OfficeNamespaces.w,
      );
      override.children.insert(0, start..parent = override);
    }
    start.setAttribute('w', OfficeNamespaces.w, prefix: 'xmlns');
    start.setAttribute(
      'val',
      '$value',
      prefix: 'w',
      namespaceUri: OfficeNamespaces.w,
    );
  }
}
