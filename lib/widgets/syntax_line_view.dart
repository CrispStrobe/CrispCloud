import 'package:flutter/material.dart';

import '../services/syntax_highlight_theme.dart';

import '../services/syntax_line_highlighting.dart';
import 'internal_viewer_views.dart';

/// Keeps scrolling/search geometry identical to the plain virtualized viewer.
class SyntaxLineView extends StatefulWidget {
  const SyntaxLineView({
    super.key,
    required this.text,
    required this.language,
    required this.lines,
    required this.fontScale,
    this.controller,
    this.activeMatchLine,
    this.activeMatchLocal,
  });
  final String text;
  final String language;
  final List<String> lines;
  final double fontScale;
  final ScrollController? controller;
  final int? activeMatchLine;
  final (int, int)? activeMatchLocal;

  @override
  State<SyntaxLineView> createState() => _SyntaxLineViewState();
}

class _SyntaxLineViewState extends State<SyntaxLineView> {
  List<List<SyntaxRun>> _lines = const [];
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant SyntaxLineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.language != widget.language)
      _parse();
  }

  Future<void> _parse() async {
    final request = ++_request;
    _lines = const [];
    try {
      final lines = await highlightSourceLines(widget.text, widget.language);
      if (mounted && request == _request) setState(() => _lines = lines);
    } catch (_) {
      // Lexing never blocks viewing/searching the original source text.
    }
  }

  InlineSpan _span(int index, String text, TextStyle matchStyle) {
    final theme = syntaxHighlightTheme(
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    final tokens = index < _lines.length
        ? _lines[index]
        : <SyntaxRun>[(text: text, scopes: const [])];
    final match = index == widget.activeMatchLine
        ? widget.activeMatchLocal
        : null;
    var offset = 0;
    final children = <InlineSpan>[];
    for (final token in tokens) {
      var style = const TextStyle();
      for (final scope in token.scopes) {
        style = style.merge(theme[scope] ?? theme[scope.split('.').first]);
      }
      final end = offset + token.text.length;
      final startMatch = match == null ? end : match.$1.clamp(offset, end);
      final endMatch = match == null ? end : match.$2.clamp(offset, end);
      if (startMatch > offset)
        children.add(
          TextSpan(
            text: token.text.substring(0, startMatch - offset),
            style: style,
          ),
        );
      if (endMatch > startMatch)
        children.add(
          TextSpan(
            text: token.text.substring(startMatch - offset, endMatch - offset),
            style: style.merge(matchStyle),
          ),
        );
      if (endMatch < end)
        children.add(
          TextSpan(text: token.text.substring(endMatch - offset), style: style),
        );
      offset = end;
    }
    return TextSpan(children: children);
  }

  @override
  Widget build(BuildContext context) => MonoLineListView(
    lines: widget.lines,
    fontScale: widget.fontScale,
    controller: widget.controller,
    activeMatchLine: widget.activeMatchLine,
    activeMatchLocal: widget.activeMatchLocal,
    lineSpanBuilder: _span,
  );
}
