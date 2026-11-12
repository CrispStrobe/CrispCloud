import 'package:flutter/foundation.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

/// A bounded, background lexer for virtualized source views. A complete parse
/// retains multiline comment/string state; the UI only paints visible lines.
const int kVirtualSyntaxMaxChars = 8 * 1024 * 1024;
typedef SyntaxRun = ({String text, List<String> scopes});

Future<List<List<SyntaxRun>>> highlightSourceLines(
  String text,
  String language,
) => compute(parseSourceLines, (text: text, language: language));

List<List<SyntaxRun>> parseSourceLines(({String text, String language}) input) {
  if (input.text.length > kVirtualSyntaxMaxChars) return const [];
  if (input.text.split('\n').any((line) => line.length > 512 * 1024))
    return const [];
  final mode = builtinAllLanguages[input.language];
  if (mode == null) return const [];
  final lexer = Highlight()..registerLanguage(input.language, mode);
  final renderer = _LineRenderer();
  for (final result in lexer.highlightChunks(
    code: input.text,
    language: input.language,
  )) {
    result.render(renderer);
  }
  return renderer.lines;
}

class _LineRenderer implements HighlightRenderer {
  final lines = <List<SyntaxRun>>[[]];
  final _scopes = <String>[];

  @override
  void addText(String text) {
    final parts = text.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) lines.add([]);
      if (parts[i].isNotEmpty) {
        lines.last.add((text: parts[i], scopes: List.of(_scopes)));
      }
    }
  }

  @override
  void openNode(DataNode node) => _scopes.add(node.scope ?? '');

  @override
  void closeNode(DataNode node) {
    if (_scopes.isNotEmpty) _scopes.removeLast();
  }
}
