part of 'slide_serial.dart';

abstract final class _SlideSourceXml {
  // Preserve unsupported native slide elements and relationships around
  // modeled edits. The generated base describes which fields an edit owns.
  static String update(
    String original,
    PmlSlideSource base,
    PmlSlideSource current,
    String generated,
  ) {
    final document = XmlDocument.parse(original);
    final native = document.root!;
    final previous = XmlDocument.parse(base.modeledXml).root!;
    final modeled = XmlDocument.parse(current.modeledXml).root!;
    final output = XmlDocument.parse(generated).root!;
    for (final attr in output.attributes.where((a) => a.prefix == 'xmlns')) {
      native.setAttribute(attr.localName, attr.value, prefix: 'xmlns');
    }
    if (native.getAttribute('Ignorable', namespaceUri: OfficeNamespaces.mc)
        case final String existing) {
      if (!existing.split(RegExp(r'\s+')).contains('p14')) {
        native.setAttribute(
          'Ignorable',
          '$existing p14',
          prefix: 'mc',
          namespaceUri: OfficeNamespaces.mc,
        );
      }
    } else {
      native.setAttribute(
        'Ignorable',
        'p14',
        prefix: 'mc',
        namespaceUri: OfficeNamespaces.mc,
      );
    }
    for (final name in ['show', 'showMasterSp']) {
      if (previous.getAttribute(name) == modeled.getAttribute(name)) continue;
      final value = output.getAttribute(name);
      if (value == null) {
        native.removeAttribute(name);
      } else {
        native.setAttribute(name, value);
      }
    }
    XmlElement? common(XmlElement e) =>
        e.firstChild('cSld', namespaceUri: OfficeNamespaces.p);
    final nativeContent = common(native);
    final previousContent = common(previous)!;
    final modeledContent = common(modeled)!;
    final outputContent = common(output)!;
    if (nativeContent == null) return generated;
    if (!_sameNode(
      previousContent.firstChild('bg'),
      modeledContent.firstChild('bg'),
    )) {
      _replaceElement(
        nativeContent,
        'bg',
        outputContent.firstChild('bg'),
        first: true,
      );
    }
    final nativeTree = nativeContent.firstChild('spTree');
    final outputTree = outputContent.firstChild('spTree')!;
    if (nativeTree != null) {
      _updateShapeTree(
        nativeTree,
        previousContent.firstChild('spTree')!,
        modeledContent.firstChild('spTree')!,
        outputTree,
        base,
        current,
      );
    }
    for (final name in ['transition', 'timing']) {
      if (!_sameNode(previous.firstChild(name), modeled.firstChild(name))) {
        _replaceElement(native, name, output.firstChild(name));
      }
    }
    return document.toXmlString();
  }

  static String? _nodeXml(XmlElement? element) => element == null
      ? null
      : XmlDocument(root: element).toXmlString(declaration: false);

  static bool _sameNode(XmlElement? a, XmlElement? b) =>
      _nodeXml(a) == _nodeXml(b);

  static void _replaceElement(
    XmlElement parent,
    String name,
    XmlElement? next, {
    bool first = false,
    String namespace = OfficeNamespaces.p,
  }) {
    final old = parent.firstChild(name, namespaceUri: namespace);
    final end = parent.firstChild('extLst', namespaceUri: OfficeNamespaces.p);
    final index = old != null
        ? parent.children.indexOf(old)
        : first
        ? 0
        : end == null
        ? parent.children.length
        : parent.children.indexOf(end);
    if (old != null) parent.children.removeAt(index);
    if (next != null) {
      parent.children.insert(index, next.copy()..parent = parent);
    }
  }

  static int? _shapeId(XmlElement node) {
    if (node.namespaceUri != OfficeNamespaces.p ||
        !const {
          'sp',
          'pic',
          'cxnSp',
          'graphicFrame',
        }.contains(node.localName)) {
      return null;
    }
    return int.tryParse(
      node.childElements.firstOrNull
              ?.firstChild('cNvPr', namespaceUri: OfficeNamespaces.p)
              ?.getAttribute('id') ??
          '',
    );
  }

  static XmlElement _mergeNativeShape(
    XmlElement native,
    XmlElement before,
    XmlElement after,
    XmlElement output,
    bool sameVisual,
  ) {
    final connector = native.localName == 'cxnSp' && after.localName == 'sp';
    if (before.localName != after.localName ||
        native.localName != after.localName && !connector) {
      return output.copy();
    }
    final result = native.copy();
    final names = {
      for (final node in before.childElements) node.localName,
      for (final node in after.childElements) node.localName,
    };
    for (final name in names) {
      final previous = before.firstChild(name);
      final current = after.firstChild(name);
      if (_sameNode(previous, current) &&
          (sameVisual || name != 'blipFill' && name != 'graphic')) {
        continue;
      }
      final next = output.firstChild(name);
      if (connector && name == 'nvSpPr') {
        final newMeta = next?.firstChild('cNvPr');
        final oldMeta = previous?.firstChild('cNvPr');
        final nativeMeta = result.firstChild('nvCxnSpPr')?.firstChild('cNvPr');
        if (newMeta != null && oldMeta != null && nativeMeta != null) {
          for (final attribute in ['name', 'descr']) {
            final value = newMeta.getAttribute(attribute);
            if (oldMeta.getAttribute(attribute) == value) continue;
            if (value == null) {
              nativeMeta.removeAttribute(attribute);
            } else {
              nativeMeta.setAttribute(attribute, value);
            }
          }
        }
        continue;
      }
      final nativeFill = result.firstChild('blipFill');
      if (name == 'blipFill' &&
          sameVisual &&
          previous != null &&
          current != null &&
          next != null &&
          nativeFill != null) {
        final changed = {
          for (final child in previous.childElements) child.localName,
          for (final child in current.childElements) child.localName,
        };
        for (final field in changed) {
          if (_sameNode(previous.firstChild(field), current.firstChild(field))) {
            continue;
          }
          final child = next.firstChild(field);
          _replaceElement(
            nativeFill,
            field,
            child,
            namespace: OfficeNamespaces.a,
            first: field == 'blip',
          );
        }
        continue;
      }
      if (name == 'spPr' &&
          previous != null &&
          current != null &&
          next != null) {
        final nativeProps = result.firstChild('spPr');
        if (nativeProps != null) {
          _mergeShapeProperties(nativeProps, previous, current, next, native);
          continue;
        }
      }
      _replaceElement(
        result,
        name,
        next,
        namespace:
            next?.namespaceUri ??
            previous?.namespaceUri ??
            current?.namespaceUri ??
            OfficeNamespaces.p,
      );
    }
    return result;
  }

  static void _mergeShapeProperties(
    XmlElement native,
    XmlElement before,
    XmlElement after,
    XmlElement output,
    XmlElement sourceShape,
  ) {
    const families = [
      {'xfrm'},
      {'prstGeom', 'custGeom'},
      {'noFill', 'solidFill', 'gradFill', 'blipFill', 'pattFill', 'grpFill'},
      {'ln'},
    ];
    for (final (index, names) in families.indexed) {
      XmlElement? first(XmlElement parent) => parent.childElements
          .where((node) => names.contains(node.localName))
          .firstOrNull;
      if (_sameNode(first(before), first(after))) continue;
      final old = first(native);
      var next = first(output);
      if (index == 0 && old != null && next != null && first(before) != null) {
        next = _groupLocalTransform(sourceShape, old, first(before)!, next);
      }
      final insertion = native.childElements
          .where(
            (node) => !families
                .take(index + 1)
                .any((family) => family.contains(node.localName)),
          )
          .firstOrNull;
      final at = old != null
          ? native.children.indexOf(old)
          : insertion == null
          ? native.children.length
          : native.children.indexOf(insertion);
      if (old != null) native.children.removeAt(at);
      if (next != null) {
        native.children.insert(at, next.copy()..parent = native);
      }
    }
  }

  // Imported group children are edited in slide coordinates. Keep the source
  // group transform and convert the edit's deltas back into its local space.
  static XmlElement _groupLocalTransform(
    XmlElement shape,
    XmlElement source,
    XmlElement previous,
    XmlElement edited,
  ) {
    final groups = <XmlElement>[];
    for (
      var parent = shape.parent;
      parent != null && parent.localName == 'grpSp';
      parent = parent.parent
    ) {
      final transform = parent.firstChild('grpSpPr')?.firstChild('xfrm');
      if (transform != null) groups.add(transform);
    }
    if (groups.isEmpty) return edited;

    double value(XmlElement? node, String key) =>
        double.tryParse(node?.getAttribute(key) ?? '') ?? 0;
    bool flag(XmlElement node, String key) =>
        const {'1', 'true'}.contains(node.getAttribute(key));
    (double, double) inverse(double x, double y) {
      for (final group in groups.reversed) {
        final width = value(group.firstChild('ext'), 'cx');
        final height = value(group.firstChild('ext'), 'cy');
        final childWidth = value(group.firstChild('chExt'), 'cx');
        final childHeight = value(group.firstChild('chExt'), 'cy');
        if (width <= 0 || height <= 0 || childWidth <= 0 || childHeight <= 0) {
          continue;
        }
        final angle = value(group, 'rot') * math.pi / 10800000;
        final cos = math.cos(angle), sin = math.sin(angle);
        final movedX = (x * cos + y * sin) * childWidth / width;
        final movedY = (-x * sin + y * cos) * childHeight / height;
        x = flag(group, 'flipH') ? -movedX : movedX;
        y = flag(group, 'flipV') ? -movedY : movedY;
      }
      return (x, y);
    }

    final sourceSize = source.firstChild('ext');
    final sourceOffset = source.firstChild('off');
    if (sourceSize == null || sourceOffset == null) return edited;
    final beforeSize = previous.firstChild('ext');
    final afterSize = edited.firstChild('ext');
    final beforeOffset = previous.firstChild('off');
    final afterOffset = edited.firstChild('off');
    double change(String axis, String extent) =>
        value(afterOffset, axis) -
        value(beforeOffset, axis) +
        (value(afterSize, extent) - value(beforeSize, extent)) / 2;
    double size(String axis) {
      final before = value(beforeSize, axis);
      final after = value(afterSize, axis);
      final native = value(sourceSize, axis);
      return before == 0 ? native + after : native * after / before;
    }

    final (dx, dy) = inverse(change('x', 'cx'), change('y', 'cy'));
    final result = source.copy();
    final localOffset = result.firstChild('off')!;
    final localSize = result.firstChild('ext')!;
    for (final (axis, extent, delta) in [('x', 'cx', dx), ('y', 'cy', dy)]) {
      final length = size(extent).round();
      final offset =
          value(sourceOffset, axis) +
          delta +
          (value(sourceSize, extent) - length) / 2;
      localSize.setAttribute(extent, '$length');
      localOffset.setAttribute(axis, '${offset.round()}');
    }
    final initialAngle = value(previous, 'rot');
    final finalAngle = value(edited, 'rot');
    if (initialAngle != finalAngle) {
      double localAngle(double rotation) {
        final angle = rotation * math.pi / 10800000;
        final (x, y) = inverse(math.cos(angle), math.sin(angle));
        return math.atan2(y, x) * 10800000 / math.pi;
      }

      final rotation =
          value(source, 'rot') +
          localAngle(finalAngle) -
          localAngle(initialAngle);
      result.setAttribute('rot', '${rotation.round() % 21600000}');
    }
    for (final flip in ['flipH', 'flipV']) {
      if (flag(previous, flip) != flag(edited, flip)) {
        result.setAttribute(flip, flag(source, flip) ? '0' : '1');
      }
    }
    return result;
  }

  static Map<int, XmlElement> _shapeNodes(XmlElement tree) => {
    for (final node in tree.childElements)
      if (_shapeId(node) case final int id)
        id: node
      else if (node.localName == 'grpSp')
        ..._shapeNodes(node),
  };

  static void _updateShapeTree(
    XmlElement native,
    XmlElement previous,
    XmlElement modeled,
    XmlElement output,
    PmlSlideSource base,
    PmlSlideSource current,
  ) {
    final sourceShapes = _shapeNodes(native);
    final oldShapes = _shapeNodes(previous);
    final editedShapes = _shapeNodes(modeled);
    final newShapes = _shapeNodes(output);
    final oldGroups = Map<int, int?>.fromEntries(
      base.shapeOrder.map((shape) => MapEntry(shape.$1, shape.$2)),
    );
    final newGroups = Map<int, int?>.fromEntries(
      current.shapeOrder.map((shape) => MapEntry(shape.$1, shape.$2)),
    );
    final affected = <int, XmlElement>{};
    for (final entry in newShapes.entries) {
      final id = entry.key;
      final source = sourceShapes[id];
      final old = oldShapes[id];
      final edited = editedShapes[id];
      final sameVisual = base.visuals[id] == current.visuals[id];
      affected[id] = source == null || old == null || edited == null
          ? entry.value.copy()
          : _sameNode(old, edited) && sameVisual
          ? source
          : _mergeNativeShape(source, old, edited, entry.value, sameVisual);
    }
    final oldOrder = base.shapeOrder
        .where((shape) => newGroups.containsKey(shape.$1))
        .toList();
    final newOrder = current.shapeOrder
        .where((shape) => oldGroups.containsKey(shape.$1))
        .toList();
    final stable =
        oldOrder.length == newOrder.length &&
        Iterable<int>.generate(
          oldOrder.length,
        ).every((i) => oldOrder[i] == newOrder[i]);
    if (!stable ||
        current.shapeOrder.any(
          (shape) => !oldGroups.containsKey(shape.$1) && shape.$2 != null,
        )) {
      // Grouping or z-order changed. Build the new modeled order while
      // retaining unchanged native shapes and unmodeled top-level XML.
      for (final node in sourceShapes.values) {
        node.parent?.children.remove(node);
      }
      native.children.removeWhere(
        (node) =>
            node is XmlElement &&
            node.localName == 'grpSp' &&
            _shapeNodes(node).isEmpty &&
            !node.childElements.any(
              (child) =>
                  child.localName == 'grpSp' ||
                  !const {'nvGrpSpPr', 'grpSpPr'}.contains(child.localName),
            ),
      );
      void append(XmlElement from, XmlElement to) {
        for (final node in from.childElements) {
          if (_shapeId(node) case final int id) {
            to.addChild(affected[id]!);
          } else if (node.localName == 'grpSp') {
            final group = node.copy();
            group.children.removeWhere(
              (child) =>
                  child is XmlElement &&
                  (_shapeId(child) != null || child.localName == 'grpSp'),
            );
            append(node, group);
            to.addChild(group);
          }
        }
      }

      final tail = native.firstChild('extLst');
      if (tail != null) native.children.remove(tail);
      append(output, native);
      if (tail != null) native.addChild(tail);
      return;
    }
    for (final entry in sourceShapes.entries) {
      if (!oldGroups.containsKey(entry.key)) continue;
      final parent = entry.value.parent!;
      final index = parent.children.indexOf(entry.value);
      final replacement = affected[entry.key];
      if (replacement == null) {
        parent.children.removeAt(index);
      } else if (!identical(replacement, entry.value)) {
        parent.children[index] = replacement..parent = parent;
      }
    }
    for (final (id, _) in current.shapeOrder) {
      if (sourceShapes.containsKey(id) || affected[id] == null) continue;
      final ext = native.firstChild('extLst');
      final index = ext == null
          ? native.children.length
          : native.children.indexOf(ext);
      native.children.insert(index, affected[id]!..parent = native);
    }
  }
}
