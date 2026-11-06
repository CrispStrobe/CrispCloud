// lib/widgets/xml_tree_view.dart
//
// Collapsible XML tree for the F3 viewer. Malformed XML falls back to an
// error message (the source view remains available).

import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../l10n/xml_view_strings.dart';

class XmlTreeView extends StatelessWidget {
  final String xml;
  final double fontSize;

  const XmlTreeView({
    super.key,
    required this.xml,
    this.fontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    XmlDocument document;
    try {
      document = XmlDocument.parse(xml);
    } catch (e) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            XmlViewStrings(context).parseError(e),
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final builder = _XmlTreeBuilder(theme, fontSize);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      children: [
        for (final node in document.children) builder.build(node, 0),
        if (builder.limitReached)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              XmlViewStrings(context).text('truncated'),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _XmlTreeBuilder {
  static const int _maxNodes = 5000;

  final ThemeData theme;
  final double fontSize;
  int _nodes = 0;

  _XmlTreeBuilder(this.theme, this.fontSize);

  bool get limitReached => _nodes >= _maxNodes;

  TextStyle get _base => TextStyle(
        fontFamily: 'AppMono',
        fontFamilyFallback: const ['Menlo', 'Consolas', 'monospace'],
        fontSize: fontSize,
        height: 1.35,
        color: theme.colorScheme.onSurface,
      );

  Widget build(XmlNode node, int depth) {
    if (_nodes >= _maxNodes) return const SizedBox.shrink();
    if (node is XmlElement) return _element(node, depth);
    if (node is XmlText) {
      final text = node.value.trim();
      if (text.isEmpty) return const SizedBox.shrink();
      _nodes++;
      return Padding(
        padding: EdgeInsets.only(left: 12.0 + depth * 12, top: 1, bottom: 1),
        child: SelectableText(
          text,
          style: _base.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    if (node is XmlComment) {
      _nodes++;
      return Padding(
        padding: EdgeInsets.only(left: 12.0 + depth * 12, top: 1, bottom: 1),
        child: SelectableText(
          '<!--${node.value}-->',
          style: _base.copyWith(color: theme.colorScheme.outline),
        ),
      );
    }
    if (node is XmlCDATA) {
      _nodes++;
      return Padding(
        padding: EdgeInsets.only(left: 12.0 + depth * 12, top: 1, bottom: 1),
        child: SelectableText(
          '<![CDATA[${node.value}]]>',
          style: _base.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _element(XmlElement element, int depth) {
    _nodes++;
    final relevantChildren = element.children
        .where((child) =>
            child is XmlElement ||
            child is XmlComment ||
            child is XmlCDATA ||
            (child is XmlText && child.value.trim().isNotEmpty))
        .toList();

    final title = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '<${element.name}',
            style: _base.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final attribute in element.attributes)
            TextSpan(
              children: [
                TextSpan(
                  text: ' ${attribute.name}',
                  style: _base.copyWith(color: theme.colorScheme.tertiary),
                ),
                TextSpan(
                  text: '="${attribute.value}"',
                  style: _base.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          TextSpan(
            text: relevantChildren.isEmpty ? ' />' : '>',
            style: _base.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      style: _base,
    );

    if (relevantChildren.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: 8.0 + depth * 12, top: 1, bottom: 1),
        child: title,
      );
    }

    return Padding(
      padding: EdgeInsets.only(left: depth * 8.0),
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.only(left: 8),
        initiallyExpanded: depth < 2,
        title: title,
        children: [
          for (final child in relevantChildren) build(child, depth + 1),
        ],
      ),
    );
  }
}
