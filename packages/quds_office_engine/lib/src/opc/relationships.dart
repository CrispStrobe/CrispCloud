import '../xml/namespaces.dart';
import '../xml/xml_reader.dart';
import '../xml/xml_writer.dart';
import 'package_part.dart';

/// Internal vs. external relationship target (ECMA-376 Part 2 §9.3).
enum RelationshipTargetMode { internal, external }

/// One `<Relationship>` row.
class PackageRelationship {
  /// PackageRelationship API.
  PackageRelationship({
    required this.id,
    required this.type,
    required this.target,
    this.targetMode = RelationshipTargetMode.internal,
  });

  /// id API.
  final String id;

  /// type API.
  final String type;

  /// target API.
  final String target;

  /// targetMode API.
  final RelationshipTargetMode targetMode;

  /// copyWith API.
  PackageRelationship copyWith({
    String? id,
    String? type,
    String? target,
    RelationshipTargetMode? targetMode,
  }) {
    return PackageRelationship(
      id: id ?? this.id,
      type: type ?? this.type,
      target: target ?? this.target,
      targetMode: targetMode ?? this.targetMode,
    );
  }
}

/// `.rels` collection with a monotonic `rId` allocator.
class RelationshipCollection {
  /// RelationshipCollection API.
  RelationshipCollection({
    required this.sourcePartUri,
    List<PackageRelationship>? items,
  }) : _items = items ?? <PackageRelationship>[];

  /// sourcePartUri API.
  final String sourcePartUri;
  final List<PackageRelationship> _items;
  int _nextId = 1;

  /// items API.
  List<PackageRelationship> get items =>
      List<PackageRelationship>.unmodifiable(_items);

  /// isNotEmpty API.
  bool get isNotEmpty => _items.isNotEmpty;

  /// isEmpty API.
  bool get isEmpty => _items.isEmpty;

  /// length API.
  int get length => _items.length;

  /// parse API.
  factory RelationshipCollection.parse(String xml, String sourcePartUri) {
    final RelationshipCollection collection = RelationshipCollection(
      sourcePartUri: OpcUris.normalize(sourcePartUri),
    );
    final XmlPullReader reader = XmlPullReader(xml);
    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement ||
          reader.localName != 'Relationship') {
        continue;
      }
      final String? id = reader.getAttribute('Id');
      final String? type = reader.getAttribute('Type');
      final String? target = reader.getAttribute('Target');
      if (id == null || type == null || target == null) {
        continue;
      }
      final String? mode = reader.getAttribute('TargetMode');
      collection._items.add(
        PackageRelationship(
          id: id,
          type: type,
          target: target,
          targetMode: mode != null && mode.toLowerCase() == 'external'
              ? RelationshipTargetMode.external
              : RelationshipTargetMode.internal,
        ),
      );
    }
    collection._nextId = collection._computeNextId();
    return collection;
  }

  /// allocateId API.
  String allocateId() {
    while (_hasId('rId$_nextId')) {
      _nextId++;
    }
    final String id = 'rId$_nextId';
    _nextId++;
    return id;
  }

  /// add API.
  PackageRelationship add({
    required String type,
    required String target,
    String? id,
    RelationshipTargetMode targetMode = RelationshipTargetMode.internal,
  }) {
    final String rid = id ?? allocateId();
    if (_hasId(rid)) {
      throw StateError('Relationship id $rid already exists');
    }
    final PackageRelationship rel = PackageRelationship(
      id: rid,
      type: type,
      target: target,
      targetMode: targetMode,
    );
    _items.add(rel);
    return rel;
  }

  /// removeById API.
  bool removeById(String id) {
    final int index = _items.indexWhere((PackageRelationship r) => r.id == id);
    if (index < 0) {
      return false;
    }
    _items.removeAt(index);
    return true;
  }

  /// byId API.
  PackageRelationship? byId(String id) {
    for (final PackageRelationship rel in _items) {
      if (rel.id == id) {
        return rel;
      }
    }
    return null;
  }

  /// firstByType API.
  PackageRelationship? firstByType(String type) {
    for (final PackageRelationship rel in _items) {
      if (rel.type == type) {
        return rel;
      }
    }
    return null;
  }

  /// byType API.
  Iterable<PackageRelationship> byType(String type) {
    return _items.where((PackageRelationship r) => r.type == type);
  }

  /// Resolves an internal target against [sourcePartUri].
  String resolve(PackageRelationship relationship) {
    if (relationship.targetMode == RelationshipTargetMode.external) {
      return relationship.target;
    }
    return OpcUris.resolve(sourcePartUri, relationship.target);
  }

  /// toXml API.
  String toXml() {
    final XmlWriter writer = XmlWriter();
    writer.writeStartDocument();
    writer.writeStartElement(
      'Relationships',
      namespaceUri: OfficeNamespaces.relationships,
    );
    for (final PackageRelationship rel in _items) {
      writer.writeStartElement('Relationship');
      writer.writeAttribute('Id', rel.id);
      writer.writeAttribute('Type', rel.type);
      writer.writeAttribute('Target', rel.target);
      if (rel.targetMode == RelationshipTargetMode.external) {
        writer.writeAttribute('TargetMode', 'External');
      }
      writer.writeEndElement();
    }
    writer.writeEndElement();
    return writer.toXml();
  }

  bool _hasId(String id) {
    for (final PackageRelationship rel in _items) {
      if (rel.id == id) {
        return true;
      }
    }
    return false;
  }

  int _computeNextId() {
    int max = 0;
    final RegExp pattern = RegExp(r'^rId(\d+)$');
    for (final PackageRelationship rel in _items) {
      final Match? match = pattern.firstMatch(rel.id);
      if (match == null) {
        continue;
      }
      final int value = int.parse(match.group(1)!);
      if (value > max) {
        max = value;
      }
    }
    return max + 1;
  }
}
